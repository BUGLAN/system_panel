/**
 * 六维 —— 显示名与顺序按参考稿：体质 / 意志 / 智识 / 感知 / 魅力 / 灵巧。
 * 存档键沿用旧版的单字键（力/体/智/知/魅/敏），结算的六维加成表、日常池、
 * 类目倾向都按这套键写。移植自 flutter-final:app/lib/data/attrs.dart。
 */
export const ATTRS = [
  { k: '力', name: '体质' },
  { k: '体', name: '意志' },
  { k: '智', name: '智识' },
  { k: '知', name: '感知' },
  { k: '魅', name: '魅力' },
  { k: '敏', name: '灵巧' },
] as const;

export type AttrKey = (typeof ATTRS)[number]['k'];

/** 一组六维加成 / 六维数值（键可缺省 = 0） */
export type AttrMap = Partial<Record<AttrKey, number>>;

export const ATTR_KEYS: readonly AttrKey[] = ATTRS.map((a) => a.k);

const NAMES: Record<string, string> = Object.fromEntries(ATTRS.map((a) => [a.k, a.name]));

export function isAttrKey(v: unknown): v is AttrKey {
  return typeof v === 'string' && v in NAMES;
}

/** 单字键 → 显示名；认不出就原样返回 */
export function attrName(k: string): string {
  return NAMES[k] ?? k;
}

/** 六维全 0 */
export function zeroAttrs(): Record<AttrKey, number> {
  return { 力: 0, 体: 0, 智: 0, 知: 0, 魅: 0, 敏: 0 };
}
