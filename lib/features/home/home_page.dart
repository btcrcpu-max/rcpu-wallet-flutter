import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/models/address.dart';
import '../../../core/models/balance.dart';
import '../wallet_state.dart';

/// 首页：总资产卡片 + 资产列表 + 底部导航。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletStateProvider);
    final pages = <Widget>[
      _HomeTab(wallet: wallet),
      const _ReceiveTabRouter(),
      const _ScanTabRouter(),
      const _BridgeTabRouter(),
      const _SettingsTabRouter(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.qr_code_outlined), selectedIcon: Icon(Icons.qr_code), label: '收款'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner_outlined), selectedIcon: Icon(Icons.qr_code_scanner), label: '扫码'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: '跨链'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

/// 首页核心内容。
class _HomeTab extends StatelessWidget {
  final WalletState wallet;
  const _HomeTab({required this.wallet});

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
                  onPressed: () => context.go('/receive'),
                  icon: const Icon(Icons.qr_code),
                  label: const Text('收款'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.go('/scan'),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('付款'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/bridge'),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('跨链（铸造 / 赎回）'),
            ),
          ),
        ],
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
          backgroundColor: iconColor.withOpacity(0.12),
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

/// 收款页：地址展示 + 二维码。
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
      return const _SkeletonPage(title: '收款', body: _CenteredMessage('钱包未初始化，请先创建或导入钱包'));
    }

    final addr = _isPrivate ? wallet.addresses!.private : wallet.addresses!.plain;
    final uri = _buildUri(addr, _amountController.text);

    return Scaffold(
      appBar: AppBar(title: const Text('收款')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 地址类型切换
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('明文 rcpu1')),
                ButtonSegment(value: true, label: Text('隐私 rcpux1')),
              ],
              selected: {_isPrivate},
              onSelectionChanged: (s) => setState(() => _isPrivate = s.first),
            ),
            const SizedBox(height: 20),
            // 二维码
            Center(
              child: QrImageView(
                data: uri,
                size: 220,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            // 地址
            Card(
              child: ListTile(
                title: SelectableText(addr.toString(),
                    style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace')),
                subtitle: Text(_isPrivate ? '隐私地址（推荐）' : '明文地址（仅限桥存款）'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    // 后续接入 Clipboard
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 金额输入
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
              '扫码协议: $uri',
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

/// 扫码页路由包装。
class _ScanTabRouter extends StatelessWidget {
  const _ScanTabRouter();
  @override
  Widget build(BuildContext context) => const _SkeletonPage(
        title: '扫码付款',
        body: _CenteredMessage('扫码付款功能联调中'),
      );
}

/// 跨链页路由包装。
class _BridgeTabRouter extends StatelessWidget {
  const _BridgeTabRouter();
  @override
  Widget build(BuildContext context) => const _SkeletonPage(
        title: '跨链',
        body: _CenteredMessage('铸造 / 赎回功能联调中'),
      );
}

/// 设置页路由包装。
class _SettingsTabRouter extends StatelessWidget {
  const _SettingsTabRouter();
  @override
  Widget build(BuildContext context) => const _SkeletonPage(
        title: '设置',
        body: _CenteredMessage('设置功能开发中'),
      );
}

/// 统一骨架页（标题 + 内容）。
class _SkeletonPage extends StatelessWidget {
  final String title;
  final Widget body;
  const _SkeletonPage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: body),
    );
  }
}

/// 居中信息展示。
class _CenteredMessage extends StatelessWidget {
  final String text;
  const _CenteredMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
