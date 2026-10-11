#!/usr/bin/env node
/**
 * ════════════════════════════════════════════════════════════════════
 *  宿主 SYSTEM · 品牌标识生成器（唯一真源）
 * ════════════════════════════════════════════════════════════════════
 *  一个命令产出「矢量母版 + 全部图标 + 预览图」：
 *
 *      node brand/build.mjs            # 全量：母版 → App 图标 → 原型 favicon → 预览
 *      node brand/build.mjs sheet      # 只出概念对照图 brand/png/_sheet.png
 *      node brand/build.mjs masters    # 只出矢量母版（brand/logo、brand/icon）
 *
 *  设计依据（都不许在这里凭感觉改，改之前先改 docs/23）：
 *    · 图形 = 点顶正六边「核心」＋ 沿六边顺时针走的经验弧 ＋ 弧头亮点 ＋ 中央晶核
 *      —— 六边＝ App 底栏「档案」字形（index.html dock 图标 `M12 3l7.8 4.5v9L12 21…`，
 *         正六边、顶点朝上、外接半径 R）；弧＝等级经验环（原型 #lvArc / docs/10）。
 *    · 弧长 4.5/6 边：从顶点 V0 顺时针点亮到左边正中（九点位置）——亮点不压顶点，
 *      上方留 1.5 边暗轨，「进度游标」的意思最清楚，六边轮廓也还数得出来。
 *    · 颜色只取锁定色板：虚空 #03060E / 面板蓝 #0B1A36 / 电光青 #38E1FF / 屏显白 #EAF7FF。
 *
 *  字体（只有 lockup 用得到）：app/assets/fonts 里的 ShuHei-Bold（中文标题）
 *  与 Tektur-VF（拉丁读数），与原型 @font-face 同源。
 */
import { Resvg } from '@resvg/resvg-js';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const BRAND = join(ROOT, 'brand');

/* ───────────────────────── 色板（锁定，勿改） ───────────────────────── */
const C_VOID = '#03060E'; // 虚空蓝黑
const C_ABYSS = '#060F20';
const C_NAVY = '#0B1A36'; // 面板深蓝
const C_CYAN = '#38E1FF'; // 电光青（唯一主强调）
const C_CYAN_DEEP = '#0EA5E9'; // 深青渐变端
const C_ICE = '#EAF7FF'; // 屏显白

/* ───────────────────────── 几何（512 画布上的母版） ───────────────────────── */
const MK = 512; // 母版画布
const CX = MK / 2; // 256
const CY = MK / 2; // 256
const R = 172; // 六边外接半径（顶点朝上）
const EDGE = R; // 正六边边长 == 外接半径
const PERIM = 6 * R; // 六边周长（原型等级牌同源算法：186.4 是它的另一个尺寸）

/** 点顶正六边顶点：k=0 顶点，顺时针 k=1…5 */
function hexPoints(r, cx = CX, cy = CY) {
  return Array.from({ length: 6 }, (_, k) => {
    const a = (Math.PI / 3) * k;
    return [cx + r * Math.sin(a), cy - r * Math.cos(a)];
  });
}
const n2 = (v) => Math.round(v * 100) / 100;
const hexPath = (r) => hexPoints(r).map((p, i) => `${i ? 'L' : 'M'}${n2(p[0])} ${n2(p[1])}`).join(' ') + 'Z';

/** 沿六边从顶点 V0 顺时针走 dist 距离后的落点（dist 可跨边，含小数） */
function pointAt(dist, r = R) {
  const pts = hexPoints(r);
  let d = dist % (6 * r);
  let k = Math.floor(d / r);
  let t = (d % r) / r;
  const a = pts[k];
  const b = pts[(k + 1) % 6];
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
}

/* ───────────────────────── 标识本体 ───────────────────────── */
/**
 * 透明底标识（512 画布）。
 * @param {object} o
 * @param {number} o.stroke   六边框/弧的线宽
 * @param {number} o.arc      点亮弧长（单位＝边数，可带小数；弧头亮点落在该处）
 * @param {number} o.coreR    中央晶核外接半径
 * @param {number} o.hollow   晶核挖空比例（0 = 实心；.45 = 内部挖掉 45% 的六边环）
 * @param {number} o.nodeR    弧头亮点半径
 * @param {number} o.glow     辉光模糊半径（0 = 不画辉光）
 * @param {string} o.idp      defs id 前缀（同文档多份标识时用来避免撞名）
 */
function markGroup(o = {}) {
  const {
    stroke = 22,
    arc = 4.5,
    coreR = 58,
    hollow = 0,
    nodeR = 19,
    glow = 20,
    glowOpacity = 0.5,
    trackOpacity = 0.26,
    idp = 'm',
  } = o;
  const lit = arc * EDGE;
  const dash = `${n2(lit)} ${n2(PERIM - lit)}`;
  const hex = hexPath(R);
  const [nx, ny] = pointAt(lit);
  const coreRule = hollow > 0 ? `fill-rule="evenodd"` : '';
  const corePath = hollow > 0
    ? `${hexPath(coreR)} ${hexPath(coreR * (1 - hollow))}`
    : hexPath(coreR);

  const defs = `
    <linearGradient id="${idp}arc" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#B6F7FF"/>
      <stop offset=".45" stop-color="${C_CYAN}"/>
      <stop offset="1" stop-color="#1E9BFF"/>
    </linearGradient>
    <linearGradient id="${idp}core" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#EAFDFF"/>
      <stop offset=".55" stop-color="#7FE9FF"/>
      <stop offset="1" stop-color="${C_CYAN}"/>
    </linearGradient>
    <filter id="${idp}blur" x="-70%" y="-70%" width="240%" height="240%">
      <feGaussianBlur stdDeviation="${glow}"/>
    </filter>`;

  const glowLayer = glow > 0
    ? `<g filter="url(#${idp}blur)" opacity="${glowOpacity}">
      <path d="${hex}" fill="none" stroke="${C_CYAN}" stroke-width="${stroke}" stroke-dasharray="${dash}" stroke-linecap="round"/>
      <path d="${corePath}" ${coreRule} fill="${C_CYAN}"/>
      <circle cx="${n2(nx)}" cy="${n2(ny)}" r="${n2(nodeR)}" fill="${C_CYAN}"/>
    </g>`
    : '';

  const body = `${glowLayer}
    <path d="${hex}" fill="none" stroke="${C_CYAN}" stroke-opacity="${trackOpacity}" stroke-width="${stroke}"/>
    <path d="${hex}" fill="none" stroke="url(#${idp}arc)" stroke-width="${stroke}" stroke-dasharray="${dash}" stroke-linecap="round"/>
    <path d="${corePath}" ${coreRule} fill="url(#${idp}core)"/>
    <circle cx="${n2(nx)}" cy="${n2(ny)}" r="${n2(nodeR)}" fill="${C_ICE}"/>`;

  return { defs, body };
}

/** 透明底标识 SVG（512×512） */
function markSvg(o = {}) {
  const { defs, body } = markGroup(o);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${MK}" height="${MK}" viewBox="0 0 ${MK} ${MK}">
  <defs>${defs}
  </defs>
  ${body}
</svg>`;
}

/** 单色版（主题图标 / 单色印刷 / 浅底反白）：无渐变无辉光的剪影，颜色可换 */
function markMonoSvg(o = {}) {
  const { stroke = 34, arc = 4.5, coreR = 62, hollow = 0, nodeR = 30, color = '#fff' } = o;
  const lit = arc * EDGE;
  const dash = `${n2(lit)} ${n2(PERIM - lit)}`;
  const [nx, ny] = pointAt(lit);
  const coreRule = hollow > 0 ? 'fill-rule="evenodd"' : '';
  const corePath = hollow > 0 ? `${hexPath(coreR)} ${hexPath(coreR * (1 - hollow))}` : hexPath(coreR);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${MK}" height="${MK}" viewBox="0 0 ${MK} ${MK}">
  <path d="${hexPath(R)}" fill="none" stroke="${color}" stroke-width="${stroke}"/>
  <path d="${hexPath(R)}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-dasharray="${dash}" stroke-linecap="round"/>
  <path d="${corePath}" ${coreRule} fill="${color}"/>
  <circle cx="${n2(nx)}" cy="${n2(ny)}" r="${n2(nodeR)}" fill="${color}"/>
</svg>`;
}

/* ───────────────────────── 图标底板 ───────────────────────── */
/**
 * 方形图标底板（尺寸即 viewBox）。
 * @param {object} o
 * @param {number} o.size      画布尺寸（1024 / 108 / …）
 * @param {number} o.markR     标识六边的外接半径（画布单位）
 * @param {number} o.rounded   圆角半径（0 = 满幅直角，交给系统裁切）
 * @param {boolean} o.grid     是否铺网格
 * @param {number} o.markStroke 标识线宽（母版 512 单位）
 */
function tileSvg(o = {}) {
  const { size = 1024, markR = 340, rounded = 0, grid = true, idp = 't', halo = 0.5, orbit = false, mark = {}, fill = '' } = o;
  const s = markR / R;
  const g = Math.round(size / 16); // 网格步长 ≈ 画布 1/16
  const { defs, body } = markGroup({ stroke: 30, ...mark, idp: `${idp}m` });
  const clip = rounded > 0
    ? `<clipPath id="${idp}clip"><rect width="${size}" height="${size}" rx="${rounded}" ry="${rounded}"/></clipPath>`
    : '';
  const fadeId = `${idp}fade`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    ${defs}
    ${clip}
    <radialGradient id="${idp}sky" cx="50%" cy="34%" r="80%">
      <stop offset="0" stop-color="#122647"/>
      <stop offset=".45" stop-color="${C_NAVY}"/>
      <stop offset="1" stop-color="${C_VOID}"/>
    </radialGradient>
    <radialGradient id="${idp}halo" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="${C_CYAN}" stop-opacity="${halo * 0.3}"/>
      <stop offset=".45" stop-color="${C_CYAN}" stop-opacity="${halo * 0.1}"/>
      <stop offset="1" stop-color="${C_CYAN}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="${fadeId}">
      <stop offset=".55" stop-color="#fff" stop-opacity=".9"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </radialGradient>
    <mask id="${idp}gridmask"><rect width="${size}" height="${size}" fill="url(#${fadeId})"/></mask>
    <pattern id="${idp}grid" width="${g}" height="${g}" patternUnits="userSpaceOnUse">
      <path d="M${g} 0H0V${g}" fill="none" stroke="${C_CYAN}" stroke-opacity=".075" stroke-width="${Math.max(1, size / 512)}"/>
    </pattern>
    <radialGradient id="${idp}vig" cx="50%" cy="50%" r="72%">
      <stop offset=".5" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity=".55"/>
    </radialGradient>
  </defs>
  <g ${rounded > 0 ? `clip-path="url(#${idp}clip)"` : ''}>
    ${fill
      ? `<rect width="${size}" height="${size}" fill="${fill}"/>`
      : `<rect width="${size}" height="${size}" fill="url(#${idp}sky)"/>
    ${grid ? `<rect width="${size}" height="${size}" fill="url(#${idp}grid)" mask="url(#${idp}gridmask)"/>` : ''}
    ${orbit ? `<circle cx="${size / 2}" cy="${size / 2}" r="${markR * 1.42}" fill="none" stroke="${C_CYAN}" stroke-opacity=".13" stroke-width="${Math.max(1.2, size / 700)}" stroke-dasharray="${n2(size / 42)} ${n2(size / 210)}"/>` : ''}
    <circle cx="${size / 2}" cy="${size / 2}" r="${markR * 1.65}" fill="url(#${idp}halo)"/>`}
    <g transform="translate(${size / 2} ${size / 2}) scale(${n2(s)}) translate(${-CX} ${-CY})">${body}</g>
    ${fill ? '' : `<rect width="${size}" height="${size}" fill="url(#${idp}vig)"/>`}
  </g>
</svg>`;
}

/** 自适应图标前景层：108 画布、透明底、内容落在中央 66dp 安全圆内（六边外接半径 28dp，留 5dp 余量） */
function adaptiveForegroundSvg(markOpts = ICON_MARK_BOLD, idp = 'af') {
  const size = 108;
  const s = 28 / R;
  const { defs, body } = markGroup({ ...markOpts, idp: `${idp}m` });
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>${defs}</defs>
  <g transform="translate(54 54) scale(${n2(s)}) translate(${-CX} ${-CY})">${body}</g>
</svg>`;
}

/** 自适应图标背景层：108 画布、满幅（会被系统按 108 缩放并裁到可视区） */
function adaptiveBackgroundSvg(idp = 'ab') {
  const size = 108;
  const g = 6.75;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    <radialGradient id="${idp}sky" cx="50%" cy="34%" r="80%">
      <stop offset="0" stop-color="#122647"/>
      <stop offset=".45" stop-color="${C_NAVY}"/>
      <stop offset="1" stop-color="${C_VOID}"/>
    </radialGradient>
    <radialGradient id="${idp}fade">
      <stop offset=".55" stop-color="#fff" stop-opacity=".9"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </radialGradient>
    <mask id="${idp}gm"><rect width="${size}" height="${size}" fill="url(#${idp}fade)"/></mask>
    <pattern id="${idp}grid" width="${g}" height="${g}" patternUnits="userSpaceOnUse">
      <path d="M${g} 0H0V${g}" fill="none" stroke="${C_CYAN}" stroke-opacity=".075" stroke-width=".55"/>
    </pattern>
  </defs>
  <rect width="${size}" height="${size}" fill="url(#${idp}sky)"/>
  <rect width="${size}" height="${size}" fill="url(#${idp}grid)" mask="url(#${idp}gm)"/>
</svg>`;
}

/* ───────────────────────── 横排组合（标识 + 字标） ───────────────────────── */
const FONT_FILES = [
  join(ROOT, 'app/assets/fonts/ShuHei-Bold.ttf'),
  join(ROOT, 'app/assets/fonts/Tektur-VF.ttf'),
  join(ROOT, 'app/assets/fonts/NotoSansSC-VF.ttf'),
].filter(existsSync);

function lockupSvg({ vertical = false } = {}) {
  const { defs, body } = markGroup({ stroke: 26, idp: 'lk' });
  const markSize = 200;
  const s = (markSize / 2) / R;
  if (vertical) {
    const W = 560;
    const H = 620;
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>${defs}</defs>
  <g transform="translate(${W / 2} ${230}) scale(${n2(s)}) translate(${-CX} ${-CY})">${body}</g>
  <text x="${W / 2}" y="470" text-anchor="middle" font-family="ShuHei" font-size="118" fill="${C_ICE}">宿主</text>
  <text x="${W / 2}" y="545" text-anchor="middle" font-family="Tektur" font-size="52" letter-spacing="18" fill="${C_CYAN}">SYSTEM</text>
</svg>`;
  }
  const W = 648;
  const H = 300;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>${defs}</defs>
  <g transform="translate(150 150) scale(${n2(s)}) translate(${-CX} ${-CY})">${body}</g>
  <rect x="288" y="72" width="3" height="156" fill="${C_CYAN}" opacity=".55"/>
  <text x="330" y="152" font-family="ShuHei" font-size="104" fill="${C_ICE}">宿主</text>
  <text x="334" y="212" font-family="Tektur" font-size="46" letter-spacing="16" fill="${C_CYAN}">SYSTEM</text>
</svg>`;
}

/* ───────────────────────── 光栅化 ───────────────────────── */
function png(svg, width, { font = true } = {}) {
  const opts = { fitTo: { mode: 'width', value: width } };
  if (font) opts.font = { fontFiles: FONT_FILES, loadSystemFonts: false, defaultFontFamily: 'ShuHei' };
  return new Resvg(svg, opts).render().asPng();
}
const write = (p, data) => {
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, data);
  return p;
};
const writeSvg = (p, svg) => write(p, Buffer.from(svg, 'utf8'));

/* ───────────────────────── 产物清单 ───────────────────────── */
/**
 * 图标切（App 图标用的那套参数）——比母版更粗，缩到 20px 仍立得住。
 * arc 4.5 = 点亮 4.5/6 边，弧头亮点正好落在左边的正中间（九点位置）：
 * 不与顶点粘连，"进度游标"的意思最清楚；上方留 1.5 边暗轨，一眼数得出还差多少。
 */
const ICON_MARK = { stroke: 30, coreR: 60, nodeR: 21, glow: 22 };
const ICON_MARK_BOLD = { stroke: 40, coreR: 64, nodeR: 28, glow: 0, trackOpacity: 0.34 };
/** 图标底板：标识六边外接半径 / 是否铺召唤阵细环（只在大尺寸看得见） */
const ICON_TILE = { markR: 366, orbit: true };

const ANDROID_LEGACY = [
  ['mdpi', 48],
  ['hdpi', 72],
  ['xhdpi', 96],
  ['xxhdpi', 144],
  ['xxxhdpi', 192],
];
const ANDROID_ADAPTIVE = [
  ['mdpi', 108],
  ['hdpi', 162],
  ['xhdpi', 216],
  ['xxhdpi', 324],
  ['xxxhdpi', 432],
];
/** iOS 全套（文件名 → 像素边长，与 AppIcon.appiconset/Contents.json 对齐） */
const IOS_ICONS = [
  ['Icon-App-20x20@1x.png', 20],
  ['Icon-App-20x20@2x.png', 40],
  ['Icon-App-20x20@3x.png', 60],
  ['Icon-App-29x29@1x.png', 29],
  ['Icon-App-29x29@2x.png', 58],
  ['Icon-App-29x29@3x.png', 87],
  ['Icon-App-40x40@1x.png', 40],
  ['Icon-App-40x40@2x.png', 80],
  ['Icon-App-40x40@3x.png', 120],
  ['Icon-App-60x60@2x.png', 120],
  ['Icon-App-60x60@3x.png', 180],
  ['Icon-App-76x76@1x.png', 76],
  ['Icon-App-76x76@2x.png', 152],
  ['Icon-App-83.5x83.5@2x.png', 167],
  ['Icon-App-1024x1024@1x.png', 1024],
];

function buildMasters() {
  const out = [];
  out.push(writeSvg(join(BRAND, 'logo/logo-mark.svg'), markSvg({ stroke: 22, idp: 'mark' })));
  out.push(writeSvg(join(BRAND, 'logo/logo-mark-bold.svg'), markSvg({ ...ICON_MARK_BOLD, idp: 'markb' })));
  out.push(writeSvg(join(BRAND, 'logo/logo-mark-mono.svg'), markMonoSvg()));
  out.push(writeSvg(join(BRAND, 'logo/logo-lockup-h.svg'), lockupSvg()));
  out.push(writeSvg(join(BRAND, 'logo/logo-lockup-v.svg'), lockupSvg({ vertical: true })));
  out.push(writeSvg(join(BRAND, 'icon/app-icon.svg'), tileSvg({ size: 1024, ...ICON_TILE, mark: ICON_MARK, idp: 'ic' })));
  out.push(writeSvg(join(BRAND, 'icon/app-icon-legacy.svg'), tileSvg({ size: 1024, ...ICON_TILE, rounded: 176, mark: ICON_MARK, idp: 'icl' })));
  out.push(writeSvg(join(BRAND, 'icon/adaptive-foreground.svg'), adaptiveForegroundSvg(ICON_MARK_BOLD)));
  out.push(writeSvg(join(BRAND, 'icon/adaptive-background.svg'), adaptiveBackgroundSvg()));
  out.push(writeSvg(join(BRAND, 'icon/adaptive-monochrome.svg'), markMonoSvg()));
  return out;
}

function buildAppIcons() {
  const out = [];
  // ── Android：旧版方图（≤96 用粗版，≥144 用图标切）──
  for (const [d, px] of ANDROID_LEGACY) {
    const svg = tileSvg({
      size: 1024,
      ...ICON_TILE,
      rounded: 176,
      mark: px <= 96 ? ICON_MARK_BOLD : ICON_MARK,
      idp: `al${px}`,
    });
    out.push(write(join(ROOT, `app/android/app/src/main/res/mipmap-${d}/ic_launcher.png`), png(svg, px)));
  }
  // ── Android：自适应图标三层（前景一律粗版：无辉光，缩到 48px 不糊）──
  for (const [d, px] of ANDROID_ADAPTIVE) {
    out.push(write(
      join(ROOT, `app/android/app/src/main/res/mipmap-${d}/ic_launcher_foreground.png`),
      png(adaptiveForegroundSvg(ICON_MARK_BOLD, `af${px}`), px),
    ));
    out.push(write(
      join(ROOT, `app/android/app/src/main/res/mipmap-${d}/ic_launcher_background.png`),
      png(adaptiveBackgroundSvg(`ab${px}`), px),
    ));
    out.push(write(
      join(ROOT, `app/android/app/src/main/res/mipmap-${d}/ic_launcher_monochrome.png`),
      png(markMonoSvg(), px),
    ));
  }
  // ── iOS：全套（≤120pt 用粗版；iOS 图标不许带透明通道）──
  const iosDir = join(ROOT, 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset');
  for (const [name, px] of IOS_ICONS) {
    const svg = tileSvg({
      size: 1024,
      ...ICON_TILE,
      mark: px <= 120 ? ICON_MARK_BOLD : ICON_MARK,
      idp: `ios${px}${name.length}`,
    });
    out.push(write(join(iosDir, name), png(svg, px)));
  }
  return out;
}

function buildFavicon() {
  const dir = join(ROOT, 'prototype/opus-v2-dir');
  const out = [];
  const tile = (px, idp) => png(
    tileSvg({
      size: 1024,
      ...ICON_TILE,
      rounded: 176,
      mark: px <= 48 ? ICON_MARK_BOLD : ICON_MARK,
      idp,
    }),
    px,
  );
  out.push(write(join(dir, 'favicon.svg'), tileSvg({ size: 1024, ...ICON_TILE, rounded: 176, mark: ICON_MARK_BOLD, idp: 'fav' })));
  out.push(write(join(dir, 'favicon-16.png'), tile(16, 'f16')));
  out.push(write(join(dir, 'favicon-32.png'), tile(32, 'f32')));
  out.push(write(join(dir, 'favicon-48.png'), tile(48, 'f48')));
  out.push(write(join(dir, 'apple-touch-icon.png'), tile(180, 'f180')));
  return out;
}

/** 预览图（只入库 brand/png，给文档和评审看） */
function buildPreviews() {
  const out = [];
  out.push(write(join(BRAND, 'png/logo-mark-1024.png'), png(markSvg({ stroke: 22, idp: 'pv' }), 1024)));
  out.push(write(join(BRAND, 'png/logo-mark-dark-512.png'), png(
    tileSvg({ size: 512, fill: C_VOID, mark: { stroke: 22 }, idp: 'pvd' }),
    512,
  )));
  out.push(write(join(BRAND, 'png/logo-lockup-h.png'), png(lockupSvg(), 1800)));
  out.push(write(join(BRAND, 'png/logo-lockup-v.png'), png(lockupSvg({ vertical: true }), 900)));
  out.push(write(join(BRAND, 'png/app-icon-1024.png'), png(tileSvg({ size: 1024, ...ICON_TILE, mark: ICON_MARK, idp: 'pv1' }), 1024)));
  out.push(write(join(BRAND, 'png/app-icon-legacy-512.png'), png(tileSvg({ size: 1024, ...ICON_TILE, rounded: 176, mark: ICON_MARK, idp: 'pv2' }), 512)));
  return out;
}

/** 规格对照图：采用参数 × 各真机尺寸 + 三个落选对照，防止以后"凭感觉"改回去 */
function buildSheet() {
  const variants = [
    ['采用 · 弧 4.5/6 亮点在左边正中', {}],
    ['对照 · 弧 4/6（亮点压在顶点上）', { mark: { arc: 4 } }],
    ['对照 · 弧 5/6（只剩一条暗轨）', { mark: { arc: 5 } }],
    ['对照 · 空心晶核（像六角螺母）', { mark: { hollow: 0.45 } }],
    ['对照 · 满幅渐隐、无召唤阵', { orbit: false, markR: 340 }],
  ];
  const cell = 260;
  const pad = 26;
  const cols = variants.length;
  const W = cols * cell + (cols + 1) * pad;
  const rowDefs = [
    { title: '1024 图标（1:1）', px: 1024 },
    { title: '192 图标（xxhdpi）', px: 192 },
    { title: '48 图标（mdpi · 粗版）', px: 48, bold: true },
    { title: '16 favicon（粗版）', px: 16, bold: true },
  ];
  const H = rowDefs.length * cell + (rowDefs.length + 1) * pad + 34;
  let inner = '';
  variants.forEach(([label, o], i) => {
    rowDefs.forEach((row, j) => {
      const mark = { ...(row.bold ? ICON_MARK_BOLD : ICON_MARK), ...(o.mark || {}) };
      const real = png(
        tileSvg({
          size: 1024,
          ...ICON_TILE,
          markR: o.markR || ICON_TILE.markR,
          orbit: o.orbit !== undefined ? o.orbit : ICON_TILE.orbit,
          rounded: 176,
          mark,
          idp: `s${i}${j}`,
        }),
        row.px,
      );
      const b64 = real.toString('base64');
      const x = pad + i * (cell + pad);
      const y = pad + j * (cell + pad);
      const side = row.px === 1024 ? cell : Math.max(16, Math.round(row.px * (cell / 192)));
      inner += `<image x="${x + (cell - side) / 2}" y="${y + (cell - side) / 2}" width="${side}" height="${side}" shape-rendering="crispEdges" href="data:image/png;base64,${b64}"/>`;
      inner += `<text x="${x}" y="${y - 8}" font-family="KodeMono" font-size="12" fill="#8FA6C4">${row.title}</text>`;
    });
    inner += `<text x="${pad + i * (cell + pad)}" y="${H - 12}" font-family="ShuHei" font-size="15" fill="#38E1FF">${label}</text>`;
  });
  const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <rect width="${W}" height="${H}" fill="#0A0E1A"/>${inner}</svg>`;
  return [write(join(BRAND, 'png/_sheet.png'), png(sheet, W))];
}

/**
 * 品牌规格卡：一图看清标识、字标、图标在真机尺寸/圆角掩码/浅底上的表现，
 * 加锁定色板。入库 brand/png/brand-card.png，docs/23 直接引用。
 */
function buildSpecCard() {
  const W = 1680;
  const H = 1180;
  const b64 = (buf) => buf.toString('base64');
  // —— 素材：透明标识、两种 lockup、浅/深底剪影、预掩码图标（clip 要在底板自己的坐标系里做，
  //      否则 resvg 会把 clipPath 连着外层 transform 一起算，裁出来全是碎角）——
  const mark = png(markSvg({ stroke: 22, idp: 'card-m' }), 1024);
  const lockH = png(lockupSvg(), 1296);
  const lockV = png(lockupSvg({ vertical: true }), 640);
  const monoNavy = png(markMonoSvg({ color: C_NAVY }), 1024);
  const monoIce = png(markMonoSvg({ color: C_ICE }), 1024);
  const tileB64 = b64(png(tileSvg({ size: 1024, ...ICON_TILE, mark: ICON_MARK, idp: 'card-t' }), 1024));
  const maskedTile = (mask, px, idp) => {
    const clip = mask === 'circle' ? `<circle cx="512" cy="512" r="512"/>` : `<rect width="1024" height="1024" rx="230"/>`;
    return png(`<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs><clipPath id="${idp}">${clip}</clipPath></defs>
  <g clip-path="url(#${idp})"><image width="1024" height="1024" href="data:image/png;base64,${tileB64}"/></g>
</svg>`, px);
  };
  const ios180 = b64(maskedTile('squircle', 180, 'm1'));
  const ios120 = b64(maskedTile('squircle', 120, 'm2'));
  const circle = (px, idp) => b64(maskedTile('circle', px, idp));

  const label = (x, y, t, fill = '#8FA6C4') =>
    `<text x="${x}" y="${y}" font-family="KodeMono" font-size="15" letter-spacing="2" fill="${fill}">${t}</text>`;
  const head = (x, y, t) =>
    `<text x="${x}" y="${y}" font-family="ShuHei" font-size="24" fill="#EAF7FF">${t}</text>`;
  const img = (x, y, s, b) => `<image x="${x}" y="${y}" width="${s}" height="${s}" href="data:image/png;base64,${b}"/>`;

  let inner = '';
  // ═══ 左列：标识本体 + 横排组合 ═══
  inner += `<rect x="60" y="80" width="520" height="520" rx="24" fill="${C_VOID}" stroke="${C_CYAN}" stroke-opacity=".18"/>`;
  inner += `<image x="90" y="110" width="460" height="460" href="data:image/png;base64,${b64(mark)}"/>`;
  inner += head(60, 650, '标识 · MARK');
  inner += label(60, 678, 'POINTY-TOP HEX R172 / ARC 4.5:6 / NODE @ 9:00');
  inner += `<image x="60" y="760" width="648" height="300" href="data:image/png;base64,${b64(lockH)}"/>`;
  inner += head(60, 1120, '横排 · LOCKUP H');
  inner += label(60, 1148, '宿主 = SHUHEI BOLD / SYSTEM = TEKTUR +0.35EM');

  // ═══ 中列：图标（掩码 + 尺寸阶梯）═══
  inner += img(640, 90, 180, ios180);
  inner += img(860, 90, 120, ios120);
  inner += img(640, 310, 120, circle(120, 'm3'));
  inner += img(800, 310, 96, circle(96, 'm4'));
  inner += img(936, 310, 72, circle(72, 'm5'));
  [[60, 60], [48, 48], [32, 32], [16, 16]].forEach(([s, px], i) =>
    inner += img(640 + i * 84 + (60 - s) / 2, 470 + (60 - s) / 2, s, circle(px, `mL${i}`)));
  inner += head(640, 650, '图标 · ICONS');
  inner += label(640, 678, 'IOS SQUIRCLE 22.5% / ANDROID CIRCLE / 180-16PX');

  // ═══ 中列下：竖排组合 ═══
  inner += `<image x="640" y="740" width="330" height="330" preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,${b64(lockV)}"/>`;
  inner += head(640, 1120, '竖排 · LOCKUP V');

  // ═══ 右列：色板 + 单色场景 ═══
  inner += head(1120, 72, '色板 · PALETTE（锁定）');
  const chips = [
    ['VOID 虚空', '#03060E'],
    ['NAVY 面板蓝', '#0B1A36'],
    ['CYAN 电光青', '#38E1FF'],
    ['ICE 屏显白', '#EAF7FF'],
  ];
  chips.forEach(([name, c], i) => {
    const cx = 1120 + (i % 2) * 260;
    const cy = 90 + Math.floor(i / 2) * 320;
    inner += `<rect x="${cx}" y="${cy}" width="220" height="220" rx="18" fill="${c}" stroke="${C_CYAN}" stroke-opacity=".25"/>`;
    inner += label(cx, cy + 250, name);
    inner += label(cx, cy + 274, c, '#38E1FF');
  });
  // 浅底：深蓝剪影 / 深底：冰白剪影（单色场景）
  inner += `<rect x="1120" y="740" width="240" height="240" rx="18" fill="#F4F8FF"/>`;
  inner += `<image x="1150" y="770" width="180" height="180" href="data:image/png;base64,${b64(monoNavy)}"/>`;
  inner += `<rect x="1380" y="740" width="240" height="240" rx="18" fill="${C_VOID}" stroke="${C_CYAN}" stroke-opacity=".18"/>`;
  inner += `<image x="1410" y="770" width="180" height="180" href="data:image/png;base64,${b64(monoIce)}"/>`;
  inner += label(1120, 1012, '单色场景：浅底 NAVY / 深底 ICE');
  inner += head(1120, 1076, '单色 · MONO');
  inner += label(1120, 1104, 'ANDROID 13+ THEMED ICON 同款剪影');

  const card = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="cardbg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0A0E1A"/><stop offset="1" stop-color="#060B16"/>
    </linearGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#cardbg)"/>
  <text x="60" y="48" font-family="ShuHei" font-size="26" fill="#EAF7FF">宿主 SYSTEM · 品牌标识规格卡</text>
  <text x="500" y="48" font-family="KodeMono" font-size="14" letter-spacing="3" fill="#38E1FF">BRAND SPEC CARD · v1</text>
  ${inner}
</svg>`;
  return [write(join(BRAND, 'png/brand-card.png'), png(card, W))];
}

/** iOS 图标去 alpha（App Store 不接受带透明通道的图标） */
function stripAlphaIos() {
  const dir = join(ROOT, 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset');
  const py = join(BRAND, 'strip_alpha.py');
  if (!existsSync(py)) return;
  try {
    execFileSync('python3', [py, dir], { stdio: 'inherit' });
  } catch (e) {
    console.warn('[warn] 去 alpha 失败（python3/Pillow 不可用？）:', e.message);
  }
}

/* ───────────────────────── 入口 ───────────────────────── */
const stage = process.argv[2] || 'all';
const report = (title, files) => {
  console.log(`\n▸ ${title}（${files.length}）`);
  for (const f of files) console.log('   ' + f.replace(ROOT + '/', ''));
};

if (stage === 'sheet') {
  report('概念对照图', buildSheet());
} else if (stage === 'masters') {
  report('矢量母版', buildMasters());
} else if (stage === 'card') {
  report('品牌规格卡', buildSpecCard());
} else {
  report('矢量母版', buildMasters());
  report('App 图标', buildAppIcons());
  stripAlphaIos();
  report('原型 favicon', buildFavicon());
  report('预览图', buildPreviews());
  report('品牌规格卡', buildSpecCard());
  console.log('\n完成。');
}
