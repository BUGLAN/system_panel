import { defineProject } from 'vitest/config';

export default defineProject({
  test: {
    name: 'server',
    include: ['tests/**/*.test.ts'],
    environment: 'node',
  },
});
