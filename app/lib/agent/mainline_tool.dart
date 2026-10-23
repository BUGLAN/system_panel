/// `set_plan` —— 「她」在 agent 循环里**拆计划**（docs/34 起，不再拆「环」）。
///
/// ═══════════════════════════════════════════════════════════
///  这是目标拆解的**唯一**实现路径
/// ═══════════════════════════════════════════════════════════
///  2026-10-23 宿主定调：
///    · 拆解必须是 Agent 的一个 tool，由 Agent 调，不是单独写死的流程；
///    · 工具入参**沿用既有 schema**（short/title/proof/minutes/rank），
///      字段、类型、输出结构一个字都不许漂 —— 下游 `PlanTask` 直接吃它；
///    · 形状不对**不许**回填给模型「让它再试」：那是把失败藏进多轮循环。
///      一律抛 [PlanShapeError]，让调用方当场看到哪一张哪个字段坏了。
///
///  ⚠️ 只暂存、不落库：[PlanDraft] 收下任务池，真正铸计划交给
///     `goal_gen.buildGoalFromPlan`（它会再跑一遍规则校验，不合格就抛）。
library;

import '../data/rarity.dart';
import '../state/goal_gen.dart';
import '../state/plan_failure.dart';
import 'tools.dart';

/// 任务池草案 —— 工具把解析好的任务放这儿，调用方取走。
class PlanDraft {
  /// 工具成功交上来的任务（形状已校验）。null = 她还没交。
  List<TaskSpec>? tasks;

  /// 她交了几次（诊断用）
  int attempts = 0;
}

/// 拆计划工具的 JSON Schema。`taskCount` 写进描述里，让模型知道要几条。
///
/// **这是任务卡片的唯一 schema 真源**：字段名、类型、枚举、必填项都钉在这里，
/// 对应 `TaskSpec`（`goal_gen.dart`）与 `PlanTask`（`goal.dart`）。
/// 改它 = 改存档格式，先改 docs/34 与两个数据类，再改这里。
Map<String, dynamic> setPlanSchema(int taskCount) => <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'tasks': <String, dynamic>{
      'type': 'array',
      'minItems': taskCount,
      'maxItems': taskCount,
      'description':
          '正好 $taskCount 张，一张一天，按时间先后排。'
          '每一张都是**一次能做完**的具体动作（不要写「坚持一个月」这种跨度几周的事，'
          '也不要写「努力」「拆解目标」这类空话）。'
          '**必须贴着目标本身写**：目标里的动作、次数、周期要出现在题面上'
          '（例：「两周骑 10 次」就要写出骑多久/骑多远，而不是「把目标写在纸上」）。'
          '难度与耗时逐张递增，档位不许倒退；最后一张是**兑现单**：'
          'S 级、一次能证明目标达成的验证动作。'
          '访谈答案里他亲口说的数字（能跑多远、一周几次、几点睡）必须用进题面。',
      'items': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'short': <String, dynamic>{
            'type': 'string',
            'description': '短标签，不超过 4 个字，显示在进度带上',
          },
          'title': <String, dynamic>{
            'type': 'string',
            'description': '一句话行动，不超过 20 字，写清做什么、做多久',
          },
          'proof': <String, dynamic>{
            'type': 'string',
            'description': '要拍什么当证据（截图/照片/录音），不超过 10 字',
          },
          'minutes': <String, dynamic>{
            'type': 'integer',
            'description': '预计耗时（分钟），5~180',
          },
          'rank': <String, dynamic>{
            'type': 'string',
            'enum': Rarity.ranks,
            'description': '难度档位 F~S（F 最轻、S 最重）',
          },
        },
        'required': <String>['short', 'title', 'proof', 'minutes', 'rank'],
      },
    },
  },
  'required': <String>['tasks'],
};

/// 造一个「拆这份计划」的工具。
///
/// [goalText] / [days] / [taskCount] 一并写进 description，让她知道这次拆的是
/// 哪句话、期限多长、要交几张。
///
/// **失败一律抛**（[PlanShapeError]）：条数不对、字段空、档位非法、分钟数非正。
AgentTool setPlanTool({
  required String goalText,
  required int taskCount,
  required int days,
  required PlanDraft draft,
  void Function()? onStaged,
}) {
  return AgentTool(
    name: 'set_plan',
    description:
        '把宿主的目标「$goalText」（期限 $days 天）拆成 $taskCount 张任务、交上来当计划。'
        '调用前先用 get_status 看他的现状（等级/连败/最弱维），'
        '必要时用 recall 翻一下他以前说过什么。必须正好 $taskCount 张。',
    parameters: setPlanSchema(taskCount),
    run: (Map<String, dynamic> args) async {
      draft.attempts++;
      final Object? raw = args['tasks'];
      if (raw is! List || raw.isEmpty) {
        throw PlanShapeError(-1, 'tasks', 'tasks 必须是数组，且正好 $taskCount 张，实际给了 ${raw is List ? raw.length : raw.runtimeType}');
      }
      if (raw.length != taskCount) {
        throw PlanShapeError(
          -1,
          'tasks',
          '计划要正好 $taskCount 张，模型给了 ${raw.length} 张',
        );
      }
      final List<TaskSpec> out = <TaskSpec>[];
      for (int i = 0; i < raw.length; i++) {
        final Object? item = raw[i];
        if (item is! Map) {
          throw PlanShapeError(i, 'tasks', '第 ${i + 1} 张不是对象（是 ${item.runtimeType}）');
        }
        final String short = _str(item['short']);
        final String title = _str(item['title']);
        final String proof = _str(item['proof']);
        final String rank = _str(item['rank']).toUpperCase();
        final Object? minutesRaw = item['minutes'];
        final int? minutes = minutesRaw is num
            ? minutesRaw.toInt()
            : int.tryParse(_str(minutesRaw));
        if (short.isEmpty) throw PlanShapeError(i, 'short', '第 ${i + 1} 张的 short 是空的');
        if (title.isEmpty) throw PlanShapeError(i, 'title', '第 ${i + 1} 张的 title 是空的');
        if (proof.isEmpty) throw PlanShapeError(i, 'proof', '第 ${i + 1} 张的 proof 是空的');
        if (!Rarity.ranks.contains(rank)) {
          throw PlanShapeError(i, 'rank', '第 ${i + 1} 张的 rank「${_str(item['rank'])}」不是 ${Rarity.ranks.join('/')}');
        }
        if (minutes == null || minutes <= 0) {
          throw PlanShapeError(i, 'minutes', '第 ${i + 1} 张的 minutes 不是正整数（收到 ${minutesRaw ?? 'null'}）');
        }
        out.add(
          TaskSpec(
            short: short,
            title: title,
            proof: proof,
            minutes: minutes,
            rank: rank,
          ),
        );
      }
      draft.tasks = out;
      onStaged?.call();
      return ToolOutcome.ok(
        '计划收下了：$taskCount 张，'
        '${out.first.short} → … → ${out.last.short}。拿去用一句话告诉他为什么这么排。',
        data: <String, dynamic>{
          'tasks': <Map<String, dynamic>>[
            for (final TaskSpec t in out)
              <String, dynamic>{
                'short': t.short,
                'title': t.title,
                'proof': t.proof,
                'minutes': t.minutes,
                'rank': t.rank,
              },
          ],
        },
      );
    },
  );
}

String _str(Object? v) => v is String ? v.trim() : (v == null ? '' : '$v');

// ═══════════════════════════════════════════════════════════
//  目标匹配（类别 / 天幕短字 / 期限）—— 也走 Agent 的 tool
// ═══════════════════════════════════════════════════════════
//
// 2026-10-23：这里原来是一张**正则关键词表**（`GoalCategory.pattern`）+
// 关键词表（骑行/单车这类词不在表里就落到兜底类别 gen），
// 于是「两周内骑自行车 10 次」被拆成「把目标写在纸上」。
// 现在类别、天幕短字、期限三样都由 Agent 调 `set_goal_category` 决定，
// 规则只负责**校验**（类别 id 必须存在、期限必须在合法区间）。

/// Agent 交上来的匹配结果。
class GoalMatch {
  const GoalMatch({
    required this.cat,
    required this.short,
    required this.days,
    this.quota = 0,
  });

  /// 目标类别（从 [kGoalCatOrder] 里选的，已校验存在）
  final GoalCategory cat;

  /// 天幕大字（≤4 字）
  final String short;

  /// 期限（天）—— 由她按目标本身的周期读出来，不是关键词表猜的
  final int days;

  /// 目标自带的**次数配额**（「骑 10 次」就是 10；不是次数型目标给 0）。
  /// 清单条数按它定，见 `goal_gen.planTaskCountFor`。
  final int quota;
}

/// 匹配工具的草案（工具写、调用方取）。
class GoalMatchDraft {
  GoalMatch? match;

  /// 她调了几次（诊断用）
  int attempts = 0;
}

/// 类别 id 的枚举（schema 用）——**模型只能从这十个里选**。
List<String> get goalCategoryIds =>
    <String>[for (final GoalCategory c in kGoalCatOrder) c.id];

/// 匹配工具的 JSON Schema。
Map<String, dynamic> setGoalCategorySchema() => <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'id': <String, dynamic>{
      'type': 'string',
      'enum': goalCategoryIds,
      'description':
          '目标类型。按目标**真正的动作**选，不要因为词表里没有就选 gen：'
          '骑行/游泳/爬山都算 run（耐力运动）；球类/格斗算 fit；'
          '读书/写作/学习算 exam 或 make；只有确实无法归类才用 gen。',
    },
    'short': <String, dynamic>{
      'type': 'string',
      'description': '天幕上的大字，不超过 4 个字，取目标里最有辨识度的那个词（如「骑自行车」「半马」）',
    },
    'days': <String, dynamic>{
      'type': 'integer',
      'description':
          '期限天数。按目标里写的周期读：一周 7 / 两周 14 / 一个月 30 / '
          '三个月 90 / 半年 180 / 一年 365；没写周期就按这件事**合理需要多久**给一个，'
          '不要留空。',
    },
    'quota': <String, dynamic>{
      'type': 'integer',
      'description':
          '目标自带的**次数配额**：目标里写「10 次」就给 10，「每周 3 次」按总次数给；'
          '不是次数型目标（如「三个月跑完半马」）就给 0。'
          '⚠️ 清单条数按它算，所以填错会直接改变计划规模。',
    },
  },
  'required': <String>['id', 'short', 'days', 'quota'],
};

/// 造一个「匹配这个目标」的工具。
AgentTool setGoalCategoryTool({
  required String goalText,
  required GoalMatchDraft draft,
  void Function()? onStaged,
}) => AgentTool(
  name: 'set_goal_category',
  description:
      '判断宿主的目标「$goalText」属于哪一类、天幕短字写什么、期限多少天。'
      '先看清目标本身的动作与周期，再交上来。',
  parameters: setGoalCategorySchema(),
  run: (Map<String, dynamic> args) async {
    draft.attempts++;
    final Object? rawId = args['id'];
    final String id = rawId is String ? rawId.trim() : '';
    // ⚠️ 2026-10-23 真机实测：本地微调模型会自造 id（例如把骑行目标写成
    //    `cycling_10_in_2_weeks`），即使 schema 里给了 enum。
    //    这里**不做模糊匹配、不猜**（那会把失败藏起来），但把可选值原样
    //    摆回错误里 —— Agent 看到 detail 会照着重交一次，仍不对就抛给开发者。
    final GoalCategory? cat = goalCats[id];
    if (cat == null) {
      throw PlanShapeError(
        -1,
        'id',
        '类别「$id」不在可选列表里。必须从这几个 id 里选一个：'
        '${goalCategoryIds.join(' / ')}',
      );
    }
    final Object? rawShort = args['short'];
    final String short = rawShort is String ? rawShort.trim() : '';
    if (short.isEmpty) {
      throw const PlanShapeError(-1, 'short', '天幕短字是空的');
    }
    final Object? rawDays = args['days'];
    final int? days = rawDays is num ? rawDays.toInt() : int.tryParse('$rawDays');
    if (days == null) {
      throw PlanShapeError(-1, 'days', '期限不是整数（收到 $rawDays）');
    }
    if (days < kPlanMinTasks || days > kPlanMaxTasks) {
      throw PlanShapeError(
        -1,
        'days',
        '期限 $days 天不在 $kPlanMinTasks~$kPlanMaxTasks 之间',
      );
    }
    final Object? rawQuota = args['quota'];
    final int? quota = rawQuota is num
        ? rawQuota.toInt()
        : int.tryParse('$rawQuota');
    if (quota == null || quota < 0) {
      throw PlanShapeError(-1, 'quota', '次数配额不是非负整数（收到 $rawQuota）');
    }
    if (quota > kPlanMaxTasks) {
      throw PlanShapeError(-1, 'quota', '次数配额 $quota 超过上限 $kPlanMaxTasks');
    }
    draft.match = GoalMatch(cat: cat, short: short, days: days, quota: quota);
    onStaged?.call();
    return ToolOutcome.ok(
      '记下了：${cat.label}（${cat.id}）· 天幕「$short」· 期限 $days 天 · '
      '次数配额 ${quota == 0 ? '无' : '$quota 次'}。',
      data: <String, dynamic>{
        'id': cat.id,
        'short': short,
        'days': days,
        'quota': quota,
      },
    );
  },
);
