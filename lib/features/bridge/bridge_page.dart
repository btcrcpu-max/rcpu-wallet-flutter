import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wallet/wallet_service.dart';
import '../wallet/wallet_state.dart';

/// 跨链页：铸造 / 赎回。
class BridgePage extends ConsumerWidget {
  const BridgePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletStateProvider);
    final theme = Theme.of(context);

    if (!wallet.isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('跨链')),
        body: const Center(child: Text('钱包未初始化')),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('跨链桥'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.arrow_downward), text: '铸造'),
              Tab(icon: Icon(Icons.arrow_upward), text: '赎回'),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('铸造 wRCPU', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('1. 向桥专属地址存入原生 RCPU（明文地址）', style: theme.textTheme.bodyMedium),
                Text('2. 累计满 10 RCPU 后自动铸造 wRCPU 到 BSC 地址', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                SelectableText(
                  '专属存款地址: ${addresses.plain.toString()}',
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
          child: const Text('复制专属存款地址'),
        ),
        const SizedBox(height: 8),
        Text(
          '铸造进度: 0 / 10 RCPU（联调后获取实时进度）',
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('赎回 RCPU', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('1. 在 BSC 上燃烧 wRCPU', style: theme.textTheme.bodyMedium),
                Text('2. 指定收款地址为原生钱包地址', style: theme.textTheme.bodyMedium),
                Text('3. 桥处理完成后 RCPU 直接到账', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Text('收款地址: ${addresses.plain.toString()}', style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '赎回数量',
            suffixText: 'wRCPU',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            // TODO: 桥联调后接入
          },
          child: const Text('确认赎回'),
        ),
      ],
    );
  }
}
