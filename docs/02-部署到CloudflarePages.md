# 02 · 部署到 Cloudflare Pages

> 纯静态站：没有后端、没有账号、没有云同步。LLM 由用户在设置页自己填端点和 Key，浏览器直连服务商。

## 一、本地先过一遍

```bash
npm ci
```

```bash
npm run check
```

`check` = 类型检查 + 单测 + 构建 + 构建产物检查（manifest 字段、预缓存里有全部音效且没有字体分片、产物里没有疑似 Key）。全绿再部署。

产物在 `dist/`。想在本机看构建后的效果（含 Service Worker）：

```bash
npm run preview
```

## 二、Cloudflare Pages 设置（Git 集成，推荐）

1. Cloudflare 控制台 → Workers & Pages → 创建 → Pages → 连接到 Git，选这个仓库、`main` 分支
2. 构建设置：

| 项 | 值 |
|---|---|
| 框架预设 | 无（None） |
| 构建命令 | `npm run build` |
| 构建输出目录 | `dist` |
| 根目录 | `/`（仓库根） |
| 环境变量 | `NODE_VERSION` = `22`（Vite 8 / Vitest 5 要求 Node ≥ 22.12） |

3. 不需要任何密钥类环境变量：前端代码和产物里不允许出现 Key。
4. 保存并部署。之后每次 push 到 `main` 自动重新部署；其它分支会生成预览地址。

## 三、或者手动上传（不连 Git）

```bash
npm run build
```

```bash
npx wrangler pages deploy dist --project-name host-system
```

第一次会让你登录 Cloudflare 并创建项目。

## 四、部署后注意

- **必须走 HTTPS**：Service Worker、相机、持久化存储都只在安全上下文里可用。Pages 默认就是 HTTPS。
- **缓存头**：`public/_headers` 会被拷进 `dist/`。带哈希的 `assets/*` 长缓存；`sw.js`、`manifest.webmanifest`、`index.html` 每次回源校验，所以发新版后用户下次打开就能拿到。
- **新版本切换**：新的 Service Worker 就绪后，App 会提示「有新版本了」，等用户回到大厅、手上没有执行中的单时才切过去，不会在计时中途刷新。
- **自定义域名**：在 Pages 项目 → 自定义域里加。换域名等于换一个「浏览器里的存储空间」：旧域名下的数据不会自动带过去，换之前让用户先在设置里「导出存档」，到新域名「导入存档」。
- **不备案**：国内访问 `*.pages.dev` 可能慢或不稳；字体自托管、音效预缓存，装到主屏幕后断网也能打开。

## 五、给朋友用时要交代的

1. 用 iOS Safari / Android Chrome 打开，按引导「添加到主屏幕」，以后从图标打开（不添加的话浏览器可能清掉数据）。
2. 第一次进去要点「同意并继续」，然后去 设置 → 模型设置 填自己的：
   - 端点（OpenAI 兼容，一般以 `/v1` 结尾）、API Key、文本模型、视觉模型
   - 点【测试连接】。报「跨域被拦（CORS）」说明这家服务商不允许网页直连，得换一家或自己加代理
3. 数据只在自己手机的浏览器里。换手机 / 清浏览器前，设置 → 导出存档。
