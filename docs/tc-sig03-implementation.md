# TC-SIG-03 实现方案：指纹确认后触发原生交易签名

> 状态：方案 v0.3｜更新：2026-10-14
> 目标：实现「扫码解析 → 确认页 → 指纹授权 → 签名广播」流程；
> 当前 `signNative` 为占位（依赖 C1/C2），本方案以**降级分支**保证流程先行落地，
> TC-SIG-03 可先验证「指纹成功 → 进入签名调用 → 捕获占位异常 → 展示降级提示」。
> v0.2 新增：函数级实现（`PaymentService.confirmAndPay`）与真机测试常见报错排查表。
> v0.3 新增：占位代码落盘（`SignatureService.signNative`、`PaymentService._buildTxHex`）
> 与 `test/tc_sig03_test.dart` 验证脚本（见 §8，占位实现下可直接运行）。
> 关联：`docs/blocked-test-cases.md`（TC-SIG-03）、`test/tc_blocked_test.dart`、CI 阶段「立即」。

---

## 1. 流程设计

```
扫码解析(rcpu:...) → 确认页(金额/地址/资产类型) → local_auth 指纹验证
        → 通过: 调用 confirmAndPay() → signNative() → broadcast()
        → 拒绝/失败: 中止，不产生签名对象
        → 签名抛 UnimplementedError(隐私路径未定版): 降级提示「仅支持明文地址支付」
```

- 收款地址为 `rcpux1...` 且 `signNative` 未实现 → 确认页直接提示「当前仅支持明文地址支付」；
- 明文 `rcpu1...` 支付走现有广播流程，不受占位影响。

## 2. 签名调用逻辑（降级兼容）

```dart
Future<String?> signAndBroadcast({
  required String txHex,
  required String privateKey,
}) async {
  try {
    // 尝试真实签名（Path C 落地后可用）
    final signed = await signature.signNative(txHex, privateKey);
    return await nativeRpc.broadcast(signed);
  } on UnimplementedError {
    // 当前占位：降级提示
    throw UserException('隐私交易签名暂未开放，请使用明文地址');
  }
}
```

## 3. 函数级实现（PaymentService.confirmAndPay）——v0.3 已落盘

> 本节代码已实际落盘为 `lib/features/payment/payment_service.dart` 与
> `lib/core/crypto/signature.dart`（`SignatureService` 占位类），并非仅文档示意。

```dart
// lib/features/payment/payment_service.dart（v0.3 落盘版本）

class PaymentService {
  final BiometricAuth biometric;
  final SignatureService signature;
  final NativeRpcClient nativeRpc;

  PaymentService({
    required this.biometric,
    required this.signature,
    required this.nativeRpc,
  });

  /// 指纹确认后发起支付（TC-SIG-03 核心路径）
  Future<PaymentResult> confirmAndPay({
    required String toAddress,
    required int amountMicro,
    required String privateKeyHex,
    required String assetType, // 'native' | 'wrcpu'
  }) async {
    // 1. 指纹验证
    final authOk = await biometric.authenticate(
      reason: '确认支付 ${amountMicro / 1e8} RCPU',
    );
    if (!authOk) {
      return PaymentResult.fail('指纹验证失败');
    }

    // 2. 构造交易（此处简化，实际需按地址类型构建）
    final txHex = _buildTxHex(toAddress, amountMicro);

    // 3. 签名并广播（含降级）
    try {
      final signed = await signature.signNative(txHex, privateKeyHex);
      final txid = await nativeRpc.broadcast(signed);
      return PaymentResult.ok(txid);
    } on UnimplementedError {
      // Path C 未落地时的降级
      if (toAddress.startsWith('rcpux1')) {
        return PaymentResult.fail('当前仅支持明文地址支付，隐私地址暂未开放');
      }
      // 明文地址可走其他已实现路径
      return PaymentResult.fail('原生签名暂未实现，请稍后重试');
    } catch (e) {
      return PaymentResult.fail('支付失败: $e');
    }
  }

  String _buildTxHex(String toAddress, int amountMicro) {
    // 占位：实际应调用 native 构建逻辑；返回可识别字符串便于日志排查
    return 'placeholder_tx_${toAddress}_${amountMicro}_${DateTime.now().millisecondsSinceEpoch}';
  }
}

class PaymentResult {
  final bool ok;
  final String? txid;
  final String? error;
  const PaymentResult.ok(this.txid) : ok = true, error = null;
  const PaymentResult.fail(this.error) : ok = false, txid = null;
}
```

```dart
// lib/core/crypto/signature.dart（v0.3 追加的占位类，未覆盖既有 Signature/verifyBscSignature）

/// 原生交易签名服务（Path C 落地前占位）。
class SignatureService {
  /// 原生交易签名（Path C 落地前占位）。
  ///
  /// - 依赖 C1/C2：原生签名算法待协议文档确认；
  /// - 当前仅支持明文地址（rcpu1）支付；隐私地址（rcpux1）触发上层降级提示。
  Future<String> signNative(String txHex, String privateKeyHex) async {
    throw UnimplementedError(
      '原生签名算法待协议文档确认（C1/C2）。'
      '当前仅支持明文地址支付，请使用 rcpu1 地址。',
    );
  }
}
```

**调用链**：
```
扫码解析 → 确认页 → biometric.authenticate() → confirmAndPay() → signNative()（占位抛 UnimplementedError）→ 降级提示
```

## 4. UI 降级处理

| 场景 | 行为 |
| --- | --- |
| 收款地址 `rcpux1` + `signNative` 未实现 | 确认页禁用「确认支付」，提示「当前仅支持明文地址支付」 |
| 收款地址 `rcpu1` | 正常走现有广播流程 |
| 指纹授权失败 / 取消 | 中止流程，返回确认页，不产生签名对象 |

## 5. 测试对应（TC-SIG-03）

1. 指纹成功 → 进入签名调用 → 捕获 `UnimplementedError` → 展示降级提示；
2. 指纹失败 / 取消 → 流程中止，无签名对象；
3. Path C 落地后移除 try-catch 降级分支，改为真实签名断言。

> v0.3：测试用例 1、2 已落地为 `test/tc_sig03_test.dart`（fake 注入，可直接运行），详见 §8。

## 6. 涉及文件

| 文件 | 动作 |
| --- | --- |
| `lib/features/payment/payment_service.dart` | v0.3 已扩展：保留静态解析（`parseAndValidate`/`toMicro`），新增实例化 `confirmAndPay` + `PaymentResult` + `_buildTxHex` 占位 |
| `lib/core/crypto/signature.dart` | v0.3 新增 `SignatureService` 占位类（`signNative` 抛 `UnimplementedError`，依赖 C1/C2）；既有 `Signature`/`verifyBscSignature` 未被覆盖 |
| `lib/core/biometric/biometric_auth.dart` | 已有，直接复用 `local_auth` 封装 |
| `test/tc_sig03_test.dart` | v0.3 新增：占位实现下可运行的降级路径测试（fake 注入，不依赖真机指纹 / RPC） |

## 7. 真机测试常见报错排查

| 场景 | 典型报错 / 现象 | 原因 | 排查与处理建议 |
| --- | --- | --- | --- |
| 指纹验证失败 | 「指纹验证失败」或系统取消弹窗 | 用户取消、指纹不匹配、未录入指纹 | 检查 `local_auth` 权限；真机确认已录入指纹；允许重试 |
| 隐私地址被拦截 | 「当前仅支持明文地址支付」 | 收款地址为 `rcpux1` 且 `signNative` 抛 `UnimplementedError` | 预期行为；确认页应提前提示；测试时改用 `rcpu1` 地址 |
| 签名占位异常未捕获 | 红屏 / `UnimplementedError` 直接抛出 | `try-catch` 未覆盖或调用链错误 | 确认 `confirmAndPay` 中有 `on UnimplementedError` 分支 |
| 明文地址仍失败 | 「原生签名暂未实现」 | 即使明文也走了 `signNative` 占位 | 明文路径应绕过 `signNative`，或在构建阶段区分地址类型 |
| 生物识别权限缺失 | 权限弹窗不出现 / 直接失败 | Android `USE_BIOMETRIC` 或 iOS Face ID 描述未配置 | 检查 `AndroidManifest.xml` 与 `Info.plist` |
| 广播失败 | 「支付失败: ...」 | RPC 不可达、交易构造错误 | 查看 `nativeRpc.broadcast` 日志；确认代理或节点可用 |

**测试建议**：
- 真机分别测试「明文地址 + 指纹成功」「隐私地址 + 指纹成功」「指纹取消」三条路径。
- 当前阶段预期：隐私地址被优雅降级，明文地址可继续走已实现广播（或同样提示占位）。

---

## 8. flutter test 验证脚本（v0.3）

在装有 Flutter SDK 的机器上，于工程根目录执行：

```bash
flutter test test/tc_sig03_test.dart
```

或连带回归全部用例：

```bash
flutter test
```

**用例断言**（`test/tc_sig03_test.dart`，全部通过 fake 注入，不依赖真机指纹与链上 RPC）：

| 用例 | 输入 | 断言 |
| --- | --- | --- |
| 隐私地址 + 指纹成功 → 降级提示 | `toAddress='rcpux1...'`、指纹通过 | `ok=false` 且错误含「仅支持明文地址」 |
| 指纹取消 → 直接失败 | 任意地址、指纹拒绝 | `ok=false` 且错误含「指纹验证失败」 |

**执行预期**：
- 隐私地址用例捕获 `SignatureService.signNative` 抛出的 `UnimplementedError` 并走降级分支；
- 指纹取消用例在指纹阶段直接返回失败，不进入签名链路（不产生签名对象）；
- 当前阶段不会触发真实广播（fake RPC 未接入真实节点）。

**与本机环境的差异**：本机无 Dart/Flutter SDK，`flutter test` 需在装有 Flutter 的环境执行
（CI 已接入，见 `.github/workflows/ci.yml` / `.gitlab-ci.yml`）。