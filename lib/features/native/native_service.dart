import '../../core/models/balance.dart';
import '../../core/models/tx_record.dart';
import '../../core/network/native_rpc.dart';
import '../../core/utils/ct_resolver.dart';

/// 原生 RCPU 主支付通道服务（明文 + CT）。
///
/// 余额查询由 RPC 代理聚合（明文 + CT unblind 后合并视图）；
/// 交易广播走 RPC，CT 输出解析默认由代理完成。
class NativeService {
  final NativeRpcClient _rpc;

  NativeService(this._rpc);

  /// 查询原生余额（代理已 unblind 本地址 CT 输出）。
  Future<Balance> getBalance(String address) => _rpc.getBalance(address);

  /// 广播签名交易。
  Future<String> broadcast(String signedTxHex) => _rpc.broadcast(signedTxHex);

  /// 历史记录。
  Future<List<TxRecord>> getHistory(String address) =>
      _rpc.getHistory(address, limit: 20);

  /// CT 输出本地解析储备（默认走代理，本地实现见 CtResolver）。
  Future<int?> resolveCtOutput(String txHex) =>
      CtResolver().resolveOutput(txHex, '', '');
}