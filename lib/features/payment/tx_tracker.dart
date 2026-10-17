import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di.dart';
import '../../core/network/native_rpc.dart';

/// 待确认交易（首页/收款页展示；达到 6 确认后自动消失）。
class PendingTx {
  /// 交易哈希（显示字节序）。
  final String txid;

  /// 方向：out=转出（本机广播）/ in=转入（链上检测到）。
  final String direction;

  /// 金额（RCPU 十进制字符串）。
  final String amount;

  /// 当前确认数（0–5；达到 6 即移出列表）。
  final int confirmations;

  const PendingTx({
    required this.txid,
    required this.direction,
    required this.amount,
    required this.confirmations,
  });

  Map<String, dynamic> toJson() => {
        'txid': txid,
        'direction': direction,
        'amount': amount,
      };

  factory PendingTx.fromJson(Map<String, dynamic> json) => PendingTx(
        txid: (json['txid'] ?? '').toString(),
        direction: (json['direction'] ?? 'out').toString(),
        amount: (json['amount'] ?? '0').toString(),
        confirmations: 0,
      );
}

/// 待确认交易列表 provider。
final txTrackerProvider =
    StateNotifierProvider<TxTrackerNotifier, List<PendingTx>>((ref) {
  return TxTrackerNotifier(ref.watch(nativeRpcProvider));
});

/// 追踪收/付款确认数。
///
/// - 转出：本机广播成功时经 [recordOutgoing] 登记并持久化（重启不丢）；
/// - 转入：刷新时按地址拉取历史（[NativeRpcClient.getHistory]），
///   筛出未达 6 确认的入账；
/// - 确认数经 [NativeRpcClient.getConfirmations] 查询（未打包按 0 计），
///   达到 6 确认的记录移出列表（UI 消失）。
class TxTrackerNotifier extends StateNotifier<List<PendingTx>> {
  static const _storeKey = 'pending_outgoing_txs';
  static const requiredConfirmations = 6;

  final NativeRpcClient _rpc;
  List<PendingTx> _outgoing = [];

  TxTrackerNotifier(this._rpc) : super(const []);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storeKey);
    if (raw == null || raw.isEmpty) return;
    try {
      _outgoing = [
        for (final e in jsonDecode(raw) as List)
          PendingTx.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      _outgoing = [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storeKey, jsonEncode([for (final t in _outgoing) t.toJson()]));
  }

  /// 付款广播成功后登记（send 页调用），并立即刷新一次确认数。
  Future<void> recordOutgoing({
    required String txid,
    required String amount,
    String? address,
  }) async {
    await _load();
    if (!_outgoing.any((t) => t.txid == txid)) {
      _outgoing = [
        ..._outgoing,
        PendingTx(txid: txid, direction: 'out', amount: amount, confirmations: 0),
      ];
      await _save();
    }
    await refresh(address);
  }

  /// 刷新全部待确认记录（区块高度变化 / 钱包就绪 / 广播成功后调用）。
  ///
  /// [address] 为本机明文地址，用于拉取转入历史；为 null 时仅刷新转出。
  Future<void> refresh([String? address]) async {
    await _load();

    // 转出：逐条查确认数；达到 6 确认的移除（持久层同步删除）。
    final kept = <PendingTx>[];
    for (final t in _outgoing) {
      final c = await _rpc.getConfirmations(t.txid) ?? 0;
      if (c >= requiredConfirmations) continue;
      kept.add(PendingTx(
        txid: t.txid,
        direction: 'out',
        amount: t.amount,
        confirmations: c,
      ));
    }
    _outgoing = kept;
    await _save();

    // 转入：历史中的未达 6 确认入账（历史查询失败不阻塞转出列表）。
    var incoming = <PendingTx>[];
    if (address != null && address.isNotEmpty) {
      try {
        final history = await _rpc.getHistory(address, limit: 20);
        for (final r in history.where((r) => r.isIncoming)) {
          final c = await _rpc.getConfirmations(r.txHash) ??
              (r.isPending ? 0 : requiredConfirmations);
          if (c < requiredConfirmations) {
            incoming.add(PendingTx(
              txid: r.txHash,
              direction: 'in',
              amount: r.amount,
              confirmations: c,
            ));
          }
        }
      } catch (_) {
        // 历史查询失败不阻塞转出列表展示。
      }
    }

    state = [..._outgoing.reversed, ...incoming];
  }
}
