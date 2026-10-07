/* v5B 验证 · 变体 A：无执行中任务（exec=null），rings = 已完成 / 待执行 / 待执行
   用途：检查 6A（待执行面板出现「接任务」）
   用法： Get-Content prototype\references\verify-v5b-assets\inject-chain-noexec.js -Raw | agent-browser --session verifier eval --stdin  */
(() => {
  const T = Date.now();
  const D = 86400000;
  const state = {
    bound: true,
    goal: '三个月减十斤',
    newb: false,
    done: 1,
    lv: 1,
    exp: 20,
    coins: 10,
    streak: 1,
    ev: 2,
    failStreak: 0,
    lastStreakDate: new Date().toDateString(),
    attrs: { 体: 2, 智: 1, 专: 1, 心: 1, 交: 1, 生: 1 },
    inv: { 金牌: 1, 双倍: 0 },
    title: '初入江湖',
    ai: { base: '', key: '', model: 'deepseek-chat' },
    l2d: { url: '' },
    voice: false,
    given: [],
    sudden: null,
    exec: null,
    week: { name: '周试炼 · 体魄：累计运动 150 分钟', prog: 30, goal: 150, done: false },
    main: {
      title: '三个月减脂改造',
      theme: '体',
      cycleDays: 8,
      rings: [
        {
          name: '饮水令：今日喝满 8 杯水', diff: 'F', verify: '水杯照片', attr: '体',
          state: '已完成',
          timeline: [
            { t: T - D + 3600000, k: 'start', x: '拔单，开始执行' },
            { t: T - D + 3780000, k: 'shot', x: '第 1 次快照' },
            { t: T - D + 5460000, k: 'done', x: '提交任务，等待验证' }
          ]
        },
        { name: '步行挑战：单日 8000 步', diff: 'E', verify: '步数截图', attr: '体', state: '待执行', timeline: [] },
        { name: '初次奔跑：完成 3 公里', diff: 'D', verify: '跑步 App 截图', attr: '体', state: '待执行', timeline: [] }
      ]
    }
  };
  localStorage.setItem('hostsys_v1', JSON.stringify(state));
  location.reload();
  return 'injected-A';
})();
