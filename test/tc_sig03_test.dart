import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:rcpu_wallet/core/biometric/biometric_auth.dart';
import 'package:rcpu_wallet/core/crypto/native_tx.dart';
import 'package:rcpu_wallet/core/crypto/signature.dart';
import 'package:rcpu_wallet/core/models/balance.dart';
import 'package:rcpu_wallet/core/models/ct_resolve_result.dart';
import 'package:rcpu_wallet/core/models/native_utxo.dart';
import 'package:rcpu_wallet/core/models/tx_record.dart';
import 'package:rcpu_wallet/core/network/native_rpc.dart';
import 'package:rcpu_wallet/features/payment/payment_service.dart';

/// TC-SIG-03 降级路径测试（占位实现下可直接运行）。
///
/// 依赖：`SignatureService.signNative` 为占位（C1/C2 未定），本用例校验两层降级：
/// 1. 隐私地址 + 指纹成功 + 未配置 CT 代理 → 捕获 `UnimplementedError`
///    → 降级提示「隐私地址支付需 CT 代理」；
/// 2. 指纹取消 → 直接失败，不进入签名链路（不产生签名对象）。
/// 本文件不依赖真实生物识别 / RPC，全部以 fake 注入。
class _FakeBiometric implements BiometricAuth {
  final bool authResult;
  _FakeBiometric(this.authResult);

  @override
  Future<bool> authenticate({required String reason}) async => authResult;

  @override
  Future<bool> hasEnrolledBiometrics() async => authResult;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool value) async {}
}

class _FakeSignature implements SignatureService {
  @override
  Future<String> signNative(
    String txHex,
    String privateKeyHex, {
    List<NativePrevOut>? prevOuts,
  }) async {
    throw UnimplementedError(
      '原生签名算法待协议文档确认（C1/C2）。'
      '当前仅支持明文地址支付，请使用 rcpu1 地址。',
    );
  }

  @override
  Uint8List signEcdsaDigest(Uint8List privKey32, Uint8List digest32) =>
      Uint8List(0);

  @override
  Uint8List compressedPubKey(Uint8List privKey32) => Uint8List(0);
}

class _FakeNativeRpc implements NativeRpcClient {
  @override
  String get baseUrl => 'fake://native';

  @override
  Future<int?> getConfirmations(String txid) async => null;

  @override
  Future<Balance> getBalance(String address) async {
    throw UnimplementedError('TC-SIG-03 不涉及余额查询');
  }

  @override
  Future<List<NativeUtxo>> getUtxos(String address) async {
    throw UnimplementedError('TC-SIG-03 不涉及 UTXO 查询');
  }

  @override
  Future<String> getRawTransactionHex(String txidDisplayHex) async =>
      throw UnimplementedError('TC-SIG-03 不涉及原始交易拉取');

  @override
  Future<String> broadcast(String signedTxHex) async => 'fake_txid';

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
  group('TC-SIG-03 降级路径', () {
    late PaymentService service;

    setUp(() {
      service = PaymentService(
        biometric: _FakeBiometric(true),
        signature: _FakeSignature(),
        nativeRpc: _FakeNativeRpc(),
      );
    });

    test('隐私地址 + 指纹成功 → 降级提示', () async {
      final result = await service.confirmAndPay(
        toAddress: 'rcpux1xxxxxxxxxxxxxxxxxxxxxxxx',
        amountMicro: 150000000,
        privateKeyHex: '0xdeadbeef',
        assetType: 'native',
      );
      expect(result.ok, false);
      expect(result.error, contains('CT 代理'));
    });

    test('指纹取消 → 直接失败', () async {
      final cancelled = PaymentService(
        biometric: _FakeBiometric(false),
        signature: _FakeSignature(),
        nativeRpc: _FakeNativeRpc(),
      );
      final result = await cancelled.confirmAndPay(
        toAddress: 'rcpu1xxxxxxxxxxxxxxxxxxxxxxxx',
        amountMicro: 100000000,
        privateKeyHex: '0xdeadbeef',
        assetType: 'native',
      );
      expect(result.ok, false);
      expect(result.error, contains('指纹验证失败'));
    });
  });
}