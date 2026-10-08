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

    test('每种情绪都能在 28 表情表里查到下标（≥0）', () {
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
    // 大厅（s=.92, syF=.505）在 390×844 下：她应占屏高 92%、顶 ~4.5%、底 ~96.5%
    test('stageRect：大厅矩形 = 中心 ± 屏高×s（数学对照原型相机表）', () {
      final Rect r = Live2DStage.stageRect(
        Cam.byName('lobby'),
        const Size(390, 844),
      );
      expect(r.height, closeTo(844 * .92, .5));
      expect(r.width, closeTo(844 * .92, .5));
      expect(r.center.dx, closeTo(390 * .5, .5));
      expect(r.center.dy, closeTo(844 * .505, .5));
      // 顶/底落在原型标定值附近（顶 ~4.5%H、底 ~96.5%H）
      expect(r.top / 844, closeTo(.045, .01));
      expect(r.bottom / 844, closeTo(.965, .01));
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
}
