import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di.dart';
import '../../core/network/native_rpc.dart';
import '../../core/utils/amount.dart';

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
/// - 转入：扫描最近 5 个区块（`getblock` verbosity=2）与 mempool 中发往
///   本机地址脚本的输出（裸节点无 `get_history`，以区块扫描替代）；
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

    // 转入：扫描最近 5 个区块 + mempool 中发往本机地址脚本的输出
    // （rcpu.cloud 为裸节点，无 get_history；1–5 确认来自区块，0 确认来自
    // mempool）。扫描失败不阻塞转出列表展示。
    var incoming = <PendingTx>[];
    if (address != null && address.isNotEmpty) {
      try {
        final scriptHex = _rpc.scriptHexForAddress(address);
        if (scriptHex != null) {
          final tip = await _rpc.getBlockHeight();
          // txid -> (确认数, 合计金额 micro)；同交易多输出合并。
          final matched = <String, _IncomingMatch>{};
          void collect(Iterable<ScannedVout> vouts, int confs) {
            for (final v in vouts) {
              if (v.scriptHex != scriptHex) continue;
              final m = matched[v.txid];
              if (m == null) {
                matched[v.txid] = _IncomingMatch(confs, v.amountMicro);
              } else {
                m.amountMicro += v.amountMicro;
              }
            }
          }

          // 1–5 确认：最近 5 个区块（6 确认及以上本就不展示）。
          for (var h = tip; h > tip - (requiredConfirmations - 1) && h > 0; h--) {
            collect(await _rpc.getBlockVouts(h), tip - h + 1);
          }
          // 0 确认：mempool。
          collect(await _rpc.getMempoolVouts(), 0);

          incoming = [
            for (final e in matched.entries)
              PendingTx(
                txid: e.key,
                direction: 'in',
                amount: Amount.fromMicro(e.value.amountMicro),
                confirmations: e.value.confs,
              ),
          ];
        }
      } catch (_) {
        // 历史扫描失败不阻塞转出列表展示。
      }
    }

    state = [..._outgoing.reversed, ...incoming];
  }
}

/// 区块/mempool 扫描匹配到的入账（同交易多输出累加金额）。
class _IncomingMatch {
  final int confs;
  int amountMicro;
  _IncomingMatch(this.confs, this.amountMicro);
}
