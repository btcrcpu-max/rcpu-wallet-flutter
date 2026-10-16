import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
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
              Text('RCPU 钱包', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('原生 RCPU + BSC wRCPU 双链钱包', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 40),
              if (_createdMnemonic == null && !_showImport) ...[
                FilledButton.icon(
                  onPressed: _createWallet,
                  icon: const Icon(Icons.add),
                  label: const Text('创建新钱包'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showImport = true),
                  icon: const Icon(Icons.download),
                  label: const Text('导入已有钱包'),
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
                        Text('请备份助记词', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SelectableText(
                          _createdMnemonic!,
                          style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text('⚠️ 助记词是恢复钱包的唯一凭证，请妥善保存，不要截图或发送给他人', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _enterWallet,
                  child: const Text('我已备份，进入钱包'),
                ),
              ],
              if (_showImport) ...[
                TextField(
                  controller: _importController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '助记词（12 个英文单词，空格分隔）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _importWallet,
                  child: const Text('导入钱包'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _showImport = false),
                  child: const Text('返回'),
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
      _showError('请输入助记词');
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
    try {
      final available = await bio.isAvailable();
      final enrolled = await bio.hasEnrolledBiometrics();
      final enabled = await bio.isEnabled();
      if (available && enrolled && !enabled && mounted) {
        final enable = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('开启指纹/面容保护'),
            content: const Text(
              '建议开启生物识别保护钱包：\n'
              '进入付款、导出助记词等敏感操作时将要求验证指纹/面容或锁屏密码。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('暂不'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('立即开启'),
              ),
            ],
          ),
        );
        if (enable == true) {
          final ok = await bio.authenticate(reason: '验证以开启生物识别保护');
          if (ok) {
            await bio.setEnabled(true);
          } else if (mounted) {
            _showError('验证失败，未开启生物识别（可稍后在设置中开启）');
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
