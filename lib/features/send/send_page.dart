import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di.dart';
import '../../core/crypto/derivation.dart';
import '../../core/models/address.dart';
import '../../core/utils/amount.dart';
import '../payment/payment_service.dart';
import '../wallet/wallet_state.dart';
import 'scan_page.dart';

/// 付款/发送页：输入（或扫描）收款地址与金额，确认后签名广播。
///
/// 原生 RCPU：走 [PaymentService.confirmAndPay] 完整链路
/// （指纹确认 → UTXO 选择 → P2TR 输入构造 → BIP340 签名 → 广播）；
/// 隐私收款（rcpux1）本地无 CT 盲化能力，fail-closed 提示；
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

  @override
  void dispose() {
    _addressCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  /// 扫码：`rcpu:` 收款 URI 回填地址/金额/资产；裸地址仅回填地址。
  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (raw == null || raw.isEmpty) return;
    if (!mounted) return;
    final text = raw.trim();
    if (text.startsWith('rcpu:')) {
      try {
        final payment = PaymentService.parseAndValidate(text);
        setState(() {
          _addressCtrl.text = payment.address;
          if (payment.amount != null) _amountCtrl.text = payment.amount!;
          _asset = payment.resolvedAsset;
          _error = null;
        });
      } catch (e) {
        setState(() => _error = '二维码无效: $e');
      }
      return;
    }
    setState(() {
      _addressCtrl.text = text;
      _error = null;
    });
  }

  Future<void> _confirm() async {
    setState(() => _error = null);

    final address = _addressCtrl.text.trim();
    final amount = _amountCtrl.text.trim();

    if (address.isEmpty || amount.isEmpty) {
      setState(() => _error = '请填写地址和金额');
      return;
    }

    // 地址校验
    try {
      final addr = Address.parse(address);
      if (_asset == 'native' && !addr.isNative) {
        setState(() => _error = '原生资产收款地址须为 rcpu1 / rcpux1 开头');
        return;
      }
      if (_asset == 'wrcpu' && !addr.isEvm) {
        setState(() => _error = 'wRCPU 收款地址须为 0x 开头');
        return;
      }
    } catch (e) {
      setState(() => _error = '地址格式错误: $e');
      return;
    }

    // 金额校验
    if (!Amount.isValid(amount)) {
      setState(() => _error = '金额格式非法');
      return;
    }
    if (amount == '0') {
      setState(() => _error = '金额不能为 0');
      return;
    }

    // wRCPU 转账链路（BSC 合约调用）尚未接入，如实提示而非伪造成功。
    if (_asset == 'wrcpu') {
      setState(() => _error = 'wRCPU 转账功能尚未开放，当前仅支持原生 RCPU');
      return;
    }

    setState(() => _loading = true);

    String? failure;
    PaymentResult? result;
    try {
      final wallet = ref.read(walletStateProvider);
      final addresses = wallet.addresses;
      if (addresses == null) {
        failure = '钱包未解锁';
      } else {
        final mnemonic = await ref.read(secureStoreProvider).readMnemonic();
        if (mnemonic == null) {
          failure = '钱包未初始化';
        } else {
          // 明文路径花费私钥（m/84'/1'/0'/0/0），与 plain 地址对应。
          final privKeyHex = Derivation(mnemonic)
              .deriveNativePlainKey()
              .spendPriv
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          result = await ref.read(paymentServiceProvider).confirmAndPay(
                toAddress: address,
                amountMicro: Amount.toMicro(amount),
                privateKeyHex: privKeyHex,
                assetType: _asset,
                fromAddress: addresses.plain.value,
              );
        }
      }
    } catch (e) {
      failure = '支付失败: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted || result == null) {
      if (mounted && failure != null) setState(() => _error = failure);
      return;
    }

    if (result.ok) {
      final txid = result.txid;
      _addressCtrl.clear();
      _amountCtrl.clear();
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('支付成功'),
          content: SelectableText('交易 ID：$txid'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('付款'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: '扫码付款',
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
                labelText: '收款地址',
                hintText: _asset == 'native' ? 'rcpu1... 或 rcpux1...' : '0x...',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: '扫码',
                  onPressed: _loading ? null : _scan,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 金额
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '金额',
                suffixText: _asset == 'native' ? 'RCPU' : 'wRCPU',
                prefixIcon: const Icon(Icons.payments_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // 余额提示
            if (wallet.isReady)
              Text(
                '可用余额: ${(wallet.balanceOf(_asset)?.raw ?? '0.00000000')} ${_asset == 'native' ? 'RCPU' : 'wRCPU'}',
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
                label: const Text('确认付款'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
