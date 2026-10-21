import { defineConfig } from 'vitest/config';

// 端到端：test/**/*.e2e-spec.ts（需要 DATABASE_URL 指向测试库，scripts/ci-test.sh 起临时 MySQL）
export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: { globals: true, root: './', include: ['test/**/*.e2e-spec.ts'] },
});
