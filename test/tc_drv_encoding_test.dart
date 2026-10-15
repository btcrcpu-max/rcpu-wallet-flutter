import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rcpu_wallet/core/crypto/bech32.dart';
import 'package:rcpu_wallet/core/crypto/derivation.dart';

/// bech32 / bech32m 编解码 + Path C 地址编码单元测试。
///
/// 覆盖：
/// - BIP173 官方向量（BC1QW...）解码结构
/// - bech32 / bech32m 往返编码一致性
/// - 两种校验常量不混用（交叉解码必须失败）
/// - 隐私地址 `rcpux1`：bech32m，payload = `0x00 || keyid(20B) || pub(33B)`（54B）
/// - 明文地址 `rcpu1`：bech32，payload = `0x00 || keyid(20B)`（21B）
/// - NativeKeyBundle 确定性派生与 keyid 自洽
void main() {
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';

  group('Bech32 编解码（BIP173 官方向量）', () {
    test('BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4 解码结构正确', () {
      final d = Bech32.decode(
        'BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4',
        isBech32m: false,
      );
      expect(d.hrp, 'bc');
      // BIP173：witness version 是单个 5-bit 值（0x00），
      // 其余 32 个 5-bit 值（160 bits）严格还原 20 字节 witness program。
      expect(d.data[0], 0x00);
      final program =
          Bech32.convertBits(Uint8List.fromList(d.data.sublist(1)), 5, 8,
              pad: false);
      expect(program, <int>[
        0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, //
        0x54, 0x94, 0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, //
        0xf1, 0x43, 0x3b, 0xd6,
      ]);
      // scriptPubKey = OP_0 || OP_PUSHBYTES_20 || program（22B）
      final spk = [0x00, 0x14, ...program];
      expect(spk.length, 22);
    });

    test('bech32 往返：encode 后可 decode 还原', () {
      final payload = Uint8List.fromList(
          List.generate(20, (i) => (i * 7) & 0xff));
      final encoded = Bech32.encode('rcpu', payload, bech32m: false);
      final decoded = Bech32.decode(encoded,
          isBech32m: false);
      expect(decoded.hrp, 'rcpu');
      expect(
        Bech32.convertBits(decoded.data, 5, 8, pad: false),
        payload,
      );
    });

    test('bech32m 往返：encode 后可 decode 还原', () {
      final payload = Uint8List.fromList(
          List.generate(54, (i) => (i * 13) & 0xff));
      final encoded = Bech32.encode('rcpux', payload, bech32m: true);
      final decoded = Bech32.decode(encoded,
          isBech32m: true);
      expect(decoded.hrp, 'rcpux');
      expect(
        Bech32.convertBits(decoded.data, 5, 8, pad: false),
        payload,
      );
    });

    test('bech32 与 bech32m 不可混用（交叉解码抛 FormatException）', () {
      final payload = Uint8List.fromList(
          List.generate(54, (i) => (i * 13) & 0xff));
      final encodedM =
          Bech32.encode('rcpux', payload, bech32m: true);
      final encodedPlain =
          Bech32.encode('rcpu', payload.sublist(0, 21), bech32m: false);
      // bech32m 编码用 bech32 校验解码必须失败
      expect(() => Bech32.decode(encodedM, isBech32m: false),
          throwsFormatException);
      // bech32 编码用 bech32m 校验解码必须失败
      expect(() => Bech32.decode(encodedPlain, isBech32m: true),
          throwsFormatException);
    });

    test('非法输入拒绝：缺分隔符 / 非法字符', () {
      expect(() => Bech32.decode('noSeparatorHere', isBech32m: false),
          throwsFormatException);
      expect(() => Bech32.decode('rcpu1zzzzzzzzzz0!', isBech32m: false),
          throwsFormatException);
    });
  });

  group('Path C 地址编码（C2 已解锁）', () {
    test('隐私地址 rcpux1 为 bech32m，payload 54B 结构正确', () {
      final d = Derivation(mnemonic);
      final addr = d.deriveNativePrivateAddress().value;
      expect(addr.startsWith('rcpux1'), isTrue);

      final decoded = Bech32.decode(addr, isBech32m: true);
      expect(decoded.hrp, Derivation.confidentialHrp);
      final payload = Bech32.convertBits(decoded.data, 5, 8, pad: false);
      expect(payload.length, 54);
      expect(payload[0], Derivation.confidentialVersion);

      final bundle = d.deriveNativePrivateKey();
      // payload = 0x00 || keyid(20B) || spendPub(33B)
      expect(payload.sublist(1, 21), bundle.keyid);
      expect(payload.sublist(21, 54), bundle.spendPub);
    });

    test('明文地址 rcpu1 为 bech32，payload 21B 结构正确', () {
      final d = Derivation(mnemonic);
      final addr = d.deriveNativePlainAddress().value;
      expect(addr.startsWith('rcpu1'), isTrue);

      final decoded = Bech32.decode(addr, isBech32m: false);
      expect(decoded.hrp, Derivation.plainHrp);
      final payload = Bech32.convertBits(decoded.data, 5, 8, pad: false);
      expect(payload.length, 21);
      expect(payload[0], Derivation.confidentialVersion);

      final bundle = d.deriveNativePlainKey();
      expect(payload.sublist(1, 21), bundle.keyid);
    });
  });

  group('NativeKeyBundle 派生', () {
    test('同一助记词派生原语确定性一致，keyid 自洽', () {
      final bundle1 = Derivation(mnemonic).deriveNativePlainKey();
      final bundle2 = Derivation(mnemonic).deriveNativePlainKey();
      expect(bundle1.spendPriv, bundle2.spendPriv);
      expect(bundle1.spendPub, bundle2.spendPub);
      expect(bundle1.keyid, bundle2.keyid);
      expect(bundle1.keyidValid, isTrue);
      expect(bundle1.spendPub.length, 33);
      expect(bundle1.keyid.length, 20);
    });

    test('明文与隐私密钥组互不相同', () {
      final d = Derivation(mnemonic);
      final plain = d.deriveNativePlainKey();
      final priv = d.deriveNativePrivateKey();
      expect(plain.spendPub, isNot(priv.spendPub));
      expect(plain.keyid, isNot(priv.keyid));
    });
  });
}