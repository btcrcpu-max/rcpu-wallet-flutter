import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/balance.dart';
import '../receive/receive_page.dart';
import '../send/send_page.dart';
import '../settings/settings_page.dart';
import '../wallet/wallet_state.dart';

/// 首页：总资产卡片 + 资产列表 + 底部导航。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tabIndex = 0;

  void _switchTab(int index) => setState(() => _tabIndex = index);

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletStateProvider);
    final pages = <Widget>[
      wallet.isReady
          ? _HomeTab(wallet: wallet, onQuickAction: _switchTab)
          : _InitGuide(onCreate: () => context.go('/wallet')),
      const _ReceiveTabRouter(),
      const _PayTabRouter(),
      const _SettingsTabRouter(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: _switchTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.qr_code_outlined), selectedIcon: Icon(Icons.qr_code), label: '收款'),
          NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: '付款'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

/// 首页核心内容。
class _HomeTab extends StatelessWidget {
  final WalletState wallet;
  final ValueChanged<int> onQuickAction;
  const _HomeTab({required this.wallet, required this.onQuickAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 16),
          // 总资产卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('总资产', style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(wallet.totalBalanceDisplay,
                          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text('RCPU', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('≈ 联调后获取实时价格', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 资产列表
          _AssetCard(
            icon: Icons.account_balance_wallet,
            iconColor: colorScheme.primary,
            assetName: 'RCPU',
            subtitle: '原生资产',
            balance: wallet.balanceOf('native') ?? Balance.zero('native'),
          ),
          _AssetCard(
            icon: Icons.currency_exchange,
            iconColor: colorScheme.tertiary,
            assetName: 'wRCPU',
            subtitle: 'BSC 包装资产',
            balance: wallet.balanceOf('wrcpu') ?? Balance.zero('wrcpu'),
          ),
          const SizedBox(height: 24),
          // 快速操作
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onQuickAction(1), // 收款
                  icon: const Icon(Icons.qr_code),
                  label: const Text('收款'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onQuickAction(2), // 付款
                  icon: const Icon(Icons.send),
                  label: const Text('付款'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => onQuickAction(3), // 设置
              icon: const Icon(Icons.settings),
              label: const Text('设置 / 网络'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 钱包未初始化引导（未创建/导入钱包时首页展示）。
class _InitGuide extends StatelessWidget {
  final VoidCallback onCreate;
  const _InitGuide({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('尚未创建钱包', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('创建或导入钱包后即可收发 RCPU / wRCPU',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('创建 / 导入钱包'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 资产列表卡片。
class _AssetCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String assetName;
  final String subtitle;
  final Balance balance;

  const _AssetCard({
    required this.icon,
    required this.iconColor,
    required this.assetName,
    required this.subtitle,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withAlpha(31),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(assetName, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: Text(balance.raw, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// 收款页路由包装（底部导航切换时走内部路由）。
class _ReceiveTabRouter extends StatelessWidget {
  const _ReceiveTabRouter();
  @override
  Widget build(BuildContext context) => const ReceivePage();
}

/// 付款页路由包装。
class _PayTabRouter extends StatelessWidget {
  const _PayTabRouter();
  @override
  Widget build(BuildContext context) => const SendPage();
}

/// 设置页路由包装。
class _SettingsTabRouter extends StatelessWidget {
  const _SettingsTabRouter();
  @override
  Widget build(BuildContext context) => const SettingsPage();
}
