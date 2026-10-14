import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../models/ct_resolve_result.dart';
import '../network/native_rpc.dart';

/// Path C 密钥派生原语（官方 `doc/ct-path-c.md` Appendix A/C 向量锚定于
/// `test/tc_sig02_hkdf_test.dart`）。
///
/// - [deriveViewSeed]：view_seed = HKDF-Extract(salt = "rcpu-pathc-v1", ikm = ss)
/// - [deriveRewindNonceFromViewSeed]：rewind nonce = HKDF-Expand(
///   PRK = view_seed, info = scriptPubKey || 0x01 || le64(64), L = 32)
/// - [derivePathCNonce]：两步组合（官方 Appendix C 全流程）。
Uint8List deriveViewSeed(Uint8List ss) {
  final salt = utf8.encode('rcpu-pathc-v1');
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(salt));
  return hmac.process(ss);
}

Uint8List deriveRewindNonceFromViewSeed(
    Uint8List viewSeed, Uint8List scriptPubKey) {
  final info = Uint8List.fromList([
    ...scriptPubKey,
    0x01,
    0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // le64(64)
  ]);
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(viewSeed));
  final block = hmac.process(Uint8List.fromList([...info, 0x01]));
  return block.sublist(0, 32);
}

Uint8List derivePathCNonce(Uint8List ss, Uint8List scriptPubKey) {
  final viewSeed = deriveViewSeed(ss);
  return deriveRewindNonceFromViewSeed(viewSeed, scriptPubKey);
}

/// CT（机密交易）输出解析器。
///
/// 生产环境由轻量代理完成 unblind（ECDH + 解承诺 + range proof），APP 侧仅
/// 转发 `resolve_ct` 并消费结果（docs/proxy-rpc-schema.md §6.1 对象形态）。
/// 本地纯实现仅作储备，不在此处展开。
class CtResolver {
  final NativeRpcClient _rpc;

  CtResolver(this._rpc);

  /// 解析交易 hex 中的本人 CT 输出为明文金额（micro 单位）。
  ///
  /// - [txHex]：待解析交易 hex（或 txid，按代理契约）；
  /// - [viewSeed]：Path C view_seed（见 [deriveViewSeed]）；
  /// - [ownScriptPubKey]：本人隐私地址对应输出脚本（hex），用于匹配输出。
  ///
  /// 返回本人输出合计；非本人交易或不可解时返回 `null`。
  Future<int?> resolveOutput({
    required String txHex,
    required String viewSeed,
    required String ownScriptPubKey,
  }) async {
    final result = await _rpc.resolveCt(
      txHex: txHex,
      viewSeed: viewSeed,
      ownScriptPubKey: ownScriptPubKey,
    );
    return result.isMine ? result.amountMicro : null;
  }
}