# 原型覆盖审计

> 生成方式：`python tools/ref/coverage.py --md`
> —— **这个文件是脚本产出的**，不要手改；原型一变就重跑一次。

## 为什么要做这个

`PORTING-NOTES.md` #19：大厅比到 1.5% 之后才做了一次这样的审计，发现 **`#ringTag`
（当前环的挂签）根本没移植** —— 而我的比对区域表里没有它，所以**连着八轮比对都"合格"**。

区域均值只能证明"我比过的地方对"，证明不了"我比全了"。这个审计补的就是后半句。

## 判定方式

把原型里所有 `id`（`index.html` 的 + JS 模板里动态建的）列出来，
每个在脚本的映射表里给出它对应的 Flutter 标识（Key 字符串或类名），
再去 `app/lib` 里 grep 那个标识**是否真的出现过**。

所以报告不会被写成"应该有" —— 它只认代码里真有的东西。

## 结论

**原型 103 个 id：已移植 95，故意不移植 8，缺失 0。**

不移植的那 8 个，每一个都有明确原因（下面表里标 `--` 的那几行）：

| id | 原因 |
|---|---|
| `#demo` `#dmCrit` | 桌面演示控制台 —— 开发工具，移动端不需要 |
| `#desk` `#phone` | 桌面外壳（把手机框和控制台并排摆）—— 移动端不需要 |
| `#filePick` | 证据拍照：要真相机（`image_picker`）+ 证据规则 |
| `#hit` | 戳她的命中层：依赖 B1 模型 |
| `#stage` `#stageCv` | Live2D 画布：依赖 B1 模型（见 `STAGE-OPTIONS.md`） |

也就是说：**除了"她本人"和证据拍照，界面元素已经一个不落。**

## 明细
| ԭ�� id | Flutter | ״̬ |
|---|---|---|
| `#app` | AppShell | OK |
| `#ask` | AskField | OK |
| `#askIn` | AskField | OK |
| `#askPresets` | AskField | OK |
| `#askPs` | AskField | OK |
| `#banner` | SysBanner | OK |
| `#beam` | SheetBeam | OK |
| `#beamG` | SheetBeam | OK |
| `#beamL` | SheetBeam | OK |
| `#beamPoly` | SheetBeam | OK |
| `#beamR` | SheetBeam | OK |
| `#bg` | BgLayer | OK |
| `#bgWord` | BgLayer | OK |
| `#boot` | BootScreen | OK |
| `#btBar` | BootScreen | OK |
| `#btClock` | BootScreen | OK |
| `#btGo` | BootScreen | OK |
| `#btLog` | BootScreen | OK |
| `#btTip` | BootScreen | OK |
| `#choices` | Choices | OK |
| `#cta` | Dock | OK |
| `#ctaCap` | Dock | OK |
| `#ctaLabel` | Dock | OK |
| `#ctaN` | Dock | OK |
| `#ctaSub` | Dock | OK |
| `#demo` | �� | [MISS]��������ʾ����̨ ���� �������ߣ��ƶ��˲���Ҫ�� |
| `#desk` | �� | [MISS]��������ǣ��ֻ�������ʾ̨������ �ƶ��˲���Ҫ�� |
| `#dmCrit` | �� | [MISS]��ͬ�ϣ� |
| `#dock` | Dock | OK |
| `#exBar` | exec.bar | OK |
| `#exCrit` | ExecPanel | OK |
| `#exDrawer` | exec.drawer | OK |
| `#exEye` | ExecPanel | OK |
| `#exGo` | exec.go | OK |
| `#exItem` | exec.item | OK |
| `#exItemN` | exec.item | OK |
| `#exMin` | exec.min | OK |
| `#exQuit` | exec.quit | OK |
| `#exSlots` | ExecPanel | OK |
| `#exT` | ExecPanel | OK |
| `#exTags` | ExecPanel | OK |
| `#exec` | ExecPanel | OK |
| `#execPill` | ExecPill | OK |
| `#failv` | FailLayer | OK |
| `#filePick` | �� | [MISS]��֤�����գ�Ҫ�������image_picker��+ ֤�ݹ��� |
| `#flash` | FlashLayer | OK |
| `#fpSub` | plate.print | OK |
| `#fpTxt` | plate.print | OK |
| `#fvRem` | fail.remedy | OK |
| `#fx` | FxField | OK |
| `#hit` | �� | [MISS]�����������в㣺���� B1 ģ�ͣ� |
| `#hud` | Hud | OK |
| `#hudCoin` | Hud | OK |
| `#hudLv` | Hud | OK |
| `#hudLvN` | Hud | OK |
| `#hudMenu` | Hud | OK |
| `#hudName` | Hud | OK |
| `#hudStreak` | Hud | OK |
| `#hudTitle` | Hud | OK |
| `#line` | LineLayer | OK |
| `#lineMood` | LineLayer | OK |
| `#lineTxt` | TypeText | OK |
| `#lvArc` | Hud | OK |
| `#mainv` | MainView | OK |
| `#mvDetail` | main.detail | OK |
| `#mvGo` | main.dispatch | OK |
| `#mvNew` | main.newGoal | OK |
| `#mvX` | main.close | OK |
| `#phone` | �� | [MISS]��ͬ�ϣ� |
| `#pillT` | ExecPill | OK |
| `#plPrint` | plate.print | OK |
| `#plReward` | Plate | OK |
| `#plate` | Plate | OK |
| `#plateAlt` | PlateAlt | OK |
| `#result` | ResultPanel | OK |
| `#ringCv` | RingField | OK |
| `#ringLabels` | RingLabels | OK |
| `#ringTag` | RingTag | OK |
| `#rsBar` | result.bar | OK |
| `#rsBarI` | result.bar.fill | OK |
| `#rsCard` | result.card | OK |
| `#rsExp` | ResultPanel | OK |
| `#rsGain` | result.gain | OK |
| `#rsGlyph` | result.glyph | OK |
| `#rsHead` | ResultPanel | OK |
| `#rsLv` | ResultPanel | OK |
| `#rsNear` | ResultPanel | OK |
| `#rsNeed` | ResultPanel | OK |
| `#rsSave` | result.save | OK |
| `#rsTags` | ResultPanel | OK |
| `#rtName` | RingTag | OK |
| `#rtNum` | RingTag | OK |
| `#shBody` | Sheet | OK |
| `#shK` | Sheet | OK |
| `#shT` | Sheet | OK |
| `#shX` | Sheet | OK |
| `#shake` | ShakeLayer | OK |
| `#sheet` | Sheet | OK |
| `#stage` | �� | [MISS]��Live2D ���������� B1 ģ�ͣ��� STAGE-OPTIONS.md���� |
| `#stageCv` | �� | [MISS]��ͬ�ϣ� |
| `#ui` | Stack | OK |
| `#veil` | Veil | OK |
| `#wipe` | sheet.danger | OK |

ԭ�� id �� 103 ��������ֲ 95�����ⲻ��ֲ 8��ȱʧ 0
  ��  #demo��������ʾ����̨ ���� �������ߣ��ƶ��˲���Ҫ
  ��  #desk��������ǣ��ֻ�������ʾ̨������ �ƶ��˲���Ҫ
  ��  #dmCrit��ͬ��
  ��  #filePick��֤�����գ�Ҫ�������image_picker��+ ֤�ݹ���
  ��  #hit�����������в㣺���� B1 ģ��
  ��  #phone��ͬ��
  ��  #stage��Live2D ���������� B1 ģ�ͣ��� STAGE-OPTIONS.md��
  ��  #stageCv��ͬ��

