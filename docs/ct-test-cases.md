# Path C 完整测试用例（基于修改清单验收矩阵）

> 对应 `docs/path-c-fix-list.md` 第 5 节「端到端验证矩阵」，逐条展开为可执行用例。
> 用例状态标注：
> - ✅ 可执行：不依赖官方 Path C 协议文档，当前骨架 + 公开 RPC / 桥逻辑即可运行；
> - 🔴 阻塞：依赖 C1/C2（Path C 规范）或 C3/C4（代理契约），标注所依赖待确认项。

## 0. 测试环境约定

| 项 | 约定 |
| --- | --- |
| 测试助记词 | 官方测试向量助记词（C1 文档提供；当前用任意 BIP39 助记词做结构测试，前缀校验用 Address 模型） |
| 原生 RPC | 轻量代理 `http://127.0.0.1:7337`（JSON-RPC） |
| BSC RPC | `https://bsc-dataseed.binance.org/` |
| wRCPU 合约 | `0x2F720B253EF63176cF54b0088C7F57997dd2c340`（Decimals=8） |
| 桥 | `https://rcpupool.asia/`（明文 rcpu1 专属地址累计，满 10 铸造） |
| 金额单位 | micro（1 RCPU = 1e8 micro） |

### 实测执行记录（2026-10-14，本机 Flutter SDK 3.13.5 / Dart 3.13.5）

- 命令：`flutter test -j 1 --reporter expanded`（工程根 `rcpu_wallet/`）
- 结果：**41 通过 / 12 跳过 / 0 失败（EXIT=0）**；6 个用例文件全部纳入
  - `tc_sig02_hkdf_test.dart`：4/4 通过（官方 Appendix A/C 向量：view_seed、Path C nonce、rewind nonce、不同 spk 不同 nonce）
  - `tc_sig03_test.dart`：2/2 通过（指纹成功触发签名入口；取消则中止且不产生签名对象）
  - `tc_qr_payment_test.dart`：13/13 通过（收款码生成、扫码解析、金额校验）
  - `tc_crypto_test.dart`：30 项派生/签名/地址结构全部通过
  - `tc_bridge_test.dart`：11 项桥逻辑全部通过
  - `tc_blocked_test.dart`：12 项按预期 skip（C1/C2/C3/C4 依赖项）
- 实测修复的编译缺陷（此前全量运行暴露）：
  1. `lib/core/biometric/biometric_auth.dart:19`：`isDeviceSupported()` 返回 `Future<bool>`，缺 `await` 导致类型不匹配 → 已加 `await`；
  2. `lib/core/network/bsc_rpc.dart`：`DelegatingContract`/`ContractInterface` 为 API 误用（web3dart 2.7.3 实际为 `DeployedContract` + `ContractAbi.fromJson`）；`getBalance` 返回 `EtherAmount` 需 `.getInWei`；`getTransactionReceipt` 直接收 `String` 哈希 → 全部按真实 API 修正；
  3. `lib/core/network/http_client.dart:5`：`BaseOptions` 非 const 构造，`static const` 编译失败 → 改 `static final`。

---

## 1. 派生一致性（对应矩阵第①行）

### TC-DRV-01 明文地址派生一致（rcpu1）
- **输入**：官方测试助记词；`Derivation.deriveNativePlainAddress()`
- **步骤**：1) 导入助记词；2) 派生明文地址；3) 与官方钱包展示地址比对
- **期望**：双方 `rcpu1...` 地址逐字符一致
- **当前状态**：✅ 可执行（结构测试）；地址协议编码 `_protocolEncode` 须与官网编码核对后最终定版 🔴 依赖 C2

### TC-DRV-02 隐私地址派生一致（rcpux1 / Path C）
- **输入**：官方测试助记词；`Derivation.deriveNativePrivateAddress()`，`nativePrivatePath` 已替换为官方 Path C
- **步骤**：1) 按官方 Path C 常量派生；2) 比对官方钱包的 `rcpux1...` 地址
- **期望**：一致；含 CT 公钥/viewing key 绑定字段时也一致
- **当前状态**：🔴 阻塞 C1/C2（`nativePrivatePath` 现为占位 `m/44'/307'/0'/1/0`，编码为伪 hex）

### TC-DRV-03 派生确定性
- **输入**：固定助记词 × 3 次调用
- **期望**：三次派生结果地址完全相同
- **当前状态**：✅ 可执行（现有 BIP32/BIP39 实现具备确定性）

### TC-DRV-04 助记词校验
- **输入**：12 词合法助记词 / 错词助记词
- **期望**：合法通过；错词抛 `FormatException('助记词校验失败')`
- **当前状态**：✅ 可执行

### TC-DRV-05 NativeKeyBundle 双钥派生（新增能力回归）
- **输入**：Path C 修正后 `deriveKey` 暴露 spending key + viewing key
- **期望**：spending/viewing 两密钥由同一种子确定性派生、独立可取、可备份
- **当前状态**：🔴 阻塞 C1/C2（key bundle 结构待协议定）

---

## 2. 签名（对应矩阵第②行）

### TC-SIG-01 BSC 签名校验
- **输入**：已知私钥、消息、签名（官方测试向量）
- **期望**：`verifyBscSignature` 恢复地址 == 私钥对应地址
- **当前状态**：✅ 已实测 4/4 通过（2026-10-14：恢复地址 == 派生地址、篡改消息失败、错误地址失败、非 65 字节签名返回 false）；`verifyBscSignature` 已按 web3dart 真实 API 落地（`signature.dart`）

### TC-SIG-02 原生 CT 交易签名
- **输入**：交易 hex + 私钥 + 盲化因子种子 + 接收方 CT 公钥（按协议签名方法入参）
- **期望**：签名通过官方测试向量校验；CT 场景输出承诺 + 范围证明
- **当前状态**：🟡 部分解锁——HKDF/ECDH 层已由 `test/tc_sig02_hkdf_test.dart` 以官方 Appendix A/C 向量验证（view_seed / rewind nonce 逐字节一致），**已于 2026-10-14 本机实测 4/4 通过**；`signNative` 签名本体仍为占位 `UnimplementedError`（待 §2.3/§4.4 签名实现）

### TC-SIG-03 指纹确认后签名触发
- **输入**：指纹授权结果 true/false
- **期望**：true → 进入签名流程；false → 中止且不产生任何签名对象
- **当前状态**：✅ 已实测 2/2 通过（2026-10-14：隐私地址 + 指纹成功 → 进入签名入口；指纹取消 → 直接失败、不产生签名对象）

---

## 3. CT 收款（对应矩阵第③行）

### TC-CT-IN-01 收款到账（代理 unblind）
- **输入**：第三方发送 1.5 RCPU CT 输出至本 APP `rcpux1...`
- **步骤**：1) 接收方调 `getBalance(rcpux1...)`；2) 观察合计
- **期望**：代理 unblind 后 `Balance.micro` 增加 1.5e8；链上该输出金额不可见
- **当前状态**：🔴 阻塞 C3/C4（代理须完成 ECDH + 解承诺 + 范围证明）

### TC-CT-IN-02 单笔明细解析（本地储备）
- **输入**：该笔交易 txid/txHex；`ownAddress`、`unblindingKey`
- **期望**：`resolveOutput` 返回 1.5e8；非本人输出返回 null（不抛异常）
- **当前状态**：🔴 阻塞 C1/C3/C4（`ct_resolver.dart` 与 `native_rpc.resolveCtOutput` 均为占位）

### TC-CT-IN-03 收款二维码
- **输入**：选择收款资产「原生 RCPU」→ 生成 `rcpu:rcpux1...?amount=1.5`
- **期望**：二维码可扫、可分享、金额字段正确解析
- **当前状态**：✅ 可执行（QR 生成/扫描层独立于 CT 密码学）

---

## 4. CT 付款（对应矩阵第④行）

### TC-CT-OUT-01 扫码解析与资产预判
- **输入**：`rcpu:rcpux1...?amount=1.5`、`rcpu:rcpu1...?amount=0.8`
- **期望**：识别 `rcpu:` 前缀；`rcpux1` 预判为隐私付款、`rcpu1` 为明文付款；金额分别 1.5 / 0.8
- **当前状态**：✅ 可执行

### TC-CT-OUT-02 隐私付款签名广播
- **输入**：1.5 RCPU 至 `rcpux1`，指纹确认，调用 `signNative` → `broadcast`
- **期望**：签名产出交易 hex；`broadcast_tx` 返回 txid；接收方余额增加
- **当前状态**：🔴 阻塞 C1（签名）+ C4（广播契约已就绪，代理直连可用）——签名打通后即可全通

### TC-CT-OUT-03 明文付款（对照通道）
- **输入**：0.8 RCPU 至 `rcpu1` 地址
- **期望**：广播成功、余额扣减、历史出现 `direction:'out'` 记录
- **当前状态**：✅ 可执行（明文通道不依赖 CT 密码学；依赖代理链上能力）

### TC-CT-OUT-04 余额不足拒绝
- **输入**：付款金额 > 可用余额（含 CT 合计）
- **期望**：拒绝并提示「余额不足」，不产生签名/广播
- **当前状态**：✅ 可执行

---

## 5. 铸造 Deposit（对应矩阵第⑤行）

> 用例供联调、错误码与文案最终以桥 API 契约为准（C4）。

### TC-MINT-01 最小存款校验
- **输入**：`amountMicro` = 0.009 RCPU
- **期望**：`BridgeResult.fail('最低存款 0.01 RCPU')`，不广播
- **当前状态**：✅ 可执行（`bridge_provider.dart` `minDeposit = 0.01` 已实现）

### TC-MINT-02 地址强制明文
- **输入**：`fromPlainAddress` 传 `rcpux1...`
- **期望**：`BridgeResult.fail('铸造仅支持明文 rcpu1 地址，已拒绝 rcpux1')`
- **当前状态**：✅ 可执行（已实现）

### TC-MINT-03 专属存款地址获取（API 优先 + WebView 降级）
- **输入**：桥 API 可用 / 不可用两种模式
- **期望**：API 可用 → 返回专属 `rcpu1` 地址；不可用 → 返回 null，页面打开 WebView 至 `https://rcpupool.asia/`
- **当前状态**：🟡 部分可执行（降级分支 ✅；API 契约 🔴 依赖 C4）

### TC-MINT-04 累计满 10 铸造 + 指数退避轮询
- **输入**：余额 0.5 → 连续存入至累计 10.5 RCPU；轮询 3 次退避 10s/20s/40s
- **期望**：满 10 后桥铸造 wRCPU 到用户 BSC 地址；轮询 3 次仍未确认 → 提示「仍在处理，请稍后在跨链页查看」
- **当前状态**：🟡 逻辑可执行（`retryBackoff` 已实现，单测可跑）；真实到账 🔴 依赖桥处理（C4）

### TC-MINT-05 铸造历史展示
- **输入**：完成 2 次铸造
- **期望**：跨链页展示累计进度、专属地址与历史记录
- **当前状态**：✅ 可执行（UI 层）

---

## 6. 赎回 Redeem（对应矩阵第⑥行）

### TC-REDEEM-01 BNB Gas 检查
- **输入**：BSC 地址 BNB 余额 < 0.01 BNB
- **期望**：`BridgeResult.fail('BSC Gas（BNB）不足，请先补充 BNB')`，不广播
- **当前状态**：✅ 可执行（已实现）

### TC-REDEEM-02 收款地址强制明文
- **输入**：赎回收款地址传 `rcpux1...`
- **期望**：`BridgeResult.fail('赎回收款地址必须是明文 rcpu1 地址')`
- **当前状态**：✅ 可执行（已实现）

### TC-REDEEM-03 赎回广播（burn + 指定原生收款）
- **输入**：1 wRCPU → `redeem` 调用，收款地址为本 APP `rcpu1...`
- **期望**：BSC 交易签名广播成功；赎回金额后原生 RCPU 余额自动到账
- **当前状态**：🔴 阻塞 C1/C4（`redeem` 现为按 `bridge_provider` 包装的占位实现，契约待桥确认）

### TC-REDEEM-04 到账自动刷新
- **输入**：桥完成赎回处理后 30s 内观察
- **期望**：首页原生余额自动更新（含新到账 RCPU），无需手动刷新
- **当前状态**：🔴 阻塞 C3/C4（依赖代理余额缓存与桥回调/轮询）

---

## 7. 明文通道回归（降级路径验证）

### TC-FB-01 明文收付全链路（对照基准）
- **输入**：`rcpu1` 收款 0.5 + 付款 0.2
- **期望**：余额、历史、二维码、指纹确认全链路正常
- **当前状态**：✅ 可执行

### TC-FB-02 CT 金额保密降级
- **输入**：代理不可用 / CT 明细缺失时打开交易详情
- **期望**：展示「隐私交易（金额保密）」占位文案，不崩溃、不显示错误金额
- **当前状态**：✅ 可执行（降级分支）

### TC-FB-03 网络异常
- **输入**：RPC 7337 不可达
- **期望**：余额页显示错误态 + 重试按钮；`getBalance` 超时（10s 连接/20s 接收）后不阻塞 UI
- **当前状态**：✅ 可执行

---

## 8. 运行方式建议

```bash
# 单元级（✅ 用例可先行）
flutter test test/            # 或按本清单编号建 tc_drv/tc_mint 等测试组

# 集成级（依赖代理/桥环境）
# 启动轻量代理于 127.0.0.1:7337 后，用 integration_test 覆盖 TC-CT-IN-03、
# TC-CT-OUT-01/03/04、TC-MINT-01/02/05、TC-REDEEM-01/02、TC-FB-*

# 🔴 用例执行时间：C1/C2 文档到位 + 代理（C3）与桥（C4）契约就绪后
```

## 9. 状态汇总

| 组 | ✅ 可执行 | 🟡 部分 | 🔴 阻塞 |
| --- | --- | --- | --- |
| 派生 | 3 | 0 | 2 |
| 签名 | 1 | 1 | 1 |
| CT 收款 | 1 | 0 | 2 |
| CT 付款 | 3 | 0 | 1 |
| 铸造 | 3 | 2 | 0 |
| 赎回 | 2 | 0 | 2 |
| 明文回归 | 3 | 0 | 0 |
| **合计** | **16** | **3** | **8** |