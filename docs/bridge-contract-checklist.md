# 桥契约定稿确认清单（B1–B5）

> 状态：**待桥侧确认**｜更新：2026-10-14
> 用途：`docs/bridge-api-contract-c4.md` §7 的 B1–B5 待确认项落实为可逐行填写的确认单；
> 桥侧在「最终约定」列填写结论后，`bridge-api-contract-c4.md` 可由草案 v0.1 升级为正式契约。
> 关联：`docs/bridge-api-contract-c4.md`、`docs/blocked-test-cases.md`（TC-MINT-03/04、TC-REDEEM-03/04）、
> `docs/bridge-backfill-schema.md`（B1–B5 回填 JSON 格式规范）。

---

## 1. 确认单

| 编号 | 待确认项 | 当前草案描述 | 确认后期望输出 | 优先级 | 影响范围 | 桥侧「最终约定」 |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | 赎回方法形态 | 合约层 `redeem(uint256 amount, string rcpuAddress)`；备选标准 `burn(uint256)` + 链下登记 `POST /api/v1/redeem/record` | 唯一选定一种方法，并给出**完整 ABI 片段**与 `rcpuAddress` 参数约束（仅明文 `rcpu1`） | **P0** | `bsc_rpc.dart` 的 `redeem` 封装、TC-REDEEM-03 | ☐ |
| B2 | `estimatedMinutes` 口径 | 桥在 `collecting` 状态返回预计处理分钟数 | 明确是静态固定值还是动态计算、单位、上限与 null 语义 | P1 | UI「预计到账时间」展示 | ☐ |
| B3 | 专属存款地址生成规则 | 由桥按 `nativeAddress` 恒定映射生成唯一明文 `rcpu1` 地址 | 说明生成算法（确定性?）、同一地址是否永久固定、是否可预测/含服务端签名 | **P0** | `fetchDepositAddress` 幂等假设、重试安全、安全审计 | ☐ |
| B4 | 到账通知机制 | 当前仅客户端轮询（10s→20s→40s 三次，手动刷新 8s） | 是否提供 Webhook / WebSocket / 事件回调；通知字段定义 | P2 | 到账体验、TC-REDEEM-04 | ☐ |
| B5 | 幂等键实现 | 可选 `Idempotency-Key` 头；未携带时以 `(nativeAddress, txHash)` 兜底去重 | 明确幂等键存储时长、重复提交的返回码（目标 `alreadyRecorded=true` + 200）、客户端重试策略 | P1 | 防重复累计/重复铸造；`http_client.dart` 头注入 | ☐ |

---

## 2. 定稿动作

1. 桥侧逐行填写「最终约定」并回传本清单；
2. 客户端按结论更新：
   - B1 → `bsc_rpc.dart`（ABI 或 burn+登记接口）；
   - B3/B5 → `bridge_provider.dart` / `http_client.dart`（幂等键头）；
   - B2/B4 → UI 文案与轮询逻辑（可选，P2 可后置）；
3. 回填 `bridge-api-contract-c4.md` §7 并升级版本号（v0.1 → v1.0）；
4. 按 `bridge-api-contract-c4.md` §8 验证清单逐条联调，解锁 TC-MINT-03/04、TC-REDEEM-03/04。

> 阻塞影响：B1/B3 为 P0，直接阻塞赎回与专属地址的联调断言；B2/B5 为 P1，定稿前客户端按草案实现即可并行推进。