import { defineConfig, minimal2023Preset } from '@vite-pwa/assets-generator/config';

// 图标母版来自 flutter-final:brand/icon/app-icon.svg；生成 64 / 192 / 512 / maskable / apple-touch-icon / favicon
export default defineConfig({
  headLinkOptions: { preset: '2023' },
  preset: {
    ...minimal2023Preset,
    maskable: { ...minimal2023Preset.maskable, resizeOptions: { background: '#06050c' } },
    apple: { ...minimal2023Preset.apple, resizeOptions: { background: '#06050c' } },
  },
  images: ['public/app-icon.svg'],
});
