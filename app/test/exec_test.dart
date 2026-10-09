import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/agent/vision.dart' show EvidenceShot, EvidenceStatus;
import 'package:system_panel/data/format.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/widgets/exec_panel.dart';

/// 执行面板（大字计时器 / 时限条 / 观看眼 / 证据槽 / 暴击率 / 道具 + 提交）。
/// 坐标断言来自运行中原型的实测值。
///
/// ⚠️ 同 lobby_test：`flutter test` 用占位字体（每字形 1em 宽），
/// 凡"宽度由文字撑出来"的盒子在单测里量不准，只断言与文字宽度无关的部分。
const Size kDesign = Size(390, 844);

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(kDesign);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  await tester.pump();
}

void main() {
  group('时间格式 = util.js', () {
    test('fmtClock：1 小时以内 MM:SS，超过 H:MM:SS（L46）', () {
      expect(fmtClock(const Duration(seconds: 7)), '00:07');
      expect(fmtClock(const Duration(minutes: 45)), '45:00');
      expect(fmtClock(const Duration(minutes: 7)), '07:00');
      expect(
        fmtClock(const Duration(hours: 1, minutes: 5, seconds: 3)),
        '1:05:03',
      );
      expect(fmtClock(const Duration(seconds: -5)), '00:00');
    });

    test('fmtMin：分钟 / 小时 / 小时+分（L51）', () {
      expect(fmtMin(45), '45 分钟');
      expect(fmtMin(60), '1 小时');
      expect(fmtMin(90), '1 小时 30 分');
    });
  });

  group('执行面板', () {
    testWidgets('文案齐全', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7),
          critChance: .12,
          itemCount: 3,
          evidenceCount: 0,
        ),
      );
      expect(find.text('执行中 · RING 5/8'), findsOneWidget);
      expect(find.text('跑完 5 公里'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text('/ 45:00'), findsOneWidget);
      expect(find.text('SYSTEM 正在看着你'), findsOneWidget);
      expect(find.text('证据 · 跑步 APP 截图'), findsOneWidget);
      expect(find.textContaining('暴击率'), findsWidgets);
      expect(find.textContaining('12%'), findsWidgets);
      expect(find.text('道具'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('提交 · 让她验收'), findsOneWidget);
      expect(find.text('按住 · 认输'), findsOneWidget);
      expect(find.text('收起 ▾'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('各件落在原型实测坐标上', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7),
          critChance: .12,
          itemCount: 3,
          evidenceCount: 0,
        ),
      );
      // .ex-col：left 22 / top 92 / 宽 62%（390 → 241.8）
      final Rect col = tester.getRect(find.byKey(const Key('exec.col')));
      expect(col.left, 22);
      expect(col.top, 92);
      expect(col.width, closeTo(241.8, .5));
      // .ex-k .rk → [22,92,22,22]
      expect(
        tester.getRect(find.byKey(const Key('exec.rk'))),
        const Rect.fromLTWH(22, 92, 22, 22),
      );
      // 三个证据槽 x=22/88/154，各 58×58，y=349
      for (int i = 0; i < 3; i++) {
        final Rect s = tester.getRect(find.byKey(Key('exec.slot.$i')));
        expect(s.left, 22 + i * 66);
        expect(s.top, 349);
        expect(s.size, const Size(58, 58));
      }
      // .ex-act [20,708,350,54]；道具 [20,708,88,54]；提交 [118,708,252,54]
      final Rect act = tester.getRect(find.byKey(const Key('exec.act')));
      expect(act.left, 20);
      expect(act.right, 370);
      expect(act.bottom, closeTo(762, .5));
      expect(tester.getRect(find.byKey(const Key('exec.item'))).left, 20);
      expect(tester.getRect(find.byKey(const Key('exec.item'))).height, 54);
      expect(tester.getRect(find.byKey(const Key('exec.go'))).right, 370);
      // .ex-low [20,778,350,40]
      expect(tester.getRect(find.byKey(const Key('exec.quit'))).top, 778);
      expect(tester.getRect(find.byKey(const Key('exec.quit'))).height, 40);
      expect(tester.getRect(find.byKey(const Key('exec.min'))).right, 370);
    });

    testWidgets('时限条真的有高度，且按进度铺开', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7), // 7/45 = 15.6%
          critChance: .12,
          itemCount: 3,
          evidenceCount: 0,
        ),
      );
      // 回归：FractionallySizedBox 少了 heightFactor，无子元素的 DecoratedBox 会被量成 0 高
      final Rect bar = tester.getRect(find.byKey(const Key('exec.bar')));
      final Rect fill = tester.getRect(find.byKey(const Key('exec.bar.fill')));
      expect(fill.height, 3);
      expect(fill.left, closeTo(22, .5));
      // 条的宽度由右边文案撑）——所以只断言"填充占整条的比例"，与字体无关
      expect(fill.width / bar.width, closeTo(7 / 45, .01));
    });

    testWidgets('超时前 85% 不进入 warn，超过则变白（`.ex-t.warn`）', (
      WidgetTester tester,
    ) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 40), // 40/45 = 88.9% > 85%
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
        ),
      );
      final Text t = tester.widget<Text>(
        find.byWidgetPredicate((Widget w) => w is Text && w.data == '40:00'),
      );
      expect(t.style?.color, Colors.white);
      expect(find.text('道具'), findsOneWidget); // 道具数为 0 时不显数字
      expect(find.text('0'), findsNothing);
    });

    testWidgets('不可见时不占位', (WidgetTester tester) async {
      await _mount(
        tester,
        const ExecPanel(
          quest: Quest.demo,
          elapsed: Duration(minutes: 7),
          critChance: .12,
          itemCount: 0,
          evidenceCount: 0,
          visible: false,
        ),
      );
      expect(find.byKey(const Key('exec.col')), findsNothing);
    });
  });

  // ── 入退场过渡（t26/TODO-13）──────────────────────────────
  //
  // 全 App 唯一的整页硬切（`if (!visible) shrink`）换成：
  // 入场 280ms scale .97→1 + fade（与钤印 280ms 亮帧同拍收尾）、退场 200ms。
  // 终态零包裹 —— 演出播完，渲染树与旧版逐字节一致。
  group('入退场过渡（t26/TODO-13）', () {
    Widget host(bool vis) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            ExecPanel(
              quest: Quest.demo,
              elapsed: const Duration(minutes: 7),
              critChance: .12,
              itemCount: 0,
              evidenceCount: 0,
              visible: vis,
            ),
          ],
        ),
      ),
    );

    testWidgets('visible 翻真：280ms scale+fade 入场，终态零包裹', (
      WidgetTester tester,
    ) async {
      await _mount(tester, host(false));
      expect(find.byKey(const Key('exec.col')), findsNothing);
      await _mount(tester, host(true));
      // kOut（.16,1,.3,1）前段极陡：~1/3 处曲线就饱和了，
      // 取 20ms 的采样点才能读到中间值
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byKey(const Key('exec.col')), findsOneWidget);
      final Opacity op = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(ExecPanel),
              matching: find.byKey(const Key('exec.enter')),
            )
            .first,
      );
      expect(op.opacity, greaterThan(0));
      expect(op.opacity, lessThan(1));
      final Transform tr = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(ExecPanel),
              matching: find.byKey(const Key('exec.enter.scale')),
            )
            .first,
      );
      // X/Y 缩放（getMaxScaleOnAxis 会把 z=1 那条轴也算进来，恒为 1）
      final double sx = tr.transform[0];
      expect(sx, greaterThan(.97));
      expect(sx, lessThan(1));
      await tester.pump(const Duration(milliseconds: 260)); // 280ms 播完
      // 零包裹：找不到演出层，坐标回到原型实测值
      expect(find.byKey(const Key('exec.enter')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('exec.rk'))),
        const Rect.fromLTWH(22, 92, 22, 22),
      );
    });

    testWidgets('visible 翻假：200ms 退场（期间不挨点），播完摘树', (
      WidgetTester tester,
    ) async {
      await _mount(tester, host(true));
      await tester.pump(); // 首挂即终态
      await _mount(tester, host(false));
      await tester.pump(const Duration(milliseconds: 100)); // 退场半程
      expect(find.byKey(const Key('exec.col')), findsOneWidget); // 还挂着
      final IgnorePointer ip = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(ExecPanel),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ip.ignoring, isTrue); // 退场中不再挨点
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('exec.col')), findsNothing); // 摘干净
    });

    testWidgets('首挂即终态（静态比对不受演出影响）', (WidgetTester tester) async {
      await _mount(tester, host(true));
      await tester.pump();
      expect(find.byKey(const Key('exec.enter')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('exec.rk'))),
        const Rect.fromLTWH(22, 92, 22, 22),
      );
    });
  });

  // ── 证据槽入槽过渡（t26/P2-4）─────────────────────────────
  //
  // 拍照回填从「缩略图瞬现」改成：照片 160ms scale .82→1（easeOutBack）+ fade；
  // 状态角标延迟 120ms 再 160ms 淡入 —— 「先照片后判定」的节拍。
  group('证据槽入槽过渡（t26/P2-4）', () {
    Widget host(List<EvidenceShot> shots) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            ExecPanel(
              quest: Quest.demo,
              elapsed: Duration.zero,
              critChance: .12,
              itemCount: 0,
              evidenceCount: 0,
              evidence: shots,
            ),
          ],
        ),
      ),
    );

    testWidgets('加照 160ms 入槽，角标延迟 120ms 淡入', (WidgetTester tester) async {
      final List<EvidenceShot> shots = <EvidenceShot>[];
      await _mount(tester, host(shots));
      expect(find.text('已丢失'), findsNothing); // 空槽
      shots.add(
        EvidenceShot(
          id: 'e1',
          path: 'evidence/x.jpg',
          status: EvidenceStatus.verified,
          takenAt: DateTime(2026),
        ),
      );
      await _mount(tester, host(shots));
      await tester.pump(const Duration(milliseconds: 80)); // 入槽半程
      final Opacity reveal = tester.widget<Opacity>(
        find.byKey(const Key('exec.evi.reveal.0')),
      );
      expect(reveal.opacity, greaterThan(0));
      expect(reveal.opacity, lessThan(1));
      expect(find.text('已丢失'), findsOneWidget); // 槽已填（照片读不到 → 降级字）
      // 角标还没到拍（120ms 延迟未到）
      final Opacity badge = tester.widget<Opacity>(
        find.byKey(const Key('exec.evi.badge.fade.verified')),
      );
      expect(badge.opacity, 0);
      await tester.pump(const Duration(milliseconds: 80)); // t=160 照片落定
      // 落定：包裹还在但已是无操作（opacity 1）—— 结构稳定，角标节拍不被重挂打断
      final Opacity revealDone = tester.widget<Opacity>(
        find.byKey(const Key('exec.evi.reveal.0')),
      );
      expect(revealDone.opacity, 1);
      final Opacity badgeHalf = tester.widget<Opacity>(
        find.byKey(const Key('exec.evi.badge.fade.verified')),
      );
      expect(badgeHalf.opacity, closeTo(.25, .02)); // (160-120)/160
      await tester.pump(const Duration(milliseconds: 120)); // t=280 角标落定
      expect(find.byKey(const Key('exec.evi.badge.fade.verified')), findsNothing);
      expect(find.byKey(const Key('exec.evi.badge.verified')), findsOneWidget);
    });
  });
}
