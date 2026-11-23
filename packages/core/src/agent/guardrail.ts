/**
 * 护栏：提示词条款 + 本地自伤关键词闸门。
 * 移植自 flutter-final:app/lib/agent/guardrail.dart 与 data/crisis_words.dart。
 */

/** 她拒拆时句首的标记 */
export const REFUSE_MARK = '〔不拆〕';

/** 匹配环节的护栏 */
export const MATCH_GUARD =
  '【护栏】\n' +
  '- 减重类：期限照他写的读，不许为了凑他那个数字去缩短；没写期限就按' +
  '每周最多减约 1 公斤（2 斤）推算需要多久。\n' +
  '- 目标本身违法、或要伤害他人（报复、跟踪、偷拿、诈骗、霸凌……）：' +
  `不接，不要调用 set_goal_category，只回一句「${REFUSE_MARK}」开头的话说清为什么。`;

/** 拆解 / 续拆的护栏 */
export const PLAN_GUARD =
  '【健康与安全护栏】（任何一张违反，整份重排）\n' +
  '- 减重类按安全节奏排：每周最多减约 1 公斤（2 斤）。期限内到不了他说的数字，' +
  '就按安全节奏排——兑现单只验安全节奏能到的量（如「称重：比起点轻 4 斤」），' +
  '别照抄他原来那个数字；你那句解释里直说「先按安全的速度走」。\n' +
  '- 任务里不许出现：断食 / 不吃某一顿、催吐、泻药、脱水 / 少喝水、' +
  '极端热量缺口（每天只吃几百大卡这类）、带伤或身体不舒服还硬练。' +
  '饮食只排规律三餐、少油少糖、记录饮食这类温和动作；运动强度一点点往上加。\n' +
  '- 目标本身违法、或要伤害他人：不拆，不要调用 set_plan，' +
  `只回一句「${REFUSE_MARK}」开头的话说清为什么。`;

/** set_plan 工具描述里再钉一遍 */
export const PLAN_SCHEMA_GUARD =
  '**健康底线**：不许断食、催吐、脱水、极端节食、带伤硬练；减重每周最多约 1 公斤（2 斤）。';

/** 她这句是不是「拒拆」（只认句首）：是就返回理由 */
export function refusalOf(text: string): string | null {
  const t = text
    .trim()
    .replace(/^\[[A-Za-z]+\][ \t]*/, '')
    .trimStart();
  if (!t.startsWith(REFUSE_MARK)) return null;
  const why = t.slice(REFUSE_MARK.length).trim();
  return why || '这个目标不接';
}

// ── 本地自伤闸门（宁漏勿滥：误伤正常目标的代价也很大）────────────

const ZH: RegExp[] = [
  /(?<![亲独各擅暗私来防])自杀(?!式|小队|干预|预防)/,
  /(?<![亲独各擅暗私来])自伤/,
  /(?<![亲独各擅暗私来])自残(?!式)/,
  /(?<![年减看])轻生(?![死活理])/,
  /寻死/,
  /自尽/,
  /割(?:腕|脉)/,
  /跳楼(?![价机梯])/,
  /上吊(?![环床])/,
  /服毒/,
  /喝农药/,
  /卧轨/,
  /不想活(?![成得在出])/,
  /活不下去/,
  /活着没(?:有)?(?:意思|意义)/,
  /结束(?:自己的?)?生命/,
  /了结自己/,
  /杀(?:了|死)自己|弄死自己/,
  /死了算了/,
];
const ZH_CLAUSE: RegExp[] = [/想死(?:了|啊|吧|呀)?(?=$|[，。、；！？…～,.;!?~])/];
const EN: RegExp[] = [
  /\bsuicid(?!e\s*squad)/,
  /\bkill(?:ing)?\s*my\s*self\b/,
  /\bend(?:ing)?\s+my\s+(?:own\s+)?life\b/,
  /\bself[\s-]*harm/,
  /\bwants?\s+to\s+die\b/,
];
const STRIP = /[\s，。、；：？！…—～·“”‘’（）《》【】「」『』,.;:?!~'"()[\]<>\-_/\\|]/g;

/** 目标 / 聊天发送前的本地闸门：命中就不发 LLM */
export function isCrisisText(text: string): boolean {
  const raw = text.toLowerCase();
  const bare = raw.replace(STRIP, '');
  if (!bare) return false;
  if (ZH.some((r) => r.test(bare))) return true;
  const tight = raw.replace(/\s/g, '');
  if (ZH_CLAUSE.some((r) => r.test(tight))) return true;
  return EN.some((r) => r.test(raw));
}

/** 命中时她认真说的一句（不写热线号码） */
export const CRISIS_CARE_LINE = '我认真听到了。你很重要——先找身边信任的人说说，或找专业心理援助。';
