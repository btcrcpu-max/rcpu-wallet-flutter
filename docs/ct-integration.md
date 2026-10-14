# CT（机密交易）协议集成要点

> 目标：明确 APP 侧如何接入 RCPU 机密交易（Confidential Transaction）能力，
> 让「余额合并显示 + 收款/付款 + 桥铸造」全链路可用。
> 本文档是**集成要点与缺口清单**，不是协议规范——RCPU CT 规范尚未公开检索到，
> 标注【待确认】的内容必须在拿到仓库文档后逐项核对（见第 5 章）。

## 0. 来源与可信度声明

- 已确认工程事实（本仓库/本项目内部确认）：明文地址 `rcpu1...`、隐私地址 `rcpux1...`
  （默认 Path C）、桥站点 `https://rcpupool.asia/`。
- 已通过公开检索（websearch + rcpu.top 页面解析）核实：**未能定位到 RCPU 官方仓库
  中 Path C / blinding / viewing key 的具体文档路径**，公开渠道不存在可引用的规范原文。
  因此本章不虚构任何仓库内文件路径；所有【待确认】项均需要在拿到
  RCPU 官方文档/仓库/桥 API 契约后补齐。
- rcpu.top 页面本身可确认的运营事实（2026-10 观察）：
  - 提供网页钱包、APK 下载（RCPU wallet.apk 3.0）、区块链浏览器、DApp 浏览器入口；
  - 发送手续费按档位收取：低 0.1 / 中 0.2 / 高 0.3 RCPU；
  - HD 地址派生提示为 BIP84（`m/84'/1'/0'/0/N`，测试网 coin type 1'）。
  - 注意：BIP84 属**明文地址**线索；隐私 CT 地址（Path C）派生路径未见公开描述，【待确认】。

## 1. 架构定位：APP 不直接做 CT 密码学

CT 涉及 Pedersen 承诺、盲化因子（blinding factor）、范围证明与 viewing key 解密，
在纯 Dart 侧完整实现风险高、审计面大。本工程采用**轻量 RPC 代理**模式：

```text
┌──────────────┐    JSON-RPC     ┌─────────────────┐    P2P/公开节点    ┌──────────────┐
│ Flutter APP  │ ──────────────► │ 轻量代理(服务端) │ ────────────────► │ RCPU 链节点  │
│ (native_rpc) │ ◄────────────── │ http://x:7337  │ ◄──────────────── │ RPC 7337    │
└──────────────┘  unblind 结果   └─────────────────┘   原始 CT / 明文     └──────────────┘
```

- 代理持有 viewing key 或委托节点钱包执行 unblind；
- APP 只发起 `get_balance` / `broadcast_tx` / `get_history` / `resolve_ct` 四类调用；
- 隐私明细不落 APP 本地，规避密钥与审计风险。

## 2. unblind 数据流（APP 视角）

1. 用户解锁钱包（指纹/密码）→ 派生 `rcpux1...` 隐私地址；
2. APP 调 `get_balance(rcpux1...)`，代理返回**已 unblind 的明文合计**（micro 单位，1e8 精度）；
3. 收款/交易后，APP 需要刷新时调 `get_history(address, limit)`；
4. 代理可选的增量接口 `resolve_ct(txHex | txid)`：APP 用于展示单笔明细，
   若代理不支持则降级为「隐私交易（金额保密）」展示；
5. 支付确认页对 CT 输出明确标注「RCPU 隐私交易，金额对链上不可见」。

与工程的对接点：

| 工程文件 | 现状 | 落地动作 |
| --- | --- | --- |
| lib/core/network/native_rpc.dart | 已按代理设计（get_balance / broadcast_tx / get_history） | 增加 resolve_ct 方法，或按代理实际契约调整端点 |
| lib/core/utils/ct_resolver.dart | `UnimplementedError` 占位 | 改为代理调用实现；本地纯实现仅作储备 |
| lib/core/models/balance.dart | asset=native 合并视图 | 保持：总余额 = 明文 + 已解 CT |
| lib/core/models/tx_record.dart | 已含 asset/direction/amount | CT 明细 amount 可置空并以类型标记代替 |

## 3. Path C / 隐私地址派生【待确认】

方案已确认「默认 Path C」（`rcpux1...`）。落地前必须从官方文档核对：

1. Path C 的完整派生路径（BIP32 路径字符串）与使用的 coin type；
2. `rcpux1` 前缀的地址编码格式（bech32 风格或自定义 checksum）；
3. 隐私地址是单地址还是地址索引族（参照明文 BIP84 的 `/0/N` 设计）；
4. viewing key 与 spending key 的关系、导出/导入格式（WIF？hex？）；
5. 盲化因子（blinding factor）是每输出随机还是确定性派生；
6. 收款码场景：`rcpux1` 收款是否必须附带一次性公钥/审计密钥字段。

> 工程现状：lib/core/crypto/derivation.dart 中 nativePrivatePath 为占位值
> （`m/44'/307'/0'/1/0`），**必须以官方 Path C 为准修正**，否则隐私地址不可用。

## 4. 集成顺序建议（依赖代理可用性）

| 步骤 | 内容 | 前置 |
| --- | --- | --- |
| 1 | 拿到 CT 规范与 Path C 定义，修正 derivation.dart | 官方文档（第 3 章【待确认】） |
| 2 | 与桥/节点团队确认轻量代理 RPC 契约（端点、返回 schema、错误码） | 代理开发 |
| 3 | ct_resolver.dart 接代理 resolve_ct；native_rpc.dart 补方法 | 步骤 2 |
| 4 | 收款页支持 rcpux1 二维码 + 隐私到账提示 | 步骤 1-3 |
| 5 | 铸造强制明文 rcpu1（bridge_provider 已实现拦截） | 已具备 |
| 6 | 钱包锁定自动 rescan 新 CT 输出（代理侧缓存/增量推送） | 步骤 2 |

## 5. 待确认清单（对桥/官方团队）

| 编号 | 待确认内容 | 影响 |
| --- | --- | --- |
| C1 | RCPU 官方仓库地址与 CT 文档路径（Path C、blinding、viewing key） | 派生与 unblind 的正确性 |
| C2 | Path C 完整 BIP32 路径与地址编码规范 | 隐私地址可生成/可校验 |
| C3 | viewing key 格式与代理 unblind 所需最小权限 | 代理设计 |
| C4 | 代理 RPC 契约（端点、schema、错误码） | native_rpc / ct_resolver 落地 |
| C5 | CT 输出是否需要本地证明验证（防代理作恶） | 安全审计范围 |

> 说明：C1 为本文档编写时经公开检索无法获得的缺口；其余为集成必需但需官方确认的
> 参数。获取到 C1-C5 任一答案后，本文档应作为工程内部核对基准同步更新，
> 并将对应常量（含 derivation.dart 路径、RPC 方法名）落到工程代码中。