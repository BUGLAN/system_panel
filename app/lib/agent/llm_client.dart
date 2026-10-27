import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'llm_telemetry.dart';

/// ═══════════════════════════════════════════════════════════
///  OpenAI 兼容统一 LLM 客户端（docs/18 §2.4 / §3.1-T4）
///
///  视觉校验、小祥对话、文案接管共用这一层。三条铁律：
///   1. **永不抛异常** —— 失败一律折叠成 [LlmReply.failure]（`ok=false`
///      + 失败类别），上层据此走兜底（模板/逐字回退），App 不因 LLM 卡住
///   2. 超时 12s、传输层失败（超时/网络异常）**重试 1 次**；
///      HTTP 4xx/5xx 与坏 JSON 不重试（重试也不会好）
///   3. 模型名做**别名归一化**（ENV.md round 15 实测：`deepseek-v4.1flash`
///      在端点 400，实际可用 `deepseek-flash` / `deepseek-v4-pro`，两者均收
///      image_url 多模态输入）——设置页保持宿主钦定的默认名不变，请求前归一
/// ═══════════════════════════════════════════════════════════

/// 失败类别（可兜底信号：上层按类别决定回退文案，永不抛异常）
enum LlmFailure {
  /// 没配 Key —— 连请求都不发
  noKey,

  /// 连不上 / DNS / 中途断流
  network,

  /// 超过时限（重试 1 次后仍超时）
  timeout,

  /// 端点回了非 200
  httpError,

  /// 200 但不是预期的 JSON 结构
  badResponse,
}

/// 默认补全预算（调用点没指定时用）。
///
/// ⚠️ 宿主 2026-10-12 定调：**不用为省 token 做设计取舍** —— 这点成本是有的，
///    后续用图片做证据校验还会更贵，所以别把预算卡在"刚好够"上。
///    真机教训：最早是 120，被推理模型的 `reasoning_content` 吃光 → 正文空 →
///    静默退回模板，于是抬到 512；但思考量在 68~2067 之间乱跳，
///    任何"刚好够"的数字都是抛硬币。**给足，别猜。**
const int kDefaultMaxTokens = 4096;

/// 工具循环（聊天里她调工具）的预算：**思考 + 工具调用 + 终答** 共用它，
/// 所以要给得比"回一句话"宽得多。
const int kToolLoopMaxTokens = 8192;

/// 立主线 / 拆解一轮的预算：一条链的 JSON + 思考共用。
const int kPlanMaxTokens = 8192;

/// 需要思考的路径（拆解 / 工具循环）的档位**下限**。
///
/// 宿主把「思考档位」调到「关」是为了**台词说得快**，不该顺手把拆解质量
/// 也砍掉 —— 所以这两条路至少停在 `low`。
const String kPlanReasoningEffort = 'low';

/// 把设置页的「思考档位」折算成"需要思考的路径"实际用的档位。
/// 空 / `none` / `minimal` → 抬到 [kPlanReasoningEffort]；其余原样。
String planReasoningEffort(String configured) {
  final String e = configured.trim().toLowerCase();
  if (e.isEmpty || e == 'none' || e == 'minimal') return kPlanReasoningEffort;
  return e;
}

/// 「思考吃光预算」时抬预算的封顶（兜底网，不是常规路径）。
/// 端点实测最多能吃到 65536，这里留一半当余量。
const int kMaxEscalatedTokens = 16384;

class LlmConfig {
  const LlmConfig({
    String? baseUrl,
    this.apiKey = '',
    String? model,
    this.reasoningEffort = kDefaultReasoningEffort,
    this.strict = false,
    this.temperature,
    this.contextLen = 0,
    this.stream = false,
  }) : baseUrl = baseUrl ?? kDefaultBase,
       model = model ?? kDefaultModel;

  static const String kDefaultBase = 'https://api.deepseek.com';

  /// 宿主钦定的首发模型名（设置页默认值；请求前经 [normalizedModel] 归一）
  static const String kDefaultModel = 'deepseek-v4.1flash';

  /// 推理档位（端点 `/models` 自报支持 low/high/max）。
  /// **默认 low**：端点是推理模型，`max_tokens` 同时算思考与正文——
  /// 档位越高、正文越容易被思考吃光（docs/22 §2.0 / R1）。空串 = 不带该参数。
  static const String kDefaultReasoningEffort = 'low';

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 请求带的 `reasoning_effort`（空串＝不传，交端点默认）
  final String reasoningEffort;

  /// 严格模式（docs/22 §2.0）：开发构建下失败**不伪装成正常回复**。
  /// 客户端本身只把它带在配置上（诊断/上层决策用），不改变失败折叠行为。
  final bool strict;

  // ── 采样参数（设置页可调；参考稿没有，按「补全缺失组件」新增）────
  //
  // 三条都**真的进请求体**，不是摆设：
  //   [temperature] null = 调用点自己决定（多数调用点显式传 0.8 / 0.3）
  //   [contextLen]  0 = 用调用点的 maxTokens；>0 = 作为**上限**钳制它
  //   [stream]      true 时向端点要 `stream: true`（客户端仍按整包解析）
  // 为什么 contextLen 是"上限"而不是"覆盖"：拆解/工具循环有自己的预算
  // （kPlanMaxTokens / kToolLoopMaxTokens），设置页不该把它们压低。
  /// 默认温度（null = 调用点决定）
  final double? temperature;

  /// 响应预算上限；0 = 不钳制
  final int contextLen;

  /// 是否请求流式响应
  final bool stream;

  /// 把调用点的温度与配置合并：调用点显式给了就用它，否则用设置页的。
  double? resolveTemperature(double? asked) => asked ?? temperature;

  /// 把调用点的 maxTokens 与配置上限合并（取小；0 = 不限制）。
  int? resolveMaxTokens(int? asked) {
    if (contextLen <= 0) return asked;
    if (asked == null) return contextLen;
    return asked < contextLen ? asked : contextLen;
  }

  /// 别名归一化表 —— 全小写键。ENV.md 实测 v4.1flash 不存在 → deepseek-flash。
  /// 新端点换名只改这张表，设置页文案不动。
  static const Map<String, String> modelAliases = <String, String>{
    'deepseek-v4.1flash': 'deepseek-flash',
    'deepseek-v4.1-flash': 'deepseek-flash',
    'v4.1flash': 'deepseek-flash',
  };

  /// 实际发请求用的模型名（未命中别名表则原样透传，第三方端点可自由填）
  String get normalizedModel {
    final String key = model.trim().toLowerCase();
    return modelAliases[key] ?? model.trim();
  }

  /// 设置页默认名是否会被归一改写（测试连接回显用）
  bool get modelWasNormalized => normalizedModel != model.trim();

  /// OpenAI 兼容端点：base 已带 /chat/completions 就原样用，否则补上。
  /// 兼容 `https://api.deepseek.com`、`…/v1`、写全的 endpoint 三种填法。
  String get endpoint {
    String b = baseUrl.trim();
    if (b.isEmpty) b = kDefaultBase;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }
}

/// 一条对话消息；[images] 非空时 content 变多模态 parts 数组
/// （OpenAI vision 格式：`{"type":"image_url","image_url":{"url":…}}`）。
class LlmMessage {
  const LlmMessage(this.role, this.text, {this.images = const <String>[]});

  LlmMessage.system(String text) : this('system', text);
  LlmMessage.user(String text, {List<String> images = const <String>[]})
    : this('user', text, images: images);
  LlmMessage.assistant(String text) : this('assistant', text);

  final String role;
  final String text;

  /// data URL（`data:image/jpeg;base64,…`）或 https 图片地址
  final List<String> images;

  Map<String, dynamic> toJson() {
    if (images.isEmpty) {
      return <String, dynamic>{'role': role, 'content': text};
    }
    return <String, dynamic>{
      'role': role,
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': text},
        for (final String url in images)
          <String, dynamic>{
            'type': 'image_url',
            'image_url': <String, String>{'url': url},
          },
      ],
    };
  }
}

/// function calling 的工具声明（OpenAI tools 数组格式）
class LlmTool {
  const LlmTool({
    required this.name,
    required this.description,
    this.parameters,
  });

  final String name;
  final String description;

  /// JSON Schema（OpenAI `parameters`），null 时给空对象
  final Map<String, dynamic>? parameters;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': description,
      'parameters':
          parameters ??
          <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
    },
  };
}

/// 模型要求调用的一个工具
class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    this.arguments = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// 统一应答：`ok=false` 时 [failure] 一定有值，内容全在 [detail]（给人看）。
class LlmReply {
  const LlmReply.success({
    this.text = '',
    this.toolCalls = const <LlmToolCall>[],
    this.model,
    this.finishReason,
    this.reasoningTokens,
  }) : ok = true,
       failure = null,
       detail = null;

  const LlmReply.failure(this.failure, this.detail)
    : ok = false,
      text = '',
      toolCalls = const <LlmToolCall>[],
      model = null,
      finishReason = null,
      reasoningTokens = null;

  final bool ok;
  final String text;
  final List<LlmToolCall> toolCalls;
  final String? model;
  final LlmFailure? failure;
  final String? detail;

  /// 端点的 `choices[0].finish_reason`（`stop` / `length` …）。
  final String? finishReason;

  /// `usage.completion_tokens_details.reasoning_tokens`（端点不报就 null）。
  /// 真机实测（2026-10-12）：同一个 deepseek 推理端点 6 次里 2 次把 512 预算
  /// **全花在思考上**，正文空 → 她静默退回模板，宿主看到的就是「她忽然哑了」。
  final int? reasoningTokens;

  /// 「话还没说出口就被掐了」：HTTP 200、正文空、没有工具调用，而且
  /// 端点明说了是 `length` 截断（或确实产生了思考 token）。
  ///
  /// ⚠️ 这**不是失败**（strict 模式也不该按失败处理）——请求本身是成功的，
  /// 只是预算不够她开口。所以由 [LlmClient.chat] 抬预算重来一次，
  /// 而不是把这一发当成错误丢掉。只看 [ok] 会被它骗过去。
  bool get starvedByThinking =>
      ok &&
      text.trim().isEmpty &&
      toolCalls.isEmpty &&
      (finishReason == 'length' || (reasoningTokens ?? 0) > 0);

  /// 「真的拿到了一句话」。验收 F-2：只看 [ok] 会被「HTTP 200 + 正文为空」
  /// 骗过去——推理模型把 `max_tokens` 花在思考上就是这个表现，
  /// 设置页「测试连接」据此判定才不会给假绿灯。
  bool get hasText => ok && text.trim().isNotEmpty;
}

class LlmClient {
  LlmClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 12),
    this.retries = 1,
  }) : _http = httpClient ?? http.Client();

  final LlmConfig config;
  final http.Client _http;

  /// 单次请求时限（docs/18 §2.4：12s）
  final Duration timeout;

  /// 传输层失败的重试次数（docs/18：1 次）
  final int retries;

  /// 连通性探测：设置页「测试连接」用。
  ///
  /// **必须是真实形状**（docs/22 R1）：低思考档 + 足够 `max_tokens` + 一句系统提示。
  /// 旧版 `maxTokens: 8` 会永远返回空正文/截断，却因为只看「HTTP 200」而显示成功——
  /// 宿主看到的「测试连接通了、聊天却兜底」就是它造成的错觉。
  Future<LlmReply> ping() => chat(
    messages: <LlmMessage>[
      LlmMessage.system('你是系统娘小祥，只用一句话回答，不要解释。'),
      LlmMessage.user('ping'),
    ],
    maxTokens: 512,
    temperature: 0,
  );

  /// 释放底层 http.Client（TODO-07 网关热更：设置变更重建客户端时**必须**
  /// 关掉旧的，别让连接池一直挂着）。关闭瞬间还在途的请求会收
  /// ClientException → [chat] 把它折叠成 [LlmFailure.network]，
  /// 调用方按断网兜底——永远不抛。
  void close() => _http.close();

  /// 对话 / 多模态 / function calling 统一入口。**任何失败都不抛异常**。
  ///
  /// 每次应答都记一笔 [LlmTelemetry]（docs/22 §2.0：兜底不能再「默默发生」）。
  Future<LlmReply> chat({
    required List<LlmMessage> messages,
    List<LlmTool>? tools,
    double? temperature,
    int? maxTokens,
    String? reasoningEffort,
    Duration? timeout,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    LlmReply r = await _chat(
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort,
      timeout: timeout,
    );
    // 思考把预算吃光 → **抬预算重来一次**。
    //
    // ⚠️ 这不违反 strict 模式的纪律（docs/22 §2.0「开发期不重试、别把偶发失败
    //    藏过去」）：那一条管的是**失败**重试。这一发请求是成功的、端点也没报错，
    //    只是她在开口前就被 `max_tokens` 掐断了——不重来就必然静默退回模板，
    //    宿主看到的是「她忽然哑了」，那才是真正被藏起来的问题。真机 2026-10-12
    //    实测 6 次里 2 次命中，比例不低。
    final int? bumped = _escalatedBudget(maxTokens);
    if (bumped != null && r.starvedByThinking) {
      debugPrint(
        '[llm] 空正文（思考吃光 max_tokens=$maxTokens，'
        'reasoning=${r.reasoningTokens}，finish=${r.finishReason}）→ 抬到 $bumped 重来一次',
      );
      r = await _chat(
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxTokens: bumped,
        reasoningEffort: reasoningEffort,
        timeout: timeout,
      );
    }
    sw.stop();
    LlmTelemetry.record(r);
    // docs/22 F-1：聊天路径直连本客户端、**不走网关**，所以日志必须在这里打，
    // 否则「logcat 能看到请求与回执」这条验收永远拿不到证据。
    // 只打诊断元信息：不打 Key、不打完整 prompt、不打回复全文。
    if (r.ok) {
      // tools=N：工具循环第一轮就是「200 + content 空 + 有 tool_calls」，
      // 不打出调用数会被误读成"空正文的成功"（task-4 验收建议）
      debugPrint(
        '[llm] ok model=${config.normalizedModel} '
        'effort=${reasoningEffort ?? config.reasoningEffort} max_tokens=$maxTokens '
        'chars=${r.text.length} tools=${r.toolCalls.length} '
        '${sw.elapsedMilliseconds}ms',
      );
    } else {
      debugPrint(
        '[llm] 失败 kind=${r.failure?.name} model=${config.normalizedModel} '
        'effort=${reasoningEffort ?? config.reasoningEffort} ${sw.elapsedMilliseconds}ms '
        'detail=${r.detail}',
      );
    }
    return r;
  }

  /// 抬预算的目标值：×3、封顶 [kMaxEscalatedTokens]。已经到顶就返回 null
  /// （不再重试，免得拿同样的预算白跑一趟）。
  ///
  /// ⚠️ 别写成 `(base*3).clamp(base+1, kMaxEscalatedTokens)` —— 当 base 已经等于
  /// 封顶时下界会比上界大，Dart 的 `clamp` 直接抛 ArgumentError（本文件的测试
  /// 「预算已封顶时不再白跑第二趟」抓到的就是这个）。
  static int? _escalatedBudget(int? current) {
    final int base = current ?? kDefaultMaxTokens;
    if (base >= kMaxEscalatedTokens) return null;
    final int tripled = base * 3;
    final int target = tripled > kMaxEscalatedTokens
        ? kMaxEscalatedTokens
        : tripled;
    return target > base ? target : null;
  }

  Future<LlmReply> _chat({
    required List<LlmMessage> messages,
    List<LlmTool>? tools,
    double? temperature,
    int? maxTokens,
    String? reasoningEffort,
    Duration? timeout,
  }) async {
    // ⚠️ 工具循环（目标匹配 / 拆解）一轮常常要 10~40s：推理模型先想再调工具。
    //    全局 12s 会把「模型正在正常思考」误判成 timeout —— 这正是本地实测
    //    「第 1 轮请求失败：timeout」的根因。调用点可传更长的时限。
    final Duration limit = timeout ?? this.timeout;
    if (config.apiKey.trim().isEmpty) {
      return const LlmReply.failure(LlmFailure.noKey, '未配置 API Key');
    }
    // 本发实际用的思考档位：调用点覆盖 > 配置（设置页「思考档位」）
    final String effort = (reasoningEffort ?? config.reasoningEffort).trim();
    // 采样参数：调用点 > 设置页（null = 不带该字段，交端点默认）
    final double? temp = config.resolveTemperature(temperature);
    final int? budget = config.resolveMaxTokens(maxTokens);
    final Uri uri = Uri.parse(config.endpoint);
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey.trim()}',
    };
    final String payload = jsonEncode(<String, dynamic>{
      'model': config.normalizedModel,
      'messages': <Map<String, dynamic>>[
        for (final LlmMessage m in messages) m.toJson(),
      ],
      if (tools != null && tools.isNotEmpty)
        'tools': <Map<String, dynamic>>[
          for (final LlmTool t in tools) t.toJson(),
        ],
      // 推理档位：按调用覆盖优先（台词走 `none`，拆解/工具循环走配置档位）
      if (effort.trim().isNotEmpty) 'reasoning_effort': effort,
      'temperature': ?temp,
      'max_tokens': ?budget,
      if (config.stream) 'stream': true,
    });

    // 严格模式（docs/22 §2.0 / 验收 F-5）：**开发期不重试** —— 一次就把真因报出来，
    // 别让「重试一次」把偶发失败藏过去（这正是宿主说的"出问题直接报错"）。
    // release（strict=false）保持原样：传输层失败重试 1 次。
    final int attempts = config.strict ? 0 : retries;
    LlmFailure lastKind = LlmFailure.network;
    String lastDetail = '网络错误';
    for (int attempt = 0; attempt <= attempts; attempt++) {
      try {
        final http.Response resp = await _http
            .post(uri, headers: headers, body: payload)
            .timeout(limit);
        // HTTP 状态错误不重试：4xx/5xx 重试也不会好
        if (resp.statusCode != 200) {
          return LlmReply.failure(
            LlmFailure.httpError,
            'HTTP ${resp.statusCode}：${_snippet(resp.body)}',
          );
        }
        return _parseOk(resp.body, config);
      } on TimeoutException {
        lastKind = LlmFailure.timeout;
        lastDetail = '请求超时（>${limit.inMilliseconds}ms）';
      } catch (e) {
        // SocketException / ClientException / 其余传输层异常一律按断网兜底
        lastKind = LlmFailure.network;
        lastDetail = '网络不可达：$e';
      }
    }
    return LlmReply.failure(
      lastKind,
      attempts > 0 ? '$lastDetail（已重试 $attempts 次）' : lastDetail,
    );
  }

  LlmReply _parseOk(String body, LlmConfig config) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const LlmReply.failure(LlmFailure.badResponse, '响应不是 JSON 对象');
      }
      final Object? choicesRaw = decoded['choices'];
      if (choicesRaw is! List || choicesRaw.isEmpty) {
        return const LlmReply.failure(LlmFailure.badResponse, '响应缺少 choices');
      }
      final Object? first = choicesRaw.first;
      if (first is! Map<String, dynamic>) {
        return const LlmReply.failure(
          LlmFailure.badResponse,
          'choices[0] 不是对象',
        );
      }
      final Object? msgRaw = first['message'];
      if (msgRaw is! Map<String, dynamic>) {
        return const LlmReply.failure(LlmFailure.badResponse, '响应缺少 message');
      }
      String text = '';
      final Object? content = msgRaw['content'];
      if (content is String) text = content;

      final List<LlmToolCall> calls = <LlmToolCall>[];
      final Object? rawCalls = msgRaw['tool_calls'];
      if (rawCalls is List) {
        for (final Object? c in rawCalls) {
          if (c is! Map<String, dynamic>) continue;
          final Object? fn = c['function'];
          if (fn is! Map<String, dynamic>) continue;
          calls.add(
            LlmToolCall(
              id: '${c['id'] ?? ''}',
              name: '${fn['name'] ?? ''}',
              arguments: _decodeArguments(fn['arguments']),
            ),
          );
        }
      }
      return LlmReply.success(
        text: text,
        toolCalls: calls,
        model: config.normalizedModel,
        // 截断证据：留给 chat() 判断「是不是思考把预算吃光了」
        finishReason: first['finish_reason'] is String
            ? first['finish_reason'] as String
            : null,
        reasoningTokens: _reasoningTokens(decoded['usage']),
      );
    } catch (e) {
      return LlmReply.failure(LlmFailure.badResponse, 'JSON 解析失败：$e');
    }
  }

  /// `usage.completion_tokens_details.reasoning_tokens`（OpenAI 兼容形状）。
  /// 端点不报这个字段时返回 null —— 不猜、不默认 0（0 会让 [starvedByThinking]
  /// 判不出来，null 只是少一条证据，另有 `finish_reason == 'length'` 兜着）。
  static int? _reasoningTokens(Object? usage) {
    if (usage is! Map<String, dynamic>) return null;
    final Object? details = usage['completion_tokens_details'];
    if (details is! Map<String, dynamic>) return null;
    final Object? rt = details['reasoning_tokens'];
    return rt is num ? rt.toInt() : null;
  }

  Map<String, dynamic> _decodeArguments(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final Object? a = jsonDecode(raw);
        if (a is Map<String, dynamic>) return a;
      } catch (_) {
        // 模型吐了坏 JSON 参数 → 空参数，调用方按缺参兜底
      }
    }
    return const <String, dynamic>{};
  }

  static String _snippet(String body) {
    final String t = body.trim().replaceAll('\n', ' ');
    return t.length <= 160 ? t : '${t.substring(0, 160)}…';
  }
}
