import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import 'bip340.dart';
import 'native_tx.dart';

/// BIP341（Taproot）签名哈希计算，key-path 花费（SIGHASH_DEFAULT）。
///
/// 原生链 Path C 采用 P2TR（witness v1）+ BIP340 Schnorr 签名，
/// 签名消息为 BIP341 sighash（`docs/signnative-implementation.md` §5）。
///
/// 本实现覆盖 key-path + 无 annex（spend_type = 0x00）主场景：
/// ```
/// sigmsg = hash_type(1) || ext_flag(1) ||
///          hash_prevouts(32) || hash_amounts(32) || hash_scriptpubkeys(32) ||
///          hash_sequences(32) || hash_outputs(32) ||
///          spend_type(1) || input_index(4LE) ||
///          scriptpubkey(varint||bytes) || amount(8LE) || sequence(4LE) ||
///          key_version(1:0x00) || sighash_postfix(1:0x00)
/// sighash = TaggedHash("TapSighash", sigmsg)
/// ```
/// 其中 key path 时不含 tapleaf_hash；SIGHASH_DEFAULT（0x00）等价 ALL，
/// 包含全部输入/输出。
class Bip341 {
  /// SIGHASH_DEFAULT（等价 ALL，且签名无 hash_type 尾字节）。
  static const int sighashDefault = 0x00;

  /// hash_type：SIGHASH_DEFAULT。
  static const int _hashType = 0x00;

  /// spend_type：key path，无 annex。
  static const int _spendType = 0x00;

  /// 计算第 [inputIndex] 个输入的 BIP341 key-path sighash。
  ///
  /// [prevOuts] 与该输入一一对应（长度须等于输入的个数）：
  /// scriptPubKey 为 prevout 锁定脚本（P2TR：`0x51 0x20 || xonly32`，34 字节），
  /// amount 为 prevout 金额（8LE，原字节序）。
  static Uint8List taprootKeyPathSighash({
    required NativeTx tx,
    required List<NativePrevOut> prevOuts,
    required int inputIndex,
  }) {
    if (inputIndex < 0 || inputIndex >= tx.inputs.length) {
      throw RangeError('inputIndex 越界');
    }
    if (prevOuts.length != tx.inputs.length) {
      throw ArgumentError('prevOuts 长度须与输入个数一致');
    }

    final b = BytesBuilder();

    // hash_type + ext_flag（无 annex）
    b.add([_hashType, 0x00]);

    // hash_prevouts = SHA256(concat(outpoint))
    final prevOutBytes = BytesBuilder();
    for (final i in tx.inputs) {
      prevOutBytes.add(i.prevTxid);
      prevOutBytes.add(_le32(i.prevVout));
    }
    b.add(_sha256(prevOutBytes.toBytes()));

    // hash_amounts = SHA256(concat(amount 8LE))
    final amounts = BytesBuilder();
    for (final p in prevOuts) {
      amounts.add(_le64(p.amount));
    }
    b.add(_sha256(amounts.toBytes()));

    // hash_scriptpubkeys = SHA256(concat(varint||spk))
    final spks = BytesBuilder();
    for (final p in prevOuts) {
      spks.add(NativeTxCodec.encodeVarInt(p.scriptPubKey.length));
      spks.add(p.scriptPubKey);
    }
    b.add(_sha256(spks.toBytes()));

    // hash_sequences = SHA256(concat(sequence 4LE))
    final seqs = BytesBuilder();
    for (final i in tx.inputs) {
      seqs.add(_le32(i.sequence));
    }
    b.add(_sha256(seqs.toBytes()));

    // hash_outputs = SHA256(concat(value 8LE || varint||spk))
    final outs = BytesBuilder();
    for (final o in tx.outputs) {
      outs.add(_le64(o.value));
      outs.add(NativeTxCodec.encodeVarInt(o.scriptPubKey.length));
      outs.add(o.scriptPubKey);
    }
    b.add(_sha256(outs.toBytes()));

    // spend_type（key path，无 annex）
    b.add([_spendType]);

    // input_index (4LE)
    b.add(_le32(inputIndex));

    // 当前输入的 scriptpubkey、amount、sequence
    final input = tx.inputs[inputIndex];
    final prev = prevOuts[inputIndex];
    b.add(NativeTxCodec.encodeVarInt(prev.scriptPubKey.length));
    b.add(prev.scriptPubKey);
    b.add(_le64(prev.amount));
    b.add(_le32(input.sequence));

    // key-version（key path：0x00）+ sighash_postfix（无 annex：0x00）
    b.add([0x00, 0x00]);

    return Bip340.taggedHash('TapSighash', b.toBytes());
  }

  /// 标准 P2TR 锁定脚本：`0x51 0x20 || xonly32`。
  static Uint8List p2trScriptPubKey(Uint8List xOnly32) {
    if (xOnly32.length != 32) {
      throw ArgumentError('x-only 公钥必须为 32 字节');
    }
    return Uint8List.fromList([0x51, 0x20, ...xOnly32]);
  }

  /// 判断脚本是否为 P2TR（witness v1，34 字节 `0x51 0x20 || 32B`）。
  static bool isP2tr(Uint8List scriptPubKey) {
    return scriptPubKey.length == 34 &&
        scriptPubKey[0] == 0x51 &&
        scriptPubKey[1] == 0x20;
  }

  static Uint8List _sha256(Uint8List input) {
    final d = SHA256Digest();
    return d.process(input);
  }

  static Uint8List _le32(int value) =>
      Uint8List.fromList(List.generate(4, (i) => (value >> (8 * i)) & 0xff));

  static Uint8List _le64(BigInt value) {
    final out = Uint8List(8);
    var v = value;
    for (var i = 0; i < 8; i++) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }
}