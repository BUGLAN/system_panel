/**
 * 拆解链路的显式失败（fail fast：不吞、不降级、不退回模板）。
 * 移植自 flutter-final:app/lib/state/plan_failure.dart。
 */
export type PlanFailureCode =
  /** 没配 API Key */
  | 'noKey'
  /** 断网 / DNS / 断流 */
  | 'network'
  /** 浏览器跨域被拦（服务商没放行 CORS） */
  | 'cors'
  | 'timeout'
  /** 端点回了非 2xx */
  | 'httpError'
  /** 2xx 但不是预期结构 */
  | 'badResponse'
  /** 工具循环用尽仍没拿到 tasks */
  | 'noPlan'
  /** 工具入参形状不合 schema */
  | 'badShape'
  /** 清单违反计划规则 */
  | 'badPlan'
  /** 目标没通过前置校验 / 她拒拆 */
  | 'badGoal'
  /** 宿主没同意告知页，请求没发出 */
  | 'noConsent'
  /** 超了限速 / 今天的额度（服务器默认 Key 才有每日上限），请求没发出 */
  | 'quota';

export class PlanFailure extends Error {
  constructor(
    readonly code: PlanFailureCode,
    readonly detail: string,
  ) {
    super(`[plan:${code}] ${detail}`);
    this.name = 'PlanFailure';
  }
}

/** 工具入参形状不对：taskIndex 是出错那一张（0 基；-1 = 整份），field 是字段名 */
export class PlanShapeError extends PlanFailure {
  constructor(
    readonly taskIndex: number,
    readonly field: string,
    detail: string,
  ) {
    super('badShape', detail);
    this.name = 'PlanShapeError';
  }

  get where(): string {
    return this.taskIndex < 0 ? this.field : `第 ${this.taskIndex + 1} 张的 ${this.field}`;
  }
}

/** 生成的清单违反计划规则（条数 / 档位倒退 / 时限越界 / 内容空） */
export class PlanRuleError extends PlanFailure {
  constructor(detail: string) {
    super('badPlan', detail);
    this.name = 'PlanRuleError';
  }
}
