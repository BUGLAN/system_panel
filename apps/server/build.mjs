// 服务端打包：src → dist/main.mjs + dist/cli.mjs（@host/core 一起打进去，原生依赖留外部），迁移目录复制到 dist/drizzle
import { build } from 'esbuild';
import { cpSync, rmSync } from 'node:fs';

rmSync('dist', { recursive: true, force: true });
const common = {
  bundle: true,
  platform: 'node',
  target: 'node22',
  format: 'esm',
  sourcemap: true,
  external: ['better-sqlite3', '@node-rs/argon2'],
  banner: {
    js: "import { createRequire as __cr } from 'node:module'; const require = __cr(import.meta.url);",
  },
  logLevel: 'warning',
};
await build({
  ...common,
  entryPoints: { main: 'src/main.ts', cli: 'src/cli/admin.ts' },
  outdir: 'dist',
  outExtension: { '.js': '.mjs' },
});
cpSync('drizzle', 'dist/drizzle', { recursive: true });
console.log('✓ 服务端已打包到 apps/server/dist');
