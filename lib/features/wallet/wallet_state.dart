import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di.dart';
import '../../core/models/balance.dart';
import '../native/native_service.dart';
import '../wrcpu/wrcpu_service.dart';
import 'wallet_service.dart';

/// 钱包全局状态。
///
/// 初始为未初始化（[WalletStatus.uninitialized]），创建/导入后解锁为
/// [WalletStatus.ready]，持有三套派生地址与真实余额。
final walletStateProvider =
    StateNotifierProvider<WalletStateNotifier, WalletState>((ref) {
  final store = ref.watch(secureStoreProvider);
  final nativeRpc = ref.watch(nativeRpcProvider);
  final bscRpc = ref.watch(bscRpcProvider);
  return WalletStateNotifier(
    WalletService(store),
    NativeService(nativeRpc),
    WrcpuService(bscRpc),
  );
});

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
  final NativeService _nativeService;
  final WrcpuService _wrcpuService;

  WalletStateNotifier(this._service, this._nativeService, this._wrcpuService)
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

  /// 解锁后派生地址并加载真实余额（原生 RPC + BSC RPC）。
  ///
  /// 任一链查询失败不阻塞整页：失败资产按 0 展示，并记录错误消息
  /// 供 UI 提示，避免「余额始终 0 且无任何说明」。
  Future<void> _unlock() async {
    final addrs = await _service.deriveAddresses();
    state = WalletState(
      status: WalletStatus.loading,
      addresses: addrs,
      balances: const [],
    );
    // 两条链分别查询、分别兜底：任一失败不影响另一条余额展示。
    Future<Balance> guard(String asset, Future<Balance> f) async {
      try {
        return await f;
      } catch (_) {
        return Balance.zero(asset);
      }
    }

    final results = await Future.wait([
      guard('native', _nativeService.getBalance(addrs.plain.value)),
      guard('wrcpu', _wrcpuService.getBalance(addrs.bsc.value)),
    ]);
    state = WalletState(
      status: WalletStatus.ready,
      addresses: addrs,
      balances: [results[0], results[1]],
    );
  }

  /// 刷新余额（节点高度变化或用户下拉刷新时调用）。
  ///
  /// 复用 [_unlock] 的双链查询与单链兜底逻辑；仅在钱包就绪时执行，
  /// 地址不变，仅更新 [WalletState.balances]。
  Future<void> refreshBalances() async {
    final addrs = state.addresses;
    if (addrs == null || state.status != WalletStatus.ready) return;
    Future<Balance> guard(String asset, Future<Balance> f) async {
      try {
        return await f;
      } catch (_) {
        return Balance.zero(asset);
      }
    }

    final results = await Future.wait([
      guard('native', _nativeService.getBalance(addrs.plain.value)),
      guard('wrcpu', _wrcpuService.getBalance(addrs.bsc.value)),
    ]);
    state = state.copyWith(balances: [results[0], results[1]]);
  }
}
