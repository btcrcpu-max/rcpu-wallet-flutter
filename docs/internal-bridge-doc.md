# 内部桥对接纪要（C1–C5 可填写清单）

> 状态：草案 v0.1｜更新：2026-10-14
> 性质：**内部技术纪要**，供钱包客户端（rcpu_wallet）与跨桥侧逐项确认。
> 口径：跨桥（rcpupool.asia）、wRCPU 合约、轻量代理（RPC 7337）均为**我方自研**，
> 因此 C3（viewing key / 代理权限）与 C4（代理 RPC 契约）由内部直接定义；
> 唯一外部阻塞为官方 Path C 协议文档（C1/C2）。
>
> 使用方式：逐项填写「确认结果」列并打勾；全部澄清后回到
> `docs/path-c-fix-list.md` 执行代码修改，并用 `docs/ct-test-cases.md` 复核。

---

## 0. 已确认事实（无需再确认）

| 项 | 值 |
| --- | --- |
| 桥站点 | `https://rcpupool.asia/` |
| wRCPU 合约 | `0x2F720B253EF63176cF54b0088C7F57997dd2c340`（Decimals = 8） |
| 桥存款规则 | 仅接受明文 `rcpu1`（拒绝 `rcpux1`）；最小存款 0.01 RCPU；按地址累计满 10 RCPU 铸造 |
| 原生地址 | 明文 `rcpu1...` / 隐私 `rcpux1...`（默认 Path C） |
| 原生 RPC | 轻量代理 `http://127.0.0.1:7337`（JSON-RPC，我方自研） |
| 轮询退避 | 3 次，10s → 20s → 40s |
| BNB Gas 阈值 | 赎回前检查 ≥ 0.01 BNB，不足拒绝 |
| 桥 API 降级 | 专属地址获取失败 → WebView 打开桥站手动存款 |
| 对接归属 | 桥 / 代理契约由我方直接定义（用户确认「跨桥也是我开发的」） |

---

## 1. 待确认项总览

| 编号 | 名称 | 优先级 | 依赖对象 | 当前状态 |
| --- | --- | --- | --- | --- |
| C1 | 官方 Path C 协议文档（仓库 + CT 规范原文） | **P0** | RCPU 官方 | ⏳ 待获取 |
| C2 | Path C BIP32 路径与 `rcpux1` 编码规范 | **P0** | C1 | ⏳ 待 C1 |
| C3 | viewing key 格式与代理 unblind 最小权限 | **P1** | 内部自研 | 🟢 我方内部定义 |
| C4 | 代理 RPC 契约（方法/schema/错误码） | **P1** | 内部自研 | 🟢 草案已出（见 `docs/proxy-rpc-schema.md`，桥契约见 `docs/bridge-api-contract-c4.md`） |
| C5 | CT 本地证明验证范围 | **P2** | C3 结论 | 🔵 待评审 |

---

## 2. C1 —— 官方 Path C 协议文档（P0 阻塞）

> 目标：拿到 Path C、blinding、viewing key 规范原文，开启
> `derivation.dart` 与 `signature.dart` 的并行改造。

| 字段 | 我方当前状态 / 假定 | 待确认内容 | 涉及模块 | 影响 | 确认结果 |
| --- | --- | --- | --- | --- | --- |
| 官方仓库地址 | 未命中公开文档 | 仓库 URL / 文档路径 | 全链 CT 功能 | 阻塞全部 Path C 派生 | ☐ |
| CT 规范原文 | 无 | Path C、blinding、range proof、viewing key 规范章节原文 | `derivation.dart` `signature.dart` `ct_resolver.dart` | 阻塞 CT 签名与 unblind 实现 | ☐ |
| 测试向量 | 无 | 官方助记词与地址对照向量 | `test/tc_crypto_test.dart`（结构版）`test/tc_blocked_test.dart`（完整版） | 阻塞 TC-DRV-01/02、TC-SIG-02 断言 | ☐ |

**我方动作**：拿到文档后，将原文段落编号逐条填入，并同步 `docs/ct-integration.md` 来源声明。

---

## 3. C2 —— Path C 路径与 `rcpux1` 编码规范（P0 阻塞）

> 依赖 C1。目标：把占位路径与伪编码替换为官方规范。

| 字段 | 我方当前状态 / 假定 | 待确认内容 | 涉及模块 | 影响 | 确认结果 |
| --- | --- | --- | --- | --- | --- |
| BIP32 路径模板 | 占位 `m/44'/307'/0'/1/0` | 官方 Path C 完整路径 | `derivation.dart.nativePrivatePath` | 隐私地址与合约算得的地址不一致 | ☐ |
| 前缀 / checksum | 假定 `rcpux1` 前缀 + 协议编码 | 前缀、checksum 算法 | `derivation.dart._protocolEncode` | 地址有效性校验 | ☐ |
| 是否绑定 CT 公钥 / viewing key | 假定地址 = CT 公钥或含 viewing key 派生 | 绑定关系与字段顺序 | `address.dart` 模型 | 收款时能否自动识别支付者公钥 | ☐ |
| 明文编码一致性 | `_protocolEncode` 为伪 hex | 明文 `rcpu1` 编码是否同规则 | `derivation.dart` | TC-DRV-01 定版 | ☐ |

---

## 4. C3 —— viewing key 与代理 unblind 权限（P1，内部自研）

> 我方内部定义；结论决定代理是「全量 unblind」还是「最小权限验证型」。

| 字段 | 我方当前状态 / 假定 | 内部决议 | 涉及模块 | 影响 | 确认结果 |
| --- | --- | --- | --- | --- | --- |
| viewing key 格式 | 未定（占位） | 由内部定稿 | 代理设计、`native_rpc.resolveCtOutput` | 代理调用参数 | ☐ |
| 最小权限集合 | 代理仅需 ECDH + 解承诺 + range proof 验证，**不含 spending key** | 明确权限边界 | 代理安全设计 | 防止代理作恶 | ☐ |
| 是否返回明文金额 | 假定返回明文金额，APP 不自行 unblind | 定稿返回口径 | `Balance` 模型 | 余额展示 | ☐ |

---

## 5. C4 —— 代理 RPC 契约（P1，内部自研）

> 草案正文见 **`docs/代理 RPC schema（C4 草案）.md`**；本节为此处清单入口。

| 字段 | 草案建议（我方） | 待确认内容 | 涉及模块 | 影响 | 确认结果 |
| --- | --- | --- | --- | --- | --- |
| 端点 | `http://127.0.0.1:7337` | 正式部署端点 | `native_rpc.dart` | 全局连接配置 | ☐ |
| 方法集 | `get_balance` / `broadcast_tx` / `get_history` / `resolve_ct` | 方法名与入参顺序 | `native_rpc.dart` | 客户端调用层 | ☐ |
| 余额口径 | `totalRaw` + `plainRaw` + `ctRaw` 拆分 | 是否拆分明文/CT | `Balance` 模型 | 首页资产展示 | ☐ |
| 错误码 | JSON-RPC 标准 + 自定义段 | 错误码清单 | 全链路错误处理 | 用户提示文案 | ☐ |
| `resolve_ct` | `txHex` + `ownAddress` + `viewingKey` 入参 | 最小权限确认（见 C3） | `native_rpc.dart` | CT 明细解析 | ☐ |

---

## 6. C5 —— 本地证明验证范围（P2）

> 依赖 C3 结论。目标：明确上线前审计对本地验证的要求，避免重复设计。

| 字段 | 我方当前状态 / 假定 | 待确认内容 | 涉及模块 | 影响 | 确认结果 |
| --- | --- | --- | --- | --- | --- |
| 是否本地验证 | 代理 unblind 优先，`ct_resolver.dart` 仅储备 | 审计是否要求本地独立验证 | `ct_resolver.dart` | 实现深度 | ☐ |
| 证明类型 | range proof + 承诺一致性 | 最小验证范围 | 代理 / 客户端 | 安全加固范围 | ☐ |

---

## 7. 内部桥 API 契约（随 C4 一并定稿）

> 桥与代理均为自研，以下接口建议随 C1→C4 结论同步定稿，
> 作为 `bridge_provider.dart` 联调依据。

| 接口 | 方法与路径 | 建议请求 | 建议响应 | 涉及模块 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 生成专属存款地址 | `POST /api/v1/deposit/address` | `{nativeAddress}` | `{address}` | `fetchDepositAddress` | 草案 |
| 登记存款 | `POST /api/v1/deposit/record` | `{nativeAddress, amount, txHash}` | `{ok}` | `deposit()` | 草案 |
| 查询铸造状态 | `GET /api/v1/deposit/status` | `?nativeAddress=` | `{state, totalDeposited, wrcpuTxHash, estimatedMinutes}` | `pollMintStatus` | 草案 |
| 赎回调用 | BSC 合约 `redeem(uint256, string)` 或 `burn` | — | 交易 hash | `bsc_rpc.redeem` | 待定（见下） |

**赎回方法注意**：`bsc_rpc.dart` 当前按 `redeem(amount, rcpuAddress)` 封装；
若桥合约只暴露标准 `burn(amount)`，需改为 burn + 链下登记，并在
`BridgeConfig` 增加「赎回后登记接口」。此项 **P1**，随 C4 定稿。

---

## 8. 结论汇总与下一步

| 项 | 结论 |
| --- | --- |
| 可立即推进 | 明文通道（收付、二维码、指纹）、wRCPU（余额/转账/Gas）、桥参数校验、`verifyBscSignature`、代理 RPC schema 草案（C4） |
| 唯一外部阻塞 | **C1/C2 —— 官方 Path C 协议文档**（路径模板、`rcpux1` 编码、CT 公钥绑定）；到位前按降级策略运行 |
| 内部待定稿 | C3（viewing key 权限）、C4（代理契约）、赎回方法形态 |

> 本文档为追踪载体，不替代代码；C2 定稿后所有占位替换以
> `docs/path-c-fix-list.md` 为执行清单。