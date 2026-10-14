# 轻量代理 RPC Schema（C4 草案）

> 状态：草案 v0.1｜更新：2026-10-14
> 对象：原生链轻量代理（默认 `http://127.0.0.1:7337`，我方自研）
> 用途：约束钱包客户端与代理之间的 JSON-RPC 契约，覆盖明文 + CT 场景；
> CT unblind 由代理完成（ECDH + 解承诺 + range proof 验证），客户端仅消费结果。
> 配套追踪见 `docs/internal-bridge-doc.md` 第 5 节（C4）。

---

## 1. 通用约定

- **传输**：HTTP POST，`Content-Type: application/json`；
- **协议**：JSON-RPC 2.0（id 自增，建议 1 起）；
- **金额单位**：十进制字符串，8 位精度（1 RCPU = 1e8 micro），**禁止浮点**；
- **地址**：
  - 原生明文 `rcpu1...`、隐私 `rcpux1...` 原样传输；
  - BSC：`0x` + 40 hex（大小写不敏感）；
- **错误**：`{"jsonrpc":"2.0","id":N,"error":{"code":..,"message":".."}}`；
- **安全**：代理须校验来源（仅允许已登记钱包 IP/凭证，草案阶段放行内网）。

## 2. 错误码

| code | 含义 |
| --- | --- |
| -32600 | 请求体非法（非 JSON / 缺字段） |
| -32601 | 方法不存在 |
| -32602 | 参数无效（地址格式 / 金额非法） |
| -32603 | 内部错误 |
| -32001 | 链不可达或超时 |
| -32002 | CT unblind 失败（viewing key 错误 / 无本人输出） |
| -32003 | 余额未同步完成（缓存未就绪，稍后重试） |
| -32004 | 交易广播被拒（nonce 冲突 / 余额不足） |

---

## 3. 方法一：`get_balance`

获取地址余额，**拆分明文与 CT（unblind 后）**。

### 请求
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "get_balance",
  "params": ["rcpux1..."]
}
```
`params`：`[address]`（原生 `rcpu1` / `rcpux1`，或 BSC `0x...`，兼容普通查询）。

### 成功响应
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "totalRaw": "1.50000000",
    "plainRaw": "0.80000000",
    "ctRaw": "0.70000000",
    "ctCount": 1,
    "synced": true
  }
}
```
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| totalRaw | string | 可花费总额（plain + ct） |
| plainRaw | string | 明文部分 |
| ctRaw | string | CT 部分（unblind 后合计） |
| ctCount | int | 待解析 CT 输出笔数（0 表示无） |
| synced | bool | 是否已同步到最新区块（false 时客户端可提示「余额刷新中」） |

> 注：现有 `native_rpc.dart` 的 `getBalance` 按 `result` 为字符串解析；
> 定稿后需同步升级客户端为对象解析（见 §7 兼容说明）。

### 错误示例
```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32003,"message":"余额未同步完成"}}
```

---

## 4. 方法二：`broadcast_tx`

广播已签名的原生交易（明文或 CT）。

### 请求
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "broadcast_tx",
  "params": ["<signedTxHex>"]
}
```

### 成功响应
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "txid": "0x...",
    "status": "pending"
  }
}
```

### 错误
- `-32004` 广播被拒（余额不足 / nonce 冲突 / 签名无效）；
- `-32602` 交易 hex 格式非法。

---

## 5. 方法三：`get_history`

获取交易历史（明文 + CT 统一返回；CT 记录带 `privacy:'ct'`，金额已 unblind）。

### 请求
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "get_history",
  "params": ["rcpux1...", 20]
}
```
`params`：`[address, limit?]`。

### 成功响应
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": [
    {
      "txHash": "0x...",
      "direction": "in",
      "asset": "native",
      "amount": "0.70000000",
      "counterparty": "rcpu1...",
      "timestamp": "2026-10-14T08:00:00Z",
      "status": "confirmed",
      "privacy": "ct"
    }
  ]
}
```
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| privacy | string | `plain` / `ct`；ct 时金额已由代理 unblind |
| 其余字段 | — | 与 `TxRecord.fromJson` 现有解析对齐 |

---

## 6. 方法四：`resolve_ct`

解析指定交易中的 CT 输出为明文金额（**独立明细查询**，历史缺失时补充）。

### 请求
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "resolve_ct",
  "params": ["<txHexOrTxid>", "rcpux1...", "<viewingKey>"]
}
```
`params`：`[txRef, ownAddress, viewingKey]`。

### 成功响应
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "txHash": "0x...",
    "amountMicro": "70000000",
    "privacy": "ct",
    "matchedOutputs": 1
  }
}
```
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| amountMicro | string | 本人输出合计（micro 十进制） |
| matchedOutputs | int | 命中的本人输出数；0 且无错误时视为非本人交易 |

### 错误
- `-32002` 解承诺失败（viewing key 错误 / 无匹配输出）；
- `-32602` txRef 非法。

---

## 7. 客户端兼容说明（定稿待办）

| 现状（native_rpc.dart） | 升级项 |
| --- | --- |
| `getBalance` 按 `result` 字符串解析 | 改为对象（`totalRaw/plainRaw/ctRaw/ctCount/synced`），并兼容旧字符串（视为 `totalRaw`） |
| `getHistory` 按数组解析 | 字段已对齐；补 `privacy` 字段到模型（可先忽略） |
| `resolveCtOutput` 抛 `UnimplementedError` | 落地为 `resolve_ct` 调用（依赖 C3 viewing key 定稿） |
| `broadcast` 按 `result` 字符串解析 | 改为对象取 `txid`，兼容旧字符串 |

## 8. 验证清单（对接时逐条核对）

- [ ] `get_balance(rcpu1...)` 返回明文余额一致；
- [ ] `get_balance(rcpux1...)` 在收到第三方 CT 后 `ctRaw` 正确、`ctCount` 正确；
- [ ] `broadcast_tx` 明文交易广播成功，返回 txid 可查；
- [ ] `broadcast_tx` 余额不足返回 `-32004`；
- [ ] `get_history` 含 privacy 字段，CT 记录金额为明文；
- [ ] `resolve_ct` 用正确 viewing key 返回金额；错误 key 返回 `-32002`；
- [ ] 错误响应统一 JSON-RPC 结构，客户端错误映射文案完善。