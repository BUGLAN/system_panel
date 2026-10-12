import 'dart:async';

import 'package:flutter/foundation.dart';

import 'copy.dart';
import 'llm_client.dart';
import 'llm_telemetry.dart';

/// ═══════════════════════════════════════════════════════════
///  CopyLlmGateway 的真实现（docs/18 §3.1-T5 集成件）
///
///  copy.dart 只依赖 [CopyLlmGateway] 这个最小面；本类用几行适配器把
///  t9 的 [LlmClient] 插进去。两条铁律与接口一致：
///   1. `configured == false`（没配 Key）→ `complete` 直接返回 null，零网络等待；
///   2. **任何失败都返回 null**（无网/超时/坏 JSON/空话）——由调用方
///      （SystemCopyProvider / 聊天服务）逐字回退内置文案，App 永不因 LLM 卡住。
///
///  LlmClient 本身永不抛异常（失败折叠成 `LlmReply.failure`），这里的
///  try/catch 只是兜「调用方给的 timeout 短于客户端内部超时」那一层。
/// ═══════════════════════════════════════════════════════════
class LlmGateway implements CopyLlmGateway {
  LlmGateway(this._client);

  final LlmClient _client;

  /// 最近一次应答（诊断用）。docs/22 §2.0：严格模式要把失败原因摆到宿主面前，
  /// 而 [complete] 的契约是「失败返回 null」——原因只能从这里读。
  LlmReply? lastReply;

  @override
  bool get configured => _client.config.apiKey.trim().isNotEmpty;

  @override
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
    String? reasoningEffort,
  }) async {
    if (!configured) {
      // 短路也要记账：无 Key 是最常见的一类「她哑了」，不能从遥测里消失
      final LlmReply r = const LlmReply.failure(LlmFailure.noKey, '未配置 API Key');
      lastReply = r;
      LlmTelemetry.record(r);
      return null;
    }
    try {
      final Future<LlmReply> call = _client.chat(
        messages: <LlmMessage>[
          for (final Map<String, dynamic> m in messages) _fromWire(m),
        ],
        temperature: temperature,
        maxTokens: maxTokens,
        reasoningEffort: reasoningEffort,
      );
      // 客户端内部有自己的 12s 超时；调用方（copy 用 8s）给得更短就听调用方的
      final LlmReply r =
          await (timeout == null ? call : call.timeout(timeout));
      lastReply = r;
      if (!r.ok) {
        // 失败日志由 [LlmClient.chat] 统一打（它是所有路径的唯一咽喉）——
        // 这里再打一条会变成同一失败两条日志（task-4 验收建议）。
        return null;
      }
      final String text = r.text.trim();
      if (text.isEmpty) {
        // HTTP 200 但正文为空：推论模型把 max_tokens 花在思考上的典型症状。
        // 客户端那行只显示 `chars=0 tools=0`，这一行给出**为什么**。
        debugPrint('[llm] 空正文（HTTP 200）model=${_client.config.normalizedModel} '
            'maxTokens=$maxTokens reasoning_effort=${_client.config.reasoningEffort} '
            '— 多半是 max_tokens 被思考用尽');
        return null;
      }
      return text;
    } catch (e) {
      // 调用方给的 timeout 短于客户端内部超时 → Future.timeout 抛 TimeoutException
      debugPrint('[llm] 调用侧超时/异常：$e');
      return null;
    }
  }

  /// OpenAI 线格式 → [LlmMessage]（[LlmMessage.toJson] 的逆过程）。
  /// content 是 String 直取；是数组时拆 `type:text` 拼正文、
  /// `type:image_url` 收进 images（聊天/文案链路用不到图，纯为契约完整）。
  static LlmMessage _fromWire(Map<String, dynamic> m) {
    final String role = '${m['role'] ?? 'user'}';
    final Object? content = m['content'];
    if (content is String) return LlmMessage(role, content);
    if (content is! List) return LlmMessage(role, '');
    final StringBuffer text = StringBuffer();
    final List<String> images = <String>[];
    for (final Object? part in content) {
      if (part is! Map) continue;
      final Object? type = part['type'];
      if (type == 'text') {
        text.write('${part['text'] ?? ''}');
      } else if (type == 'image_url') {
        final Object? iv = (part['image_url'] as Map?)?['url'];
        if (iv is String) images.add(iv);
      }
    }
    return LlmMessage(role, text.toString(), images: images);
  }
}
