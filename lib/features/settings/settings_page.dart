import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../wallet/wallet_state.dart';

/// 设置页。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _bioEnabled = false;
  bool _bioLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBioState();
  }

  Future<void> _loadBioState() async {
    final bio = ref.read(biometricAuthProvider);
    final available = await bio.isAvailable();
    final hasEnrolled = await bio.hasEnrolledBiometrics();
    final enabled = await bio.isEnabled();
    if (mounted) {
      setState(() {
        _bioEnabled = enabled;
      });
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前设备不支持生物识别')),
        );
      } else if (!hasEnrolled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('系统未录入指纹/人脸，请先在系统设置中添加')),
        );
      }
    }
  }

  Future<void> _toggleBio(bool value) async {
    final bio = ref.read(biometricAuthProvider);
    if (value) {
      // 先检测设备支持情况
      final available = await bio.isAvailable();
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前设备不支持生物识别')),
          );
        }
        return;
      }
      final hasEnrolled = await bio.hasEnrolledBiometrics();
      if (!hasEnrolled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('系统未录入指纹/人脸，请先在系统设置中添加')),
          );
        }
        return;
      }

      setState(() => _bioLoading = true);
      final ok = await bio.authenticate(reason: '开启生物识别以解锁钱包');
      setState(() => _bioLoading = false);
      if (ok) {
        await bio.setEnabled(true);
        if (mounted) setState(() => _bioEnabled = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生物识别验证失败')),
        );
      }
    } else {
      await bio.setEnabled(false);
      if (mounted) setState(() => _bioEnabled = false);
    }
  }

  /// 复制文本到剪贴板并提示（带 mounted 保护）。
  Future<void> _copyAddress(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label已复制')),
    );
  }

  Future<void> _exportMnemonic() async {
    final bio = ref.read(biometricAuthProvider);
    if (_bioEnabled) {
      final ok = await bio.authenticate(reason: '验证身份以导出助记词');
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('生物识别验证失败')),
          );
        }
        return;
      }
    }

    final store = ref.read(secureStoreProvider);
    final mnemonic = await store.readMnemonic();
    if (!mounted) return;

    if (mnemonic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到钱包数据')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: mnemonic));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('助记词已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                subtitle: SelectableText(wallet.addresses!.plain.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyAddress(
                    wallet.addresses!.plain.toString(),
                    '明文地址',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off),
                title: const Text('隐私地址'),
                subtitle: SelectableText(wallet.addresses!.private.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyAddress(
                    wallet.addresses!.private.toString(),
                    '隐私地址',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: const Text('BSC 地址'),
                subtitle: SelectableText(wallet.addresses!.bsc.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyAddress(
                    wallet.addresses!.bsc.toString(),
                    'BSC 地址',
                  ),
                ),
              ),
            ]),
          ],
          _SettingsSection(title: '安全', children: [
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('生物识别'),
              trailing: _bioLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(value: _bioEnabled, onChanged: _toggleBio),
            ),
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('导出助记词'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportMnemonic,
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
              subtitle: Text('v0.3.2'),
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
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}
