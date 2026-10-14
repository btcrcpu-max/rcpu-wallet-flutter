import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/balance.dart';
import '../models/tx_record.dart';

/// 原生链 RPC 客户端。
///
/// 连接公开节点 RPC 7337 或轻量代理；CT 输出解析优先由代理完成，
/// APP 侧保留 [resolveCtOutput] 占位供本地 unblind 储备。
class NativeRpcClient {
  /// 默认公开节点；生产环境经轻量代理转发并缓存余额。
  final String baseUrl;

  late final Dio _dio;

  NativeRpcClient({this.baseUrl = 'http://127.0.0.1:7337'}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
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

  /// 解析 CT 输出为明文金额（占位：轻量代理优先，本地实现储备）。
  Future<String?> resolveCtOutput(String txHex) async {
    throw UnimplementedError('CT unblind 待接入代理或本地实现');
  }

  static int _parseMicro(String raw) {
    return (double.tryParse(raw) ?? 0.0) * 1e8 ~/ 1;
  }
}