import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rcpu_wallet/core/crypto/derivation.dart';
import 'package:rcpu_wallet/core/crypto/mnemonic.dart';
import 'package:rcpu_wallet/core/crypto/signature.dart';
import 'package:rcpu_wallet/core/models/address.dart';
import 'package:web3dart/web3dart.dart';

/// 派生与签名测试组（对应 docs/ct-test-cases.md 第 1、2 节）。
///
/// 覆盖：
/// - TC-DRV-01 明文地址结构（rcpu1 前缀；协议编码定版依赖 C2）
/// - TC-DRV-02 隐私地址结构（rcpux1 前缀；路径定版依赖 C1/C2）
/// - TC-DRV-03 派生确定性
/// - TC-DRV-04 助记词校验
/// - TC-SIG-01 BSC 签名校验（verifyBscSignature 已落地，可直接执行）
///
/// 🔴 阻塞用例（TC-DRV-05、TC-SIG-02/03 完整版）登记于 tc_blocked_test.dart。
const String kTestMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

void main() {
  group('TC-DRV-03 派生确定性', () {
    test('同一助记词三次派生明文地址完全一致', () {
      final a = Derivation(kTestMnemonic).deriveNativePlainAddress().value;
      final b = Derivation(kTestMnemonic).deriveNativePlainAddress().value;
      final c = Derivation(kTestMnemonic).deriveNativePlainAddress().value;
      expect(a, b);
      expect(b, c);
    });

    test('同一助记词三次派生 BSC 地址完全一致', () {
      final a = Derivation(kTestMnemonic).deriveBscAddress().value;
      final b = Derivation(kTestMnemonic).deriveBscAddress().value;
      expect(a, b);
    });
  });

  group('TC-DRV-04 助记词校验', () {
    test('合法 12 词助记词通过校验并可派生', () {
      expect(Mnemonic.isValid(kTestMnemonic), isTrue);
      expect(() => Derivation(kTestMnemonic), returnsNormally);
    });

    test('错词助记词拒绝（isValid false 且派生抛 FormatException）', () {
      const bad =
          'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon wrong';
      expect(Mnemonic.isValid(bad), isFalse);
      expect(() => Derivation(bad), throwsFormatException);
    });
  });

  group('TC-DRV-01/02 地址结构（定版依赖 C1/C2）', () {
    test('明文地址：rcpu1 前缀 + plain 类型', () {
      final addr = Derivation(kTestMnemonic).deriveNativePlainAddress();
      expect(addr.value.startsWith(Address.plainPrefix), isTrue);
      expect(addr.type, 'plain');
      expect(addr.isPlain, isTrue);
    });

    test('隐私地址：rcpux1 前缀 + private 类型', () {
      final addr = Derivation(kTestMnemonic).deriveNativePrivateAddress();
      expect(addr.value.startsWith(Address.privatePrefix), isTrue);
      expect(addr.type, 'private');
      expect(addr.isPrivate, isTrue);
    });

    test('明文与隐私地址互不相同', () {
      final d = Derivation(kTestMnemonic);
      expect(d.deriveNativePlainAddress().value,
          isNot(d.deriveNativePrivateAddress().value));
    });
  });

  group('TC-SIG-01 BSC 签名校验（verifyBscSignature 已落地）', () {
    test('正确签名：恢复地址 == 派生 BSC 地址', () async {
      final d = Derivation(kTestMnemonic);
      final bscAddress = d.deriveBscAddress().value;
      final privateKey = EthPrivateKey(d.deriveKey(Derivation.bscPath).privateKey!);
      final message = Uint8List.fromList(utf8.encode('RCPU payment 1.5'));

      final sig = privateKey.signPersonalMessageToUint8List(message);
      final ok = Signature().verifyBscSignature(message, sig, bscAddress);

      expect(ok, isTrue);
    });

    test('篡改消息：校验失败', () async {
      final d = Derivation(kTestMnemonic);
      final bscAddress = d.deriveBscAddress().value;
      final privateKey = EthPrivateKey(d.deriveKey(Derivation.bscPath).privateKey!);
      final message = Uint8List.fromList(utf8.encode('RCPU payment 1.5'));
      final evil = Uint8List.fromList(utf8.encode('RCPU payment 99'));

      final sig = privateKey.signPersonalMessageToUint8List(message);
      final ok = Signature().verifyBscSignature(evil, sig, bscAddress);

      expect(ok, isFalse);
    });

    test('错误地址：校验失败（大小写不敏感）', () async {
      final d = Derivation(kTestMnemonic);
      final bscAddress = d.deriveBscAddress().value;
      // 同路径派生第 2 个账号（m/44'/60'/0'/0/1）的地址作为错误地址
      final other = d.deriveKey("m/44'/60'/0'/0/1");
      final otherAddress = EthPrivateKey(other.privateKey!).address.hexEip55;
      final privateKey = EthPrivateKey(d.deriveKey(Derivation.bscPath).privateKey!);
      final message = Uint8List.fromList(utf8.encode('RCPU payment 1.5'));

      final sig = privateKey.signPersonalMessageToUint8List(message);
      final ok = Signature()
          .verifyBscSignature(message, sig, otherAddress.toUpperCase());

      expect(ok, isFalse);
      expect(otherAddress, isNot(bscAddress));
    });

    test('签名长度非法（非 65 字节）：直接返回 false', () async {
      final d = Derivation(kTestMnemonic);
      final bscAddress = d.deriveBscAddress().value;
      final message = Uint8List.fromList(utf8.encode('RCPU payment 1.5'));
      final bad = Uint8List.fromList([1, 2, 3]);

      final ok = Signature().verifyBscSignature(message, bad, bscAddress);
      expect(ok, isFalse);
    });
  });
}