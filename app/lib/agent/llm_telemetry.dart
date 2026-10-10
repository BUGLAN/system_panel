import 'llm_client.dart';

/// ═══════════════════════════════════════════════════════════
///  LLM 调用遥测（docs/22 §2.0「严格模式」配套）
///
///  目的：把兜底从「默默发生」变成「可观测事件」。
///  - 每次 [LlmReply] 进来就计数（成功 / 失败 / 失败类别分布）
///  - 失败保留**最近一次原因**（[lastDetail]），设置页据此回显
///  - 诊断只在内存里，不落盘（重启归零：它是开发期仪表，不是产品数据）
///
///  谁在写：LlmClient.chat（每次应答）· LlmGateway.complete（转发失败）
///  谁在读：设置页 LLM 组「最近一次 LLM 失败」回显 · 测试断言
/// ═══════════════════════════════════════════════════════════
class LlmTelemetry {
  LlmTelemetry._();

  /// 总调用次数（含成功与失败；noKey 短路也算一次）
  static int calls = 0;

  /// 成功次数
  static int ok = 0;

  /// 失败次数（网络/超时/HTTP/坏响应/无 Key）
  static int failures = 0;

  /// 按失败类别分布
  static final Map<LlmFailure, int> byKind = <LlmFailure, int>{};

  /// 最近一次失败原因（LlmReply.detail 原文，给人看）
  static String? lastDetail;

  /// 最近一次失败时间
  static DateTime? lastAt;

  /// 记一次应答。**永不抛**（遥测不能反过来影响主链路）。
  static void record(LlmReply r) {
    try {
      calls++;
      if (r.ok) {
        ok++;
        return;
      }
      failures++;
      final LlmFailure? kind = r.failure;
      if (kind != null) {
        byKind[kind] = (byKind[kind] ?? 0) + 1;
      }
      final String? detail = r.detail;
      if (detail != null && detail.isNotEmpty) lastDetail = detail;
      lastAt = DateTime.now();
    } catch (_) {
      // 遥测自身的任何异常都不外泄
    }
  }

  /// 一行摘要（设置页回显用）：「12/15 成功 · 3 失败」；从未调用过给「—」
  static String get summary =>
      calls == 0 ? '—' : '$ok/$calls 成功 · $failures 失败';

  /// 失败类别分布摘要，如 `network=2 · httpError=1`
  static String get kindSummary {
    if (byKind.isEmpty) return '—';
    return byKind.entries
        .map((MapEntry<LlmFailure, int> e) => '${e.key.name}=${e.value}')
        .join(' · ');
  }

  /// 清空（测试用；也给设置页「清空诊断」留口）
  static void reset() {
    calls = 0;
    ok = 0;
    failures = 0;
    byKind.clear();
    lastDetail = null;
    lastAt = null;
  }
}
