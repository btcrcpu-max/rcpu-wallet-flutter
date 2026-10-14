import 'package:local_auth/local_auth.dart';

/// 生物识别封装（local_auth）。
///
/// 指纹 / Face ID 仅用于：
/// - 解锁进入钱包
/// - 交易确认
/// 不承载密钥本身。
class BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  /// 设备是否支持生物识别。
  Future<bool> isSupported() async {
    return _auth.canCheckBiometrics;
  }

  /// 已录入生物特征。
  Future<bool> hasEnrolledBiometrics() async {
    return _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
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