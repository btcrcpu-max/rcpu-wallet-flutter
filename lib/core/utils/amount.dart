/// 金额换算工具。
///
/// 统一以 1e8 为内部整数单位（micro-RCPU），与 wRCPU Decimals = 8 对齐。
/// 所有 UI 展示与桥 API 交互的金额均使用十进制字符串，禁用浮点累加。
class Amount {
  static const int precision = 8;
  static const int microPerUnit = 100000000; // 1e8

  /// 校验十进制金额字符串（非负、最多 8 位小数）。
  static bool isValid(String input) {
    final s = input.trim();
    if (s.isEmpty) return false;
    final re = RegExp(r'^\d+(\.\d{1,8})?$');
    if (!re.hasMatch(s)) return false;
    return double.parse(s) >= 0;
  }

  /// 字符串金额 -> micro 整数。
  static int toMicro(String input) {
    if (!isValid(input)) {
      throw FormatException('非法金额: $input');
    }
    final parts = input.split('.');
    final whole = int.parse(parts[0]);
    final frac = parts.length == 2 ? parts[1].padRight(precision, '0') : '00000000';
    return whole * microPerUnit + int.parse(frac);
  }

  /// micro 整数 -> 十进制字符串（去尾零）。
  static String fromMicro(int micro) {
    if (micro == 0) return '0';
    final whole = micro ~/ microPerUnit;
    final frac = (micro % microPerUnit).toString().padLeft(precision, '0');
    final trimmed = frac.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
  }

  /// 最小存款（0.01 RCPU）。
  static int get minDepositMicro => toMicro('0.01');

  /// 铸造门槛（10 RCPU）。
  static int get mintThresholdMicro => toMicro('10');
}