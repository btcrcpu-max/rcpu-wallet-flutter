import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di.dart';
import '../../core/models/bridge_state.dart';
import '../../core/models/address.dart';
import '../../core/network/bsc_rpc.dart';
import '../../core/network/http_client.dart';
import '../../core/utils/amount.dart';

/// 桥常量（已确认事实，勿改）。
class BridgeConfig {
  /// 桥站点
  static const String site = 'https://rcpupool.asia/';

  /// 最小存款 0.01 RCPU
  static const double minDeposit = 0.01;

  /// 按地址累计满 10 RCPU 才铸造
  static const double mintThreshold = 10.0;

  /// 状态轮询回调（秒）
  static const Duration pollInterval = Duration(seconds: 8);

  /// 轮询最多 3 次，指数退避：10s -> 20s -> 40s
  static const List<Duration> retryBackoff = [
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
  ];
}

/// 桥操作结果。
class BridgeResult {
  final bool ok;
  final String message;
  final BridgeState? state;

  const BridgeResult.ok(String this.message, {this.state}) : ok = true;
  const BridgeResult.fail(String this.message) : ok = false, state = null;
}

/// 桥模块状态机 Provider。
///
/// 职责：
/// 1. 铸造：获取专属明文 rcpu1 存款地址 -> 校验存款 -> 轮询到账（3 次指数退避）
/// 2. 赎回：BSC 调用 wrcpuContract.redeem -> 指定手机钱包原生 RCPU 地址收款
/// 3. 桥 API 失败时降级为 WebView 引导（页面层处理，本层给出标记）
class BridgeNotifier extends StateNotifier<BridgeState> {
  BridgeNotifier(this._ref) : super(BridgeState.idle());

  final Ref _ref;

  /// 当前桥 API 是否可用（失败降级 WebView 标记）。
  bool _apiAvailable = true;
  bool get apiAvailable => _apiAvailable;

  BscRpcClient get _bsc => _ref.read(bscRpcProvider);

  /// 获取用户专属明文 rcpu1 存款地址。
  ///
  /// 优先桥 API；API 不可用时返回 null，由页面降级为 WebView。
  Future<String?> fetchDepositAddress(String userPlainAddress) async {
    try {
      final client = HttpClient(baseUrl: BridgeConfig.site);
      final resp = await client.post('/api/v1/deposit/address', body: {
        'nativeAddress': userPlainAddress,
      });
      _apiAvailable = true;
      final address = (resp as Map<String, dynamic>)['address'] as String;
      state = BridgeState(
        phase: 'deposit',
        state: 'collecting',
        depositAddress: address,
      );
      return address;
    } catch (_) {
      _apiAvailable = false;
      return null; // 降级：页面打开 WebView 至桥站点
    }
  }

  /// 铸造：强制使用明文 rcpu1 地址，禁止 rcpux1 隐私地址。
  ///
  /// [fromPlainAddress] 为用户的明文 rcpu1 地址；
  /// [amountMicro] 为本次发送数量（micro 单位，>= 0.01 RCPU）。
  Future<BridgeResult> deposit({
    required String fromPlainAddress,
    required int amountMicro,
    String? nativeTxHash,
  }) async {
    final Address addr;
    try {
      addr = Address.parse(fromPlainAddress);
    } on FormatException {
      return const BridgeResult.fail('铸造仅支持明文 rcpu1 地址，已拒绝 rcpux1');
    }
    if (!addr.isPlain) {
      return const BridgeResult.fail('铸造仅支持明文 rcpu1 地址，已拒绝 rcpux1');
    }
    if (amountMicro < Amount.minDepositMicro) {
      return const BridgeResult.fail('最低存款 0.01 RCPU');
    }
    state = BridgeState(
      phase: 'deposit',
      state: 'collecting',
      depositAddress: fromPlainAddress,
      totalDeposited: Amount.fromMicro(amountMicro),
    );
    try {
      final client = HttpClient(baseUrl: BridgeConfig.site);
      await client.post('/api/v1/deposit/record', body: {
        'nativeAddress': fromPlainAddress,
        'amount': Amount.fromMicro(amountMicro),
        'txHash': nativeTxHash ?? '',
      });
      return BridgeResult.ok('存款已记录，等待累计满 10 RCPU', state: state);
    } catch (_) {
      return const BridgeResult.fail('桥 API 暂不可用，请稍后重试');
    }
  }

  /// 轮询铸造状态：最多 3 次，指数退避 10s -> 20s -> 40s。
  ///
  /// 返回最新状态；仍未 minted 时由页面提示累计进度。
  Future<BridgeState> pollMintStatus(String userPlainAddress) async {
    state = BridgeState(
      phase: 'deposit',
      state: 'collecting',
      depositAddress: userPlainAddress,
    );
    for (var i = 0; i < BridgeConfig.retryBackoff.length; i++) {
      await Future.delayed(BridgeConfig.retryBackoff[i]);
      final result = await _queryMintStatus(userPlainAddress);
      state = result;
      if (result.state == 'minted' || result.state == 'failed') {
        return result;
      }
    }
    return state;
  }

  Future<BridgeState> _queryMintStatus(String plainAddress) async {
    try {
      final client = HttpClient(baseUrl: BridgeConfig.site);
      final resp = await client.get('/api/v1/deposit/status', query: {
        'nativeAddress': plainAddress,
      });
      final map = resp as Map<String, dynamic>;
      return BridgeState(
        phase: 'deposit',
        state: map['state'] as String,
        totalDeposited: (map['totalDeposited'] ?? '0').toString(),
        wrcpuTxHash: map['wrcpuTxHash'] as String?,
        estimatedTimeMinutes: map['estimatedMinutes'] as int?,
      );
    } catch (_) {
      // 查询失败不改变外部状态，等待下一次轮询
      return BridgeState(
        phase: 'deposit',
        state: 'collecting',
        depositAddress: plainAddress,
      );
    }
  }

  /// 赎回：BSC 上调用 wrcpuContract.redeem，收款地址为手机钱包原生 RCPU 地址。
  ///
  /// 先做 BNB Gas 检查；Gas 不足时明确报错，不广播。
  /// [amountMicro] 为 wRCPU 数量（Decimals = 8）。
  Future<BridgeResult> redeem({
    required String bscPrivateKey,
    required String bscAddress,
    required String rcpuReceiveAddress,
    required int amountMicro,
  }) async {
    final Address addr;
    try {
      addr = Address.parse(rcpuReceiveAddress);
    } on FormatException {
      return const BridgeResult.fail('赎回收款地址必须是明文 rcpu1 地址');
    }
    if (!addr.isPlain) {
      return const BridgeResult.fail('赎回收款地址必须是明文 rcpu1 地址');
    }
    if (amountMicro < Amount.minDepositMicro) {
      return const BridgeResult.fail('赎回金额过小');
    }
    state = BridgeState(
      phase: 'redeem',
      state: 'processing',
      estimatedTimeMinutes: 15,
    );
    try {
      final bnbWei = await _bsc.getBnbBalance(bscAddress);
      if (bnbWei < BigInt.from(10000000000000000)) { // 0.01 BNB 预估
        return const BridgeResult.fail('BSC Gas（BNB）不足，请先补充 BNB');
      }
      final txHash = await _bsc.redeem(
        fromPrivateKey: bscPrivateKey,
        amount: BigInt.from(amountMicro),
        rcpuAddress: rcpuReceiveAddress,
      );
      state = BridgeState(
        phase: 'redeem',
        state: 'pending',
        wrcpuTxHash: txHash,
        estimatedTimeMinutes: 15,
      );
      return BridgeResult.ok('赎回已广播，RCPU 将直接到账原生余额', state: state);
    } catch (e) {
      state = BridgeState(
        phase: 'redeem',
        state: 'failed',
        errorCode: 'REDEEM_FAILED',
      );
      return BridgeResult.fail('赎回失败: $e');
    }
  }

  /// 重置状态。
  void reset() {
    state = BridgeState.idle();
    _apiAvailable = true;
  }
}

final bridgeProvider =
    StateNotifierProvider<BridgeNotifier, BridgeState>((ref) {
  return BridgeNotifier(ref);
});