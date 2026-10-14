import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rcpu_wallet/core/crypto/bip340.dart';

/// BIP340 Schnorr 单测（锚定 BIP-0340 官方 test-vectors）。
///
/// 覆盖：
/// - 官方向量 #0 / #1：sign（priv+aux+msg → 64B sig）逐字节一致；
/// - 官方向量 verify 通过；
/// - 篡改消息 / 篡改签名 → verify false；
/// - 公钥非曲线点 / 签名长度非法 → verify false；
/// - 私钥越界（0 / n）→ sign 抛 ArgumentError。
void main() {
  group('BIP340 官方向量（BIP-0340 test-vectors）', () {
    test('向量 #0：sign 输出与官方一致且 verify 通过', () {
      final seckey = _hex(
          '0000000000000000000000000000000000000000000000000000000000000003');
      final pubkey = _hex(
          'F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9');
      final aux = Uint8List(32);
      final msg = Uint8List(32);
      final expectedSig = _hex(
          'E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA82152'
          '5F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0');

      final sig = Bip340.sign(seckey, msg, auxRand32: aux);
      expect(sig, expectedSig);
      expect(Bip340.verify(pubkey, msg, sig), isTrue);
    });

    test('向量 #1：sign 输出与官方一致且 verify 通过', () {
      final seckey = _hex(
          'B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF');
      final pubkey = _hex(
          'DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659');
      final aux = _hex(
          '0000000000000000000000000000000000000000000000000000000000000001');
      final msg = _hex(
          '243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89');
      final expectedSig = _hex(
          '6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE3341'
          '8906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A');

      final sig = Bip340.sign(seckey, msg, auxRand32: aux);
      expect(sig, expectedSig);
      expect(Bip340.verify(pubkey, msg, sig), isTrue);
    });

    test('向量 #2（verify=false 锚点）：篡改消息 → false', () {
      final pubkey = _hex(
          'DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659');
      // 基于官方向量 #1 的合法组合，篡改消息最后 1 字节（89→90），
      // verify 必须返回 false。
      final sig = _hex(
          '6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE3341'
          '8906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A');
      final tampered = _hex(
          '243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C90');

      expect(Bip340.verify(pubkey, tampered, sig), isFalse);
    });
  });

  group('BIP340 边界与容错', () {
    late Uint8List seckey;
    late Uint8List pubkey;
    late Uint8List msg;

    setUp(() {
      seckey = _hex(
          'B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF');
      pubkey = _hex(
          'DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659');
      msg = Uint8List(32);
    });

    test('篡改签名单字节 → verify false', () {
      final sig = Bip340.sign(seckey, msg, auxRand32: Uint8List(32));
      final bad = Uint8List.fromList(sig);
      bad[10] = bad[10] ^ 0x01;
      expect(Bip340.verify(pubkey, msg, bad), isFalse);
    });

    test('签名长度非法 → verify false', () {
      expect(Bip340.verify(pubkey, msg, Uint8List(63)), isFalse);
      expect(Bip340.verify(pubkey, msg, Uint8List(65)), isFalse);
    });

    test('公钥不是曲线点（x 越界）→ verify false', () {
      final bad = Uint8List.fromList(pubkey);
      bad[0] = 0xff;
      bad[1] = 0xff;
      bad[2] = 0xff;
      final sig = Bip340.sign(seckey, msg, auxRand32: Uint8List(32));
      expect(Bip340.verify(bad, msg, sig), isFalse);
    });

    test('私钥越界（0 / n）→ sign 抛 ArgumentError', () {
      expect(() => Bip340.sign(Uint8List(32), msg), throwsArgumentError);
      final nBytes = _hex(
          'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141');
      expect(() => Bip340.sign(nBytes, msg), throwsArgumentError);
    });

    test('x-only 与压缩公钥互转', () {
      final pubComp = _hex(
          '02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659');
      final xOnly = Bip340.xOnlyFromPub(pubComp);
      expect(xOnly, pubkey);
    });
  });
}

Uint8List _hex(String s) => Uint8List.fromList(List.generate(
    s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));