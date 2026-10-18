import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/di.dart';
import '../../core/l10n/app_strings.dart';
import '../wallet/wallet_state.dart';

/// 包信息只取一次（fromPlatform 走 platform channel，避免重复调用）。
/// 版本号直接读 pubspec.yaml，发版时无需再改界面代码。
Future<PackageInfo>? _packageInfoFuture;

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
    final enabled = await bio.isEnabled();
    if (mounted) {
      setState(() {
        _bioEnabled = enabled;
      });
    }
  }

  Future<void> _toggleBio(bool value) async {
    final bio = ref.read(biometricAuthProvider);
    final s = ref.read(appStringsProvider);
    if (value) {
      // 直接发起系统验证：canCheckBiometrics / getAvailableBiometrics 在
      // 部分机型上误报（付款指纹可用的机器上返回不支持/未录入），导致
      // 开关永远无法开启。authenticate 与付款同一通路，设备不支持时会
      // 快速失败并提示。
      setState(() => _bioLoading = true);
      final ok = await bio.authenticate(reason: s.bioEnableReason);
      setState(() => _bioLoading = false);
      if (ok) {
        await bio.setEnabled(true);
        if (mounted) setState(() => _bioEnabled = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.bioFailed)),
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
    final s = ref.read(appStringsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.copiedLabel(label))),
    );
  }

  Future<void> _exportMnemonic() async {
    final bio = ref.read(biometricAuthProvider);
    final s = ref.read(appStringsProvider);
    // 备份必须验证身份（指纹/人脸或设备锁屏密码），
    // 与「生物识别」开关状态无关。
    final ok = await bio.authenticate(reason: s.exportMnReason);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.authFailedNoExport)),
        );
      }
      return;
    }

    final store = ref.read(secureStoreProvider);
    final mnemonic = await store.readMnemonic();
    if (!mounted) return;

    if (mnemonic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noWalletData)),
      );
      return;
    }

    // 安全展示：不写入系统剪贴板，明文只出现在本次受保护的对话框内，
    // 由用户肉眼核对/抄写后手动关闭，避免留痕被其他应用读取。
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.backupMnemonic),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              SelectableText(
                mnemonic,
                style: const TextStyle(fontSize: 16, height: 1.6),
              ),
              const SizedBox(height: 12),
              Text(
                s.mnemonicWarning,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.ok),
          ),
        ],
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.mnemonicShown)),
    );
  }

  /// 退出当前钱包：二次确认 + 身份验证后清除本机助记词，
  /// 回到创建/导入页，可创建或导入其他钱包。
  Future<void> _logout() async {
    final s = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.logoutTitle),
        content: Text(s.logoutContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.logoutConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 退出删除数据前同样要求身份验证。
    final bio = ref.read(biometricAuthProvider);
    final ok = await bio.authenticate(reason: s.logoutReason);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.authFailedLogoutCancelled)),
        );
      }
      return;
    }

    final store = ref.read(secureStoreProvider);
    await store.deleteMnemonic();
    await store.clearInitialized();
    ref.read(walletStateProvider.notifier).lock();
    if (mounted) context.go('/wallet');
  }

  /// 语言选择弹窗：跟随系统 / 中文 / English。
  Future<void> _pickLanguage() async {
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

  String _languageLabel(AppStrings s, AppLanguage sel) {
    switch (sel) {
      case AppLanguage.zh:
        return s.langZh;
      case AppLanguage.en:
        return s.langEn;
      case AppLanguage.system:
        return s.langSystem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletStateProvider);
    final s = ref.watch(appStringsProvider);
    final langSel = ref.watch(languageSelectionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.navSettings)),
      body: ListView(
        children: [
          if (wallet.isReady && wallet.addresses != null) ...[
            _SettingsSection(title: s.addressManagement, children: [
              ListTile(
                leading: const Icon(Icons.key),
                title: Text(s.plainAddress),
                subtitle: SelectableText(wallet.addresses!.plain.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyAddress(
                    wallet.addresses!.plain.toString(),
                    s.plainAddress,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off),
                title: Text(s.privateAddress),
                subtitle: SelectableText(wallet.addresses!.private.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyAddress(
                    wallet.addresses!.private.toString(),
                    s.privateAddress,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text(s.bscAddress),
                subtitle: SelectableText(wallet.addresses!.bsc.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyAddress(
                    wallet.addresses!.bsc.toString(),
                    s.bscAddress,
                  ),
                ),
              ),
            ]),
          ],
          _SettingsSection(title: s.security, children: [
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text(s.biometric),
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
              title: Text(s.exportMnemonic),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportMnemonic,
            ),
          ]),
          _SettingsSection(title: s.language, children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(s.language),
              subtitle: Text(_languageLabel(s, langSel)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickLanguage,
            ),
          ]),
          _SettingsSection(title: s.network, children: [
            ListTile(
              leading: const Icon(Icons.network_check),
              title: Text(s.rpcNode),
              subtitle: Text(s.rpcNodeValue),
              trailing: const Icon(Icons.chevron_right),
            ),
          ]),
          _SettingsSection(title: s.about, children: [
            ListTile(
              leading: const Icon(Icons.info),
              title: Text(s.version),
              subtitle: FutureBuilder<PackageInfo>(
                future: (_packageInfoFuture ??= PackageInfo.fromPlatform()),
                builder: (context, snap) {
                  final v = snap.data?.version ?? '—';
                  return Text('v$v');
                },
              ),
            ),
          ]),
          _SettingsSection(title: s.walletSection, children: [
            ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text(
                s.logoutSwitch,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: Text(s.logoutHint),
              onTap: _logout,
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
