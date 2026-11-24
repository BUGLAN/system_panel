#!/usr/bin/env node
/**
 * 构建产物检查（npm run build 之后跑）：
 *  前端（apps/web/dist）
 *  - manifest：应用名「宿主养成系统」、display standalone、192 / 512 / maskable 图标齐
 *  - Service Worker：预缓存有 index.html、没有 .woff2；导航回退排除 /api；不缓存任何 /api
 *  - iOS 启动图：不进预缓存；index.html 里每条都有图，像素尺寸和媒体查询对得上
 *  - 前端不再直连模型：产物里没有 chat/completions、Authorization: Bearer
 *  - 没有疑似 Key（sk- 长串）；环境里配了密钥时逐字扫描它们的值
 *  服务端（apps/server/dist）
 *  - 没有疑似 Key、没有硬编码的默认端点；环境里的密钥值不在产物里
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('../', import.meta.url).pathname;
const dist = join(root, 'apps/web/dist');
const serverDist = join(root, 'apps/server/dist');
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
if (!urls.includes('index.html')) fail('预缓存缺 index.html');
if (urls.some((u) => u.startsWith('api/'))) fail('预缓存里出现了 /api');
if (!/denylist:\[\/\^\\\/api\\\/\/\]/.test(sw)) fail('Service Worker 的导航回退没有排除 /api');
else ok('Service Worker 导航回退排除 /api，不缓存接口');
if (urls.some((u) => u.startsWith('splash/'))) fail('预缓存里出现了 iOS 启动图（splash/）');
else ok('预缓存不含 iOS 启动图');

// iOS 启动图：每条 <link> 指向的图都在，且像素尺寸 = 媒体查询的点尺寸 × 倍率（差一个像素 iOS 就不用）
const indexHtml = readFileSync(join(dist, 'index.html'), 'utf8');
const splashLinks = [...indexHtml.matchAll(/<link\b[^>]*apple-touch-startup-image[^>]*>/g)].map(
  ([tag]) => ({
    media: /media="([^"]+)"/.exec(tag)?.[1] ?? '',
    href: /href="([^"]+)"/.exec(tag)?.[1] ?? '',
  }),
);
const splashBad = splashLinks.flatMap(({ media, href }) => {
  const num = (re) => Number(re.exec(media)?.[1]);
  const [w, h, s] = [
    /device-width:\s*(\d+)px/,
    /device-height:\s*(\d+)px/,
    /pixel-ratio:\s*(\d+)/,
  ].map(num);
  const file = join(dist, href.replace(/^\//, ''));
  if (!w || !h || !s || !/orientation:\s*portrait/.test(media)) return [`${href} 的 media 不完整`];
  if (!existsSync(file)) return [`${href} 不存在`];
  const png = readFileSync(file);
  const [pw, ph] = [png.readUInt32BE(16), png.readUInt32BE(20)]; // PNG 的 IHDR 宽高
  return pw === w * s && ph === h * s ? [] : [`${href} 是 ${pw}×${ph}，应为 ${w * s}×${h * s}`];
});
if (!splashLinks.length) fail('index.html 里没有 iOS 启动图（npm run splash）');
else if (!splashLinks.some((l) => l.href.includes('430x932@3x')))
  fail('启动图缺 430×932@3（宿主的 iPhone 15 Pro Max）');
else if (splashBad.length) fail(`iOS 启动图不对：${splashBad.join('；')}`);
else ok(`iOS 启动图 ${splashLinks.length} 张，尺寸与媒体查询一致`);

const walk = (d) =>
  readdirSync(d).flatMap((f) => {
    const p = join(d, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
const textFiles = (d) => walk(d).filter((p) => /\.(js|mjs|html|css|webmanifest|json)$/.test(p));

const webFiles = textFiles(dist);
const read = (p) => readFileSync(p, 'utf8');
const direct = webFiles.filter((p) =>
  /chat\/completions|Bearer \$\{|Authorization:\s*`Bearer/.test(read(p)),
);
if (direct.length) fail(`前端产物里还有直连模型的代码：${direct.join(', ')}`);
else ok('前端不直连模型（没有 chat/completions、Bearer）');

const secrets = ['LLM_API_KEY', 'APP_ENCRYPTION_KEY', 'ADMIN_PASSWORD']
  .map((k) => process.env[k])
  .filter((v) => v && v.length >= 8);
const scan = (files, label) => {
  const leaks = files.filter((p) => {
    const t = read(p);
    return /sk-[A-Za-z0-9]{20,}/.test(t) || secrets.some((s) => t.includes(s));
  });
  if (leaks.length) fail(`${label}疑似 Key 泄漏：${leaks.join(', ')}`);
  else
    ok(
      `${label}没有疑似 Key${secrets.length ? `（另逐字扫了 ${secrets.length} 个环境密钥）` : ''}`,
    );
};
scan(webFiles, '前端产物里');

if (existsSync(serverDist)) {
  const serverFiles = textFiles(serverDist).filter((p) => !p.endsWith('.map'));
  scan(serverFiles, '服务端产物里');
  const hard = serverFiles.filter((p) =>
    /https:\/\/api\.(openai|deepseek|anthropic|moonshot)\./.test(read(p)),
  );
  if (hard.length) fail(`服务端产物里有硬编码的默认端点：${hard.join(', ')}`);
  else ok('服务端产物里没有硬编码的默认端点');
} else fail('没有服务端产物（先 npm run build）');
