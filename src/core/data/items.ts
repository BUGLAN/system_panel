/**
 * 道具（晶核唯一去处）。顺序、名字、价格、颜色移植自 flutter-final:app/lib/data/items.dart。
 * 文案按 docs/01 第 6 节定案改成与结算规则一致（数值不动）；护盾换成「超时免判负一次」。
 */
export type ItemId = 'crit' | 'dbl' | 'shield' | 'patch';

export interface Item {
  id: ItemId;
  name: string;
  price: number;
  desc: string;
  /** exec = 执行中装载；shop = 补给站里直接使用 */
  use: 'exec' | 'shop';
  /** 牌面编号 */
  code: string;
  /** 档位色（CSS 变量名，见 tokens.css） */
  color: string;
  /** 购买所需等级（0 = 不限） */
  lv: number;
}

export const ITEMS: readonly Item[] = [
  {
    id: 'crit',
    name: '暴击芯片',
    price: 45,
    desc: '本单暴击率 +25%。暴击时 EXP 与晶核 ×2。',
    use: 'exec',
    code: 'CRIT',
    color: 'var(--hot)',
    lv: 0,
  },
  {
    id: 'dbl',
    name: '双倍卡',
    price: 60,
    desc: '本单 EXP ×2，晶核不翻倍。贪心是第一生产力。',
    use: 'exec',
    code: 'DBL',
    color: 'var(--gold)',
    lv: 0,
  },
  {
    id: 'shield',
    name: '护盾',
    price: 90,
    desc: '计时单到点时替你挡一次：不判负，再续原时长的一半。',
    use: 'exec',
    code: 'SHIELD',
    color: 'var(--cyan)',
    lv: 2,
  },
  {
    id: 'patch',
    name: '补签券',
    price: 30,
    desc: '补回一天断签，连胜 +1。这叫补救，不叫作弊。',
    use: 'shop',
    code: 'PATCH',
    color: 'var(--mint)',
    lv: 0,
  },
];

export function itemById(id: string): Item | undefined {
  return ITEMS.find((i) => i.id === id);
}

/** 执行中可装载的三样，顺序照原型写死 */
export const EXEC_ITEM_IDS: readonly ItemId[] = ['dbl', 'crit', 'shield'];

/** 执行类道具的持有总数（执行页「道具」角标） */
export function execItemCount(items: Record<string, number>): number {
  return ITEMS.filter((i) => i.use === 'exec').reduce((s, i) => s + (items[i.id] ?? 0), 0);
}
