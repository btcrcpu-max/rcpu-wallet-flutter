import 'package:bip39/bip39.dart' as bip39;

/// 助记词工具：BIP39 生成与校验。
class Mnemonic {
  /// 生成 12 词助记词（128 bit 熵，库内使用安全随机源）。
  static String generate12() {
    return bip39.generateMnemonic(strength: 128);
  }

  /// 校验助记词是否合法。
  static bool isValid(String mnemonic) {
    try {
      return bip39.validateMnemonic(mnemonic.trim());
    } catch (_) {
      return false;
    }
  }

  /// 助记词转种子（用于派生）。
  static List<int> toSeed(String mnemonic, {String passphrase = ''}) {
    return bip39.mnemonicToSeed(mnemonic.trim(), passphrase: passphrase);
  }
}

/// 助记词校验异常。
class MnemonicException implements Exception {
  final String message;
  MnemonicException(this.message);

  @override
  String toString() => message;
}