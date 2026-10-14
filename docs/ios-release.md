# iOS 真机调试到 IPA 发布流程

> 前置：macOS + Xcode（建议 15+）+ 已安装 Flutter（3.24+）并 `flutter doctor` 通过。
> 本工程使用 `local_auth`（Face ID）与 `mobile_scanner`（摄像头），
> Info.plist 权限声明见 `docs/platform-config.md`，缺失会导致运行期崩溃。

## 1. 证书与 Provisioning Profile 配置（Apple Developer 后台）

1. 登录 https://developer.apple.com/account → Certificates, Identifiers & Profiles。
2. 注册 App ID（Identifiers → +）：Bundle ID 与工程 `ios/Runner.xcodeproj` 中一致（如 `com.rcpu.wallet`），勾选 Capabilities：Face ID（Sign In with Apple 不需要）与 Push Notifications（若启用推送）。
3. 创建开发证书：Certificates → + → Apple Development，用 Mac 钥匙串生成的 CSR 申请，下载 `.cer` 双击导入钥匙串。
4. 注册真机：Devices → + 填入 iPhone UDID（可先用 Xcode 连接设备后从 Window → Devices and Simulators 复制）。
5. 创建开发 Profile：Profiles → + → iOS App Development → 选择 App ID 与设备 → 命名并下载，双击导入 Xcode。

## 2. 工程内配置（Xcode）

```bash
open ios/Runner.xcworkspace
```

- TARGETS → Runner → Signing & Capabilities：
  - 勾选 Automatically manage signing，Team 选择你的开发者账号；
  - Bundle Identifier 与后台 App ID 完全一致；
  - 确认 Development Team 已选，Xcode 自动生成 Provisioning Profile。
- Info.plist 确认已含（见 platform-config.md）：

```xml
<key>NSCameraUsageDescription</key>
<string>用于扫描 rcpu: 收款码完成付款</string>
<key>NSFaceIDUsageDescription</key>
<string>用于指纹 / Face ID 解锁与交易确认</string>
```

## 3. flutter run 真机调试

```bash
# 用 Lightning 连接 iPhone，首次信任电脑（手机上点"信任"）
flutter devices          # 应列出你的 iPhone

flutter run -d <设备ID>  # 热重载调试；--release 出接近正式包
```

- 首次运行提示 Developer Mode：iPhone 到 设置 → 隐私与安全性 → 开发者模式 → 开启。
- 证书未信任提示：设置 → 通用 → VPN 与设备管理 → 信任开发者应用。

## 4. Archive 导出 IPA（发布用）

```bash
flutter build ios --release
```

然后：

1. Xcode 打开 `ios/Runner.xcworkspace`；
2. 选择 Any iOS Device (arm64) 作为目标设备；
3. Product → Archive，等待归档完成；
4. Window → Organizer → 选择本次 Archive → Distribute App：
   - App Store Connect：需先创建发布证书（Apple Distribution）与 App Store Profile；
   - Ad Hoc / Development：指定设备清单导出，用于内测安装；
   - Enterprise：企业证书（本工程不用）。
5. 导出 IPA 后可用 `sideloadly` / Apple Configurator 安装到真机，或上传 App Store Connect（Transporter）。

## 5. 常见问题

| 问题 | 原因与处理 |
| --- | --- |
| 真机列表为空 | 检查 `flutter devices`；iPhone 需解锁并信任电脑 |
| 证书/Profile 不匹配 | Bundle ID 与 App ID 必须一致；Team 一致 |
| 安装后点击闪退 | 大概率 Info.plist 缺 Face ID/相机用途声明，补上重装 |
| Archive 时报 profile 失效 | Apple Developer 后台重建 Profile，Xcode 刷新 |
| 模拟器无 Face ID 报 PlatformException | local_auth 需真机；模拟器走密码兜底路径 |