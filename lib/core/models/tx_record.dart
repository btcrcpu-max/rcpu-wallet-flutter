/// 交易记录领域模型。
///
/// 同时覆盖原生链（RPC 查询 + CT unblind）与 BSC（BEP-20）交易。
class TxRecord {
  /// 交易哈希（原生链或 BSC）
  final String txHash;

  /// 资产类型：native / wrcpu
  final String asset;

  /// 方向：in / out
  final String direction;

  /// 十进制金额字符串
  final String amount;

  /// 对手地址（收款方或付款方）
  final String counterparty;

  /// ISO 8601 时间戳；未知时为 null
  final String? timestamp;

  /// 交易状态：pending / confirmed / failed
  final String status;

  const TxRecord({
    required this.txHash,
    required this.asset,
    required this.direction,
    required this.amount,
    required this.counterparty,
    this.timestamp,
    this.status = 'confirmed',
  });

  /// 从链上/代理返回的 JSON 记录构造。
  factory TxRecord.fromJson(Map<String, dynamic> json) {
    return TxRecord(
      txHash: (json['txHash'] ?? json['hash'] ?? '').toString(),
      asset: (json['asset'] ?? 'native').toString(),
      direction: (json['direction'] ?? 'out').toString(),
      amount: (json['amount'] ?? '0').toString(),
      counterparty: (json['counterparty'] ?? '').toString(),
      timestamp: json['timestamp']?.toString(),
      status: (json['status'] ?? 'confirmed').toString(),
    );
  }

  bool get isIncoming => direction == 'in';

  bool get isPending => status == 'pending';

  @override
  String toString() => '$asset $direction $amount ($txHash)';
}