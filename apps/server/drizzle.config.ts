import { defineConfig } from 'drizzle-kit';

// 只用来生成迁移 SQL（npm run db:generate）；运行时迁移由 src/db/client.ts 执行
export default defineConfig({
  dialect: 'sqlite',
  schema: './src/db/schema.ts',
  out: './drizzle',
});
