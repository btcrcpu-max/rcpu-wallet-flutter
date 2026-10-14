import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../models/balance.dart';
import '../models/tx_record.dart';

/// BSC RPC 客户端（web3dart）。
///
/// 已确认事实：
/// - 公共 RPC：https://bsc-dataseed.binance.org/
/// - wRCPU 合约：0x2F720B253EF63176cF54b0088C7F57997dd2c340（Decimals = 8）
class BscRpcClient {
  static const String defaultBscRpc = 'https://bsc-dataseed.binance.org/';

  /// wRCPU 合约地址（BSC 主网，Decimals = 8）
  static const String wrcpuContractAddress =
      '0x2F720B253EF63176cF54b0088C7F57997dd2c340';

  static const int wrcpuDecimals = 8;

  final String rpcUrl;
  late final Web3Client _client;
  late final EthPrivateKey _signer;

  BscRpcClient({String this.rpcUrl = defaultBscRpc, String? privateKeyHex}) {
    _client = Web3Client(rpcUrl, http.Client());
    if (privateKeyHex != null && privateKeyHex.isNotEmpty) {
      _signer = EthPrivateKey.fromHex(privateKeyHex);
    }
  }

  /// 查询 wRCPU 余额（BEP-20 balanceOf）。
  Future<Balance> getWrcpuBalance(String address) async {
    final wrcpuContract = _wrcpuContract();
    final fn = wrcpuContract.function('balanceOf');
    final result = await _client.call(
      contract: wrcpuContract,
      function: fn,
      params: [EthereumAddress.fromHex(address)],
    );
    final raw = result.first.toString();
    return Balance(asset: 'wrcpu', raw: raw, micro: int.tryParse(raw) ?? 0);
  }

  /// 查询 BNB 余额（Gas 检查）。
  Future<BigInt> getBnbBalance(String address) async {
    return _client.getBalance(EthereumAddress.fromHex(address));
  }

  /// 估算 Gas（web3dart 专用实现预留）。
  Future<BigInt> estimateGas() async {
    throw UnimplementedError('按具体合约调用封装');
  }

  /// 转账 wRCPU（标准 BEP-20 transfer）。
  Future<String> transferWrcpu({
    required String fromPrivateKey,
    required String toAddress,
    required BigInt amount,
  }) async {
    final signer = EthPrivateKey.fromHex(fromPrivateKey);
    final wrcpuContract = _wrcpuContract();
    final fn = wrcpuContract.function('transfer');
    return _client.sendTransaction(
      signer,
      Transaction.callContract(
        contract: wrcpuContract,
        function: fn,
        parameters: [EthereumAddress.fromHex(toAddress), amount],
      ),
      chainId: 56,
    );
  }

  /// 赎回构造：调用合约 redeem(amount, rcpuAddress)。
  /// 注：若桥合约仅暴露标准 burn，改用 burn 并按桥 API 链下登记，见说明文档。
  Future<String> redeem({
    required String fromPrivateKey,
    required BigInt amount,
    required String rcpuAddress,
  }) async {
    final signer = EthPrivateKey.fromHex(fromPrivateKey);
    final wrcpuContract = _wrcpuContract();
    final fn = wrcpuContract.function('redeem');
    return _client.sendTransaction(
      signer,
      Transaction.callContract(
        contract: wrcpuContract,
        function: fn,
        parameters: [amount, rcpuAddress],
      ),
      chainId: 56,
    );
  }

  /// 查询交易状态。
  Future<TxRecord> getTxStatus(String txHash) async {
    final receipt = await _client.getTransactionReceipt(Hash.fromHex(txHash));
    return TxRecord(
      txHash: txHash,
      asset: 'wrcpu',
      direction: 'out',
      amount: '0',
      counterparty: '',
      status: receipt == null ? 'pending' : 'confirmed',
    );
  }

  DelegatingContract _wrcpuContract() {
    return DelegatingContract(
      ContractInterface.fromJson(wrcpuAbi),
      EthereumAddress.fromHex(wrcpuContractAddress),
    );
  }
}

/// wRCPU 标准 BEP-20 ABI 片段（balanceOf / transfer / redeem / burn）。
const String wrcpuAbi = '''
[
  {"constant":true,"inputs":[{"name":"account","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"type":"function"},
  {"constant":false,"inputs":[{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"},
  {"constant":false,"inputs":[{"name":"amount","type":"uint256"},{"name":"rcpuAddress","type":"string"}],"name":"redeem","outputs":[],"type":"function"},
  {"constant":false,"inputs":[{"name":"amount","type":"uint256"}],"name":"burn","outputs":[],"type":"function"}
]
''';