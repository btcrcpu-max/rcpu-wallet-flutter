import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../wallet/wallet_service.dart';
import '../wallet/wallet_state.dart';

/// 跨链页：铸造 / 赎回。
class BridgePage extends ConsumerWidget {
  const BridgePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletStateProvider);
    final s = ref.watch(appStringsProvider);

    if (!wallet.isReady) {
      return Scaffold(
        appBar: AppBar(title: Text(s.bridgeTitle)),
        body: Center(child: Text(s.walletNotInit)),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.bridgeTitle),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.arrow_downward), text: s.mint),
              Tab(icon: const Icon(Icons.arrow_upward), text: s.redeem),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DepositTab(addresses: wallet.addresses!),
            _RedeemTab(addresses: wallet.addresses!),
          ],
        ),
      ),
    );
  }
}

class _DepositTab extends StatelessWidget {
  final DerivedAddresses addresses;
  const _DepositTab({required this.addresses});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.current;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.mintWrcpu, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(s.mintStep1, style: theme.textTheme.bodyMedium),
                Text(s.mintStep2, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                SelectableText(
                  s.depositAddress(addresses.plain.toString()),
                  style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            // TODO: 桥联调后接入
          },
          child: Text(s.copyDepositAddress),
        ),
        const SizedBox(height: 8),
        Text(
          s.mintProgress,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _RedeemTab extends StatelessWidget {
  final DerivedAddresses addresses;
  const _RedeemTab({required this.addresses});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.current;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.redeemRcpu, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(s.redeemStep1, style: theme.textTheme.bodyMedium),
                Text(s.redeemStep2, style: theme.textTheme.bodyMedium),
                Text(s.redeemStep3, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Text(s.receiveAddress(addresses.plain.toString()), style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: s.redeemAmount,
            suffixText: 'wRCPU',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            // TODO: 桥联调后接入
          },
          child: Text(s.confirmRedeem),
        ),
      ],
    );
  }
}
