/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// PWA 插件在第 7 步接入（manifest / Service Worker / 图标）
export default defineConfig({
  plugins: [react()],
  build: {
    target: 'es2022',
    // 中文字体分片本来就多，别为它们报体积警告
    chunkSizeWarningLimit: 800,
  },
  test: {
    include: ['tests/**/*.test.ts', 'tests/**/*.test.tsx'],
    environment: 'node',
    setupFiles: ['tests/setup.ts'],
  },
});
