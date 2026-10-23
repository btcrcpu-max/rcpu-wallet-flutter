import 'dart:typed_data';
import '../l10n/app_strings.dart';

/// 原生 RCPU 交易结构（Bitcoin 风格序列化，segwit + CT 支持）。
///
/// 序列化布局（与 Bitcoin Core 一致）：
/// - 版本 4B LE
/// - 输入数 varint；每个输入：prevTxid(32) || prevVout(4LE) || scriptSigLen || scriptSig || seq(4LE)
///   （v3 额外多 1 字节尾字段，观测恒为 0x00，见 [NativeTxCodec.ctVersion]）
/// - 输出数 varint；输出布局随版本分两种（见下）
/// - 带 witness 时：标志 0x00 0x01 位于输入数之前（见 [NativeTx.hasWitness]）
/// - witness 栈（每输入：栈项数 varint + 每项：长度 varint + 字节）
/// - locktime 4B LE
///
/// 输出布局（已对照链上真实 v3 交易与节点 decoderawtransaction 逐项核实）：
/// - **v2（明文）**：value(8LE) || scriptLen || scriptPubKey；
/// - **v3（CT，`NativeTxCodec.ctVersion`）**：CConfidentialValue || CConfidentialNonce
///   || rangeproofLen || rangeproof || scriptLen || scriptPubKey
///   （**rangeproof 在脚本之前**，与 Elements 不同，是本链自定义 CTxOut 布局）。
///   金额：0x01 || 8B **大端** = 显式；0x08/0x09 || 32B = Pedersen 承诺；
///   0x00 = 显式 null（罕见，仅解析保留）。nonce：0x00 = 空；
///   0x02/0x03/0x04 || 32B = 承诺（0x04 为 Path C，仅存 ephemeral X）。
///   rangeproof 在输出体内（非 witness），与链上 `CTxOut` 序列化一致。
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
  }) : witness = witness ?? <Uint8List>[];

  bool get isTaproot => witness.any((w) => w.length == 64);
}

/// 交易输出：金额 + 锁定脚本（v3 CT 输出另含承诺 / nonce / rangeproof）。
class NativeTxOut {
  /// 显式金额（micro）；盲化承诺输出为 0。
  final BigInt value;
  final Uint8List scriptPubKey;

  /// v3（CT）Pedersen 金额承诺（33B，`08/09 || …`）；null = 显式金额。
  final Uint8List? valueCommitment;

  /// v3（CT）nonce 承诺（33B，`02/03/04 || …`）；null = 空 nonce（0x00）。
  final Uint8List? nonceCommitment;

  /// v3（CT）rangeproof（输出体内序列化）；null 视同空。
  final Uint8List? rangeproof;

  /// v3（CT）显式 null 金额（0x00 单字节）标记；仅解析时回填，
  /// 用于往返序列化保真，构造交易时无需设置。
  final bool valueIsNull;

  NativeTxOut({
    required this.value,
    required this.scriptPubKey,
    this.valueCommitment,
    this.nonceCommitment,
    this.rangeproof,
    this.valueIsNull = false,
  });

  /// 是否盲化（承诺）输出。
  bool get isConfidential => valueCommitment != null;
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
  /// CT 交易版本号：v3 起输出按「承诺/nonce/rangeproof」布局序列化。
  static const int ctVersion = 3;

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

  /// v3 显式金额：8 字节**大端**（与链上 CConfidentialValue 一致，
  /// 已经链上真实手续费输出 `000000000073ff50` → 7,602,000 micro = 0.07602
  /// RCPU 实证，与节点 decoderawtransaction 一致）。
  static Uint8List _be64(BigInt value) {
    final out = Uint8List(8);
    var v = value;
    for (var i = 7; i >= 0; i--) {
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
    final ct = tx.version == ctVersion;
    for (final i in tx.inputs) {
      b.add(i.prevTxid);
      b.add(_le(i.prevVout, 4));
      b.add(encodeVarInt(i.scriptSig.length));
      b.add(i.scriptSig);
      b.add(_le(i.sequence, 4));
      if (ct) {
        // v3 每输入尾字段（观测恒为 0x00，已对照多笔链上交易）。
        b.add([0x00]);
      }
    }
    b.add(encodeVarInt(tx.outputs.length));
    for (final o in tx.outputs) {
      if (ct) {
        _writeCtOutput(b, o);
      } else {
        b.add(_le64(o.value));
        b.add(encodeVarInt(o.scriptPubKey.length));
        b.add(o.scriptPubKey);
      }
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

  /// 写出 v3（CT）输出：金额 || nonce || rangeproof || 脚本。
  ///
  /// 金额：承诺 33B 原样；显式为 `0x01 || 8B 大端`；显式 null 为 0x00。
  /// nonce：承诺 33B 原样；空为 0x00。rangeproof 以 varbytes 写入（可空），
  /// **位于 scriptPubKey 之前**（链上 CTxOut 自定义布局，已实证）。
  static void _writeCtOutput(BytesBuilder b, NativeTxOut o) {
    final vc = o.valueCommitment;
    if (vc != null) {
      if (vc.length != 33) {
        throw FormatException(tr('CT 金额承诺须为 33B', 'CT amount commitment must be 33 bytes'));
      }
      b.add(vc);
    } else if (o.valueIsNull) {
      b.add([0x00]);
    } else {
      b.add([0x01]);
      b.add(_be64(o.value));
    }
    final nc = o.nonceCommitment;
    if (nc != null) {
      if (nc.length != 33) {
        throw FormatException(tr('CT nonce 承诺须为 33B', 'CT nonce commitment must be 33 bytes'));
      }
      b.add(nc);
    } else {
      b.add([0x00]);
    }
    final rp = o.rangeproof ?? Uint8List(0);
    b.add(encodeVarInt(rp.length));
    b.add(rp);
    b.add(encodeVarInt(o.scriptPubKey.length));
    b.add(o.scriptPubKey);
  }

  /// 解析 v3（CT）输出：金额 || nonce || rangeproof || 脚本。
  ///
  /// 金额前缀：0x00 = 显式 null；0x01 = 显式 8B **大端**；0x08/0x09 = 33B 承诺。
  /// nonce 前缀：0x00 = 空；0x02/0x03/0x04 = 33B 承诺。
  /// rangeproof（varbytes）位于 scriptPubKey（varbytes）**之前**。
  static NativeTxOut _readCtOutput(
    Uint8List Function(int) take,
    BigInt Function() takeBe64,
    int Function() readVarInt,
  ) {
    BigInt value = BigInt.zero;
    Uint8List? valueCommitment;
    var valueIsNull = false;
    final vtag = take(1)[0];
    if (vtag == 0x00) {
      valueIsNull = true;
    } else if (vtag == 0x01) {
      value = takeBe64();
    } else if (vtag == 0x08 || vtag == 0x09) {
      valueCommitment = Uint8List.fromList([vtag, ...take(32)]);
    } else {
      throw FormatException(tr('非法 CT 金额前缀', 'invalid CT amount prefix'));
    }

    Uint8List? nonceCommitment;
    final ntag = take(1)[0];
    if (ntag == 0x00) {
      nonceCommitment = null;
    } else if (ntag == 0x02 || ntag == 0x03 || ntag == 0x04) {
      nonceCommitment = Uint8List.fromList([ntag, ...take(32)]);
    } else {
      throw FormatException(tr('非法 CT nonce 前缀', 'invalid CT nonce prefix'));
    }

    final rpLen = readVarInt();
    final rangeproof = take(rpLen);
    final scriptLen = readVarInt();
    final scriptPubKey = take(scriptLen);

    return NativeTxOut(
      value: value,
      scriptPubKey: scriptPubKey,
      valueCommitment: valueCommitment,
      nonceCommitment: nonceCommitment,
      rangeproof: rpLen > 0 ? rangeproof : null,
      valueIsNull: valueIsNull,
    );
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
        throw FormatException(tr('交易字节不足（截断）', 'transaction bytes are truncated'));
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

    /// v3 显式金额：8 字节大端（链上 CConfidentialValue 布局）。
    BigInt takeBe64() {
      final bytes = take(8);
      var v = BigInt.zero;
      for (var i = 0; i < 8; i++) {
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
    final ct = version == ctVersion;

    var inputCount = readVarInt();
    var hasWitness = false;
    if (inputCount == 0) {
      // marker 0x00 + flag 0x01
      final flag = take(1)[0];
      if (flag != 0x01) {
        throw FormatException(tr('非法 witness 标志', 'invalid witness flag'));
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
      if (ct) {
        // v3 每输入尾字段（观测恒为 0x00；helper 构造与链上已确认交易一致）。
        final tail = take(1)[0];
        if (tail != 0x00) {
          throw FormatException(tr('非法 v3 输入尾字节', 'invalid v3 input trailing byte'));
        }
      }
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
      if (ct) {
        outputs.add(_readCtOutput(take, takeBe64, readVarInt));
      } else {
        final value = takeLe64();
        final scriptLen = readVarInt();
        final scriptPubKey = take(scriptLen);
        outputs.add(NativeTxOut(value: value, scriptPubKey: scriptPubKey));
      }
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
      throw FormatException(tr('交易尾部存在多余字节', 'trailing bytes after transaction'));
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
    if (h.length.isOdd) throw FormatException(tr('hex 长度必须为偶数', 'hex length must be even'));
    return Uint8List.fromList(List.generate(
        h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
  }

  static String bytesToHex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}