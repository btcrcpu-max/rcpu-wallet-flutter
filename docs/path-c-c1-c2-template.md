# Path C 待确认规范模板（C1/C2）

> 状态：**待官方文档回填**｜更新：2026-10-14
> 用途：官方 CT / Path C 协议文档到位前的**对照填写模板**——拿到官方文档后将
> 「待确认内容」逐行回填，回填后即可替换 `derivation.dart` 中的占位路径与编码逻辑。
> 关联：`docs/path-c-fix-list.md`（修改清单）、`docs/path-c-check-list.md`（验收清单）、
> `docs/ct-test-cases.md`（TC-DRV-xx 用例）。

---

## 1. C1：RCPU 官方 CT / Path C 协议文档要点

> 拿到官方仓库或文档链接后，按以下字段逐项填写。

| 字段 | 待确认内容 | 填写示例 / 说明 |
| --- | --- | --- |
| 文档来源 | 官方仓库或文档链接 | （粘贴链接或附件） |
| Path C 名称 | 官方对隐私派生路径的命名 | Path C / Privacy Path |
| 盲化方案 | Pedersen 承诺 + 范围证明类型 | Bulletproofs / 其他 |
| viewing key 格式 | 长度、编码、是否可单独导出 | 32 字节 hex / bech32 |
| 签名算法 | 原生交易签名方案 | Clsag / ECDSA / 其他 |

## 2. C2：Path C BIP32 路径与地址编码规范

| 字段 | 待确认内容 | 填写示例 / 说明 |
| --- | --- | --- |
| 隐私派生路径 | 完整 BIP32 路径 | `m/44'/307'/0'/1/0` 或官方值 |
| 明文派生路径 | 是否与隐私路径同 coin type | `m/44'/307'/0'/0/0` |
| 地址前缀 | 隐私地址前缀 | `rcpux1` |
| 编码方式 | bech32 / 自定义 checksum | bech32 + 5-bit |
| 是否绑定 viewing key | 地址中是否包含 viewing key 信息 | 是 / 否 |

## 3. 使用方式

1. 拿到官方文档后，按上表逐行填写；
2. 将确认值回填到 `docs/path-c-fix-list.md` §1（`derivation.dart` 的 `nativePrivatePath`
   常量与 `_protocolEncode()` 编码逻辑）；
3. 按 `docs/path-c-check-list.md` A 组（地址派生）执行验收，关联用例 TC-DRV-01/02/05；
4. C1/C2 回填后再推进 C3（viewing key / 代理 unblind）与 C4（桥 + 代理契约定稿）。

> 阻塞关系：C1 ∩ C2 → 解锁 TC-DRV-01/02/05；C1 签名算法 → 解锁 TC-SIG-02；全部待确认项见
> `docs/bridge-contract-checklist.md` 与各测试用例的 skip 注释。