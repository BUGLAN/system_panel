/**
 * 聊天里她能调的工具：get_status / swap_quest / adjust_plan / remember / recall / summarize_progress。
 * 移植自 flutter-final:app/lib/agent/tools.dart + context_adapter.dart。
 * 安全钳制：工具只改队列（换单、改时限、降档），不直接改经验 / 晶核——数值只能经结算入账。
 */
import { RANK_ATTR_POINTS, isRank } from '../core/data/rank';
import { needFor } from '../core/data/rewards';
import { attrName } from '../core/data/attrs';
import { weakestAttr } from '../core/goal/daily';
import { splitAttrs } from '../core/goal/split';
import { QuestFlow } from '../core/flow/questFlow';
import type { HistoryEntry } from '../core/flow/types';
import { goalDoneCount, goalTotalTasks } from '../core/model/goal';
import type { SaveData } from '../core/save/saveData';
import type { MemoryStore } from './memory';
import { ToolRegistry, objSchema, toolFail, toolOk, type ToolOutcome } from './tools';

export interface StatusSummary extends Record<string, unknown> {
  name: string;
  lv: number;
  exp: number;
  expNeed: number;
  coins: number;
  streak: number;
  bestStreak: number;
  queue: number;
  goal: string;
  planDone: number;
  planTotal: number;
  weakest: string;
  weakestValue: number;
  doneCount: number;
  failCount: number;
  items: Record<string, number>;
  executing: string;
}

export function statusSummary(s: SaveData): StatusSummary {
  const h = s.host;
  const [wk, wv] = weakestAttr(h.attrs);
  return {
    name: h.name,
    lv: h.lv,
    exp: h.exp,
    expNeed: needFor(h.lv),
    coins: h.coins,
    streak: h.streak,
    bestStreak: h.bestStreak,
    queue: s.queue.length,
    goal: s.goal.text,
    planDone: goalDoneCount(s.goal),
    planTotal: goalTotalTasks(s.goal),
    weakest: attrName(wk),
    weakestValue: wv,
    doneCount: h.doneCount,
    failCount: h.failCount,
    items: { ...h.items },
    executing: s.active?.task.name ?? '',
  };
}

/** 她的宿主档案一行（系统提示词【宿主档案】位） */
export function statusLineOf(s: SaveData): string {
  const st = statusSummary(s);
  return (
    `${st.name} · LV${st.lv} · 连击 ${st.streak} · 手里 ${st.queue} 单` +
    (s.goal.short ? ` · 主线「${s.goal.short}」` : '') +
    (st.planTotal ? ` · 主线进度 ${st.planDone}/${st.planTotal} 单` : '') +
    ` · 最弱维 ${st.weakest} ${st.weakestValue} · 连败 ${st.failCount} 次`
  );
}

/** 工具读写存档的接缝：store 侧实现（读最新存档、提交新存档） */
export interface ChatToolContext {
  read(): SaveData;
  commit(next: SaveData): void;
  history(): HistoryEntry[];
  now(): number;
}

export function chatTools(ctx: ChatToolContext, memory: MemoryStore): ToolRegistry {
  const reg = new ToolRegistry();
  reg.register(
    {
      name: 'get_status',
      description: '查宿主状态：等级/经验/晶核/连击/队列/主线进度。',
      parameters: objSchema({}),
      run() {
        const s = statusSummary(ctx.read());
        const goalLine = s.goal ? `「${s.goal}」完成 ${s.planDone}/${s.planTotal} 单` : '未立目标';
        return toolOk(
          `LV${s.lv} · EXP ${s.exp}/${s.expNeed} · 晶核 ${s.coins} · 连击 ${s.streak}（最好 ${s.bestStreak}）\n` +
            `主线：${goalLine}\n` +
            `手里 ${s.queue} 单 · 完成 ${s.doneCount} · 战败 ${s.failCount} · 最弱维：${s.weakest}${s.weakestValue}`,
          s,
        );
      },
    },
    {
      name: 'swap_quest',
      description: '换掉队首的日常/补救单（主线单不可换）。',
      parameters: objSchema({
        rank: { type: 'string', description: '期望档位 F~S，可省略' },
        note: { type: 'string', description: '换单理由，可省略' },
      }),
      run(args): ToolOutcome {
        const f = new QuestFlow(ctx.read());
        const head = f.head;
        if (!head) return toolFail('队列是空的。没有可换的单。');
        if (head.kind === 'main')
          return toolFail('主线上的单不能换。这是你自己选的目标，要么做完，要么认输重来。');
        const out = f.retreat(head, ctx.now());
        if (!out) return toolFail('这张单已经不在她手里了，换不了。');
        const nt = out.replacement;
        if (!nt) return toolFail('池子里的 F 级备胎也空了。原单先留着，明天再说。');
        ctx.commit(f.save);
        const note =
          typeof args['note'] === 'string' && args['note'].trim()
            ? `（${args['note'].trim()}）`
            : '';
        return toolOk(
          `换好了${note}。「${nt.name}」现在是 ${nt.rank} 级 · ${nt.minutes} 分钟（№ ${String(nt.serial).padStart(4, '0')}）。` +
            (out.shame ? '\n——退缩满三次，「口头巨人」给你挂上了。' : ''),
          {
            serial: nt.serial,
            name: nt.name,
            rank: nt.rank,
            minutes: nt.minutes,
            retreatTotal: out.total,
          },
        );
      },
    },
    {
      name: 'adjust_plan',
      description: '调整队首日常/补救单的计划：改时限（分钟）、改档位、顺延。主线单不可调。',
      parameters: objSchema({
        minutes: { type: 'integer', description: '新时限（分钟 5~180）' },
        rank: { type: 'string', description: '目标档位 F~S' },
        postponeMinutes: { type: 'integer', description: '顺延的分钟数' },
        note: { type: 'string', description: '调整理由，可省略' },
      }),
      run(args): ToolOutcome {
        const s = structuredClone(ctx.read());
        const head = s.queue[0];
        if (!head) return toolFail('队列是空的。没有可调整的单。');
        if (head.kind === 'main') return toolFail('主线单的规格不动。要改的是你自己，不是目标。');
        let minutes = head.minutes;
        if (typeof args['minutes'] === 'number') minutes = Math.trunc(args['minutes']);
        else if (typeof args['postponeMinutes'] === 'number')
          minutes = head.minutes + Math.trunc(args['postponeMinutes']);
        minutes = Math.min(180, Math.max(5, minutes));
        const r = typeof args['rank'] === 'string' ? args['rank'].trim().toUpperCase() : '';
        const rank = isRank(r) ? r : head.rank;
        const attrs =
          rank !== head.rank ? splitAttrs(head.attrs, RANK_ATTR_POINTS[rank]) : head.attrs;
        s.queue[0] = { ...head, minutes, rank, attrs };
        ctx.commit(s);
        return toolOk(`改好了：「${head.name}」→ ${rank} 级 · ${minutes} 分钟。做得到吧？`, {
          serial: head.serial,
          name: head.name,
          rank,
          minutes,
        });
      },
    },
    {
      name: 'remember',
      description: '把宿主说的话写进长期记忆（重启仍在）。',
      parameters: objSchema({ text: { type: 'string', description: '要记住的内容' } }, ['text']),
      async run(args) {
        const raw = args['text'];
        if (typeof raw !== 'string' || !raw.trim()) return toolFail('你到底要我记什么？说内容。');
        await memory.add(raw, 'tool', 3);
        return toolOk(`记住了：「${raw.trim()}」。`, { text: raw.trim() });
      },
    },
    {
      name: 'recall',
      description: '查长期记忆：按关键词翻宿主说过的话。',
      parameters: objSchema({
        query: { type: 'string', description: '关键词，可省略（省略=最近几条）' },
      }),
      async run(args) {
        const q = typeof args['query'] === 'string' ? args['query'] : null;
        const rel = await memory.relevant(q, 5);
        if (!rel.length) return toolOk('记忆里还没有这一条。');
        return toolOk(`翻到了 ${rel.length} 条：\n${rel.map((e) => `- ${e.text}`).join('\n')}`);
      },
    },
    {
      name: 'summarize_progress',
      description: '总结近 7 天的执行情况（完成/暴击/战败）。',
      parameters: objSchema({}),
      run() {
        const since = ctx.now() - 7 * 86_400_000;
        const recent = ctx.history().filter((e) => e.at >= since);
        if (!recent.length) return toolOk('近 7 天：空白。一张记录都没有，总结无从谈起。');
        const done = recent.filter((e) => e.result === 'clear').length;
        const quit = recent.filter((e) => e.result === 'quit').length;
        const timeout = recent.filter((e) => e.result === 'timeout').length;
        const exp = recent.reduce((s, e) => s + e.exp, 0);
        const byName = new Map<string, number>();
        for (const e of recent) byName.set(e.name, (byName.get(e.name) ?? 0) + 1);
        const top = [...byName.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? '';
        return toolOk(
          `近 7 天：执行 ${recent.length} 单，完成 ${done}、认输 ${quit}、超时 ${timeout}，入账 EXP ${exp}` +
            `${top ? `，做得最多的是「${top}」` : ''}。`,
          { total: recent.length, done, quit, timeout, exp },
        );
      },
    },
  );
  return reg;
}
