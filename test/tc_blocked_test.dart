import 'package:flutter_test/flutter_test.dart';

/// 🔴 阻塞用例登记（对应 docs/ct-test-cases.md 中的阻塞项）。
///
/// 这些用例依赖 C1/C2/C3/C4 待确认项，当前以 skip 登记并注明依赖编号，
/// 保持 `flutter test` 可直接运行（跳过项不影响通过率）。
/// 依赖项补齐后，将 skip 移除并补充实现断言。
///
/// | 用例 | 依赖 | 阻塞原因 |
/// | --- | --- | --- |
/// | TC-DRV-01 官方地址比对 | C2 | `_protocolEncode` 伪编码待定版 |
/// | TC-DRV-02 隐私地址派生一致 | C1/C2 | `nativePrivatePath` 占位 |
/// | TC-DRV-05 双钥（spending/viewing）派生 | C1/C2 | key bundle 结构待协议 |
/// | ~~TC-SIG-02 原生 CT 交易签名~~ | ~~C1~~ | 已解锁：BIP340 官方向量锚定于 tc_bip340_test.dart（8/8） |
/// | TC-SIG-03 指纹确认后签名触发 | 签名流程 | payment 流程待实现 |
/// | TC-CT-IN-01 CT 收款到账 | C3/C4 | 代理 unblind 契约待定 |
/// | TC-CT-IN-02 单笔明细本地解析 | C1/C3/C4 | `ct_resolver` 占位 |
/// | TC-CT-OUT-02 隐私付款签名广播 | C1/C4 | 签名 + 代理广播待通 |
/// | TC-MINT-03 桥 API 专属地址 | C4 | 桥 API 契约待定 |
/// | TC-MINT-04 真实铸造到账 | C4 | 依赖桥处理 |
/// | TC-REDEEM-03 赎回广播 | C1/C4 | `redeem` 契约待桥确认 |
/// | TC-REDEEM-04 到账自动刷新 | C3/C4 | 代理余额缓存 + 桥回调 |
void main() {
  group('🔴 依赖 C1/C2（Path C 协议文档）', () {
    test('TC-DRV-01 明文地址与官方钱包一致', () {}, skip: '依赖 C2：_protocolEncode 伪编码待定版');
    test('TC-DRV-02 隐私地址与官方钱包一致', () {}, skip: '依赖 C1/C2：nativePrivatePath 为占位 m/44\'/307\'/0\'/1/0');
    test('TC-DRV-05 spending/viewing 双钥派生', () {}, skip: '依赖 C1/C2：key bundle 结构待协议定');
    // TC-SIG-02 已解锁：BIP340 官方向量（8/8）与 signNative 闭环分别
    // 锚定于 tc_bip340_test.dart / tc_sig04_sign_native_test.dart。
  });

  group('🔴 依赖 C3/C4（代理契约）', () {
    test('TC-CT-IN-01 CT 收款到账（代理 unblind）', () {}, skip: '依赖 C3/C4：代理须完成 ECDH + 解承诺 + range proof');
    test('TC-CT-IN-02 单笔 CT 明细本地解析', () {}, skip: '依赖 C1/C3/C4：ct_resolver 与 resolveCtOutput 均为占位');
    test('TC-CT-OUT-02 隐私付款签名广播', () {}, skip: '依赖 C1/C4：signNative 占位 + 广播链路未通');
    test('TC-MINT-03 桥 API 专属存款地址获取', () {}, skip: '依赖 C3/C4：桥 API 契约待定（API 优先，WebView 降级已就绪）');
    test('TC-MINT-04 累计满 10 铸造真实到账', () {}, skip: '依赖 C4：真实铸造需桥处理');
    test('TC-REDEEM-03 赎回广播（burn + 指定收款）', () {}, skip: '依赖 C1/C4：redeem 契约待桥确认');
    test('TC-REDEEM-04 赎回后原生余额自动刷新', () {}, skip: '依赖 C3/C4：代理余额缓存 + 桥回调/轮询');
  });

  group('🔴 依赖支付流程实现', () {
    test('TC-SIG-03 指纹确认后触发签名', () {}, skip: 'payment 流程待实现：授权 true 进入签名、false 中止且不产生签名对象');
  });
}