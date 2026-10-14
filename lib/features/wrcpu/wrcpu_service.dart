import '../../core/models/balance.dart';
import '../../core/network/bsc_rpc.dart';

/// wRCPU（BSC）服务：余额 / 转账 / Gas 检查。
///
/// 合约：0x2F720B253EF63176cF54b0088C7F57997dd2c340（Decimals = 8）
class WrcpuService {
  final BscRpcClient _rpc;

  WrcpuService(this._rpc);

  Future<Balance> getBalance(String evmAddress) =>
      _rpc.getWrcpuBalance(evmAddress);

  /// 转账前检查 BNB Gas。
  Future<bool> hasEnoughGas(String evmAddress,
      {BigInt? thresholdWei}) async {
    final balance = await _rpc.getBnbBalance(evmAddress);
    final need = thresholdWei ?? BigInt.from(10000000000000000); // 0.01 BNB
    return balance >= need;
  }

  Future<String> transfer({
    required String fromPrivateKey,
    required String toAddress,
    required BigInt amount,
  }) =>
      _rpc.transferWrcpu(
        fromPrivateKey: fromPrivateKey,
        toAddress: toAddress,
        amount: amount,
      );
}