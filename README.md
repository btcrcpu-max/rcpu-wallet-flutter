# RCPU Wallet (Flutter) —— 手机钱包工程骨架

对标微信支付体验的双链钱包：原生 RCPU（明文 `rcpu1` + 隐私 Path C `rcpux1`）与 BSC 上的 wRCPU（BEP-20，合约 `0x2F720B253EF63176cF54b0088C7F57997dd2c340`，Decimals=8），并在 APP 内完成桥铸造/赎回（桥：https://rcpupool.asia/）。

## 状态

工程骨架（Phase 0–1 基础能力与测试骨架），本仓库用于 GitHub Actions CI（analyze + test + APK 构建）。

## 常用命令

```bash
flutter pub get        # 拉取依赖
flutter analyze        # 静态检查（须保持 0 issues，CI 硬性门槛）
flutter test           # 全量测试（当前 41 pass / 12 skip）
flutter build apk --debug   # 无签名 secrets 时的兜底构建
```

## CI（GitHub Actions）

- **Analyze & Test**：`flutter analyze` + `flutter test`（Flutter 3.47.7，与本机开发环境对齐）
- **Run TC-SIG-03**：Path C 支付降级专项用例
- **Build APK**：配置 `ANDROID_KEYSTORE_B64` / `KEYSTORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS` 四个 secrets 即构建签名 release，否则 debug 兜底

## 版本口径

- Flutter 3.47.7 / Dart 3.13.5（stable）
- web3dart ^2.7.3；qr_flutter 4.x（使用 `eyeStyle`/`dataModuleStyle` API）
- 派生路径（工程占位，非协议强制）：`m/44'/60'/0'/0/0`（BSC）、`m/44'/307'/0'/0/0`（原生明文）、`m/44'/307'/0'/1/0`（原生隐私）

## 目录要点

- `lib/core/` 密钥派生、RPC 客户端、二维码、安全存储等基础层
- `lib/features/` 支付、桥（铸造/赎回）、钱包状态
- `test/` TC 编号用例（含官方 Path C 向量测试）
- `docs/` 桥 API 契约、阻塞用例、Path C 规范等