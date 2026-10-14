import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

/// TC-SIG-02 HKDF/ECDH 层单测（对应 docs/path-c-spec.md §5 官方向量）。
///
/// 基于官方 `doc/ct-path-c.md` Appendix A（B1: ss）与 Appendix C（C1: view_seed /
/// rewind nonce）固定十六进制向量，验证 Path C KDF 层与官方向量逐字节一致。
///
/// 覆盖：
/// - `deriveViewSeed`（HKDF-Extract：salt="rcpu-pathc-v1"，ikm=ss，即
///   HMAC-SHA256(key="rcpu-pathc-v1", msg=ss)）
/// - `derivePathCNonce`（HKDF 全流程：ss -> view_seed -> rewind nonce）
/// - `deriveRewindNonceFromViewSeed`（HKDF-Expand：info=scriptPubKey||0x01||le64(64)，L=32）
/// - 不同 scriptPubKey 得到不同 nonce（info 绑定收付脚本，view_seed 不绑定）
///
/// 说明：本测试不依赖地址派生、不依赖代理，可直接验证 HKDF 层确定性，
/// 从而**部分解锁 TC-SIG-02**（签名向量层）；签名本体 `signNative`
/// 仍为占位，见 docs/ct-test-cases.md §2 与 docs/path-c-spec.md §4.4。
/// 占位集中在文件底部，待 `ct_resolver` 落地后迁移至 lib。
void main() {
  group('TC-SIG-02 Path C HKDF/ECDH（官方 Appendix A/C 向量）', () {
    // Appendix A（B1）共享秘密；Appendix C（C1）spk / 预期输出
    final ss =
        hexToBytes('8ff9563819af439784eff54bd65e65614b14c7fe66b6b2f6010a72ec681f38f0');
    final spkA = hexToBytes('00144242424242424242424242424242424242424242');
    final expectedNonce =
        hexToBytes('0dc418dc644de8e38a83aee9740f2d39a1c6792b81dcab208ccccb25de08c47c');
    final expectedViewSeed =
        hexToBytes('23f71d02deed10b0a9562200e8ef49951f2e5a2d775eb92d9fe0bda764fda1fe');

    test('DeriveViewSeed matches official vector', () {
      final viewSeed = deriveViewSeed(ss);
      expect(viewSeed, equals(expectedViewSeed));
    });

    test('DerivePathCNonce matches official vector', () {
      final nonce = derivePathCNonce(ss, spkA);
      expect(nonce, equals(expectedNonce));
    });

    test('DeriveRewindNonceFromViewSeed matches sender nonce', () {
      final viewSeed = deriveViewSeed(ss);
      final rewind = deriveRewindNonceFromViewSeed(viewSeed, spkA);
      expect(rewind, equals(expectedNonce));
    });

    test('Different scriptPubKey yields different nonce', () {
      final spkB = hexToBytes('0014aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      final nonceA = derivePathCNonce(ss, spkA);
      final nonceB = derivePathCNonce(ss, spkB);
      expect(nonceA, isNot(equals(nonceB)));
    });
  });
}

// --- 占位实现（按官方规范，待迁移至 lib/core/utils/ct_resolver.dart） ---

/// view_seed = HKDF-Extract(salt = "rcpu-pathc-v1", ikm = ss)
///            = HMAC-SHA256(key = "rcpu-pathc-v1", msg = ss)
Uint8List deriveViewSeed(Uint8List ss) {
  final salt = utf8.encode('rcpu-pathc-v1');
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(salt));
  return hmac.process(ss);
}

/// nonce = HKDF-Expand(PRK = view_seed,
///                     info = scriptPubKey || 0x01 || le64(64), L = 32)
/// 单块展开：T(1) = HMAC(PRK, info || 0x01)，取前 32 字节。
Uint8List deriveRewindNonceFromViewSeed(Uint8List viewSeed, Uint8List scriptPubKey) {
  final info = Uint8List.fromList([
    ...scriptPubKey,
    0x01,
    0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // le64(64)
  ]);
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(viewSeed));
  final block = hmac.process(Uint8List.fromList([...info, 0x01]));
  return block.sublist(0, 32);
}

/// nonce = HKDF 全流程：先 Extract 得到 view_seed，再 Expand 得到 rewind nonce。
Uint8List derivePathCNonce(Uint8List ss, Uint8List scriptPubKey) {
  final viewSeed = deriveViewSeed(ss);
  return deriveRewindNonceFromViewSeed(viewSeed, scriptPubKey);
}

Uint8List hexToBytes(String hex) => Uint8List.fromList(
    List.generate(hex.length ~/ 2, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));