import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di.dart';
import '../../core/network/native_rpc.dart';

/// 节点同步状态（首页右上角指示）。
class NodeSyncStatus {
  final bool connected;
  final int? height;
  final String? error;
  final DateTime? updatedAt;

  const NodeSyncStatus({
    this.connected = false,
    this.height,
    this.error,
    this.updatedAt,
  });
}

/// 节点同步状态 provider：启动即查询，每 30 秒轮询一次区块高度。
///
/// 连接失败时 [NodeSyncStatus.error] 携带可读原因（超时 / HTTP 状态码 /
/// RPC 错误），UI 据此区分「节点未连接」与「余额为 0」。
final nodeSyncProvider =
    StateNotifierProvider<NodeSyncNotifier, NodeSyncStatus>((ref) {
  return NodeSyncNotifier(ref.watch(nativeRpcProvider));
});

class NodeSyncNotifier extends StateNotifier<NodeSyncStatus> {
  final NativeRpcClient _rpc;
  Timer? _timer;

  NodeSyncNotifier(this._rpc) : super(const NodeSyncStatus()) {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  /// 立即查询一次区块高度（供自动轮询与手动重试共用）。
  Future<void> refresh() async {
    try {
      final h = await _rpc.getBlockHeight();
      state = NodeSyncStatus(
        connected: true,
        height: h,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      state = NodeSyncStatus(
        connected: false,
        error: e.toString(),
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
