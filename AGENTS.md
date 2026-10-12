# AGENTS.md — 宿主 SYSTEM 项目指南

> 本文件供 AI Agent 阅读：任何 Agent 在本项目工作前必读。产品是"网文系统流自我提升 App"——用户是宿主，App 是毒舌但靠谱的系统。

## 仓库与运行（先看这里）

- **仓库根目录：`E:\repo\system_panel`**（git 仓库，主分支 master）。规则文档在 `docs/`，原型在 `prototype/`。
- **跑原型**：`cd prototype/opus-v2-dir && node server.mjs` → 打开 http://localhost:4925（**这就是宿主最终选定的那一版**：全息舞台 + 环套在她身上 + 桌面演示控制台）。端口 4925 硬编码在 `server.mjs`；Live2D 必须走 http，不能双击 `index.html`
  - `server.mjs` = 静态服务 + `/api/plan` LLM 代理（对接 DeepSeek，对应 `13-LLM拆解接入方案.txt`）
- **原型归档（2026-10-07）**：`prototype/` 下只留**中选**的 `opus-v2-dir` 与跨原型的真源/证据（`.stitch`、`motion-demo`、`references`、`screens`、`stitch-bridge`）。**另外 7 版历史原型（app / app2 / app-v2 / ink / opus-dir / opus-v1 / redesign-v6）已整体移动到 `E:\repo\archive\`**（不在本 git 仓库内），每个子目录自包含并各带 `README.md`，索引见 `E:\repo\archive\README.md`。下文提到的 `prototype/app/...` 路径**均指归档前的历史状态**，现在对应 `E:\repo\archive\app\`
- **动效样机**：`prototype/motion-demo/index.html`，同款静态服务挂 4920 端口即可
- **Stitch 相关**：`prototype/stitch-bridge/` 只保留 package.json 与提示词；`node_modules` 未入库，需要时 `npm install --registry=https://registry.npmjs.org`（npmmirror 不同步官方新包）
- **原型调试快捷方式**：⚠️ **v11 起等级徽章已从 HUD 删除，这条捷径当前没有宿主、暂时点不到**（宿主将另定位置）。`SYS.simTap()` / `SYS.simDay()` 两个函数与设置页说明文案都原样保留，接回新宿主只需给元素加 `onclick="SYS.simTap()"` + 一个 `dblclick` 绑定。历史：原为「点 HUD 右上角火焰」（火焰动画已删），后迁到「点左侧等级徽章」，现徽章也删了
- **火焰引擎（已退役 · v4）**：`prototype/app/index.html` 里的 `Fire` 对象仍是程序化多层火焰（贝塞尔火舌形变 + 湍流粒子精灵 + 白热内核 + 环境辉光 + 火星拖尾），但 HUD 的火种已删、`#fireCv` 不存在，`Fire.spawn/burst/extinguish` 一律提前返回（空转不报错）。代码留着是为了将来换形态回归；Flutter 侧**暂不移植**。**v11 起整个 HUD 行也已删除**：顶部只剩一条 4px 经验条（贴顶全宽）
- **场景化今日页（15 · v4 全息委托板）**：板上六空位=日上限，清晨钉单=发布仪式；按住拔单=接受（铆钉进度环）、横扫撕单=拒绝、轻点=详情；主线=板下缘独立卷轴、周挑战=金框角单；突发=飞刀钉单（红印"突"）；结算金币逐枚点收；传统列表已删除（板即唯一入口）。**v4 按宿主指定删除两个常驻组件**：柜台「任务袋」（#pouchDock/.counter）与角色左侧「台词区」（#saybox/sayLine）——进行中看被拔掉的那一格 + 顶部执行面板，已完成看主线时间轴的朱砂印；系统说话收敛到发布/结算/毒舌/追问四处
- **主线时间轴（17 · v5）**：主线页=左右交错时间轴（卡片 47% 宽，中央让给轴线），底栏顺序 主线/任务/面板/设置、默认首屏=主线；状态一律用样式表达（走过=实心发光轴+实色印章／脚下=呼吸节点+光晕／未走=虚线暗轨+线框印章），**禁止状态文字**；轴上任意节点可点，展开为自屏幕顶部垂下约 60% 屏高的**顶部面板**（弹簧下落），三态=执行中（实时计时+证据轴+快照记录/提交任务/认输）／已完成（只读回顾：时长/证据份数/结算数字，无按钮）／待执行（要求+验证方式+接任务，仅当前无执行中任务时给接任务）；执行面板证据轴=**紧凑书脊**（连续发光轴 + 节点分类型 开始/快照/记录/完成/认输 + 快照缩略图 + 时间右对齐）；主线页底部「立新目标/放弃主线」按钮已删，入口迁至设置页
- **V6 组件补完（顶部面板 + 面板页 · frontend-design）**：`prototype/app/index.html` 末尾的 `V6 · 冷光神殿 · 补完` 层。① 顶部面板=「从书脊垂下的一张委托单」：锚定行 `RING nn / NN` + 主公线名 → 稀有度压印（46px 双框）→ 点线规格表（验证／维度／回报／限时，**不再把标题重复成"要求"**）→ 5 个虚线证据槽 + 一句验收条款 → 脚部单一青 CTA【接任务】；三态共用同一外壳，脚部 `margin-top:auto` 吸底，执行/回顾态的证据轴 `flex:1` 吃满剩余高度。**v8 按宿主指定把待执行的「验证/维度/回报/限时」流水账改成战利品面板**：三格 loot（EXP 青 / 金币 金 / 维度用该环稀有度色，各带顶部发光条 + 字形 + 24px Rajdhani 数值），标签「报酬 · REWARD」下划线取稀有度色，三格 0/70/140ms 错峰 `lootin` 入场（reduced-motion 关闭）；校验信息降级为两行点线规格。**v4 按宿主指定删除底部「书脊定位」轨**（原 `.nsrail`），腾出的高度给证据轴。执行态动作区顺序=【快照记录】【认输】上行 + 【提交任务】通栏下行（宿主指定与认输对调）。② 面板页=宿主档案：**v9 按宿主指定重排头部**——上排「六边等级牌（`LV` 微标 + 大数字 + **沿六边轮廓走的经验环**，周长 186.4）＋金币紧贴其右，称号在右端」／中排「主线目标居中：`主线目标 · MAINLINE` + 目标名 + **N 段刻度轨**（走过=实心、脚下=亮框、未走=暗槽）」／下排「两格读数（完成 / 连击）各带一句下一步」；六边框必须用"外层青色渐变 + 内层 `inset:1.5px` 再裁六边"两层叠（`clip-path` 上写 `border` 只会剩左右两条竖边）→ 六维阵列（**v10 二次优化**：雷达 4 环 + 6 条轴 + 每轴 3 枚刻度；**顶点默认不画点**（只留多边形轮廓，悬浮该维才冒出一颗 r2.6 的点）、**无扫描扇面**；**刻度改平方根**（低值外扩，避免极端偏科变成"一根针"；图下一行小字注明）；**原先下方的 6 行条形/数值列表已删除**，数值改为**悬浮对应顶点或轴名时才在顶点旁显出**——`.axg` 分组 + `.axhit` 命中圈 + `.raxv` 带描边数字 + `<title>` 兜底触屏长按；主线主题轴改为**轴线本身加亮**，替掉原来的「主线」标）→ SYSTEM LOG 观测条 → 3 个装备槽（2 实 + 1 虚线空槽）→ 兑换台行（金币不足自动禁用）→ 封存档案。规格与验证留痕见 `prototype/references/v6-redesign.md`
- **V10 批次（六维换血 + 四处 UI · 宿主指定）**：① **六维换血**：体/智/专/心/交/生 → **力/敏/体/智/知/魅**（力量·体魄强度／敏捷·灵活性反应平衡／体质·健康耐力／智力·推理记忆／感知·洞察与精神坚韧／魅力·自信仪态吸引）。代码侧有 `ATTRS`、`ATTR_MAP`、`migrateAttrs`：**老存档自动搬家**（旧 体→力、生→体、智→智、专→知、心→敏、交→魅，取名取最大值防丢档），`REMEDIES`/`AI.clamp`/`genChain`/`SUDDENS`/默认 theme（`体`）全部跟随；文档 02/13 + Flutter `app/lib/main.dart`、`app/test/env_check_test.dart` 同步。② 顶部面板待执行态**删掉复述型文字**（头部不再挂 meta、验证值只留目标、"证据槽 · 提交任务时上传，最多 5 张"一行收尾、脚部只留「拔单即开始计时」）。③ 执行态面板与任务详情新增**【使用道具】**（在【提交任务】左边）：选择器由 `ITEMS` 表驱动（新增道具只加一行），使用后立刻扣道具并把效果挂到这张委托（`r.shield`／`r.dbl`），结算与判负优先读预置标记、没有则退回原来的自动消耗。④ 任务详情的「执行时间轴」**改用与别处同一套紧凑书脊**（`evlHtml`），不再手搓文字列表。⑤ 面板雷达**删扫描扇面**、**顶点默认不画点**、**数值不再常驻**（悬浮顶点/轴名才显，轴名带原生 `<title>`）、**刻度改平方根**、下方条形列表已删；装备槽／兑换台统一到战利品格（`.loot`/`.lt`）语言
- **V11 批次（设置页＝系统控制台 · 二级菜单 · 宿主指定）**：`#pg-set` 拆两层——① 一级「模块清单」`#setMenu`（`SETMENU` 表驱动：序号 + 青色图标框 + 名称/mono kicker + **当前值只读回显**，菜单本身就是仪表），顶部 `SYSTEM CONSOLE` 品牌块 + 一行实时读数（LV·连击·主线进度·道具数），底部 `#setState` 控制台状态条（存档 key/项数、角色模型来源、音效与语音状态、主线与周期）；② 二级「子面板」`#setPane` 从右侧滑入（`translateX(101%)→0`，根列表同步 `-17%` + 降不透明度做视差），表头常驻（返回键 + 分类 kicker/标题）+ 内容独立滚动；四个分类 `LLM 拆解 / 语音 TTS / 音效 / 系统`（`SETPANES` 表驱动，新增分类＝各加一项）。**全部控件沿用旧 ID 与 onclick**（`aiBase/aiKey/aiModel/saveAI`、`voiceBtn/voice`、`bgmBtn/bgm`、`sfxBtn/sfx`、`l2dUrl/saveL2D`、`newGoal/abandon/hardReset`），功能零改动；`UI.set()` 改成**逐元素判空**（控件只在子面板打开时存在），并刷新菜单摘要与开关文案；切底栏即时复位到一级。两处「活数据」彩蛋：语音 pane 的「语音 KEY」现读 `prototype/app/voice/README.txt`（改 README 即改界面），音效 pane 的「音效事件」现读 `SFX` 对象（新增音效自动出现）
- **V12 批次（HUD 精简 + 执行面板道具 + 结算改经验条上涨 · 宿主指定）**：① **HUD 行整体删除**——等级徽章（`#hLv`/`#hLvNum`）、金币计数器（`#hCoin`）连同 `.hud`/`.gem`/`.coins` 的 CSS 一起清掉，顶栏只剩一条 **4px 经验条**（`.expwrap` 贴顶全宽、无圆角、带辉光；两端被手机 34px 圆角自然裁切）；等级与金币改由「面板」页承载。② **顶距级联收紧 96 → 64px**：`.page` / `#pg-panel` / `.scene` / `.sud` / `#setRoot` / `#setPane` 六处一起改（漏一处就会有一条空带或元素贴条）。③ **任务页执行面板 `#execPanel` 补【使用道具】**：动作区变成 `[快照记录 solid][认输 danger]` + `[使用道具 ghost][提交任务 solid]`，与顶部面板同款，直接复用 `ITEMS` 表 + `#ov-item` + `SYS.itemPick(true)`。④ **结算删除「金币弧线飞入 HUD」，改为「经验条上涨」**：`coinFly()` 整段删除，金币改为 `S.coins+=coin` 直接入账（原来金币**只**在 coinFly 里累加，删它必须补记账）；新增 `expTo(v,ms)` 分段动画——不跨级 520ms 涨到位，跨级＝涨满 360ms → 白闪+升级动效 → 归零 → 再涨到余额 420ms，上涨期间叠一次性流光 `.expbar.rise`；`UI.hud(keepBar)` 支持结算期间把经验条让给动画独占。⑤ **动效真源同步**：`prototype/motion-demo/index.html` 的 `coinFly` 同样换成 `expRise`，其 HUD 道具也去掉了等级/金币；`docs/08`（结算逐帧）、`docs/09`（场景 9）、`docs/10`（常驻层）三处文档同步改写。⑥ **顺带修一个 v10 遗留崩溃**：`settle()` 里 `const crit` 之后又 `crit=true`（身上有双倍卡或预置 `q.dbl` 时必抛 `Assignment to constant variable`），已改为 `let crit`
- **V13 批次（主线页 / 任务页补入场动效 · 宿主指定「只加动效，不改现有 UI」）**：面板页与设置页本来就有入场（`.lt` 战利品格错峰 `lootin`、`.setrow` 错峰 `setin`），主线页与任务页切页签时是硬切。本轮给这两页补同一套语言：① **主线页**＝报头 `dropin` 360ms@0 → 时间轴节点逐环 `dropin` 440ms@`(i*55+70)ms`（spring 过冲；左卡 `--dx:-9px`、右卡 `+9px`，入场也走同一条书脊）；② **任务页**＝委托板 `bdin` 280ms@0 显影 → 板上单子逐张 `slipin` 450ms@`(i*55+150)ms` 落钉（保留各自 `--tilt`，落完不跳回 sway）→ 板下缘主线卷轴 `dropin` 420ms@470ms。实现＝CSS 层 `V13 · 页面入场动效` + `UI.enter(p)`/`UI.pinSlips()` 两个方法（`UI.tab()` 与 load / `OB.finish()` 收尾处各调一次）；**只挂一个 1.4s 入场窗口**（`.enter` 加前先摘 + 强制 reflow，窗口过完摘掉），`backwards` 填充保证末帧＝原样，因此不覆盖 `.scene.exec` 的暗场（板子/卷轴用 `#scene:not(.exec)` 守卫，执行态只留顶部提示行显影）、不覆盖 `.qmod.holding` 抓起态，落钉后把 sway 的 `animation-delay` 原样还回去；`prefers-reduced-motion` 下 JS 直接不挂 `.enter`。**验证**：4 个页面共 377 个元素的 computed style + 盒模型快照（关掉全部动画）前后 **0 行差异**、4 张定格截图**逐字节相同**（证据 `.verify/v15/`）；动效真源已同步 `prototype/motion-demo/index.html` 场景 ⑦⑧，`docs/09` 新增场景 19
- **V14 批次（四页顶距再收紧 64 → 20px · 宿主指定）**：v12 把 HUD 行删干净后，四页顶上仍留着 64px 空带（正是被删 HUD 占的位置、截图里看着像"删了进度条还剩一大片空白"），宿主指定四页整体上移。**同一个级联的六处常量一起改**：`.page` / `#pg-panel` / `.scene` / `.sud` / `#setRoot` / `#setPane` 全部 64 → 20px（`.scene` 写作 `inset:20px 0 58px`），四页内容整体上移 44px；**顶栏那条 4px 经验条保留不动**，各页自身内边距（`.tlhead` 14 / `.dshead` 12 / `.setbrand` 2）、`.page` 底距 78、`.scene` 底距 58、`.tabbar` 58 全部不变。落点（相对手机顶边）：主线报头 64→20、标题字 78→34；任务页提示行 70→26、板顶 86→42；面板页头 64→20、读数行 76→32；设置页品牌块 64→20；突发 `.sud` 64→20。**验证**：`.verify/v16/`（新会话名 `v16`，与并行会话的 `v15` 隔离）改前/改后逐元素快照比对——四页共 **326 个上移元素 top 恰好 −44px**、`left/width/height` 与全部计算样式**逐字段零差异**；例外全部可解释（`inset:0` 的页面/`#setRoot`/`#setPane` 容器自身 5 个、零盒与 `display:none` 子树及 SVG 元数据 45 个、flex 吃空间的 `#setPaneIn` 与 `.scene` 各 +44px 高、贴底角色层 `#l2dHost`/`.aura` 底边未动故不动 3 个），**未解释差异 0**；`64px` 全文零命中。文档同步 `docs/10` 加「▸ v6 修订」行
- **⚠️ 单文件原型的写入纪律**：`prototype/app/index.html` 是 2000+ 行单文件原型，**同时只允许一个 Agent 写它**。本仓库出现过两个会话并行改同一文件（一侧改面板头部 `.dsgoal`/`.dsid`/`pDoneNext`，另一侧改六维与顶部面板），`edit` 工具会以 `file changed since it was read` 报冲突。遇到该报错先轮询 `Get-FileHash` + `LastWriteTime` 确认是否有别的写入者，再决定避让或接手，**不要用脚本硬写覆盖对方改动**；本次改设置页前先探测 30s（哈希不变才动手）
- **Live2D 角色（14）**：脚本本地化在 `prototype/app/vendor/`（入库），模型本地化在 `prototype/app/live2d/`（gitignore，版权红线），默认 Hiyori，设置页可换 model3.json 地址；等待播"召唤阵"，失败降级全息剪影
- **TTS 语音钩子**：音频按 key 放 `prototype/app/voice/`（key 见该目录 README.txt），缺文件自动回退电子音垫音
- **品牌标识（23）**：LOGO＝「六边核心 + 经验弧」，唯一真源 `brand/build.mjs`（一条命令重生成全部 SVG 母版 + Android/iOS 图标 + 原型 favicon + 规格卡，产物入库）；**禁手改任何生成的 SVG/PNG**，要改就改参数重跑并同步 `docs/23`；细节与落点见 `brand/README.md`
- 未入库：`.env`（含 Stitch API Key）、`node_modules/`、`prototype/stitch-bridge/results/`

## 技术栈（已拍板，勿再摇摆）

- **Flutter 跨平台框架**（Dart），目标 iOS + Android 双端高效运行
- 选型理由：Impeller 渲染引擎对大量动画友好（着色器预编译、无 jank），单代码库双端，60/120fps 下动画再多也没问题
- 动画实现约定：优先 `Transform`/`Opacity`（对应 web 端 transform/opacity 铁律）；弹簧用 `SpringSimulation(stiffness: 100, damping: 20)`；数字滚动用 count-up 补间；禁用线性匀速
- 状态管理建议 Riverpod；动效库建议 flutter_animate + 自定义弹簧
- **本机 Flutter 工具链已就绪**：Flutter `3.47.6` stable（Dart 3.13.5）装在 `D:\flutter`（已加入用户 PATH），JDK 用 Android Studio 自带 JBR，Android SDK 在 `%LOCALAPPDATA%\Android\Sdk`，`flutter doctor` 全绿（Android 工具链 + Chrome + VS 生成工具，许可证已接受）
- **Flutter 工程在 `app/`**：`flutter create --org com.systempanel --project-name system_panel --platforms android,ios`；applicationId 与 iOS bundle id 均为 `com.systempanel.app`。跑：`cd app && flutter run`（Windows 用 Android 模拟器；iOS 模拟器在 Mac 上，见 `tools/setup-macos-ios.sh`）
- **全程国内源、不走代理（硬要求）**：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`（已写入用户环境变量）；Gradle 发行版走腾讯云镜像（`app/android/gradle/wrapper/gradle-wrapper.properties`），AGP/Kotlin 依赖走阿里云镜像（`app/android/settings.gradle.kts`、`app/android/build.gradle.kts`，官方源只作兜底）；字体素材取自 jsDelivr 的 `google/fonts`
- **iOS 测试路线**：本机只跑 Android 模拟器，iOS 模拟器在 Mac Air（配置脚本见上）；本机不接 Android 真机
- **Live2D 舞台几何（2026-10-11 宿主验收后定稿，勿回退）**：平台视图的**布局尺寸按"族"固定**（`Live2DStage.kViewFamilies = [1.05, 1.70]`，族内所有相机共用一块矩形），缩放/平移交给 `Transform.scale(cam.s / 族尺寸)` —— 逐帧改布局尺寸会让插件 iOS 侧 `layoutSubviews()` 每帧重建 FBO，推镜头那段她基本不渲染（观感＝"直接切过去"）。换景别走 `CamSpring.glideTo(..., ms: 1400)` 的 easeInOutCubic **慢推**（弹簧 0.5s 到位太快，配上亮帧就是硬切观感）。**`Opacity` 仍然禁套平台视图**（saveLayer），`Transform` 可以（Flutter 文档 + 真机实测）。细节：`app/STAGE-OPTIONS.md` 坑 4、`docs/18` §1.5.3
- **原生 Live2D 的 shader 打包（2026-10-12 定案，勿删）**：产品路线是**原生**（`main.dart` 只有这一条舞台路线；WebView 降级路线连同 `live2d_web.dart` / `WebStagePort` / `kNativeStage` 已于 2026-10-12 按宿主拍板**删除**，理由：那条路线在 App 里触摸是断的，而当初留它的归因已被推翻）。原生依赖 `app/android/app/build.gradle.kts` 里的 `syncLive2dShaders` 任务把 `flutter_live2d` 自带的 `Shaders/StandardES/*`（`#version 100`）同步进 APK 的 `assets/FrameworkShaders/` —— **插件自己不打包这些文件，漏了就不上屏，且每帧刷 `emuglGLESv2_enc ... GL error 0x501`**。旧文档曾把这个现象误判成「MuMu/旧 AVD 的 emugl 转译层与插件不兼容」，**结论已推翻**：同一台 MuMu 补齐 shader 后原生正常上屏、GL 报错归零、无 WebView 沙箱进程。排查全文 `docs/35-MuMu原生Live2D排查.md`，过程留痕与更正见 `app/STAGE-OPTIONS.md`「2026-10-12 复盘」节
- **输入态（`#ask` / 换目标）布局纪律**：主 Scaffold 必须 `resizeToAvoidBottomInset: false`（整屏随键盘缩 → 舞台矩形变 → 重建 FBO + 她与环场错位），输入框自己用 `AskField.bottomInset: MediaQuery.viewInsetsOf(context).bottom` 抬到键盘之上；「换目标」(`_goalChangeOn`) 时**主线全景（抬头/环挂签/底部两颗）整层退场**、字幕让到屏幕中段 —— 输入框/预设词不许和【让她派这一环】【换目标】或字幕重叠（宿主截图里的"UI 重合"）

## 已锁定的设计决策

- 主题色（已锁定，勿再改）：深蓝虚空 `#0A0E1A` + 电光青 `#38E1FF`（主强调）+ 稀有度色谱（F灰 `#9AA3B2` / E绿 `#4ADE80` / D蓝 `#38BDF8` / C紫 `#A78BFA` / B金 `#FBBF24` / A橙 `#FB923C` / S红 `#FF4D5E`）
- 字体：Rajdhani（标题/大数字）+ Noto Sans SC（中文正文）+ JetBrains Mono（等宽数值/系统日志）；禁止 Inter/衬线；数字禁止用正文字体
- 字体已落位 `app/assets/fonts/` 并在 `pubspec.yaml` 声明：Rajdhani 四档静态字重（400/500/600/700）；NotoSansSC 与 JetBrainsMono 是**可变字重字体**，粗体要在代码里写 `fontVariations: [FontVariation('wght', 700)]`，别只靠 `fontWeight`
- 视觉基准唯一来源：`.stitch/DESIGN.md`（GAME HUD EDITION v2）——玻璃面板、辉光、斜切角、网格+扫描线
- 产品机制唯一来源：`docs/` 下 `00~17` 编号规则文档（自然语言，一次定一事的工作方式，修改规则先改文档）

## 规则文档索引

| 文件 | 内容 |
|---|---|
| `00-核心规则.txt` | 宿主/系统关系、核心循环、任务只由系统发布 |
| `01-任务规则.txt` | 四种任务、F~S 难度、日上限 6、等级越高任务越多 |
| `02-面板与奖励规则.txt` | 单字六维（**力/敏/体/智/知/魅**，v4 换血：力量/敏捷/体质/智力/感知/魅力）、三种奖励、无血条 |
| `03-惩罚规则.txt` | 毒舌即惩罚、连击/称号/评价、永远有补救 |
| `04-验证规则.txt` | 截图统一验证（可多张+文本备注），信任不查岗 |
| `05-新手开局规则.txt` | 【v3 激活流】六幕绑定仪式（激活/指引三卡/四卡访谈/生成烟花）、开局三件套已删除、前 10 任务必胜 |
| `06-目标拆解规则.txt` | 一句话目标 → 5~8 环主线链、长期/短期轨道分离 |
| `07-文案规则.txt` | 毒舌但靠谱人格、四种固定语气（发布/结算/毒舌/追问） |
| `08-核心动效规则.txt` | 六大时刻逐帧编排 |
| `09-动效场景全集.txt` | 19 场景 S/A/B 分级 + ComfyUI 素材分工（19＝v13 主线/任务页入场） |
| `10-无处不在游戏化清单.txt` | 四层包裹（常驻/微交互/环境/声音）+ 主题色锁定；【v4】HUD 连击火种已删；【v5】顶栏只剩经验条（等级徽章与金币计数器已删） |
| `11-精力系统规则.txt` | 【已冻结 · v3】精力随执行流删除，仅存档；原文：每日精力 100、成本 F8~A100 |
| `12-毒舌升级规则.txt` | 连败计数三档毒舌（引用真实数据）、金牌豁免嘴不豁免记录 |
| `13-LLM拆解接入方案.txt` | 本地代理 /api/plan、OpenAI 兼容、客户端钳制、关键词模板兜底 |
| `14-系统形象与表演规则.txt` | 系统拟人化（全息系统体·冷感少女）、12 个表演预算、电子音节先行、Rive/Spine 路线 |
| `15-今日场景与手感规则.txt` | 今日页=全息委托板、三动词（拔单/撕单/轻点）、主线卷轴、金币拾取、声音震动全铺、TTS 接入约定；【v4】任务袋与台词区已删 |
| `16-执行与时间轴规则.txt` | v3 专注执行流：AI 访谈立主线、周期计划（任务数=天数-1）、唯一执行中、拔单=开始执行、证据时间轴、认输、连击新定义、精力删除 |
| `17-主线时间轴与执行轴规则.txt` | v5：主线=左右交错时间轴、状态零文字纯样式、节点点击=顶部面板三态（执行中/只读回顾/待执行）、证据轴=紧凑书脊、动作区与底栏顺序、默认首屏=主线 |
| `24-待机与动作表情绑定清单.md` | 待机动作 + 各指令的动作/表情绑定（宿主 2026-10-11 要求「动作与表情绑在一起」）：素材边界（18 动作组 × 32 表情，不可新增文件）、清单 A 待机池（带表情）/ B 19 个指令时刻 / C 闲置表情用途、红线、落地顺序 |
| `25-表情动作预设总表.md` | **预设 = 动作 × 表情**（宿主 2026-10-11 定义）：预设 47 条（命名组合，`PerfPresets`）、动作组 18、表情 32 的**总表**；含组合规则（新增预设=加一行）、调试台说明（设置页→表演调试台）、落点与校验 |

## 动效参数（样机 = 真机的唯一标准）

动效真源：`prototype/motion-demo/index.html`（纯 CSS/JS 手写，已在浏览器实测）。Flutter 移植时逐时刻对照此文件，参数不许凭感觉改：

- 弹簧：stiffness 100 / damping 20；过冲到 1.08 再回弹
- 亮帧：全屏白 16% 透明度脉冲 180ms，音效踩这一帧
- EXP count-up：800ms ease-out cubic；暴击：定格 200ms → CRIT 印章 scale 2.2→1 → 续滚双倍
- 经验条上涨（v11 取代"金币弧线飞入 HUD"）：不跨级＝520ms ease-out 从旧值涨到新值，期间条内一次性流光 0.55s + 条尾脉冲；跨级＝先涨满 360ms → 白闪 + 升级动效 → 归零 → 再涨到余额 420ms。金币不再有飞行动画，结算时直接入账，进账反馈由经验条 + 结算面板的金币芯片承担
- 结算总时长 ≤1.6s；升级 ≤2s（同日重复只播简版）；发布 ≤800ms
- 失败：更短更暗更安静（成功亮度的 1/3）；打字机节奏 **标准 34ms/字**（唯一真源 `AgentSettings.kPaceStandardMs`，设置页「对白节奏」另有 慢 42 / 快 24 两档；此处原先写的 30 是原型遗留、已按 R4 统一）
- 8-bit 音效用 Web Audio 合成的频率写在 demo 里，Flutter 侧走**离线烘焙的音效包**（`tools/audio/` → `app/assets/audio/`，84 件，`docs/22` 批次②）：播放总线在 `app/lib/state/sfx.dart`（池化、永不抛、开关真正生效）

## Stitch 生成管线（屏幕设计稿）

- 官方 CLI：`@google/stitch`（npm，Google LLC 出品）。注意 npmmirror 镜像不同步新包，安装需 `--registry=https://registry.npmjs.org`
- 认证：`STITCH_API_KEY` 环境变量（key 在 `prototype/stitch-bridge/.env`，已 gitignore，勿提交勿外传）
- 项目 ID：`9824844031085818014`（画布：https://stitch.withgoogle.com/projects/9824844031085818014）
- 设计系统 ID：v1=`5203883926288910671`（弃），v2 GAME HUD=`119134925411475183`
- 生成：`npx stitch generate screen --project <id> --device MOBILE --title <t> --prompt (Get-Content prompts\Sx.txt -Raw) --json`
- **已知坑：连续生成同类提示词时内容会串台**——必须用"SCREEN CONTENT LOCK"式提示词（见 `prompts/`），生成后必须 `stitch get screen` 核对 title
- 本地预览：`npx stitch serve -p <id> --port 8788`（被占会自动顺延，以输出 url 为准）
- v2 屏幕清单与正确 screen ID 见 `prototype/README.md`

## ComfyUI 素材管线（已落地首件：游戏背景）

- 端点 `127.0.0.1:8188`（本机 ComfyUI-aki-v2 已在线，RTX 5090 32G）；素材需求清单见 `09-动效场景全集.txt` 底部
- **工作流已落地 `tools/comfyui/`**：Qwen-Image 2.1 文生图 + 2x-AnimeSharpV4 放大——`qwen21-game-bg.workflow.json` 可直接拖进 ComfyUI GUI，`gen_game_bg.mjs` 一键重生成（`--seed` 抽卡），参数与坑见该目录 README
- 首件产出：游戏天幕背景 `prototype/opus-v2-dir/img/bg-void.jpg`（垫在 `#bg .sky` 底层，CSS 轨道环/地面网格/噪点等动态层继续叠加）；PNG 母版在 `ComfyUI/output/SystemBG/`
- 生图：辉光 burst、稀有度框、粒子 sprite、印章纹章、glitch 帧
- 生视频（img2vid）：结算光线 loop、升级光环、扫描线氛围、glitch 转场——压暗后 `<video>`/Video Widget 垫底层
- 优先级：纯 CSS/canvas（Flutter 端 CustomPainter）先行，AI 素材只做质感替换

## 工作约定

- 先文档后代码；规则改动先改编号 txt，代码跟随文档
- 每次只推进一件事，不超过 500 字的决策粒度
- **【宿主指定】不要参考、也不要在 `prototype/` 下的 HTML 原型上做验证或改动**：原型早已过时，只作历史参考；实现与验证都落在 Flutter 工程 `app/`。旧约定「动效/视觉改动必须先在样机验证手感，再移植 Flutter」**作废**
- **【宿主指定 · 2026-10-11】非必要不要自己测试，宿主就在屏幕前，他就是测试员**：
  - 改完直接交给宿主看，**不要**为了"验证"去跑模拟器 / 真机截图 / 连拍量像素 / 写临时探针 / 反复 build-install 那一套（这套在 2026-10-11 那轮耗掉了与写代码相当的时间，宿主明确定调：不值）。
  - 允许保留的只有**代码级**检查：`flutter analyze` + 与改动直接相关的 `flutter test`（秒级、不占宿主时间）。**不要**主动扩测、不要为"验证得彻底"额外加测试。
  - 宿主明确说"你去验/你测一下"时才走真机验证流程。
  - 需要宿主确认的验收点，**一次列清楚**（要做什么、看哪里、预期什么），别来回问。
- **【宿主指定 · 2026-10-11】只要这一轮改动了 `app/`，会话最后必须跑 `flutter run`（真机）**：让宿主拿起手机就能直接测。
  - 真机 UDID：`00008130-001169D830A1401C`（iPhone 15 Pro Max，宿主昵称 TK）；命令：`cd app && flutter run -d 00008130-001169D830A1401C`（默认 debug；要看动效手感用 `--profile`）。
  - iOS 14+ 的 debug 包**不能从桌面图标启动**（必须由 Flutter 工具链拉起），所以"最后跑一次 flutter run"是宿主能上手测的唯一路径。
  - 真机常走无线调试：掉线/`unavailable` 是常态，先 `xcrun devicectl list devices` 确认 `connected` 再跑；VM service 连不上不影响 App 运行，能跑就跑。
- **动作区用词固定**：【快照记录】【提交任务】【认输】（顶部面板与执行面板同款，勿再用旧黑话；改名对照见 17 号文档开头）
- `.env`、`results/`、`node_modules/` 永不入库
