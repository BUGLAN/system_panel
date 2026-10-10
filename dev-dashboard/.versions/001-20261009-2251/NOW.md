# 现在

## 时间线
- 2026-10-09 23:05 | 你拍了两件事：演出时长按「分段规格 + 跳过护栏」——不砍内容、靠点按跳过兑现「别拖」；她本人继续用 WebView，原生那套留着等真机试验 | 证据: prototype/motion-demo/index.html
- 2026-10-09 22:45 | 你自己改设置里那把钥匙，她当场就换脑子——不用再重启 App 才生效（之前「测试连接」通了、聊天还走旧钥匙） | 证据: app/lib/main.dart, app/lib/agent/settings_store.dart, app/test/chat_test.dart
- 2026-10-09 22:30 | 补三处最常撞上的手感：换单时稀有度往下滚一档看得见了、执行页进出不再啪一下硬切、认输后的记录和补救单收进一张带背板的卡（压在头发上看不清的老问题） | 证据: app/lib/widgets/plate.dart, app/lib/widgets/exec_panel.dart, app/lib/widgets/fail_layer.dart
- 2026-10-09 21:30 | 修掉「板上写的和结算给的不一样」：补救单在派单板少算了一半，同一张单三处数字现在逐字一致；顺手把升级经验的旧曲线删掉——档案页经验环从此不再常年在 1/5 处趴着 | 证据: app/lib/state/quest_flow.dart, app/lib/state/host_state.dart, app/lib/widgets/plate.dart, .verify/t24/README.md
- 2026-10-09 21:11 | 主线走到底不再熄火：第 3 环收尾时她当场让你立下一条，按你说的话重铸 5~8 环（认真用户终于有第二段路）；日常题面池也加厚了一层 | 证据: app/lib/state/goal_gen.dart, app/lib/state/quest_flow.dart, app/lib/main.dart
- 2026-10-09 21:47 | 上面三件事的截图与核对清单都留在 .verify/t24、t26 里，我也把项目现状、缺点与 32 项待办写成一份「现状汇总」备查 | 证据: .verify/t26/00-boot.png, docs/20-项目现状汇总.md
- 2026-10-09 15:02 | 写了一份「现状汇总」：把十条设计要求逐条对账、列出 32 项待办和先后顺序，其中两项（结算/发布演出要不要缩短）需要你先拍板 | 证据: docs/20-项目现状汇总.md
- 2026-10-09 14:29 | 她开始记账了：你完成了什么、哪一维涨了多少都入档，档案页多一张「近 7 天」回顾卡，看得见自己的曲线 | 证据: app/lib/widgets/stats_pane.dart, app/lib/state/quest_flow.dart
- 2026-10-09 14:29 | 「说一句她就动手」不再只是摆设：查进度、换任务、改计划、记事情都能真落地，不填钥匙也能点快捷钮 | 证据: app/lib/agent/context_adapter.dart, app/lib/chat/chat_service.dart
- 2026-10-09 13:33 | 修好「新用户第一次打开看到的是演示档」：真新档现在直落绑定仪式，空白宿主从头开始 | 证据: app/lib/main.dart, app/lib/state/quest_flow.dart
- 2026-10-09 05:43 | 修掉无档启动崩溃，外加终验翻出来的四个小问题（任务丢档、暴击率算重、启动脚本点错位置） | 证据: app/lib/state/quest_flow.dart, .verify/t16/06-wipe-onboard.png, app/REGRESSION.md
- 2026-10-09 04:22 | 派单板的报酬行切到新价目表，消掉一处「显示和结算对不上」（补救单那一支后来才发现漏了系数，见 21:30 那条） | 证据: app/lib/widgets/plate.dart
- 2026-10-09 04:15 | 奖励表按 F~S 重定，周期任务生成与绑定多幕都装配上；见面礼那张双倍卡有了正确语义 | 证据: app/lib/data/rewards.dart, app/lib/state/goal_gen.dart
- 2026-10-09 03:54 | 首页能跟她打字聊天了，聊过的话关掉 App 再开还在 | 证据: app/lib/chat/chat_panel.dart, app/lib/chat/chat_history.dart, .verify/t10/03-chat-open.png, .verify/t10/06-restart-history.png
- 2026-10-09 03:18 | 原生上屏这条路在模拟器上走到头：逐帧日志证明是模拟器的图形转译层每次都拒绝插件的提交（不是我们的代码），止损改走 WebView，原生实现整套留着，将来改一个常量就能翻回来 | 证据: app/STAGE-OPTIONS.md, app/lib/stage/stage_port.dart, .verify/t7/03-native-lobby.png, .verify/t7/07-final-lobby.png
- 2026-10-09 03:03 | 她真的出来了（那一版走的是 WebView 播放器）——从这一版起 App 里能看见她，不再只有一个全息剪影 | 证据: app/lib/stage/live2d_web.dart, .verify/t7/07-final-lobby.png
- 2026-10-09 02:32 | 她有了自己的人设、长期记忆和一件「听得懂人话的助手」外套；相机弹簧数学也从原型一并搬进来 | 证据: app/lib/agent/persona.dart, app/lib/agent/memory.dart, app/lib/agent/tools.dart, app/lib/stage/spring.dart
- 2026-10-09 02:32 | 修掉你点名的那次「提交任务卡死」：真凶是震屏层每次抖都把整棵子树重挂，印章一砸就从头重播；顺手把真实结算链路接上 | 证据: app/lib/widgets/fx_layer.dart, app/lib/state/quest_flow.dart, .verify/t2/06-result.png
- 2026-10-09 02:32 | 拍照打卡接上 AI 看图（配了钥匙才判），四情形都不挡你提交；设置页能填地址、钥匙、模型名并测连接 | 证据: app/lib/agent/llm_client.dart, app/lib/agent/vision.dart, app/lib/agent/settings_store.dart
- 2026-10-09 01:06 | 委托板的「换一个 / 等会儿」两个键不再是死的 | 证据: app/lib/widgets/plate.dart
- 2026-10-09 00:11 | 把 Live2D 的模型与播放器取消入库屏蔽（换机 clone 就能跑）；顺手放行本机网络、给天幕常驻渲染减负（模拟器实测稳在 60 帧） | 证据: app/android/app/src/main/res/xml/network_security_config.xml, app/lib/widgets/bg_layer.dart
- 2026-10-08 22:18 | 写了一份交接文档，把「她在 iOS 上怎么原生渲染」这件事交给下一手（含 9 个已排除的假设，省两轮瞎查） | 证据: HANDOFF-LIVE2D-IOS.md
- 2026-10-08 20:35 | 大厅相机标定到 scale 1.132，她占屏高 92%，和原型对齐 | 证据: app/lib/stage/camera.dart
- 2026-10-08 20:25 | 原生合成问题挖到底并结案：①搁置、②就位；结论与证据都留档，不再重复排查 | 证据: app/STAGE-OPTIONS.md
- 2026-10-08 19:57 | 她在 App 里第一次真的上屏了（路线②：WebView 播放器），层序完全正确 | 证据: app/lib/stage/live2d_web.dart, app/assets/stage/stage.js
- 2026-10-08 13:12 | 发现两处文档和代码对不上：AGENTS.md 说 docs/ 下有 00~17 规则文档、server.mjs 带 LLM 拆解代理，实际两个都没有 | 证据: AGENTS.md, prototype/opus-v2-dir/server.mjs
- 2026-10-08 13:12 | App 的环境自检测试改名了（env_check_test.dart → boot_and_tokens_test.dart），旧文件已经不在仓库里 | 证据: app/test/boot_and_tokens_test.dart
- 2026-10-08 13:10 | 仪表盘建立：从这一版开始，进度、功能状态和等你拍板的事都在这里看
- 2026-10-08 13:08 | App 里她的"说话"活了一半：嘴型跟着字走，SYSTEM 后面那排波形条也跳起来了（行为清单 C2/C4） | 证据: app/lib/state/voice.dart, app/lib/widgets/voice_bars.dart
- 2026-10-08 12:46 | App 现在知道自己离开了多久，回来她会拿这个说事（行为清单 A1/A5） | 证据: app/lib/state/away.dart
- 2026-10-08 12:13 | 修好"关掉 App 再打开就忘了你"：真机重启后存档还在（曾经卡了一整轮，真凶是我自己的冻结标志） | 证据: app/lib/state/save_file.dart
- 2026-10-08 08:11 | 三种"按住"做完了：指纹接单 0.9 秒、认输 1.2 秒、重置 2 秒，中途松手会退回 | 证据: app/lib/widgets/hold_button.dart
- 2026-10-08 07:34 | App 会自己走秒了：执行计时、换日、连击检查都在跑 | 证据: app/lib/state/app_clock.dart
- 2026-10-08 07:03 | 对白有了打字机手感（34ms/字，点一下跳过整句） | 证据: app/lib/widgets/type_text.dart
- 2026-10-08 07:03 | 把 App 和原型逐条对了一遍，列出 35 条行为缺口分 7 组，等你逐条给约束 | 证据: app/BEHAVIOR-GAPS.md
- 2026-10-08 06:42 | 亮帧、震屏、粒子层搬进 App | 证据: app/lib/widgets/fx_layer.dart, app/lib/widgets/fx_particles.dart
- 2026-10-08 06:42 | 调研"她本人怎么落地"的三条路，带证据，等你选 | 证据: app/STAGE-OPTIONS.md
- 2026-10-08 06:11 | 她身上那 8 个环搬进 App（相机数学 + 环 + 挂签 + 点环看要求） | 证据: app/lib/stage/ring_painter.dart, app/lib/widgets/ring_tag.dart
- 2026-10-08 03:29 | 绑定仪式进 App：终端式输入 + 横幅（六幕还差四幕） | 证据: app/lib/widgets/ask_field.dart, app/lib/widgets/banner.dart
- 2026-10-08 01:55 | 跟上你新换的天幕背景：虚空天幕素材入库，比对用的参考态改成可复现的 | 证据: prototype/opus-v2-dir/img/bg-void.jpg, tools/comfyui/README.md
- 2026-10-08 01:36 | 面板这条线收口：档案（六维雷达）、补给、系统三个子页都能打开 | 证据: app/lib/widgets/sheet.dart, app/lib/widgets/radar.dart
- 2026-10-08 00:21 | 失败/补救进 App；顺手修掉一个"隐形浮层偷点击"的 bug | 证据: app/lib/widgets/fail_layer.dart
- 2026-10-07 22:47 | 结算面板进 App（砸数字 + 印章 + 经验条） | 证据: app/lib/widgets/result_panel.dart
- 2026-10-07 22:11 | 执行面板进 App（计时 + 证据槽 + 道具 + 认输） | 证据: app/lib/widgets/exec_panel.dart
- 2026-10-07 21:52 | 派单板进 App（玻璃板 / 等级骰子 / 指纹） | 证据: app/lib/widgets/plate.dart
- 2026-10-07 21:28 | 大厅页进 App（顶栏 / 字幕 / 底栏） | 证据: app/lib/widgets/main_view.dart, app/lib/widgets/dock.dart
- 2026-10-07 20:33 | 移植第一步：天幕层与开机自检屏 | 证据: app/lib/screens/boot_screen.dart
- 2026-10-07 20:07 | 界面原型完成并定稿：7 版历史原型整体归档，只留中选的这一版 | 证据: prototype/README.md

## 决策

### D1 她本人（Live2D 角色）就这么定了吗？
- 状态: 已定 A
- 说明: 2026-10-09 拍板——继续用 WebView 播放器，原生实现整套留着（翻回 = 改一个常量），等有真机时做一次试验再决定去留
- C: 就用现在的 WebView 播放器——已经在跑、和原型像素级一致；代价是多一个 225MB 的沙箱进程、模拟器上舞台只有约 11 帧
- A: 原生实现整套留着，等有真机时试一次再决定——模拟器上原生渲染是被图形转译层挡住的（不是代码问题），真机 GPU 下有可能翻回来
- B: 现在就宣布原生这条路关掉，删掉保底的翻回开关——少一处要维护的分支，代价是万一插件或环境变好也没法白捡

### D2 目标拆解要不要接真 LLM？
- 状态: 待拍板
- A: 先不接——现在的本地关键词模板够用，随时能跑、不花钱、不怕断网（AGENTS.md 里写的 /api/plan 代理在代码里其实不存在）
- B: 接一个本地代理走真模型——拆出来的环更贴你的目标，但要多维护一条服务，还要处理失败兜底

### D3 声音怎么做？
- 状态: 待拍板
- A: 照搬原型的现场合成（Web Audio 那套）——零素材、和原型完全一致，手机上要确认延迟
- B: 预生成一套音效包——手机上更稳，但要多一道出素材的工序

### D4 对白节奏照搬还是调快？
- 状态: 待拍板
- A: 照搬原型（34ms/字，soft 42ms/字，标点额外停顿，点一下跳过整句）
- B: 调快一档（比如 24ms/字）——老玩家不用等，但少了那股系统腔的压迫感

### D5 规则文档（00~17）怎么办？
- 状态: 已定 B、C
- 说明: 事实结案——00~17 确认不在仓库里，`docs/` 现在有新写的 18（施工方案）、19（产品分析）、20（现状与 32 项待办）；机制以代码 + 原型为真源
- A: 你手上有备份，放回 docs/——规则文档是产品机制的唯一来源，代码跟随文档
- B: 从现有代码 + AGENTS.md 反推重建一套——能自洽，但等于把"文档先行"改成"代码为准"
- C: 确认不再需要，同时清掉 AGENTS.md 里对 docs/ 的引用——最省事，但以后改规则没有单一来源

### D6 结算/发布演出时长：按哪一份规格？
- 状态: 已定 A
- 说明: 2026-10-09 拍板——改文档、以原型为真源，并升级为「分段规格 + 跳过护栏」：首拍仍限时（结算首帧 ≤1.6s／发布落板 ≤1.2s），全演出给到 4s／3.5s，同日第二单起自动快进、点任意处跳过。施工清单：改 AGENTS.md 动效参数表那一行 + 实现「点按跳过／同日快进」
- A: 改文档、以原型为真源，但加两件护栏——首拍仍限时（结算首帧 ≤1.6s / 发布落板 ≤1.2s）、全演出给到 4s / 3.5s，同日第二单起自动快进、点任意处跳过
- B: 坚持旧的硬规格（结算 ≤1.6s、发布 ≤800ms），按「保形状缩时长」逐拍等比压——与「原型即规格」的宪法条款冲突，要同步改 AGENTS.md
- C: 维持现状（忠实复刻原型 ≈3.85s / ≈3.3s），只补「点按跳过」——不动规格也不动手感

## 待办
- [x] 拍板 D6（演出时长）→ 选 A：改文档以原型为真源 + 分段规格 + 跳过护栏
- [x] 拍板 D1（她本人）→ 选 A：WebView 就这么用，原生实现留着等真机
- [ ] 按 D6 的裁决开工：改 AGENTS.md 动效参数表那一行 + 实现「点按跳过／同日第二单快进」
- [ ] 拍板 D2（目标拆解要不要接真 LLM）
- [ ] 拍板 D3（声音用现场合成还是预生成素材）
- [ ] 拍板 D4（对白节奏照搬还是调快）
- [ ] 收尾 D5：AGENTS.md 里那七份不存在的规则文档索引要不要清掉
- [ ] 还差一件结构性缺口：到点提醒（她不会主动找你，连击没有保卫战）
- [ ] 决定存档要不要接云端同步 / 至少加个导出（现在只在这台设备上）
- [ ] 试用「和小祥聊天」「近 7 天回顾」「第二目标闭环」——觉得对就说一句"我验证过了"，你不说，我最多只能标到「可用」
- [ ] 拿真机装一次 App，确认"关掉再打开还记得你"
- [ ] 真机到手时一次跑完三件：键盘避让、WebView 舞台真机帧率、Live2D 原生翻回试验（D1 选的 A 靠这次收尾）
