import 'dart:typed_data';

/// 原生 RCPU 交易结构（Bitcoin 风格序列化，segwit 支持）。
///
/// 序列化布局（与 Bitcoin Core 一致）：
/// - 版本 4B LE
/// - 输入数 varint；每个输入：prevTxid(32) || prevVout(4LE) || scriptSigLen || scriptSig || seq(4LE)
/// - 输出数 varint；每个输出：value(8LE) || scriptLen || scriptPubKey
/// - 带 witness 时：标志 0x00 0x01 位于输入数之前（见 [NativeTx.hasWitness]）
/// - witness 栈（每输入：栈项数 varint + 每项：长度 varint + 字节）
/// - locktime 4B LE
///
/// 仅承载「交易结构与序列化」职责；sighash 计算见 `bip341.dart`。
class NativeTx {
  final int version;
  final List<NativeTxIn> inputs;
  final List<NativeTxOut> outputs;
  final int locktime;

  NativeTx({
    required this.version,
    required this.inputs,
    required this.outputs,
    required this.locktime,
  });

  bool get hasWitness => inputs.any((i) => i.witness.isNotEmpty);

  /// 完整序列化（含 witness）。
  Uint8List serialize() => NativeTxCodec.serialize(this);

  /// 仅序列化非 witness 部分（计算 sighash 用）。
  Uint8List serializeNoWitness() => NativeTxCodec.serialize(this, dropWitness: true);
}

/// 交易输入：outpoint + scriptSig + sequence + witness 栈。
class NativeTxIn {
  final Uint8List prevTxid; // 32B（内部字节序，与区块一致）
  final int prevVout;
  final Uint8List scriptSig;
  final int sequence;
  final List<Uint8List> witness;

  NativeTxIn({
    required this.prevTxid,
    required this.prevVout,
    required this.scriptSig,
    required this.sequence,
    List<Uint8List>? witness,
  }) : witness = witness ?? const [];

  bool get isTaproot => witness.any((w) => w.length == 64);
}

/// 交易输出：金额（8B LE）+ 锁定脚本。
class NativeTxOut {
  final BigInt value; // 原生金额（micro）
  final Uint8List scriptPubKey;

  NativeTxOut({required this.value, required this.scriptPubKey});
}

/// 花费输入所需的 prevout 数据（sighash 使用，交易体不含金额与脚本）。
///
/// 由 UTXO 选择层（_buildTxHex）填充：金额来自链上输出，scriptPubKey 为
/// 该输出的锁定脚本（P2TR 为 `0x51 0x20 || xonly_pub`，34B）。
class NativePrevOut {
  final Uint8List scriptPubKey;
  final BigInt amount; // micro

  NativePrevOut({required this.scriptPubKey, required this.amount});
}

/// 交易编解码（varint / 序列化 / 解析）。
class NativeTxCodec {
  /// varint 编码（Bitcoin CompactSize）。
  static Uint8List encodeVarInt(int value) {
    if (value < 0xfd) return Uint8List.fromList([value]);
    if (value <= 0xffff) {
      return Uint8List.fromList([0xfd, ..._le(value, 2)]);
    }
    if (value <= 0xffffffff) {
      return Uint8List.fromList([0xfe, ..._le(value, 4)]);
    }
    return Uint8List.fromList([0xff, ..._le(value, 8)]);
  }

  static Uint8List _le(int value, int len) {
    final out = Uint8List(len);
    for (var i = 0; i < len; i++) {
      out[i] = (value >> (8 * i)) & 0xff;
    }
    return out;
  }

  static Uint8List _le64(BigInt value) {
    final out = Uint8List(8);
    var v = value;
    for (var i = 0; i < 8; i++) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }

  /// 序列化交易；[dropWitness] 为 true 时输出无 witness 的标志位（CLTV/DEFAULT 之外
  /// 全部场景均可使用——原始序列化即为此形态）。
  static Uint8List serialize(NativeTx tx, {bool dropWitness = false}) {
    final b = BytesBuilder();
    b.add(_le(tx.version, 4));
    final wit = !dropWitness && tx.hasWitness;
    if (wit) {
      b.add([0x00, 0x01]); // marker + flag
    }
    b.add(encodeVarInt(tx.inputs.length));
    for (final i in tx.inputs) {
      b.add(i.prevTxid);
      b.add(_le(i.prevVout, 4));
      b.add(encodeVarInt(i.scriptSig.length));
      b.add(i.scriptSig);
      b.add(_le(i.sequence, 4));
    }
    b.add(encodeVarInt(tx.outputs.length));
    for (final o in tx.outputs) {
      b.add(_le64(o.value));
      b.add(encodeVarInt(o.scriptPubKey.length));
      b.add(o.scriptPubKey);
    }
    if (wit) {
      for (final i in tx.inputs) {
        b.add(encodeVarInt(i.witness.length));
        for (final item in i.witness) {
          b.add(encodeVarInt(item.length));
          b.add(item);
        }
      }
    }
    b.add(_le(tx.locktime, 4));
    return b.toBytes();
  }

  /// 解析交易 hex（可带 witness）。
  static NativeTx parseHex(String hex) {
    final raw = _hexToBytes(hex);
    return parse(raw);
  }

  /// 解析交易字节。
  static NativeTx parse(Uint8List raw) {
    var pos = 0;
    Uint8List take(int n) {
      if (pos + n > raw.length) {
        throw const FormatException('交易字节不足（截断）');
      }
      final out = Uint8List.fromList(raw.sublist(pos, pos + n));
      pos += n;
      return out;
    }

    BigInt takeLe64() {
      final bytes = take(8);
      var v = BigInt.zero;
      for (var i = 7; i >= 0; i--) {
        v = (v << 8) | BigInt.from(bytes[i]);
      }
      return v;
    }

    int takeLe(int n) {
      final bytes = take(n);
      var v = 0;
      for (var i = n - 1; i >= 0; i--) {
        v = (v << 8) | bytes[i];
      }
      return v;
    }

    int readVarInt() {
      final first = take(1)[0];
      if (first < 0xfd) return first;
      if (first == 0xfd) return takeLe(2);
      if (first == 0xfe) return takeLe(4);
      return takeLe(8);
    }

    final version = takeLe(4);

    var inputCount = readVarInt();
    var hasWitness = false;
    if (inputCount == 0) {
      // marker 0x00 + flag 0x01
      final flag = take(1)[0];
      if (flag != 0x01) {
        throw const FormatException('非法 witness 标志');
      }
      hasWitness = true;
      inputCount = readVarInt();
    }

    final inputs = <NativeTxIn>[];
    for (var i = 0; i < inputCount; i++) {
      final prevTxid = take(32);
      final prevVout = takeLe(4);
      final scriptLen = readVarInt();
      final scriptSig = take(scriptLen);
      final sequence = takeLe(4);
      inputs.add(NativeTxIn(
        prevTxid: prevTxid,
        prevVout: prevVout,
        scriptSig: scriptSig,
        sequence: sequence,
      ));
    }

    final outputCount = readVarInt();
    final outputs = <NativeTxOut>[];
    for (var i = 0; i < outputCount; i++) {
      final value = takeLe64();
      final scriptLen = readVarInt();
      final scriptPubKey = take(scriptLen);
      outputs.add(NativeTxOut(value: value, scriptPubKey: scriptPubKey));
    }

    if (hasWitness) {
      for (var i = 0; i < inputCount; i++) {
        final itemCount = readVarInt();
        final items = <Uint8List>[];
        for (var j = 0; j < itemCount; j++) {
          final len = readVarInt();
          items.add(take(len));
        }
        inputs[i].witness.addAll(items);
      }
    }

    final locktime = takeLe(4);
    if (pos != raw.length) {
      throw const FormatException('交易尾部存在多余字节');
    }
    final tx = NativeTx(
      version: version,
      inputs: inputs,
      outputs: outputs,
      locktime: locktime,
    );
    return tx;
  }

  static Uint8List _hexToBytes(String hex) {
    final h = hex.trim();
    if (h.length.isOdd) throw const FormatException('hex 长度必须为偶数');
    return Uint8List.fromList(List.generate(
        h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
  }

  static String bytesToHex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}