/* v5B 验证 · 清档：回到「绑定降临」起点（新宿主）
   用途：检查 9（扫描→降临→报目标→签订→生成→钉单）
   用法： Get-Content prototype\references\verify-v5b-assets\inject-empty.js -Raw | agent-browser --session verifier eval --stdin  */
(() => {
  localStorage.removeItem('hostsys_v1');
  location.reload();
  return 'cleared';
})();
