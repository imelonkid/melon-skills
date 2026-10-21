# stacks/nestjs · NestJS 服务骨架（项目基线 v3）

按基线「技术架构与选型」：TypeScript（ESM）+ Node 22 + NestJS 12 + Prisma 7（MySQL 8，驱动适配器 `@prisma/adapter-mariadb`）+ Vitest + oxlint + Prettier，
结构与配置以 NestJS 官方脚手架（`nest new`）为底，加上基线要求的：日志与错误上报（`@imelonkid/common`）、统一响应体与错误码、`/health`、数据库、镜像与 CI 测试。

已验证（2026-10-21，node:22-alpine）：安装 → 生成数据库客户端 → oxlint / 类型检查 / 单测 → 编译 → 临时 MySQL 8.4 迁移 → 端到端 → 冒烟；
镜像启动先 `prisma migrate deploy`，`/health` 返回注入的版本号、库停掉回 503、容器以 node 用户运行、日志一行一条 JSON。

## 用法

| 模板文件 | 放到项目里 | 说明 |
|---|---|---|
| 整个目录（除本 README） | 单服务：仓库根；多端：`apps/server/` | `package.json` 的 `__NAME__` 换成服务名（`env.example`、`src/main.ts` 同） |
| `npmrc` | `.npmrc` | 私有公共包 `@imelonkid/*`，令牌走 `NODE_AUTH_TOKEN` |
| `dockerignore` | `.dockerignore` | |
| `gitignore.append` | 追加到 `.gitignore` | `src/generated/`（Prisma 生成的客户端）不进 git |
| `env.example` | 追加到 `.env.example` | 真实值在 1Password `ops/<名>/prod` |
| `Dockerfile` | `deploy/Dockerfile` | 多端项目构建上下文是仓库根：`COPY` 路径加 `apps/server/` |
| `scripts/ci-test.sh` | `scripts/ci-test.sh` | 多端项目：仓库根的 `scripts/ci-test.sh` 调 `apps/server/scripts/ci-test.sh`；需要 Docker（起临时 MySQL） |

然后：`pnpm install`（锁文件 `pnpm-lock.yaml` 随模板带来，钉住全部间接依赖）→ 删掉 `prisma/schema.prisma` 里的示例模型、写自己的 →
`pnpm prisma:migrate --name init`（本机 `.env` 的 `DATABASE_URL` 指向开发库）→ `bash scripts/ci-test.sh` 全绿再提交。
`ci.yml` 调 melon-ci pr-check 时传 `node-version: "22"`（模板已带）。

## 约定

- **ESM**：`"type": "module"`，相对导入写 `.js` 后缀（官方脚手架同款）
- **模块化单体**：按业务域加模块 `src/<域>/`，模块之间走服务接口、不跨模块直接查表
- **接口**：前缀 `/api/v1`（`/health` 除外）；成功 `{code:0, message, data, traceId}`；业务错误抛 `BizException(ErrorCodes.X, '…')`（HTTP 200 + 业务码，错误码在 `src/common/biz.exception.ts` 按域分段登记）
- **数据库**：`DATABASE_URL` 指向节点共享 MySQL 实例上本项目自己的库与账号；迁移向后兼容（先扩展、再收缩）；镜像启动时自动 `migrate deploy`
- **镜像大小**：约 770MB（未压缩），其中 Prisma 命令行约 200MB——留在镜像里是为了启动时执行迁移
- 升级依赖：在本目录改版本 → `pnpm install` 更新锁文件 → 跑 `scripts/ci-test.sh` 与镜像冒烟 → 基线「变更」记一笔
