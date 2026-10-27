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
  });

  /// 宿主那句话（原样，不裁剪）
  final String goalText;

  /// 期限（天）—— 由 `GoalMatchAgent` 交的 `set_goal_category.days` 决定，
  /// **条数跟着它走**（`planTaskCountFor(days)`）
  final int days;

  /// 要交几张（= `planTaskCountFor(days)`；由调用方算好，Agent 不猜）
  final int taskCount;

  /// 目标类别（决定六维倾向与访谈卡）
  final GoalCategory cat;

  /// 访谈答案（卡 id → 答案原文）
  final Map<String, String> interview;

  /// 宿主档案一行（等级/连击/最弱维/当前主线）
  final String? statusLine;

  /// 首目标（3 天 3 张 E/D/C，docs/05）
  final bool firstGoal;

  /// 交给模型的「这一单要拆什么」正文（**期限与条数必须写进来**，
  /// 旧实现漏了它们，模型只能按「有进阶关系」的通用口径瞎编）。
  String get userText {
    final StringBuffer b = StringBuffer()
      ..writeln('宿主立了目标：「$goalText」。')
      ..writeln(
        '期限 $days 天，清单要正好 $taskCount 张（= 期限天数），'
        '第 $taskCount 张是兑现单。',
      )
      ..writeln('目标类型：${cat.label}（${cat.id}）。');
    if (interview.isNotEmpty) {
      b.writeln('访谈答案（他亲口说的，必须用进拆解）：');
      for (final MapEntry<String, String> e in interview.entries) {
        b.writeln('- ${_questionOf(e.key)} → ${e.value}');
      }
    }
    if (firstGoal) {
      b.writeln('这是**首目标**：3 张，档位只能 E/D/C，一张一天，先验证他能坚持。');
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
      ..writeln('兑现单（最后一张）时限必须 ≥ $kPlanFinalMinutes 分钟。');
    b
      ..writeln()
      ..writeln('用 set_plan 把这 $taskCount 张交上来。');
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
      '拆计划：把宿主刚说的目标「$goalText」拆成 $taskCount 张单次可执行的任务，'
      '期限 $days 天。先看清他现在的状态（get_status），必要时 recall 翻记忆，'
      '再用 set_plan 交上来。';
}
