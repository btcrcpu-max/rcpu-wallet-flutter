# 桥侧真实回填数据格式规范（B1–B5）

> 状态：**格式规范（可发送）**｜更新：2026-10-14
> 用途：定义桥侧对 `bridge-api-contract-c4.md` §7（B1–B5）确认请求的**回填数据结构**，
> 桥侧可直接按此 JSON 回复（粘贴到邮件或文档）。
> 收到真实回复后：①将对应字段填入 `docs/bridge-confirmation-email.md` 回填摘要列；
> ②同步更新 `docs/bridge-api-contract-c4.md` 为正式版本（v1.0）。
> 关联：`docs/bridge-contract-checklist.md`（确认单）、`docs/bridge-confirmation-email.md`（邮件与发送记录）。

---

## 1. 回填 JSON 结构

建议桥侧按以下结构回复（可直接复制到邮件或文档）：

```json
{
  "contract_version": "v1.0",
  "confirmed_at": "2026-10-XX",
  "items": {
    "B1": {
      "method": "redeem",
      "signature": "redeem(uint256 amount, string rcpuAddress)",
      "abi_fragment": "0x...",
      "notes": "直接传入明文 rcpu1 地址"
    },
    "B2": {
      "field": "estimatedMinutes",
      "type": "static",
      "range": "5-30",
      "cap": 30,
      "notes": "超过 30 分钟返回 30"
    },
    "B3": {
      "generation": "deterministic",
      "algorithm": "keccak256(bscAddress) → bech32 rcpu1",
      "binding": "permanent",
      "notes": "同一 BSC 地址永久绑定同一明文地址"
    },
    "B4": {
      "notification": "polling_only",
      "webhook": false,
      "websocket": false,
      "notes": "当前仅客户端轮询，后续考虑 WebSocket"
    },
    "B5": {
      "idempotency_ttl_hours": 24,
      "conflict_code": 409,
      "conflict_message": "Duplicate request",
      "dedup_key": "(nativeAddress, txHash)",
      "notes": "客户端可安全重试"
    }
  }
}
```

## 2. 字段口径（与契约草案一一对应）

| 编号 | 顶层字段 | 关键子字段 | 说明 |
| --- | --- | --- | --- |
| B1 | `method` / `signature` / `abi_fragment` | 赎回方法形态 | `redeem(uint256, string)` 与 ABI 片段；`abi_fragment` 待桥侧给出实际值 |
| B2 | `type` / `range` / `cap` | `estimatedMinutes` 口径 | 静态估算 5–30 分钟，超过 30 返回 30 |
| B3 | `generation` / `algorithm` / `binding` | 专属存款地址生成 | 确定性 `keccak256(bscAddress) → bech32`，同一地址永久绑定 |
| B4 | `notification` / `webhook` / `websocket` | 到账通知机制 | 当前仅轮询；后续考虑 WebSocket |
| B5 | `idempotency_ttl_hours` / `conflict_code` / `dedup_key` | 幂等键实现 | 有效期 24h；重复请求返回 `409 Conflict`；以 `(nativeAddress, txHash)` 去重 |

## 3. 使用方式

1. 将本 JSON 结构随确认邮件发送（`docs/bridge-confirmation-email.md`），请桥侧按
   「回填摘要」列或直接以 JSON 回复；
2. 收到真实回复后，将各字段填入 `bridge-confirmation-email.md` 发送记录表「回填摘要」列
   （替换此前「模拟演示」行）；
3. 同步更新 `docs/bridge-api-contract-c4.md`：契约版本号升级 v1.0，§7 待确认项逐条闭合；
4. 按 `docs/bridge-contract-checklist.md` §2「定稿动作」解锁 TC-MINT-03/04、TC-REDEEM-03/04。

> 提示：在收到真实回填前，客户端继续按草案实现（B1 redeem 封装、B5 幂等键头注入、
> 轮询 10s/20s/40s 三次），正式回填仅影响契约文档与解锁用例，不阻塞主干开发。