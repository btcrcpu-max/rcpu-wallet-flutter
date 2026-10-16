/// 地址领域模型。
///
/// 覆盖三种地址形态：
/// - 原生明文：`rcpu1...`
/// - 原生隐私（CT）：`rcpux1...`（默认 Path C 派生）
/// - BSC 地址：`0x...`（标准 BIP44 派生）
class Address {
  /// 原生 RCPU 明文地址（rcpu1 前缀）
  static const String plainPrefix = 'rcpu1';

  /// 原生 RCPU 隐私地址（rcpux1 前缀）
  static const String privatePrefix = 'rcpux1';

  /// BSC 地址前缀
  static const String evmPrefix = '0x';

  final String value;

  /// 地址类型标记：plain / private / evm
  final String type;

  const Address(this.value, this.type);

  /// 根据前缀自动识别地址类型。
  factory Address.parse(String raw) {
    final v = raw.trim();
    if (v.startsWith(evmPrefix)) {
      return Address(v, 'evm');
    }
    // bech32 地址大小写不敏感（BIP173：全小写或全大写均为合法
    // 编码，QT 二维码按惯例输出全大写）；统一归一为小写存储。
    final lower = v.toLowerCase();
    if (lower.startsWith(privatePrefix)) {
      return Address(lower, 'private');
    }
    if (lower.startsWith(plainPrefix)) {
      return Address(lower, 'plain');
    }
    throw FormatException('无法识别的地址前缀: $v');
  }

  bool get isNative => type == 'plain' || type == 'private';

  bool get isPlain => type == 'plain';

  bool get isPrivate => type == 'private';

  bool get isEvm => type == 'evm';

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is Address && other.value == value && other.type == type;

  @override
  int get hashCode => Object.hash(value, type);
}