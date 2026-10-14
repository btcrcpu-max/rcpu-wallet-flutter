import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储封装：Android Keystore / iOS Keychain。
///
/// 助记词与本地密钥只允许存此存储，禁止明文写文件。
class SecureStore {
  static const _keyMnemonic = 'rcpu_mnemonic';
  static const _keyInitialized = 'rcpu_initialized';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 保存助记词（加密落盘，仅存内存副本参与派生）。
  Future<void> saveMnemonic(String mnemonic) async {
    await _storage.write(key: _keyMnemonic, value: mnemonic);
  }

  /// 读取助记词（仅解锁流程调用，调用后及时置空）。
  Future<String?> readMnemonic() async {
    return _storage.read(key: _keyMnemonic);
  }

  /// 删除助记词（退出 / 重置钱包）。
  Future<void> deleteMnemonic() async {
    await _storage.delete(key: _keyMnemonic);
  }

  /// 是否已初始化钱包。
  Future<bool> isInitialized() async {
    return await _storage.read(key: _keyInitialized) == '1';
  }

  Future<void> markInitialized() async {
    await _storage.write(key: _keyInitialized, value: '1');
  }
}