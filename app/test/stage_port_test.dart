import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/stage/live2d_stage.dart';
import 'package:system_panel/stage/perf_presets.dart';
import 'package:system_panel/stage/stage_port.dart';

/// 舞台桥接表一致性（docs/18 §1.5.4 / stage.js L27-77 真源）。
///
/// 这张表是「页面说人话、模型听得懂」的唯一翻译层，错一条就是
/// 「叫她笑她哭」级别的事故——所以逐条钉死：
///  · 12 种情绪全部能在 28 表情表里查到下标（一个不多、一个不少）
///  · 全部动词的动作组都在 sakiko.model3.json 的 17 个组里
///  · 待机池 ⊆ 17 组；未知输入有兜底不炸
void main() {
  group('情绪表（stage.js EMO_EXP，12 种）', () {
    test('恰好 12 种，键与原型一致', () {
      expect(StageBridges.emoExp.keys.toSet(), <String>{
        'neutral', 'smug', 'cold', 'annoyed', 'pleased', 'tsun',
        'joy', 'proud', 'surprised', 'sad', 'focus', 'sleep',
      });
      expect(StageBridges.emoExp.length, 12);
    });

    test('每种情绪都能在 32 表情表里查到下标（≥0）', () {
      for (final MapEntry<String, String> e
          in StageBridges.emoExp.entries) {
        final int i = Live2DStage.expressionIndex(e.value);
        expect(i, greaterThanOrEqualTo(0),
            reason: '${e.key} → ${e.value} 不在表情表里');
      }
    });

    test('关键映射逐条对原型（exp_sad02 / exp_idle04 / exp_bsmile01…）', () {
      expect(StageBridges.emoExp['neutral'], 'exp_idle01');
      expect(StageBridges.emoExp['smug'], 'exp_bsmile01');
      expect(StageBridges.emoExp['cold'], 'exp_serious01');
      expect(StageBridges.emoExp['annoyed'], 'exp_angry02');
      expect(StageBridges.emoExp['pleased'], 'exp_smile01');
      expect(StageBridges.emoExp['tsun'], 'exp_shy01');
      expect(StageBridges.emoExp['joy'], 'exp_bsmile02');
      expect(StageBridges.emoExp['proud'], 'exp_smile02');
      expect(StageBridges.emoExp['surprised'], 'exp_surprised02');
      expect(StageBridges.emoExp['sad'], 'exp_sad02');
      expect(StageBridges.emoExp['focus'], 'exp_serious02');
      expect(StageBridges.emoExp['sleep'], 'exp_idle04');
    });

    test('表情下标查得出：sad → exp_sad02 的字母序位置', () {
      expect(
        StageBridges.moodIndex('sad'),
        Live2DStage.expressions.indexOf('exp_sad02'),
      );
      expect(StageBridges.moodIndex('不认识的情绪'), -1);
    });
  });

  group('动词表（stage.js MOVE → model3.json 17 组）', () {
    test('19 个动词全部映射到 17 个合法动作组', () {
      expect(StageBridges.verbGroup.length, 19);
      for (final MapEntry<String, String> e
          in StageBridges.verbGroup.entries) {
        expect(
          Live2DStage.motionGroups.contains(e.value),
          isTrue,
          reason: '${e.key} → ${e.value} 不是 model3.json 里的组',
        );
      }
    });

    test('关键动词逐条对 docs/18 §1.5.4 桥接表', () {
      expect(StageBridges.groupOf('present'), 'kime');
      expect(StageBridges.groupOf('cheer'), 'kime');
      expect(StageBridges.groupOf('nod'), 'nod');
      expect(StageBridges.groupOf('nod2'), 'nod');
      expect(StageBridges.groupOf('surprise'), 'surprised');
      expect(StageBridges.groupOf('fluster'), 'denial');
      expect(StageBridges.groupOf('deny'), 'denial');
      expect(StageBridges.groupOf('down'), 'sad');
      expect(StageBridges.groupOf('think'), 'thinking');
      expect(StageBridges.groupOf('happy'), 'smile');
      expect(StageBridges.groupOf('poke'), 'check');
      expect(StageBridges.groupOf('lookAway'), 'look');
      expect(StageBridges.groupOf('ask'), 'question');
      expect(StageBridges.groupOf('bye'), 'bye');
      expect(StageBridges.groupOf('check'), 'check');
      expect(StageBridges.groupOf('serious'), 'serious');
      expect(StageBridges.groupOf('angry'), 'angry');
      expect(StageBridges.groupOf('cry'), 'cry');
      expect(StageBridges.groupOf('maskoff'), 'maskoff');
    });

    test('17 个动作组一个不缺（与 sakiko.model3.json 实测清单一致）', () {
      expect(Live2DStage.motionGroups.toSet(), <String>{
        'idle', 'smile', 'nod', 'cry', 'angry', 'look', 'surprised',
        'question', 'sad', 'serious', 'denial', 'check', 'bye',
        'misc_tear', 'maskoff', 'kime', 'thinking',
      });
    });

    test('19 个动词全带表情（docs/24 §4「动作与表情绑在一起」）', () {
      // poke 的原值保留
      expect(StageBridges.verbFace['poke'], 'exp_shy01');
      expect(
        StageBridges.verbFaceIndex('poke'),
        Live2DStage.expressions.indexOf('exp_shy01'),
      );
      // 每个动词都有自己的脸，且都在 32 表情表里
      for (final MapEntry<String, String> e in StageBridges.verbFace.entries) {
        expect(
          Live2DStage.expressions.contains(e.value),
          isTrue,
          reason: '${e.key} 的 ${e.value} 不在表情表里',
        );
      }
      expect(
        StageBridges.verbFace.keys.toSet(),
        StageBridges.verbGroup.keys.toSet(),
        reason: '动词表与表情表必须一一对应（全覆盖）',
      );
      expect(StageBridges.isVerb('down'), isTrue);
      expect(StageBridges.isVerb('不存在'), isFalse);
      expect(StageBridges.groupOf('不存在'), 'nod', reason: '兜底不静默丢弃');
    });

    test('情绪→兜底动作（emotionAct）：值全是合法动词，只给强烈情绪配', () {
      for (final MapEntry<String, String> e
          in StageBridges.emotionAct.entries) {
        expect(
          StageBridges.isVerb(e.value),
          isTrue,
          reason: '${e.key} → ${e.value} 不是动词',
        );
        expect(
          StageBridges.isMood(e.key),
          isTrue,
          reason: '${e.key} 不是合法情绪',
        );
      }
      // 克制的：neutral/smug 等不配动作（表演预算）
      expect(StageBridges.actOf('neutral'), '');
      expect(StageBridges.actOf('annoyed'), 'angry');
      expect(StageBridges.actOf('tsun'), 'deny');
    });
  });

  group('预设总表（PerfPresets：动作 × 表情 的命名组合）', () {
    test('每条预设的动作组与表情都真实存在（不可新增资源，只能组合）', () {
      for (final PerfPreset p in PerfPresets.all) {
        expect(
          Live2DStage.motionGroups.contains(p.group) ||
              p.group == Live2DStage.baseGroup,
          isTrue,
          reason: '${p.id} 的动作组 ${p.group} 不在 18 组里',
        );
        expect(
          Live2DStage.expressions.contains(p.exp),
          isTrue,
          reason: '${p.id} 的表情 ${p.exp} 不在 32 个里',
        );
        expect(Live2DStage.countOf(p.group), greaterThan(0));
      }
    });

    test('id 唯一、中文名非空、优先级合法（1 待机 / 2 指令 / 3 强制）', () {
      final Set<String> ids = <String>{};
      for (final PerfPreset p in PerfPresets.all) {
        expect(ids.add(p.id), isTrue, reason: '预设 id 重复：${p.id}');
        expect(p.name.trim(), isNotEmpty, reason: '${p.id} 没有中文名');
        expect(p.priority, inInclusiveRange(1, 3), reason: '${p.id} 优先级越界');
      }
      expect(PerfPresets.all.length, greaterThanOrEqualTo(30),
          reason: '预设是本次交付的主体，不该只剩几条');
    });

    test('按族取不丢条目（调试页分组与文档分节都靠它）', () {
      int sum = 0;
      for (final PerfFamily f in PerfFamily.values) {
        sum += PerfPresets.of(f).length;
      }
      expect(sum, PerfPresets.all.length);
      expect(PerfPresets.byId('present')?.name, '亮相');
      expect(PerfPresets.byId('不存在的预设'), isNull);
    });

    test('动作组总表 = 17 语义组 + Idle 基底（调试页"动作"页签）', () {
      expect(PerfPresets.groups.length, 18);
      expect(PerfPresets.groups.toSet().length, 18, reason: '有重复组名');
      expect(PerfPresets.groups.contains(Live2DStage.baseGroup), isTrue);
    });
  });

  group('待机池（docs/24 §3 清单 A：动作组 + 表情）', () {
    test('三档心情的池都非空，组 ⊆ 17 组、表情都在 32 表里', () {
      expect(StageBridges.idlePool.keys.toSet(), <String>{
        'cold', 'pleased', 'neutral',
      });
      for (final MapEntry<String, List<Perf>> e
          in StageBridges.idlePool.entries) {
        expect(e.value, isNotEmpty, reason: '${e.key} 池空了');
        for (final Perf p in e.value) {
          expect(
            Live2DStage.motionGroups.contains(p.group),
            isTrue,
            reason: '${e.key} 池里的 ${p.group} 不是合法组',
          );
          expect(
            Live2DStage.expressions.contains(p.exp),
            isTrue,
            reason: '${e.key} 池里 ${p.group} 的 ${p.exp} 不在表情表里',
          );
          expect(p.priority, 2, reason: '池里不落优先级，播放时恒 1');
        }
      }
    });

    test('闲置表情真的用起来了（docs/24 §5：idle02/idle03/kime01）', () {
      final Set<String> used = StageBridges.idlePool.values
          .expand((List<Perf> l) => l)
          .map((Perf p) => p.exp)
          .toSet();
      expect(used.containsAll(<String>['exp_idle02', 'exp_idle03', 'exp_kime01']),
          isTrue,
          reason: '清单 A 承诺启用这三个闲置表情');
    });

    test('未知心情回落 neutral', () {
      expect(StageBridges.poolOf('cold'), 'cold');
      expect(StageBridges.poolOf('随便'), 'neutral');
    });
  });

  group('几何相机（docs/18 §1.5.3 布局矩形）', () {
    test('stageRect：矩形高 = 屏高×cam.s×kSize，中心 = Cam.screenCenter', () {
      final Rect r = Live2DStage.stageRect(
        Cam.byName('lobby'),
        const Size(430, 932),
      );
      expect(r.height, closeTo(932 * .92 * StageCalib.kSize, .5));
      expect(r.center.dx, closeTo(430 * .5 + StageCalib.dx, .5));
      expect(r.center.dy, closeTo(932 * .505 + StageCalib.dy, .5));
    });

    // ⚠️ 2026-10-11 iOS 真机轮：矩形必须保持**画布比例**，否则插件按画布宽度
    //    适配时会把她的头/脚裁掉（详见 Live2DStage.stageRect 注释）。
    test('stageRect 宽高比 = 画布比例 2:3（否则她被裁头裁脚）', () {
      expect(Live2DStage.kCanvasAspect, closeTo(6000 / 9000, 1e-9));
      for (final String cam in <String>['boot', 'lobby', 'talk', 'exec']) {
        final Rect r = Live2DStage.stageRect(
          Cam.byName(cam),
          const Size(430, 932),
        );
        expect(
          r.width / r.height,
          closeTo(Live2DStage.kCanvasAspect, 1e-6),
          reason: '$cam 矩形不是画布比例 —— 插件会裁掉她的头/脚',
        );
      }
    });

    // ── 视图固定尺寸族（2026-10-11 根治「推镜头像硬切」）──────────────
    // 平台视图的布局尺寸一变，插件就重建 FBO；所以矩形只按"族"定尺寸，
    // 族内的缩放交给 Transform.scale —— 这两条断言保证"改矩形"和
    // "固定矩形 + 缩放"在几何上完全等价（否则她会跳位/变形）。
    group('视图固定尺寸族 + Transform', () {
      const Size screen = Size(430, 932);

      test('族选择：每个 cam 都落到 ≥ 它的最小族，且缩放系数 ≤ 1（只缩不放大）', () {
        for (final MapEntry<String, Cam> e in Cam.all.entries) {
          final double f = Live2DStage.viewFamilyS(e.value.s);
          expect(
            e.value.s,
            lessThanOrEqualTo(f + 1e-9),
            reason: '${e.key} 的 s=${e.value.s} 超过了族 $f',
          );
          expect(
            e.value.s / f,
            lessThanOrEqualTo(1 + 1e-9),
            reason: '${e.key} 的缩放系数必须 ≤ 1（放大 = 糊）',
          );
        }
        // 小景别一族（含大厅/主线/结算），派单推近才换到 1.70 那族
        expect(Live2DStage.viewFamilyS(.64), 1.05);
        expect(Live2DStage.viewFamilyS(.92), 1.05);
        expect(Live2DStage.viewFamilyS(1.05), 1.05);
        expect(Live2DStage.viewFamilyS(1.70), 1.70);
      });

      test('固定矩形 + 缩放 ≡ 原来那个矩形（中心/尺寸逐项相等）', () {
        for (final String cam in <String>['boot', 'lobby', 'talk', 'exec']) {
          final Cam c = Cam.byName(cam);
          final double f = Live2DStage.viewFamilyS(c.s);
          final Rect view = Live2DStage.viewRect(f, c, screen);
          final double k = c.s / f;
          final Rect scaled = Rect.fromCenter(
            center: view.center,
            width: view.width * k,
            height: view.height * k,
          );
          final Rect want = Live2DStage.stageRect(c, screen);
          expect(scaled.center.dx, closeTo(want.center.dx, .01), reason: cam);
          expect(scaled.center.dy, closeTo(want.center.dy, .01), reason: cam);
          expect(scaled.width, closeTo(want.width, .01), reason: cam);
          expect(scaled.height, closeTo(want.height, .01), reason: cam);
        }
      });

      test('同一族内的不同 cam：布局矩形**完全一样**（这才是"不重建 FBO"）', () {
        final Rect a = Live2DStage.viewRect(
          Live2DStage.viewFamilyS(.64),
          Cam.byName('boot'),
          screen,
        );
        final Rect b = Live2DStage.viewRect(
          Live2DStage.viewFamilyS(.92),
          Cam.byName('lobby'),
          screen,
        );
        // 尺寸必须一模一样（位置可以不同 —— 位置变不会触发 layoutSubviews）
        expect(b.width, closeTo(a.width, 1e-9));
        expect(b.height, closeTo(a.height, 1e-9));
      });
    });

    // 「戳她」命中判定（原型 stage.js `hit()` 的宽度曲线）
    test('hitHer：头顶窄、裙摆宽（原型曲线照抄，宽松是为了随手一戳就中）', () {
      const Size screen = Size(430, 932);
      final Rect r = Live2DStage.stageRect(Cam.byName('lobby'), screen);
      final double cx = r.center.dx;
      Offset at(double f, double dx) =>
          Offset(cx + dx, r.top + r.height * f);

      // 头顶（f≈.05）：宽度因子小 → 偏 150px 就出界
      expect(Live2DStage.hitHer(at(.05, 0), r), isTrue, reason: '正中间没命中');
      expect(Live2DStage.hitHer(at(.05, 200), r), isFalse, reason: '头顶不该那么宽');
      // 胸/肩（f≈.4）：满宽
      expect(Live2DStage.hitHer(at(.40, 160), r), isTrue);
      // 裙摆（f≈.75）：再宽 15%
      expect(Live2DStage.hitHer(at(.75, 200), r), isTrue);
      // 头顶以上 / 脚底以下 / 屏幕另一侧 → 都不算戳到她
      expect(Live2DStage.hitHer(Offset(cx, r.top - 4), r), isFalse);
      expect(Live2DStage.hitHer(Offset(cx, r.bottom + 4), r), isFalse);
      expect(Live2DStage.hitHer(at(.5, -400), r), isFalse);
    });

    test('相机变了矩形跟着变（推镜头是布局矩形在动）', () {
      final Rect lobby = Live2DStage.stageRect(
        Cam.byName('lobby'),
        const Size(390, 844),
      );
      final Rect talk = Live2DStage.stageRect(
        Cam.byName('talk'),
        const Size(390, 844),
      );
      expect(talk.height, greaterThan(lobby.height), reason: 'talk s=1.70 > lobby s=.92');
      expect(talk.center.dy, lessThan(lobby.center.dy));
    });
  });

  group('表演补完（2026-10-11 · STAGE-OPTIONS「表演补完」节）', () {
    test('表情表 = 28 原版 + 4 个 exp_sys_* 合成（尾部追加，早期下标不动）', () {
      expect(Live2DStage.expressions.length, 32);
      expect(Live2DStage.expressions.sublist(28), <String>[
        'exp_sys_lid05',
        'exp_sys_lid35',
        'exp_sys_sleep',
        'exp_sys_wake',
      ]);
      // 字母序不变式（转换器与名表靠同一排序对齐下标）
      for (int i = 1; i < Live2DStage.expressions.length; i++) {
        expect(
          Live2DStage.expressions[i - 1].compareTo(Live2DStage.expressions[i]),
          lessThan(0),
          reason: '表情表不是字母序：${Live2DStage.expressions[i - 1]} ≥ ${Live2DStage.expressions[i]}',
        );
      }
    });

    test('基底组 = "Idle" 别名（插件字面约定），与 17 个语义组不混', () {
      expect(Live2DStage.baseGroup, 'Idle');
      expect(Live2DStage.motionGroups, isNot(contains('Idle')),
          reason: 'Idle 是基底别名，不进动词桥接表');
    });

    // 本机有转换产物（gitignore，版权红线）时核对名表与产物逐条一致；
    // 新克隆没跑过转换器就跳过 —— 没有「模型可核对」这回事。
    test('名表 ↔ sakiko.model3.json 一致（有产物时）', () {
      final File f = File('assets/live2d/sakiko/sakiko.model3.json');
      if (!f.existsSync()) {
        // ignore: avoid_print
        print('跳过：本机没有转换产物（先跑 python tools/l2d/convert.py）');
        return;
      }
      final Map<String, dynamic> j =
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final Map<String, dynamic> refs =
          j['FileReferences'] as Map<String, dynamic>;
      final List<dynamic> exps = refs['Expressions'] as List<dynamic>;
      expect(
        exps.map((dynamic e) => (e as Map<String, dynamic>)['Name']),
        Live2DStage.expressions,
        reason: '表情名表与 model3.json 顺序不一致 —— 改了转换器要同步名表',
      );
      final Map<String, dynamic> motions =
          refs['Motions'] as Map<String, dynamic>;
      expect(motions.containsKey('Idle'), isTrue,
          reason: 'model3.json 缺 "Idle" 别名组 —— 待机会冻结（插件字面约定）');
      // 变体数表必须与产物一致（组内随机取变体就靠它，错了会越界/退化成 1）
      for (final String g in Live2DStage.motionCounts.keys) {
        expect(motions.containsKey(g), isTrue, reason: 'model3.json 缺组 $g');
        expect(
          Live2DStage.motionCounts[g],
          (motions[g] as List<dynamic>).length,
          reason: '$g 的变体数与 model3.json 不一致',
        );
      }
      for (final String g in Live2DStage.motionGroups) {
        expect(Live2DStage.countOf(g), greaterThan(0));
      }
      expect((motions['Idle'] as List<dynamic>).length, 1);
      for (final String g in Live2DStage.motionGroups) {
        expect(motions.containsKey(g), isTrue, reason: 'model3.json 缺语义组 $g');
      }
    });
  });
}
