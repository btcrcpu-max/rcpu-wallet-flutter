import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/l10n/app_strings.dart';
import '../wallet/wallet_state.dart';

/// 钱包初始化页：创建新钱包或导入助记词。
class WalletInitPage extends ConsumerStatefulWidget {
  const WalletInitPage({super.key});

  @override
  ConsumerState<WalletInitPage> createState() => _WalletInitPageState();
}

class _WalletInitPageState extends ConsumerState<WalletInitPage> {
  final _importController = TextEditingController();
  bool _showImport = false;
  String? _createdMnemonic;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 启动时检测：钱包已初始化则直接进入首页。
  Future<void> _bootstrap() async {
    final notifier = ref.read(walletStateProvider.notifier);
    await notifier.checkInitialized();
    if (!mounted) return;
    if (ref.read(walletStateProvider).isReady) {
      context.go('/');
      return;
    }
    setState(() => _checking = false);
  }

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = ref.watch(appStringsProvider);

    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Icon(Icons.account_balance_wallet, size: 64, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(s.appTitle, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(s.appSubtitle, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 40),
              if (_createdMnemonic == null && !_showImport) ...[
                FilledButton.icon(
                  onPressed: _createWallet,
                  icon: const Icon(Icons.add),
                  label: Text(s.createNewWallet),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showImport = true),
                  icon: const Icon(Icons.download),
                  label: Text(s.importExisting),
                ),
              ],
              if (_createdMnemonic != null) ...[
                Card(
                  color: colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.backupMnemonic, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SelectableText(
                          _createdMnemonic!,
                          style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(s.mnemonicWarning, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _enterWallet,
                  child: Text(s.backedUpEnter),
                ),
              ],
              if (_showImport) ...[
                TextField(
                  controller: _importController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: s.mnemonicLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _importWallet,
                  child: Text(s.importWallet),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _showImport = false),
                  child: Text(s.back),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createWallet() async {
    try {
      final mnemonic = await ref.read(walletStateProvider.notifier).createWallet();
      if (mounted) {
        setState(() => _createdMnemonic = mnemonic);
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _importWallet() async {
    final mnemonic = _importController.text.trim();
    if (mnemonic.isEmpty) {
      _showError(ref.read(appStringsProvider).enterMnemonic);
      return;
    }
    try {
      await ref.read(walletStateProvider.notifier).importMnemonic(mnemonic);
      if (mounted) await _enterWallet();
    } catch (e) {
      _showError(e.toString());
    }
  }

  /// 进入钱包前引导开启生物识别保护（指纹/人脸）。
  ///
  /// 设备支持且已录入生物特征但未开启时，弹窗建议开启；
  /// 开启前需通过一次系统验证（指纹/人脸或锁屏密码）。
  /// 设备不支持时直接进入，不影响使用。
  Future<void> _enterWallet() async {
    final bio = ref.read(biometricAuthProvider);
    final s = ref.read(appStringsProvider);
    try {
      final available = await bio.isAvailable();
      final enrolled = await bio.hasEnrolledBiometrics();
      final enabled = await bio.isEnabled();
      if (available && enrolled && !enabled && mounted) {
        final enable = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.bioProtectTitle),
            content: Text(s.bioProtectContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.notNow),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.enableNow),
              ),
            ],
          ),
        );
        if (enable == true) {
          final ok = await bio.authenticate(reason: s.bioEnableVerifyReason);
          if (ok) {
            await bio.setEnabled(true);
          } else if (mounted) {
            _showError(s.bioEnableFailedHint);
          }
        }
      }
    } catch (_) {
      // 生物能力探测失败不阻塞进入钱包。
    }
    if (mounted) context.go('/');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
