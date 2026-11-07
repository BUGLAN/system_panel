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
- 字体在 `assets/fonts/`，以 `pubspec.yaml` 为准：ChakraPetch（显示/数字）、NotoSansSC 与 JetBrainsMono（可变字重，粗体用 `FontVariation('wght', N)`）等
- 入口 `lib/main.dart` 是应用主壳（状态机 `Moment` + 场景编排），界面在 `lib/ui/ref/`
- 动效参数以 `../AGENTS.md`「动效参数」一节为准（原样机 `prototype/motion-demo` 已移出 git，只在本机副本 / git 历史里），不许凭感觉改
- 视觉基准是仓库根目录的 `宿主养成系统_重设计.html` → `lib/design/ref.dart`；项目约定见 `../AGENTS.md`
