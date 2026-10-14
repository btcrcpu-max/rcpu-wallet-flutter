# 阻塞用例详情（C1–C4 依赖登记）

> 状态：跟踪表 v0.1｜更新：2026-10-14
> 来源：`test/tc_blocked_test.dart`（🔴 阻塞用例，当前均以 `skip:` 登记，
> 保证 `flutter test` 可直接运行、跳过项不影响通过率）。
> 用途：把 12 个阻塞用例的依赖、当前行为与解阻塞后期望集中成表，
> 供 Path C 协议文档（C1/C2）与内部契约（C3/C4）定稿后逐条解锁。
> 关联文档：`docs/internal-bridge-doc.md`（C1–C5 追踪）、`docs/bridge-api-contract-c4.md`（桥契约）。

---

## 1. 依赖项定义

| 编号 | 名称 | 归属 | 状态 |
| --- | --- | --- | --- |
| C1 | 官方 Path C 协议文档（仓库 + CT 规范原文） | RCPU 官方 | ⏳ 待获取（P0） |
| C2 | Path C BIP32 路径与 `rcpux1` 编码规范 | 依赖 C1 | ⏳ 待 C1（P0） |
| C3 | viewing key 格式与代理 unblind 最小权限 | 内部自研 | 🟢 我方内部定义 |
| C4 | 桥 + 代理契约定稿 | 内部自研 | 🟡 桥契约草案已出（`bridge-api-contract-c4.md`），代理见 `proxy-rpc-schema.md` |

---

## 2. 阻塞用例总表

| 用例号 | 用例名 | 依赖 | 当前行为（代码基线） | 解阻塞后期望 |
| --- | --- | --- | --- | --- |
| TC-DRV-01 | 明文地址与官方钱包一致 | C2 | `derivation._protocolEncode` 为占位伪编码（hex），无法与官方向量比对 | 按 C2 定版编码派生明文地址，与官方钱包生成地址**逐字符一致** |
| TC-DRV-02 | 隐私地址与官方钱包一致 | C1/C2 | `nativePrivatePath` 为占位 `m/44'/307'/0'/1/0`；同助记词派生结果仅内部自洽 | 按官方路径模板派生 `rcpux1` 地址，与官方一致 |
| TC-DRV-05 | spending/viewing 双钥派生 | C1/C2 | 派生只产出单一密钥，key bundle（spending/viewing）结构未定 | 双钥分别按官方规则派生，均可从助记词稳定恢复 |
| TC-SIG-02 | 原生 CT 交易签名通过官方向量 | C1 | `signNative` 抛出 `UnimplementedError` | 按 C1 CT 签名规范实现，官方向量断言全部通过 |
| TC-SIG-03 | 指纹确认后触发签名 | 支付流程 | `payment_service` 流程未实现；无「授权→签名→中止」分支 | 指纹授权 **true** → 生成签名对象并进入广播；**false** → 中止且不产生签名对象 |
| TC-CT-IN-01 | CT 收款到账（代理 unblind） | C3/C4 | 客户端 `resolve_ct` 契约已落地（§6.1 对象形态）；真实代理服务未部署，余额仍按明文统计 | 代理完成 ECDH + 解承诺 + range proof，本人 CT 输出计入余额（`ctRaw` 正确）；客户端契约层已由 tc_ct_resolve_test.dart 锚定 |
| ~~TC-CT-IN-02~~ | ~~单笔 CT 明细本地解析~~ | ~~C1/C3/C4~~ | ~~`ct_resolver` / `resolveCtOutput` 占位~~ | ✅ 已解锁（2026-10-14）：`resolve_ct` 契约（金额 + verified）落地于 `ct_resolver.dart` / `native_rpc.dart`，锚定 tc_ct_resolve_test.dart；对手方/时间字段待 `get_history` privacy 模型补齐 |
| TC-CT-OUT-02 | 隐私付款签名广播 | C1/C4 | `signNative` 占位 + `broadcast_tx` 链路未通 | 隐私付款签名后经代理广播成功，返回 `txid` 且状态可查（错误映射 -32004） |
| TC-MINT-03 | 桥 API 专属存款地址获取 | C3/C4 | 桥契约草案 v0.1；无真实服务，`fetchDepositAddress` 返回 null 降级 WebView | 按 `bridge-api-contract-c4.md` §2.1 返回专属明文 `rcpu1` 地址；`rcpux1` 拒绝（4002） |
| TC-MINT-04 | 累计满 10 铸造真实到账 | C4 | 依赖桥真实处理；客户端仅 3 次退避轮询（10s/20s/40s） | 累计达标后 `state=minted`、`wrcpuTxHash` 非空，BSC 钱包 wRCPU 实际到账 |
| TC-REDEEM-03 | 赎回广播（burn + 指定收款） | C1/C4 | `bsc_rpc.redeem` 按 `redeem(uint256, string)` 封装；方法形态待桥确认（burn 备选） | 确认后的合约方法广播成功，收款地址为手机钱包自身 `rcpu1` 地址 |
| TC-REDEEM-04 | 赎回后原生余额自动刷新 | C3/C4 | 代理余额缓存 + 桥回调/轮询未定；当前手动刷新过渡 | 赎回发放完成后，原生余额经代理刷新自动到账并更新 UI |

---

## 3. 依赖分布统计

| 依赖组合 | 用例数 | 用例 |
| --- | --- | --- |
| C1 单独 | 1 | TC-SIG-02 |
| C1/C2 | 2 | TC-DRV-02、TC-DRV-05 |
| C2 单独 | 1 | TC-DRV-01 |
| C3/C4 | 3 | TC-CT-IN-01、TC-MINT-03、TC-REDEEM-04 |
| C1/C4 | 2 | TC-CT-OUT-02、TC-REDEEM-03 |
| C4 单独 | 1 | TC-MINT-04 |
| 支付流程实现 | 1 | TC-SIG-03 |
| **合计** | **11** | —（TC-CT-IN-02 已解锁，2026-10-14） |

**解锁路径**：
- C1/C2（官方文档）到位 → 解锁 4 项（TC-DRV-01/02/05、TC-SIG-02）、TC-CT-OUT-02 与 TC-REDEEM-03 的签名前提；
- C3（viewing key 内部定稿）→ 客户端契约层已落地（TC-CT-IN-02 于 2026-10-14 解锁）；TC-CT-IN-01 剩余端到端依赖真实代理服务（ECDH + 解承诺 + range proof）；
- C4（桥契约，草案见 `bridge-api-contract-c4.md`）→ 解锁 TC-MINT-03/04、TC-REDEEM-03/04 中的服务端依赖；
- 支付流程实现（TC-SIG-03）不依赖外部，可与 C1–C4 并行推进。

---

## 4. 解锁操作指引

1. **C1/C2 到位**：按 `docs/path-c-fix-list.md` 执行代码修改（`derivation.dart` / `signature.dart`），随后移除 TC-DRV-01/02/05、TC-SIG-02 的 `skip` 并补官方向量断言；
2. **C3 定稿**：✅ 客户端侧已落地（2026-10-14）：`proxy-rpc-schema.md` §6.1 对象形态实现于 `native_rpc.resolveCt` + `ct_resolver.resolveOutput`，tc_ct_resolve_test.dart 锚定；待真实代理部署后验收 TC-CT-IN-01；
3. **C4 定稿**：按 `bridge-api-contract-c4.md` §8 验证清单逐条对桥服务验收，再移除 TC-MINT-03/04、TC-REDEEM-03/04 的 `skip`；
4. **TC-SIG-03**：随 `payment_service` 实现（指纹授权分支）直接启用，无外部依赖。

> 所有 `skip` 用例解锁后，仍须整体跑通 `flutter test` 并保持 100% 通过率（CI 见
> `.github/workflows/ci.yml` 与 `.gitlab-ci.yml` 的 test 阶段）。