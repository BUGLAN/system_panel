import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/agent/vision.dart';
import 'package:system_panel/state/evidence_checks.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';

/// docs/50 C4 + C7：证据先入槽、后台校验；不符拒收；提交等在途校验。
void main() {
  EvidenceShot shot(String id) => EvidenceShot(
    id: id,
    path: '',
    status: EvidenceStatus.unverified,
    takenAt: DateTime(2026, 11, 5),
  );

  group('EvidenceChecks · 在途表', () {
    test('start 后 isChecking；结论回来先出表、再交给 onDone', () async {
      final EvidenceChecks c = EvidenceChecks();
      final Completer<VisionVerdict> llm = Completer<VisionVerdict>();
      VisionVerdict? got;
      bool checkingInsideDone = true;
      c.start('a', llm.future, (VisionVerdict v) {
        got = v;
        checkingInsideDone = c.isChecking('a');
      });
      expect(c.isChecking('a'), isTrue);
      expect(c.anyChecking(<String>['x', 'a']), isTrue);
      expect(c.anyChecking(<String>['x']), isFalse);

      llm.complete(const VisionVerdict.unsure('太糊'));
      await c.waitFor(<String>['a']);
      expect(got?.status, EvidenceStatus.unsure);
      expect(checkingInsideDone, isFalse);
      expect(c.isChecking('a'), isFalse);
    });

    test('校验抛异常 → 按「未校验」交结论（兜底铁律）', () async {
      final EvidenceChecks c = EvidenceChecks();
      VisionVerdict? got;
      c.start(
        'a',
        Future<VisionVerdict>.error(StateError('炸了')),
        (VisionVerdict v) => got = v,
      );
      expect(await c.waitFor(<String>['a']), isTrue);
      expect(got?.status, EvidenceStatus.unverified);
    });

    test('没有在途的 → waitFor 立即 true', () async {
      final EvidenceChecks c = EvidenceChecks();
      expect(await c.waitFor(<String>['a', 'b']), isTrue);
    });

    test('提交会等在途校验：结论落槽之后 waitFor 才返回', () async {
      final EvidenceChecks c = EvidenceChecks();
      final Completer<VisionVerdict> llm = Completer<VisionVerdict>();
      final List<String> log = <String>[];
      c.start('a', llm.future, (VisionVerdict v) => log.add('verdict'));

      final Future<bool> wait = c.waitFor(<String>['a']).then((bool ok) {
        log.add('submit');
        return ok;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(log, isEmpty, reason: '校验没回来之前不许往下结算');

      llm.complete(const VisionVerdict.verified('可信'));
      expect(await wait, isTrue);
      expect(log, <String>['verdict', 'submit']);
    });

    test('等太久 → 超时返回 false（没等到的照收），不抛', () async {
      final EvidenceChecks c = EvidenceChecks(
        submitWait: const Duration(milliseconds: 30),
      );
      final Completer<VisionVerdict> llm = Completer<VisionVerdict>();
      c.start('a', llm.future, (_) {});
      expect(await c.waitFor(<String>['a']), isFalse);
      expect(c.isChecking('a'), isTrue); // 还在途，迟到的结论照样会落
      llm.complete(const VisionVerdict.verified(''));
    });

    test('只等本单的 id：别的证据还在途也不拦', () async {
      final EvidenceChecks c = EvidenceChecks(
        submitWait: const Duration(milliseconds: 30),
      );
      final Completer<VisionVerdict> other = Completer<VisionVerdict>();
      c.start('old', other.future, (_) {});
      expect(await c.waitFor(<String>['mine']), isTrue);
      other.complete(const VisionVerdict.verified(''));
    });

    test('默认上限 20s（docs/50 C7：单张图校验约 18s）', () {
      expect(EvidenceChecks.kSubmitWait, const Duration(seconds: 20));
      expect(EvidenceChecks().submitWait, const Duration(seconds: 20));
    });
  });

  group('C4 + C7 端到端（EvidenceChecks + QuestFlow.applyVerdict）', () {
    late QuestFlow f;
    late EvidenceChecks c;
    final List<String> rejected = <String>[];

    /// 主壳 `_admitEvidence` + `_onEvidenceVerdict` 的同款接线
    void admit(EvidenceShot s, Future<VisionVerdict> check) {
      expect(f.addEvidence(s), isTrue);
      c.start(s.id, check, (VisionVerdict v) {
        if (f.applyVerdict(s.id, v) == EvidenceApply.rejected) {
          rejected.add('${s.id}:${v.note}');
        }
      });
    }

    setUp(() {
      f = QuestFlow(host: HostState.empty, goal: Goal.demo());
      f.accept(Quest.demo);
      c = EvidenceChecks();
      rejected.clear();
    });

    test('mismatch 被拒：撤出槽位、带原因', () async {
      admit(
        shot('flower'),
        Future<VisionVerdict>.value(const VisionVerdict.mismatch('这是花')),
      );
      expect(f.active!.photos, 1, reason: '选好图立刻入槽');
      await c.waitFor(<String>['flower']);
      expect(f.active!.photos, 0);
      expect(rejected, <String>['flower:这是花']);
    });

    test('unsure 被收', () async {
      admit(
        shot('blur'),
        Future<VisionVerdict>.value(const VisionVerdict.unsure('太糊')),
      );
      await c.waitFor(<String>['blur']);
      expect(f.active!.photos, 1);
      expect(f.active!.evidence.single.status, EvidenceStatus.unsure);
      expect(rejected, isEmpty);
    });

    test('断网 unverified 被收', () async {
      admit(
        shot('offline'),
        Future<VisionVerdict>.value(
          const VisionVerdict.unverified('校验失败：网络不可达'),
        ),
      );
      await c.waitFor(<String>['offline']);
      expect(f.active!.photos, 1);
      expect(f.active!.evidence.single.status, EvidenceStatus.unverified);
      expect(rejected, isEmpty);
    });

    test('提交等在途校验：等完再看槽 —— 被拒的那张不进结算', () async {
      final Completer<VisionVerdict> slow = Completer<VisionVerdict>();
      admit(
        shot('ok'),
        Future<VisionVerdict>.value(const VisionVerdict.verified('可信')),
      );
      admit(shot('bad'), slow.future);
      final List<String> ids = <String>[
        for (final EvidenceShot s in f.active!.evidence) s.id,
      ];
      expect(c.anyChecking(ids), isTrue);

      Timer(const Duration(milliseconds: 10), () {
        slow.complete(const VisionVerdict.mismatch('对不上'));
      });
      expect(await c.waitFor(ids), isTrue);
      expect(c.anyChecking(ids), isFalse);
      expect(f.active!.evidence.map((EvidenceShot s) => s.id), <String>['ok']);
      expect(f.critChance(), closeTo(f.critBase() + .07, 1e-9));
    });
  });
}
