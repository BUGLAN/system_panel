/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      // 新版本就绪时不强刷：回到大厅、手上没有执行中的单时再切（见 src/pwa.ts）
      registerType: 'prompt',
      injectRegister: false,
      manifest: {
        name: '宿主养成系统',
        short_name: '宿主养成',
        description: '毒舌但靠谱的系统娘，帮你把目标拆成一单一单的委托。',
        lang: 'zh-CN',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#06050c',
        theme_color: '#06050c',
        icons: [
          { src: 'pwa-64x64.png', sizes: '64x64', type: 'image/png' },
          { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png' },
          { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png' },
          {
            src: 'maskable-icon-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // 预缓存应用壳和音效；字体分片不预缓存（太多），走运行时 CacheFirst
        globPatterns: ['**/*.{js,css,html,ico,png,svg,mp3,wav,webmanifest}'],
        navigateFallback: '/index.html',
        // 接口一律走网络：不缓存、不拿 index.html 顶替（断网时由前端提示「需要联网」）
        navigateFallbackDenylist: [/^\/api\//],
        cleanupOutdatedCaches: true,
        // /api/* 不注册任何路由：Service Worker 不接管（SSE 长连接、图片鉴权都由浏览器直连）
        runtimeCaching: [
          {
            urlPattern: ({ request, url }) =>
              request.destination === 'font' || url.pathname.endsWith('.woff2'),
            handler: 'CacheFirst',
            options: {
              cacheName: 'fonts',
              expiration: { maxEntries: 400, maxAgeSeconds: 60 * 60 * 24 * 365 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
        ],
      },
      devOptions: { enabled: false },
    }),
  ],
  server: {
    // 开发时 API 走本机的服务端（npm run dev:server）
    proxy: {
      '/api': { target: process.env['API_TARGET'] ?? 'http://localhost:8787', changeOrigin: false },
    },
  },
  build: {
    target: 'es2022',
    // 中文字体分片本来就多，别为它们报体积警告
    chunkSizeWarningLimit: 800,
  },
  test: {
    name: 'web',
    include: ['tests/**/*.test.ts', 'tests/**/*.test.tsx'],
    environment: 'node',
    setupFiles: ['tests/setup.ts'],
  },
});
