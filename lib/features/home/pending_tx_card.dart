import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../payment/tx_tracker.dart';

/// 待确认交易卡片：收/付款未达 6 确认的记录（达到后自动消失）。
///
/// 首页与收款页共用；无待确认记录时不占位。
class PendingTxCard extends ConsumerWidget {
  const PendingTxCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(txTrackerProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = ref.watch(appStringsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.pendingTxTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final t in pending)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      t.direction == 'out'
                          ? Icons.north_east
                          : Icons.south_west,
                      size: 16,
                      color: t.direction == 'out'
                          ? colorScheme.error
                          : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${t.direction == 'out' ? s.txOutLabel : s.txInLabel}'
                        ' ${t.amount} RCPU',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.confLabel(t.confirmations),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
