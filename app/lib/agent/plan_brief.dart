/// 目标拆解的**简报** —— 调用方（main.dart / 测试）给 Agent 的输入。
///
/// 拆解只认这一份：目标一句话 + 期限 + 要交几张 + 类别 + 访谈答案 + 宿主档案。
/// 没有它就等于没有上下文（旧实现只喂一句话，于是模型只能编空话）。
library;

import '../state/goal_gen.dart';

class PlanBrief {
  const PlanBrief({
    required this.goalText,
    required this.days,
    required this.taskCount,
    required this.cat,
    this.interview = const <String, String>{},
    this.statusLine,
    this.firstGoal = false,
    this.segment,
    this.window,
    this.progress,
  });

  /// 同一份简报换成「只拆其中一段」（长清单分段并行拆）
  PlanBrief forSegment(PlanSegment? seg) => PlanBrief(
    goalText: goalText,
    days: days,
    taskCount: taskCount,
    cat: cat,
    interview: interview,
    statusLine: statusLine,
    firstGoal: firstGoal,
    segment: seg,
    window: window,
    progress: progress,
  );

  /// 宿主那句话（原样，不裁剪）
  final String goalText;

  /// 期限（天）—— 由 `GoalMatchAgent` 交的 `set_goal_category.days` 决定，
  /// **总张数跟着它走**（`planTaskCountFor(days)`）
  final int days;

  /// 这一轮要交几张（滚动生成 = 窗口张数；由调用方算好，Agent 不猜）
  final int taskCount;

  /// 目标类别（决定六维倾向与访谈卡）
  final GoalCategory cat;

  /// 访谈答案（卡 id → 答案原文）
  final Map<String, String> interview;

  /// 宿主档案一行（等级/连击/最弱维/当前主线）
  final String? statusLine;

  /// 首目标第一段（档位只许 E/D/C）
  final bool firstGoal;

  /// 非空 = 这一轮只拆窗口里的一段（段数 > 1 时才会给）
  final PlanSegment? segment;

  /// 滚动生成的窗口（整条主线里第几段、第几~几张）。
  /// null = 老口径：[taskCount] 就是整份清单，一次拆完。
  final PlanWindow? window;

  /// 续拆时「前面做到了哪里」（`goal_gen.planProgressDigest`）；首段为 null
  final String? progress;

  /// 实际生效的窗口（null 时按整份清单一个窗口算）
  PlanWindow get win =>
      window ?? PlanWindow.whole(taskCount, firstGoal: firstGoal);

  /// 交给模型的「这一单要拆什么」正文（**期限与条数必须写进来**，
  /// 旧实现漏了它们，模型只能按「有进阶关系」的通用口径瞎编）。
  String get userText {
    final PlanSegment? seg = segment;
    final PlanWindow w = win;
    final StringBuffer b = StringBuffer()..writeln('宿主立了目标：「$goalText」。');
    if (w.whole) {
      b.writeln(
        '期限 $days 天，清单要正好 ${w.total} 张（= 期限天数），'
        '${w.last ? '第 ${w.total} 张是兑现单。' : '这一份不摆兑现单。'}',
      );
    } else {
      // 滚动生成：每次只拆一段，做完再拆下一段（docs/50 C1 定案）
      b
        ..writeln(
          '期限 $days 天，整条主线共 ${w.total} 张。清单**滚动生成**：'
          '每次只拆一段，他做完这一段再拆下一段。',
        )
        ..writeln(
          '**这一轮是第 ${w.index + 1}/${w.count} 段：第 ${w.from}~${w.to} 张，'
          '共 ${w.size} 张**。档位只能在 ${w.lo}~${w.hi} 之间，逐张不许倒退。'
          '${w.last ? '本段最后一张（第 ${w.total} 张）就是整条主线的兑现单，必须 S 级。' : '本段不含兑现单（兑现单在最后一段），不要提前收尾。'}',
        );
    }
    final String? done = progress;
    if (done != null && done.trim().isNotEmpty) {
      b
        ..writeln('前面做到了哪里（接着往下排，别重复）：')
        ..writeln(done.trim());
    }
    if (seg != null) {
      b
        ..writeln(
          '这一段分 ${seg.count} 份同时拆。**你只负责第 ${seg.index + 1} 份：'
          '第 ${seg.from}~${seg.to} 张，共 ${seg.size} 张**。',
        )
        ..writeln('本段阶段：${seg.phase}。')
        ..writeln(
          '本段档位只能在 ${seg.lo}~${seg.hi} 之间，段内逐张不许倒退。'
          '${seg.last ? '本段最后一张（第 ${seg.to} 张）就是整条主线的兑现单，必须 S 级。' : '本段不含兑现单。'}',
        );
    }
    b.writeln('目标类型：${cat.label}（${cat.id}）。');
    if (interview.isNotEmpty) {
      b.writeln('访谈答案（他亲口说的，必须用进拆解）：');
      for (final MapEntry<String, String> e in interview.entries) {
        b.writeln('- ${_questionOf(e.key)} → ${e.value}');
      }
    }
    if (firstGoal) {
      b.writeln('这是**首目标的第一段**：档位只能 E/D/C，一张一天，先验证他能坚持。');
    }
    // ⚠️ 档位时限上限必须写进提示词。真机实测：模型不知道这条阶梯，
    //    给了「D 档 45 分钟」，`validatePlan` 直接抛
    //    「时限 45 分钟越界（D 档允许 5~40）」，整次拆解白跑。
    b
      ..writeln('每张的 minutes 必须落在档位上限之内（超了整份作废）：')
      ..writeln(
        <String>[
          for (final String r in <String>['F', 'E', 'D', 'C', 'B', 'A', 'S'])
            '$r ≤ ${rankCapMinutes(r)} 分钟',
        ].join(' · '),
      )
      ..writeln(
        (seg == null ? w.last : seg.last)
            ? '兑现单（最后一张）时限必须 ≥ $kPlanFinalMinutes 分钟。'
            : '',
      );
    // 计时 / 打卡（docs/50 C3）：全天类动作配倒计时会逼他「5 分钟内上秤」
    b
      ..writeln(
        '每张标 mode：一天内分散完成、或瞬间就能完成的动作'
        '（称重、拍三餐、量腰围、早睡打卡）标 "checkin"（打卡：不计时、随时传证据提交）；'
        '需要连续投入一段时间的（跑步、练琴、刷题）标 "timed"（计时）。',
      )
      ..writeln('打卡单的 minutes 照样填预计耗时（同样不许超档位上限），只作参考、不倒计时。');
    b
      ..writeln()
      ..writeln(
        seg == null
            ? '用 set_plan 把这 ${w.size} 张交上来'
                  '${w.whole ? '' : '（第 ${w.from}~${w.to} 张，不要交别的段）'}。'
            : '用 set_plan 只把本段这 ${seg.size} 张交上来（第 ${seg.from}~${seg.to} 张，不要交别的段）。',
      );
    return b.toString().trim();
  }

  /// 卡 id → 问题原文（把访谈答案还原成「问题 → 答案」，模型才读得懂）
  String _questionOf(String cardId) {
    for (final InterviewCard c in cat.cards) {
      if (c.id == cardId) return c.question;
    }
    return switch (cardId) {
      'common.slot' => '一周愿意投入几个时段？',
      'common.history' => '上次立目标是什么结果？',
      _ => cardId,
    };
  }

  /// 她这一轮的场合（system prompt 的【当前场合】位）
  String get scenario =>
      '拆计划：把宿主的目标「$goalText」拆成单次可执行的任务，'
      '期限 $days 天、整条主线共 ${win.total} 张'
      '${segment != null ? '（这一轮只拆第 ${segment!.from}~${segment!.to} 张）' : (win.whole ? '' : '（滚动生成：这一轮只拆第 ${win.from}~${win.to} 张）')}。'
      '他现在的状态（等级/连败/最弱维）与相关记忆已经写在上面的'
      '宿主档案里，直接据此拆，用 set_plan 一次交上来。';
}
