# CI 平台签名 Secrets 配置指引

> 状态：操作指引 v0.1｜更新：2026-10-14
> 对象：`.github/workflows/ci.yml`（GitHub Actions）与 `.gitlab-ci.yml`（GitLab CI）。
> 背景：流水线在未配置签名 secrets 时自动降级构建 debug APK（流水线不失败，但 release 产物不可发行）；
> 配置以下 4 个变量后，restart 流水线即可产出 **release 签名 APK** 并执行 `apksigner` 签名校验。
> **实测记录见 `docs/release-signing-trigger.md`（2026-10-14 已跑通签名构建并验签）**。

---

## 0. 需要准备的 4 个值

| Secret / 变量名 | 内容 | 来源 |
| --- | --- | --- |
| `ANDROID_KEYSTORE_B64` | keystore 文件的 **Base64 编码**（文本，单行） | 本机 `android/rcpu-release.jks` 编码而来 |
| `KEYSTORE_PASSWORD` | JKS storePassword | 生成 keystore 时设定 |
| `KEY_PASSWORD` | JKS keyPassword | 生成 keystore 时设定 |
| `KEY_ALIAS` | 别名（工程默认 `rcpu`） | `keytool -genkeypair -alias` 时设定 |

### 生成 `ANDROID_KEYSTORE_B64` 的命令

```bash
# Git Bash / WSL / macOS / Linux
base64 -w0 android/rcpu-release.jks
# 输出较长，一次性全部复制进 Secret

# Windows PowerShell（无 base64 命令时）
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\rcpu-release.jks"))
```

> 安全红线：keystore 文件与两个密码**禁止提交版本库**（`android/rcpu-release.jks`、`android/key.properties` 须在 .gitignore）；
> 流水线内只消费 Base64 文本，不在日志打印明文密码（本工程 CI 脚本已按此设计）。

---

## 1. GitHub Actions

1. 进入仓库 → **Settings** → **Secrets and variables** → **Actions**；
2. 点击 **New repository secret**，依次新建 4 个 Secret：
   - `ANDROID_KEYSTORE_B64`（粘贴上一步 Base64 文本，勾选无明文可见性选项如有）
   - `KEYSTORE_PASSWORD`
   - `KEY_PASSWORD`
   - `KEY_ALIAS`（值为 `rcpu`，与 `keytool` 生成时一致）
3. 触发流水线（push / PR / 手动 `workflow_dispatch`）；
4. 检查流程：`release` job 中「Check signing config」应输出 `signing=enabled`，随后出现「Install signing material」→「Build release APK (signed)」→「Verify APK signature」（apksigner 打印证书）；
5. 产物在 Actions 运行页的 **Artifacts**（`rcpu-wallet-apk-<sha>`），保留 14 天。

> 说明：未配置 secrets 时同样能跑通（debug 降级），「Verify unsigned APK exists」步骤显式确认降级产物存在，便于排查。

---

## 2. GitLab CI

1. 进入项目 → **Settings** → **CI/CD** → **Variables**；
2. 点击 **Add variable**，依次添加 4 个变量：
   - `ANDROID_KEYSTORE_B64`（粘贴 Base64 文本）
   - `KEYSTORE_PASSWORD`
   - `KEY_PASSWORD`
   - `KEY_ALIAS`（值为 `rcpu`）
3. 建议选项：
   - **Masked**：对两个密码与 `KEY_ALIAS` 勾选（Base64 文本过长，GitLab Masked 有长度限制时可只 mask 密码）；
   - **Protected**：仅受保护分支/标签使用的流水线生效，防止 MR 分支被注入使用正式密钥；
4. 运行流水线，查看 `build` 阶段日志：应输出 `==> signing: enabled` 并构建 release APK；
5. `verify-signature` 阶段对 artifacts 中的 APK 执行签名校验；产物在流水线页 **Job artifacts**（`rcpu-wallet-apk-<sha>`，14 天过期）。

> 说明：镜像锁定 `cirrusci/flutter:3.22.4`（与 pubspec `sdk >=3.3.0`、web3dart 2.7.3 验证环境一致）；
> 变量缺失时 `build` 阶段自动降级 debug 并打印 WARN。

---

## 3. 验收清单

- [ ] 4 个 Secret / 变量全部配置（名称与上文一致，注意大小写）；
- [ ] 重新触发流水线后 `signing=enabled` 生效；
- [ ] 产出 `app-release.apk`，签名校验步骤打印证书（SHA-256 与本地 `keytool -list -v` 一致）；
- [ ] 日志中未泄露密码或 Base64 明文；
- [ ] 本地 `git status` 确认 `android/rcpu-release.jks` 与 `android/key.properties` 未被提交（.gitignore 生效）。