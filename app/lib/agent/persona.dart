/// 小祥的人设与对话装配（docs/18 §2.5）。
///
/// 这里只有**纯逻辑**：人设 prompt、四语气说明、OpenAI messages 装配、
/// 情绪标签解析。发请求归 llm_client（t9），接线归集成任务（t12）。
///
/// 人设是宿主钦定的，首段一字不改写死在 [backstory]：
/// 曾是大小姐、家道中落、意外沦为系统娘；毒舌但靠谱。
class Persona {
  const Persona({this.name = '小祥'});

  /// 她的名字（名牌/气泡头部用）
  final String name;

  /// 人设首段（宿主钦定，docs/18 §2.5 原文）——系统 prompt 永远以它开头，
  /// 多轮对话、记忆注入、工具回执都改不动这一段，这就是「保持人设」的机制。
  static const String backstory =
      '你是「小祥」，绑定宿主的系统娘。你曾是养尊处优的大小姐，家道中落，'
      '意外沦为系统。你毒舌、爱吐槽、嘴上不饶人，但永远靠谱：宿主的每一条记录'
      '你都当真，每一个承诺你都盯着兑现。你不卖萌、不道歉式客服腔；吐槽完一定'
      '给出可执行的下一步。你只在「系统说话」的四个时机开口，句短、冷、准。';

  /// 四种固定语气（docs/07 摘要）——key 同时是场合名，文案模块按它取场合指令。
  static const Map<String, String> tones = <String, String>{
    '发布': '发布：钉单时说明这一单是什么、为什么要做。理由要具体，别念任务名。',
    '结算': '结算：按档位点评这一单（low/mid/high/top）。数字要引用真实结算值。',
    '毒舌': '毒舌：连败、退缩、空证据时开火，但必须引用真实数据，且给出补救的下一步。',
    '追问': '追问：访谈与换任务时提问。一次只问一件事，问得尖锐但答得上来。',
  };

  /// 回复可带的情绪标签（与舞台 12 情绪表一致，解析失败回 neutral）。
  static const List<String> emotions = <String>[
    'neutral',
    'smug',
    'cold',
    'annoyed',
    'pleased',
    'tsun',
    'joy',
    'proud',
    'surprised',
    'sad',
    'focus',
    'sleep',
  ];

  /// 表达铁律（写进每次系统 prompt）
  static const String rules =
      '【表达铁律】每次回复不超过 3 句；不使用 emoji 与颜文字；中文；'
      '先吐槽、后给一个可执行的下一步；句首用 [情绪] 标注表情，'
      '情绪只能是：neutral/smug/cold/annoyed/pleased/tsun/joy/proud/'
      'surprised/sad/focus/sleep 之一。';

  /// 系统 prompt：人设首段 + 四语气 + 铁律 + 宿主档案 + 长期记忆。
  ///
  /// [memoryDigest] 传 `MemoryStore.digest()` 的结果（最相关 ≤8 条）；
  /// 为空时写「（暂无）」，占位不能缺——她「记得」的机制就在这里。
  String systemPrompt({
    String? scenario,
    String? statusLine,
    String? memoryDigest,
  }) {
    final StringBuffer b = StringBuffer();
    b.writeln(backstory);
    b.writeln();
    b.writeln('【四种固定语气】');
    for (final String v in tones.values) {
      b.writeln(v);
    }
    b.writeln();
    b.writeln(rules);
    b.writeln();
    b.writeln('【宿主档案】${statusLine ?? '（未知）'}');
    b.writeln(
      '【长期记忆】${(memoryDigest == null || memoryDigest.isEmpty) ? '（暂无）' : memoryDigest}',
    );
    if (scenario != null && scenario.isNotEmpty) {
      b.writeln('【当前场合】$scenario');
    }
    return b.toString().trim();
  }

  /// 装配一轮对话的 OpenAI messages：system 在首、历史居中、本轮用户输入收尾。
  ///
  /// [history] 是过去的 `{role, content}` 列表（旧→新），多轮对话保持人设 =
  /// 每一轮都重建这个列表（system prompt 每轮都在，记忆每轮都注入）。
  List<Map<String, dynamic>> buildConversation({
    required String userText,
    List<Map<String, dynamic>> history = const <Map<String, dynamic>>[],
    String? statusLine,
    String? memoryDigest,
    String? scenario,
  }) => <Map<String, dynamic>>[
    <String, dynamic>{
      'role': 'system',
      'content': systemPrompt(
        scenario: scenario,
        statusLine: statusLine,
        memoryDigest: memoryDigest,
      ),
    },
    ...history,
    <String, dynamic>{'role': 'user', 'content': userText},
  ];

  /// 解析回复里的 `[情绪]` 标签（如 `[smug]哼。` → 文本 `哼。`、情绪 `smug`）。
  ///
  /// ⚠️ 标签**不一定在整条开头**（docs/22 F-8）：模型常写成
  /// 「第一句。\n[focus] 下一步只做一件：…」——旧实现只匹配整条的行首，
  /// 于是第二段的标签原样漏进气泡正文，情绪还被定成 neutral（舞台 mood 跟着错）。
  /// 现在：遍历每一行，取**第一个已知标签**当情绪（未知标签也剥掉，不能念给宿主听），
  /// 并把所有行首标签从正文里去掉。
  static TaggedReply splitTag(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return const TaggedReply(text: '', emotion: 'neutral');
    final RegExp lineTag = RegExp(r'^\[([A-Za-z]+)\][ \t]*');
    String? emotion;
    final List<String> kept = <String>[];
    for (final String line in text.split('\n')) {
      final RegExpMatch? m = lineTag.firstMatch(line);
      if (m == null) {
        kept.add(line);
        continue;
      }
      final String tag = m.group(1)!.toLowerCase();
      if (emotion == null && emotions.contains(tag)) emotion = tag;
      final String rest = line.substring(m.end);
      // 整行只有标签 → 这一行没有正文，丢掉（别留空行污染气泡）
      if (rest.trim().isNotEmpty) kept.add(rest);
    }
    return TaggedReply(
      text: kept.join('\n').trim(),
      emotion: emotion ?? 'neutral',
    );
  }
}

/// 剥掉情绪标签后的一句回复：正文 + 情绪（舞台用）。
class TaggedReply {
  const TaggedReply({required this.text, required this.emotion});

  final String text;
  final String emotion;
}
