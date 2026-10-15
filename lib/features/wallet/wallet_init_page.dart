import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                  onPressed: () => context.go('/'),
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
      if (mounted) context.go('/');
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
