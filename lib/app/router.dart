import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 应用路由。
///
/// 路由清单（按文档第 3 章 feature-first 划分）：
/// - `/`          首页（总资产 + 收款/付款/跨链入口）
/// - `/wallet`    钱包初始化（创建/导入助记词、解锁）
/// - `/receive`   收款页
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
        builder: (context, state) => const _PlaceholderPage(title: '首页'),
      ),
      GoRoute(
        path: '/wallet',
        name: 'wallet',
        builder: (context, state) => const _PlaceholderPage(title: '钱包'),
      ),
      GoRoute(
        path: '/receive',
        name: 'receive',
        builder: (context, state) => const _PlaceholderPage(title: '收款'),
      ),
      GoRoute(
        path: '/scan',
        name: 'scan',
        builder: (context, state) => const _PlaceholderPage(title: '扫码付款'),
      ),
      GoRoute(
        path: '/bridge',
        name: 'bridge',
        builder: (context, state) => const _PlaceholderPage(title: '跨链'),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const _PlaceholderPage(title: '设置'),
      ),
    ],
  );
});

/// 骨架期占位页面，后续由各 feature 页面替换。
class _PlaceholderPage extends StatelessWidget {
  final String title;
  const _PlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title（待实现）')),
    );
  }
}