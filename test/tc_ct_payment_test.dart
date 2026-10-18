import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:rcpu_wallet/core/biometric/biometric_auth.dart';
import 'package:rcpu_wallet/core/crypto/bech32.dart';
import 'package:rcpu_wallet/core/crypto/derivation.dart';
import 'package:rcpu_wallet/core/crypto/signature.dart';
import 'package:rcpu_wallet/core/models/balance.dart';
import 'package:rcpu_wallet/core/models/ct_resolve_result.dart';
import 'package:rcpu_wallet/core/models/native_utxo.dart';
import 'package:rcpu_wallet/core/models/tx_record.dart';
import 'package:rcpu_wallet/core/network/ct_helper_client.dart';
import 'package:rcpu_wallet/core/network/native_rpc.dart';
import 'package:rcpu_wallet/core/utils/ct_resolver.dart';
import 'package:rcpu_wallet/features/native/native_service.dart';
import 'package:rcpu_wallet/features/payment/payment_service.dart';

/// TC-CT-PAY-01：机密交易（CT）支付闭环（假 helper + 假 RPC，确定性）。
///
/// 覆盖两条 CT 通路：
/// 1. **明文输入 → `rcpux1` 收款**：输出盲化交服务器 CT 协处理器（`/ct/build`），
///    App 仅本地签名（对 helper 返回的 digest 做 ECDSA）并拼接 witness；
/// 2. **花费自身 CT 输出**：`getrawtransaction` → `/ct/xctout` → 本地
///    ECDH + HKDF 推导 rewind nonce → `/ct/rewind` 还原金额/盲因子，再作为
///    盲化输入交给 `/ct/build`。
///
/// 私钥永不出设备：假 helper 只接受客户端自算的 rewind nonce，不接触任何密钥。

class _FakeBiometric implements BiometricAuth {
  final bool result;
  _FakeBiometric(this.result);

  @override
  Future<bool> authenticate({required String reason}) async => result;

  @override
  Future<bool> hasEnrolledBiometrics() async => result;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<bool> setEnabled(bool value) async => true;
}

/// 罐装 RPC：UTXO 按地址返回；原始交易 hex 固定。
class _CannedRpc implements NativeRpcClient {
  final Map<String, List<NativeUtxo>> utxosByAddress;
  final String rawTxHex;
  String? broadcastHex;

  _CannedRpc({required this.utxosByAddress, this.rawTxHex = '00'});

  @override
  String get baseUrl => 'fake://native';

  @override
  Future<int?> getConfirmations(String txid) async => null;

  @override
  Future<Balance> getBalance(String address) async =>
      const Balance(asset: 'native', raw: '0', micro: 0);

  @override
  Future<List<NativeUtxo>> getUtxos(String address) async =>
      utxosByAddress[address] ?? const [];

  @override
  Future<String> getRawTransactionHex(String txidDisplayHex) async => rawTxHex;

  @override
  Future<String> broadcast(String signedTxHex) async {
    broadcastHex = signedTxHex;
    return 'ct_txid';
  }

  @override
  Future<List<TxRecord>> getHistory(String address, {int limit = 20}) async =>
      const [];

  @override
  Future<int> getBlockHeight() async => 0;

  @override
  String? scriptHexForAddress(String address) => null;

  @override
  Future<List<ScannedVout>> getBlockVouts(int height) async => const [];

  @override
  Future<List<ScannedVout>> getMempoolVouts({int cap = 200}) async => const [];

  @override
  Future<CtResolveResult> resolveCt({
    required String txHex,
    required String viewSeed,
    required String ownScriptPubKey,
  }) async {
    return const CtResolveResult(amountMicro: null, verified: false);
  }
}

/// 假 CT 协处理器（本地 HTTP），按命令路由并记录请求体。
class _FakeCtServer {
  late HttpServer _server;
  final Map<String, List<Map<String, dynamic>>> requests = {};

  Map<String, dynamic> Function(Map<String, dynamic>)? buildHandler;
  Map<String, dynamic> Function(Map<String, dynamic>)? rewindHandler;
  Map<String, dynamic> Function(Map<String, dynamic>)? xctoutHandler;

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final seg = req.uri.pathSegments;
      final cmd = seg.isEmpty ? '' : seg.last;
      final body =
          jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      requests.putIfAbsent(cmd, () => []).add(body);

      Map<String, dynamic> resp;
      if (cmd == 'build' && buildHandler != null) {
        resp = buildHandler!(body);
      } else if (cmd == 'rewind' && rewindHandler != null) {
        resp = rewindHandler!(body);
      } else if (cmd == 'xctout' && xctoutHandler != null) {
        resp = xctoutHandler!(body);
      } else {
        req.response.statusCode = 500;
        resp = {'error': 'no handler for $cmd'};
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(resp));
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

/// hex 字符串重复 n 次（Dart 无 String `*` 运算）。
String _rep(String unit, int n) => List.filled(n, unit).join();

String _hexOf(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String _hexOfList(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _bytesOf(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

/// 从 `rcpux1` 地址 payload 取内嵌压缩公钥（`0x00 || keyid(20) || pub(33)`）。
List<int> _pubOf(String address) =>
    Bech32.decodeToBytes(address, isBech32m: true).sublist(21, 54);

void main() {
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  // 另一个助记词派生的独立收款隐私地址（与自身隐私地址区分，避免脚本重合）。
  const recipientMnemonic =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';

  final me = Derivation(mnemonic);
  final sig = SignatureService();
  final plainAddr = me.deriveNativePlainAddress();
  final privAddr = me.deriveNativePrivateAddress();
  final plainPub = me.deriveNativePlainKey().spendPub;
  final plainPrivHex = _hexOf(me.deriveNativePlainKey().spendPriv);
  final plainPubHex = _hexOf(plainPub);
  final plainSpk = '0014${_hexOf(Derivation.hash160(plainPub))}';
  final ctPriv = me.deriveNativePrivateKey().spendPriv;
  final ctPrivHex = _hexOf(ctPriv);
  final ctPubHex = _hexOf(sig.compressedPubKey(ctPriv));

  final recipient = Derivation(recipientMnemonic).deriveNativePrivateAddress();

  // 真实收款/找零脚本（payment_service 锚定校验要求服务器返回的交易使用
  // 与本地意图一致的输出脚本，fake 必须如实模拟该行为）。
  final recipientSpk = '0014${_hexOfList(Derivation.hash160(Uint8List.fromList(_pubOf(recipient.value))))}';
  final changeSpk = '0014${_hexOf(Derivation.hash160(sig.compressedPubKey(ctPriv)))}';

  /// 假 helper 的「无 witness」交易：version || vin(1) || vout(收款/找零?/fee) || locktime。
  ///
  /// v3（CT）线格式与链上真实交易逐项核实（节点 decoderawtransaction 对照）：
  /// - 每输入尾部多 1 字节 0x00（helper 构造与链上已确认交易一致）；
  /// - 输出 = value || nonce || **rangeproof varbytes** || script varbytes
  ///   （rangeproof 在脚本之前，本链自定义 CTxOut 布局）；
  /// - 盲化输出：value 承诺 33B（`08||…`）|| nonce 承诺 33B（`04||…`，Path C）；
  /// - 显式 fee 输出：`01 || 8B 大端(金额)` || `00`（空 nonce）|| `00`（空
  ///   rangeproof）|| `00`（空脚本）。
  String le32(int v) => [
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String be64(int v) => [
        for (var i = 7; i >= 0; i--) (v >> (8 * i)) & 0xff,
      ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String fakeNoWitHex({
    required String prevTxidHex, // 64 hex（内部字节序）
    required int vout,
    required String recipientSpkHex,
    String? changeSpkHex,
    int feeMicro = 7290000,
  }) {
    // rangeproof 3500B：varint 0xfd + le16(3500=0x0dac)。
    final rp = 'fdac0d${_rep('ab', 3500)}';
    String ctOut(String spkHex) =>
        '08${_rep('c1', 32)}' // value 承诺 33B（假承诺，仅承载格式）
        '04${_rep('e2', 32)}' // Path C nonce 承诺 33B（假）
        '$rp' // rangeproof varbytes（先于脚本）
        '16$spkHex'; // script varbytes（22B）
    final outs = StringBuffer()..write(ctOut(recipientSpkHex));
    var n = 1;
    if (changeSpkHex != null) {
      outs.write(ctOut(changeSpkHex));
      n++;
    }
    // 显式 fee 输出（大端金额、空 nonce、空 rangeproof、空脚本）。
    outs.write('01${be64(feeMicro)}000000');
    n++;
    return '03000000'
        '01$prevTxidHex${le32(vout)}'
        '00' // scriptSig 空（P2WPKH）
        'fdffffff' // sequence
        '00' // v3 每输入尾字段
        '${n.toRadixString(16).padLeft(2, '0')}'
        '$outs'
        '00000000';
  }

  final noWitHex = fakeNoWitHex(
    prevTxidHex: _rep('11', 32),
    vout: 0,
    recipientSpkHex: recipientSpk,
    changeSpkHex: changeSpk,
  );
  final bodyHex = noWitHex.substring(8, noWitHex.length - 8);

  test('CT 收款：明文输入 → rcpux1 盲化输出 + 自身 CT 找零 + 本地签名拼接 witness', () async {
    final srv = _FakeCtServer();
    srv.buildHandler = (_) => {
          'tx_no_witness_hex': noWitHex,
          'vin': 1,
          'vout': 3,
          'fee_micro': 7290000,
          'digests': [_rep('ab', 32)],
          'outputs_meta': [],
        };
    await srv.start();
    addTearDown(srv.stop);

    final plainUtxo = NativeUtxo(
      prevTxid: Uint8List.fromList(List.generate(32, (i) => 0x11)),
      vout: 0,
      amountMicro: 200000000, // 2.0 RCPU
      scriptPubKey: plainSpk,
    );
    final rpc = _CannedRpc(utxosByAddress: {privAddr.value: const []});
    final service = PaymentService(
      biometric: _FakeBiometric(true),
      signature: sig,
      nativeRpc: rpc,
      ctHelper: CtHelperClient(endpoint: 'http://127.0.0.1:${srv.port}'),
    );

    final result = await service.confirmAndPay(
      toAddress: recipient.value,
      amountMicro: 150000000, // 1.5
      privateKeyHex: plainPrivHex,
      assetType: 'native',
      fromAddress: plainAddr.value,
      ctPrivateKeyHex: ctPrivHex,
      privateAddress: privAddr.value,
      utxos: [plainUtxo],
    );

    expect(result.ok, true, reason: 'CT 支付应成功：${result.error}');
    expect(rpc.broadcastHex, isNotNull);

    // /ct/build 请求形态：明文输入（blind 空）+ 收款 CT 输出 + 找零 CT 输出。
    final req = srv.requests['build']!.single;
    final in0 = (req['inputs'] as List).single as Map<String, dynamic>;
    expect(in0['txid_hex'], _rep('11', 32)); // 内部字节序
    expect(in0['vout'], 0);
    expect(in0['amount_micro'], 200000000);
    expect(in0['blind_hex'], ''); // 显式明文输入
    expect(in0['script_pubkey_hex'], plainSpk);

    final outs = (req['outputs'] as List).cast<Map<String, dynamic>>();
    expect(outs.length, 2);
    // 收款：脚本指向 rcpux1 内嵌 keyid，盲化公钥 = 其内嵌压缩公钥。
    expect(outs[0]['script_pubkey_hex'],
        '0014${_hexOfList(Derivation.hash160(Uint8List.fromList(_pubOf(recipient.value))))}');
    expect(outs[0]['blinding_pub_hex'], _hexOfList(_pubOf(recipient.value)));
    expect(outs[0]['amount_micro'], 150000000);
    // 找零：自身隐私路径公钥（盲化 key == spend key）。
    expect(outs[1]['script_pubkey_hex'],
        '0014${_hexOf(Derivation.hash160(sig.compressedPubKey(ctPriv)))}');
    expect(outs[1]['blinding_pub_hex'], ctPubHex);
    expect(outs[1]['amount_micro'], greaterThan(0));

    // 最终广播 hex（BIP144）：version + 0001(marker/flag) + vin/vout +
    // witness[sig,pub] + locktime。
    final b = rpc.broadcastHex!;
    expect(b.startsWith('030000000001'), true);
    expect(b.endsWith('00000000'), true);
    // witness 必须位于交易体（vin/vout）之后、locktime 之前。
    final inner = b.substring(12, b.length - 8);
    expect(inner.startsWith(bodyHex), true, reason: 'vin/vout 体应紧跟 marker/flag');
    final witHex = inner.substring(bodyHex.length);
    // 单输入栈：项数 2 = [签名, 压缩公钥]；公钥为栈末项（0x21 = 33 字节）。
    expect(witHex.startsWith('02'), true);
    expect(witHex.endsWith('21$plainPubHex'), true); // P2WPKH witness 含签名者公钥
  });

  test('花费自身 CT 输出：xctout → 本地 ECDH/HKDF → rewind → 作为盲化输入构造', () async {
    // 输出对应的密钥：盲化 key == spend key（同一把隐私路径公钥）。
    final ctPub = sig.compressedPubKey(ctPriv);
    final keyidHex = _hexOf(Derivation.hash160(ctPub));
    final ctSpk = '0014$keyidHex';

    // ephemeral 私钥/公钥（模拟上一笔交易输出携带的 Path C nonce，仅存 X 坐标）。
    final ephPriv =
        Uint8List.fromList(List.generate(32, (i) => (i + 3) & 0xff));
    final ephPub = sig.compressedPubKey(ephPriv);
    // 客户端应推导出的 rewind nonce：HKDF(ECDH(自身私钥, ephemeral 公钥), spk)。
    final expectedNonce = derivePathCNonce(
      ecdhSharedX(ctPriv, ephPub),
      Uint8List.fromList(_bytesOf(ctSpk)),
    );

    final srv = _FakeCtServer();
    srv.xctoutHandler = (_) => {
          'commitment_hex': '02${_rep('cc', 32)}',
          'rangeproof_hex': _rep('dd', 200),
          'nonce_prefix': 0x04, // Path C（X-only）
          'nonce_x_hex': _hexOf(ephPub.sublist(1, 33)),
          'script_pubkey_hex': ctSpk,
        };
    srv.rewindHandler = (body) {
      if (body['nonce_hex'] != _hexOf(expectedNonce)) {
        return {'error': 'rangeproof_rewind failed'};
      }
      return {'amount_micro': 200000000, 'blind_hex': _rep('aa', 32)};
    };
    srv.buildHandler = (_) => {
          'tx_no_witness_hex': fakeNoWitHex(
            prevTxidHex: _rep('22', 32),
            vout: 1,
            recipientSpkHex: recipientSpk,
            changeSpkHex: changeSpk,
          ),
          'vin': 1,
          'vout': 3,
          'fee_micro': 7290000,
          'digests': [_rep('ab', 32)],
          'outputs_meta': [],
        };
    await srv.start();
    addTearDown(srv.stop);

    final ctUtxo = NativeUtxo(
      prevTxid: Uint8List.fromList(List.generate(32, (i) => 0x22)),
      vout: 1,
      amountMicro: 0, // scantxoutset 读 CT 金额为 0
      scriptPubKey: ctSpk,
      privacy: 'ct',
    );
    final rpc = _CannedRpc(
      utxosByAddress: {privAddr.value: [ctUtxo]},
      rawTxHex: '0300deadbeef',
    );
    final service = PaymentService(
      biometric: _FakeBiometric(true),
      signature: sig,
      nativeRpc: rpc,
      ctHelper: CtHelperClient(endpoint: 'http://127.0.0.1:${srv.port}'),
    );

    final result = await service.confirmAndPay(
      toAddress: recipient.value,
      amountMicro: 150000000,
      privateKeyHex: plainPrivHex,
      assetType: 'native',
      fromAddress: plainAddr.value,
      ctPrivateKeyHex: ctPrivHex,
      privateAddress: privAddr.value,
      utxos: const [],
      ctUtxos: [ctUtxo],
    );

    expect(result.ok, true, reason: 'CT 花费应成功：${result.error}');

    // 拉取原始交易 → 拆 CT 字段。
    expect(srv.requests['xctout']!.single['tx_hex'], '0300deadbeef');
    expect(srv.requests['xctout']!.single['vout'], 1);
    // 客户端自算 nonce 命中（证明本地 ECDH + HKDF 与假 helper 期望一致）。
    expect(srv.requests['rewind']!.single['nonce_hex'], _hexOf(expectedNonce));

    // 构造请求：CT 输入携带 rewind 还原的金额与盲因子（非显式）。
    final in0 = (srv.requests['build']!.single['inputs'] as List).single
        as Map<String, dynamic>;
    expect(in0['txid_hex'], _rep('22', 32));
    expect(in0['amount_micro'], 200000000);
    expect(in0['blind_hex'], _rep('aa', 32));
    expect(in0['script_pubkey_hex'], ctSpk);
    expect(rpc.broadcastHex, isNotNull);
  });

  test('隐私地址 CT 余额解盲：金额 0 的盲化输出本地 rewind + 代理已解盲出账直接计入', () async {
    final ctPub = sig.compressedPubKey(ctPriv);
    final keyidHex = _hexOf(Derivation.hash160(ctPub));
    final ctSpk = '0014$keyidHex';

    final ephPriv =
        Uint8List.fromList(List.generate(32, (i) => (i + 5) & 0xff));
    final ephPub = sig.compressedPubKey(ephPriv);
    final expectedNonce = derivePathCNonce(
      ecdhSharedX(ctPriv, ephPub),
      Uint8List.fromList(_bytesOf(ctSpk)),
    );

    final srv = _FakeCtServer();
    srv.xctoutHandler = (_) => {
          'commitment_hex': '02${_rep('cc', 32)}',
          'rangeproof_hex': _rep('dd', 200),
          'nonce_prefix': 0x04,
          'nonce_x_hex': _hexOf(ephPub.sublist(1, 33)),
          'script_pubkey_hex': ctSpk,
        };
    srv.rewindHandler = (body) => body['nonce_hex'] == _hexOf(expectedNonce)
        ? {'amount_micro': 200000000, 'blind_hex': _rep('aa', 32)}
        : {'error': 'rangeproof_rewind failed'};
    await srv.start();
    addTearDown(srv.stop);

    // 盲化输出：scantxoutset 读金额为 0，须本地解盲。
    final blinded = NativeUtxo(
      prevTxid: Uint8List.fromList(List.generate(32, (i) => 0x33)),
      vout: 2,
      amountMicro: 0,
      scriptPubKey: ctSpk,
      privacy: 'ct',
    );
    // 代理已 unblind 的出账：直接计入，不再 rewind。
    final already = NativeUtxo(
      prevTxid: Uint8List.fromList(List.generate(32, (i) => 0x44)),
      vout: 0,
      amountMicro: 300000000,
      scriptPubKey: ctSpk,
      privacy: 'ct',
    );
    final rpc = _CannedRpc(
      utxosByAddress: {privAddr.value: [blinded, already]},
      rawTxHex: '0300deadbeef',
    );
    final service = NativeService(
      rpc,
      ctHelper: CtHelperClient(endpoint: 'http://127.0.0.1:${srv.port}'),
    );

    final b = await service.getPrivateBalance(
      privateAddress: privAddr.value,
      spendPriv32: ctPriv,
    );
    expect(b.micro, 500000000, reason: 'CT 余额应为 2.0（解盲）+ 3.0（代理）RCPU');
    expect(b.raw, '5.00000000');
    // 客户端自算 nonce 命中，且已解出的输出被缓存。
    expect(srv.requests['xctout']!.length, 1);
    expect(srv.requests['rewind']!.length, 1);

    final b2 = await service.getPrivateBalance(
      privateAddress: privAddr.value,
      spendPriv32: ctPriv,
    );
    expect(b2.micro, 500000000);
    expect(srv.requests['rewind']!.length, 1, reason: '缓存命中后不应重复解盲');
  });
}
