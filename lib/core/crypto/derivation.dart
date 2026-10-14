import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:web3dart/web3dart.dart';

import '../models/address.dart';

/// 地址派生工具。
///
/// 同一助记词派生三套地址：
/// - 原生 RCPU 明文（`rcpu1...`）
/// - 原生 RCPU 隐私（`rcpux1...`，默认 Path C）
/// - BSC 地址（标准 BIP44，`0x...`）
///
/// 说明：BSC 地址为标准 BIP44 派生；原生 RCPU 地址的完整编码
/// （bech32 风格前缀 / CT 密钥）需与链上协议核对后补齐，
/// 当前以协议占位字节拼接地址展示，见 [Address]。
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

  /// 派生原生明文地址（协议层编码 `rcpu1...`）。
  Address deriveNativePlainAddress() {
    final key = deriveKey(nativePlainPath);
    return Address('rcpu1${_protocolEncode(key)}', 'plain');
  }

  /// 派生原生隐私地址（默认 Path C，协议层编码 `rcpux1...`）。
  Address deriveNativePrivateAddress() {
    final key = deriveKey(nativePrivatePath);
    return Address('rcpux1${_protocolEncode(key)}', 'private');
  }

  /// 协议编码占位：真实编码（bech32 / CT 密钥）与链上规范对齐后替换。
  static String _protocolEncode(bip32.BIP32 key) {
    return key.publicKey.sublist(0, 20).map(_hex2).join();
  }

  static String _hex2(int b) => b.toRadixString(16).padLeft(2, '0');
}