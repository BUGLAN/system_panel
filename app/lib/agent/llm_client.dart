import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

class LlmConfig {
  const LlmConfig({
    String? baseUrl,
    this.apiKey = '',
    String? model,
  })  : baseUrl = baseUrl ?? kDefaultBase,
        model = model ?? kDefaultModel;

  static const String kDefaultBase = 'https://api.deepseek.com';

  /// 宿主钦定的首发模型名（设置页默认值；请求前经 [normalizedModel] 归一）
  static const String kDefaultModel = 'deepseek-v4.1flash';

  final String baseUrl;
  final String apiKey;
  final String model;

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
  const LlmTool({required this.name, required this.description, this.parameters});

  final String name;
  final String description;

  /// JSON Schema（OpenAI `parameters`），null 时给空对象
  final Map<String, dynamic>? parameters;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': description,
      'parameters': parameters ?? <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}},
    },
  };
}

/// 模型要求调用的一个工具
class LlmToolCall {
  const LlmToolCall({required this.id, required this.name, this.arguments = const <String, dynamic>{}});

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
  })  : ok = true,
        failure = null,
        detail = null;

  const LlmReply.failure(this.failure, this.detail)
    : ok = false,
      text = '',
      toolCalls = const <LlmToolCall>[],
      model = null;

  final bool ok;
  final String text;
  final List<LlmToolCall> toolCalls;
  final String? model;
  final LlmFailure? failure;
  final String? detail;
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

  /// 最小连通性探测：设置页「测试连接」用
  Future<LlmReply> ping() =>
      chat(messages: <LlmMessage>[LlmMessage.user('ping')], maxTokens: 8, temperature: 0);

  /// 对话 / 多模态 / function calling 统一入口。**任何失败都不抛异常**。
  Future<LlmReply> chat({
    required List<LlmMessage> messages,
    List<LlmTool>? tools,
    double? temperature,
    int? maxTokens,
  }) async {
    if (config.apiKey.trim().isEmpty) {
      return const LlmReply.failure(LlmFailure.noKey, '未配置 API Key');
    }
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
        'tools': <Map<String, dynamic>>[for (final LlmTool t in tools) t.toJson()],
      'temperature': ?temperature,
      'max_tokens': ?maxTokens,
    });

    LlmFailure lastKind = LlmFailure.network;
    String lastDetail = '网络错误';
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final http.Response resp = await _http
            .post(uri, headers: headers, body: payload)
            .timeout(timeout);
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
        lastDetail = '请求超时（>${timeout.inMilliseconds}ms）';
      } catch (e) {
        // SocketException / ClientException / 其余传输层异常一律按断网兜底
        lastKind = LlmFailure.network;
        lastDetail = '网络不可达：$e';
      }
    }
    return LlmReply.failure(
      lastKind,
      retries > 0 ? '$lastDetail（已重试 $retries 次）' : lastDetail,
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
        return const LlmReply.failure(LlmFailure.badResponse, 'choices[0] 不是对象');
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
          calls.add(LlmToolCall(
            id: '${c['id'] ?? ''}',
            name: '${fn['name'] ?? ''}',
            arguments: _decodeArguments(fn['arguments']),
          ));
        }
      }
      return LlmReply.success(
        text: text,
        toolCalls: calls,
        model: config.normalizedModel,
      );
    } catch (e) {
      return LlmReply.failure(LlmFailure.badResponse, 'JSON 解析失败：$e');
    }
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
