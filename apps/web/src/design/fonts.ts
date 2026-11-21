/**
 * 自托管字体（不走 Google Fonts 外链：国内访问不稳，而且要能离线）。
 *
 * Fontsource 自带按 unicode-range 切好的 woff2 分片和 `font-display: swap`，
 * 浏览器只下载页面上真正用到的字。只引用到的字重：
 *  - Chakra Petch：500 / 700 / 700 斜体（显示字、数字）
 *  - Noto Sans SC（可变，wght 100–900）：中文正文
 *  - JetBrains Mono（可变，wght 100–800）：等宽读数、系统日志
 *
 * 分片不进 Service Worker 预缓存，走运行时 CacheFirst（第 7 步配置）。
 */
import '@fontsource/chakra-petch/500.css';
import '@fontsource/chakra-petch/700.css';
import '@fontsource/chakra-petch/700-italic.css';
import '@fontsource-variable/noto-sans-sc';
import '@fontsource-variable/jetbrains-mono';
