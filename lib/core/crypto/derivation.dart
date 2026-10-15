import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:web3dart/web3dart.dart';

import '../models/address.dart';
import 'bech32.dart';

/// 地址派生工具。
///
/// 同一助记词派生三套地址：
/// - 原生 RCPU 明文（`rcpu1...`，P2WPKH bech32）
/// - 原生 RCPU 隐私（`rcpux1...`，Path C bech32m）
/// - BSC 地址（标准 BIP44，`0x...`）
///
/// 编码规范（C2 已解锁，`docs/path-c-spec.md` §3）：
/// - 隐私 `rcpux1`：bech32m（HRP=`rcpux`），payload =
///   `0x00 || HASH160(compressed_pub 33B) || compressed_pub 33B`（54 字节）→ 8→5 ConvertBits；
/// - 明文 `rcpu1`：bech32（HRP=`rcpu`），payload = `0x00 || HASH160(pub 33B)`（21 字节）。
class Derivation {
  /// BIP44 路径：m/44'/60'/0'/0/0（BSC / Ethereum）
  static const String bscPath = "m/44'/60'/0'/0/0";

  /// 原生 RCPU 明文路径。
  /// 工程自定占位（非协议强制）：官方仓库未定义 Native RCPU 的 BIP32 路径常量，
  /// Coin type 307 未在 SLIP-44 注册；派生路径属钱包实现层决策。
  /// 与官方钱包导出地址的一致性待官方钱包源码/官方确认（docs/path-c-spec.md §4.1）。
  static const String nativePlainPath = "m/44'/307'/0'/0/0";

  /// 原生 RCPU 隐私路径（默认 Path C）。
  /// 同为工程自定占位（非协议强制），沿用「change/privacy」分支习惯；
  /// 定版依据同 [nativePlainPath]。
  static const String nativePrivatePath = "m/44'/307'/0'/1/0";

  /// 隐私地址 HRP（mainnet）。
  static const String confidentialHrp = 'rcpux';

  /// 明文地址 HRP（mainnet）。
  static const String plainHrp = 'rcpu';

  /// 隐私地址版本字节（P2WPKH-Confidential）。
  static const int confidentialVersion = 0x00;

  final String mnemonic;
  late final Uint8List _seed;

  Derivation(this.mnemonic) {
    if (!bip39.validateMnemonic(mnemonic.trim())) {
      throw const FormatException('助记词校验失败');
    }
    _seed = Uint8List.fromList(bip39.mnemonicToSeed(mnemonic.trim()));
  }

  /// 派生指定 BIP32 路径的扩展私钥。
  bip32.BIP32 deriveKey(String path) {
    return bip32.BIP32.fromSeed(_seed).derivePath(path);
  }

  /// 派生 BSC 地址（标准 BIP44）。
  Address deriveBscAddress() {
    final key = deriveKey(bscPath);
    final ethAddr = EthPrivateKey(key.privateKey!).address;
    return Address(ethAddr.hexEip55, 'evm');
  }

  /// 派生原生明文地址（P2WPKH bech32，`rcpu1...`）。
  Address deriveNativePlainAddress() {
    final bundle = deriveNativePlainKey();
    return Address(
      _encodePlain(bundle.spendPub),
      'plain',
    );
  }

  /// 派生原生隐私地址（Path C bech32m，`rcpux1...`）。
  Address deriveNativePrivateAddress() {
    final bundle = deriveNativePrivateKey();
    return Address(
      _encodeConfidential(bundle.spendPub),
      'private',
    );
  }

  /// 派生明文花费密钥组（`m/44'/307'/0'/0/0`）。
  NativeKeyBundle deriveNativePlainKey() {
    return NativeKeyBundle.fromBip32(deriveKey(nativePlainPath));
  }

  /// 派生隐私花费密钥组（`m/44'/307'/0'/1/0`）。
  NativeKeyBundle deriveNativePrivateKey() {
    return NativeKeyBundle.fromBip32(deriveKey(nativePrivatePath));
  }

  /// 隐私地址编码：bech32m（`0x00 || HASH160(pub33) || pub33`）。
  static String _encodeConfidential(Uint8List pub33) {
    final keyid = hash160(pub33);
    final payload = Uint8List.fromList([
      confidentialVersion,
      ...keyid,
      ...pub33,
    ]);
    return Bech32.encode(confidentialHrp, payload, bech32m: true);
  }

  /// 明文地址编码：bech32（`0x00 || HASH160(pub33)`）。
  static String _encodePlain(Uint8List pub33) {
    final keyid = hash160(pub33);
    final payload = Uint8List.fromList([
      confidentialVersion,
      ...keyid,
    ]);
    return Bech32.encode(plainHrp, payload, bech32m: false);
  }

  /// HASH160 = RIPEMD160(SHA256(msg))。
  static Uint8List hash160(Uint8List msg) {
    final sha = SHA256Digest();
    final shaOut = sha.process(msg);
    final rmd = RIPEMD160Digest();
    return Uint8List.fromList(rmd.process(shaOut));
  }
}

/// 原生 RCPU 密钥三件套：花费私钥 / 压缩公钥（33B）/ keyid（HASH160）。
///
/// 由同一路径确定性派生，供 signature / ct_resolver 复用。
class NativeKeyBundle {
  /// 花费私钥（32 字节原始字节，内存驻留，不落盘）。
  final Uint8List spendPriv;

  /// 压缩公钥（33 字节，`02/03 || X`）。
  final Uint8List spendPub;

  /// keyid = HASH160(spendPub)（20 字节）；隐私地址 payload 首段。
  final Uint8List keyid;

  NativeKeyBundle({
    required this.spendPriv,
    required this.spendPub,
    required this.keyid,
  });

  /// 从 BIP32 扩展私钥构造。
  factory NativeKeyBundle.fromBip32(bip32.BIP32 key) {
    final priv = key.privateKey!;
    final pub = key.publicKey;
    return NativeKeyBundle(
      spendPriv: Uint8List.fromList(priv),
      spendPub: Uint8List.fromList(pub),
      keyid: Derivation.hash160(Uint8List.fromList(pub)),
    );
  }

  /// 校验 keyid 是否与公钥一致（协议约束：blinding key 与 spend key 同一把）。
  bool get keyidValid =>
      _bytesEqual(Derivation.hash160(spendPub), keyid);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}