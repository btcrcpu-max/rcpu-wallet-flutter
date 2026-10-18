import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:rcpu_wallet/core/biometric/biometric_auth.dart';
import 'package:rcpu_wallet/core/crypto/bip340.dart';
import 'package:rcpu_wallet/core/crypto/bip341.dart';
import 'package:rcpu_wallet/core/crypto/derivation.dart';
import 'package:rcpu_wallet/core/crypto/native_tx.dart';
import 'package:rcpu_wallet/core/crypto/signature.dart';
import 'package:rcpu_wallet/core/models/balance.dart';
import 'package:rcpu_wallet/core/models/ct_resolve_result.dart';
import 'package:rcpu_wallet/core/models/native_utxo.dart';
import 'package:rcpu_wallet/core/models/tx_record.dart';
import 'package:rcpu_wallet/core/network/native_rpc.dart';
import 'package:rcpu_wallet/features/payment/payment_service.dart';

/// TC-PAY-01 buildNativeTxHex 交易构造（真实 UTXO 选择 / 输出 / fee / 降级）
/// + TC-PAY-02 get_utxos 请求形态。
///
/// v0.4.7 纯机密模式：明文目标地址由 `confirmAndPay` 直接拒绝（策略锁定用例）；
/// 构造闭环改经公开 `buildNativeTxHex` + 真实 `SignatureService` 直测，
/// 广播侧不再触发。复用真实 `Derivation` 派生密钥组（地址与私钥同源）。

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
  Future<void> setEnabled(bool value) async {}
}

class _RecordingNativeRpc implements NativeRpcClient {
  final List<NativeUtxo> utxos;
  String? lastBroadcastHex;
  String? lastUtxoAddress;

  _RecordingNativeRpc(this.utxos);

  @override
  String get baseUrl => 'fake://native';

  @override
  Future<int?> getConfirmations(String txid) async => null;

  @override
  Future<Balance> getBalance(String address) async =>
      const Balance(asset: 'native', raw: '0', micro: 0);

  @override
  Future<List<NativeUtxo>> getUtxos(String address) async {
    lastUtxoAddress = address;
    return utxos;
  }

  @override
  Future<String> getRawTransactionHex(String txidDisplayHex) async =>
      throw UnimplementedError('明文构造不拉取原始交易');

  @override
  Future<String> broadcast(String signedTxHex) async {
    lastBroadcastHex = signedTxHex;
    return 'fake_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<List<TxRecord>> getHistory(String address, {int limit = 20}) async => [];

  @override
  Future<int> getBlockHeight() async => 0;

  @override
  Future<CtResolveResult> resolveCt({
    required String txHex,
    required String viewSeed,
    required String ownScriptPubKey,
  }) async {
    return const CtResolveResult(amountMicro: null, verified: false);
  }
}

void main() {
  // 同一助记词派生明文地址与花费私钥（地址/签名同源，保证闭环可验签）。
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  final derivation = Derivation(mnemonic);
  final keyBundle = derivation.deriveNativePlainKey();
  final plainAddress = derivation.deriveNativePlainAddress();
  final privHex =
      keyBundle.spendPriv.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // 同一把 key 的 P2TR 锁定脚本（可签名输入，path-c-spec §3）。
  final p2trSpkHex = _p2trScriptHex(keyBundle.spendPriv);

  NativeUtxo utxo(int amountMicro, String spkHex,
      {int vout = 0, int seed = 0}) {
    final txid = Uint8List.fromList(List.generate(32, (i) => (i + seed) & 0xff));
    return NativeUtxo(
      prevTxid: txid,
      vout: vout,
      amountMicro: amountMicro,
      scriptPubKey: spkHex,
    );
  }

  group('TC-PAY-01 原生交易构造闭环（纯机密模式：构造器直测）', () {
    // v0.4.7 起原生付款仅受理机密地址：confirmAndPay 对明文目标直接拒绝；
    // 明文 v2 构造器（buildNativeTxHex）保留（wRCPU 桥路径复用），
    // 本组改为直测构造 + signNative 闭环，并锁定纯机密拒绝策略。

    test('明文目标地址 → 拒绝（纯机密策略，不构造不广播）', () async {
      final rpc = _RecordingNativeRpc([
        utxo(150000000, p2trSpkHex),
      ]);
      final service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: SignatureService(),
        nativeRpc: rpc,
      );
      final result = await service.confirmAndPay(
        toAddress: plainAddress.value,
        amountMicro: 100000000,
        privateKeyHex: privHex,
        assetType: 'native',
        fromAddress: plainAddress.value,
      );
      expect(result.ok, false);
      expect(result.error, contains('仅支持机密付款'));
      expect(rpc.lastBroadcastHex, isNull);
    });

    test('单输入：输出金额 / 找零 / fee / P2WPKH 脚本 / witness 64B', () async {
      final rpc = _RecordingNativeRpc([
        utxo(150000000, p2trSpkHex), // 1.5 RCPU
      ]);
      final service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: SignatureService(),
        nativeRpc: rpc,
      );
      final built = await service.buildNativeTxHex(
        toAddress: plainAddress.value,
        amountMicro: 100000000, // 1.0 RCPU
        fromAddress: plainAddress.value,
        utxos: rpc.utxos,
        feeRateMicroPerByte: PaymentService.defaultFeeRateMicroPerByte,
      );
      final signed = await SignatureService()
          .signNative(built.txHex, privHex, prevOuts: built.prevOuts);

      final tx = NativeTxCodec.parseHex(signed);
      expect(tx.inputs.length, 1);
      expect(tx.outputs.length, 2);

      // 输出 0：收款 1.0 RCPU，P2WPKH 22B（0x00 0x14 || h160）
      expect(tx.outputs[0].value, BigInt.from(100000000));
      expect(tx.outputs[0].scriptPubKey.length, 22);
      expect(tx.outputs[0].scriptPubKey[0], 0x00);
      expect(tx.outputs[0].scriptPubKey[1], 0x14);

      // 输出 1：找零 = 入 - 出 - fee，0 < change < 0.5 RCPU
      final change = tx.outputs[1].value;
      expect(change, greaterThan(BigInt.zero));
      expect(change, lessThan(BigInt.from(50000000)));
      expect(tx.outputs[1].scriptPubKey, tx.outputs[0].scriptPubKey);

      // fee > 0（总额守恒）
      final fee = BigInt.from(150000000) - BigInt.from(100000000) - change;
      expect(fee, greaterThan(BigInt.zero));

      // witness：P2TR key-path 单元素 64B Schnorr 签名
      expect(tx.hasWitness, true);
      expect(tx.inputs[0].witness.length, 1);
      expect(tx.inputs[0].witness[0].length, 64);
    });

    test('升序最小足够集合：不暴露全部余额（多输入按需凑足）', () async {
      final rpc = _RecordingNativeRpc([
        utxo(90000000, p2trSpkHex, seed: 1), // 0.9（大额在前）
        utxo(60000000, p2trSpkHex, seed: 2), // 0.6
        utxo(50000000, p2trSpkHex, seed: 3), // 0.5
      ]);
      final service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: SignatureService(),
        nativeRpc: rpc,
      );
      final built = await service.buildNativeTxHex(
        toAddress: plainAddress.value,
        amountMicro: 120000000, // 1.2
        fromAddress: plainAddress.value,
        utxos: rpc.utxos,
        feeRateMicroPerByte: PaymentService.defaultFeeRateMicroPerByte,
      );
      final signed = await SignatureService()
          .signNative(built.txHex, privHex, prevOuts: built.prevOuts);
      final tx = NativeTxCodec.parseHex(signed);
      // 升序累加：0.5 + 0.6 = 1.1 仍不足（+fee）→ 需 3 输入
      expect(tx.inputs.length, 3);
      // 交易体不含输入金额；通过输入数 + 输出总额守恒间接验证选择正确：
      // 出 = 1.2 + change + fee，change = 2.0 - 1.2 - fee ∈ (0, 0.8)
      final change = tx.outputs[1].value;
      expect(change, greaterThan(BigInt.zero));
      expect(change, lessThan(BigInt.from(80000000)));
    });

    test('余额不足 → 明确失败（不广播）', () async {
      final rpc = _RecordingNativeRpc([
        utxo(80000000, p2trSpkHex), // 0.8
      ]);
      final service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: SignatureService(),
        nativeRpc: rpc,
      );
      await expectLater(
        service.buildNativeTxHex(
          toAddress: plainAddress.value,
          amountMicro: 100000000, // 1.0
          fromAddress: plainAddress.value,
          utxos: rpc.utxos,
          feeRateMicroPerByte: PaymentService.defaultFeeRateMicroPerByte,
        ),
        throwsA(predicate((e) => e.toString().contains('余额不足'))),
      );
      expect(rpc.lastBroadcastHex, isNull);
    });

    test('隐私收款 → 降级提示（fail-closed，不静默降明文）', () async {
      final rpc = _RecordingNativeRpc([
        utxo(150000000, p2trSpkHex),
      ]);
      final service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: SignatureService(),
        nativeRpc: rpc,
      );
      final result = await service.confirmAndPay(
        toAddress: 'rcpux1yqspn06cfhvdw5gk9yvrvx9a3urldslnvl9p4mmwgmz6mvef2lq2704mp0cruc',
        amountMicro: 100000000,
        privateKeyHex: privHex,
        assetType: 'native',
        fromAddress: plainAddress.value,
      );
      expect(result.ok, false);
      expect(result.error, contains('CT 代理'));
      expect(rpc.lastBroadcastHex, isNull);
    });

    test('明文 P2WPKH 输入 → 成功构造签名（BIP143/ECDSA 路径）', () async {
      // P2WPKH（0x00 0x14 || h160）为 BIP84 明文地址的链上实际形态，
      // v0.3.6 起与 P2TR 并列为可签名输入。
      final p2wpkhSpk = '0014${'11' * 20}';
      final rpc = _RecordingNativeRpc([
        utxo(150000000, p2wpkhSpk),
      ]);
      final service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: SignatureService(),
        nativeRpc: rpc,
      );
      final built = await service.buildNativeTxHex(
        toAddress: plainAddress.value,
        amountMicro: 100000000,
        fromAddress: plainAddress.value,
        utxos: rpc.utxos,
        feeRateMicroPerByte: PaymentService.defaultFeeRateMicroPerByte,
      );
      final signed = await SignatureService()
          .signNative(built.txHex, privHex, prevOuts: built.prevOuts);
      final tx = NativeTxCodec.parseHex(signed);
      expect(tx.hasWitness, true);
      // P2WPKH witness = [DER 签名(+0x01 sighash), 33B 压缩公钥]
      expect(tx.inputs[0].witness.length, 2);
      expect(tx.inputs[0].witness[1].length, 33);
      expect(tx.inputs[0].witness[0].last, 0x01);
    });

    test('锁定后未确认输出不可花费（confirmed=false 被过滤）', () async {
      final unconfirmed = NativeUtxo(
        prevTxid: Uint8List.fromList(List.generate(32, (i) => i)),
        vout: 0,
        amountMicro: 150000000,
        scriptPubKey: p2trSpkHex,
        confirmed: false,
      );
      final rpc = _RecordingNativeRpc([unconfirmed]);
      final service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: SignatureService(),
        nativeRpc: rpc,
      );
      await expectLater(
        service.buildNativeTxHex(
          toAddress: plainAddress.value,
          amountMicro: 100000000,
          fromAddress: plainAddress.value,
          utxos: rpc.utxos,
          feeRateMicroPerByte: PaymentService.defaultFeeRateMicroPerByte,
        ),
        throwsA(predicate((e) => e.toString().contains('没有可花费'))),
      );
      expect(rpc.lastBroadcastHex, isNull);
    });
  });

  group('TC-PAY-02 get_utxos 请求形态', () {
    test('method=get_utxos / id=5 / params=[address] / 解析金额与脚本', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final requests = <Map<String, dynamic>>[];
      final sub = server.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join())
            as Map<String, dynamic>;
        requests.add(body);
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': [
              {
                'txid': '00' * 32,
                'vout': 0,
                'amountMicro': 250000000,
                'scriptPubKey': '5120${'11' * 32}',
                'confirmed': true,
                'privacy': 'ct',
              },
            ],
          }));
        await req.response.close();
      });

      final client = NativeRpcClient(baseUrl: 'http://127.0.0.1:${server.port}');
      final utxos = await client.getUtxos(plainAddress.value);
      await sub.cancel();
      await server.close(force: true);

      expect(requests.single['method'], 'get_utxos');
      expect(requests.single['id'], 5);
      expect((requests.single['params'] as List).single, plainAddress.value);

      expect(utxos.length, 1);
      expect(utxos.single.amountMicro, 250000000);
      expect(utxos.single.privacy, 'ct');
      expect(utxos.single.isP2trInput, true);
      expect(utxos.single.prevTxid.length, 32);
    });
  });
}

/// 同一把 key 的 P2TR 锁定脚本 hex（`0x51 0x20 || xonly`）。
String _p2trScriptHex(Uint8List priv32) {
  final pub = Bip340.pubKeyFromPriv(priv32);
  final xOnly = Bip340.xOnlyFromPub(pub);
  return Bip341.p2trScriptPubKey(xOnly)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}