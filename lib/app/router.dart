import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_page.dart';

/// 应用路由。
///
/// 路由清单（按文档第 3 章 feature-first 划分）：
/// - `/`          首页（总资产 + 收款/付款/跨链入口）
/// - `/wallet`    钱包初始化（创建/导入助记词、解锁）
/// - `/receive`   收款页（由底部导航直接嵌入，不通过独立路由进入）
/// - `/scan`      扫码付款页
/// - `/bridge`    跨链页（铸造/赎回）
/// - `/settings`  设置页
///
/// 守卫待接入：锁屏状态与钱包未初始化时重定向至 `/wallet`。
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/wallet',
        name: 'wallet',
        builder: (context, state) => const _SkeletonPage(title: '钱包'),
      ),
      GoRoute(
        path: '/scan',
        name: 'scan',
        builder: (context, state) => const _SkeletonPage(title: '扫码付款'),
      ),
      GoRoute(
        path: '/bridge',
        name: 'bridge',
        builder: (context, state) => const _SkeletonPage(title: '跨链'),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const _SkeletonPage(title: '设置'),
      ),
    ],
  );
});

/// 骨架期占位页面，保留 /wallet /scan /bridge /settings 的友好占位。
class _SkeletonPage extends StatelessWidget {
  final String title;
  const _SkeletonPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('$title（开发中）', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}