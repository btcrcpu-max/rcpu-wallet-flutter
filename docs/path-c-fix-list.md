# Path C 修正后的代码修改清单

> 目标：把当前工程中的协议占位替换为官方 Path C 实现，使隐私 `rcpux1...` 地址
> 可真实派生、CT 交易可签名、CT 输出可 unblind。
> **前置**：官方 Path C 规范已到位（**详见 `docs/path-c-spec.md`**，C1/C2 地址编码已解锁；
> 仅「Native BIP32 派生路径」仍待官方钱包源码确认，见其 §4.1）；按本清单执行，
> 每项改动均标注【当前占位】→【目标形态】→【验收标准】。
> **模板（存档）**：`docs/path-c-c1-c2-template.md`（回填完成，仅作历史对照）。

## 0. 修改顺序总览（依赖关系）

```text
C1/C2 文档到位
   → 1. derivation.dart（地址与密钥派生正确）
   → 2. signature.dart（交易签名 + CT 证明）
   → 3. ct_resolver.dart（本地 unblind 储备，接口对齐）
   → 4. native_rpc.dart（代理调用契约对齐）
   → 5. 端到端验证（真链铸造/转账/赎回）
```
> 1 是 2 的前置（签名需要正确密钥），1–2 是 3–4 的前置（unblind 需同一密钥体系）。

---

## 1. `lib/core/crypto/derivation.dart`

### 1.1 隐私派生路径常量

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| 行 26 `nativePrivatePath` | `"m/44'/307'/0'/1/0"` | 官方 Path C 的完整 BIP32 路径（含 coin type 与分支索引） |
| 行 23 `nativePlainPath` | `"m/44'/307'/0'/0/0"` | 如带官方 Path A/B 编号，同步修正；否则保留并注明依据 |

**验收**：相同助记词在 APP 与链上既有钱包派生出的 `rcpux1...` 地址一致。

### 1.2 地址协议编码

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| 行 63-66 `_protocolEncode()` | `publicKey.sublist(0,20)` 拼 hex（fake 编码，非链上可用） | **bech32m** 编码（官方 `src/key_io.cpp` 已确认）：`0x00 || HASH160(compressed_pub) || compressed_pub(33B)` → ConvertBits 8→5 → `bech32m("rcpux", data)`；明文 `rcpu1` 用 **BECH32**（P2WPKH），勿混用。详见 `docs/path-c-spec.md` §3/§4 |

**验收**：`deriveNativePrivateAddress()` 输出可被链上浏览器/桥校验，且与官方钱包导出地址一致。

### 1.3 派生密钥扩展

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| 新增能力 | 私钥仅存在于 `deriveKey` 内部 | 暴露「struct：spending key + viewing key + blind factor seed」派生结果，供 signature/ct_resolver 复用；或返回统一的 `NativeKeyBundle` 模型 |

**验收**：同一助记词多次调用派生结果确定（确定性），且双 key 可独立导出/备份。

---

## 2. `lib/core/crypto/signature.dart`

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| 行 11-13 `signNative(tx, privateKey)` | `UnimplementedError('原生签名算法待协议文档确认')` | 按官方方案实现：私钥 → 签名（Clsag/ECDSA/RingCT 由协议定），并在 CT 场景附加 Pedersen 承诺 + 范围证明；构造盲化因子、一次性 nonce |
| 行 16-19 `verifyBscSignature` | `UnimplementedError('BSC 签名校验待接入')` | 独立于 CT 改动的 BSC 侧；建议接入 `web3dart` 的 `recoverAddress`（`MessageDigest` + `secp256k1`），与本文件解耦 |

**验收**：
- 用官方测试向量（固定私钥/消息/盲化种子）输出签名哈希与文档一致；
- 链上确认交易后，`verifyBscSignature` 能从签名恢复出发送方地址。

> 注意：当前 `signNative` 在工程内**尚无实际调用者**（`native_service.dart` 仅调用
> `CtResolver().resolveOutput`）。新增原生支付/收款流程时，应在
> `native_service.dart` / `payment_service.dart` 中接入本签名方法的调用；
> 若协议要求签名方法参数变化（如增加盲化因子种子、接收方 CT 公钥），
> 需同步调整新接入处的方法签名。

---

## 3. `lib/core/utils/ct_resolver.dart`

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| 行 9-15 `resolveOutput(txHex, ownAddress, unblindingKey)` | `UnimplementedError('CT unblind 待接入：代理优先，本地储备')` | 本地 unblind 储备实现：parsing proof → ECDH nonce 恢复 → 解承诺 → 校验范围证明 → 返回明文金额（micro）；或按代理契约改为纯转发 `resolve_ct` |

**验收**：
- 对代理已 unblind 的同一条真实交易，本地实现返回相同金额；
- 非本人输出返回 `null`（不抛异常，由调用方降级展示）。

> 工程策略：生产默认走代理（`native_rpc.resolveCtOutput`），本地实现仅作双端校验
> 与代理不可用时的兜底；两者结果不一致时以代理为准并告警。
>
> 调用点联动：`native_service.dart` 行 25-27 的 `resolveCtOutput(String txHex)` 目前以
> `CtResolver().resolveOutput(txHex, '', '')` 空参数占位调用，Path C 落地后需改为
> 传入真实 `ownAddress` 与 `unblindingKey`（可从 [NativeKeyBundle] 派生结果取值，
> 见第 1.3 节），并决定走代理还是本地。

---

## 4. `lib/core/network/native_rpc.dart`

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| 行 70-72 `resolveCtOutput(txHex)` | `UnimplementedError('CT unblind 待接入代理或本地实现')` | 按代理最终 RPC 契约实现：`resolve_ct` 方法号与参数（单 txid / txHex），解析返回的明文金额与元数据 |

**此外需核对（如需新增）**：
- `getBalance` 现返回 `Balance(asset:'native', raw:, micro:)`——确认代理返回是否含「明文+CT 分开统计」字段；若是，扩展 `Balance` 模型（新增 `plainMicro` / `ctMicro`）以支撑 UI「明细拆分」展示；

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| `Balance` 模型（如代理拆分返回） | 仅 `raw`/`micro` 合计 | 增加明文/CT 分量字段，`toString` 与序列化同步扩展 |

**验收**：本地 mock 代理（`http://127.0.0.1:7337`）按契约返回后，APP 余额、历史记录与明细页均正确渲染；异常（代理返回错误码）有兜底文案。

---

## 5. 端到端验证矩阵（全部替换完成后）

| 场景 | 步骤 | 预期 |
| --- | --- | --- |
| 派生一致性 | 导入官方测试助记词 | `rcpux1` 地址与官方钱包一致 |
| CT 收款 | 对方发 CT 输出到本 APP `rcpux1` | `get_balance` 合计包含该笔，明细页明文显示金额 |
| CT 付款 | 扫码 `rcpu:rcpux1...?amount=1.5` → 指纹 → 广播 | 链上确认，接收方余额增加 1.5（去盲化一致） |
| 铸造（Deposit） | 明文 `rcpu1` 转账 ≥ 0.01，累计满 10 | 桥铸造 wRCPU 到 BSC 地址（`bridge_provider` 轮询 10s/20s/40s 后退避终止提示） |
| 赎回（Redeem） | BSC 调用 burn → 指定本 APP 明文 `rcpu1` 收款 | 桥处理后原生余额自动到账 |

---

## 6. 每项改动无协议文档时的临时策略

| 文件 | 无文档临时策略 | 风险 |
| --- | --- | --- |
| derivation.dart | 保持占位常量，新增 `const String pathCPlaceholder` 显式标记，禁止线上使用隐私地址收款 | 隐私地址不可用，仍可用明文 `rcpu1` 收付 |
| signature.dart | 保持 `UnimplementedError`，CT 交易拒绝发起；明文交易走 `broadcast` | 功能降级为仅明文 |
| ct_resolver.dart | 保持占位，隐私明细展示「金额保密」 | 体验降级，不阻塞其他功能 |
| native_rpc.dart | 代理契约确定前不改方法签名 | 无 |

> 以上策略保证「拿到官方文档前主干可编译、明文通道可用、隐私能力安全降级」。