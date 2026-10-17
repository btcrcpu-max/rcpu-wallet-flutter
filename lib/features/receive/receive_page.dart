import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/address.dart';
import '../home/pending_tx_card.dart';
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
    final s = ref.watch(appStringsProvider);

    if (!wallet.isReady) {
      return Scaffold(
        appBar: AppBar(title: Text(s.navReceive)),
        body: Center(child: Text(s.walletNotInit)),
      );
    }

    final addr = _isPrivate ? wallet.addresses!.private : wallet.addresses!.plain;
    final uri = _buildUri(addr, _amountController.text);

    return Scaffold(
      appBar: AppBar(title: Text(s.navReceive)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(s.plainSeg)),
                ButtonSegment(value: true, label: Text(s.privateSeg)),
              ],
              selected: {_isPrivate},
              onSelectionChanged: (v) => setState(() => _isPrivate = v.first),
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
                subtitle: Text(_isPrivate ? s.privateAddrHint : s.plainAddrHint),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: addr.toString()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.addressCopied)),
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
              decoration: InputDecoration(
                labelText: s.amountOptional,
                suffixText: 'RCPU',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              '${s.paymentProtocol}: $uri',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // 收款确认数（达到 6 确认后自动消失）
            const PendingTxCard(),
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

