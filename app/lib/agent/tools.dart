/// 小祥的 agent 工具注册表（docs/18 §2.5）。
///
/// 形态：`AgentTool{name, desc, schema, run(args)}`，注册表可扩展——
/// 后续任何页面操作注册一个 AgentTool 就能被对话驱动。
///
/// **QuestFlow 缝隙**：t2 正在施工 `lib/state/quest_flow.dart`（docs/18 §3.1 契约：
/// bind/newGoal/rollDay/head/accept/settle/fail/retreat/…）。本文件**不 import**它，
/// 只定义 [AgentContext] 抽象作为接缝；集成任务（t12）用几行适配器把真实
/// QuestFlow/存档接进来，[MockAgentContext] 是替换前的可运行占位（demo 档语义）。
///
/// **安全钳制**：工具只改队列/计划（换单、改时限、降档），**不直接改经验/金币**
/// ——数值只能经结算入账。见 defaultAgentTools 与测试。
library;

import '../data/rarity.dart';
import '../state/goal.dart';
import '../state/plan_failure.dart';
import '../state/host_state.dart';
import '../state/quest.dart';
import 'memory.dart';

/// 一个工具调用的回执：ok=成功；message 给人看（聊天气泡/回执条），data 给程序。
class ToolOutcome {
  const ToolOutcome({required this.ok, required this.message, this.data});

  const ToolOutcome.ok(String message, {Map<String, dynamic>? data})
    : this(ok: true, message: message, data: data);

  const ToolOutcome.fail(String message, {Map<String, dynamic>? data})
    : this(ok: false, message: message, data: data);

  final bool ok;
  final String message;
  final Map<String, dynamic>? data;
}

/// 工具的实现体：args 来自 LLM 的 function calling 参数（已解析为 Map），
/// 或聊天面板快捷 chip 的直调参数。
typedef AgentToolRun = Future<ToolOutcome> Function(Map<String, dynamic> args);

/// 一个 agent 工具。parameters 是 JSON Schema（OpenAI tools 格式的 parameters 位）。
class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.run,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final AgentToolRun run;

  /// OpenAI function calling 的 tools 数组条目（docs/18 §2.5）
  Map<String, dynamic> toOpenAiTool() => <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// 工具注册表。可扩展：`registry.register(...)` 即接入新能力。
class AgentToolRegistry {
  final Map<String, AgentTool> _tools = <String, AgentTool>{};

  void register(AgentTool tool) => _tools[tool.name] = tool;

  void registerAll(Iterable<AgentTool> tools) {
    for (final AgentTool t in tools) {
      register(t);
    }
  }

  AgentTool? tool(String name) => _tools[name];
  bool contains(String name) => _tools.containsKey(name);
  List<String> get names => _tools.keys.toList();

  /// 全部工具（聊天服务装配 LLM function calling 的 tools 数组用）
  List<AgentTool> get all => _tools.values.toList();
  bool get isEmpty => _tools.isEmpty;
  bool get isNotEmpty => _tools.isNotEmpty;
  int get length => _tools.length;

  /// 给 LLM 请求用的 tools 数组
  List<Map<String, dynamic>> toOpenAiTools() => <Map<String, dynamic>>[
    for (final AgentTool t in _tools.values) t.toOpenAiTool(),
  ];

  /// 执行一个工具。**永不抛**：未知工具、工具内部异常都折成 fail 回执——
  /// 工具链路绝不把 UI 带崩（提交卡死同款事故零容忍）。
  Future<ToolOutcome> execute(String name, [Map<String, dynamic>? args]) async {
    final AgentTool? t = _tools[name];
    if (t == null) {
      return ToolOutcome.fail('没有「$name」这个工具。');
    }
    try {
      return await t.run(args ?? <String, dynamic>{});
    } catch (e) {
      return ToolOutcome.fail('工具 $name 执行出错：$e');
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  AgentContext —— 应用状态缝隙（真实现接 QuestFlow，见文件头）
// ═══════════════════════════════════════════════════════════

/// 工具能摸到的应用状态入口。t12 接线时用真实 QuestFlow 实现这三个方法。
abstract interface class AgentContext {
  /// 查状态：LV/EXP/金币/连击/队列/主线进度（get_status 用）
  Map<String, dynamic> statusSummary();

  /// 换任务：换单券语义（retreat/newGoal 的对话形态）。
  /// 主线单**必须拒绝**（docs/18 §2.7，原型 store.js:254 语义）。
  ToolOutcome swapQuest({String? rank, String? note});

  /// 调整计划：改时限/降档/顺延——只许动队列里的日常/补救单。
  ToolOutcome adjustQuestPlan({
    int? minutes,
    String? rank,
    int? postponeMinutes,
    String? note,
  });

  /// 近 N 天执行记录（summarize_progress 用），条目形如
  /// `{at: DateTime, name: String, rank: String, result: 'done'|'fail'|'crit', minutes: int}`。
  List<Map<String, dynamic>> recentHistory({int days});
}

/// [AgentContext] 的可运行占位：一小块可变世界状态（demo 语义），
/// 供测试与「LLM 未接线时快捷 chip 直调工具」使用；t12 换成 QuestFlow 适配器。
class MockAgentContext implements AgentContext {
  MockAgentContext({
    HostState? host,
    this.goal,
    List<Quest>? queue,
    List<Map<String, dynamic>>? history,
    this.nextCandidate,
    this.onChanged,
  }) : host = host ?? HostState.demo,
       queue = queue ?? <Quest>[],
       history = history ?? <Map<String, dynamic>>[];

  /// 只读字段对接存档；exp/coins/lv 只能由结算改——工具路径不提供写入口。
  HostState host;
  Goal? goal;
  List<Quest> queue;

  /// 执行历史（老→新随意；recentHistory 会过滤）
  final List<Map<String, dynamic>> history;

  /// 换单时的下一张候选单（真实现接 QuestFlow.genDaily/retreat 的产物）
  final Quest? Function()? nextCandidate;

  /// 状态被工具改动后的回调（宿主侧用来存档/刷新 UI）
  final void Function(String action)? onChanged;

  @override
  Map<String, dynamic> statusSummary() {
    final Goal? g = goal;
    final MapEntry<String, int> weakest = host.weakest;
    return <String, dynamic>{
      'name': host.name,
      'lv': host.lv,
      'exp': host.exp,
      'expNeed': HostState.need(host.lv),
      'coins': host.coins,
      'streak': host.streak,
      'bestStreak': host.bestStreak,
      'queue': queue.length,
      'goal': g?.text ?? '',
      'planDone': g?.doneCount ?? 0,
      'planTotal': g?.plan.length ?? 0,
      'weakest': weakest.key,
      'weakestValue': weakest.value,
      'doneCount': host.doneCount,
      'failCount': host.failCount,
      'items': Map<String, int>.of(host.items),
    };
  }

  @override
  ToolOutcome swapQuest({String? rank, String? note}) {
    if (queue.isEmpty) {
      return ToolOutcome.fail('队列是空的。没有可换的单。');
    }
    final Quest head = queue.first;
    if (head.kind == 'main') {
      // docs/18 §2.7：主线单不可换——她直接拒绝
      return ToolOutcome.fail('主线上的单不能换。这是你自己选的目标，要么做完，要么认输重来。');
    }
    final Quest? candidate = nextCandidate?.call();
    if (candidate == null) {
      return ToolOutcome.fail('手里暂时没有备选的单，换不了。');
    }
    queue[0] = candidate;
    onChanged?.call('swap_quest');
    final String why = (note == null || note.trim().isEmpty)
        ? ''
        : '（${note.trim()}）';
    return ToolOutcome.ok(
      '换好了$why。现在是 ${candidate.serialText}「${candidate.name}」'
      '（${candidate.rank} 级 · ${candidate.minutes} 分钟）。',
      data: <String, dynamic>{
        'serial': candidate.serial,
        'name': candidate.name,
        'rank': candidate.rank,
        'minutes': candidate.minutes,
      },
    );
  }

  @override
  ToolOutcome adjustQuestPlan({
    int? minutes,
    String? rank,
    int? postponeMinutes,
    String? note,
  }) {
    if (queue.isEmpty) {
      return ToolOutcome.fail('队列是空的。没有可调整的单。');
    }
    final Quest head = queue.first;
    if (head.kind == 'main') {
      return ToolOutcome.fail('主线单的规格不动。要改的是你自己，不是目标。');
    }
    int newMinutes = head.minutes;
    if (minutes != null) {
      newMinutes = minutes;
    } else if (postponeMinutes != null) {
      newMinutes = head.minutes + postponeMinutes; // 顺延
    }
    newMinutes = newMinutes.clamp(5, 180).toInt();
    String newRank = head.rank;
    if (rank != null && Rarity.table.containsKey(rank.toUpperCase())) {
      newRank = rank.toUpperCase();
    }
    final Quest adjusted = _questWith(head, minutes: newMinutes, rank: newRank);
    queue[0] = adjusted;
    onChanged?.call('adjust_plan');
    return ToolOutcome.ok(
      '改好了：「${adjusted.name}」→ ${adjusted.rank} 级 · ${adjusted.minutes} 分钟。做得到吧？',
      data: <String, dynamic>{
        'serial': adjusted.serial,
        'name': adjusted.name,
        'rank': adjusted.rank,
        'minutes': adjusted.minutes,
      },
    );
  }

  @override
  List<Map<String, dynamic>> recentHistory({int days = 7}) {
    final DateTime since = DateTime.now().subtract(Duration(days: days));
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> e in history) {
      final Object? at = e['at'];
      if (at is DateTime && at.isBefore(since)) continue;
      out.add(e);
    }
    return out;
  }
}

/// 复制一单（Quest 无 copyWith，这里按字段搬）。
Quest _questWith(Quest q, {int? minutes, String? rank}) => Quest(
  serial: q.serial,
  kind: q.kind,
  planIndex: q.planIndex,
  planTotal: q.planTotal,
  goalId: q.goalId,
  name: q.name,
  reason: q.reason,
  proof: q.proof,
  minutes: minutes ?? q.minutes,
  rank: rank ?? q.rank,
  attrs: q.attrs,
  hinted: q.hinted,
);

// ═══════════════════════════════════════════════════════════
//  首发六工具（docs/18 §2.5 表）
// ═══════════════════════════════════════════════════════════

const Map<String, dynamic> _emptySchema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{},
};

Map<String, dynamic> _schema(
  Map<String, dynamic> properties, {
  List<String>? required,
}) => <String, dynamic>{
  'type': 'object',
  'properties': properties,
  if (required != null && required.isNotEmpty) 'required': required,
};

/// 首发六工具：查状态 / 换任务 / 调整计划 / 记住 / 查记忆 / 总结近 7 天。
///
/// [context] 为必接（状态与队列）；[memory] 为必接（remember/recall）。
/// 装配即用，无 LLM 时聊天面板快捷 chip 也能直调。
AgentToolRegistry defaultAgentTools({
  required AgentContext context,
  required MemoryStore memory,
}) {
  final AgentToolRegistry reg = AgentToolRegistry();
  reg.registerAll(<AgentTool>[
    AgentTool(
      name: 'get_status',
      description: '查宿主状态：等级/经验/金币/连击/队列/主线进度。',
      parameters: _emptySchema,
      run: (Map<String, dynamic> args) async {
        final Map<String, dynamic> s = context.statusSummary();
        final String goalLine = (s['goal'] as String? ?? '').isEmpty
            ? '未立目标'
            : '「${s['goal']}」完成 ${s['planDone']}/${s['planTotal']} 单';
        return ToolOutcome.ok(
          'LV${s['lv']} · EXP ${s['exp']}/${s['expNeed']} · ◈${s['coins']} · '
          '连击 ${s['streak']}（最好 ${s['bestStreak']}）\n'
          '主线：$goalLine\n'
          '手里 ${s['queue']} 单 · 完成 ${s['doneCount']} · 战败 ${s['failCount']} · '
          '最弱维：${s['weakest']}${s['weakestValue']}',
          data: s,
        );
      },
    ),
    AgentTool(
      name: 'swap_quest',
      description: '换掉队首的日常/补救单（主线单不可换）。',
      parameters: _schema(<String, dynamic>{
        'rank': <String, dynamic>{
          'type': 'string',
          'description': '期望档位 F~S，可省略',
        },
        'note': <String, dynamic>{'type': 'string', 'description': '换单理由，可省略'},
      }),
      run: (Map<String, dynamic> args) async => context.swapQuest(
        rank: args['rank'] is String ? args['rank'] as String : null,
        note: args['note'] is String ? args['note'] as String : null,
      ),
    ),
    AgentTool(
      name: 'adjust_plan',
      description: '调整队首日常/补救单的计划：改时限（分钟）、改档位、顺延。主线单不可调。',
      parameters: _schema(<String, dynamic>{
        'minutes': <String, dynamic>{
          'type': 'integer',
          'description': '新时限（分钟 5~180）',
        },
        'rank': <String, dynamic>{'type': 'string', 'description': '目标档位 F~S'},
        'postponeMinutes': <String, dynamic>{
          'type': 'integer',
          'description': '顺延的分钟数',
        },
        'note': <String, dynamic>{'type': 'string', 'description': '调整理由，可省略'},
      }),
      run: (Map<String, dynamic> args) async {
        int? minutes;
        int? postpone;
        if (args['minutes'] is int) minutes = args['minutes'] as int;
        if (args['postponeMinutes'] is int)
          postpone = args['postponeMinutes'] as int;
        return context.adjustQuestPlan(
          minutes: minutes,
          rank: args['rank'] is String ? args['rank'] as String : null,
          postponeMinutes: postpone,
          note: args['note'] is String ? args['note'] as String : null,
        );
      },
    ),
    AgentTool(
      name: 'remember',
      description: '把宿主说的话写进长期记忆（重启仍在）。',
      parameters: _schema(
        <String, dynamic>{
          'text': <String, dynamic>{'type': 'string', 'description': '要记住的内容'},
        },
        required: <String>['text'],
      ),
      run: (Map<String, dynamic> args) async {
        final Object? raw = args['text'];
        if (raw is! String || raw.trim().isEmpty) {
          return ToolOutcome.fail('你到底要我记什么？说内容。');
        }
        await memory.add(raw, source: MemorySource.tool, weight: 3);
        return ToolOutcome.ok(
          '记住了：「${raw.trim()}」。',
          data: <String, dynamic>{'text': raw.trim()},
        );
      },
    ),
    AgentTool(
      name: 'recall',
      description: '查长期记忆：按关键词翻宿主说过的话。',
      parameters: _schema(<String, dynamic>{
        'query': <String, dynamic>{
          'type': 'string',
          'description': '关键词，可省略（省略=最近几条）',
        },
      }),
      run: (Map<String, dynamic> args) async {
        final String? q = args['query'] is String
            ? args['query'] as String
            : null;
        final List<MemoryEntry> rel = await memory.relevant(q, limit: 5);
        if (rel.isEmpty) {
          return ToolOutcome.ok('记忆里还没有这一条。');
        }
        return ToolOutcome.ok(
          '翻到了 ${rel.length} 条：\n${rel.map((MemoryEntry e) => '- ${e.text}').join('\n')}',
          data: <String, dynamic>{
            'items': <Map<String, dynamic>>[
              for (final MemoryEntry e in rel)
                <String, dynamic>{'text': e.text, 'at': e.at.toIso8601String()},
            ],
          },
        );
      },
    ),
    AgentTool(
      name: 'summarize_progress',
      description: '总结近 7 天的执行情况（完成/暴击/战败/总时长）。',
      parameters: _emptySchema,
      run: (Map<String, dynamic> args) async {
        final List<Map<String, dynamic>> recent = context.recentHistory();
        int done = 0, crit = 0, fail = 0, minutes = 0;
        final Map<String, int> byName = <String, int>{};
        for (final Map<String, dynamic> e in recent) {
          final String result = e['result'] is String
              ? e['result'] as String
              : '';
          final String name = e['name'] is String
              ? e['name'] as String
              : '（未记录）';
          if (result == 'done' || result == 'crit') done++; // 暴击也是完成
          if (result == 'crit') crit++;
          if (result == 'fail') fail++;
          if (e['minutes'] is int) minutes += e['minutes'] as int;
          byName[name] = (byName[name] ?? 0) + 1;
        }
        String top = '';
        int topN = 0;
        for (final MapEntry<String, int> e in byName.entries) {
          if (e.value > topN) {
            topN = e.value;
            top = e.key;
          }
        }
        if (recent.isEmpty) {
          return ToolOutcome.ok('近 7 天：空白。一张记录都没有，总结无从谈起。');
        }
        return ToolOutcome.ok(
          '近 7 天：执行 ${recent.length} 单，完成 $done（含暴击 $crit）、战败 $fail，'
          '累计 $minutes 分钟${top.isEmpty ? '' : '，做得最多的是「$top」'}。',
          data: <String, dynamic>{
            'total': recent.length,
            'done': done,
            'crit': crit,
            'fail': fail,
            'minutes': minutes,
          },
        );
      },
    ),
  ]);
  return reg;
}

// ═══════════════════════════════════════════════════════════
//  严格注册表（2026-10-23 宿主定调：fail fast，不许吞异常）
// ═══════════════════════════════════════════════════════════

/// 工具执行失败 —— **抛**出来，不再折成 `ToolOutcome.fail` 回执。
///
/// [tool] 是工具名（一眼知道哪一步炸了），[detail] 是人可读原因，
/// [cause] 是原始异常（工具内部抛的那种，带堆栈）。
class ToolExecutionError implements Exception {
  const ToolExecutionError(this.tool, this.detail, {this.cause});

  final String tool;
  final String detail;
  final Object? cause;

  @override
  String toString() =>
      '[tool:$tool] $detail${cause == null ? '' : ' · 原因：$cause'}';
}

/// 严格版注册表：**任何不成功都抛异常**，绝不把失败包成一条"回执"。
///
/// 与 [AgentToolRegistry.execute] 的区别（那张是给聊天用的宽容版）：
///   · 未知工具名 → [ToolExecutionError]
///   · 工具内部抛异常 → 包成 [ToolExecutionError] 抛出（带原因与堆栈）
///   · 工具抛 [PlanFailure]（形状/规则错）→ **原样上抛**，不包一层
///     （code / where 这些字段是调用方分流用的，包掉就丢了）
///   · 工具返回 `ok == false` → [ToolExecutionError] 抛出
///
/// 目标拆解只走这一张：模型交的形状不对时必须当场炸给开发者看，
/// 而不是把 fail 文案回填给模型"让它再试一次"——那会把失败藏进多轮循环里。
class StrictAgentToolRegistry extends AgentToolRegistry {
  @override
  Future<ToolOutcome> execute(String name, [Map<String, dynamic>? args]) async {
    final AgentTool? t = _tools[name];
    if (t == null) {
      throw ToolExecutionError(name, '没有这个工具（已注册：${_tools.keys.join(' / ')}）');
    }
    final ToolOutcome out;
    try {
      out = await t.run(args ?? const <String, dynamic>{});
    } on PlanFailure {
      // 工具自己抛的**带类型**的失败（形状/规则）原样上抛 —— 包一层会丢掉
      // code/where 这些调用方要分流的信息。
      rethrow;
    } on ToolExecutionError {
      rethrow;
    } catch (e, st) {
      throw ToolExecutionError(name, '工具内部异常', cause: '$e\n$st');
    }
    if (!out.ok) {
      throw ToolExecutionError(name, out.message);
    }
    return out;
  }
}
