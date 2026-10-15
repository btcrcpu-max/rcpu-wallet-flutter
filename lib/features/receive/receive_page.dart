import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/address.dart';
import '../wallet/wallet_state.dart';

/// 收款页：地址展示 + 二维码生成。
class ReceivePage extends ConsumerStatefulWidget {
  const ReceivePage({super.key});

  @override
  ConsumerState<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends ConsumerState<ReceivePage> {
  bool _isPrivate = true;
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletStateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!wallet.isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('收款')),
        body: const Center(child: Text('钱包未初始化')),
      );
    }

    final addr = _isPrivate ? wallet.addresses!.private : wallet.addresses!.plain;
    final uri = _buildUri(addr, _amountController.text);

    return Scaffold(
      appBar: AppBar(title: const Text('收款')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('明文 rcpu1')),
                ButtonSegment(value: true, label: Text('隐私 rcpux1')),
              ],
              selected: {_isPrivate},
              onSelectionChanged: (s) => setState(() => _isPrivate = s.first),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: uri,
                  size: 220,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: SelectableText(
                  addr.toString(),
                  style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
                ),
                subtitle: Text(_isPrivate ? '隐私地址（推荐收款）' : '明文地址（仅限桥存款）'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: addr.toString()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('地址已复制')),
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '金额（可选）',
                suffixText: 'RCPU',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              '支付协议: $uri',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _buildUri(Address addr, String amount) {
    final base = 'rcpu:${addr.toString()}';
    final a = amount.trim();
    if (a.isNotEmpty) return '$base?amount=$a';
    return base;
  }
}
