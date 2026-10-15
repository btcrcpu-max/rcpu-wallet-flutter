import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/biometric/biometric_auth.dart';
import '../core/network/bsc_rpc.dart';
import '../core/network/native_rpc.dart';
import '../core/secure_store/secure_store.dart';

/// 依赖注入装配（Riverpod）。
///
/// 首次启动时在此注册全局单例；feature 层通过 ref.watch 取用。
/// 钱包初始化前以下依赖均以「未初始化」状态存在，由 wallet feature 激活。

/// 安全存储（Android Keystore / iOS Keychain）。
final secureStoreProvider = Provider<SecureStore>((ref) {
  return SecureStore();
});

/// 生物识别（指纹 / Face ID）。
final biometricAuthProvider = Provider<BiometricAuth>((ref) {
  return BiometricAuth();
});

/// 原生链 RPC 客户端（服务器节点 / 轻量代理）。
final nativeRpcProvider = Provider<NativeRpcClient>((ref) {
  return NativeRpcClient();
});

/// BSC RPC 客户端（web3dart，公共节点）。
final bscRpcProvider = Provider<BscRpcClient>((ref) {
  return BscRpcClient();
});