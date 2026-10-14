import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

/// BIP340 Schnorr 签名（基于 pointycastle 的 secp256k1 曲线自实现）。
///
/// 工程依赖探测（T1）结论：pub 生态的 `bip340` 包与既有 `bip32` 的
/// pointycastle 版本约束冲突，`secp256k1` 包仅 ECDSA，故按 BIP340
/// 规范（BIP-0340：schnorr-signature.media）自实现，复用 pointycastle 3.9.1：
/// - 点乘 `G * k` / 点加 `p1 + p2`（已探测定案）
/// - `decompressPoint(yTilde, x)` 实现 BIP340 `lift_x`（偶 Y）
/// - SHA256Digest 实现 tagged hash
///
/// 覆盖：tagged hash、lift_x、sign（含 aux_rand）、verify。
/// 验证锚点：BIP340 官方 test-vectors（sign + verify 双向）。
class Bip340 {
  static final ECDomainParameters _params = ECCurve_secp256k1();

  /// 曲线阶 n。
  static final BigInt curveOrder = _params.n;

  /// 域素数 p（secp256k1：2^256 - 2^32 - 977）。
  static final BigInt curveField = BigInt.parse(
      'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
      radix: 16);

  /// SHA256(tag) || SHA256(tag) || msg 的 tagged hash（BIP340）。
  static Uint8List taggedHash(String tag, Uint8List msg) {
    final tagHash = _sha256(Uint8List.fromList(tag.codeUnits));
    return _sha256(Uint8List.fromList([...tagHash, ...tagHash, ...msg]));
  }

  /// lift_x：给定 x 坐标，求曲线点，y 取偶数（失败返回 null）。
  ///
  /// BIP340：P = (x, y)，y 为偶；不存在则签名/验签失败。
  static ECPoint? liftX(BigInt x) {
    if (x <= BigInt.zero || x >= curveField) return null;
    try {
      return _params.curve.decompressPoint(0, x);
    } catch (_) {
      return null;
    }
  }

  /// 从 32 字节 x-only 公钥构造曲线点（偶 Y），失败返回 null。
  static ECPoint? pubKeyFromXOnly(Uint8List xOnly32) {
    if (xOnly32.length != 32) return null;
    return liftX(_bytesToBigInt(xOnly32));
  }

/// 压缩公钥（33B `02/03||X`）取 x-only（32B）。
  static Uint8List xOnlyFromPub(Uint8List pub33) {
    assert(pub33.length == 33, '压缩公钥必须为 33 字节');
    return Uint8List.fromList(pub33.sublist(1));
  }

  /// 由 32 字节私钥派生压缩公钥（33B，`02/03||X`）。
  ///
  /// 供交易模板构建与 prevout 校验使用（P2TR 脚本 = `0x51 0x20 || xonly`）。
  static Uint8List pubKeyFromPriv(Uint8List privKey32) {
    if (privKey32.length != 32) {
      throw ArgumentError('私钥必须为 32 字节');
    }
    var d = _bytesToBigInt(privKey32);
    if (d <= BigInt.zero || d >= curveOrder) {
      throw ArgumentError('私钥超出合法范围');
    }
    final p = _params.G * d;
    if (p == null || p.isInfinity) {
      throw StateError('私钥点乘失败');
    }
    return p.getEncoded(true);
  }

  /// BIP340 签名（secp256k1，64 字节 `r(32) || s(32)`）。
  ///
  /// [privKey32] 为 32 字节私钥（大端）；[msg32] 为 32 字节消息哈希
  /// （原生链 P2TR 花费传入 BIP341 sighash 摘要）；
  /// [auxRand32] 为辅助随机数（可空，规范上用 32 字节；空则按全 0）。
  ///
  /// 实现细节：
  /// 1. d = int(priv)；若 d·G 的 Y 为奇，d' = n - d（P 仍为同一 x 的偶 Y 点）；
  /// 2. t = d' XOR tagged_hash("BIP0340/aux", aux)；
  /// 3. k0 = int(tagged_hash("BIP0340/nonce", t || Px || msg)) mod n；
  ///    k0 == 0 时规范定义为无效签名（概率 ~2^-256），此处直接抛错；
  /// 4. R = k0·G；k = R.y 偶 ? k0 : n - k0；
  /// 5. e = int(tagged_hash("BIP0340/challenge", Rx || Px || msg)) mod n；
  /// 6. s = (k + e·d') mod n；返回 Rx(32) || s(32)。
  static Uint8List sign(Uint8List privKey32, Uint8List msg32,
      {Uint8List? auxRand32}) {
    if (privKey32.length != 32 || msg32.length != 32) {
      throw ArgumentError('私钥与消息均须为 32 字节');
    }
    var d = _bytesToBigInt(privKey32);
    if (d <= BigInt.zero || d >= curveOrder) {
      throw ArgumentError('私钥超出合法范围');
    }
    final aux = auxRand32 == null
        ? Uint8List(32)
        : Uint8List.fromList(auxRand32);
    if (aux.length != 32) {
      throw ArgumentError('aux_rand 必须为 32 字节');
    }

    final p = _params.G * d;
    if (p == null || p.isInfinity) {
      throw StateError('私钥点乘失败');
    }
    // 取偶 Y 表示：P 为奇时用 n - d（等价点 -P，x 相同）。
    if (!p.y!.toBigInteger()!.isEven) {
      d = curveOrder - d;
    }
    final px = p.x!.toBigInteger()!;

    final dBytes = _bigIntToBytes(d, 32);
    final t = _xor32(dBytes, taggedHash('BIP0340/aux', aux));
    final k0Bytes = taggedHash(
        'BIP0340/nonce', Uint8List.fromList([...t, ..._bigIntToBytes(px, 32), ...msg32]));
    var k = _bytesToBigInt(k0Bytes) % curveOrder;
    if (k == BigInt.zero) {
      // 概率 ~2^-256；按 BIP340 声明无效签名。
      throw StateError('BIP340 nonce 为零（极小概率），请更换辅助随机数');
    }
    final rPoint = _params.G * k;
    if (rPoint == null || rPoint.isInfinity) {
      throw StateError('nonce 点乘失败');
    }
    if (!rPoint.y!.toBigInteger()!.isEven) {
      k = curveOrder - k;
    }
    final r = rPoint.x!.toBigInteger()!;

    final e = _bytesToBigInt(taggedHash(
            'BIP0340/challenge',
            Uint8List.fromList([
              ..._bigIntToBytes(r, 32),
              ..._bigIntToBytes(px, 32),
              ...msg32,
            ]))) %
        curveOrder;
    final s = (k + e * d) % curveOrder;
    return Uint8List.fromList([
      ..._bigIntToBytes(r, 32),
      ..._bigIntToBytes(s, 32),
    ]);
  }

  /// BIP340 验签。成功返回 true；任何结构/数学失败返回 false（不抛异常，
  /// 与 `Signature.verifyBscSignature` 的容错口径一致）。
  static bool verify(Uint8List pubXOnly32, Uint8List msg32, Uint8List sig64) {
    if (pubXOnly32.length != 32 || msg32.length != 32 || sig64.length != 64) {
      return false;
    }
    final p = pubKeyFromXOnly(pubXOnly32);
    if (p == null) return false;
    // BIP340：拒绝所有元素为 0 的签名（r == 0 或 s == 0）。
    final r = _bytesToBigInt(sig64.sublist(0, 32));
    final s = _bytesToBigInt(sig64.sublist(32, 64));
    if (s == BigInt.zero || r == BigInt.zero) return false;
    if (r >= curveField || s >= curveOrder) return false;

    final e = _bytesToBigInt(taggedHash(
            'BIP0340/challenge',
            Uint8List.fromList([
              ..._bigIntToBytes(r, 32),
              ...pubXOnly32,
              ...msg32,
            ]))) %
        curveOrder;
    // R = s·G - e·P（-e 用 n - e 计算）。
    final negE = (curveOrder - e) % curveOrder;
    final rPoint = _params.G * s;
    final eP = p * negE;
    if (rPoint == null || eP == null) return false;
    final sum = rPoint + eP;
    if (sum == null || sum.isInfinity) return false;
    if (!sum.y!.toBigInteger()!.isEven) return false;
    return sum.x!.toBigInteger() == r;
  }

  static Uint8List _sha256(Uint8List input) {
    final d = SHA256Digest();
    return d.process(input);
  }

  static Uint8List _xor32(Uint8List a, Uint8List b) {
    assert(a.length == b.length);
    return Uint8List.fromList(
        List.generate(a.length, (i) => a[i] ^ b[i]));
  }

  /// 大端 32/64 字节日志转 BigInt（截断前导 0）。
  static BigInt _bytesToBigInt(Uint8List bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  /// BigInt 转定长大端字节（[len] 不足补 0，超出抛错）。
  static Uint8List _bigIntToBytes(BigInt v, int len) {
    var hex = v.toRadixString(16);
    if (hex.length > len * 2) {
      throw ArgumentError('数值超出 $len 字节范围');
    }
    hex = hex.padLeft(len * 2, '0');
    return Uint8List.fromList(List.generate(
        len, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
  }
}