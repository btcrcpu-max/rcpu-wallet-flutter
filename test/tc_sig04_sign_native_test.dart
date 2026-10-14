import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:rcpu_wallet/core/crypto/bip340.dart';
import 'package:rcpu_wallet/core/crypto/bip341.dart';
import 'package:rcpu_wallet/core/crypto/native_tx.dart';
import 'package:rcpu_wallet/core/crypto/signature.dart';

/// TC-SIG-04（新）：`signNative` 真实实现闭环。
///
/// 验收：交易解析 → BIP341 key-path sighash → BIP340 签名 → witness 写回 →
/// 序列化 → 独立解析 + 独立验签，全链路一致；金额篡改必然验签失败；
/// 缺 prevOuts 上下文时给出明确错误指引。
void main() {
  // 固定测试私钥（BIP340 向量 #1 私钥：B7E151...，确定性）。
  final privHex = 'b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef';

  NativeTx buildSpendTx() {
    final xOnly = Bip340.xOnlyFromPub(Bip340.pubKeyFromPriv(_hex(privHex)));
    return NativeTx(
      version: 2,
      inputs: [
        NativeTxIn(
          prevTxid: Uint8List.fromList(List.generate(32, (i) => i)), // 固定假 txid
          prevVout: 0,
          scriptSig: Uint8List(0),
          sequence: 0xfffffffd, // 无 locktime 约束
        ),
      ],
      outputs: [
        NativeTxOut(
          value: BigInt.from(99000000), // 0.99 RCPU
          scriptPubKey: Bip341.p2trScriptPubKey(xOnly), // 收款为发给同 pub（自回合）
        ),
      ],
      locktime: 0,
    );
  }

  NativePrevOut prevOutOf(NativeTx tx, BigInt amount) {
    final xOnly = Bip340.xOnlyFromPub(Bip340.pubKeyFromPriv(_hex(privHex)));
    return NativePrevOut(
      scriptPubKey: tx.inputs.isEmpty
          ? Bip341.p2trScriptPubKey(xOnly)
          : Bip341.p2trScriptPubKey(xOnly),
      amount: amount,
    );
  }

  group('TC-SIG-04 signNative 闭环', () {
    test('签名→序列化→独立解析→验签通过', () async {
      final tx = buildSpendTx();
      final txHex = NativeTxCodec.bytesToHex(tx.serialize());
      final prevOuts = [prevOutOf(tx, BigInt.from(100000000))]; // 1 RCPU

      final signed = await SignatureService().signNative(txHex, privHex,
          prevOuts: prevOuts);
      expect(signed, isNot(equals(txHex)));

      // 独立解析：witness 已写回 64B 签名。
      final parsed = NativeTxCodec.parseHex(signed);
      expect(parsed.hasWitness, true);
      expect(parsed.inputs.length, 1);
      expect(parsed.inputs[0].witness.length, 1);
      expect(parsed.inputs[0].witness[0].length, 64);

      // 独立验签：重算 sighash → BIP340 verify。
      final xOnly = Bip340.xOnlyFromPub(Bip340.pubKeyFromPriv(_hex(privHex)));
      final sighash =
          Bip341.taprootKeyPathSighash(tx: parsed, prevOuts: prevOuts, inputIndex: 0);
      expect(Bip340.verify(xOnly, sighash, parsed.inputs[0].witness[0]), true);
    });

    test('金额篡改 → 验签失败（sighash 绑定 prevout amount）', () async {
      final tx = buildSpendTx();
      final txHex = NativeTxCodec.bytesToHex(tx.serialize());
      final signed = await SignatureService().signNative(txHex, privHex,
          prevOuts: [prevOutOf(tx, BigInt.from(100000000))]);

      final parsed = NativeTxCodec.parseHex(signed);
      final xOnly = Bip340.xOnlyFromPub(Bip340.pubKeyFromPriv(_hex(privHex)));
      // 用篡改后的金额（99999999）重算 sighash → 验签必须失败。
      final wrongSighash = Bip341.taprootKeyPathSighash(
          tx: parsed, prevOuts: [prevOutOf(tx, BigInt.from(99999999))], inputIndex: 0);
      expect(Bip340.verify(xOnly, wrongSighash, parsed.inputs[0].witness[0]), false);
    });

    test('缺失 prevOuts → 给出明确错误指引', () async {
      final tx = buildSpendTx();
      final txHex = NativeTxCodec.bytesToHex(tx.serialize());
      expect(
        () => SignatureService().signNative(txHex, privHex),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
            contains('prevOuts'))),
      );
    });

    test('prevOuts 数量不匹配 → 抛 ArgumentError', () async {
      final tx = buildSpendTx();
      final txHex = NativeTxCodec.bytesToHex(tx.serialize());
      expect(
        () => SignatureService().signNative(txHex, privHex, prevOuts: const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('非 P2TR prevout 脚本 → 抛格式错误', () async {
      final tx = buildSpendTx();
      final txHex = NativeTxCodec.bytesToHex(tx.serialize());
      final bad = NativePrevOut(
        scriptPubKey: Uint8List.fromList([0x00, 0x14, ...List.filled(20, 1)]), // P2PKH
        amount: BigInt.from(100000000),
      );
      expect(
        () => SignatureService().signNative(txHex, privHex, prevOuts: [bad]),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TC-SIG-04b Signature 字节级入口', () {
    test('signNative(sighash, priv) 产出可验签签名', () async {
      final xOnly = Bip340.xOnlyFromPub(Bip340.pubKeyFromPriv(_hex(privHex)));
      final msg = Uint8List.fromList(List.generate(32, (i) => i));
      final sig = await Signature().signNative(msg, _hex(privHex));
      expect(sig.length, 64);
      expect(Bip340.verify(xOnly, msg, sig), true);
    });
  });
}

Uint8List _hex(String hex) {
  final h = hex.trim();
  return Uint8List.fromList(List.generate(
      h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
}