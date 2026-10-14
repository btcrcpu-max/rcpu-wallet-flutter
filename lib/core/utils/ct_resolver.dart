/// CT（机密交易）输出解析工具。
///
/// 生产环境优先由轻量代理完成 unblind，APP 侧保留本地实现储备。
/// 此处定义接口与占位，接入链上证明协议后补齐。
class CtResolver {
  /// 解析交易 hex 中的 CT 输出为明文金额（micro 单位）。
  ///
  /// 返回 null 表示该输出非本人或不可解。
  Future<int?> resolveOutput(
    String txHex,
    String ownAddress,
    String unblindingKey,
  ) async {
    throw UnimplementedError('CT unblind 待接入：代理优先，本地储备');
  }
}