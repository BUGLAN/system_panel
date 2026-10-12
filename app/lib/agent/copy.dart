/// SystemCopyProvider —— 系统「说话」的四个入口（docs/18 §2.5，docs/07 四语气）。
///
/// 发布 `dispatchLine` / 结算 `settleLine` / 毒舌 `roastLine` / 追问 `probeLine`。
/// 每个入口：先试 LLM（人设 prompt + 语气场合 + 真实上下文，temperature 0.8、
/// max_tokens 512、**300 字符钳制**），任何失败（未配 Key/无网/超时/异常/空话）
/// → **逐字回退内置文案**——能对上现有 LINES 的场合直接用 LINES 原句
/// （content.dart 原样保留，它就是兜底真源），结算档位等 LINES 没有的用本文件的
/// 内置池补齐。文案链路永不抛、永不阻塞 UI。
///
/// ⚠️ 为什么是 512 而不是 120：端点是**推理模型**，`max_tokens` 同时算
/// `reasoning_content` 与正文——120 会被思考整段吃光、正文永远为空，于是
/// 发布/结算/毒舌的 AI 文案从来没生效过（docs/22 R1 实锤）。
/// 文案在严格模式下**也不中断**（演出不能因为模型出错而崩），它的失败可见性
/// 走「日志 + 遥测 + 设置页回显」（docs/22 §2.0 例外条款）。
///
/// LLM 客户端本体归 t9（`lib/agent/llm_client.dart`，OpenAI 兼容 chat +
/// function calling，docs/18 §2.4 契约）。本文件只依赖 [CopyLlmGateway] 这个
/// 最小面，集成任务用几行适配器把 t9 的实现插进来即可。
library;

import '../data/content.dart';
import '../state/goal.dart';
import '../state/host_state.dart';
import '../state/quest.dart';
import '../state/result.dart';
import 'memory.dart';
import 'persona.dart';

/// 「一句话」的补全上限 —— 台词链路（发布/结算/毒舌/追问）与聊天的一次性
/// 回复共用。
///
/// ⚠️ 历史（docs/22 R1）：最早 120，被推理模型的 `reasoning_content` 吃光 →
///    正文空 → 永远回退模板，于是抬到 512。512 同样是拍出来的数字：真机实测
///    同一句 38 字台词，思考量在 **68~2067** 之间乱跳 —— 任何"刚好够"的预算
///    都是抛硬币。宿主 2026-10-12 定调「不用那么省」，所以这里直接给足，
///    并保留 `llm_client` 的抬预算兜底网。
///
/// 思考档位**跟随设置页**（不再是硬编码 `none`）：宿主想要她台词更快，
/// 就把「思考档位」调成「关」；预算给足之后，思考只剩"值不值"的问题，
/// 不再是"会不会空正文"的问题。
const int kLineMaxTokens = 4096;

/// copy.dart 需要的最小 LLM 面。真实现（t9 的 LlmClient）适配此接口；
/// `configured=false` 或 `complete` 返回 null 都表示「走模板兜底」。
abstract interface class CopyLlmGateway {
  /// 是否已配置可用（通常 = 配了 API Key）。false 时零网络等待。
  bool get configured;

  /// 补全一句文案。**任何失败都返回 null**（无网/超时/坏 JSON/限流…），
  /// 由调用方回退内置模板——本接口的实现自己也必须遵守这条铁律。
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
    /// 本发的思考档位覆盖：`null` = 用配置（设置页）。台词链路传
    /// [kLineReasoningEffort]（`none`）—— 一句话不需要推理，把它关掉
    /// 比拿一个小 max_tokens 硬扛稳得多也快得多。
    String? reasoningEffort,
  });
}

/// 结算档位（docs/07：结算语气按档位 tier）
enum SettleTier { low, mid, high, top }

/// 文案出处：LLM 生成 / 内置模板
enum CopySource { llm, template }

/// 一句她说的话。
class CopyLine {
  const CopyLine({required this.text, required this.source, required this.emotion});

  final String text;
  final CopySource source;

  /// 情绪标签（舞台 emote 用， Persona.emotions 表内；模板句自带默认值）
  final String emotion;
}

/// 生成文案用的现场快照。全字段带默认——任何一个模块都能零成本喂上下文。
class CopyContext {
  const CopyContext({
    this.lv = 1,
    this.streak = 0,
    this.bestStreak = 0,
    this.queue = 0,
    this.doneIndex = -1,
    this.planTotal = 0,
    this.goalShort = '',
    this.weakestAttr = '',
    this.failCount = 0,
    this.questName = '',
    this.questRank = '',
    this.questMinutes = 0,
    this.questProof = '',
    this.exp = 0,
    this.coin = 0,
    this.crit = false,
    this.photos = 0,
    this.topic = '',
  });

  /// 从现有档案/主线/单/结算结果一把抓（集成处最省事的构造方式）
  factory CopyContext.fromState({
    HostState host = HostState.empty,
    Goal? goal,
    Quest? quest,
    QuestResult? result,
    String topic = '',
  }) => CopyContext(
    lv: host.lv,
    streak: host.streak,
    bestStreak: host.bestStreak,
    queue: host.queue,
    doneIndex: goal?.doneCount ?? host.doneIndex,
    planTotal: goal?.plan.length ?? host.planTotal,
    goalShort: goal?.short ?? '',
    weakestAttr: host.weakest.key,
    failCount: host.failCount,
    questName: result?.quest.name ?? quest?.name ?? '',
    questRank: result?.quest.rank ?? quest?.rank ?? '',
    questMinutes: result?.quest.minutes ?? quest?.minutes ?? 0,
    questProof: result?.quest.proof ?? quest?.proof ?? '',
    exp: result?.exp ?? 0,
    coin: result?.coin ?? 0,
    crit: result?.crit ?? false,
    photos: result?.photos ?? 0,
    topic: topic,
  );

  final int lv;
  final int streak;
  final int bestStreak;
  final int queue;
  /// 已完成单数
  final int doneIndex;
  final int planTotal;
  final String goalShort;
  final String weakestAttr;
  final int failCount;
  final String questName;
  final String questRank;
  final int questMinutes;
  final String questProof;
  final int exp;
  final int coin;
  final bool crit;
  final int photos;
  final String topic;

  CopyContext copyWith({
    int? lv,
    int? streak,
    int? bestStreak,
    int? queue,
    int? doneIndex,
    int? planTotal,
    String? goalShort,
    String? weakestAttr,
    int? failCount,
    String? questName,
    String? questRank,
    int? questMinutes,
    String? questProof,
    int? exp,
    int? coin,
    bool? crit,
    int? photos,
    String? topic,
  }) => CopyContext(
    lv: lv ?? this.lv,
    streak: streak ?? this.streak,
    bestStreak: bestStreak ?? this.bestStreak,
    queue: queue ?? this.queue,
    doneIndex: doneIndex ?? this.doneIndex,
    planTotal: planTotal ?? this.planTotal,
    goalShort: goalShort ?? this.goalShort,
    weakestAttr: weakestAttr ?? this.weakestAttr,
    failCount: failCount ?? this.failCount,
    questName: questName ?? this.questName,
    questRank: questRank ?? this.questRank,
    questMinutes: questMinutes ?? this.questMinutes,
    questProof: questProof ?? this.questProof,
    exp: exp ?? this.exp,
    coin: coin ?? this.coin,
    crit: crit ?? this.crit,
    photos: photos ?? this.photos,
    topic: topic ?? this.topic,
  );

  /// 确定性选句的种子（同现场稳定，不同现场有变化）
  String get seedToken =>
      'lv$lv|st$streak|q$queue|done$doneIndex|fail$failCount|$questName|$exp|$coin|$topic';
}

/// 内置兜底文案池。`[[…]]` 是高亮标记（与 LINES 同一约定，LineLayer 会点亮）；
/// `{key}` 是填空位。能对上 LINES 的条目**直接引用 LINES 常量**（逐字由构造保证），
/// 其余为本文件补写的同声内置文案（结算档位池，LINES 没有对应条目）。
abstract final class SystemCopyTemplates {
  /// 发布（首条 = LINES.holding 原句）
  static const List<String> dispatch = <String>[
    LINES.holding,
    '[[{rank}]] 级。[[{name}]]，{minutes}——证据按「{proof}」交。',
    '接住。[[{name}]]。理由我写在单子上了，看完再动。',
    '新单钉上了，[[{rank}]] 级，{minutes}。别让我等。',
  ];

  /// 结算 · low（F/E）
  static const List<String> settleLow = <String>[
    '[[{exp}]] 点经验。有总比没有强。',
    '做完了就算数。◈[[{coin}]]，收好。',
    '这就是今天的全部了吗。……算你交了差。',
  ];

  /// 结算 · mid（D/C）
  static const List<String> settleMid = <String>[
    '[[{exp}]] EXP 入账。这个速度，勉强能看。',
    '完成确认。◈[[{coin}]]——离下一件道具不远了。',
    '不错。但[[{streak}]]连击才是你该守住的数字。',
  ];

  /// 结算 · high（B/A）
  static const List<String> settleHigh = <String>[
    '[[{exp}]] EXP。今天这单，配得上你吹过的牛。',
    '利落。◈[[{coin}]]照付。别飘，明天还有。',
    '完成确认。证据 [[{photos}]] 份，一单比一单像样。',
  ];

  /// 结算 · top（S）
  static const List<String> settleTop = <String>[
    'S 级都让你啃下来了。……有点东西。[[{exp}]] EXP、◈[[{coin}]]，拿好。',
    '这一单我记进档案了。[[{streak}]] 连击，就是你现在的名字。',
  ];

  /// 毒舌（引用真实数据；补救条 = LINES.remedyLine 原句，{dl} 渲染时取「明天」）
  static const List<String> roast = <String>[
    '连败 [[{fail}]] 次了。你的字典里是不是没有「吸取教训」这四个字？',
    '连击 [[{streak}]]——最好的时候是 [[{best}]]。自己挑个数字脸红。',
    '空着手来要暴击？我的暴击不给借口。',
    LINES.remedyLine,
    '手里还压着 [[{queue}]] 单。它们不会自己消失。',
  ];

  /// 追问（首条 = LINES.askGoal 原句）
  static const List<String> probe = <String>[
    LINES.askGoal,
    '哪个环节卡住了？[[说具体点]]。',
    '先回答我：这次要[[短平快]]，还是[[上强度]]？',
    '「想换」不算理由。这单哪里不对，[[一样一样说]]。',
  ];
}

class SystemCopyProvider {
  SystemCopyProvider({
    this.llm,
    this.persona = const Persona(),
    this.memory,
    this.llmTimeout = const Duration(seconds: 8),
  });

  static const int maxChars = 300;

  /// LLM 网关（t9 的 OpenAI 兼容实现适配进来）；null/未配 Key = 全走模板
  final CopyLlmGateway? llm;

  /// 人设（默认即小祥）
  final Persona persona;

  /// 长期记忆（LLM 上下文的相关记忆注入源）
  final MemoryStore? memory;

  /// LLM 气质的场合等待上限——到点就回模板，绝不吊着 UI
  final Duration llmTimeout;

  // ── 四个入口 ──────────────────────────────────────────────

  /// 发布：钉单时的说明与理由
  Future<CopyLine> dispatchLine(CopyContext ctx) =>
      _speak('发布', ctx, SystemCopyTemplates.dispatch, 'neutral');

  /// 结算：按档位点评（tier 省略时按本单 rank 推）
  Future<CopyLine> settleLine(CopyContext ctx, {SettleTier? tier}) {
    final SettleTier t = tier ?? tierOf(ctx.questRank);
    return _speak(
      '结算（档位 ${t.name}）',
      ctx,
      _settlePool(t),
      _settleEmotion(t),
      extraFacts: '本单结算 EXP +${ctx.exp}、◈+${ctx.coin}${ctx.crit ? '（暴击！）' : ''}',
    );
  }

  /// 毒舌：连败/退缩/空证据，必须引用真实数据
  Future<CopyLine> roastLine(CopyContext ctx, {String? reason}) => _speak(
    '毒舌',
    ctx,
    SystemCopyTemplates.roast,
    'annoyed',
    extraFacts: reason == null || reason.isEmpty ? '' : '宿主刚才的行为：$reason',
  );

  /// 追问：访谈与换任务时的提问
  Future<CopyLine> probeLine(CopyContext ctx, {String? topic}) => _speak(
    '追问',
    ctx,
    SystemCopyTemplates.probe,
    'neutral',
    extraFacts: '追问话题：${(topic ?? ctx.topic).isEmpty ? '目标与计划' : (topic ?? ctx.topic)}',
  );

  /// rank → 结算档位（F/E→low，D/C→mid，B/A→high，S→top；认不出的归 low）
  static SettleTier tierOf(String rank) => switch (rank.toUpperCase()) {
    'F' || 'E' => SettleTier.low,
    'D' || 'C' => SettleTier.mid,
    'B' || 'A' => SettleTier.high,
    'S' => SettleTier.top,
    _ => SettleTier.low,
  };

  // ── 内部 ──────────────────────────────────────────────────

  static List<String> _settlePool(SettleTier t) => switch (t) {
    SettleTier.low => SystemCopyTemplates.settleLow,
    SettleTier.mid => SystemCopyTemplates.settleMid,
    SettleTier.high => SystemCopyTemplates.settleHigh,
    SettleTier.top => SystemCopyTemplates.settleTop,
  };

  static String _settleEmotion(SettleTier t) => switch (t) {
    SettleTier.low => 'cold',
    SettleTier.mid => 'pleased',
    SettleTier.high => 'smug',
    SettleTier.top => 'proud',
  };

  Future<CopyLine> _speak(
    String toneKey,
    CopyContext ctx,
    List<String> pool,
    String fallbackEmotion, {
    String extraFacts = '',
  }) async {
    final String template = _fill(pool[_pick(pool, '${ctx.seedToken}|$toneKey')], ctx);
    final CopyLlmGateway? gateway = llm;
    if (gateway == null || !gateway.configured) {
      return CopyLine(text: template, source: CopySource.template, emotion: fallbackEmotion);
    }
    try {
      // 相关记忆注入（docs/18 §2.5：上下文含等级/连击/相关记忆）
      final MemoryStore? mem = memory;
      final String? digest = mem == null
          ? null
          : await mem.digest('${ctx.questName} ${ctx.topic}');
      final String? raw = await gateway.complete(
        messages: persona.buildConversation(
          userText: _userBrief(toneKey, ctx, extraFacts),
          memoryDigest: digest,
          scenario: '${Persona.tones[toneKey] ?? ''} 只输出一句她的台词本身，不要任何解释。',
        ),
        temperature: 0.8,
        // 预算给足 + 档位跟随设置页（宿主可在设置里把思考关掉换速度）
        maxTokens: kLineMaxTokens,
        timeout: llmTimeout,
      );
      final String text = (raw ?? '').trim();
      if (text.isEmpty) {
        return CopyLine(text: template, source: CopySource.template, emotion: fallbackEmotion);
      }
      final TaggedReply tagged = Persona.splitTag(text);
      if (tagged.text.isEmpty) {
        // 只有标签没有正文——当 LLM 没说话处理
        return CopyLine(text: template, source: CopySource.template, emotion: fallbackEmotion);
      }
      return CopyLine(
        text: _clamp(tagged.text),
        source: CopySource.llm,
        emotion: tagged.emotion == 'neutral' ? fallbackEmotion : tagged.emotion,
      );
    } catch (_) {
      // 兜底铁律：LLM 链路上任何异常都折回模板
      return CopyLine(text: template, source: CopySource.template, emotion: fallbackEmotion);
    }
  }

  String _userBrief(String toneKey, CopyContext ctx, String extraFacts) {
    final String quest = ctx.questName.isEmpty
        ? ''
        : '本单「${ctx.questName}」（${ctx.questRank} 级 · ${ctx.questMinutes} 分钟'
              '${ctx.questProof.isEmpty ? '' : ' · 证据：${ctx.questProof}'}）。';
    final String goal = ctx.goalShort.isEmpty ? '未立目标' : '主线「${ctx.goalShort}」';
    return '现场事实：宿主 LV${ctx.lv}，连击 ${ctx.streak}（最好 ${ctx.bestStreak}），'
        '手里 ${ctx.queue} 单，$goal（${ctx.doneIndex}/${ctx.planTotal} 单），'
        '最弱维 ${ctx.weakestAttr}，连败 ${ctx.failCount} 次。$quest'
        '${extraFacts.isEmpty ? '' : ' $extraFacts'}\n'
        '要求：${toneKey == '追问' ? '只输出一个问题，不超过 30 字' : '只输出一句台词，不超过 40 字'}，'
        '句首加 [情绪] 标签。';
  }

  /// 填空。模板里出现的 `{key}` 都在喂值表内；喂不出来的（比如空字段给默认）
  /// 也不会残留 `{xx}`——由测试盯住这一点。
  static String _fill(String template, CopyContext ctx) {
    final String minutes = ctx.questMinutes <= 0
        ? ''
        : ctx.questMinutes < 60
            ? '${ctx.questMinutes} 分钟'
            : '${ctx.questMinutes ~/ 60} 小时${ctx.questMinutes % 60 == 0 ? '' : ' ${ctx.questMinutes % 60} 分'}';
    final Map<String, String> v = <String, String>{
      'n': '${ctx.queue}',
      'lv': '${ctx.lv}',
      'streak': '${ctx.streak}',
      'best': '${ctx.bestStreak}',
      'queue': '${ctx.queue}',
      'fail': '${ctx.failCount}',
      'rank': ctx.questRank.isEmpty ? 'F' : ctx.questRank,
      'name': ctx.questName.isEmpty ? '无名之单' : ctx.questName,
      'minutes': minutes,
      'proof': ctx.questProof.isEmpty ? '能证明的截图' : ctx.questProof,
      'exp': '${ctx.exp}',
      'coin': '${ctx.coin}',
      'photos': '${ctx.photos}',
      'done': '${ctx.doneIndex < 0 ? 0 : ctx.doneIndex}',
      'left': '${(ctx.planTotal - ctx.doneIndex) < 0 ? 0 : ctx.planTotal - ctx.doneIndex}',
      'total': '${ctx.planTotal}',
      'goal': ctx.goalShort.isEmpty ? '你的目标' : ctx.goalShort,
      'attr': ctx.weakestAttr,
      'topic': ctx.topic.isEmpty ? '目标与计划' : ctx.topic,
      'dl': '明天',
    };
    String out = template;
    for (final MapEntry<String, String> e in v.entries) {
      out = out.replaceAll('{${e.key}}', e.value);
    }
    return out;
  }

  /// 确定性选句：种子哈希旋转（同现场稳定，可测）
  static int _pick(List<String> pool, String seed) {
    int h = 0;
    for (final int c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % pool.length;
  }

  /// docs/18 §2.5：LLM 文案 300 字符钳制
  static String _clamp(String s) => s.length > maxChars ? s.substring(0, maxChars) : s;
}
