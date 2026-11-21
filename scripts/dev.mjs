#!/usr/bin/env node
// 开发：同时起服务端（tsx watch，:8787）和前端（vite，:5173，/api 代理到服务端）
import { spawn } from 'node:child_process';

const run = (name, args) => {
  const p = spawn('npm', ['run', ...args], {
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  p.on('exit', (code) => {
    console.log(`[dev] ${name} 退出（${code}）`);
    process.exit(code ?? 0);
  });
  return p;
};
const procs = [run('server', ['dev:server']), run('web', ['dev:web'])];
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => procs.forEach((p) => p.kill(sig)));
