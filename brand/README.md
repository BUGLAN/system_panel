# brand/ · 宿主 SYSTEM 品牌资产

> 规范全文（概念、几何、色值、用法与禁例）在 **`docs/23-品牌标识与图标规范.md`**，
> 这里只讲"怎么重新生成"。

## 一条命令全量重生成

```bash
node brand/build.mjs          # 矢量母版 → App 图标 → 原型 favicon → 预览图 → 规格卡
```

分步可用：`node brand/build.mjs sheet`（概念对照）/ `masters`（只出 SVG 母版）/
`card`（只出规格卡）。产物**直接写进** `app/android`、`app/ios`、`prototype/opus-v2-dir`
与 `brand/png`，全部入库、可以直接提交。

首次运行前装一次渲染依赖（node_modules 不入库）：

```bash
cd brand && npm install
```

⚠️ npm 若报 `Invalid Version`（arborist 的老毛病），先装主包再手动补平台二进制：

```bash
npm install --no-audit --no-fund @resvg/resvg-js
npm pack @resvg/resvg-js-darwin-arm64@2.6.2 && tar xzf resvg-resvg-js-darwin-arm64-*.tgz -C node_modules/@resvg --strip-components=1 --one-top-level=resvg-js-darwin-arm64
```

（其他平台同理替换 `-darwin-arm64`；iOS 去 alpha 需要 python3 + Pillow。）

## 目录

| 路径 | 内容 |
| --- | --- |
| `build.mjs` | **唯一真源**。几何、色板、尺寸表全在这里；改标识先改它（以及 docs/23） |
| `strip_alpha.py` | iOS 图标去 alpha 通道（App Store 硬要求），build 末尾自动跑 |
| `logo/*.svg` | 矢量母版：标识（细/粗）、单色剪影、横/竖排组合 |
| `icon/*.svg` | 图标母版：1024 方形（直角/圆角）、自适应前景/背景/单色层 |
| `png/` | 预览：标识、组合、图标、`brand-card.png` 规格卡、`_sheet.png` 对照图 |

## 图标落点（build 自动写入）

- **Android** `app/android/app/src/main/res/mipmap-*/`：旧版 `ic_launcher.png`
  （48-192，≤96 用粗版），自适应三层 `ic_launcher_{foreground,background,monochrome}.png`
  （108-432）＋ `mipmap-anydpi-v26/ic_launcher.xml`（API 25 及以下自动回落旧图）。
- **iOS** `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/`：Contents.json 里
  19 格全部重生成，文件名不动、已去 alpha。
- **原型** `prototype/opus-v2-dir/`：`favicon.svg` / `favicon-16|32|48.png` /
  `apple-touch-icon.png`（index.html 的 `<link rel="icon">` 已接上）。

## 改动的第一原则

`build.mjs` 顶部注释就是设计依据（图形 DNA、弧长、色板）。**不要手改任何生成的
SVG/PNG**——手改的下一次 `node brand/build.mjs` 就被覆盖；要改就改参数重跑，
并同步 `docs/23`。
