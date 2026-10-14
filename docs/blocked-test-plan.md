# 阻塞用例并行执行计划（修正版）

> 状态：执行计划 v0.2（修正版）｜更新：2026-10-14
> 来源：`docs/blocked-test-cases.md`（12 项 🔴 阻塞用例）与 `test/tc_blocked_test.dart`。
> 修正点：补「数量 / 状态」列；明确 TC-SIG-03 先做流程骨架（签名占位降级）；
> 各阶段数量与基线严格一致（1+4+3+4=12）。
> 关联：`docs/bridge-confirmation-email.md`（桥侧 B1–B5 确认邮件）、`docs/tc-sig03-implementation.md`（TC-SIG-03 实现方案）。

---

## 1. 阶段任务表（修正版）

| 阶段 | 用例 | 数量 | 依赖条件 | 状态 | 建议负责人 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| **立即** | TC-SIG-03 | 1 | 无 C1–C4 外部依赖，但依赖支付流程实现 | 可并行开发 | 前端 | 指纹确认后触发签名；当前可先做流程骨架，签名占位降级（方案见 `docs/tc-sig03-implementation.md`） |
| **阶段 1** | TC-DRV-01 / TC-DRV-02 / TC-DRV-05 + TC-SIG-02 | 4 | C1 + C2（官方 Path C 路径与编码） | 阻塞 | 前端 + 协议 | 拿到文档后优先改 `derivation.dart`（TC-DRV-03/04 已落地，保持绿不阻塞） |
| **阶段 2** | TC-CT-IN / TC-CT-OUT 系列 | 3 | C3（viewing key / 代理 unblind） | 阻塞 | 前端 + 代理 | 代理契约确定后落地（`resolve_ct` 接 `ct_resolver`） |
| **阶段 3** | TC-MINT / TC-REDEEM 系列 | 4 | C4（桥 API 契约定稿，含 B1–B5） | 阻塞 | 前端 + 桥侧 | B1–B5 回填后替换占位（确认单见 `docs/bridge-contract-checklist.md`，邮件模板见 `docs/bridge-confirmation-email.md`） |
| **合计** | — | **12** | — | — | — | 1+4+3+4=12，与基线一致 |

---

## 2. 推荐推进顺序

立即推进 TC-SIG-03 流程骨架 → 拿到 C1/C2 后并行解阶段 1 → 同步推进 C3（阶段 2）→ B1–B5 确认后解阶段 3。

> 依赖提醒：
> - TC-SIG-01（BSC 签名验证）已落地非阻塞，可随时随 CI 回归；
> - TC-REDEEM-04（赎回后余额自动刷新）同时依赖 C3（代理余额缓存）与 C4（桥发放回调/轮询），建议放在阶段 2/3 全部完成后最后解锁；
> - TC-SIG-03 流程骨架不阻塞任何其他用例，先落 `payment_service` 的授权分支即可。