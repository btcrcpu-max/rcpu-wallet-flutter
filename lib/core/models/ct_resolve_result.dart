/// `resolve_ct` 代理返回模型（docs/proxy-rpc-schema.md §6.1 对象形态）。
///
/// - [amountMicro] 为本人输出合计（micro 单位，1e8 精度）；`null` 表示非本人交易。
/// - [verified] 表示代理完成 ECDH + 解承诺 + 范围证明校验通过。
class CtResolveResult {
  /// 本人输出合计（micro）；非本人交易为 `null`。
  final int? amountMicro;

  /// 是否经代理验证（unblind 成功）。
  final bool verified;

  const CtResolveResult({
    required this.amountMicro,
    required this.verified,
  });

  /// 是否为本人输出且已解密验证（可计入余额）。
  bool get isMine => verified && amountMicro != null;
}