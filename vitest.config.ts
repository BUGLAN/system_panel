import { defineConfig } from 'vitest/config';

// 三个工作区各跑各的：core（纯逻辑）/ web（前端）/ server（接口，内存 SQLite）
export default defineConfig({
  test: {
    projects: ['packages/core', 'apps/web', 'apps/server'],
  },
});
