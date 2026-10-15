import 'dart:convert';

import 'package:dio/dio.dart';

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

  /// 查询原生余额（含 CT unblind 后合计）。
  Future<Balance> getBalance(String address) async {
    final resp = await _dio.post(
      '/',
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'get_balance',
        'params': [address],
      }),
    );
    final raw = (resp.data as Map<String, dynamic>)['result'] as String;
    return Balance(asset: 'native', raw: raw, micro: _parseMicro(raw));
  }

  /// 查询可用 UTXO（docs/proxy-rpc-schema.md §方法五）。
  ///
  /// 代理返回自有、未花费、已确认输出；CT 输出金额已 unblind。
  /// 客户端据此做 UTXO 选择（`PaymentService._buildTxHex`）。
  Future<List<NativeUtxo>> getUtxos(String address) async {
    final resp = await _dio.post(
      '/',
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'get_utxos',
        'params': [address],
      }),
    );
    final list = (resp.data as Map<String, dynamic>)['result'] as List;
    return list
        .map((e) => NativeUtxo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 广播交易，返回交易哈希。
  Future<String> broadcast(String signedTxHex) async {
    final resp = await _dio.post(
      '/',
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'broadcast_tx',
        'params': [signedTxHex],
      }),
    );
    return (resp.data as Map<String, dynamic>)['result'] as String;
  }

  /// 查询交易历史（代理聚合明文与 CT 记录）。
  Future<List<TxRecord>> getHistory(String address, {int limit = 20}) async {
    final resp = await _dio.post(
      '/',
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'get_history',
        'params': [address, limit],
      }),
    );
    final list = (resp.data as Map<String, dynamic>)['result'] as List;
    return list.map((e) => TxRecord.fromJson(e as Map<String, dynamic>)).toList();
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
    final resp = await _dio.post(
      '/',
      data: jsonEncode({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'resolve_ct',
        'params': {
          'txHex': txHex,
          'viewSeed': viewSeed,
          'ownScriptPubKey': ownScriptPubKey,
        },
      }),
    );
    final body = resp.data as Map<String, dynamic>;
    final err = body['error'];
    if (err != null) {
      final e = err as Map<String, dynamic>;
      throw RpcException(
        e['code'] as int? ?? -32603,
        e['message'] as String? ?? 'resolve_ct 失败',
      );
    }
    final result = body['result'] as Map<String, dynamic>;
    final amountRaw = result['amountMicro'];
    return CtResolveResult(
      amountMicro: amountRaw == null ? null : (amountRaw as num).toInt(),
      verified: result['verified'] as bool? ?? false,
    );
  }

  static int _parseMicro(String raw) {
    return (double.tryParse(raw) ?? 0.0) * 1e8 ~/ 1;
  }
}