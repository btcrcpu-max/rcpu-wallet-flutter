import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../payment/payment_service.dart';
import '../wallet/wallet_state.dart';

/// 扫码付款页。
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletStateProvider);
    final theme = Theme.of(context);

    if (!wallet.isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('扫码付款')),
        body: const Center(child: Text('钱包未初始化')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('扫码付款')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('扫一扫'),
                subtitle: const Text('扫描收款方二维码'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: 接入 mobile_scanner
                },
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text('手动输入', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: '收款地址',
                hintText: 'rcpu1... 或 rcpux1...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '金额',
                suffixText: 'RCPU',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitPayment,
              icon: const Icon(Icons.send),
              label: const Text('确认付款'),
            ),
          ],
        ),
      ),
    );
  }

  void _submitPayment() {
    final addr = _addressController.text.trim();
    final amount = _amountController.text.trim();
    if (addr.isEmpty || amount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写地址和金额')),
      );
      return;
    }

    // 复用 PaymentService 的协议校验（类型判定 + 金额合法性）。
    String? error;
    try {
      PaymentService.parseAndValidate('rcpu:$addr?amount=$amount');
    } catch (e) {
      error = e.toString().replaceFirst('FormatException: ', '');
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('付款确认'),
        content: Text('向 $addr 支付 $amount RCPU\n\n（RPC 联调后接入真实签名广播）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('交易已提交（联调中）')),
              );
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}
