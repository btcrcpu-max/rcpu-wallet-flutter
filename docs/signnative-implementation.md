# signNative 原生交易签名实现方案（基于官方 Path C 规范）

> 状态：**实现方案 v1.1**｜更新：2026-10-14（T5 交易构造已实装：§7.3 / §8 步骤 5）
> 依据：`docs/path-c-spec.md`（C1 已解锁的 Path C 官方规范）、官方仓库
> `github.com/btcrcpu-max/rcpu`（`doc/ct-path-c.md`、`doc/confidential-transactions.md`、
> `src/key_io.cpp`、`src/blind.cpp`）。
> 对应占位：`lib/core/crypto/signature.dart`（`Signature.signNative` /
> `SignatureService.signNative`）、`lib/features/payment/payment_service.dart`（`_buildTxHex`）。
> 测试向量：`docs/ct-test-cases.md` TC-SIG-02（HKDF/ECDH 层已 4/4 通过）、官方 Appendix A/C。

---

## 1. 结论与边界

- **可本地实现**：BIP32 派生、ECDH（CopyX32）、HKDF-SHA256（nonce / view seed）、
  隐私地址 bech32m 编码、交易序列化与 sighash 计算、私钥签名（Schnorr，P2TR 花费）。
- **依赖官方签名库 / 代理辅助**：CT 输出构造（rangeproof 的盲化承诺）、批量 `BlindOutputToRecipientV2`。
  与 `path-c-spec.md` §4.4 工程策略一致：**生产走轻量代理构造 CT 部分，本地实现作为储备与双端校验**。
- 本篇给出**完整交易构造 + 签名 + 广播**的思路、密钥与逐步实现，并对照现有占位列出改造点；
  CT 盲化承诺的回填由代理或官方库完成，接口以「盲化输出字节回填」形式预留。

## 2. 所需密钥与衍生材料

| 密钥/材料 | 来源 | 用途 |
| --- | --- | --- |
| 助记词（12 词） | 用户创建/导入 | 种子 → 全部密钥根 |
| BIP32 种子 | `bip39.mnemonicToSeed` | 注入 `Derivation`（已实现） |
| 明文花费私钥 `sk_plain` | 路径 `m/44'/307'/0'/0/0` | 明文 `rcpu1` 地址与 P2TR 花费签名 |
| 隐私花费私钥 `sk_priv` | 路径 `m/44'/307'/0'/1/0` | 隐私 `rcpux1` 地址与 P2TR 花费签名 |
| 公钥 `pk = sk·G`（压缩 33B） | 上述私钥派生 | 地址编码（keyid + 见证程序）、ECDH 参与方 |
| 每输出 ephemeral 私钥 `e_priv` | 每次构造随机生成（**禁止复用**） | ECDH 生成共享密钥 `ss` |
| `ss = ECDH(e_priv, recip_pk)` | CopyX32（32B X 坐标，无预哈希） | HKDF 的 IKM |
| `view_seed` | `HKDF-Extract(salt=rcpu-pathc-v1, ikm=ss)` | 生成重放 nonce（也是代理 unblind 的 rewind 材料） |
| 发送 nonce | `HKDF-Expand(info=spk||0x01||le64(64))` | 隐私输出 nonce 字段 = `0x04 || X(e_pub)` 的对称密钥衍生 |

> 密钥安全：全程只驻留内存（`sigstore` 用 Android Keystore/iOS Keychain 加密持久化助记词），
> 与 `docs/ct-integration.md` 口径一致。

## 3. 原语参数（官方已 LOCKED，逐步复用 TC-SIG-02 已测实现）

### 3.1 ECDH（ComputeECDHNonce）

```
ss = ephemeral_priv * recipient_spend_pub   # secp256k1, CopyX32 = 取 X 坐标 32 字节
```
- 双向对称：`ECDH(e_priv, r_pub) == ECDH(r_priv, e_pub)`（官方 Appendix A B1 已断言）。
- 实现层已过单测：`test/tc_sig02_hkdf_test.dart`（HKDF/ECDH 层 4/4 通过）。

### 3.2 HKDF-SHA256（RFC 5869，L=32）

```
view_seed = HKDF-Extract(salt = "rcpu-pathc-v1", ikm = ss)
nonce     = HKDF-Expand(PRK = view_seed, info = spk || 0x01 || le64(64), L = 32)
```
- `info` 绑定该输出原始 `scriptPubKey` 字节（P2TR = `0x51 0x20 || x-only`，34 字节）；
- salt/info 均为 UTF-8 原始字节，无 NUL 终止符；
- 官方向量：C1（spkA / 0x01 / le64(64)，sender nonce `0dc4…7c`、view_seed `23f7…fe`）。

### 3.3 Nonce 字段（33 字节）

| 字节 | 值 |
| --- | --- |
| byte[0] | `0x04`（Path C） |
| byte[1..32] | ephemeral 公钥 **X 坐标**（33B 公钥去掉前缀字节） |

- Y 奇偶性不写入；收款方重构时先试 even-Y（`0x02||X`）再试 odd-Y（`0x03||X`）；
- fee 输出与裸明文输出（`rcpu1`）**永不携带** Path C nonce。

### 3.4 地址编码（C2 已解锁，`derivation.dart` 待重写）

- 隐私 `rcpux1`：bech32m（HRP=`rcpux`），payload = `0x00 || HASH160(compressed_pub 33B) || compressed_pub 33B`，共 54 字节 8→5 ConvertBits；
- 明文 `rcpu1`：P2WPKH bech32（HRP=`rcpu`），payload = `0x00 || HASH160(pub 20B)`，**BECH32 非 bech32m**。

## 4. 交易构造步骤（`_buildTxHex` 替代方案）

输入：收款地址（`rcpu1` 或 `rcpux1`）、金额 micro、找零地址、手续费率。

```
1. 查询 UTXO（get_balance / listunspent，代理或公开 RPC）
   - 仅取自有、未花费、已确认输出；CT 输出须先经代理 unblind 得到可用金额
2. 选择输入：按需凑足金额 + 手续费（下限满足，避免暴露全部余额）
3. 构造输出：
   a. 收款输出：
      - 明文 rcpu1：脚本 P2WPKH 或 P2TR？→ 官方默认：rcpu1 为显式明文（无 nonce）：
        金额明文写输出；scripthash = 收款方 P2TR/P2WPKH（按地址版本）
      - 隐私 rcpux1（默认 Path C）：
        nonce = 0x04 || X(e_pub)；金额用盲化承诺（rangeproof）——由代理/官方库
        BlindOutputToRecipientV2 批量生成，APP 填入返回字节；sym_key = nonce（见 §3.2）
   b. 找零输出：归自己（明文或 CT，默认明文以简化）
   c. fee 输出：永不携带 nonce；手续费用输入差额
4. 检查：非 fee 输出若含隐私地址必须全部具备 key（fail-closed，参照 path-c-spec §2.5）
5. 序列化交易（版本号、输入 outpoints、scriptSig（P2TR 为空的 witness v1）、输出、locktime）
6. 计算 sighash：BIP341 taproot sighash（P2TR 花费）；明文 P2TR 找零/输入同规则
7. 签名：Schnorr（BIP340）对每个输入签名，填入 witness
8. 返回完整交易 hex
```

> 依赖代理的部分集中在步骤 3a 的**盲化承诺 (rangeproof)**：承诺值本身需要
> 生成 pedersen commitment + range proof 的随机盲因子，官方 Bitcoin Core 钱包基座
> （`src/blind.cpp`）才有完整实现；APP 侧不建议重写，按「构造请求 → 回填盲化输出字节」对接。

## 5. 签名与广播（`signNative` 替代方案）

```
SignatureService.signNative(txHex, privateKeyHex):
  1. 反序列化 txHex；解析出待填充签名的输入（witness v1/P2TR）
  2. 对每个输入：
     - 用输入私钥（sk_plain 或 sk_priv，按输入归属地址路径）
     - 构造 BIP341 sighash（SIGHASH_DEFAULT，即 0x00）
     - BIP340 Schnorr 签名（secp256k1，nonce 随机且禁止复用）
     - 写回 witness：<schnorr_sig>
  3. 序列化 → 返回带 witness 的完整交易 hex
  4. 广播：nativeRpc.broadcast(signedTxHex) → txid
```

- 仅 **signing part** 落地 `signature.dart`；盲化输出已有（步骤 4.3a 由代理/官方库提供）。
- 隐私地址收款（`rcpux1`）在本地无盲化能力时**不允许静默改为明文**（Path A 主网已共识禁用，
  v1.1.10 起 fail-closed），上层 UI 明确提示「该收款地址需代理协助，请开通代理模式」。

## 6. 所需依赖（新增 pubspec）

| 包 | 用途 | 状态 |
| --- | --- | --- |
| `pointycastle` ^3.9.1 | SHA256/HMAC/HKDF、ECDH、secp256k1 曲线原语 | 已引入（dev → dependencies 提升，T1 定案） |
| `bech32` / 自实现 | bech32m 编解码（BECH32M 常量 `0x2bc830a3`） | 自实现（`lib/core/crypto/bech32.dart`，BIP173/BIP350 官方向量锚定） |
| BIP340 Schnorr 自实现 | secp256k1 曲线、BIP340 签名 | 自实现（`lib/core/crypto/bip340.dart`，基于 pointycastle 3.9.1，BIP340 官方向量锚定） |
| web3dart 已有 | keccak 用于 BSC 侧 | 已有 |

> **T1 依赖探测结论**（2026-10-14）：
> - `package:bech32 0.2.2`：SDK 约束 `>=2.12.0 <3.0.0` 不兼容 Dart 3.13，且**无 bech32m**（BIP350）→ 自实现；
> - `package:bip340 0.3.1`：依赖 pointycastle ^4.0.0，与既有 bip32 2.0.0 的 pointycastle ^3.0.1 **冲突** → 基于 pointycastle 3.9.1 自实现；
> - `package:secp256k1 0.4.1`：仅 ECDSA（`secp256k1` 私钥/公钥），无 BIP340 → 排除；曲线操作直接复用 pointycastle。

## 7. 对照现有占位代码的改造点

### 7.1 `lib/core/crypto/derivation.dart`（§4.2 已有方向）

| 现实现 | 改造 |
| --- | --- |
| `_protocolEncode`（行 63-66）假编码 `pub.sublist(0,20)` hex | 拆为 `_encodeConfidential(pub)`（bech32m `rcpux`）与 `_encodePlain(pub)`（BECH32 `rcpu`）；keyid = HASH160 |
| 无密钥可见接口 | 新增 `NativeKeyBundle{ spendPriv, spendPub(33B), keyid }`，供 signature 与 ct_resolver 复用 |
| 路径常量 | 保持 `m/44'/307'/0'/0/0`、`m/44'/307'/0'/1/0` 占位（已注释待官方确认） |

### 7.2 `lib/core/crypto/signature.dart`

| 现实现 | 改造 |
| --- | --- |
| `Signature.signNative`（行 14-16）抛 `UnimplementedError` | 已实现：对 32B 消息（BIP341 sighash）做 BIP340 Schnorr 签名，返回 64B `r\|\|s`（TC-SIG-04b） |
| `SignatureService.signNative`（行 65-70）占位 | 已实现：hex → `NativeTxCodec` 反序列化 → 逐输入 BIP341 key-path sighash（SIGHASH_DEFAULT）→ BIP340 签名 → 写回 witness `sig64` → 序列化返回；prevout 上下文（scriptPubKey + amount）由调用方经 `prevOuts` 提供（BIP341 sighash 所需，交易体不含）；`rcpux1` 盲化经代理回填（TC-SIG-04 闭环锚定） |

> 新增 `lib/core/crypto/native_tx.dart`（交易解析/序列化，signature 依赖）与
> `lib/core/crypto/bip341.dart`（P2TR key-path sighash，BIP341 规范）。

### 7.3 `lib/features/payment/payment_service.dart`

| 占位/现状 | 状态 |
| --- | --- |
| `_buildTxHex`（行 93-95）返回占位字符串 | **已落地（2026-10-14，T5）**：真实 UTXO 选择 + 输出构造 + fee + prevOuts 串接。明文收款 `rcpu1`：`get_utxos`（§6.2 契约）→ 过滤 `confirmed && P2TR` → 升序最小足够集合 → P2WPKH 收款输出（`0x00 0x14 || h160`）+ 找零（差额归 fee）→ version=2 / seq=0xfffffffd / locktime=0；隐私收款 `rcpux1` 本地无盲化能力 → fail-closed 抛 `UnimplementedError`（不静默降明文，path-c-spec §2.5）→ 上层降级提示「仅支持明文地址支付」。数据源经 `NativeRpcClient.getUtxos`（代理 `get_utxos`，方法号 5）。锚定测试：test/tc_payment_build_test.dart（TC-PAY-01：单/多输入选择、找零与 fee 守恒、P2WPKH 脚本、witness 64B、余额不足/无 P2TR/未确认/隐私降级全分支）。 |
| `confirmAndPay` 降级分支（行 78-87） | 保留 `UnimplementedError` 捕获作为「隐私收款/代理未就绪」提示；明文收款路径已走完整签名广播链（`signNative(prevOuts)` → `broadcast`）。 |

### 7.4 `lib/core/utils/ct_resolver.dart` / `lib/core/network/native_rpc.dart`

| 现实现 | 改造 |
| --- | --- |
| `CtResolver.resolveOutput` 抛错 | **已落地（2026-10-14）**：接代理 `resolve_ct`（docs/proxy-rpc-schema.md §6.1 对象形态，txHex+viewSeed+ownScriptPubKey），返回本人输出合计 / 非本人 null；HKDF 原语（deriveViewSeed / deriveRewindNonceFromViewSeed / derivePathCNonce）已迁移至 `ct_resolver.dart` 并由官方向量锚定（test/tc_sig02_hkdf_test.dart）。本地 unblind 储备未展开。 |
| `NativeRpcClient.resolveCtOutput` 抛错 | **已落地（2026-10-14）**：替换为 `resolveCt`，按 `resolve_ct` 契约（§6.1）构造请求、解析 `amountMicro`/`verified`、错误码映射为 `RpcException`（-32002/-32001 等）；契约层锚定于 test/tc_ct_resolve_test.dart。 |

## 8. 实现顺序与验证

1. **地址编码**（独立，可先行）：bech32m `rcpux1` / BECH32 `rcpu1` + 单元测试（官方地址向量）；
2. **NativeKeyBundle**（依赖 1）：派生并缓存三件套，TC-DRV-03 确定性用例；
3. **盲化回填接口**（依赖代理）：定义 `createBlindedOutput(recipientPub, amountMicro) → (tx 片段, nonce)`，
   代理/官方库实现，APP 侧先以 mock 通过 TC-SIG-03 占位流程；
4. **Schnorr 签名**（依赖 2，不依赖 3）：BIP340/BIP341 输入签名 + 单测（构造-验签闭环）；
5. **交易串接**：_buildTxHex 真实现 + 端到端仿真空投（无代理时明文收款路径可全链验证）。
   **✅ 已落地（2026-10-14，T5）**：明文收款端到端闭合——`get_utxos` → UTXO 选择 →
   P2WPKH 输出 + 找零 → BIP341 sighash → BIP340 签名（witness 64B）→ `broadcast`；
   锚定测试 `test/tc_payment_build_test.dart`（TC-PAY-01 全分支 + TC-PAY-02 请求形态）。

> 官方向量仍为准绳：路径 A/B 回归（Appendix A B1）、Extract/Expand（Appendix C C1）已过；
> P2TR 输出/签名类目暂无官方附录向量，以「构造→本地反解析→金额一致」为验收。

## 9. 风险与回退

| 风险 | 缓解 |
| --- | --- |
| 盲化/rangeproof 无法本地实现 | 生产代理优先（既定策略）；本地实现仅做 rewind 校验 |
| BIP340 包能力不足 | 降级直接调官方库（C FFI）或延长代理范围 |
| 找不到 P2TR 官方测试向量 | 先明文路径端到端；隐私路径以代理输出为准做契约测试 |
| KeyBundle/路径与官方钱包不一致 | 已标注待官方确认；落地后以官方导出地址回归 TC-DRV-01/02/05 |

> 关联：`docs/path-c-spec.md`、`docs/path-c-fix-list.md`、`docs/ct-test-cases.md`、
> `docs/proxy-rpc-schema.md`、`docs/tc-sig03-implementation.md`。