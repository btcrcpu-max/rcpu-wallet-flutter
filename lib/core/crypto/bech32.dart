import 'dart:typed_data';
import '../l10n/app_strings.dart';

/// bech32 / bech32m 编解码（BIP173 / BIP350）。
///
/// 原生 RCPU 地址编码依赖：
/// - 隐私地址 `rcpux1...`：bech32m（HRP=`rcpux`，BECH32M 常量 `0x2bc830a3`）
/// - 明文地址 `rcpu1...`：bech32（HRP=`rcpu`，BECH32 常量 `1`）
///
/// 两者 checksum 常量不同，不可混用（协议要求与 `docs/path-c-spec.md` §3 一致）。
class Bech32 {
  /// bech32 字符集（BIP173）。
  static const String charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  /// bech32 校验常量（BIP173）。
  static const int bech32Const = 1;

  /// bech32m 校验常量（BIP350）。
  static const int bech32mConst = 0x2bc830a3;

  /// 将 5-bit 数据编码为 bech32 / bech32m 字符串。
  ///
  /// [data] 为 8-bit 原始字节，内部先做 8→5 ConvertBits（带填充）。
  static String encode(String hrp, Uint8List data, {required bool bech32m}) {
    final converted = convertBits(data, 8, 5, pad: true);
    final constant = bech32m ? bech32mConst : bech32Const;
    final checksum = _createChecksum(hrp, converted, constant);
    final sb = StringBuffer()..write(hrp)..write('1');
    for (final v in [...converted, ...checksum]) {
      sb.write(charset[v]);
    }
    return sb.toString();
  }

  /// 解码 bech32 / bech32m 字符串，返回 HRP 与 5-bit 数据（不含 checksum）。
  ///
  /// [isBech32m] 指定期望的编码类型；解码后 checksum 不符会抛出
  /// [FormatException]。解码得到的 5-bit 数据可经 [convertBits] 还原 8-bit。
  static Bech32Decoded decode(String input, {required bool isBech32m}) {
    final lower = input.toLowerCase();
    final sep = lower.lastIndexOf('1');
    if (sep < 1 || sep + 7 > lower.length) {
      throw FormatException(tr('bech32 格式非法: 缺少或错误的 1 分隔符', 'invalid bech32: missing or misplaced 1 separator'));
    }
    final hrp = lower.substring(0, sep);
    final dataPart = lower.substring(sep + 1);
    final data = Uint8List(dataPart.length);
    for (var i = 0; i < dataPart.length; i++) {
      final idx = charset.indexOf(dataPart[i]);
      if (idx < 0) {
        throw FormatException(tr('bech32 字符集外字符: ${dataPart[i]}', 'invalid bech32 character: ${dataPart[i]}'));
      }
      data[i] = idx;
    }
    final polymod = _polyMod([..._expandHrp(hrp), ...data]);
    final expectedConst = isBech32m ? bech32mConst : bech32Const;
    if (polymod != expectedConst) {
      throw FormatException(tr('bech32 checksum 校验失败', 'bech32 checksum failed'));
    }
    // 去掉 6 字节 checksum
    return Bech32Decoded(
      hrp: hrp,
      data: Uint8List.fromList(data.sublist(0, data.length - 6)),
    );
  }

  /// 只解码并返回 8-bit 数据（自动 5→8 ConvertBits，严格模式拒绝多余填充位）。
  static Uint8List decodeToBytes(String input, {required bool isBech32m}) {
    final decoded = decode(input, isBech32m: isBech32m);
    return convertBits(decoded.data, 5, 8, pad: false);
  }

  /// 编码 SegWit witness 地址（BIP173 / BIP350 标准分组）。
  ///
  /// witness version 单独占 1 个 5-bit group，program 独立做 8→5 ConvertBits；
  /// version 0 使用 bech32 校验常量，version 1..16 使用 bech32m（BIP350 规则）。
  /// 不得把 version 混入 program 一起转换，否则 Bitcoin Core 解析为
  /// 「Invalid padding / 非法 program 长度」并拒绝地址。
  static String encodeWitness(String hrp, int version, Uint8List program) {
    if (version < 0 || version > 16) {
      throw FormatException(tr('witness version 须在 0..16', 'witness version must be within 0..16'));
    }
    final useM = version != 0;
    final data = <int>[version, ...convertBits(program, 8, 5, pad: true)];
    final constant = useM ? bech32mConst : bech32Const;
    final checksum = _createChecksum(hrp, data, constant);
    final sb = StringBuffer()..write(hrp)..write('1');
    for (final v in [...data, ...checksum]) {
      sb.write(charset[v]);
    }
    return sb.toString();
  }

  /// 解码 witness 地址，返回 (version, program)。
  ///
  /// 同时接受 bech32 与 bech32m 两种校验（按 BIP350：version 0 必须 bech32，
  /// version 1..16 必须 bech32m，交叉组合抛 [FormatException]）；
  /// program 转换使用严格模式（拒绝非零填充位）。
  static WitnessAddress decodeWitness(String input) {
    final lower = input.toLowerCase();
    final sep = lower.lastIndexOf('1');
    if (sep < 1 || sep + 7 > lower.length) {
      throw FormatException(tr('bech32 格式非法: 缺少或错误的 1 分隔符', 'invalid bech32: missing or misplaced 1 separator'));
    }
    final hrp = lower.substring(0, sep);
    final dataPart = lower.substring(sep + 1);
    final data = <int>[];
    for (var i = 0; i < dataPart.length; i++) {
      final idx = charset.indexOf(dataPart[i]);
      if (idx < 0) {
        throw FormatException(tr('bech32 字符集外字符: ${dataPart[i]}', 'invalid bech32 character: ${dataPart[i]}'));
      }
      data.add(idx);
    }
    final polymod = _polyMod([..._expandHrp(hrp), ...data]);
    if (polymod != bech32Const && polymod != bech32mConst) {
      throw FormatException(tr('bech32 checksum 校验失败', 'bech32 checksum failed'));
    }
    if (data.isEmpty) {
      throw FormatException(tr('bech32 数据段为空', 'bech32 data part is empty'));
    }
    final version = data[0];
    if (version < 0 || version > 16) {
      throw FormatException(tr('witness version 非法: $version', 'invalid witness version: $version'));
    }
    final isM = polymod == bech32mConst;
    if ((version == 0) == isM) {
      throw FormatException(tr('witness version 与 checksum 类型不匹配', 'witness version does not match checksum type'));
    }
    final program = convertBits(
      Uint8List.fromList(data.sublist(1, data.length - 6)),
      5,
      8,
      pad: false,
    );
    return WitnessAddress(version: version, program: program);
  }

  /// 通用 ConvertBits（8→5 / 5→8）。
  ///
  /// [pad] 为 true 时按目标位宽补齐尾段（编码用）；为 false 时拒绝不完整尾段
  /// （解码校验用）。实现与 Bitcoin Core ConvertBits 一致。
  static Uint8List convertBits(Uint8List data, int from, int to,
      {required bool pad}) {
    final acc = <int>[];
    var bits = 0;
    var value = 0;
    final maxv = (1 << to) - 1;
    for (final b in data) {
      value = (value << from) | b;
      bits += from;
      while (bits >= to) {
        bits -= to;
        acc.add((value >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) {
        acc.add((value << (to - bits)) & maxv);
      }
    } else if (bits >= from || ((value << (to - bits)) & maxv) != 0) {
      throw FormatException(tr('ConvertBits 尾段不完整，拒绝解码', 'ConvertBits produced an incomplete tail, refusing to decode'));
    }
    return Uint8List.fromList(acc);
  }

  /// 生成 6 字节 checksum。
  static List<int> _createChecksum(
      String hrp, List<int> data, int constant) {
    final values = [..._expandHrp(hrp), ...data, 0, 0, 0, 0, 0, 0];
    final polymod = _polyMod(values) ^ constant;
    return [
      for (var i = 0; i < 6; i++) (polymod >> (5 * (5 - i))) & 31,
    ];
  }

  /// HRP 展开（BIP173：高 5 位 + 0 + 低 5 位）。
  static List<int> _expandHrp(String hrp) {
    final codes = hrp.codeUnits;
    return [
      ...codes.map((c) => (c >> 5) & 0x1f),
      0,
      ...codes.map((c) => c & 0x1f),
    ];
  }

  /// BIP173 polymod 生成器常量（GENERATOR[5]）。
  static const List<int> _generator = [
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3,
  ];

  /// BIP173 polymod（generator 0x3b6a57b2 系列）。
  static int _polyMod(List<int> values) {
    var chk = 1;
    for (final v in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        if (((top >> i) & 1) == 1) {
          chk ^= _generator[i];
        }
      }
    }
    return chk;
  }
}

/// bech32 / bech32m 解码结果。
class Bech32Decoded {
  final String hrp;
  final Uint8List data;

  const Bech32Decoded({required this.hrp, required this.data});
}

/// witness 地址解码结果：version 与 program。
class WitnessAddress {
  final int version;
  final Uint8List program;

  const WitnessAddress({required this.version, required this.program});
}