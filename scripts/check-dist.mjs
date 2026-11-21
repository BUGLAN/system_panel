#!/usr/bin/env node
/**
 * 构建产物检查（npm run build 之后跑）：
 *  - manifest：应用名「宿主养成系统」、display standalone、192 / 512 / maskable 图标齐
 *  - Service Worker 预缓存：有 index.html 与全部音效，没有任何 .woff2 字体分片
 *  - 产物里没有疑似 API Key（sk- 开头的长串）
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
const fail = (m) => {
  console.error(`✗ ${m}`);
  process.exitCode = 1;
};
const ok = (m) => console.log(`✓ ${m}`);

const man = JSON.parse(readFileSync(join(dist, 'manifest.webmanifest'), 'utf8'));
if (man.name !== '宿主养成系统') fail(`manifest.name = ${man.name}`);
else ok('manifest.name = 宿主养成系统');
if (man.display !== 'standalone') fail(`manifest.display = ${man.display}`);
else ok('display: standalone');
const sizes = man.icons.map((i) => `${i.sizes}${i.purpose === 'maskable' ? ' maskable' : ''}`);
for (const need of ['192x192', '512x512', '512x512 maskable']) {
  if (!sizes.includes(need)) fail(`缺图标 ${need}`);
}
ok(`图标：${sizes.join(' / ')}`);

const sw = readFileSync(join(dist, 'sw.js'), 'utf8');
const urls = [...sw.matchAll(/url:"([^"]+)"/g)].map((m) => m[1]);
if (urls.some((u) => u.endsWith('.woff2'))) fail('预缓存里出现了 woff2 字体分片');
else ok('预缓存不含字体分片');
const audio = readdirSync(join(dist, 'audio'));
const missing = audio.filter((a) => !urls.includes(`audio/${a}`));
if (missing.length) fail(`音效没进预缓存：${missing.join(', ')}`);
else ok(`音效 ${audio.length} 件全部预缓存`);
if (!urls.includes('index.html')) fail('预缓存缺 index.html');

const walk = (d) =>
  readdirSync(d).flatMap((f) => {
    const p = join(d, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
const leaks = walk(dist)
  .filter((p) => /\.(js|html|css|webmanifest)$/.test(p))
  .filter((p) => /sk-[A-Za-z0-9]{20,}/.test(readFileSync(p, 'utf8')));
if (leaks.length) fail(`疑似 Key 泄漏：${leaks.join(', ')}`);
else ok('产物里没有疑似 API Key');
