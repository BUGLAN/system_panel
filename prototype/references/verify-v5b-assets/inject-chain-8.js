/* v5B 验证 · 变体 C：8 环长链（2 已完成 / 1 执行中 / 5 待执行）— 文件名 7 为历史名
   用途：检查 8（主线页底部按钮 + 最后一节点是否被底栏裁切；环数少时无需滚动，测不出裁切）
   用法： Get-Content prototype\references\verify-v5b-assets\inject-chain-7.js -Raw | agent-browser --session verifier eval -b <base64> */
(() => {
  const T = Date.now();
  const D = 86400000;
  const mk = (name, diff, st, tl) => ({ name, diff, verify: '截图验证', attr: '体', state: st, timeline: tl || [] });
  const doneTl = (seed) => [
    { t: T - D + seed, k: 'start', x: '拔单，开始执行' },
    { t: T - D + seed + 180000, k: 'shot', x: '第 1 次快照' },
    { t: T - D + seed + 240000, k: 'note', x: '补一条备注' },
    { t: T - D + seed + 1860000, k: 'done', x: '提交任务，等待验证' },
    { t: T - D + seed + 1866000, k: 'done', x: '结算入账' }
  ];
  const state = {
    bound: true, goal: '三个月减十斤', newb: false, done: 2, lv: 1, exp: 30, coins: 15,
    streak: 2, ev: 2, failStreak: 0, lastStreakDate: new Date().toDateString(),
    attrs: { 体: 3, 智: 1, 专: 1, 心: 1, 交: 1, 生: 1 },
    inv: { 金牌: 0, 双倍: 0 }, title: '初入江湖',
    ai: { base: '', key: '', model: 'deepseek-chat' }, l2d: { url: '' }, voice: false,
    given: [], sudden: null,
    exec: { rid: 2, startedAt: T - 90000 },
    week: { name: '周试炼 · 体魄：累计运动 150 分钟', prog: 60, goal: 150, done: false },
    main: {
      title: '三个月减脂改造 · 七环长链', theme: '体', cycleDays: 8,
      rings: [
        mk('饮水令：今日喝满 8 杯水', 'F', '已完成', doneTl(3600000)),
        mk('步行挑战：单日 8000 步', 'E', '已完成', doneTl(7200000)),
        mk('初次奔跑：完成 3 公里', 'E', '执行中', [
          { t: T - 90000, k: 'start', x: '拔单，开始执行' },
          { t: T - 45000, k: 'shot', x: '第 1 次快照' }
        ]),
        mk('周跑量累计 15 公里（第 1 周）', 'D', '待执行'),
        mk('周跑量累计 15 公里（第 2 周）', 'D', '待执行'),
        mk('核心训练：平板支撑累计 10 分钟', 'C', '待执行'),
        mk('两周不断跑：连续 14 天打卡', 'C', '待执行'),
        mk('最终检验：完成一次 5 公里跑', 'B', '待执行')
      ]
    }
  };
  localStorage.setItem('hostsys_v1', JSON.stringify(state));
  location.reload();
  return 'injected-C(7rings)';
})();
