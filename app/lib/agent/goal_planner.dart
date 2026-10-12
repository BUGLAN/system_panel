/// 目标拆解 —— **让 LLM 真的把宿主那句话拆成一条环链**（docs/06 的核心动作）。
///
/// 背景（2026-10-12 排查结论）：在此之前「拆解」= `detectCategory` 关键词归类 +
/// 套该类别写死的 3 条起步环 + 按「时长词」正则决定环数。宿主写什么只影响
/// ①类别 ②环数 ③末环标题 ④天幕短字 —— 环的内容与那句话无关，
/// 所以会出现「半年减重 10 斤」拿到「称重 / 少一杯 / 走路 / 加码 1~4」这种
/// 跟目标没有语义关系的链。
///
/// 本文件补上缺的那一环：把目标原文交给模型，拿回**逐环可执行**的清单。
///
/// ⚠️ 两条纪律：
///  1. **难度阶梯不交给模型**（档位 / 时限上限 / 末环是「兑现」）——
///     那是锁定规则，由 `goal_gen` 的 `nextRingSpecs*` 收口。这里只产出**内容**。
///  2. **任何失败都返回 null** —— 调用方逐字回退类别模板。她不会因为
///     模型抽风就铸不出一条主线（与 `copy.dart` 同一条铁律）。
library;

import 'dart:convert';

import '../data/rarity.dart';
import '../state/goal_gen.dart';
import 'copy.dart';
import 'persona.dart';

/// 拆解结果 —— 成功就是一组环的「内容」。
class GoalPlan {
  const GoalPlan({required this.rings, required this.raw});

  /// 逐环内容（档位/时限只是模型的建议，落地时会被阶梯收口）
  final List<RingSpec> rings;

  /// 模型原文（诊断/遥测用，不打进 UI）
  final String raw;
}

class GoalPlanner {
  GoalPlanner({
    this.llm,
    this.persona = const Persona(),
    this.timeout = const Duration(seconds: 20),
    // 拆解要吐一整条链的 JSON，比「一句台词」长得多；推理模型还要先想一遍，
    // 预算给小了必然空正文（见 llm_client 的 starvedByThinking）。
    this.maxTokens = 2048,
  });

  /// LLM 网关（与文案链路同一个最小面）；null / 未配 Key = 直接走模板。
  final CopyLlmGateway? llm;

  final Persona persona;

  /// 拆解等待上限：到点就回模板。**宿主在等**，不能吊着。
  final Duration timeout;

  final int maxTokens;

  /// 把 [goalText] 拆成 [ringCount] 环。失败（未配 Key / 无网 / 超时 /
  /// 坏 JSON / 内容不合格）一律返回 null，由调用方回退模板。
  Future<GoalPlan?> plan({
    required String goalText,
    required int ringCount,
    required GoalCategory cat,
  }) async {
    final String text = goalText.trim();
    if (text.isEmpty || ringCount <= 0) return null;
    final CopyLlmGateway? gateway = llm;
    if (gateway == null || !gateway.configured) return null;
    try {
      final String? raw = await gateway.complete(
        messages: <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'system',
            'content': _systemPrompt(ringCount, cat),
          },
          <String, dynamic>{'role': 'user', 'content': '宿主的目标：「$text」'},
        ],
        temperature: 0.7,
        maxTokens: maxTokens,
        timeout: timeout,
      );
      if (raw == null || raw.trim().isEmpty) return null;
      final List<RingSpec>? rings = parseRings(raw, ringCount: ringCount);
      if (rings == null) return null;
      return GoalPlan(rings: rings, raw: raw.trim());
    } catch (_) {
      // 兜底铁律：拆解链路上任何异常都折回模板
      return null;
    }
  }

  String _systemPrompt(int ringCount, GoalCategory cat) {
    final StringBuffer b = StringBuffer();
    // 人设照旧（她拆解时也是她，不是另一个人）
    b.writeln(persona.systemPrompt());
    b.writeln();
    b.writeln('【这一轮的任务：拆解目标】');
    b.writeln(
      '宿主立了一个目标。把它拆成 **$ringCount 环**可执行的主线链，'
      '每一环都是他当天**能独立做完并拍下证据**的一件事。',
    );
    b.writeln('这个目标偏「${cat.label}」类，但**以目标原文为准**，别硬套类别模板。');
    b.writeln();
    b.writeln('要求：');
    b.writeln('1. 从最容易的一环起步（低门槛、当天必成），难度与耗时**逐环递增**；');
    b.writeln('2. 环与环之间要有**真实的进阶关系**（后一环建立在前一环之上），'
        '不是同一件事改个时长；');
    b.writeln('3. 只写**宿主自己**的动作，写具体（「打开 X 做 Y 分钟」），'
        '禁止「坚持」「努力」「加油」这类空话；');
    b.writeln('4. 最后一环必须是一次**能证明目标达成**的验证动作；');
    b.writeln('5. 证据要拍得到（截图/照片/录音），写清拍什么。');
    b.writeln();
    b.writeln('**只输出 JSON**，不要解释、不要 markdown 代码块：');
    b.writeln('{"rings":[{"short":"≤4字的短标签","title":"一句话行动，≤20字",'
        '"proof":"拍什么，≤10字","minutes":整数,"rank":"E/D/C/B/A/S"}]}');
    b.writeln('rings 必须正好 $ringCount 条。');
    return b.toString().trim();
  }

  /// 从模型原文里抠出环。**宽容解析**：模型常把 JSON 包在
  /// ```json 围栏里、或在前后加一句废话 —— 只认第一个平衡的 `{...}`。
  ///
  /// 校验（任一不过就返回 null，让上层退回模板）：
  ///  · 条数必须 == [ringCount]（少一环都不是同一条链）
  ///  · short / title / proof 必须非空
  ///  · rank 必须在稀有度表内，minutes 必须是正数
  static List<RingSpec>? parseRings(String raw, {required int ringCount}) {
    final Object? decoded = _extractJson(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final Object? ringsRaw = decoded['rings'];
    if (ringsRaw is! List || ringsRaw.length != ringCount) return null;
    final List<RingSpec> out = <RingSpec>[];
    for (final Object? item in ringsRaw) {
      if (item is! Map<String, dynamic>) return null;
      final String short = _str(item['short']);
      final String title = _str(item['title']);
      final String proof = _str(item['proof']);
      final String rank = _str(item['rank']).toUpperCase();
      final Object? minutesRaw = item['minutes'];
      final int minutes = minutesRaw is num ? minutesRaw.toInt() : -1;
      if (short.isEmpty || title.isEmpty || proof.isEmpty) return null;
      if (!Rarity.ranks.contains(rank)) return null;
      if (minutes <= 0) return null;
      out.add(
        RingSpec(
          short: short,
          title: title,
          proof: proof,
          minutes: minutes,
          rank: rank,
        ),
      );
    }
    return out;
  }

  /// 抠第一个**能解析出对象的**平衡 `{…}`（字符串里的花括号不算）。
  ///
  /// ⚠️ 逐个候选取试，不是「只看第一个 `{`」：模型的正文里常有
  /// `说明{这里不是 JSON}` 这种插话，只看第一个会把整段丢掉。
  static Object? _extractJson(String raw) {
    int from = 0;
    while (from < raw.length) {
      final int start = raw.indexOf('{', from);
      if (start < 0) return null;
      final Object? decoded = _balancedAt(raw, start);
      if (decoded is Map<String, dynamic>) return decoded;
      from = start + 1;
    }
    return null;
  }

  /// 从 [start] 处的 `{` 开始找平衡的右花括号并解析；不成立返回 null。
  static Object? _balancedAt(String raw, int start) {
    int depth = 0;
    bool inStr = false;
    bool esc = false;
    for (int i = start; i < raw.length; i++) {
      final String c = raw[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == r'\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          try {
            return jsonDecode(raw.substring(start, i + 1));
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  static String _str(Object? v) => v is String ? v.trim() : '';
}
