import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/crypto/derivation.dart';
import '../../core/models/address.dart';
import '../../core/models/balance.dart';
import '../../core/secure_store/secure_store.dart';
import 'wallet_service.dart';

/// 钱包全局状态。
///
/// 初始为未初始化（[WalletStatus.uninitialized]），创建/导入后解锁为
/// [WalletStatus.ready]，持有三套派生地址与占位余额。
final walletStateProvider =
    StateNotifierProvider<WalletStateNotifier, WalletState>((ref) {
  final store = ref.watch(secureStoreProvider);
  return WalletStateNotifier(WalletService(store));
});

/// 安全存储 Provider（已在 di.dart 定义，此处引用避免循环依赖）。
final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

/// 钱包状态枚举。
enum WalletStatus { uninitialized, loading, ready, error }

/// 聚合状态（地址 + 余额 + 状态）。
class WalletState {
  final WalletStatus status;
  final DerivedAddresses? addresses;
  final List<Balance> balances;
  final String? errorMessage;

  const WalletState({
    required this.status,
    this.addresses,
    this.balances = const [],
    this.errorMessage,
  });

  bool get isReady => status == WalletStatus.ready;

  /// 总资产折合占位值（RCPU + wRCPU 原值展示，不做汇率换算）。
  String get totalBalanceDisplay {
    if (balances.isEmpty) return '0.00000000';
    final sum = balances.fold<int>(0, (a, b) => a + b.micro);
    final raw = sum / 1e8;
    return raw.toStringAsFixed(8);
  }

  Balance? balanceOf(String asset) =>
      balances.where((b) => b.asset == asset).firstOrNull;

  /// 占位：余额列表始终包含两种资产，缺失时补零。
  static List<Balance> placeholderBalances() => [
        Balance.zero('native'),
        Balance.zero('wrcpu'),
      ];

  WalletState copyWith({
    WalletStatus? status,
    DerivedAddresses? addresses,
    List<Balance>? balances,
    String? errorMessage,
  }) {
    return WalletState(
      status: status ?? this.status,
      addresses: addresses ?? this.addresses,
      balances: balances ?? this.balances,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class WalletStateNotifier extends StateNotifier<WalletState> {
  final WalletService _service;

  WalletStateNotifier(this._service)
      : super(const WalletState(status: WalletStatus.uninitialized));

  /// 首次启动时检测是否已初始化。
  Future<void> checkInitialized() async {
    state = const WalletState(status: WalletStatus.loading);
    try {
      final ok = await _service.isInitialized();
      if (ok) {
        await _unlock();
      } else {
        state = const WalletState(status: WalletStatus.uninitialized);
      }
    } catch (e) {
      state = WalletState(
        status: WalletStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 创建新钱包。
  Future<String> createWallet() async {
    state = const WalletState(status: WalletStatus.loading);
    try {
      final mnemonic = await _service.createWallet();
      await _unlock();
      return mnemonic;
    } catch (e) {
      state = WalletState(
        status: WalletStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// 导入助记词。
  Future<String> importMnemonic(String mnemonic) async {
    state = const WalletState(status: WalletStatus.loading);
    try {
      final m = await _service.importMnemonic(mnemonic);
      await _unlock();
      return m;
    } catch (e) {
      state = WalletState(
        status: WalletStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// 解锁后派生地址并加载余额。
  Future<void> _unlock() async {
    final addrs = await _service.deriveAddresses();
    // 占位余额：联调前用零余额，后续由 RPC 替换。
    final balances = WalletState.placeholderBalances();
    state = WalletState(
      status: WalletStatus.ready,
      addresses: addrs,
      balances: balances,
    );
  }
}
