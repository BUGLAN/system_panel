/**
 * 类目查找、访谈卡组、空泛目标判定、访谈记忆、见面礼。
 * 移植自 flutter-final:app/lib/state/goal_gen.dart。
 */
import { CATEGORIES } from '../data/categories';
import type { GoalCategory, InterviewCard } from '../data/categoryTypes';

/** 绑定仪式的目标预设（原样六条） */
export const ONBOARD_PRESETS: readonly string[] = [
  '三个月跑完半马',
  '一个月早睡早起',
  '考研上岸',
  '半年减重 10 斤',
  '学会画画',
  '变优秀',
];

export const CATEGORY_IDS: readonly string[] = CATEGORIES.map((c) => c.id);

const BY_ID = new Map(CATEGORIES.map((c) => [c.id, c]));

/** 按 id 取类目；认不出就给 gen（变强） */
export function categoryOf(id: string): GoalCategory {
  return BY_ID.get(id) ?? (BY_ID.get('gen') as GoalCategory);
}

export function isCategoryId(id: string): boolean {
  return BY_ID.has(id);
}

/** 通用追加卡（等级更高才问） */
const COMMON_SLOT: InterviewCard = {
  id: 'common.slot',
  question: '一周愿意投入几个时段？',
  options: ['2 个', '3~4 个', '5 个以上'],
};
const COMMON_HISTORY: InterviewCard = {
  id: 'common.history',
  question: '上次立目标是什么结果？',
  options: ['没开始就放弃了', '坚持了几天', '完成了'],
};

/** 按等级出 3~5 张卡：lv1 = 类别 3 张；lv2~3 追加「投入时段」；lv4+ 再追加「上次结果」 */
export function interviewCardsFor(cat: GoalCategory, level = 1): InterviewCard[] {
  const cards = [...cat.cards];
  if (level >= 2) cards.push(COMMON_SLOT);
  if (level >= 4) cards.push(COMMON_HISTORY);
  return cards;
}

const VAGUE =
  /^(变优秀|变强|变好|变得更好|努力|成功|自律|提升自己|加油|好好学习|做更好的自己|改变|有钱|发财|开心|快乐)$/;

/** 空泛判定：剥掉标点后少于 2 字，或整句就是空话 */
export function isVagueGoal(text: string): boolean {
  const bare = text.replace(/[。.!！?？\s~～]/g, '');
  if ([...bare].length < 2) return true;
  return VAGUE.test(bare);
}

/** 访谈即第一批记忆：目标一句 + 逐卡问答一句 */
export function memoriesFromInterview(o: {
  cat: GoalCategory;
  answers: Record<string, string>;
  goalText: string;
  days: number;
}): string[] {
  const out = [`宿主立了新目标：「${o.goalText.trim()}」（${o.cat.label}向，期限 ${o.days} 天）。`];
  for (const card of interviewCardsFor(o.cat)) {
    const a = o.answers[card.id];
    if (a) out.push(`${card.question}——${a}。`);
  }
  return out;
}

/** 见面礼：双倍卡 ×1 */
export const BIND_GIFT = { item: 'dbl', count: 1, kicker: '见面礼', text: '双倍卡 ×1' } as const;

export function applyBindGift(items: Record<string, number>): Record<string, number> {
  return { ...items, [BIND_GIFT.item]: (items[BIND_GIFT.item] ?? 0) + BIND_GIFT.count };
}
