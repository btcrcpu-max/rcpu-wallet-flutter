import 'dart:typed_data';

import '../../core/crypto/derivation.dart';
import '../../core/crypto/mnemonic.dart';
import '../../core/models/address.dart';
import '../../core/secure_store/secure_store.dart';

/// 钱包生命周期服务：创建 / 导入 / 解锁 / 派生。
///
/// 同一助记词派生三套地址（原生明文 rcpu1、原生隐私 rcpux1、BSC 0x）。
class WalletService {
  final SecureStore _store;

  WalletService(this._store);

  /// 创建新钱包（12 词助记词），返回助记词供首次展示备份。
  Future<String> createWallet() async {
    final mnemonic = Mnemonic.generate12();
    await _store.saveMnemonic(mnemonic);
    await _store.markInitialized();
    return mnemonic;
  }

  /// 导入既有助记词，校验合法性。
  Future<String> importMnemonic(String mnemonic) async {
    if (!Mnemonic.isValid(mnemonic)) {
      throw const FormatException('助记词无效');
    }
    await _store.saveMnemonic(mnemonic.trim());
    await _store.markInitialized();
    return mnemonic.trim();
  }

  /// 是否已初始化。
  Future<bool> isInitialized() => _store.isInitialized();

  /// 解锁后派生地址集。
  Future<DerivedAddresses> deriveAddresses() async {
    final mnemonic = await _store.readMnemonic();
    if (mnemonic == null) {
      throw StateError('钱包未初始化');
    }
    final d = Derivation(mnemonic);
    return DerivedAddresses(
      plain: d.deriveNativePlainAddress(),
      private: d.deriveNativePrivateAddress(),
      bsc: d.deriveBscAddress(),
    );
  }

  /// 隐私路径（`m/84'/1'/0'/1/0`）花费私钥，供隐私地址 CT 余额解盲使用。
  ///
  /// 解盲（Path C rewind nonce = HKDF(ECDH(priv, ephemeral))) 需要该私钥；
  /// 私钥仅在内存中派生，不落盘、不外传。
  Future<Uint8List> deriveNativePrivateSpendPriv() async {
    final mnemonic = await _store.readMnemonic();
    if (mnemonic == null) {
      throw StateError('钱包未初始化');
    }
    return Derivation(mnemonic).deriveNativePrivateKey().spendPriv;
  }
}

/// 派生地址集合。
class DerivedAddresses {
  final Address plain;
  final Address private;
  final Address bsc;

  const DerivedAddresses({
    required this.plain,
    required this.private,
    required this.bsc,
  });
}