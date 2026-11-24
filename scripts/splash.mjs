#!/usr/bin/env node
/**
 * iOS 启动图（apple-touch-startup-image）生成：npm run splash（npm run icons 也会顺带跑）
 *
 * 不配启动图时，从主屏幕冷启动会先白屏约 1 秒（iOS 自己的启动画面）。iOS 只认「像素尺寸和屏幕完全一致」
 * 且 media 命中的那一张，所以每种「点尺寸 × 倍率」各出一张竖屏图：
 *  - 底色、两团光晕照抄 design/base.css 里 #root 的背景，启动图撤掉时只剩图标消失，底色不跳；
 *  - 中间放 apps/web/public/app-icon.svg，切成主屏幕图标那样的圆角，边长固定 120pt。
 *    index.html 的 #root 里先放同一个图标接住：只靠启动图的话，iOS 撤图时网页还没画第一帧，会淡出成白底。
 * 产物写到 apps/web/public/splash/（不进 Service Worker 预缓存，iOS 在「添加到主屏幕」时自己取），
 * 同时改写 apps/web/index.html 里两条标记之间的 <link>，清单只在这里维护一份。
 * 改了图标或底色后重跑；已经加到主屏幕的要删掉重加才换图。
 */
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import sharp from 'sharp';

const root = new URL('../', import.meta.url).pathname;
const pub = join(root, 'apps/web/public');
const outDir = join(pub, 'splash');
const htmlPath = join(root, 'apps/web/index.html');

/**
 * 竖屏的 CSS 点尺寸与倍率（= WebKit 的 device-width / device-height / -webkit-device-pixel-ratio）。
 * 以 Xcode 模拟器机型表（/Library/Developer/CoreSimulator/Profiles/DeviceTypes）为准；
 * Plus 与 mini 的物理屏是缩放出来的，媒体查询报的是 414×736@3 / 375×812@3。
 */
const DEVICES = [
  [440, 956, 3, 'iPhone 16 Pro Max / 17 Pro Max / 18 Pro Max'],
  [430, 932, 3, 'iPhone 14 Pro Max / 15 Pro Max / 15 Plus / 16 Plus'],
  [428, 926, 3, 'iPhone 12 Pro Max / 13 Pro Max / 14 Plus'],
  [420, 912, 3, 'iPhone Air'],
  [414, 896, 3, 'iPhone XS Max / 11 Pro Max'],
  [414, 896, 2, 'iPhone XR / 11'],
  [414, 736, 3, 'iPhone 6s Plus / 7 Plus / 8 Plus'],
  [402, 874, 3, 'iPhone 16 Pro / 17 / 17 Pro / 18 Pro'],
  [393, 852, 3, 'iPhone 14 Pro / 15 / 15 Pro / 16'],
  [390, 844, 3, 'iPhone 12 / 13 / 14 / 16e / 17e'],
  [375, 812, 3, 'iPhone X / XS / 11 Pro / 12 mini / 13 mini'],
  [375, 667, 2, 'iPhone 8 / SE 第二、三代'],
];

/** 底色与光晕：与 design/base.css 的 #root 背景逐项一致（那边改了这里跟着改） */
const BG = '#030208';
const GLOWS = [
  { at: [0.15, 0.1], r: [1200, 700], color: '#8f6bff', alpha: 0.2 },
  { at: [0.9, 0.9], r: [900, 600], color: '#3be8ff', alpha: 0.12 },
];
/** 图标边长（pt）与圆角比例（接近 iOS 主屏幕图标的圆角）；index.html 的 .boot-icon 要跟着一致 */
const ICON_PT = 120;
const ICON_RADIUS = 0.2237;

const BEGIN = '<!-- 启动图：npm run splash 生成，别手改 -->';
const END = '<!-- /启动图 -->';

const fileName = (w, h, s) => `${w}x${h}@${s}x.png`;

/** CSS 的 radial-gradient(rx ry at x% y%, 色, transparent 60%)：rx / ry 是半径，透明只降不透明度 */
function backgroundSvg(w, h, s) {
  const defs = GLOWS.map(
    (g, i) =>
      `<radialGradient id="g${i}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" ` +
      `gradientTransform="translate(${g.at[0] * w} ${g.at[1] * h}) scale(${g.r[0]} ${g.r[1]})">` +
      `<stop offset="0" stop-color="${g.color}" stop-opacity="${g.alpha}"/>` +
      `<stop offset="0.6" stop-color="${g.color}" stop-opacity="0"/></radialGradient>`,
  ).join('');
  const rect = (fill) => `<rect width="${w}" height="${h}" fill="${fill}"/>`;
  const glows = GLOWS.map((_, i) => rect(`url(#g${i})`)).join('');
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w * s}" height="${h * s}" viewBox="0 0 ${w} ${h}">` +
      `<defs>${defs}</defs>${rect(BG)}${glows}</svg>`,
  );
}

async function iconPng(px) {
  const r = Math.round(px * ICON_RADIUS);
  const mask = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}">` +
      `<rect width="${px}" height="${px}" rx="${r}" ry="${r}"/></svg>`,
  );
  return sharp(join(pub, 'app-icon.svg'))
    .resize(px, px)
    .composite([{ input: mask, blend: 'dest-in' }])
    .png()
    .toBuffer();
}

function linkTags() {
  const indent = '    ';
  return DEVICES.map(([w, h, s, name]) =>
    [
      `${indent}<!-- ${name} -->`,
      `${indent}<link`,
      `${indent}  rel="apple-touch-startup-image"`,
      `${indent}  media="(device-width: ${w}px) and (device-height: ${h}px) and (-webkit-device-pixel-ratio: ${s}) and (orientation: portrait)"`,
      `${indent}  href="/splash/${fileName(w, h, s)}"`,
      `${indent}/>`,
    ].join('\n'),
  ).join('\n');
}

mkdirSync(outDir, { recursive: true });
const wanted = new Set(DEVICES.map(([w, h, s]) => fileName(w, h, s)));
for (const f of readdirSync(outDir)) {
  if (!wanted.has(f)) rmSync(join(outDir, f));
}

const icons = new Map();
let total = 0;
for (const [w, h, s] of DEVICES) {
  const px = ICON_PT * s;
  if (!icons.has(px)) icons.set(px, await iconPng(px));
  const out = await sharp(backgroundSvg(w, h, s))
    .composite([{ input: icons.get(px), gravity: 'center' }])
    // 调色板 PNG：底色本来就暗，256 色提亮 4 倍对比也看不出色带，体积从约 200 KB 降到约 80 KB
    .png({ compressionLevel: 9, palette: true })
    .toBuffer();
  const meta = await sharp(out).metadata();
  if (meta.width !== w * s || meta.height !== h * s) {
    throw new Error(`${fileName(w, h, s)} 尺寸不对：${meta.width}×${meta.height}`);
  }
  writeFileSync(join(outDir, fileName(w, h, s)), out);
  total += out.length;
  console.log(
    `✓ splash/${fileName(w, h, s)}  ${w * s}×${h * s}  ${(out.length / 1024).toFixed(0)} KB`,
  );
}

const html = readFileSync(htmlPath, 'utf8');
const a = html.indexOf(BEGIN);
const b = html.indexOf(END);
if (a < 0 || b < a) throw new Error(`index.html 里找不到启动图标记（${BEGIN} … ${END}）`);
const next = `${html.slice(0, a + BEGIN.length)}\n${linkTags()}\n    ${html.slice(b)}`;
if (next !== html) writeFileSync(htmlPath, next);
console.log(
  `共 ${DEVICES.length} 张，${(total / 1024).toFixed(0)} KB；index.html ${next === html ? '无变化' : '已更新'}`,
);
