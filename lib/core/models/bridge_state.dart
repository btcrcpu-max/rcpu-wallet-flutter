/// 跨链桥（rcpupool.asia）状态领域模型。
///
/// 状态机取值（与桥 API 约定一致）：
/// - collecting：存款累计中
/// - ready_to_mint：已满 10 RCPU，待铸造
/// - minting：铸造中
/// - minted：铸造完成
/// - pending / processing / completed（赎回流程）
/// - failed：失败（携带 errorCode）
class BridgeState {
  final String phase;

  /// collecting / minting / minted / pending / processing / completed / failed
  final String state;

  /// 累计存款金额（十进制字符串，铸造场景）
  final String? totalDeposited;

  /// 铸造门槛，固定为 10 RCPU
  static const double mintThreshold = 10.0;

  /// 最小存款，固定为 0.01 RCPU
  static const double minDeposit = 0.01;

  /// 专属明文存款地址（rcpu1 前缀）
  final String? depositAddress;

  /// 铸造交易哈希（铸造完成时）
  final String? wrcpuTxHash;

  /// 赎回归还的原生交易哈希（赎回完成时）
  final String? rcpuTxHash;

  /// 桥估计的处理时长（分钟）
  final int? estimatedTimeMinutes;

  /// 失败错误码
  final String? errorCode;

  const BridgeState({
    required this.phase,
    required this.state,
    this.totalDeposited,
    this.depositAddress,
    this.wrcpuTxHash,
    this.rcpuTxHash,
    this.estimatedTimeMinutes,
    this.errorCode,
  });

  factory BridgeState.idle() =>
      const BridgeState(phase: 'deposit', state: 'collecting');

  bool get isDeposit => phase == 'deposit';

  bool get isRedeem => phase == 'redeem';

  bool get isFailed => state == 'failed';

  bool get isCompleted => state == 'minted' || state == 'completed';

  @override
  String toString() => 'BridgeState($phase/$state${errorCode != null ? ' err=$errorCode' : ''})';
}