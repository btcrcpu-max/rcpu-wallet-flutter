import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rcpu_wallet/core/network/native_rpc.dart';
import 'package:rcpu_wallet/core/utils/ct_resolver.dart';

/// TC-CT-IN-00（新）：`resolve_ct` 代理契约（docs/proxy-rpc-schema.md §6.1 对象形态）。
///
/// 使用本地 HttpServer 模拟代理，验证：
/// - 请求形态（method / params 对象 = txHex + viewSeed + ownScriptPubKey）；
/// - 成功响应解析（amountMicro / verified）；
/// - 非本人输出返回 `amountMicro == null`（不抛异常）；
/// - 代理错误（-32002 / -32001）映射为 [RpcException]；
/// - [CtResolver.resolveOutput] 转发链路：本人返回金额、非本人返回 null。
void main() {
  late HttpServer server;
  late Uri base;

  /// 记录最后一次收到的 JSON-RPC 请求体。
  Map<String, dynamic>? lastRequest;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    lastRequest = null;
    server.listen((HttpRequest req) async {
      req.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      final body = await utf8.decoder.bind(req).join();
      lastRequest = jsonDecode(body) as Map<String, dynamic>;
      // 由各用例自行覆写 handler 前，先检查是否设置了应答。
      if (respond != null) {
        req.response.write(jsonEncode(respond!()));
      } else {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write(jsonEncode({'jsonrpc': '2.0', 'error': {'code': -32603}}));
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  /// 各用例设置应答；返回 json 可序列化对象。
  Map<String, dynamic> Function()? respond;

  NativeRpcClient client() => NativeRpcClient(baseUrl: base.toString());

  const tx = '01000000';
  const viewSeed = '23f71d02deed10b0a9562200e8ef49951f2e5a2d775eb92d9fe0bda764fda1fe';
  const ownSpk = '5120aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('请求形态：method=resolve_ct，params 为对象（txHex/viewSeed/ownScriptPubKey）', () async {
    respond = () => {
          'jsonrpc': '2.0',
          'id': 4,
          'result': {'amountMicro': 70000000, 'verified': true},
        };
    final rpc = client();
    final r = await rpc.resolveCt(
      txHex: tx,
      viewSeed: viewSeed,
      ownScriptPubKey: ownSpk,
    );
    expect(lastRequest!['jsonrpc'], '2.0');
    expect(lastRequest!['id'], 4);
    expect(lastRequest!['method'], 'resolve_ct');
    expect(lastRequest!['params'], {
      'txHex': tx,
      'viewSeed': viewSeed,
      'ownScriptPubKey': ownSpk,
    });
    expect(r.amountMicro, 70000000);
    expect(r.verified, isTrue);
    expect(r.isMine, isTrue);
  });

  test('成功响应：金额为十进制整数 micro，verified=true', () async {
    respond = () => {
          'jsonrpc': '2.0',
          'id': 4,
          'result': {'amountMicro': 150000000, 'verified': true},
        };
    final r = await client().resolveCt(
      txHex: tx,
      viewSeed: viewSeed,
      ownScriptPubKey: ownSpk,
    );
    expect(r.amountMicro, 150000000);
    expect(r.verified, isTrue);
    expect(r.isMine, isTrue);
  });

  test('非本人输出：amountMicro=null 且 verified=false，不抛异常', () async {
    respond = () => {
          'jsonrpc': '2.0',
          'id': 4,
          'result': {'amountMicro': null, 'verified': false},
        };
    final r = await client().resolveCt(
      txHex: tx,
      viewSeed: viewSeed,
      ownScriptPubKey: ownSpk,
    );
    expect(r.amountMicro, isNull);
    expect(r.verified, isFalse);
    expect(r.isMine, isFalse);
  });

  test('代理错误 -32002（viewing key 错误）→ RpcException', () async {
    respond = () => {
          'jsonrpc': '2.0',
          'id': 4,
          'error': {'code': -32002, 'message': 'CT unblind 失败（viewing key 错误 / 无本人输出）'},
        };
    await expectLater(
      client().resolveCt(
        txHex: tx,
        viewSeed: viewSeed,
        ownScriptPubKey: ownSpk,
      ),
      throwsA(isA<RpcException>()
          .having((e) => e.code, 'code', -32002)
          .having((e) => e.message, 'message', contains('CT unblind'))),
    );
  });

  test('代理错误 -32001（链不可达）→ RpcException', () async {
    respond = () => {
          'jsonrpc': '2.0',
          'id': 4,
          'error': {'code': -32001, 'message': '链不可达或超时'},
        };
    await expectLater(
      client().resolveCt(
        txHex: tx,
        viewSeed: viewSeed,
        ownScriptPubKey: ownSpk,
      ),
      throwsA(isA<RpcException>().having((e) => e.code, 'code', -32001)),
    );
  });

  test('CtResolver 转发链路：本人输出返回金额（micro）', () async {
    respond = () => {
          'jsonrpc': '2.0',
          'id': 4,
          'result': {'amountMicro': 70000000, 'verified': true},
        };
    final resolver = CtResolver(client());
    final amount = await resolver.resolveOutput(
      txHex: tx,
      viewSeed: viewSeed,
      ownScriptPubKey: ownSpk,
    );
    expect(amount, 70000000);
  });

  test('CtResolver 转发链路：非本人输出返回 null', () async {
    respond = () => {
          'jsonrpc': '2.0',
          'id': 4,
          'result': {'amountMicro': null, 'verified': false},
        };
    final resolver = CtResolver(client());
    final amount = await resolver.resolveOutput(
      txHex: tx,
      viewSeed: viewSeed,
      ownScriptPubKey: ownSpk,
    );
    expect(amount, isNull);
  });
}