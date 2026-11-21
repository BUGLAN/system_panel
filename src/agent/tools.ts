/**
 * 工具注册表。移植自 flutter-final:app/lib/agent/tools.dart。
 *  - ToolRegistry（宽容）：工具失败折成回执，聊天用
 *  - StrictToolRegistry：工具失败当场抛，拆解 / 匹配用（失败不许藏进多轮循环）
 */
import { PlanFailure } from '../core/goal/planFailure';
import type { LlmTool } from './llmClient';

export interface ToolOutcome {
  ok: boolean;
  /** 给人看（聊天回执条） */
  message: string;
  /** 给程序看 */
  data?: Record<string, unknown>;
}

export const toolOk = (message: string, data?: Record<string, unknown>): ToolOutcome => ({
  ok: true,
  message,
  ...(data ? { data } : {}),
});
export const toolFail = (message: string, data?: Record<string, unknown>): ToolOutcome => ({
  ok: false,
  message,
  ...(data ? { data } : {}),
});

export interface AgentTool {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
  run(args: Record<string, unknown>): ToolOutcome | Promise<ToolOutcome>;
}

export class ToolExecutionError extends Error {
  constructor(
    readonly tool: string,
    readonly detail: string,
  ) {
    super(`[tool:${tool}] ${detail}`);
    this.name = 'ToolExecutionError';
  }
}

export class ToolRegistry {
  protected readonly tools = new Map<string, AgentTool>();

  register(...ts: AgentTool[]): this {
    for (const t of ts) this.tools.set(t.name, t);
    return this;
  }

  get all(): AgentTool[] {
    return [...this.tools.values()];
  }

  get names(): string[] {
    return [...this.tools.keys()];
  }

  get size(): number {
    return this.tools.size;
  }

  get(name: string): AgentTool | undefined {
    return this.tools.get(name);
  }

  /** 给 LLM 的 tools 定义 */
  defs(): LlmTool[] {
    return this.all.map((t) => ({
      name: t.name,
      description: t.description,
      parameters: t.parameters,
    }));
  }

  async execute(name: string, args: Record<string, unknown> = {}): Promise<ToolOutcome> {
    const t = this.tools.get(name);
    if (!t) return toolFail(`没有「${name}」这个工具。`);
    try {
      return await t.run(args);
    } catch (e) {
      return toolFail(`工具 ${name} 执行出错：${e instanceof Error ? e.message : String(e)}`);
    }
  }
}

export class StrictToolRegistry extends ToolRegistry {
  override async execute(name: string, args: Record<string, unknown> = {}): Promise<ToolOutcome> {
    const t = this.tools.get(name);
    if (!t) throw new ToolExecutionError(name, `没有这个工具（已注册：${this.names.join(' / ')}）`);
    let out: ToolOutcome;
    try {
      out = await t.run(args);
    } catch (e) {
      if (e instanceof PlanFailure || e instanceof ToolExecutionError) throw e;
      throw new ToolExecutionError(
        name,
        `工具内部异常：${e instanceof Error ? e.message : String(e)}`,
      );
    }
    if (!out.ok) throw new ToolExecutionError(name, out.message);
    return out;
  }
}

/** JSON Schema 小工具 */
export function objSchema(
  properties: Record<string, unknown>,
  required?: string[],
): Record<string, unknown> {
  return { type: 'object', properties, ...(required?.length ? { required } : {}) };
}
