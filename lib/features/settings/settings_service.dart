import '../../core/biometric/biometric_auth.dart';
import '../../core/secure_store/secure_store.dart';

/// 设置服务：指纹开关、地址管理、导出助记词、网络切换。
class SettingsService {
  final SecureStore _store;
  final BiometricAuth _biometric;

  SettingsService(this._store, this._biometric);

  Future<bool> biometricEnabled() => _biometric.hasEnrolledBiometrics();

  /// 导出助记词（需二次生物识别确认）。
  Future<String?> exportMnemonic() async {
    final ok = await _biometric.authenticate(reason: '请验证身份以导出助记词');
    if (!ok) return null;
    return _store.readMnemonic();
  }

  /// 重置钱包（删除本地账户数据）。
  Future<void> resetWallet() => _store.deleteMnemonic();
}