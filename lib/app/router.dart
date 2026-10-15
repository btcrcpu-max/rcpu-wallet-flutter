import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/bridge/bridge_page.dart';
import '../features/home/home_page.dart';
import '../features/receive/receive_page.dart';
import '../features/scan/scan_page.dart';
import '../features/settings/settings_page.dart';
import '../features/wallet/wallet_init_page.dart';
import '../features/wallet/wallet_state.dart';

/// 应用路由。
///
/// 路由清单（按文档第 3 章 feature-first 划分）：
/// - `/`          首页（总资产 + 收款/付款/跨链入口）
/// - `/wallet`    钱包初始化（创建/导入助记词）
/// - `/receive`   收款页
/// - `/scan`      扫码付款页
/// - `/bridge`    跨链页（铸造/赎回）
/// - `/settings`  设置页
///
/// 启动时若钱包已初始化则直进首页，否则先走 `/wallet`。
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/wallet',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/wallet',
        name: 'wallet',
        builder: (context, state) => const WalletInitPage(),
      ),
      GoRoute(
        path: '/receive',
        name: 'receive',
        builder: (context, state) => const ReceivePage(),
      ),
      GoRoute(
        path: '/scan',
        name: 'scan',
        builder: (context, state) => const ScanPage(),
      ),
      GoRoute(
        path: '/bridge',
        name: 'bridge',
        builder: (context, state) => const BridgePage(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
});