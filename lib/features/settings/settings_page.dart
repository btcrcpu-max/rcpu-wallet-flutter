import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wallet/wallet_state.dart';

/// 设置页。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          if (wallet.isReady && wallet.addresses != null) ...[
            _SettingsSection(title: '地址管理', children: [
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('明文地址'),
                subtitle: Text(wallet.addresses!.plain.toString()),
                trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () {}),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off),
                title: const Text('隐私地址'),
                subtitle: Text(wallet.addresses!.private.toString()),
                trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () {}),
              ),
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: const Text('BSC 地址'),
                subtitle: Text(wallet.addresses!.bsc.toString()),
                trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () {}),
              ),
            ]),
          ],
          _SettingsSection(title: '安全', children: [
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('生物识别'),
              trailing: Switch(value: false, onChanged: (v) {}),
            ),
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('导出助记词'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: 生物识别验证后展示
              },
            ),
          ]),
          const _SettingsSection(title: '网络', children: [
            ListTile(
              leading: Icon(Icons.network_check),
              title: Text('RPC 节点'),
              subtitle: Text('原生: http://207.57.129.188/rpc | BSC: 公共节点'),
              trailing: Icon(Icons.chevron_right),
            ),
          ]),
          const _SettingsSection(title: '关于', children: [
            ListTile(
              leading: Icon(Icons.info),
              title: Text('版本'),
              subtitle: Text('v0.1.0+1'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}
