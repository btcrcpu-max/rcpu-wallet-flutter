import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/models/balance.dart';
import '../native/node_sync.dart';
import '../payment/tx_tracker.dart';
import '../receive/receive_page.dart';
import '../send/send_page.dart';
import '../settings/settings_page.dart';
import '../wallet/wallet_state.dart';
import 'pending_tx_card.dart';

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
    final s = ref.watch(appStringsProvider);
    // 区块高度推进时自动刷新余额（新块可能包含本地址入账）。
    ref.listen<NodeSyncStatus>(nodeSyncProvider, (prev, next) {
      if (next.connected &&
          next.height != null &&
          next.height != prev?.height) {
        ref.read(walletStateProvider.notifier).refreshBalances();
        // 同步刷新待确认交易的确认数。
        ref
            .read(txTrackerProvider.notifier)
            .refresh(ref.read(walletStateProvider).addresses?.plain.value);
      }
    });
    // 钱包就绪后立即拉取一次待确认交易（含历史入账）。
    ref.listen<WalletState>(walletStateProvider, (prev, next) {
      if (next.isReady && prev?.isReady != true) {
        ref.read(txTrackerProvider.notifier).refresh(next.addresses?.plain.value);
      }
    });
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
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.navHome),
          NavigationDestination(icon: const Icon(Icons.qr_code_outlined), selectedIcon: const Icon(Icons.qr_code), label: s.navReceive),
          NavigationDestination(icon: const Icon(Icons.send_outlined), selectedIcon: const Icon(Icons.send), label: s.navSend),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: s.navSettings),
        ],
      ),
    );
  }
}

/// 首页核心内容。
class _HomeTab extends ConsumerWidget {
  final WalletState wallet;
  final ValueChanged<int> onQuickAction;
  const _HomeTab({required this.wallet, required this.onQuickAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = ref.watch(appStringsProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(walletStateProvider.notifier).refreshBalances(),
            ref.read(nodeSyncProvider.notifier).refresh(),
          ]);
        },
        child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 8),
          // 顶部栏：标题 + 节点同步状态（右上角小区块高度显示）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.appTitle, style: theme.textTheme.titleLarge),
              const _SyncChip(),
            ],
          ),
          const SizedBox(height: 8),
          // 总资产卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.totalAssets, style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(wallet.totalBalanceDisplay,
                              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('RCPU', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(s.pricePending, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 待确认交易（收/付款确认数，6 确认后自动消失）
          const PendingTxCard(),
          const SizedBox(height: 12),
          // 资产列表
          _AssetCard(
            icon: Icons.account_balance_wallet,
            iconColor: colorScheme.primary,
            assetName: 'RCPU',
            subtitle: s.nativeAsset,
            balance: wallet.balanceOf('native') ?? Balance.zero('native'),
          ),
          _AssetCard(
            icon: Icons.currency_exchange,
            iconColor: colorScheme.tertiary,
            assetName: 'wRCPU',
            subtitle: s.wrappedAsset,
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
                  label: Text(s.receive),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onQuickAction(2), // 付款
                  icon: const Icon(Icons.send),
                  label: Text(s.send),
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
              label: Text(s.settingsNetwork),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// 钱包未初始化引导（未创建/导入钱包时首页展示）。
class _InitGuide extends ConsumerWidget {
  final VoidCallback onCreate;
  const _InitGuide({required this.onCreate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(appStringsProvider);
    final lang = ref.watch(languageSelectionProvider);
    final langLabel = switch (lang) {
      AppLanguage.system => s.langSystem,
      AppLanguage.zh => s.langZh,
      AppLanguage.en => s.langEn,
    };
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: TextButton.icon(
                onPressed: () => _pickLanguage(context, ref),
                icon: const Icon(Icons.language, size: 20),
                label: Text(langLabel),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet, size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(s.noWallet, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(s.noWalletHint,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add),
                      label: Text(s.createImportWallet),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 语言选择弹窗（与设置页同一逻辑）。
  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final s = ref.read(appStringsProvider);
    final current = ref.read(languageSelectionProvider);
    final picked = await showDialog<AppLanguage>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.language),
        children: [
          for (final opt in [
            (AppLanguage.system, s.langSystem),
            (AppLanguage.zh, s.langZh),
            (AppLanguage.en, s.langEn),
          ])
            ListTile(
              title: Text(opt.$2),
              trailing: current == opt.$1 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, opt.$1),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(languageSelectionProvider.notifier).setLanguage(picked);
    }
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withAlpha(31),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(assetName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(balance.raw,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
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

/// 节点同步状态小标（首页右上角）。
///
/// 已连接：绿点 + 当前区块高度；未连接：红点 + 「节点未连接」。
/// 点击弹出详情（端点 / 高度 / 错误原因 / 更新时间），并可手动重连。
class _SyncChip extends ConsumerWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(nodeSyncProvider);
    final s = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    final color =
        sync.connected ? Colors.green : theme.colorScheme.error;
    final label = sync.connected
        ? (sync.height != null ? s.heightLabel(sync.height!) : s.connected)
        : s.nodeDisconnected;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showDetail(context, ref, sync),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, NodeSyncStatus sync) {
    final s = ref.read(appStringsProvider);
    final updated = sync.updatedAt;
    final updatedText = updated == null
        ? '—'
        : '${updated.hour.toString().padLeft(2, '0')}:'
            '${updated.minute.toString().padLeft(2, '0')}:'
            '${updated.second.toString().padLeft(2, '0')}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(sync.connected ? s.nodeConnected : s.nodeDisconnected),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.endpointLabel}: https://wallet.rcpuapp.top/rpc'),
            Text('${s.blockHeight}: ${sync.height ?? '—'}'),
            Text('${s.updatedAt}: $updatedText'),
            if (!sync.connected && sync.error != null) ...[
              const SizedBox(height: 8),
              Text(
                '${s.reasonLabel}: ${sync.error}',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          if (!sync.connected)
            TextButton(
              onPressed: () {
                ref.read(nodeSyncProvider.notifier).refresh();
                Navigator.of(ctx).pop();
              },
              child: Text(s.retry),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }
}
