import { defineConfig } from 'prisma/config';

// Prisma CLI 的配置（Prisma 7）：迁移、生成用 DATABASE_URL。本机开发从 .env 读（Node 22 自带，不引 dotenv）
try {
  process.loadEnvFile('.env');
} catch {
  /* 没有 .env：用已有的环境变量（CI、容器） */
}

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: { path: 'prisma/migrations' },
  datasource: { url: process.env.DATABASE_URL }, // 生成客户端不需要；迁移时必须有
});
