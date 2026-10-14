/// 资产余额领域模型。
///
/// [raw] 为链上十进制字符串；[micro] 为按 8 位精度换算的整数值。
/// 展示层一律从 [raw] 解析，避免浮点误差。
class Balance {
  /// 资产类型：native（原生 RCPU，含明文与 CT 合并视图）或 wrcpu（BSC 包装）
  final String asset;

  /// 原始十进制字符串余额（如 "1.50000000"）
  final String raw;

  /// 按 8 位精度表示的整数值（micro 单位）
  final int micro;

  const Balance({
    required this.asset,
    required this.raw,
    required this.micro,
  });

  /// 零余额快捷构造。
  factory Balance.zero(String asset) => Balance(asset: asset, raw: '0', micro: 0);

  bool get isZero => micro == 0;

  @override
  String toString() => '$asset: $raw';
}