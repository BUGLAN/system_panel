/* store.js — 存档与规则：她记得的一切 */
'use strict';

const SAVE_KEY = 'opus-v2/save/v1';
const need = lv => 60 + lv * 40;                       // 升到下一级要的经验
const dailyCount = lv => clamp(1 + Math.ceil(lv / 3), 2, 4);
const rankShift = (r, d) => RANKS[clamp(RARITY[r].i + d, 0, 6)];

const Store = {
  S: null,

  fresh() {
    const t = Clock.now();
    return {
      v: 1, created: t, bound: false,
      name: '', goal: null, rings: [],
      lv: 1, exp: 0, coins: 0,
      attrs: { 力: 3, 敏: 3, 体: 3, 智: 3, 知: 3, 魅: 3 },
      queue: [], active: null, remedyOffer: null,
      history: [],
      items: { dbl: 0, crit: 0, shield: 0, swap: 0 },
      titles: ['bind'], title: 'bind', prevTitle: null,
      streak: 0, bestStreak: 0, lastDoneDay: null,
      failStreak: 0, easy: false,
      retreatDay: null, retreatToday: 0, retreatTotal: 0,
      stats: { done: 0, fail: 0, crit: 0, s: 0, a: 0, dispatched: 0 },
      day: null, hint: null,
      lastSeen: t, prevSeen: t,
      serial: 41, pokes: 0, tongzi: 0,
      forceS: false, forceCrit: false,
    };
  },

  load() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      this.S = raw ? Object.assign(this.fresh(), JSON.parse(raw)) : this.fresh();
    } catch (e) { this.S = this.fresh(); }
    if (typeof this.S.clockShift === 'number') Clock.shift = this.S.clockShift;
    this.S.prevSeen = this.S.lastSeen;
    return this.S;
  },
  save() {
    const S = this.S; if (!S || this.frozen) return;
    S.lastSeen = Clock.now(); S.clockShift = Clock.shift;
    try { localStorage.setItem(SAVE_KEY, JSON.stringify(S)); }
    catch (e) { /* 照片太多会爆配额：只扔照片再存一次 */
      if (S.active) S.active.photos = S.active.photos.slice(-1);
      try { localStorage.setItem(SAVE_KEY, JSON.stringify(S)); } catch (_) { }
    }
  },
  wipe() { localStorage.removeItem(SAVE_KEY); Clock.shift = 0; this.S = this.fresh(); this.frozen = true; },

  /* ── 派生 ── */
  get title() { return TITLE_BY[this.S.title]?.name || ''; },
  weakest() {
    const a = this.S.attrs; const k = ATTRS.map(x => x.k).sort((x, y) => a[x] - a[y])[0];
    return { k, name: ATTR_NAME[k], v: a[k] };
  },
  strongest() {
    const a = this.S.attrs; const k = ATTRS.map(x => x.k).sort((x, y) => a[y] - a[x])[0];
    return { k, name: ATTR_NAME[k], v: a[k] };
  },
  curRing() { return this.S.rings.findIndex(r => r.state === 'cur'); },
  mood() {
    const S = this.S, now = Clock.now();
    const last = S.history[S.history.length - 1];
    if (last && last.res === 'fail' && !last.redeemed && now - last.at < 36 * 36e5) return 'cold';
    if (S.streak >= 3 || (last && last.res === 'done' && (last.crit || 'AS'.includes(last.r)) && now - last.at < 12 * 36e5)) return 'pleased';
    return 'neutral';
  },
  pending() { return this.S.queue.length; },

  /* ── 造单 ── */
  splitAttrs(a, pts) {
    const ks = Object.keys(a).sort((x, y) => a[y] - a[x]);
    const sum = ks.reduce((s, k) => s + a[k], 0);
    const out = {}; let left = pts;
    ks.forEach((k, i) => {
      const v = i === ks.length - 1 ? left : Math.min(left, Math.max(i === 0 ? 1 : 0, Math.round(pts * a[k] / sum)));
      if (v > 0) { out[k] = v; left -= v; }
    });
    if (left > 0) out[ks[0]] = (out[ks[0]] || 0) + left;
    return out;
  },
  mk({ kind, ring = -1, t, n, p, m, a, r, failId, hinted }) {
    const S = this.S;
    return {
      id: uid(), kind, ring, name: t, short: n || '', proof: p, min: m, baseA: a,
      attrs: this.splitAttrs(a, RARITY[r].pt), r, serial: S.serial++, at: Clock.now(), failId, hinted,
    };
  },
  ringTask(i) {
    const g = this.S.rings[i];
    return this.mk({ kind: 'main', ring: i, t: g.t, n: g.n, p: g.p, m: g.m, a: g.a, r: g.r });
  },
  genDaily(n) {
    const S = this.S, C = CATS[S.goal?.cat || 'gen'];
    const pool = [...C.daily.map(d => ({ ...d, own: 1 })), ...DAILY_COMMON];
    const weak = this.weakest().k;
    const out = []; const used = new Set();
    const take = pred => {
      const cand = pool.filter(d => !used.has(d.t) && pred(d));
      if (!cand.length) return null;
      const d = pick(cand); used.add(d.t); return d;
    };
    // 一单专治短板，一单贴主线，其余随缘
    const plan = [d => d.a[weak], d => d.own, () => true, () => true];
    for (let i = 0; i < n; i++) {
      const d = take(plan[i] || (() => true)) || take(() => true); if (!d) break;
      let r = d.r;
      if (S.lv >= 4 && Math.random() < .3) r = rankShift(r, 1);
      if (S.lv >= 8 && Math.random() < .2) r = rankShift(r, 1);
      r = RANKS[Math.min(RARITY[r].i, S.lv >= 8 ? 3 : 2)];
      out.push(this.mk({ kind: 'daily', t: d.t, p: d.p, m: d.m, a: d.a, r }));
    }
    // 昨天她说"替你留着"的那一张
    if (S.hint && S.hint.for === dayKey() && out.length) {
      const h = out[out.length - 1]; h.r = S.hint.r; h.attrs = this.splitAttrs(h.baseA, RARITY[h.r].pt);
      h.hinted = true; h.min = Math.max(h.min, RARITY[h.r].min);
      out.unshift(out.pop());
    }
    return out;
  },

  /* ── 目标拆解（本地规则：关键词 → 阶梯模板） ── */
  shortOf(text, cat) {
    const m = [
      [/半马/, '半马'], [/全马|马拉松/, '全马'], [/(\d+)\s*(公里|km|K)/i, x => x[1] + 'K'],
      [/六级/, '六级'], [/四级/, '四级'], [/雅思/, '雅思'], [/托福/, '托福'], [/考研/, '上岸'], [/考公/, '上岸'],
      [/N[1-5]/i, x => x[0].toUpperCase()], [/(\d+)\s*斤/, x => '−' + x[1] + '斤'], [/早起/, '早起'], [/早睡/, '早睡'],
      [/腹肌/, '腹肌'], [/引体/, '引体'], [/吉他/, '吉他'], [/钢琴/, '钢琴'], [/小说/, '小说'], [/画/, '画'],
    ];
    for (const [re, v] of m) { const x = text.match(re); if (x) return typeof v === 'function' ? v(x) : v; }
    if (cat !== 'gen') return CATS[cat].short;
    const s = text.replace(/[，。！？,.!?\s]/g, '')
      .replace(/^(我要|我想|想要|我希望|希望|争取|坚持|每天|学会|学习)+/, '')
      .replace(/^(一|两|三|四|五|六|半)?(个)?(月|年|周|天)(内|之内)?/, '')
      .replace(/^(学会|坚持|每天)/, '');
    return (s || '变强').slice(0, 4);
  },
  makeGoal(text) {
    text = String(text || '').trim().slice(0, 40);
    const bare = text.replace(/[。.!！?？\s~～]/g, '');
    if (bare.length < 2 || VAGUE.test(bare)) return { vague: true };
    const cat = CAT_ORDER.find(k => CATS[k].re.test(text)) || 'gen';
    let n = 6;
    if (/一年|半年|[三四五六七八九十]个月|百天|100\s*天/.test(text)) n = 8;
    else if (/[两二]个月|60\s*天|八周/.test(text)) n = 7;
    else if (/一周|7\s*天|七天|两周|14\s*天|十天/.test(text)) n = 5;
    const C = CATS[cat], seq = RING_SEQ[n];
    const short = this.shortOf(text, cat);
    const rings = RING_PICK[n].map((ti, i) => {
      const tp = C.rings[ti];
      return { n: tp.n, t: tp.t, p: tp.p, m: tp.m, a: tp.a, r: seq[i], state: i === 0 ? 'cur' : 'lock' };
    });
    rings.push({ n: short, t: text + '——兑现它', p: '能证明你做到了的截图', m: 120, a: C.tilt, r: seq[n - 1], state: 'lock', final: true });
    return { goal: { text, short, cat, n, at: Clock.now() }, rings };
  },
  bind(name, plan) {
    const S = this.S;
    S.bound = true; S.name = name || '宿主';
    S.goal = plan.goal; S.rings = plan.rings;
    S.items.dbl += 1;
    S.queue = [this.ringTask(0)];
    S.day = dayKey();
    S.queue.push(...this.genDaily(dailyCount(S.lv)));
    this.save();
  },
  newGoal(plan) {
    const S = this.S;
    S.goal = plan.goal; S.rings = plan.rings;
    S.queue = S.queue.filter(t => t.kind !== 'main');
    S.queue.unshift(this.ringTask(0));
    this.save();
  },

  /* ── 换日：连击判定、作废隔夜日常、发新单 ── */
  rollDay() {
    const S = this.S; const today = dayKey();
    if (!S.bound || S.day === today) return null;
    const info = { broke: 0, gap: S.day ? dayDiff(S.day, today) : 0 };
    if (S.lastDoneDay && S.streak > 0 && dayDiff(S.lastDoneDay, today) > 1) { info.broke = S.streak; S.streak = 0; }
    const now = Clock.now();
    // 隔夜：日常作废；主线这一环换一张新的（昨天退缩降下来的档位，新的一天还原）
    S.queue = S.queue.filter(t => t.kind === 'remedy' && t.deadline > now);
    if (S.remedyOffer && S.remedyOffer.deadline < now) S.remedyOffer = null;
    const ci = this.curRing();
    if (ci >= 0 && !(S.active && S.active.task.kind === 'main')) S.queue.unshift(this.ringTask(ci));
    S.day = today;
    S.queue.push(...this.genDaily(dailyCount(S.lv)));
    S.hint = S.hint && S.hint.for === today ? null : S.hint;
    S.retreatToday = 0;
    this.save();
    return info;
  },

  /* ── 派单前的上下文：给单子写一句"为什么是你" ── */
  reasonFor(T) {
    const S = this.S, now = Clock.now(), h = new Date(now).getHours();
    const o = [];
    if (T.kind === 'main') {
      const left = S.rings.length - T.ring - 1;
      if (T.ring === 0) o.push(`你说要「${S.goal.text}」。那就从这一步开始。`);
      else if (S.rings[T.ring - 1].held) o.push(`上一环你用了 ${fmtDur(S.rings[T.ring - 1].held)}。这一环，我加了点码。`);
      o.push(left === 0 ? '最后一环。我头顶那一环。' : `离我头顶还差 ${left} 环。`);
      return o[0];
    }
    if (T.kind === 'remedy') return '补救。做完一半，就当那一笔没输。';
    if (T.hinted) return '昨天说好的那张。我替你留着呢。';
    const w = this.weakest();
    if (T.attrs[w.k]) o.push(`你的${w.name}只有 ${w.v}。这一单，专门治它。`);
    const lf = [...S.history].reverse().find(x => x.res === 'fail');
    if (lf && now - lf.at < 48 * 36e5 && !lf.redeemed) o.push(`上次你撑了 ${fmtDur(lf.held)} 就放弃了。今天换一件，再来。`);
    if (T.r === 'F') o.push('很小的一件事。小到你没有借口。');
    if (S.streak >= 2) o.push(`连击 ${S.streak} 天。别断在这一单上。`);
    if (h < 9) o.push('早上做完，一整天都是你的。');
    else if (h >= 22) o.push('这个点了。做完就去睡。');
    o.push('今天的。我挑过了。');
    return o[0];
  },
  /* 取下一单（她手里的第一张），套上演示开关与幼儿档 */
  head() {
    const S = this.S; const T = S.queue[0]; if (!T) return null;
    if (S.forceS && T.r !== 'S') {
      T.r = 'S'; T.attrs = this.splitAttrs(T.baseA, RARITY.S.pt); T.min = Math.max(T.min, 45); S.forceS = false;
    }
    if (S.easy && !T.eased && T.r !== 'F') { T.r = rankShift(T.r, -1); T.attrs = this.splitAttrs(T.baseA, RARITY[T.r].pt); T.eased = true; }
    T.reason = this.reasonFor(T);
    return T;
  },

  /* ── 宿主的回应 ── */
  later() { /* 原样留在她手里：下一次她还是递这一张 */ this.save(); },
  retreat(T) {
    const S = this.S, today = dayKey();
    if (S.retreatDay !== today) { S.retreatDay = today; S.retreatToday = 0; }
    S.retreatToday++; S.retreatTotal++;
    let shame = false;
    if (S.retreatTotal >= 3 && !S.titles.includes('mouth')) {
      S.titles.push('mouth'); S.prevTitle = S.title; S.title = 'mouth'; shame = true;
    }
    if (T.r === 'F') { // F 还退：换一张别的 F
      const nt = this.genDaily(1)[0]; if (nt) { nt.r = 'F'; nt.attrs = this.splitAttrs(nt.baseA, 1); S.queue[0] = nt; }
    } else {
      T.r = rankShift(T.r, -1); T.attrs = this.splitAttrs(T.baseA, RARITY[T.r].pt); T.retreated = (T.retreated || 0) + 1;
    }
    this.save();
    return { n: S.retreatToday, shame };
  },
  swap(T) {
    const S = this.S; if (S.items.swap <= 0) return null;
    S.items.swap--;
    if (T.kind === 'main') { this.save(); return T; } // 主线这一环换不了，券退回也不合理：她直接说不
    const nt = this.genDaily(1)[0]; nt.r = T.r; nt.attrs = this.splitAttrs(nt.baseA, RARITY[T.r].pt);
    S.queue[0] = nt; this.save(); return nt;
  },
  accept(T) {
    const S = this.S;
    S.queue = S.queue.filter(x => x.id !== T.id);
    S.active = { task: T, startAt: Clock.now(), photos: [], dbl: false, crit: false, shield: false, said: {} };
    S.stats.dispatched++;
    this.save();
  },
  useItem(k) {
    const S = this.S, A = S.active; if (!A || S.items[k] <= 0 || A[k]) return false;
    S.items[k]--; A[k] = true; this.save(); return true;
  },
  critChance() {
    const S = this.S, A = S.active; if (!A) return 0;
    return Math.min(.85, .06 + .06 * Math.min(3, A.photos.length) + Math.min(10, S.streak) * .01 + (A.crit ? .25 : 0));
  },

  /* ── 结算 ── */
  settle() {
    const S = this.S, A = S.active, T = A.task, R = RARITY[T.r], now = Clock.now();
    const held = now - A.startAt, photos = A.photos.length;
    const chance = this.critChance(), roll = Math.random();
    const crit = S.forceCrit || roll < chance;
    const near = !crit && roll - chance < .08 ? Math.max(1, Math.round((roll - chance) * 100)) : 0;
    const k = T.kind === 'remedy' ? .5 : 1;
    const baseExp = Math.round(R.exp * k), exp = baseExp * (crit ? 2 : 1) * (A.dbl ? 2 : 1);
    const coin = Math.round(R.coin * k) * (crit ? 2 : 1);
    const before = { lv: S.lv, exp: S.exp, need: need(S.lv) };
    S.exp += exp; const ups = [];
    while (S.exp >= need(S.lv)) { S.exp -= need(S.lv); S.lv++; ups.push(S.lv); }
    S.coins += coin;
    const attrBefore = { ...S.attrs };
    for (const [a, v] of Object.entries(T.attrs)) S.attrs[a] += v;
    const today = dayKey(); let streakUp = false;
    if (S.lastDoneDay !== today) {
      S.streak = S.lastDoneDay && dayDiff(S.lastDoneDay, today) === 1 ? S.streak + 1 : 1;
      S.lastDoneDay = today; streakUp = true; S.bestStreak = Math.max(S.bestStreak, S.streak);
    }
    S.failStreak = 0; S.easy = false;
    S.stats.done++; if (crit) S.stats.crit++; if (T.r === 'S') S.stats.s++; if (T.r === 'A') S.stats.a++;
    let ringClear = -1, finale = false;
    if (T.kind === 'main' && S.rings[T.ring]) {
      const g = S.rings[T.ring]; g.state = 'done'; g.doneAt = now; g.held = held; ringClear = T.ring;
      const nx = T.ring + 1;
      if (nx < S.rings.length) { S.rings[nx].state = 'cur'; S.queue.unshift(this.ringTask(nx)); }
      else finale = true;
    }
    let redeemed = false;
    if (T.kind === 'remedy') { const h = S.history.find(x => x.id === T.failId); if (h) h.redeemed = true; redeemed = true; }
    S.history.push({ id: uid(), name: T.name, r: T.r, kind: T.kind, res: 'done', at: now, held, plan: T.min * 6e4, exp, coin, crit, dbl: A.dbl, photos });
    if (S.history.length > 200) S.history.splice(0, S.history.length - 200);
    S.active = null;
    const titles = this.checkTitles({ crit, r: T.r, redeemed, finale });
    let unshamed = false;
    if (S.title === 'mouth' && S.prevTitle) { S.title = S.prevTitle; S.prevTitle = null; unshamed = true; }
    if (titles.length && S.title !== 'mouth') S.title = titles[titles.length - 1];
    const dailiesLeft = S.queue.filter(t => t.kind === 'daily').length;
    let hint = null;
    if (!dailiesLeft && !S.hint) { // 今天清空 → 她替你预留明天的一张
      const tm = new Date(now); tm.setDate(tm.getDate() + 1);
      S.hint = { r: pick(['C', 'B', 'B', 'A']), for: dayKey(tm.getTime()) }; hint = S.hint;
    }
    this.save();
    return {
      task: T, held, photos, chance, crit, near, dbl: A.dbl, baseExp, exp, coin, attrs: T.attrs, attrBefore,
      before, after: { lv: S.lv, exp: S.exp, need: need(S.lv) }, ups, streak: S.streak, streakUp,
      ringClear, finale, redeemed, titles, unshamed, hint, tooFast: held < 60000, empty: !S.queue.length,
    };
  },
  checkTitles(c) {
    const S = this.S, got = [];
    const add = id => { if (!S.titles.includes(id)) { S.titles.push(id); got.push(id); } };
    if (S.stats.done >= 1) add('first');
    if (c.crit) add('crit');
    if (S.stats.done >= 5) add('done5');
    if (c.redeemed) add('redeem');
    if (S.streak >= 3) add('streak3');
    if (c.r === 'A') add('rankA');
    if (S.stats.done >= 15) add('done15');
    if (S.streak >= 7) add('streak7');
    if (c.r === 'S') add('rankS');
    if (c.finale) add('finale');
    return got;
  },

  /* ── 认输 / 超时 ── */
  fail(how = 'quit') {
    const S = this.S, A = S.active, T = A.task, now = Clock.now();
    const held = now - A.startAt, plan = T.min * 6e4, shield = A.shield;
    const prev = [...S.history].reverse().find(x => x.res === 'fail');
    if (!shield) S.failStreak++;
    S.stats.fail++;
    const wk = S.history.filter(x => x.res === 'fail' && now - x.at < 7 * 864e5).length + 1;
    let last = '';
    if (prev) {
      const d = dayDiff(dayKey(prev.at), dayKey(now));
      last = d === 0 ? '今天早些时候' : d === 1 ? '昨天' : d < 7 ? WEEK[new Date(prev.at).getDay()] : d + ' 天前';
    }
    const tier = shield ? 0 : Math.min(3, S.failStreak);
    if (tier >= 3) S.easy = true;
    const fid = uid();
    S.history.push({ id: fid, name: T.name, r: T.r, kind: T.kind, res: 'fail', at: now, held, plan, shield, how });
    if (T.kind === 'main') S.queue.unshift(T); // 主线不判死：这一环回到她手里
    let remedy = null;
    if (T.kind !== 'remedy') {
      remedy = this.mk({
        kind: 'remedy', t: T.name + '（做一半）', n: '补救', p: T.proof, m: Math.max(5, Math.ceil(T.min / 2)),
        a: T.baseA, r: rankShift(T.r, -2), failId: fid,
      });
      remedy.deadline = now + 24 * 36e5;
      S.remedyOffer = remedy;
    }
    S.active = null;
    this.save();
    return { task: T, held, plan, tier, shield, wk, last, remedy, how, failStreak: S.failStreak };
  },
  takeRemedy(now) {
    const S = this.S, r = S.remedyOffer; if (!r) return null;
    S.remedyOffer = null;
    if (now) S.queue.unshift(r); else S.queue.push(r);
    this.save(); return r;
  },

  buy(k) {
    const S = this.S, it = ITEMS[k];
    if (S.coins < it.price) return false;
    S.coins -= it.price; S.items[k]++; this.save(); return true;
  },
  equip(id) { if (this.S.titles.includes(id) && this.S.title !== 'mouth') { this.S.title = id; this.save(); return true; } return false; },

  /* ── 演示：一个坚持了 23 天的老宿主 ── */
  veteran() {
    const now = Date.now();
    Clock.shift = 0;
    const S = this.fresh();
    this.S = S;
    const plan = this.makeGoal('三个月跑完半马');
    S.bound = true; S.name = '林深'; S.goal = plan.goal; S.rings = plan.rings;
    S.created = now - 23 * 864e5;
    const helds = [11, 19, 23, 38].map(m => m * 6e4 + randi(0, 59) * 1000);
    S.rings.forEach((g, i) => {
      if (i < 4) { g.state = 'done'; g.doneAt = now - (20 - i * 5) * 864e5; g.held = helds[i]; }
      else g.state = i === 4 ? 'cur' : 'lock';
    });
    S.lv = 7; S.exp = 214; S.coins = 340;
    S.attrs = { 力: 9, 敏: 12, 体: 17, 智: 6, 知: 8, 魅: 4 };
    S.titles = ['bind', 'first', 'crit', 'done5', 'redeem', 'streak3', 'done15'];
    S.title = 'done15';
    S.items = { dbl: 1, crit: 1, shield: 1, swap: 2 };
    const y = new Date(now); y.setDate(y.getDate() - 1);
    S.streak = 6; S.bestStreak = 6; S.lastDoneDay = dayKey(y.getTime());
    S.stats = { done: 31, fail: 4, crit: 6, s: 0, a: 1, dispatched: 38 };
    S.history = [
      { id: uid(), name: '慢跑 1.5 公里', r: 'E', kind: 'daily', res: 'fail', at: now - 4 * 864e5, held: 6 * 6e4 + 12e3, plan: 20 * 6e4, redeemed: true },
      { id: uid(), name: '跑完 3 公里，配速随你', r: 'D', kind: 'main', res: 'done', at: now - 3 * 864e5, held: helds[3], plan: 35 * 6e4, exp: 32, coin: 15, crit: false, photos: 2 },
      { id: uid(), name: '跑后拉伸 10 分钟', r: 'F', kind: 'daily', res: 'done', at: now - 864e5 - 3 * 36e5, held: 11 * 6e4, plan: 12 * 6e4, exp: 24, coin: 12, crit: true, photos: 1 },
    ];
    S.day = dayKey(y.getTime());
    S.queue = [this.ringTask(4)];
    S.lastSeen = now - (14 * 60 + 22) * 6e4;
    S.serial = 77;
    S.queue.push(...this.genDaily(3));
    this.save();
    // save() 会把 lastSeen 刷成现在——老宿主要的就是"离开了 14 小时"，再写一次
    S.lastSeen = now - (14 * 60 + 22) * 6e4;
    localStorage.setItem(SAVE_KEY, JSON.stringify(S));
    this.frozen = true; // 马上要重载：别让 pagehide 的自动存档把"离开了 14 小时"冲掉
  },
};
