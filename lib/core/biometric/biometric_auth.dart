import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 生物识别封装（local_auth）。
///
/// 指纹 / Face ID 仅用于：
/// - 解锁进入钱包
/// - 交易确认
/// 不承载密钥本身。
class BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();
  static const String _kEnabled = 'biometric_enabled';

  /// 设备是否支持生物识别（硬件层面）。
  Future<bool> isAvailable() async {
    return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
  }

  /// 已录入生物特征（用户已在系统里录了指纹/人脸）。
  Future<bool> hasEnrolledBiometrics() async {
    final enrolled = await _auth.getAvailableBiometrics();
    return enrolled.isNotEmpty;
  }

  /// 生物识别开关状态（用户手动开启/关闭）。
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  /// 设置生物识别开关（需先通过 authenticate 验证身份）。
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  /// 弹出系统生物识别确认。
  ///
  /// [reason] 为系统弹窗说明，如「请验证指纹以确认付款」。
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
