import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di.dart';
import '../../core/crypto/derivation.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/address.dart';
import '../../core/utils/amount.dart';
import '../payment/payment_service.dart';
import '../payment/tx_tracker.dart';
import '../wallet/wallet_state.dart';
import 'scan_page.dart';

/// 付款/发送页：输入（或扫描）收款地址与金额，确认后签名广播。
///
/// 原生 RCPU：走 [PaymentService.confirmAndPay] 完整链路
/// （指纹确认 → UTXO 选择 → 交易构造 → 签名 → 广播）；
/// - 明文收款（`rcpu1`）本地构造 + BIP143/BIP341 签名；
/// - 隐私收款（`rcpux1`）经 CT 协处理器盲化输出 + 本地签名（私钥不出设备）；
/// wRCPU 转账（BSC 合约调用）尚未接入，如实提示。
class SendPage extends ConsumerStatefulWidget {
  const SendPage({super.key});

  @override
  ConsumerState<SendPage> createState() => _SendPageState();
}

class _SendPageState extends ConsumerState<SendPage> {
  final _addressCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _asset = 'native';
  bool _loading = false;
  String? _error;

  /// 「最大付款」模式：金额由 [estimateMaxSendableMicro] 回填，
  /// 广播时手续费从付款金额中扣除；用户手动改金额后自动退出该模式。
  bool _isMax = false;

  /// 程序化回填金额时置位，避免被文本侦听误判为手动编辑。
  bool _programmatic = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() {
      if (!_programmatic && _isMax) setState(() => _isMax = false);
    });
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  /// 最大付款：估算全部可用 UTXO − 手续费后回填金额。
  Future<void> _fillMax() async {
    final s = ref.read(appStringsProvider);
    final from = ref.read(walletStateProvider).addresses?.plain.value;
    if (from == null) {
      setState(() => _error = s.walletLocked);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final maxMicro =
          await ref.read(paymentServiceProvider).estimateMaxSendableMicro(from);
      if (!mounted) return;
      setState(() {
        if (maxMicro <= 0) {
          _isMax = false;
          _error = s.insufficientWithFee;
        } else {
          _programmatic = true;
          _amountCtrl.text = Amount.fromMicro(maxMicro);
          _programmatic = false;
          _isMax = true;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = s.paymentFailed('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 扫码：`rcpu:` 收款 URI 回填地址/金额/资产；裸地址仅回填地址。
  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (raw == null || raw.isEmpty) return;
    if (!mounted) return;
    final text = raw.trim();
    if (text.toLowerCase().startsWith('rcpu:')) {
      try {
        final payment = PaymentService.parseAndValidate(text);
        setState(() {
          _addressCtrl.text = payment.address;
          if (payment.amount != null) _amountCtrl.text = payment.amount!;
          _asset = payment.resolvedAsset;
          _error = null;
        });
      } catch (e) {
        setState(() => _error = AppStrings.current.invalidQr('$e'));
      }
      return;
    }
    // 裸地址：bech32 统一小写回填（QT 二维码输出全大写）。
    final filled = text.startsWith('0x') ? text : text.toLowerCase();
    setState(() {
      _addressCtrl.text = filled;
      // 按地址前缀自动切换资产类型，避免用户停留在 wRCPU
      // 档扫入原生地址造成校验误报。
      if (filled.startsWith('0x')) {
        _asset = 'wrcpu';
      } else {
        _asset = 'native';
      }
      _error = null;
    });
  }

  Future<void> _confirm() async {
    setState(() => _error = null);
    final s = ref.read(appStringsProvider);

    final address = _addressCtrl.text.trim();
    final amount = _amountCtrl.text.trim();

    if (address.isEmpty || amount.isEmpty) {
      setState(() => _error = s.fillAddressAmount);
      return;
    }

    // 地址校验
    try {
      final addr = Address.parse(address);
      if (_asset == 'native' && !addr.isNative) {
        setState(() => _error = s.nativeAddrPrefix);
        return;
      }
      if (_asset == 'wrcpu' && !addr.isEvm) {
        setState(() => _error = s.wrcpuAddrPrefix);
        return;
      }
    } catch (e) {
      setState(() => _error = s.addressInvalid('$e'));
      return;
    }

    // 金额校验
    if (!Amount.isValid(amount)) {
      setState(() => _error = s.amountInvalid);
      return;
    }
    if (amount == '0') {
      setState(() => _error = s.amountZero);
      return;
    }

    // wRCPU 转账链路（BSC 合约调用）尚未接入，如实提示而非伪造成功。
    if (_asset == 'wrcpu') {
      setState(() => _error = s.wrcpuNotOpen);
      return;
    }

    setState(() => _loading = true);

    String? failure;
    PaymentResult? result;
    try {
      final wallet = ref.read(walletStateProvider);
      final addresses = wallet.addresses;
      if (addresses == null) {
        failure = s.walletLocked;
      } else {
        final mnemonic = await ref.read(secureStoreProvider).readMnemonic();
        if (mnemonic == null) {
          failure = s.walletNotInit;
        } else {
          // 明文路径花费私钥（m/84'/1'/0'/0/0），与 plain 地址对应；
          // 隐私路径私钥（m/84'/1'/0'/1/0）供 CT 收款盲化/找零与自身 CT 输出解盲。
          final d = Derivation(mnemonic);
          final privKeyHex = d
              .deriveNativePlainKey()
              .spendPriv
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final ctPrivHex = d
              .deriveNativePrivateKey()
              .spendPriv
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          result = await ref.read(paymentServiceProvider).confirmAndPay(
                toAddress: address,
                amountMicro: Amount.toMicro(amount),
                privateKeyHex: privKeyHex,
                assetType: _asset,
                fromAddress: addresses.plain.value,
                ctPrivateKeyHex: ctPrivHex,
                privateAddress: addresses.private.value,
                subtractFeeFromAmount: _isMax,
              );
        }
      }
    } catch (e) {
      failure = s.paymentFailed('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted || result == null) {
      if (mounted && failure != null) setState(() => _error = failure);
      return;
    }

    if (result.ok) {
      final txid = result.txid;
      // 登记待确认交易（首页/收款页展示确认数，6 确认后消失）。
      final fromAddr =
          ref.read(walletStateProvider).addresses?.plain.value ?? '';
      ref.read(txTrackerProvider.notifier).recordOutgoing(
            txid: '$txid',
            amount: amount,
            address: fromAddr,
          );
      _addressCtrl.clear();
      _amountCtrl.clear();
      setState(() => _isMax = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.paymentSuccess),
          content: SelectableText(s.txIdLabel('$txid')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.ok),
            ),
          ],
        ),
      );
    } else {
      final err = result.error;
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = ref.watch(walletStateProvider);
    final s = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.navSend),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: s.scanPayTooltip,
            onPressed: _loading ? null : _scan,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 资产选择
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'native', label: Text('RCPU')),
                ButtonSegment(value: 'wrcpu', label: Text('wRCPU')),
              ],
              selected: {_asset},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) setState(() => _asset = set.first);
              },
            ),
            const SizedBox(height: 16),
            // 收款地址
            TextField(
              controller: _addressCtrl,
              decoration: InputDecoration(
                labelText: s.recipientAddress,
                hintText: _asset == 'native' ? s.nativeAddrHint : '0x...',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: s.scanTooltip,
                  onPressed: _loading ? null : _scan,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 金额（原生资产支持 MAX：手续费从付款金额中扣除）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: s.amount,
                      suffixText: _asset == 'native' ? 'RCPU' : 'wRCPU',
                      prefixIcon: const Icon(Icons.payments_outlined),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_asset == 'native')
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: OutlinedButton(
                      onPressed: _loading ? null : _fillMax,
                      child: Text(s.maxLabel),
                    ),
                  ),
              ],
            ),
            if (_isMax)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  s.maxFeeHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            const SizedBox(height: 16),
            // 余额提示
            if (wallet.isReady)
              Text(
                s.availableBalance(
                  wallet.balanceOf(_asset)?.raw ?? '0.00000000',
                  _asset == 'native' ? 'RCPU' : 'wRCPU',
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            const SizedBox(height: 24),
            // 错误提示
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            // 确认按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _confirm,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(s.confirmSend),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

