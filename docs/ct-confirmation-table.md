# C1-C5 待确认项清单

> 汇总 CT（机密交易）/ Path C 集成前必须由外部确认的参数，与
> `docs/ct-integration.md` 第 5 章保持一致，此处整理为「按优先级排序」的追踪表，
> 便于排期与对接。全部澄清后回到 `docs/path-c-fix-list.md` 执行代码修改。

| 项号 | 描述 | 影响模块 | 优先级 | 建议确认对象 |
| --- | --- | --- | --- | --- |
| C1 | RCPU 官方仓库地址与 CT 文档路径（Path C、blinding、viewing key 规范原文） | 派生（derivation.dart）、签名（signature.dart）、unblind（ct_resolver.dart）；阻塞全部 CT 功能 | **P0 阻塞** | RCPU 官方 / 桥团队（rcpupool.asia 运维方） |
| C2 | Path C 完整 BIP32 路径与地址编码规范（前缀、checksum、是否绑定 CT 公钥） | derivation.dart（nativePrivatePath、_protocolEncode）、Address 模型校验 | **P0 阻塞** | RCPU 官方文档 / 桥团队 |
| C3 | viewing key 格式与代理 unblind 所需最小权限（能否仅凭 viewing key 完成 ECDH 与解承诺） | 轻量代理设计、native_rpc.resolveCtOutput 契约 | **P1 高** | 桥 / 节点团队（RPC 7337 运维方） |
| C4 | 代理 RPC 契约（端点、方法名、请求/响应 schema、错误码；含余额字段是否拆分明文/CT） | native_rpc.dart（get_balance / broadcast_tx / get_history / resolve_ct）、Balance 模型 | **P1 高** | 轻量代理后端负责方 / 桥团队 |
| C5 | CT 输出是否需要本地证明验证（防代理作恶），及该验证的最小实现范围 | 安全审计范围、ct_resolver.dart 本地实现深度 | **P2 中** | 安全审计方 / RCPU 官方 | 

## 优先级说明

- **P0 阻塞**：不确认则无法派生隐私地址、无法签名/广播 CT 交易——隐私通道完全不可用；
- **P1 高**：不确认则代理调用与余额展示停留在占位/猜测状态，可先行明文通道但隐私明细不可用；
- **P2 中**：不确认则安全等级待定，不影响功能开发排期，但影响上线前审计清单。

## 依赖关系速查

```text
C1（规范原文）→ C2（Path C 路径/编码）→ C3（viewing key / 代理权限）→ C4(代理契约)
                                                     └──────────────► C5（审计范围，随 C3 结论收敛）
```

- 拿到 C1 后可开启 derivation.dart 与 signature.dart 的并行改造；
- C3 与 C4 决定代理是「全量 unblind」还是「最小权限验证型」，直接影响代理安全设计；
- C5 建议在 C3 结论明确后一并评审，避免重复设计本地证明校验。

## 追踪方式建议

- 每项由负责人打勾（`[ ]` → `[x]`），并在备注列贴官方文档链接/原文段落编号；
- 全部勾选后，按 `docs/path-c-fix-list.md` 第 1-4 节逐条执行修改，
  每节末尾验收标准通过后再进入下一节。