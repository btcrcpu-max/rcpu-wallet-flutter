import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../crypto/bech32.dart';
import '../models/balance.dart';
import '../models/ct_resolve_result.dart';
import '../models/native_utxo.dart';
import '../models/tx_record.dart';

/// RPC 调用失败（错误码定义见 docs/proxy-rpc-schema.md §2）。
class RpcException implements Exception {
  final int code;
  final String message;

  const RpcException(this.code, this.message);

  @override
  String toString() => 'RpcException($code): $message';
}

/// 原生链 RPC 客户端。
///
/// 连接公开节点 RPC 7337 或轻量代理；CT 输出解析由代理完成
/// （`resolve_ct` 契约，见 [resolveCt]）。
///
/// 当代理层自定义方法不可用时，自动回退到 rcpud 原生 Bitcoin Core RPC：
/// - `get_balance`  → `scantxoutset`
/// - `get_utxos`    → `scantxoutset`
/// - `broadcast_tx` → `sendrawtransaction`
/// - `get_history`  → 空列表（原生 RPC 无直接等价方法）
/// - `resolve_ct`   → 未验证结果（原生 RPC 不支持 CT 解析）
class NativeRpcClient {
  /// 默认公开节点；生产环境经轻量代理转发并缓存余额。
  final String baseUrl;

  late final Dio _dio;

  NativeRpcClient({this.baseUrl = 'http://207.57.129.188/rpc'}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Authorization': 'Basic cmNwdXJwYzppa25sbko3b0pYbW9wSElSWjh2cGRMSUxXcUhCZGNUeg==',
        'Content-Type': 'application/json',
      },
    ));
  }

  /// 通用 JSON-RPC 请求封装，统一处理错误与 null result。
  Future<Map<String, dynamic>> _rpc(String method, dynamic params, {int id = 1}) async {
    final resp = await _dio.post(
      '/',
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final body = resp.data as Map<String, dynamic>;
    final err = body['error'];
    if (err != null) {
      final e = err as Map<String, dynamic>;
      throw RpcException(
        e['code'] as int? ?? -32603,
        e['message'] as String? ?? '$method 失败',
      );
    }
    return body;
  }

/// 判断 [RpcException] 是否因代理方法不存在导致。
  bool _isMethodNotFound(RpcException e) =>
      e.message.contains('Method not found') || e.code == -32601;

  /// 将 bech32 明文地址转换为 scantxoutset raw() 描述符。
  ///
  /// 明文 `rcpu1`（P2WPKH）：payload = `0x00 || hash160(20B)`，
  /// scriptPubKey = `0014<hash160>`，描述符 `raw(0014<hash160>)`。
  /// 隐私 `rcpux1`（CT 盲化输出）或解码失败返回 null —— 原生节点
  /// 的 scantxoutset 无法读取 CT 金额，交由代理 resolve_ct 路径处理。
  String? _rawDescriptorFor(String address) {
    if (!address.startsWith('rcpu1')) return null;
    try {
      final payload = Bech32.decodeToBytes(address, isBech32m: false);
      if (payload.length != 21 || payload[0] != 0x00) return null;
      final hash160 = payload.sublist(1);
      final sb = StringBuffer('0014');
      for (final b in hash160) {
        sb.write(b.toRadixString(16).padLeft(2, '0'));
      }
      return 'raw($sb)';
    } catch (_) {
      return null;
    }
  }

  /// 查询原生余额（含 CT unblind 后合计）。
  Future<Balance> getBalance(String address) async {
    try {
      final body = await _rpc('get_balance', [address], id: 1);
      final raw = (body['result'] as String?) ?? '0';
      return Balance(asset: 'native', raw: raw, micro: _parseMicro(raw));
    } on RpcException catch (e) {
      if (_isMethodNotFound(e)) {
        // 回退：使用原生 scantxoutset 扫描 raw() 描述符
        final desc = _rawDescriptorFor(address);
        if (desc == null) {
          // 隐私地址或无法解析：原生 RPC 无法扫描 CT 输出
          return Balance.zero('native');
        }
        final body = await _rpc(
          'scantxoutset',
          ['start', [desc]],
          id: 11,
        );
        final result = body['result'] as Map<String, dynamic>? ?? {};
        final totalAmount = result['total_amount'] as num? ?? 0;
        final raw = totalAmount.toStringAsFixed(8);
        return Balance(asset: 'native', raw: raw, micro: _parseMicro(raw));
      }
      rethrow;
    }
  }

  /// 查询可用 UTXO（docs/proxy-rpc-schema.md §方法五）。
  ///
  /// 代理返回自有、未花费、已确认输出；CT 输出金额已 unblind。
  /// 客户端据此做 UTXO 选择（`PaymentService._buildTxHex`）。
  Future<List<NativeUtxo>> getUtxos(String address) async {
    try {
      final body = await _rpc('get_utxos', [address], id: 5);
      final list = (body['result'] as List?) ?? [];
      return list
          .map((e) => NativeUtxo.fromJson(e as Map<String, dynamic>))
          .toList();
} on RpcException catch (e) {
      if (_isMethodNotFound(e)) {
        // 回退：使用原生 scantxoutset 扫描 raw() 描述符
        final desc = _rawDescriptorFor(address);
        if (desc == null) return const []; // 隐私地址：原生 RPC 无法扫描 CT
        final body = await _rpc(
          'scantxoutset',
          ['start', [desc]],
          id: 15,
        );
        final result = body['result'] as Map<String, dynamic>? ?? {};
        final unspents = result['unspents'] as List? ?? [];
        return unspents.map((e) {
          final json = e as Map<String, dynamic>;
          final spk = json['scriptPubKey'];
          final spkHex = spk is Map
              ? (spk['hex'] ?? '').toString()
              : (spk ?? '').toString();
          return NativeUtxo(
            prevTxid: _hexToBytes((json['txid'] ?? '').toString()),
            vout: (json['vout'] as num?)?.toInt() ?? 0,
            amountMicro: (((json['amount'] as num?)?.toDouble() ?? 0.0) * 1e8).toInt(),
            scriptPubKey: spkHex,
            confirmed: true,
            privacy: 'plain',
          );
        }).toList();
      }
      rethrow;
    }
  }

  /// 广播交易，返回交易哈希。
  Future<String> broadcast(String signedTxHex) async {
    try {
      final body = await _rpc('broadcast_tx', [signedTxHex], id: 2);
      return (body['result'] as String?) ?? '';
    } on RpcException catch (e) {
      if (_isMethodNotFound(e)) {
        // 回退：使用原生 sendrawtransaction
        final body = await _rpc('sendrawtransaction', [signedTxHex], id: 12);
        return (body['result'] as String?) ?? '';
      }
      rethrow;
    }
  }

  /// 查询交易历史（代理聚合明文与 CT 记录）。
  Future<List<TxRecord>> getHistory(String address, {int limit = 20}) async {
    try {
      final body = await _rpc('get_history', [address, limit], id: 3);
      final list = (body['result'] as List?) ?? [];
      return list.map((e) => TxRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on RpcException catch (e) {
      if (_isMethodNotFound(e)) {
        // 原生 Bitcoin Core RPC 没有直接按地址查询交易历史的方法。
        // 返回空列表避免 null cast 异常和 UI 崩溃。
        return [];
      }
      rethrow;
    }
  }

  /// 解析 CT 输出为明文金额（docs/proxy-rpc-schema.md §6.1 对象形态契约）。
  ///
  /// - [txHex]：待解析交易 hex（或 txid，按代理契约）；
  /// - [viewSeed]：Path C view_seed（hex，由 [CtResolver] 提供）；
  /// - [ownScriptPubKey]：本人隐私地址输出脚本（hex），用于匹配输出。
  ///
  /// 非本人输出返回 `CtResolveResult.amountMicro == null`（不抛异常）；
  /// 代理失败（viewing key 错误 / 链不可达）抛 [RpcException]。
  Future<CtResolveResult> resolveCt({
    required String txHex,
    required String viewSeed,
    required String ownScriptPubKey,
  }) async {
    try {
      final body = await _rpc('resolve_ct', {
        'txHex': txHex,
        'viewSeed': viewSeed,
        'ownScriptPubKey': ownScriptPubKey,
      }, id: 4);
      final result = body['result'] as Map<String, dynamic>? ?? {};
      final amountRaw = result['amountMicro'];
      return CtResolveResult(
        amountMicro: amountRaw == null ? null : (amountRaw as num).toInt(),
        verified: result['verified'] as bool? ?? false,
      );
    } on RpcException catch (e) {
      if (_isMethodNotFound(e)) {
        // 原生 RPC 不支持 CT 解析，返回未验证结果（视为非本人交易）。
        return const CtResolveResult(amountMicro: null, verified: false);
      }
      rethrow;
    }
  }

  static int _parseMicro(String raw) {
    return (double.tryParse(raw) ?? 0.0) * 1e8 ~/ 1;
  }

  static Uint8List _hexToBytes(String hex) {
    final h = hex.trim().startsWith('0x') ? hex.trim().substring(2) : hex.trim();
    if (h.isEmpty) return Uint8List(0);
    if (h.length.isOdd) throw const FormatException('hex 长度必须为偶数');
    return Uint8List.fromList(List.generate(
        h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
  }
}
