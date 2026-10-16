import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/biometric/biometric_auth.dart';
import '../core/crypto/signature.dart';
import '../core/network/bsc_rpc.dart';
import '../core/network/ct_helper_client.dart';
import '../core/network/native_rpc.dart';
import '../core/secure_store/secure_store.dart';
import '../features/payment/payment_service.dart';

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

/// CT 盲化协处理器客户端（服务器侧 secp256k1-zkp）。
///
/// 仅用于隐私地址（`rcpux1`）收付：输出盲化 / 自身 CT 输出解盲。
/// 私钥永不出设备；该客户端只收发承诺、rangeproof 与客户端自算的 rewind nonce。
final ctHelperProvider = Provider<CtHelperClient>((ref) {
  return CtHelperClient();
});

/// 支付流程服务（指纹确认 → UTXO 选择 → 签名广播）。
final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(
    biometric: ref.watch(biometricAuthProvider),
    signature: SignatureService(),
    nativeRpc: ref.watch(nativeRpcProvider),
    ctHelper: ref.watch(ctHelperProvider),
  );
});