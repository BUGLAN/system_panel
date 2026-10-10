import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/stage/camera.dart';
import 'package:system_panel/stage/live2d_stage.dart';
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

    test('poke 自带表情覆盖 exp_shy01；未知动词回落 nod 不炸', () {
      expect(StageBridges.verbExp['poke'], 'exp_shy01');
      expect(
        StageBridges.verbExpIndex('poke'),
        Live2DStage.expressions.indexOf('exp_shy01'),
      );
      expect(StageBridges.verbExpIndex('nod'), -1);
      expect(StageBridges.isVerb('down'), isTrue);
      expect(StageBridges.isVerb('不存在'), isFalse);
      expect(StageBridges.groupOf('不存在'), 'nod', reason: '兜底不静默丢弃');
    });
  });

  group('待机池（stage.js IDLE_POOL）', () {
    test('三档心情的池都非空且 ⊆ 17 组', () {
      expect(StageBridges.idlePool.keys.toSet(), <String>{
        'cold', 'pleased', 'neutral',
      });
      for (final MapEntry<String, List<String>> e
          in StageBridges.idlePool.entries) {
        expect(e.value, isNotEmpty, reason: '${e.key} 池空了');
        for (final String g in e.value) {
          expect(
            Live2DStage.motionGroups.contains(g),
            isTrue,
            reason: '${e.key} 池里的 $g 不是合法组',
          );
        }
      }
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
      expect((motions['Idle'] as List<dynamic>).length, 1);
      for (final String g in Live2DStage.motionGroups) {
        expect(motions.containsKey(g), isTrue, reason: 'model3.json 缺语义组 $g');
      }
    });
  });
}
