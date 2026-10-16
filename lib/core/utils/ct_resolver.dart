import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../network/ct_helper_client.dart';
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

/// secp256k1 点乘（ECDH）：返回共享点 X 坐标 32B（大端），等价于
/// libsecp256k1 `secp256k1_ecdh(..., CopyX32, nullptr)` 的输出（无预哈希）。
///
/// [priv32] 为本方 32B 私钥；[compressedPub33] 为对方压缩公钥（`02/03||X`）。
Uint8List ecdhSharedX(Uint8List priv32, Uint8List compressedPub33) {
  if (priv32.length != 32) throw const FormatException('私钥须为 32B');
  if (compressedPub33.length != 33 || (compressedPub33[0] != 2 && compressedPub33[0] != 3)) {
    throw const FormatException('公钥须为 33B 压缩点');
  }
  final domain = ECCurve_secp256k1();
  final d = _bytesToBigInt(priv32);
  final q = domain.curve.decodePoint(compressedPub33);
  if (q == null) throw const FormatException('公钥不是有效曲线点');
  final shared = q * d;
  if (shared == null || shared.isInfinity) {
    throw const FormatException('ECDH 结果无效');
  }
  return _bigIntTo32(shared.x!.toBigInteger()!);
}

/// 由链上 nonce 字段（prefix + X32）与本人私钥推导 rewind nonce 候选。
///
/// - Path C（`0x04`）：nonce 只存 X，Y 奇偶未知 → 分别按 even-Y（`0x02||X`）
///   与 odd-Y（`0x03||X`）重构 ephemeral，各得一个 HKDF nonce 候选；
/// - Path B（`0x03`）：nonce 即 ECDH ss 原值（无 HKDF）；
/// - Path A（`0x02`）已共识禁用，返回空（不 fallback）。
///
/// 返回可能有 0/1/2 个候选；调用方应逐个尝试 `rewind`，任一成功即本人输出。
List<Uint8List> rewindNonceCandidates({
  required Uint8List priv32,
  required int noncePrefix,
  required Uint8List x32,
  required Uint8List scriptPubKey,
}) {
  if (x32.length != 32) return const [];
  if (noncePrefix == 0x04) {
    final out = <Uint8List>[];
    for (final y in const [0x02, 0x03]) {
      try {
        final ss = ecdhSharedX(priv32, Uint8List.fromList([y, ...x32]));
        out.add(derivePathCNonce(ss, scriptPubKey));
      } catch (_) {
        // 该奇偶性不是合法曲线点（或非本人输出），跳过。
      }
    }
    return out;
  }
  if (noncePrefix == 0x03) {
    try {
      return [ecdhSharedX(priv32, Uint8List.fromList([0x03, ...x32]))];
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

Uint8List _bigIntTo32(BigInt v) {
  final out = Uint8List(32);
  var t = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (t & BigInt.from(0xff)).toInt();
    t = t >> 8;
  }
  return out;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _hexToBytes(String hex) {
  final h = hex.trim().startsWith('0x') ? hex.trim().substring(2) : hex.trim();
  if (h.isEmpty) return Uint8List(0);
  if (h.length.isOdd) throw const FormatException('hex 长度必须为偶数');
  return Uint8List.fromList(List.generate(
      h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
}

/// 单个 CT 输出的解盲结果（金额 + 盲因子 + 脚本），供作为花费输入使用。
class CtUtxoSecret {
  /// 明文金额（micro）。
  final int amountMicro;

  /// 盲因子 hex（32B，作为 CT 输入 `blind_hex`）。
  final String blindHex;

  /// 该输出锁定脚本 hex（P2WPKH，作为 CT 输入 `script_pubkey_hex`）。
  final String scriptPubKeyHex;

  /// 交易 hash（显示字节序 hex），用于构造输入 outpoint。
  final String txidDisplayHex;
  final int vout;

  const CtUtxoSecret({
    required this.amountMicro,
    required this.blindHex,
    required this.scriptPubKeyHex,
    required this.txidDisplayHex,
    required this.vout,
  });
}

/// CT（机密交易）输出解析器。
///
/// 生产环境由轻量代理完成 unblind（ECDH + 解承诺 + range proof），APP 侧仅
/// 转发 `resolve_ct` 并消费结果（docs/proxy-rpc-schema.md §6.1 对象形态）。
/// 本地纯实现仅作储备，不在此处展开。
class CtResolver {
  final NativeRpcClient _rpc;

  /// CT 盲化协处理器（`xctout` 解析 + `rewind` 解盲）。为空表示未启用 CT 花费。
  final CtHelperClient? _ct;

  CtResolver(this._rpc, {CtHelperClient? ctHelper}) : _ct = ctHelper;

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

  /// 解析单个链上 CT 输出为可花费输入（金额 + 盲因子 + 脚本）。
  ///
  /// 步骤：`getrawtransaction` 取原始交易 → `/ct/xctout` 拆出
  /// commitment/rangeproof/nonce → 本地 ECDH + HKDF 推导 rewind nonce 候选
  /// → `/ct/rewind` 还原金额与盲因子。
  ///
  /// [txidDisplayHex] 为显示字节序交易 hash（`scantxoutset` 原样）；
  /// [spendPriv32] 为该输出对应的花费私钥（盲化 key == spend key）。
  /// 非本人输出（nonce 无法解出）返回 `null`，不抛异常。
  Future<CtUtxoSecret?> resolveUtxoSecret({
    required String txidDisplayHex,
    required int vout,
    required Uint8List spendPriv32,
  }) async {
    final ct = _ct;
    if (ct == null) {
      throw const CtHelperException('未配置 CT 代理，无法解盲隐藏金额输出');
    }
    final txHex = await _rpc.getRawTransactionHex(txidDisplayHex);
    final fields = await ct.xctout(txHex: txHex, vout: vout);
    final candidates = rewindNonceCandidates(
      priv32: spendPriv32,
      noncePrefix: fields.noncePrefix,
      x32: _hexToBytes(fields.nonceXHex),
      scriptPubKey: _hexToBytes(fields.scriptPubKeyHex),
    );
    if (candidates.isEmpty) return null;
    final commitment = _hexToBytes(fields.commitmentHex);
    final rangeproof = _hexToBytes(fields.rangeproofHex);
    for (final nonce in candidates) {
      try {
        final r = await ct.rewind(
          nonce32: nonce,
          commitment33: commitment,
          rangeproof: rangeproof,
        );
        return CtUtxoSecret(
          amountMicro: r.amountMicro,
          blindHex: r.blindHex,
          scriptPubKeyHex: fields.scriptPubKeyHex,
          txidDisplayHex: txidDisplayHex,
          vout: vout,
        );
      } on CtHelperException {
        // 该候选 nonce 非本人输出，试下一个奇偶性。
        continue;
      }
    }
    return null;
  }
}