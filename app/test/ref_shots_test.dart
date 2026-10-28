import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/items.dart';
import 'package:system_panel/data/titles.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/ui/ref/ref_archive.dart';
import 'package:system_panel/ui/ref/ref_bg.dart';
import 'package:system_panel/ui/ref/ref_board.dart';
import 'package:system_panel/ui/ref/ref_boot.dart';
import 'package:system_panel/ui/ref/ref_exec.dart';
import 'package:system_panel/ui/ref/ref_home.dart';
import 'package:system_panel/ui/ref/ref_hud.dart';
import 'package:system_panel/ui/ref/ref_main.dart';
import 'package:system_panel/ui/ref/ref_overlays.dart';
import 'package:system_panel/ui/ref/ref_sheet.dart';
import 'package:system_panel/ui/ref/ref_shop.dart';
import 'package:system_panel/ui/ref/ref_verdict.dart';

/// v3 参考稿还原层 · 离屏出图（不依赖模拟器 / 浏览器）
///
/// 用法：cd app && flutter test test/ref_shots_test.dart
/// 产物：app/build/refshots/<序号>-<页面>.png（390×844 @2x = 780×1688）
///
/// 三个关键点：
///  1. 必须自己加载字体，否则 flutter test 用 Ahem 占位字体、中文全是方框；
///  2. 出图走 RepaintBoundary.toImage（不锁像素基线）；
///  3. RefHud / RefSheet 内部是 Positioned，必须放在 Stack 里。
const Size kPhone = Size(390, 844);
// 出图倍率（390×844 @2x = 780×1688，与真机 1170×2532 同比例）。
// 配合 _snap 里的 runAsync，整套 11 张 ~1 秒，不再需要降倍率。
const double kDpr = 2;
const String kOutDir = 'build/refshots';
const ValueKey<String> kShotKey = ValueKey<String>('shot');

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final FontLoader loader = FontLoader(family);
    for (final String p in paths) {
      final ByteData data = await rootBundle.load(p);
      loader.addFont(Future<ByteData>.value(data));
    }
    await loader.load();
  }

  await load('NotoSansSC', <String>['assets/fonts/NotoSansSC-VF.ttf']);
  await load('JetBrainsMono', <String>['assets/fonts/JetBrainsMono-VF.ttf']);
  await load('ChakraPetch', <String>[
    'assets/fonts/ChakraPetch-Medium.ttf',
    'assets/fonts/ChakraPetch-Bold.ttf',
    'assets/fonts/ChakraPetch-Italic.ttf',
    'assets/fonts/ChakraPetch-BoldItalic.ttf',
  ]);
}

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.pump();
  final RenderRepaintBoundary boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(kShotKey),
  );
  // ⚠️ 必须包在 runAsync 里。`toImage` 走引擎的真实 IO/光栅线程，而
  //    flutter_test 的 FakeAsync 不会推进那些线程 —— 直接 await 会卡在
  //    「等一个永远不会完成的 Future」，表现就是一张图几分钟、看起来像挂死。
  late final ui.Image img;
  late final ByteData? bd;
  await tester.runAsync(() async {
    img = await boundary.toImage(pixelRatio: kDpr);
    bd = await img.toByteData(format: ui.ImageByteFormat.png);
  });
  final Directory dir = Directory(kOutDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final File f = File('${dir.path}/$name.png');
  f.writeAsBytesSync(bd!.buffer.asUint8List());
  // ignore: avoid_print
  print('[shot] $name  ${img.width}×${img.height}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  final HostState demoHost = HostState.demo.copyWith(
    lv: 4,
    exp: 22,
    coins: 128,
    streak: 3,
    attrs: const <String, int>{
      '力': 4, '体': 3, '智': 5, '知': 3, '魅': 2, '敏': 2,
    },
  );

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    bool hud = true,
    bool useBg = false,
    Color accent = Ref.acid,
    String ghost = '系统',
  }) async {
    tester.view.physicalSize = Size(kPhone.width * kDpr, kPhone.height * kDpr);
    tester.view.devicePixelRatio = kDpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: kShotKey,
        // 不关 ticker：入场动画（.rv 的淡入/上移）要跑完才是最终态，
        // 关掉会拍到 opacity 0 的中间帧（按钮发暗、印章半透明）。
        // 之前的「一张几分钟」不是 ticker 的锅，是 toImage 没包 runAsync。
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: 'NotoSansSC',
            scaffoldBackgroundColor: Ref.bg,
          ),
          home: Scaffold(
            backgroundColor: Ref.bg,
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // ⚠️ 出图时默认**不带天幕**：_HorizonPainter 的 MaskFilter.blur
                //    在 flutter test 的软件光栅下极慢（实测单张 >10 分钟），
                //    而它只是背景里的一条辉光线，对逐页核对版式没有影响。
                //    要看完整天幕可以把 useBg 打开（很慢）。
                if (useBg)
                  RefBackground(accent: accent, ghost: ghost, animate: false),
                child,
                if (hud) RefHud(state: demoHost),
              ],
            ),
          ),
        ),
      ),
    );
    // ⚠️ 不能用 pumpAndSettle：页面里有 repeat() 的永动动画（核心旋转 /
    //    呼吸 / 扫描线），帧循环永不停，settle 一定超时。
    //    但也不能只 pump 一次：票券的入场是 Timer(delay: index*80ms) →
    //    forward()，真实 Timer 不受 pump(Duration) 推进，会拍到 opacity 0
    //    的委托板空壳。用固定次数的短 pump 把入场动画推完。
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('01 开机屏', (WidgetTester tester) async {
    await mount(
      tester,
      hud: false,
      RefBoot(
        lines: const <String>[
          '挂载人格模块 …… 毒舌 ✓',
          '挂载人格模块 …… 靠谱 ✓',
          '校准良心 …… 未找到，跳过',
          '链接宿主档案 …… 宿主 · LV1',
          '唤醒序列就绪',
        ],
        progress: 1,
        ready: true,
        onWake: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _snap(tester, '01-boot');
  });

  testWidgets('02 大厅', (WidgetTester tester) async {
    await mount(
      tester,
      RefHome(
        host: demoHost,
        goal: Goal.demo(),
        quip: '这个点还醒着？那就做点有用的，或者去睡。',
        queue: 4,
        day: 2,
        days: 14,
      ),
    );
    await _snap(tester, '02-home');
  });

  testWidgets('03 主线（正面）', (WidgetTester tester) async {
    await mount(
      tester,
      hud: false,
      RefMain(
        goal: Goal.demo(),
        lead: 0,
        mood: '冷淡',
        line: '清单不会自己变短。看哪张？',
      ),
      accent: Ref.cyan,
      ghost: '骑行',
    );
    await _snap(tester, '03-main');
  });

  testWidgets('04 委托板', (WidgetTester tester) async {
    await mount(
      tester,
      RefBoard(
        quests: <Quest>[
          Quest.demo,
          const Quest(
            serial: 42,
            kind: 'main',
            planIndex: 5,
            planTotal: 8,
            goalId: 'demo',
            name: '清晨 6:45 前起床并出门走 10 分钟',
            reason: '',
            proof: '晨间起床时间截图',
            minutes: 30,
            rank: 'D',
            attrs: <String, int>{'体': 1, '知': 1},
          ),
          const Quest(
            serial: 43,
            kind: 'main',
            planIndex: 6,
            planTotal: 8,
            goalId: 'demo',
            name: '连续一日完成 23:45 睡 + 6:45 起打卡',
            reason: '',
            proof: '全天作息记录截图',
            minutes: 60,
            rank: 'B',
            attrs: <String, int>{'体': 1, '知': 1},
          ),
          const Quest(
            serial: 44,
            kind: 'daily',
            planIndex: -1,
            planTotal: 0,
            goalId: '',
            name: '今天不喝咖啡和浓茶，晚上才睡得着',
            reason: '',
            proof: '晚上拍一张今天喝过的东西',
            minutes: 5,
            rank: 'E',
            attrs: <String, int>{'知': 1},
          ),
        ],
        filter: 'all',
        onFilter: (String _) {},
        onTap: (Quest _) {},
      ),
      accent: Ref.gold,
      ghost: '委托',
    );
    await _snap(tester, '04-board');
  });

  testWidgets('05 执行', (WidgetTester tester) async {
    await mount(
      tester,
      RefExec(
        quest: Quest.demo,
        elapsed: const Duration(minutes: 6, seconds: 12),
        critChance: .16,
        onQuitProgress: (double _) {},
      ),
      accent: Ref.hot,
      ghost: '执行',
    );
    await _snap(tester, '05-exec');
  });

  testWidgets('06 结算', (WidgetTester tester) async {
    await mount(
      tester,
      hud: false,
      RefVerdict(
        rank: 'B',
        crit: false,
        line: 'C 级的活儿，干得像模像样。我认。',
        rows: const <RefRewardRow>[
          RefRewardRow(label: 'EXP', value: 12),
          RefRewardRow(label: '晶核', value: 7),
          RefRewardRow(label: '体质', value: 2, tag: '×2'),
          RefRewardRow(label: '连胜天数', value: 1, tag: 'TODAY'),
        ],
        xpFrom: 4,
        xpTo: 16,
        xpNeed: 42,
        lv: 4,
        onAccept: () {},
        scanning: false,
        phase: RefVerdictPhase.result,
      ),
      accent: Ref.mint,
      ghost: '验收',
    );
    await tester.pump(const Duration(milliseconds: 900));
    await _snap(tester, '06-verdict');
  });

  testWidgets('07 档案', (WidgetTester tester) async {
    await mount(
      tester,
      hud: false,
      RefArchive(
        host: demoHost,
        ownedCount: 3,
        totalTitles: HostTitle.all.length,
        onBack: () {},
        onEquip: (String _) => true,
      ),
      accent: Ref.violet,
      ghost: '档案',
    );
    await _snap(tester, '07-archive');
  });

  testWidgets('08 补给', (WidgetTester tester) async {
    await mount(
      tester,
      RefShop(
        items: Item.all,
        owned: const <String, int>{'dbl': 1},
        coins: 128,
        onBack: () {},
        onBuy: (Item _) => true,
      ),
      accent: Ref.mint,
      ghost: '补给',
    );
    await _snap(tester, '08-shop');
  });

  testWidgets('09 系统设置抽屉', (WidgetTester tester) async {
    await mount(
      tester,
      RefSheet(
        visible: true,
        sound: true,
        onSound: (bool _) {},
        onClose: () {},
        onHint: () {},
        onChat: () {},
        onLlm: () {},
        onReset: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await _snap(tester, '09-sheet');
  });

  testWidgets('10 失败页', (WidgetTester tester) async {
    await mount(
      tester,
      hud: false,
      RefFail(
        title: '任务超时',
        sub: 'MISSION FAILED',
        box: const Text('认输也是一种勇气。不过，别养成习惯。'),
        onBack: () {},
      ),
      accent: Ref.hot,
      ghost: '失败',
    );
    await _snap(tester, '10-fail');
  });

  testWidgets('11 升级过场', (WidgetTester tester) async {
    await mount(
      tester,
      hud: false,
      RefLevelUp(from: 3, to: 4, perk: '解锁「档案 · 名牒册」', onTap: () {}),
    );
    await tester.pump(const Duration(milliseconds: 1400));
    await _snap(tester, '11-levelup');
  });
}
