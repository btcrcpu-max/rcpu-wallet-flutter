# 跨链桥 API 契约草案（C4）

> 状态：**草案 v0.1**｜更新：2026-10-14
> 对象：跨链桥服务（Base URL `https://rcpupool.asia/`，我方自研）+ wRCPU 合约（BSC 主网）
> 性质：**内部契约**，供 `bridge_provider.dart` / `bsc_rpc.dart` 与桥服务联调使用；
> 与 `docs/proxy-rpc-schema.md`（原生链轻量代理，JSON-RPC）为**两套独立契约**，勿混用。
> 配套追踪：`docs/internal-bridge-doc.md` 第 5、7 节（C4）；阻塞用例：`docs/blocked-test-cases.md`（TC-MINT-03/04、TC-REDEEM-03/04）；
> 回填格式：`docs/bridge-backfill-schema.md`（B1–B5 回填 JSON 规范，回填后本契约升级 v1.0）。
>
> 当前实现锚点（勿改，随代码演进同步）：
> - `lib/features/bridge/bridge_provider.dart`（`BridgeConfig` + 三个桥方法）
> - `lib/core/network/bsc_rpc.dart`（`redeem` 合约调用）
> - `lib/core/utils/amount.dart`（金额格式）

---

## 0. 已确认事实（契约基线）

| 项 | 值 | 来源 |
| --- | --- | --- |
| 桥站点 | `https://rcpupool.asia/` | `BridgeConfig.site` |
| wRCPU 合约 | `0x2F720B253EF63176cF54b0088C7F57997dd2c340`（Decimals = 8） | `BscRpcClient.wrcpuContractAddress` |
| BSC 网络 | 主网，chainId 56 | `bsc_rpc.dart` |
| 存款通道 | 仅接受**明文** `rcpu1...`；`rcpux1...` 隐私地址**一律拒绝** | `bridge_provider.deposit` |
| 最小存款 | 0.01 RCPU（= 1000000 micro） | `BridgeConfig.minDeposit` / `Amount.minDepositMicro` |
| 铸造门槛 | 按地址累计满 10 RCPU（= 1e9 micro）才铸造 wRCPU | `BridgeConfig.mintThreshold` |
| 轮询退避 | 最多 3 次：10s → 20s → 40s | `BridgeConfig.retryBackoff` |
| 手动刷新间隔 | 8s（UI 侧轮询常量，入口为 `BridgeConfig.pollInterval`） | `BridgeConfig.pollInterval` |
| 赎回 Gas 检查 | BSC 地址 BNB 余额 ≥ 0.01 BNB（= 1e16 wei），不足拒绝广播 | `bridge_provider.redeem` |
| 客户端降级 | 桥 API 不可用 → `fetchDepositAddress` 返回 null，页面打开 WebView 至桥站 | `bridge_provider.apiAvailable` |

---

## 1. 通用约定

- **传输**：HTTPS；`Content-Type: application/json`（`GET /status` 除外，query 参数）。
- **金额**：十进制字符串，最多 8 位小数，**禁用浮点**（与 `Amount` 一致，如 `0.01`、`10`；服务端折算 micro = 字符串转 1e8 整数）。
- **地址**：
  - 原生：明文 `rcpu1...` / 隐私 `rcpux1...` 原样传输；桥接口的地址字段**仅接受明文**。
  - BSC：`0x` + 40 hex（大小写不敏感）。
- **响应结构**：成功 `{"code": 0, "message": "ok", "data": {...}}`；失败 `{"code": <业务码>, "message": "...", "data": null}`。
  HTTP 状态码与业务码配合使用：参数错误 400 / 未找到 404 / 冲突 409 / 服务错误 500，业务码见 §5.1。
- **幂等键**：可选请求头 `Idempotency-Key`（见 §6）。
- **时间**：ISO-8601 UTC（`estimatedMinutes` 为整数分钟，非时间戳）。

---

## 2. 铸造（Deposit）——把原生 RCPU 换成 wRCPU

流程：客户端通过 2.1 获取**专属明文存款地址** → 用户从明文 `rcpu1` 地址向该地址转账（APP 强制明文通道，禁止 `rcpux1`）→ 客户端经 2.2 登记 → 按 2.3 轮询，累计满 10 RCPU 服务端自动铸造到用户 BSC 地址。

### 2.1 获取专属存款地址

`POST /api/v1/deposit/address`

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| nativeAddress | string | ✅ | 用户**明文** `rcpu1...` 地址（隐私地址返回 4002） |

**请求示例**
```json
{"nativeAddress": "rcpu1..."}
```

**成功响应**（200）
```json
{
  "code": 0,
  "message": "ok",
  "data": {"address": "rcpu1..."}
}
```
| data 字段 | 类型 | 说明 |
| --- | --- | --- |
| address | string | 该用户专属明文存款地址（服务端按 nativeAddress 恒定映射，天然幂等） |

**客户端映射**：`BridgeNotifier.fetchDepositAddress(userPlainAddress)`，失败时置 `_apiAvailable=false` 降级 WebView。

### 2.2 登记存款

`POST /api/v1/deposit/record`

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| nativeAddress | string | ✅ | 用户明文 `rcpu1...` 地址 |
| amount | string | ✅ | 本次发送数量（十进制字符串，≥ 0.01 RCPU） |
| txHash | string | ✅ | 原生链交易哈希（客户端无哈希时传空串，服务端按链上到账为准） |

**请求示例**
```json
{
  "nativeAddress": "rcpu1...",
  "amount": "0.05",
  "txHash": "0x..."
}
```

**成功响应**（200）
```json
{
  "code": 0,
  "message": "ok",
  "data": {"id": "dep_20261014_8f3a", "alreadyRecorded": false}
}
```
| data 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 登记记录 ID（服务端生成，客户端可忽略/留档） |
| alreadyRecorded | bool | 同 txHash 重复登记时为 true（幂等命中，见 §6） |

**校验规则（服务端）**：
- `nativeAddress` 非 `rcpu1` 前缀 → **4002**（仅支持明文地址）；
- `amount` 非法或 < 0.01 RCPU → **4003**（低于最小存款）；
- 同 `nativeAddress` + `txHash` 已登记 → **4004**（重复登记，返回既有记录，不重复累计）；
- 链上余额尚未同步 → **4005**（稍后重试，客户端提示「余额校验中」）。

**客户端映射**：`BridgeNotifier.deposit(fromPlainAddress, amountMicro, nativeTxHash)`。当前实现不消费响应体，登记成功即返回 `BridgeResult.ok`；服务端仍须按上述规则返回，供联调断言（TC-MINT-03）。

### 2.3 查询铸造状态

`GET /api/v1/deposit/status?nativeAddress=<明文地址>`

**成功响应**（200）
```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "state": "collecting",
    "totalDeposited": "2.55000000",
    "wrcpuTxHash": null,
    "estimatedMinutes": null
  }
}
```
| data 字段 | 类型 | 说明 |
| --- | --- | --- |
| state | string | 枚举：`collecting`（累计中）/ `minted`（已铸造）/ `failed`（失败） |
| totalDeposited | string | 该地址累计存款（应为十进制字符串；客户端 `toString()` 兜底兼容数字） |
| wrcpuTxHash | string? | 已铸造时的 BSC 交易哈希，未铸造为 null |
| estimatedMinutes | int? | 预计剩余分钟（仅 `collecting` 时有值），客户端展示「预计到账时间」 |

**客户端映射**：`BridgeNotifier.pollMintStatus(plainAddress)` → `_queryMintStatus`；读取字段 `state` / `totalDeposited` / `wrcpuTxHash` / `estimatedMinutes`（字段名必须与上表完全一致）。

### 2.4 铸造状态机与轮询策略

```
            首次存款            累计达到 10 RCPU
  idle ───────────────► collecting ─────────────────► minted（wrcpuTxHash 落地）
              <0.01 被拒            │ 服务端检测异常
                                   ▼
                                 failed
```

- 客户端轮询：最多 3 次，退避间隔 10s → 20s → 40s（`BridgeConfig.retryBackoff`）；
- `state == minted | failed` 时停止轮询并返回结果；3 次后仍 `collecting` 由 UI 显示累计进度，用户可手动刷新（8s 间隔常量 `BridgeConfig.pollInterval`）；
- 服务端在累计满 10 RCPU 后**自动铸造**，并在 `minted` 状态下回填 `wrcpuTxHash`。

---

## 3. 赎回（Redeem）——把 wRCPU 换回原生 RCPU 直达手机钱包

赎回为**合约层调用 + 链下登记**两步（客户端先行签名广播）：

### 3.1 合约调用（客户端广播）

| 项 | 值 |
| --- | --- |
| 合约 | `0x2F720B253EF63176cF54b0088C7F57997dd2c340` |
| 方法 | `redeem(uint256 amount, string rcpuAddress)` |
| amount | wRCPU 数量（8 位精度，micro） |
| rcpuAddress | 收款方**原生明文** `rcpu1...` 地址（手机钱包自己的原生地址，**禁止 `rcpux1`**） |
| Gas | 客户端先检查 BNB ≥ 0.01 BNB（1e16 wei），不足拒绝广播 |
| 广播 | 客户端 `web3dart` 签名，chainId 56；桥服务监听事件后完成原生发放 |

**客户端映射**：`BscRpcClient.redeem(fromPrivateKey, amount, rcpuAddress)` → `BridgeNotifier.redeem`。

**备选方案（待桥确认）**：若合约只暴露标准 `burn(uint256 amount)`，则改为
burn + 链下登记接口（新增 `POST /api/v1/redeem/record`，body `{bscAddress, txHash, amount, rcpuAddress}`），
原生发放由桥在**链下登记**后执行；需随本草案 §8 确认。（见 `internal-bridge-doc.md` §7 注意事项）

### 3.2 原生余额到账

- 桥完成原生发放后，目标 `rcpu1...` 余额经轻量代理（`proxy-rpc-schema.md`）刷新可见；
- 客户端到账刷新依赖 C3/C4 代理契约定稿（TC-REDEEM-04），当前以手动刷新/轮询过渡。

---

## 4. 错误码表

### 4.1 桥 API 业务错误码（HTTP 层）

| HTTP | code | message 含义 | 客户端文案建议 |
| --- | --- | --- | --- |
| 400 | 4001 | 参数缺失或非法 | 「请求参数有误，请重试」 |
| 400 | 4002 | 仅支持明文 `rcpu1` 地址 | 「桥仅支持明文地址，已拒绝隐私地址」 |
| 400 | 4003 | 低于最小存款 0.01 RCPU | 「最低存款 0.01 RCPU」 |
| 409 | 4004 | 重复登记（同 address+txHash） | 「该笔存款已登记」 |
| 503 | 4005 | 链上余额未同步完成 | 「余额校验中，请稍后重试」 |
| 500 | 5001 | 桥内部错误 | 「桥服务异常，请稍后重试」 |

### 4.2 依赖节点（轻量代理）错误码（JSON-RPC）

> 桥服务与钱包客户端共用同一原生链代理口径，完整 schema 见 `docs/proxy-rpc-schema.md` §2。
> 桥服务在调用原生链时透出以下错误码；客户端不得自行重定义。

| code | 含义 |
| --- | --- |
| -32001 | 链不可达或超时 |
| -32002 | CT unblind 失败（viewing key 错误 / 无本人输出） |
| -32003 | 余额未同步完成（缓存未就绪，稍后重试） |
| -32004 | 交易广播被拒（nonce 冲突 / 余额不足） |

---

## 5. 幂等规则

| 接口 | 幂等键 | 策略 | 客户端重试是否安全 |
| --- | --- | --- | --- |
| 2.1 获取专属地址 | nativeAddress | 同地址恒定返回同专属地址（服务端持久化映射） | ✅ 天然幂等 |
| 2.2 登记存款 | `Idempotency-Key` 头；未携带时以 `(nativeAddress, txHash)` 兜底 | 同键重复请求返回既有记录，`alreadyRecorded=true`，**不重复累计金额** | ✅ |
| 2.3 查询状态 | GET 无副作用 | 只读 | ✅ |
| 3.x 赎回广播 | BSC nonce（链层） | 同 nonce 重复广播被拒/被替换（链层语义）；链下登记（若启用）以 `(bscAddress, txHash)` 去重 | ✅（依赖链层） |

> 客户端对可能断网的 POST 均需允许重试：超时后**不要**立即展示失败，先以同幂等键
> （或同 txHash）重复登记确认结果，避免重复累计。

---

## 6. 与客户端实现的映射

| 契约条目 | 客户端实现 | 当前状态 |
| --- | --- | --- |
| 2.1 `POST /api/v1/deposit/address` | `BridgeNotifier.fetchDepositAddress` | 已实现（API 失败降级 WebView） |
| 2.2 `POST /api/v1/deposit/record` | `BridgeNotifier.deposit` | 已实现（校验明文 + 最低存款） |
| 2.3 `GET /api/v1/deposit/status` | `BridgeNotifier.pollMintStatus` / `_queryMintStatus` | 已实现（3 次指数退避） |
| 3.1 `redeem(uint256, string)` | `BscRpcClient.redeem` + `BridgeNotifier.redeem` | 已实现（Gas 检查先行） |
| §5 幂等 | `Idempotency-Key` 头 | 待补：`HttpClient` 加头（见 `http_client.dart`） |

---

## 7. 契约定稿前待确认项（阻塞 TC-MINT-03/04、TC-REDEEM-03/04）

| 编号 | 项 | 当前假定 | 需确认 | 影响 |
| --- | --- | --- | --- | --- |
| B1 | 赎回方法形态 | `redeem(uint256, string)` | 桥合约是否同时暴露 `burn(uint256)`；burn 时链下登记接口是否落地 | `bsc_rpc.dart` 实现 |
| B2 | `estimatedMinutes` 口径 | 整数分钟提示 | 服务端如何估算（排队? 批次?) | 展示文案 |
| B3 | 专属地址生成规则 | 同 nativeAddress 恒定映射 | 是否含服务端签名/一次性地址 | 安全审计 |
| B4 | 到账通知 | 代理轮询 | 是否提供 Webhook / 事件回调 | 到账刷新体验（TC-REDEEM-04） |
| B5 | `Idempotency-Key` 实现 | 草案 §5 | 服务端是否强制校验 | 客户端 `http_client.dart` |

---

## 8. 对接验证清单（定稿后逐条核对）

- [ ] `POST /api/v1/deposit/address`：同一 `rcpu1` 地址两次请求返回同一存款地址；
- [ ] 上述接口传 `rcpux1` 返回 **4002**；
- [ ] `POST /api/v1/deposit/record`：amount `0.009` 返回 **4003**；amount `0.01` 通过；
- [ ] 同 `(nativeAddress, txHash)` 重复登记返回 `alreadyRecorded=true` 且累计不翻倍；
- [ ] `GET /api/v1/deposit/status`：累计 2.55 时 `state=collecting`、`totalDeposited="2.55000000"`；
- [ ] 累计满 10 后 `state=minted` 且 `wrcpuTxHash` 非空可查；
- [ ] `redeem(amount, rcpu1...)` 签名广播成功；`rcpux1` 收款地址被客户端拒绝（4002 同口径）；
- [ ] BNB < 0.01 时客户端拒绝广播并提示 Gas 不足；
- [ ] 代理错误 -32001/-32002/-32003/-32004 在契约链路中被正确映射为用户文案。