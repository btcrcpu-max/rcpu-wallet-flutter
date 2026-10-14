# Path C 官方规范（C1 已解锁）与 `derivation.dart` 修改方向

> 状态：**C1（Path C 协议）已解锁**｜C2（地址编码）已解锁，**密钥派生路径待官方确认**｜更新：2026-10-14
> 来源：官方仓库 `github.com/btcrcpu-max/rcpu`（`doc/ct-path-c.md`、`doc/confidential-transactions.md`、
> `doc/address-format.md`、`src/key_io.cpp`、`src/blind.cpp`、`doc/release-notes/v1.1.6|v1.1.7|v1.1.10.md`）
> 用途：替代 `docs/path-c-c1-c2-template.md` 成为 Path C 落地的主依据；按本规范修改
> `lib/core/crypto/derivation.dart` 等占位实现。
> 归档：`path-c-c1-c2-template.md` 保留为「回填存档」，不再作为待办模板。

---

## 1. 官方来源与版本沿革（影响实现口径）

| 版本 | 内容 | 对本工程含义 |
| --- | --- | --- |
| v1.1.5 | 默认发送 fail-closed，不再写 Path A（裸 `rcpu1` 显式明文） | 明文通道永远可造，CT 默认走 Path C |
| v1.1.6（PR #66） | **默认发送路径翻转为 Path C**（`BlindOutputToRecipientV2`，`0x04` nonce） | `rcpux1...` 收款默认 Path C，是本工程默认口径 |
| v1.1.7 | Path C `0x04` nonce 上线 + `getviewingkey` / `importviewingkey` | viewing key RPC 可用；旧节点需先升级 |
| v1.1.10 | Path A 共识禁令（mainnet height 12748） | Path A 永远不可作为 fallback；`rcpux1` 无 key 输出 fail-closed |

> 结论：本工程以 **v1.1.6+ / v1.1.7 行为**为基线：`rcpux1` → Path C；`rcpu1` → 明文（无 nonce）。

## 2. Path C 完整规范（C1，官方已 LOCKED）

### 2.1 Nonce 字段（33 字节）

| byte0 | 含义 |
| --- | --- |
| `0x02` | Path A 明文 nonce（仅 `-ctlegacy=1`） |
| `0x03` | Path B 一次性压缩公钥（CopyX32 KDF） |
| `0x04` | **Path C**：一次性公钥 X 坐标，HKDF-SHA256（本工程使用） |
| 其他 | 无效，fail-closed，无 fallback |

布局：`byte[0]=0x04 || byte[1..32]=ephemeral_pubkey_X`。
Y 奇偶性**不写入** nonce 字段：重构时先试 even-Y（`0x02||X`），失败再试 odd-Y（`0x03||X`）；
两者都失败 → 该输出不可解，跳过（不得视为金额 0，不得回退 Path A/B）。

### 2.2 一次性密钥规则

- 每个 CT 输出独立 ephemeral key；**同一交易内相同 scriptPubKey 出现两次也不得复用**。
- Fee 输出与显式明文输出（裸 `rcpu1`）**永不携带** Path C nonce。

### 2.3 KDF（HKDF-SHA256，RFC 5869，L=32）

```
ss    = ECDH(ephemeral_priv, recipient_spend_pub)      # CopyX32：32B x 坐标，无预哈希
nonce = HKDF-SHA256(ikm = ss,
                    salt = "rcpu-pathc-v1",
                    info = scriptPubKey || 0x01 || le64(64))[0:32]
```

- salt / info 均为 UTF-8 原始字节，**无 NUL 终止符**。
- `info` 绑定该输出的原始 `scriptPubKey` 字节（P2TR 为 `0x51 0x20 || x-only`，34 字节）；
  同一收款密钥不同地址类型 ⇒ 不同 nonce。
- `0x01` 是 HKDF 块计数器；`le64(64)` 为小端 8 字节 `40 00 00 00 00 00 00 00`。
- ECDH 与 Path B 完全一致（`secp256k1_ecdh(..., CopyX32, nullptr)`），保证 Path B 历史 UTXO 仍可解。

### 2.4 Viewing key（opt-in，每输出 PRK）

拆分实现（sender 与 viewer 按构造字节相同）：

```
view_seed = HKDF-Extract(salt="rcpu-pathc-v1", ikm=ss)   # = HMAC-SHA256(key="rcpu-pathc-v1", msg=ss)
nonce     = HKDF-Expand(PRK=view_seed, info=scriptPubKey || 0x01 || le64(64), L=32)
```

- view_seed **不绑定** scriptPubKey；脚本绑定放在 Expand 的 info 域。
- view_seed 只能重放金额（rewind），**不能签名**；**不嵌入 `rcpux1` 地址**。
- 是每输出种子（fresh ephemeral ⇒ fresh ss），不是钱包级全局 viewing key。
- 已删除盐 `rcpu-view-v1` / `rcpu-rewind-v1`，禁止恢复使用。
- RPC：`getviewingkey` / `importviewingkey`（需确认）；默认不导出；永不与收款地址一并外发。

### 2.5 钱包规则（默认发送）

- `rcpux1...` → Path C（`0x04 || X`，HKDF rewind nonce）。
- 裸 `rcpu1...` → 显式明文（无 nonce，非 Path A）。
- `recipient_keys` 非空但某非 fee 输出缺 key → **fail-closed**（拒绝构造）。
- `-ctlegacy=1`：整笔交易强制走 Path A，绝不与 Path C 混合；主网默认禁用 Path A。

> 附录向量：官方 `doc/ct-path-c.md` Appendix A（Path B 回归，B1：ss=8ff9…f0）
> 与 Appendix C（Extract/Expand，C1：spkA / info / sender nonce 0dc4…7c / view_seed 23f7…fe）。
> 实现时必须逐字节通过二者（见 §5 测试规划）。

## 3. 隐私地址编码规范（C2 地址部分，官方源码确认）

来源：`src/key_io.cpp`（`EncodeConfidentialAddress`）+ `src/kernel/chainparams.cpp`。

- HRP（mainnet）：明文 `rcpu` → `rcpu1...`；隐私 `rcpux` → `rcpux1...`（regtest `rrcpux1`）。
- 隐私地址 = **bech32m**（非普通 bech32！`bech32::Encode(Encoding::BECH32M, "rcpux", data)`）。
- payload（编码前，8-bit）：`0x00 || HASH160(spend_pubkey_compressed) || spend_pubkey_compressed(33B)`，
  即 `CONF_ADDR_VERSION_P2WPKH || keyid(20B) || pubkey(33B)`，共 54 字节，再 8→5 ConvertBits。
- 约束：HASH160(spend_pub) 必须等于 witness program（blinding key 与 spend key 为同一把），否则拒绝编码。
- 链上输出是普通 P2TR 脚本（`0x51 0x20 || x-only`），保密来自 ECDH 盲化，不新增脚本类型。
- `getnewaddress` 默认返回 `rcpux1`；客户端仅应对外发放 `rcpux1`。

## 4. `derivation.dart` 修改方向（结合工程占位逐项）

### 4.1 隐私派生路径（`nativePrivatePath`）——仍待官方确认

| 项 | 当前占位 | 处理 |
| --- | --- | --- |
| 行 26-27 `nativePrivatePath` | `"m/44'/307'/0'/1/0"` | 官方仓库**未定义** Native RCPU 的 BIP32 路径常量（仅 BSC 侧标准 BIP44 有据）。继续保留该占位，并在注释中标注「工程自定，待官方钱包源码确认」；验收仍以「与官方钱包导出地址一致」为准（见 §4.3） |

> 说明：`grep` 官方 `src/` 未发现 Native 默认派生路径；RCPU 继承 Bitcoin Core 钱包体系，
> 派生路径属钱包实现层决策而非共识/协议规范。因此 C2 拆为两半：
> **地址编码（已解锁）** + **密钥派生路径（待官方钱包源码/官方确认）**，后者不阻塞编码实现。

> **归档确认（2026-10-14）**：`m/44'/307'/...` 占位**合理且可继续使用**——Coin type 307
> 未在 SLIP-44 注册，但工程内 BSC 与 Native 的 coin type 口径保持一致；明文
> `m/44'/307'/0'/0/0` 与隐私 `m/44'/307'/0'/1/0` 分别沿用常规 BIP44 账户与
> change/privacy 分支习惯（均**非协议强制**）。`derivation.dart` 注释已同步标注
> 「工程自定占位，待官方钱包源码/官方确认」；TC-DRV-01/02/05 的「与官方钱包一致」
> 断言仍待官方确认后闭环。

### 4.2 地址协议编码（`_protocolEncode`）——必须重写

| 项 | 当前占位 | 目标形态 |
| --- | --- | --- |
| 行 63-66 `_protocolEncode()` | `publicKey.sublist(0,20)` 拼 hex（fake，链上不可用） | 真实 bech32m 编码：`0x00 || HASH160(compressed_pub) || compressed_pub` → ConvertBits 8→5 → `bech32m("rcpux", data)` |
| 行 52-55 明文地址 | 同一 `_protocolEncode` 假编码 | 明文 `rcpu1`：P2WPKH bech32（`0x00 || HASH160(pub)`，Encoding::BECH32） |

实现要点：
- 需新增 bech32m 编解码（fluter 可引入 `bech32` 包或自行实现 BECH32M 常量 `0x2bc830a3`）；
  注意隐私用 **BECH32M**、明文用 **BECH32**，两者 checksum 不同，不可混用。
- `_protocolEncode` 拆为 `_encodeConfidential(pub)` 与 `_encodePlain(pub)` 两函数；
  输入为压缩公钥（33B），先取 `package:crypto` 的 `HASH160`/`sha256`+`ripemd160` 派生 keyid。

### 4.3 派生密钥结构（NativeKeyBundle）

| 项 | 当前 | 目标 |
| --- | --- | --- |
| 密钥可见性 | 私钥仅存在于 `deriveKey` 内部 | 新增 `NativeKeyBundle { spendPriv, spendPub, keyid }`：同一路径派生，供 signature / ct_resolver 复用；保证确定性（同助记词多次一致） |

隐私地址确定性验收：相同助记词连续派生 3 次地址一致（TC-DRV-03）；与官方钱包导出的 `rcpux1` 一致（TC-DRV-01/02 部分，路径确认后全通）。

### 4.4 依赖签名 / CT 解析的后续修改（依赖 4.1–4.3 完成）

| 文件 | 现占位 | 修改方向 |
| --- | --- | --- |
| `signature.dart` `signNative` | `UnimplementedError` | 交易构造加入 Path C：每个非 fee 输出生成独立 ephemeral、`0x04||X` nonce、HKDF nonce 与 rangeproof；**需链上尺码/官方签名库或代理辅助**（BlindOutputToRecipientV2 批量签名） |
| `ct_resolver.dart` `resolveOutput` | `UnimplementedError` | 解析 `0x04||X` → 重构 Y（even→odd）→ ECDH CopyX32 → HKDF rewind nonce → 解承诺；view_seed 路线（rewind-only）走代理或本地实现 |

> 工程策略不变：**生产走轻量代理 unblind**（含 viewing key），本地实现作为储备与双端校验。

## 5. 测试规划（official vectors 直转 Dart）

官方 `doc/ct-path-c.md` 附录为固定十六进制向量，直接作为 Dart 单测输入：

| 向量 | 断言（必须逐字节通过） |
| --- | --- |
| Appendix A B1 | `ComputeECDHNonce(ephemeral_priv, recipient_pub) == ss`；`ComputeECDHNonce(recipient_priv, ephemeral_pub) == ss`；Path B 回归 `0x03` |
| Appendix C C1 | `DeriveViewSeed(ss, any_spk) == view_seed`；`DerivePathCNonce(ss, spkA) == 0dc418…7c`；`DeriveRewindNonceFromViewSeed(view_seed, spkA) == sender nonce`；不同 spk ⇒ 不同 nonce 同 view_seed |

- ✅ **已落地且实测通过**：`test/tc_sig02_hkdf_test.dart`（HKDF/ECDH 层，C1 向量逐字节断言，
  不依赖地址派生与代理；2026-10-14 本机 Flutter 3.13.5 实测 4/4 通过）→
  **TC-SIG-02 部分解锁（签名向量层）**，CT 本地 unblind 的确定性部分可先行验证；
  签名本体 `signNative` 仍占位（见 §4.4）；
- 地址编码层用官方钱包生成地址比对（需官方钱包或代理返回）；
- 端到端：真链铸造/转账/赎回仍依赖 C4 契约定稿。

## 6. 阻塞解除判定

| 项 | 解锁条件 | 本工程状态 |
| --- | --- | --- |
| C1 Path C 协议 | 官方 `doc/ct-path-c.md` | ✅ 已解锁（本规范为整理版） |
| C2 地址编码 | 官方 `src/key_io.cpp` bech32m 细节 | ✅ 已解锁（§3） |
| C2 密钥派生路径 | 官方钱包源码/确认 | ⚠️ 待官方（不阻塞编码层，阻塞 TC-DRV-01/02/05 的“与官方一致”断言） |
| C3 viewing key / 代理 unblind | 内部自研 + 契约 | 🟢 客户端侧已落地（2026-10-14）：view_seed/rewind 公式已迁移 `ct_resolver.dart`，`resolve_ct` 契约（§6.1 对象形态）实现于 `native_rpc.resolveCt`，tc_ct_resolve_test.dart 锚定；待真实代理部署验收端到端 |
| C4 桥 + 代理契约 | B1–B5 回填 | ⏳ 待桥侧（`docs/bridge-backfill-schema.md`） |

> 关联文档：`docs/path-c-fix-list.md`（修改清单，§4 为其权威更新版）、`docs/path-c-check-list.md`（验收清单）、
> `docs/ct-test-cases.md`（TC-DRV/SIG/CT 用例）、`docs/path-c-c1-c2-template.md`（归档模板）、
> `docs/bridge-contract-checklist.md`（B 组）。

## 7. 风险与边界

- **bech32 vs bech32m 混用**：隐私地址必须 BECH32M、明文 P2WPKH 必须 BECH32，混用将导致地址互认失败——单测需含交叉解码用例。
- **Y 奇偶性**：Even→Odd 两轮都必须实现且入测试，漏 odd-Y 分支将丢失约一半真实输出。
- **view_seed 不绑定 spk**：即 `DeriveViewSeed` 第二个参数被忽略（官方 API 稳定占位），实现时勿在 Extract 阶段拼 spk。
- **Path A 永远不 fallback**：主网 v1.1.10 起 Path A 已共识禁用；`rcpux1` 缺 key 必须失败闭锁，不得降级明文。