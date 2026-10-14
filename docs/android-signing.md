# Android 签名配置

> 目标：让 `flutter build apk --release` 与 `flutter build appbundle --release`
> 使用正式 keystore 签名，避免 debug 签名包无法覆盖安装或上架被拒。
> 本工程为 Android 工程初始化必做项之一。

## 1. 一键生成 keystore（JKS）

在工程根目录执行（`android/` 同级）：

```bash
keytool -genkeypair -v \
  -keystore android/rcpu-release.jks \
  -alias rcpu \
  -keyalg RSA -keysize 2048 -validity 36500 \
  -storepass <你的存储密码> \
  -keypass <你的密钥密码> \
  -dname "CN=RCPU Wallet, OU=Mobile, O=RCPU, L=City, ST=State, C=CN"
```

生成结果：`android/rcpu-release.jks`。

> 安全红线：
> - keystore 文件与密码**禁止提交到版本库**（加入 .gitignore）。
> - 密码仅写入本机 `key.properties`（不入库），并建议在密码管理器留存备份。
> - 丢失 keystore 或密码 = 永远无法再发布同名应用的正式更新。

## 2. key.properties 模板

新建 `android/key.properties`（从 `android/key.properties.example` 复制后改密码）：

```properties
storePassword=<你的存储密码>
keyPassword=<你的密钥密码>
keyAlias=rcpu
storeFile=rcpu-release.jks
```

> 注意 `storeFile` 写相对路径 `rcpu-release.jks`（相对 `android/` 目录），
> 与下节 gradle 读取逻辑一致。

## 3. build.gradle 签名配置片段

在 `android/app/build.gradle.kts`（或 `.gradle`）的 `android {}` 块内增加：

```kotlin
import java.util.Properties
import java.io.FileInputStream

// 读取本地签名配置（不入库）
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // 其他 release 配置（minify 等）按需补充
        }
    }
}
```

如果工程为 Groovy 写法（`build.gradle`）：

```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

## 4. 验证签名

```bash
flutter build apk --release

# 查看 APK 签名信息（应与 keystore 别名一致）
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk
# 或
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## 5. 常见问题

| 问题 | 原因与处理 |
| --- | --- |
| `StoreFile found at path ... does not exist` | key.properties 的 storeFile 路径不对，确认相对 `android/` 目录 |
| Could not read key.properties | 文件不存在或格式错误；从 example 复制并填好密码 |
| 覆盖安装提示签名不一致 | 手机里装的是 debug 签名包；先卸载再装正式包 |
| Play 上架提示签名不符 | 首次上传 keystore 后**不可更换**；后续更新必须用同一 keystore |