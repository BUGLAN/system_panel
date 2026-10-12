# 35 · MuMu 原生 Live2D 排查（结论：能跑，之前是我们自己的问题）

> 状态：**已结论 · 已修复 · 已在 MuMu 实测验证**（2026-10-12）
> 影响面：推翻 `app/STAGE-OPTIONS.md`「MuMu · 原生舞台复验（2026-10-09）」的止损结论，
> 以及由它派生的「模拟器 emugl 转译层与插件不兼容」这一说法。

## 0 · 一句话结论

**MuMu 模拟器完全可以用原生 Live2D。** 之前上不了屏不是模拟器的问题，是
**我们的构建没把 Live2D 的 shader 打进 APK** —— 症状（每帧 `GL error 0x501`）
看起来像驱动不兼容，实际是「用了无效的 shader program」。

## 1 · 排查起点

- 用户当时跑的是 WebView 路线（原型播放器），不是原生。
- MuMu 实例 4（`system_panel`），`adb connect 127.0.0.1:16512`，Android 12 / x86_64。
- 仓库里 `kNativeStage` 已是 `true`（iOS 真机轮翻回来的），所以**只要在 MuMu 上装
  一个真机跑过的包，就必然走原生** —— 复现不需要改代码。

## 2 · 复现（修复前）

原样构建 Android x64 debug 包并覆盖安装（不清用户数据），冷启动：

- logcat 立刻刷满 `emuglGLESv2_enc ... s_glVertexAttribPointer / s_glEnableVertexAttribArray
  → GL error 0x501 (GL_INVALID_VALUE)`，每帧两组、无休止。
- 角色不上屏。

这与 2026-10-09 记录的现象一致，也就是说：**那次的现场被 1:1 复现了**，
可以拿它当对照基准。

## 3 · 根因链（逐环有证据）

| 环 | 事实 | 证据位置 |
|---|---|---|
| ① 插件不打包 Android shader 资产 | `flutter_live2d` 1.0.2 的 shader 源码只在 `src/main/cpp/.../Shaders/StandardES/`，**没有 `android/src/main/assets`，构建里也没有拷贝任务** | 修复前 APK 内 `.vert/.frag` 只有 Flutter 自带的 `ink_sparkle.frag`、`stretch_effect.frag` |
| ② 原生加载器只从 APK 资产读 shader | 相对路径 → `assets/FrameworkShaders/<name>`；读不到**静默返回空**（`*outSize=0; return nullptr`） | `Live2DPal::LoadFileAsBytes` 相对路径分支 |
| ③ 加载失败 → program = 0，且无人检查 | `LoadShaderProgramFromFile` 失败 `return 0`；后续照常 `glGetAttribLocation` 并直接把结果用于 attrib 调用 | `CubismShader_OpenGLES2.cpp`（成员查询/属性设置两处） |
| ④ 于是每帧 GL_INVALID_VALUE | program 无效 → location 查询返回负值 → 转成无符号索引越界 → `glEnableVertexAttribArray` / `glVertexAttribPointer` 报 0x501 | 与 logcat 报错的两条调用**逐条对应** |
| ⑤ 当时为什么没查出来 | 插件把 SDK 日志回调设成**空函数**，shader 加载/编译/链接失败一条日志都不打；`loadModel` 只看模型配置解析成功，**不校验 shader** | `live2d_flutter.cpp` 的 `LogFunction` 空实现、`Live2DModel::IsLoaded` |

**关键判据：真机（iOS）能跑不是因为"不是模拟器"，而是因为 iOS 侧用 `.metal` 内嵌着色器，
根本不读这套 APK shader 资产。** 把「Android 专用资产缺失」误读成了「Android GPU 栈不行」。

## 4 · 修复

`app/android/app/build.gradle.kts` 新增 `syncLive2dShaders`：

- 从**插件自带的** `Shaders/StandardES/*.vert|*.frag` 同步到生成 assets 的
  `FrameworkShaders/`（运行期加载器要的就是这个扁平路径）；
- 挂进 `preBuild`，`check()` 必需文件存在 —— 将来依赖变更导致漏包会**构建期报错**，
  而不是再次变成「静默黑屏 + GL 报错」；
- 选 `StandardES`（`#version 100`）而不是桌面 `Standard`（`#version 120`），
  与插件 ES2 上下文匹配；
- **文件不入库**：仍放在 pub 依赖缓存里（版权红线同模型数据）。

## 5 · 验证（同一台 MuMu，修复前后对照）

| 检查项 | 修复前 | 修复后 |
|---|---|---|
| 渲染路径 | 原生（但不上屏） | `[stage] 原生舞台就绪（flutter_live2d）` |
| 角色是否上屏 | ❌ | ✅ 开机睡姿 → 唤醒睁眼 → 大厅待机，UI 正确压在她之上 |
| `emuglGLESv2_enc` 报错条数 | 每帧刷屏 | **0** |
| WebView 舞台痕迹 | 之前跑的是 `[stage-web]` | logcat 无 `[stage-web]`；进程表无本 App 的 WebView 沙箱进程 |
| 是否真的在动 | — | 相隔 3s 两张截图差异像素 **254754**（呼吸/眨眼在跑，不是定格） |
| 打包 | debug/release 都缺 shader | debug 与 release **各 36 个** `assets/FrameworkShaders/` 条目 |

证据留档：`.verify/native-mumu/`（不入库）。

## 6 · 复现方式（给下一次）

```bash
adb connect 127.0.0.1:16512
cd app && flutter run -d 127.0.0.1:16512     # 或 flutter build apk --debug --target-platform android-x64
```

判据三连：`[stage] 原生舞台就绪` + 截图有她 + `adb logcat | grep -c emuglGLESv2_enc` 为 0。

## 7 · 遗留与提醒

- `loadModel` 首次偶发 `false`、第二次 `true`（插件自带竞态，已有重试兜住）——与本次无关。
- 旧记录里「裸舞台探针（`kStageBareProbe`）在 MuMu 上崩进程」**也是缺 shader 的构建**，
  不能继续当作「插件与模拟器不兼容」的证据；如需再引用请重测。
- `flutter_live2d` 需要跟进：① 上游把 shader 资产补上（则本仓库的同步任务可删）；
  ② KGP 迁移（Flutter 后续版本会硬性要求）。
- Android **真机**此前从未验证过原生路线。本修复对真机同样有效（缺的是 ABI 无关的资产），
  但**尚未在 Android 真机上实测**，别把模拟器结论直接当 Android 真机结论。
