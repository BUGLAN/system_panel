import 'dart:async';

import '../agent/vision.dart';

/// ═══════════════════════════════════════════════════════════
///  证据后台校验的在途表（docs/50 C7 定案：证据改后台异步校验、提交时出结果）
///
///  执行页选好图立刻入槽，校验在这里登记、在后台跑；槽位按 id 问
///  [isChecking] 画「校验中」。点「提交任务」时用 [waitFor] 等本单还在途的
///  校验结束（上限 [kSubmitWait]）—— 等不到的照收、按未校验计（「没校验成」口径）。
///
///  纯 Dart、不碰 UI，结论怎么落槽由调用方的 `onDone` 决定
///  （主壳里是 `QuestFlow.applyVerdict`）。
/// ═══════════════════════════════════════════════════════════
class EvidenceChecks {
  EvidenceChecks({this.submitWait = kSubmitWait});

  /// 提交时最多等多久（单张图校验实测约 18s，见 docs/50 C7）
  static const Duration kSubmitWait = Duration(seconds: 20);

  final Duration submitWait;

  /// 证据 id → 「校验结束且结论已交给 onDone」的信号
  final Map<String, Future<void>> _inflight = <String, Future<void>>{};

  /// 这张证据还在校验吗
  bool isChecking(String id) => _inflight.containsKey(id);

  /// 这些证据里有没有还在校验的
  bool anyChecking(Iterable<String> ids) => ids.any(_inflight.containsKey);

  /// 登记一次后台校验。[check] 结束后先出表、再把结论交给 [onDone]；
  /// [check] 抛异常按「未校验」处理（兜底铁律：校验失败永不阻塞提交）。
  void start(
    String id,
    Future<VisionVerdict> check,
    void Function(VisionVerdict v) onDone,
  ) {
    final Completer<void> done = Completer<void>();
    _inflight[id] = done.future;
    check
        .then<VisionVerdict>(
          (VisionVerdict v) => v,
          onError: (Object _) => const VisionVerdict.unverified('校验失败'),
        )
        .then((VisionVerdict v) {
          if (identical(_inflight[id], done.future)) _inflight.remove(id);
          try {
            onDone(v);
          } finally {
            done.complete();
          }
        });
  }

  /// 提交前：等 [ids] 里还在途的校验结束（结论已经落槽），最多等 [timeout]
  /// （缺省 [submitWait]）。全等到了 → true；超时 → false（没等到的照收）。
  Future<bool> waitFor(Iterable<String> ids, {Duration? timeout}) async {
    final List<Future<void>> pending = <Future<void>>[
      for (final String id in ids)
        if (_inflight[id] case final Future<void> f) f,
    ];
    if (pending.isEmpty) return true;
    try {
      await Future.wait(pending).timeout(timeout ?? submitWait);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}
