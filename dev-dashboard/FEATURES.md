# 功能地图

<!-- 状态纪律：AI 最多标到「可用」；「已验证」只能由你亲手试用后盖章。 -->
<!-- 用词：这个文件就是「开发仪表盘」，别写成看板/dashboard。 -->

## 功能: 浏览器原型（她住的那一版）
- 状态: 可用
- 简介: 一个能打开、能点、能看完所有时刻的手机原型，一轮流程完整。
- 证据: prototype/opus-v2-dir/index.html, prototype/opus-v2-dir/README.md, prototype/opus-v2-dir/server.mjs, prototype/opus-v2-dir/js/main.js

## 功能: 开机自检与唤醒
- 状态: 可用
- 简介: 打开先看日志一行行滚，碰一下屏幕她才睁眼，第一句是「……就你？」
- 证据: app/lib/screens/boot_screen.dart, app/lib/main.dart, prototype/opus-v2-dir/index.html

## 功能: 大厅与常驻层（顶栏 · 字幕 · 底栏）
- 状态: 可用
- 简介: 她永远在屏幕中间；顶栏是经验条，底栏是委托/主线/面板/设置。
- 证据: app/lib/widgets/hud.dart, app/lib/widgets/dock.dart, app/lib/widgets/bg_layer.dart, app/lib/widgets/sys_icons.dart, app/lib/widgets/exec_pill.dart, app/lib/widgets/press_scale.dart

## 功能: 对白与选项
- 状态: 可用
- 简介: 她说、你按钮回答；台词逐字显形（34ms/字），点一下跳过整句。
- 证据: app/lib/widgets/choices.dart, app/lib/widgets/line_layer.dart, app/lib/widgets/type_text.dart, app/lib/data/content.dart

## 功能: 绑定仪式与卡片式访谈
- 状态: 可用
- 简介: 报名、立目标、卡片访谈、当场拆成环、送见面礼；真新档能从头走通。
- 证据: app/lib/widgets/ask_field.dart, app/lib/widgets/banner.dart, app/lib/widgets/interview_deck.dart, prototype/opus-v2-dir/js/flows.js
- 依赖: 目标拆解成主线

## 功能: 目标拆解成主线
- 状态: 可用
- 简介: 一句话目标当场拆成 5~8 环；说得太虚会被她驳回重说。
- 证据: prototype/opus-v2-dir/js/store.js, prototype/opus-v2-dir/js/content.js, app/lib/state/goal.dart

## 功能: 第二目标闭环（主线走完后还能接着走）
- 状态: 可用
- 简介: 主线走到底不再熄火：她当场让你立下一条，按你说的话重铸 5~8 环。
- 证据: app/lib/state/goal_gen.dart, app/lib/state/quest_flow.dart, app/lib/main.dart

## 功能: 日常任务生成
- 状态: 可用
- 简介: 每天按目标出 1~2 单，隔夜作废、主线重钉，题面池比原来厚一截。
- 证据: app/lib/state/goal_gen.dart, app/lib/state/quest_flow.dart

## 功能: 派单板
- 状态: 可用
- 简介: 玻璃板砸落、骰子滚出稀有度、激光逐字刻上去，报酬与结算同一个数。
- 证据: app/lib/widgets/plate.dart, app/lib/widgets/plate_timeline.dart, app/lib/data/rarity.dart, prototype/opus-v2-dir/js/ui.js

## 功能: 按住指纹接单
- 状态: 可用
- 简介: 手指按住指纹 0.9 秒才算接单，中途松手会退回并被抓包。
- 证据: app/lib/widgets/hold_button.dart

## 功能: 执行与证据
- 状态: 可用
- 简介: 计时、最多交 3 张截图、每张当场判定「已校验/存疑」、暴击率联动、按住认输。
- 证据: app/lib/widgets/exec_panel.dart, app/lib/state/quest.dart, app/lib/data/items.dart

## 功能: 结算与战报
- 状态: 可用
- 简介: 砸数字、盖暴击印章、经验条上涨、出一张能存下来的战报。
- 证据: app/lib/widgets/result_panel.dart, app/lib/state/result.dart, app/lib/widgets/settle_timeline.dart

## 功能: 失败与补救
- 状态: 可用
- 简介: 画面变暗变安静、字幕更短；补救单带背板摆在板上，一眼看得清。
- 证据: app/lib/widgets/fail_layer.dart
- 依赖: 派单板

## 功能: 奖励与等级（她那本账）
- 状态: 可用
- 简介: F~S 各有价码，暴击翻倍、道具再翻、补救减半；全 App 只认这一本账。
- 证据: app/lib/data/rewards.dart, app/lib/state/quest_flow.dart, app/lib/state/host_state.dart, app/test/plate_test.dart

## 功能: 主线环（围在她身上的那一圈圈）
- 状态: 可用
- 简介: 从脚下到头顶的环：走过亮起、脚下在走、没到是虚线，点环看要求。
- 证据: app/lib/stage/ring_painter.dart, app/lib/stage/camera.dart, app/lib/widgets/ring_tag.dart, app/lib/widgets/ring_labels.dart, app/lib/widgets/main_view.dart
- 依赖: 目标拆解成主线

## 功能: 面板 · 档案
- 状态: 可用
- 简介: 六维雷达、称号、装备槽、战绩，一眼看出自己长成什么样。
- 证据: app/lib/widgets/sheet.dart, app/lib/widgets/radar.dart, app/lib/data/attrs.dart, app/lib/data/titles.dart

## 功能: 面板 · 数据回顾（近 7 天）
- 状态: 可用
- 简介: 本周完成率、六维涨了多少、最近几单战绩，成长看得见曲线。
- 证据: app/lib/widgets/stats_pane.dart, app/lib/state/quest_flow.dart, app/lib/widgets/sheet.dart

## 功能: 面板 · 补给
- 状态: 可用
- 简介: 四种道具，金币的去处；买完当场扣钱、当场能用。
- 证据: app/lib/data/items.dart, app/lib/widgets/sheet.dart, app/lib/widgets/item_drawer.dart

## 功能: 和小祥聊天（会记事的对话）
- 状态: 可用
- 简介: 首页直接跟她打字说话，她记得你之前说的，还能替你查状态、换任务。
- 证据: app/lib/chat/chat_panel.dart, app/lib/chat/chat_service.dart, app/lib/chat/chat_history.dart, app/lib/widgets/chat_bar.dart, app/lib/agent/persona.dart, app/lib/agent/memory.dart
- 依赖: 系统设置

## 功能: 对话即操作（她自己动手）
- 状态: 可用
- 简介: 说一句就能查进度、换任务、调计划、记事情；不用她也能点快捷钮。
- 证据: app/lib/agent/tools.dart, app/lib/agent/context_adapter.dart, app/lib/agent/copy.dart

## 功能: 拍照打卡与 AI 看图判定
- 状态: 可用
- 简介: 交的照片她真会看一眼判「像不像」，判不了也照收，绝不卡住你提交。
- 证据: app/lib/agent/vision.dart, app/lib/agent/llm_client.dart, app/lib/agent/llm_gateway.dart, app/lib/agent/settings_store.dart

## 功能: 系统设置
- 状态: 可用
- 简介: 音效、她的声音、震动、全息描边、重填 LLM 与模型地址；改完立刻生效。
- 证据: app/lib/state/settings.dart, app/lib/agent/settings_store.dart, app/lib/widgets/sheet.dart

## 功能: 她本人（Live2D 角色）
- 状态: 可用
- 简介: 会看你、会眨眼、戳她会炸毛；原生渲染在模拟器上不了屏，现走 WebView。
- 证据: app/STAGE-OPTIONS.md, app/lib/stage/live2d_web.dart, app/lib/stage/live2d_stage.dart, app/lib/stage/stage_port.dart, app/lib/stage/spring.dart, app/assets/stage/stage.html, app/assets/stage/stage.js, prototype/opus-v2-dir/js/stage.js
- 依赖: 大厅与常驻层（顶栏 · 字幕 · 底栏）

## 功能: 存档（记得你是谁）
- 状态: 可用
- 简介: 关掉再打开还在，老存档自动搬家；重启后主线仍显示你的目标。
- 证据: app/lib/state/save_file.dart, app/lib/state/host_state.dart

## 功能: 她的时间感
- 状态: 可用
- 简介: 每秒走一次：执行计时、换日、连击检查，还记得你离开多久。
- 证据: app/lib/state/app_clock.dart, app/lib/state/away.dart, prototype/opus-v2-dir/js/util.js

## 功能: 她的口型与波形条
- 状态: 可用
- 简介: 嘴型跟着字走，SYSTEM 后面那排波形条跟着跳。
- 证据: app/lib/state/voice.dart, app/lib/widgets/voice_bars.dart

## 功能: 屏幕特效（亮帧 · 震屏 · 粒子）
- 状态: 可用
- 简介: 结算那一下的白闪、震屏、粒子拖尾，App 里已经有了。
- 证据: app/lib/widgets/fx_layer.dart, app/lib/widgets/fx_particles.dart, prototype/opus-v2-dir/js/fx.js

## 功能: 演出编排
- 状态: 进行中
- 简介: 派单/结算/失败/各页入场的时序还在补；这一轮正在补三处手感。
- 证据: app/BEHAVIOR-GAPS.md, prototype/motion-demo/index.html
- 依赖: 派单板, 结算与战报, 失败与补救

## 功能: 声音与震动
- 状态: 设想
- 简介: 音效、环境音、震动节奏——App 侧一个都还没有。
- 证据: app/BEHAVIOR-GAPS.md, prototype/opus-v2-dir/js/audio.js

## 功能: 到点提醒（她主动找你）
- 状态: 设想
- 简介: 钉单提醒、截止前催、连击保卫战；现在你不打开 App 她完全说不上话。
- 证据: docs/20-项目现状汇总.md, docs/19-产品分析.md

## 功能: 存档带走（换机/备份）
- 状态: 设想
- 简介: 把整个档导成一个文件带走再导入；现在清一次就归零、换机即丢。
- 证据: docs/20-项目现状汇总.md, docs/19-产品分析.md

## 功能: 无 Key 也能用上她的脑子（唤醒引导）
- 状态: 设想
- 简介: 第一次打开就一步步教你填上 API Key；现在没填的人只能听固定五句。
- 证据: docs/20-项目现状汇总.md, docs/19-产品分析.md

## 功能: 天幕背景
- 状态: 可用
- 简介: 深蓝虚空天幕素材已出图并进 App，垫在所有动态层最底下。
- 证据: prototype/opus-v2-dir/img/bg-void.jpg, app/assets/img/bg-void.jpg, tools/comfyui/README.md

## 功能: 视觉基准与动效样机
- 状态: 可用
- 简介: 视觉与手感的真源：动效先在样机里定死，再往 App 里搬。
- 证据: prototype/motion-demo/index.html, prototype/.stitch/DESIGN.md, prototype/.stitch/SCREENS.md, prototype/opus-v2-dir/css/app.css, app/lib/design/tokens.dart

## 功能: 每一版都留了证据（可复核）
- 状态: 可用
- 简介: 每一轮改动都留了实机截图与核对清单，谁改的、改到哪都能翻回去查。
- 证据: app/COVERAGE.md, app/REGRESSION.md, app/BEHAVIOR-GAPS.md, docs/18-Agent系统升级方案.md, docs/19-产品分析.md, docs/20-项目现状汇总.md, .verify/t24/README.md
