# 签名 Secrets 配置与 workflow_dispatch 触发指引（已实测验证）

> 状态：**v1.0（已实测通过）**｜更新：2026-10-14
> 配套：`docs/ci-secrets-setup.md`（网页配置基线）、`docs/android-signing.md`（keystore 生成与 gradle 接入）。
> 本文件记录：①4 个 Secrets 的完整配置步骤（网页 + REST API 两种方式）；
> ②触发签名构建的 workflow_dispatch 命令；③2026-10-14 实测结果与验收证据。
> 结论先行：签名 release APK 构建链路已在本仓库**真实跑通并验签成功**（见 §4）。

---

## 1. 四个 Secrets 清单

| Secret | 内容 | 说明 |
| --- | --- | --- |
| `ANDROID_KEYSTORE_B64` | keystore 文件 Base64（单行文本） | `base64 -w0 android/rcpu-release.jks` |
| `KEYSTORE_PASSWORD` | JKS storePassword | 生成 keystore 时设定 |
| `KEY_PASSWORD` | JKS keyPassword | 生成 keystore 时设定 |
| `KEY_ALIAS` | 别名 | 工程默认 `rcpu` |

> 读取逻辑见 `.github/workflows/ci.yml` `release` job：
> 三者（`ANDROID_KEYSTORE_B64/KEYSTORE_PASSWORD/KEY_PASSWORD`）均非空时 `signing=enabled`，
> 注入 `android/rcpu-release.jks` + `android/key.properties` 后构建 release 签名 APK 并 apksigner 验签；
> 任一缺失则降级 debug 兜底（流水线不失败）。

## 2. 工程侧前置（必做，已落地）

- `android/app/build.gradle.kts` 必须已按 `docs/android-signing.md` §3 接入 `key.properties`：
  - 本次实测前该文件 release 仍回退 debug 签名（Flutter 模板占位），导致即便注入 jks 也不生效；
  - 已于 2026-10-14 修复并推送（commit `f438ada`）：读取 `android/key.properties`，
    存在时用 `signingConfigs.release`，不存在时回退 debug。**此改动是签名链路生效的前提。**
- `android/.gitignore` / `.gitignore` 已含 `key.properties` 与 `*.jks`（防误提交）。

## 3. 配置 Secrets 的两种方式

### 3.1 网页方式（人工，适合一次性配置）

1. 仓库 → **Settings** → **Secrets and variables** → **Actions**；
2. **New repository secret**，依次新建 4 项（名称见 §1）；
3. 生成 Base64：`base64 -w0 android/rcpu-release.jks`（复制整行文本，勿换行）。

### 3.2 REST API 方式（可脚本化，实测路径）

```bash
# ① 取 token（GCM 凭证，须有 repo + workflow 权限）
TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential fill | sed -n 's/^password=//p')

# ② 获取仓库公钥（GitHub 用 libsodium sealed box 加密 secret 值）
PUB=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/btcrcpu-max/rcpu-wallet-flutter/actions/secrets/public-key")
KEY_ID=$(echo "$PUB" | python -c "import sys,json;print(json.load(sys.stdin)['key_id'])")
KEY_PEM=$(echo "$PUB" | python -c "import sys,json;print(json.load(sys.stdin)['key'])")

# ③ 用 nacl 密封各值（pip install pynacl 或用任意语言的 sealed box 实现）
python - "$KEY_PEM" <<'PYEOF'
import sys, base64, json
from nacl import encoding, public
pub = public.PublicKey(sys.argv[1], encoding.Base64Encoder)
vals = {
  'ANDROID_KEYSTORE_B64': open('jks_b64.txt').read().strip(),  # 由 base64 -w0 生成
  'KEYSTORE_PASSWORD': '<PASSWORD>',
  'KEY_PASSWORD': '<PASSWORD>',
  'KEY_ALIAS': 'rcpu',
}
out = {k: base64.b64encode(public.SealedBox(pub).encrypt(v.encode())).decode() for k, v in vals.items()}
json.dump(out, open('sealed_values.json', 'w'))
PYEOF

# ④ PUT 四个 secret
for name in ANDROID_KEYSTORE_B64 KEYSTORE_PASSWORD KEY_PASSWORD KEY_ALIAS; do
  enc=$(python -c "import json;print(json.load(open('sealed_values.json'))['$name'])")
  curl -X PUT -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/btcrcpu-max/rcpu-wallet-flutter/actions/secrets/$name" \
    -d "{\"encrypted_value\":\"$enc\",\"key_id\":\"$KEY_ID\"}"
done
```

> 权限校验：`GET /repos/btcrcpu-max/rcpu-wallet-flutter/actions/secrets` 返回 200 且能读取
> public-key / 写入 secret / 触发 dispatched，即可判定 token 具备 `actions:write` 等价能力
> （当前登录用户为仓库 owner，实测 4 个 PUT 均 201 成功）。

## 4. 触发签名构建（workflow_dispatch）

### 4.1 网页触发

Actions → 左栏 **CI** → 右上 **Run workflow** → 分支选 `main` → **Run workflow**。

### 4.2 API 触发（实测命令）

```bash
curl -X POST -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/btcrcpu-max/rcpu-wallet-flutter/actions/workflows/ci.yml/dispatches" \
  -d '{"ref":"main"}'
# 成功返回 204；随即轮询 run 状态：
curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/btcrcpu-max/rcpu-wallet-flutter/actions/runs?event=workflow_dispatch&per_page=3"
```

### 4.3 本次实测记录（2026-10-14）

| 项 | 结果 |
| --- | --- |
| Secrets 配置 | 4 项全部 PUT 201 成功（`total_count: 4`） |
| 触发方式 | REST API `workflow_dispatch`（ref=`main`），返回 204 |
| Run ID | **38570980965**，head=`f438ada`（含签名接入修复） |
| Analyze & Test | ✅ success（flutter analyze 0 issues + flutter test 41 pass / 12 skip） |
| Run TC-SIG-03 | ✅ success |
| **Build APK (signed when secrets present)** | ✅ success：`signing=enabled` → `Install signing material` → `Build release APK (signed)` → `Verify APK signature` |
| 验签证据 | apksigner 输出 `V2 Signer: certificate SHA-256 digest: 48d6ac74f00dc566ca20f701e5066e5441d98d797539df17db2548c7eeb92360` |
| 指纹比对 | 与本地生成的测试 keystore 证书 SHA-256 **完全一致**（同一证书，签名材料注入链路正确） |

> 说明：本次使用**测试 keystore**（临时生成的 RSA-2048 自签证书，alias=`rcpu`）走通全链路，
> 仅用于验证构建与签名流水线；**正式对外发布前必须替换为正式 keystore 并重新配置 4 个 Secrets**
> （否则更新包将使用测试密钥签名，无法通过商店提审）。

## 5. 验收清单（对照本次实测）

- [x] `android/app/build.gradle.kts` 已接入 key.properties（commit `f438ada`）
- [x] 4 个 Secrets 名称/值正确（REST API 复核 `total_count: 4`）
- [x] workflow_dispatch 触发成功（HTTP 204，run id 38570980965）
- [x] 日志出现 `signing=enabled`，无 `signing=missing` 降级
- [x] `Build release APK (signed)` 步骤 success，产出 `app-release.apk`
- [x] apksigner 验签步骤 success，证书指纹与 keystore 一致
- [x] 日志未泄露密码/Base64 明文（CI 仅 echo 状态、不回显材料）

## 6. 风险与后续

- **正式 keystore 替换**：生成正式 jks → 重配 4 Secrets → 重新触发（同 §4）→ 指纹变更为正式证书后即可提审；
- **密钥不可再生成**：keystore 丢失 = 无法更新已发布应用（见 `docs/android-signing.md` 红线）；
- **GitLab CI 对照**：变量配置与触发按 `docs/ci-secrets-setup.md` §2 执行（GitHub 侧已验证，GitLab 需在对应平台重复 §1–§3 等价步骤）。