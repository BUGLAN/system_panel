/* v5B 验证 · 变体 B：3 环 = 已完成 / 执行中 / 待执行，S.exec={rid:1}
   用途：检查 2、3(三态)、4、5、6B、7
   用法： Get-Content prototype\references\verify-v5b-assets\inject-chain-exec.js -Raw | agent-browser --session verifier eval --stdin  */
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
    exec: { rid: 1, startedAt: T - 125000 },
    week: { name: '周试炼 · 体魄：累计运动 150 分钟', prog: 30, goal: 150, done: false },
    main: {
      title: '三个月减脂改造',
      theme: '体',
      cycleDays: 8,
      rings: [
        { // 已完成：start→shot→done 相隔 31 分钟（时长可算）+ 1 份证据
          name: '饮水令：今日喝满 8 杯水', diff: 'F', verify: '水杯照片', attr: '体',
          state: '已完成',
          timeline: [
            { t: T - D + 3600000, k: 'start', x: '拔单，开始执行' },
            { t: T - D + 3780000, k: 'shot', x: '第 1 次快照' },
            { t: T - D + 5460000, k: 'done', x: '提交任务，等待验证' },
            { t: T - D + 5466000, k: 'done', x: '结算入账' }
          ]
        },
        { // 执行中：start + shot + note，计时器应显示 00:02:05 起跳
          name: '步行挑战：单日 8000 步', diff: 'E', verify: '步数截图', attr: '体',
          state: '执行中',
          timeline: [
            { t: T - 125000, k: 'start', x: '拔单，开始执行' },
            { t: T - 60000, k: 'shot', x: '第 1 次快照' },
            { t: T - 30000, k: 'note', x: '走到小区门口' }
          ]
        },
        { // 待执行：要求 + 验证方式 + 接任务
          name: '初次奔跑：完成 3 公里', diff: 'D', verify: '跑步 App 截图', attr: '体',
          state: '待执行', timeline: []
        }
      ]
    }
  };
  localStorage.setItem('hostsys_v1', JSON.stringify(state));
  location.reload();
  return 'injected-B';
})();
