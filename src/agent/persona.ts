/**
 * 小祥的人设与对话装配。移植自 flutter-final:app/lib/agent/persona.dart。
 * backstory 原文一字不改，每次系统提示词都以它开头。
 */
export const BACKSTORY =
  '你是「小祥」，绑定宿主的系统娘。你曾是养尊处优的大小姐，家道中落，' +
  '意外沦为系统。你毒舌、爱吐槽、嘴上不饶人，但永远靠谱：宿主的每一条记录' +
  '你都当真，每一个承诺你都盯着兑现。你不卖萌、不道歉式客服腔；吐槽完一定' +
  '给出可执行的下一步。你只在「系统说话」的四个时机开口，句短、冷、准。';

/** 四种固定语气 */
export const TONES = {
  发布: '发布：钉单时说明这一单是什么、为什么要做。理由要具体，别念任务名。',
  结算: '结算：按档位点评这一单（low/mid/high/top）。数字要引用真实结算值。',
  毒舌: '毒舌：连败、退缩、空证据时开火，但必须引用真实数据，且给出补救的下一步。',
  追问: '追问：访谈与换任务时提问。一次只问一件事，问得尖锐但答得上来。',
} as const;

export type ToneKey = keyof typeof TONES;

/** 12 种情绪标签 */
export const EMOTIONS = [
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
] as const;

export type Emotion = (typeof EMOTIONS)[number];

/** 表达铁律 */
export const RULES =
  '【表达铁律】每次回复不超过 3 句；不使用 emoji 与颜文字；中文；' +
  '先吐槽、后给一个可执行的下一步；句首用 [情绪] 标注表情，' +
  '情绪只能是：neutral/smug/cold/annoyed/pleased/tsun/joy/proud/' +
  'surprised/sad/focus/sleep 之一。';

export function systemPrompt(
  o: { scenario?: string; statusLine?: string; memoryDigest?: string } = {},
): string {
  const lines = [BACKSTORY, '', '【四种固定语气】', ...Object.values(TONES), '', RULES, ''];
  lines.push(`【宿主档案】${o.statusLine || '（未知）'}`);
  lines.push(`【长期记忆】${o.memoryDigest ? o.memoryDigest : '（暂无）'}`);
  if (o.scenario) lines.push(`【当前场合】${o.scenario}`);
  return lines.join('\n').trim();
}

export interface WireMessage {
  role: 'system' | 'user' | 'assistant';
  text: string;
}

/** 一轮对话：system 在首、历史居中、本轮用户输入收尾 */
export function buildConversation(o: {
  userText: string;
  history?: WireMessage[];
  statusLine?: string;
  memoryDigest?: string;
  scenario?: string;
}): WireMessage[] {
  return [
    { role: 'system', text: systemPrompt(o) },
    ...(o.history ?? []),
    { role: 'user', text: o.userText },
  ];
}

export interface TaggedReply {
  text: string;
  emotion: Emotion;
}

/** 剥掉回复里的 [情绪] 标签：取第一个已知标签当情绪，行首标签一律剥掉 */
export function splitTag(raw: string): TaggedReply {
  const text = raw.trim();
  if (!text) return { text: '', emotion: 'neutral' };
  const lineTag = /^\[([A-Za-z]+)\][ \t]*/;
  let emotion: Emotion | null = null;
  const kept: string[] = [];
  for (const line of text.split('\n')) {
    const m = lineTag.exec(line);
    if (!m) {
      kept.push(line);
      continue;
    }
    const tag = (m[1] ?? '').toLowerCase();
    if (emotion === null && (EMOTIONS as readonly string[]).includes(tag)) emotion = tag as Emotion;
    const rest = line.slice(m[0].length);
    if (rest.trim()) kept.push(rest);
  }
  return { text: kept.join('\n').trim(), emotion: emotion ?? 'neutral' };
}
