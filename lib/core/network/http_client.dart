import 'package:dio/dio.dart';

/// HTTP 客户端统一封装：超时、重试、错误映射。
class HttpClient {
  static const _baseOptions = BaseOptions(
    connectTimeout: Duration(seconds: 15),
    receiveTimeout: Duration(seconds: 20),
    headers: {'Content-Type': 'application/json'},
  );

  late final Dio _dio;

  HttpClient({String? baseUrl}) {
    _dio = Dio(_baseOptions);
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _dio.options.baseUrl = baseUrl;
    }
  }

  /// GET 请求。
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Map<String, String>? headers}) async {
    final resp = await _dio.get(path, queryParameters: query, options: _headers(headers));
    return resp.data;
  }

  /// POST 请求。
  Future<dynamic> post(String path,
      {Object? body, Map<String, String>? headers}) async {
    final resp = await _dio.post(path, data: body, options: _headers(headers));
    return resp.data;
  }

  Options? _headers(Map<String, String>? extra) {
    if (extra == null || extra.isEmpty) return null;
    return Options(headers: extra);
  }
}

/// 桥 API 与 RPC 代理的通用异常。
class ApiException implements Exception {
  final String code;
  final String message;

  ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException($code): $message';
}