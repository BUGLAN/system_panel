# app/ — 宿主 SYSTEM Flutter 客户端

Flutter `3.47.6` stable / Dart `3.13.5`，目标平台 **Android + iOS**（Windows 本机只跑 Android 模拟器，iOS 模拟器在 Mac 上）。

## 跑起来

```powershell
cd app
flutter run                 # 自动挑设备；Android 模拟器用 flutter emulators --launch <id>
flutter run -d emulator-5554
flutter analyze
flutter test
flutter build apk --debug
```

> 首次在 Android 上构建会下载 Gradle 发行版与依赖，全部走国内镜像（见下），**不需要开代理**。

## 国内源配置（本项目已内置，勿改回官方源）

| 链路 | 源 | 位置 |
|---|---|---|
| pub 包 | `https://pub.flutter-io.cn` | 用户环境变量 `PUB_HOSTED_URL` |
| Flutter 引擎/产物 | `https://storage.flutter-io.cn` | 用户环境变量 `FLUTTER_STORAGE_BASE_URL` |
| Gradle 发行版 | `https://mirrors.cloud.tencent.com/gradle/` | `android/gradle/wrapper/gradle-wrapper.properties` |
| AGP / Kotlin 等依赖 | `https://maven.aliyun.com/repository/{google,public,gradle-plugin}` | `android/settings.gradle.kts`、`android/build.gradle.kts`（官方源保留作兜底） |

## 工程约定

- 包名 / bundle id：`com.systempanel.app`（Android `namespace` + `applicationId`，iOS `PRODUCT_BUNDLE_IDENTIFIER`）——这是占位 ID，上架前需换成自有域名
- 字体三件套在 `assets/fonts/`：Rajdhani（四档静态）、NotoSansSC 与 JetBrainsMono（可变字重，粗体用 `FontVariation('wght', N)`）
- 入口 `lib/main.dart` 目前是**环境自检页**：三套字体各渲染一行，真机/模拟器上肉眼确认素材管线就绪
- 动效参数真源是 `../prototype/motion-demo/index.html`，移植时逐时刻对照，不许凭感觉改
- 视觉基准唯一来源是 `../.stitch/DESIGN.md`，规则文档在 `../docs/`
