import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/address.dart';
import '../../core/utils/amount.dart';
import '../wallet/wallet_state.dart';

/// 付款/发送页：输入收款地址与金额，选择资产类型后确认。
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

    setState(() => _loading = true);

    // TODO: 接入签名广播（Phase 2/3）
    await Future.delayed(const Duration(seconds: 1));

    setState(() => _loading = false);
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('支付确认'),
          content: Text('向 $address 发送 $amount ${_asset == 'native' ? 'RCPU' : 'wRCPU'}\n\n（实际转账功能开发中，此版本仅作 UI 演示）'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = ref.watch(walletStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('付款')),
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
