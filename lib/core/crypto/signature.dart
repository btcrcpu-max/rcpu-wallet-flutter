import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:web3dart/crypto.dart';

import 'bip340.dart';
import 'bip341.dart';
import 'native_tx.dart';

/// 签名工具统一入口。
///
/// - [signNative]：原生 RCPU 交易签名（BIP340 Schnorr，P2TR key-path）
/// - [verifyBscSignature]：BSC/EVM 个人消息签名校验（EIP-191）
///
/// 密钥只驻留内存副本，不落盘。
class Signature {
  /// 原生链交易签名：对 32 字节消息（BIP341 sighash 摘要）做 BIP340 Schnorr 签名。
  ///
  /// [tx] 为待签名的 32 字节消息哈希（由 `Bip341.taprootKeyPathSighash` 产出）；
  /// [privateKey] 为 32 字节私钥。返回 64 字节签名 `r(32) || s(32)`。
  Future<Uint8List> signNative(Uint8List tx, Uint8List privateKey) async {
    return Bip340.sign(privateKey, tx);
  }

  /// 校验 BSC/EVM 个人消息签名（EIP-191：`\x19Ethereum Signed Message:\n<len>`）。
  ///
  /// [message] 为被签名的原始消息字节；[signature] 为标准 65 字节紧凑签名
  /// `r(32) || s(32) || v(1)`（v 取 `{0,1}` 或 `{27,28}`，自动归一化到 27/28）；
  /// [addressHex] 为期望的签名者地址（`0x` 前缀与大小写不敏感）。
  ///
  /// 实现：keccak256(personalMessage) -> `ecRecover` 恢复公钥
  /// -> `publicKeyToAddress` 得地址，与 [addressHex] 比对；
  /// 签名长度非法、恢复失败或地址不匹配返回 false。
  bool verifyBscSignature(
      Uint8List message, Uint8List signature, String addressHex) {
    if (signature.length != 65) return false;
    final v = signature[64] < 27 ? signature[64] + 27 : signature[64];
    final msgSig = MsgSignature(
      bytesToUnsignedInt(signature.sublist(0, 32)),
      bytesToUnsignedInt(signature.sublist(32, 64)),
      v,
    );
    try {
      final personalHash = keccak256(Uint8List.fromList([
        ...utf8.encode('\x19Ethereum Signed Message:\n${message.length}'),
        ...message,
      ]));
      final recoveredPub = ecRecover(personalHash, msgSig);
      final recovered = bytesToHex(publicKeyToAddress(recoveredPub));
      return recovered == _normHex(addressHex);
    } catch (_) {
      return false;
    }
  }

  /// 归一化十六进制地址：去 `0x` 前缀并转小写。
  static String _normHex(String input) {
    final v = input.trim().toLowerCase();
    return v.startsWith('0x') ? v.substring(2) : v;
  }
}

/// 原生交易签名服务（P2TR key-path + BIP340/BIP341 真实实现）。
///
/// 面向「交易 hex + 私钥 hex → 已签名交易 hex」的高层入口，
/// 供支付链路（TC-SIG-03 / `_buildTxHex`）调用。
///
/// 签名流程：
/// 1. 反序列化 [txHex]（`NativeTxCodec.parseHex`，含/不含 witness 均可）；
/// 2. 对每个输入：由 [prevOuts] 提供 prevout 的 scriptPubKey 与金额，
///    计算 BIP341 key-path sighash（SIGHASH_DEFAULT）；
/// 3. BIP340 签名（64B）写回该输入的 witness（key-path：单元素 `sig64`）；
/// 4. 重新序列化并返回带 witness 的完整交易 hex。
///
/// 边界（`docs/signnative-implementation.md` §5）：
/// - 盲化承诺/rangeproof 不在本端完成：CT 输出由代理 `createBlindedOutput`
///   或官方库先行回填进 [txHex] 的输出区，本端仅负责签名部分；
/// - 输入须为 P2TR（`NativePrevOut.scriptPubKey` 校验 `0x51 0x20 || x32`），
///   非 P2TR 输入抛格式错误；
/// - 所有输入使用同一把花费私钥签名（钱包本地路径派生）。
class SignatureService {
  /// 原生交易签名。
  ///
  /// [txHex] 为待签名的**未签名交易**（输入 witness 可为空，输出区已含
  /// 目标锁定脚本；CT 输出须已由代理回填盲化承诺）；[privateKeyHex] 为
  /// 32 字节私钥 hex（可带或省略 `0x` 前缀）。
  ///
  /// [prevOuts] 提供各输入 prevout 的 scriptPubKey（P2TR，34B）与金额
  /// （BIP341 sighash 需要，交易体本身不含）。缺省时将从交易输入
  /// 的 scriptPubKey（若输入携带 spk 模板）尝试推导；无法推导则抛错。
  Future<String> signNative(
    String txHex,
    String privateKeyHex, {
    List<NativePrevOut>? prevOuts,
  }) async {
    final tx = NativeTxCodec.parseHex(txHex);
    final privKeyHex = _stripHexPrefix(privateKeyHex);
    final privKey = _hexToBytes(privKeyHex);
    if (privKey.length != 32) {
      throw const FormatException('私钥须为 32 字节 hex');
    }
    final spendPub = Bip340.pubKeyFromPriv(privKey);
    final xOnly = Bip340.xOnlyFromPub(spendPub);

    prevOuts ??= _derivePrevOutsFromTx(tx, xOnly);
    if (prevOuts.length != tx.inputs.length) {
      throw ArgumentError('prevOuts 数量（${prevOuts.length}）与输入数'
          '（${tx.inputs.length}）不一致');
    }

    // 逐输入校验脚本类型：P2TR（Schnorr/BIP341）或 P2WPKH（ECDSA/BIP143）。
    final parsedPrevOuts = <NativePrevOut>[];
    for (var i = 0; i < tx.inputs.length; i++) {
      final prev = prevOuts[i];
      if (!Bip341.isP2tr(prev.scriptPubKey) && !_isP2wpkh(prev.scriptPubKey)) {
        throw const FormatException(
            '仅支持 P2TR（0x51 0x20 || x32）或 P2WPKH（0x00 0x14 || h160）输入');
      }
      parsedPrevOuts.add(NativePrevOut(
        scriptPubKey: prev.scriptPubKey,
        amount: prev.amount,
      ));
    }

    for (var i = 0; i < tx.inputs.length; i++) {
      final spk = parsedPrevOuts[i].scriptPubKey;
      if (Bip341.isP2tr(spk)) {
        // P2TR key-path：BIP341 sighash + BIP340 签名（单元素 witness）。
        final sighash = Bip341.taprootKeyPathSighash(
            tx: tx, prevOuts: parsedPrevOuts, inputIndex: i);
        final sig = Bip340.sign(privKey, sighash);
        tx.inputs[i].witness
          ..clear()
          ..add(sig);
      } else {
        // P2WPKH：BIP143 sighash + secp256k1 ECDSA（DER + SIGHASH_ALL），
        // witness 为 [签名, 压缩公钥]（BIP141 标准形态）。
        final sighash = _bip143Sighash(tx, parsedPrevOuts, i);
        final sig = _ecdsaSignSecp256k1(privKey, sighash);
        tx.inputs[i].witness
          ..clear()
          ..add(sig)
          ..add(_compressedPubKey(privKey));
      }
    }

    return NativeTxCodec.bytesToHex(tx.serialize());
  }

  /// 对**已给定的** 32B 摘要做 P2WPKH ECDSA 签名（DER 编码 + SIGHASH_ALL）。
  ///
  /// 供 CT 支付链路使用：BIP143 sighash 由服务器 CT 协处理器按共识规则
  /// （confidential 输入金额按 0 计入）算出，App 侧不得自行重算（金额与
  /// 承诺形态差异会导致签名与链上校验不一致）。返回签名字节（DER||0x01）。
  Uint8List signEcdsaDigest(Uint8List privKey32, Uint8List digest32) {
    if (privKey32.length != 32) throw const FormatException('私钥须为 32 字节');
    if (digest32.length != 32) throw const FormatException('摘要须为 32 字节');
    return _ecdsaSignSecp256k1(privKey32, digest32);
  }

  /// 压缩公钥（33B，`02/03 || X`），P2WPKH witness 第二元素。
  Uint8List compressedPubKey(Uint8List privKey32) =>
      _compressedPubKey(privKey32);

  /// P2WPKH 锁定脚本判定（`0x00 0x14 || h160`，22 字节）。
  static bool _isP2wpkh(Uint8List spk) =>
      spk.length == 22 && spk[0] == 0x00 && spk[1] == 0x14;

  /// BIP143 sighash（SIGHASH_ALL）：用于 witness v0 P2WPKH 输入。
  static Uint8List _bip143Sighash(
      NativeTx tx, List<NativePrevOut> prevOuts, int index) {
    // hashPrevouts = dsha256(全部输入 outpoint)
    final hp = BytesBuilder();
    for (final inp in tx.inputs) {
      hp.add(inp.prevTxid);
      hp.add(_le32(inp.prevVout));
    }
    final hashPrevouts = _dsha256(hp.toBytes());
    // hashSequence = dsha256(全部输入 sequence)
    final hs = BytesBuilder();
    for (final inp in tx.inputs) {
      hs.add(_le32(inp.sequence));
    }
    final hashSequence = _dsha256(hs.toBytes());
    // hashOutputs = dsha256(全部输出序列化)
    final ho = BytesBuilder();
    for (final o in tx.outputs) {
      ho.add(_le64(o.value));
      ho.add(NativeTxCodec.encodeVarInt(o.scriptPubKey.length));
      ho.add(o.scriptPubKey);
    }
    final hashOutputs = _dsha256(ho.toBytes());
    // scriptCode = 0x19 76 a9 14 <h160> 88 ac（P2PKH 模板 + 长度前缀）
    final h160 = prevOuts[index].scriptPubKey.sublist(2, 22);
    final scriptCode =
        Uint8List.fromList([0x19, 0x76, 0xa9, 0x14, ...h160, 0x88, 0xac]);

    final p = BytesBuilder()
      ..add(_le32(tx.version))
      ..add(hashPrevouts)
      ..add(hashSequence)
      ..add(tx.inputs[index].prevTxid)
      ..add(_le32(tx.inputs[index].prevVout))
      ..add(scriptCode)
      ..add(_le64(prevOuts[index].amount))
      ..add(_le32(tx.inputs[index].sequence))
      ..add(hashOutputs)
      ..add(_le32(tx.locktime))
      ..add(_le32(1)); // SIGHASH_ALL
    return _dsha256(p.toBytes());
  }

  /// secp256k1 ECDSA 签名（RFC6979 确定性 nonce，low-S 规范化），
  /// 返回 DER 编码 + SIGHASH_ALL（0x01）后缀。
  ///
  /// 手写实现（不依赖 ECDSASigner，避免 pointycastle 导出差异）：
  /// k 由 RFC6979(HMAC-SHA256) 确定；r = (k·G).x mod n；
  /// s = k⁻¹·(e + r·d) mod n；BIP62 low-S：s > n/2 时取 n − s。
  static Uint8List _ecdsaSignSecp256k1(Uint8List privKey, Uint8List msgHash) {
    final domain = ECCurve_secp256k1();
    final n = domain.n;
    final d = _bytesToBigInt(privKey);
    final e = _bytesToBigInt(msgHash) % n;

    final k = _rfc6979Nonce(d, msgHash, n);
    final pointR = domain.G * k;
    final r = pointR!.x!.toBigInteger()! % n;
    final kInv = k.modInverse(n);
    var s = (kInv * (e + r * d)) % n;
    if (s.compareTo(n >> 1) > 0) {
      s = n - s; // BIP62/BIP146 low-S
    }
    final der = _derEncode(r, s);
    return Uint8List.fromList([...der, 0x01]);
  }

  /// RFC6979 确定性 nonce（HMAC-SHA256，§3.2）：输入私钥 d 与
  /// 消息哈希 h1，输出 1 ≤ k < n。
  static BigInt _rfc6979Nonce(BigInt d, Uint8List h1, BigInt n) {
    final x = _bigIntTo32(d);
    var v = Uint8List(32)..fillRange(0, 32, 0x01);
    var k = Uint8List(32);
    k = _hmacSha256(k, [...v, 0x00, ...x, ...h1]);
    v = _hmacSha256(k, v);
    k = _hmacSha256(k, [...v, 0x01, ...x, ...h1]);
    v = _hmacSha256(k, v);
    while (true) {
      v = _hmacSha256(k, v);
      final candidate = _bytesToBigInt(v);
      if (candidate > BigInt.zero && candidate < n) return candidate;
      k = _hmacSha256(k, [...v, 0x00]);
      v = _hmacSha256(k, v);
    }
  }

  static Uint8List _hmacSha256(Uint8List key, List<int> msg) {
    final h = HMac(SHA256Digest(), 64)..init(pc.KeyParameter(key));
    return h.process(Uint8List.fromList(msg));
  }

  static Uint8List _bigIntTo32(BigInt v) {
    final out = Uint8List(32);
    var t = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (t & BigInt.from(0xff)).toInt();
      t = t >> 8;
    }
    return out;
  }

  /// 压缩公钥（0x02/0x03 || x32），P2WPKH witness 第二元素。
  static Uint8List _compressedPubKey(Uint8List privKey) {
    final pub64 = privateKeyToPublic(_bytesToBigInt(privKey)); // x||y
    final prefix = (pub64[63] & 1) == 0 ? 0x02 : 0x03;
    return Uint8List.fromList([prefix, ...pub64.sublist(0, 32)]);
  }

  /// DER 整数编码（去前导零，最高位置位时补 0x00）。
  static Uint8List _derEncode(BigInt r, BigInt s) {
    List<int> enc(BigInt v) {
      final b = _bigIntToBytes(v);
      final body = (b.isNotEmpty && (b[0] & 0x80) != 0) ? [0x00, ...b] : b;
      return [0x02, body.length, ...body];
    }

    final body = [...enc(r), ...enc(s)];
    return Uint8List.fromList([0x30, body.length, ...body]);
  }

  static Uint8List _dsha256(Uint8List data) {
    final d = SHA256Digest();
    return d.process(d.process(data));
  }

  static Uint8List _le32(int v) => Uint8List.fromList(
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);

  static Uint8List _le64(BigInt v) {
    final out = Uint8List(8);
    var t = v;
    for (var i = 0; i < 8; i++) {
      out[i] = (t & BigInt.from(0xff)).toInt();
      t = t >> 8;
    }
    return out;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  static List<int> _bigIntToBytes(BigInt v) {
    if (v == BigInt.zero) return [0x00];
    final out = <int>[];
    var t = v;
    while (t > BigInt.zero) {
      out.insert(0, (t & BigInt.from(0xff)).toInt());
      t = t >> 8;
    }
    return out;
  }

  /// 从交易输入携带的「spk 模板」推导 prevout：明文场景下，如果输入
  /// 的 scriptSig 携带了 P2TR 输出脚本（签名前预填充），可直接取用金额 0
  /// 不可行——金额必须显式提供，故此处仅支持脚本从输入预填、金额由
  /// 调用方经 prevOuts 显式传入；未提供 prevOuts 且无法推导时抛错。
  List<NativePrevOut> _derivePrevOutsFromTx(NativeTx tx, Uint8List xOnly) {
    if (tx.inputs.isEmpty) {
      throw const FormatException('交易没有输入，无法签名');
    }
    // 本端无法从交易体还原 prevout 金额；要求调用方显式提供。
    throw ArgumentError(
        '缺少 prevOuts 上下文（BIP341 sighash 需要 prevout scriptPubKey 与金额）。'
        '请由 UTXO 选择层提供 NativePrevOut 列表。');
  }

  static String _stripHexPrefix(String hex) =>
      hex.trim().startsWith('0x') ? hex.trim().substring(2) : hex.trim();

  static Uint8List _hexToBytes(String hex) {
    if (hex.length.isOdd) throw const FormatException('hex 长度必须为偶数');
    return Uint8List.fromList(List.generate(
        hex.length ~/ 2, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
  }
}