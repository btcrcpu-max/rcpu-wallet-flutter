# 平台权限配置（工程初始化必做）

> 由 `flutter create` 生成平台目录后，按下述修改。
> 涉及：摄像头（扫码）、生物识别（指纹 / Face ID）、minSdk 21+。

## Android

### 1) minSdk 21+

`android/app/build.gradle.kts`（或 `.gradle`）：

```kotlin
android {
    defaultConfig {
        minSdk = 21   // mobile_scanner 要求 >= 21
        // targetSdk 保持 34+
    }
}
```

### 2) AndroidManifest.xml 权限

`android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 内增加：

```xml
<!-- 扫码（mobile_scanner / CameraX） -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- 生物识别（local_auth：指纹 / 面部） -->
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission
    android:name="android.permission.USE_FINGERPRINT"
    android:maxSdkVersion="28" />

<!-- 部分设备扫码横屏/可带入方向信息用，可选 -->
<uses-feature android:name="android.hardware.camera" android:required="false" />
```

`<application>` 内可选声明（多次启动扫描更稳）：

```xml
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
```

## iOS

### Info.plist 声明

`ios/Runner/Info.plist` 增加：

```xml
<key>NSCameraUsageDescription</key>
<string>用于扫描 rcpu: 收款码完成付款</string>

<key>NSFaceIDUsageDescription</key>
<string>用于指纹 / Face ID 解锁与交易确认</string>
```

> 注意：
> - 缺少 `NSFaceIDUsageDescription` 时，local_auth 在带 Face ID 的设备上会直接抛
>   `PlatformException(LAErrorDomain, ...)`，权限文案必须声明。
> - 模拟器无生物特征时，`BiometricAuth.hasEnrolledBiometrics()` 返回 false，
>   页面需有密码兜底路径（助记词 + PIN 二选一解锁）。

## 权限失效排查速查

| 问题 | 排查点 |
| --- | --- |
| 扫码黑屏 / 权限弹窗不出现 | AndroidManifest 未加 `CAMERA`；或 minSdk < 21 |
| local_auth 报 `NotEnrolled` | 设备未录入指纹；先引导用户录指纹 |
| iOS 弹窗后崩溃 | 未加 `NSFaceIDUsageDescription` |
| 打包后权限被裁剪 | release 混淆规则未保留 local_auth 平台channel，检查 proguard 配置 |