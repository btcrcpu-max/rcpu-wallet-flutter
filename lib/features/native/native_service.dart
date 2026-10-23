import 'dart:typed_data';

import '../../core/models/balance.dart';
import '../../core/models/tx_record.dart';
import '../../core/network/ct_helper_client.dart';
import '../../core/network/native_rpc.dart';
import '../../core/utils/ct_resolver.dart';
import '../../core/l10n/app_strings.dart';

/// 原生 RCPU 主支付通道服务（明文 + CT）。
///
/// 余额查询由 RPC 代理聚合（明文 + CT unblind 后合并视图）；
/// 交易广播走 RPC，CT 输出解析默认由代理完成。代理未提供 CT 合并视图时，
/// 由 [getPrivateBalance] 在本地逐输出解盲（见下）。
class NativeService {
  final NativeRpcClient _rpc;

  /// CT 盲化协处理器；为空表示未启用本地 CT 解盲（隐私余额仅依赖代理）。
  final CtHelperClient? _ctHelper;

  /// 已解出金额的 CT 输出缓存（`txid:vout` → micro）。
  ///
  /// rangeproof 解盲在服务器侧较重，而首页每次区块高度推进都会刷新余额，
  /// 故对已确认输出做内存缓存，避免重复 `rewind`。
  final Map<String, int> _ctAmountCache = {};

  NativeService(this._rpc, {CtHelperClient? ctHelper}) : _ctHelper = ctHelper;

  /// 查询原生余额（代理已 unblind 本地址 CT 输出）。
  Future<Balance> getBalance(String address) => _rpc.getBalance(address);

  /// 隐私地址（`rcpux1`）CT 余额：逐输出解盲后求和（micro）。
  ///
  /// 链上 CT 输出的金额在 `scantxoutset` 中读作 0，代理未回传合并视图时
  /// 必须本地解盲：`getrawtransaction` → `/ct/xctout` → 本地 ECDH（CopyX32）
  /// + Path C HKDF 推导 rewind nonce → `/ct/rewind` 还原金额。
  ///
  /// 私钥不出设备（只用于本地 ECDH，helper 只见 nonce）。非本人输出跳过；
  /// CT 协处理器不可用时抛 [CtHelperException]，由调用方降级为明文余额。
  Future<Balance> getPrivateBalance({
    required String privateAddress,
    required Uint8List spendPriv32,
  }) async {
    final utxos = await _rpc.getUtxos(privateAddress);
    if (utxos.isEmpty) return Balance.zero('native');
    final helper = _ctHelper;
    if (helper == null) {
      throw CtHelperException(tr('未配置 CT 代理，无法解盲隐私地址余额', 'CT helper not configured; cannot unblind the confidential address balance'));
    }
    final resolver = CtResolver(_rpc, ctHelper: helper);
    var total = 0;
    for (final u in utxos) {
      if (!u.confirmed) continue;
      // 代理已 unblind 的出账可直接采用；金额为 0 的盲化输出需本地解盲。
      if (u.amountMicro > 0) {
        total += u.amountMicro;
        continue;
      }
      final cacheKey = '${_hex(u.prevTxid)}:${u.vout}';
      final cached = _ctAmountCache[cacheKey];
      if (cached != null) {
        total += cached;
        continue;
      }
      final secret = await resolver.resolveUtxoSecret(
        // 缓存/unblind 需要显示字节序 txid；NativeUtxo 存内部字节序。
        txidDisplayHex: _hex(Uint8List.fromList(u.prevTxid.reversed.toList())),
        vout: u.vout,
        spendPriv32: spendPriv32,
      );
      if (secret == null) continue; // 非本人输出
      _ctAmountCache[cacheKey] = secret.amountMicro;
      total += secret.amountMicro;
    }
    return Balance(
      asset: 'native',
      raw: (total / 1e8).toStringAsFixed(8),
      micro: total,
    );
  }

  /// 广播签名交易。
  Future<String> broadcast(String signedTxHex) => _rpc.broadcast(signedTxHex);

  /// 历史记录。
  Future<List<TxRecord>> getHistory(String address) =>
      _rpc.getHistory(address, limit: 20);

  /// 解析单笔交易中的本人 CT 输出为明文金额（走代理 `resolve_ct`）。
  ///
  /// 返回本人输出合计（micro）；非本人交易或不可解时返回 `null`。
  Future<int?> resolveCtOutput(
    String txHex, {
    required String viewSeed,
    required String ownScriptPubKey,
  }) =>
      CtResolver(_rpc).resolveOutput(
        txHex: txHex,
        viewSeed: viewSeed,
        ownScriptPubKey: ownScriptPubKey,
      );

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
