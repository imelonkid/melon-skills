import { defineConfig } from 'vitest/config';

// 单元测试：src/**/*.spec.ts（不连数据库）
export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: { globals: true, root: './', include: ['src/**/*.spec.ts'] },
});
