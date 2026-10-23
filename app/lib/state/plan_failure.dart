/// 拆解链路的**显式失败**（fail fast）。
///
/// 2026-10-23 宿主定调：本项目当前**只供开发者使用** —— 任何一处失败都必须
/// 当场抛出来、让调用方看到原因，**不许**吞异常、不许返回默认值、不许静默
/// 降级到模板。所以拆解链路上不再有「取不到就退回类别模板」这条路：
///
///   · 没配 Key / 网络失败 / HTTP 非 200 / 模型没交工具 → [PlanGenerationError]
///   · 工具参数形状不对 → [PlanShapeError]（**不**回填给模型让它「重来」）
///   · 生成出来的清单不合规 → [PlanRuleError]（规则校验不过同样抛）
///
/// 三类都带 [code]（程序可判）与 [detail]（人可读），`toString()` 直接可贴
/// 进 logcat / 诊断条。
library;

/// 拆解失败的大类 —— 调用方（UI/测试）按它分流，不必解析文案。
enum PlanFailureCode {
  /// 没配 API Key（连请求都发不出去）
  noKey,

  /// 连不上 / DNS / 断流
  network,

  /// 超过时限
  timeout,

  /// 端点回了非 200
  httpError,

  /// 200 但不是预期结构
  badResponse,

  /// 工具循环用尽仍没拿到 tasks
  noPlan,

  /// 工具的入参形状不合 schema
  badShape,

  /// 生成的清单违反了计划规则（档位/时限/条数/内容）
  badPlan,

  /// 目标本身没通过前置校验（空泛 / 太短）
  badGoal,
}

/// 拆解链路的失败基类。**永远带得住原因**，`toString()` 给人看。
sealed class PlanFailure implements Exception {
  const PlanFailure(this.code, this.detail);

  final PlanFailureCode code;

  /// 人可读的原因（会原样进诊断条 / 测试断言）
  final String detail;

  @override
  String toString() => '[plan:${code.name}] $detail';
}

/// 生成没跑通（网络 / 协议 / 模型没交工具 / 目标不合格）。
class PlanGenerationError extends PlanFailure {
  const PlanGenerationError(super.code, super.detail);
}

/// 工具入参形状不对（缺字段 / 类型错 / 档位不在 F~S / 分钟数非正）。
///
/// [taskIndex] 是出错的那一张（0 基；-1 = 整份形状的问题），[field] 是字段名。
class PlanShapeError extends PlanFailure {
  const PlanShapeError(this.taskIndex, this.field, String detail)
    : super(PlanFailureCode.badShape, detail);

  final int taskIndex;
  final String field;

  /// 「第 3 张的 minutes」这种人话定位
  String get where => taskIndex < 0 ? field : '第 ${taskIndex + 1} 张的 $field';
}

/// 生成的清单违反计划规则（条数不符 / 档位倒退 / 时限越界 / 内容空泛）。
class PlanRuleError extends PlanFailure {
  const PlanRuleError(String detail) : super(PlanFailureCode.badPlan, detail);
}
