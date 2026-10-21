# syntax=docker/dockerfile:1
# 项目基线 v3 · NestJS 服务（stacks/nestjs）。复制到 deploy/Dockerfile（多端项目：构建上下文是仓库根，路径加 apps/server/）。
# 规则：基础镜像与 pnpm 钉版本；版本号构建时注入并烘进镜像（APP_VERSION = tag，/health 返回它，门户 server-release 据此验收）
# 私有公共包 @imelonkid/common：读包令牌由 melon-ci 以 BuildKit secret npm_token 传入，只在安装依赖这一步可见、不进镜像层
FROM node:22-alpine AS build
WORKDIR /src
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate
COPY package.json pnpm-lock.yaml .npmrc ./
RUN --mount=type=secret,id=npm_token NODE_AUTH_TOKEN="$(cat /run/secrets/npm_token 2>/dev/null)" pnpm install --frozen-lockfile
COPY . .
RUN pnpm build && CI=true pnpm prune --prod --ignore-scripts && rm -f .npmrc

FROM node:22-alpine
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} NODE_ENV=production PORT=8080
WORKDIR /srv/app
COPY --from=build /src/package.json /src/prisma.config.ts ./
COPY --from=build /src/node_modules ./node_modules
COPY --from=build /src/prisma ./prisma
COPY --from=build /src/dist ./dist
USER node
EXPOSE 8080
# 启动先执行数据库迁移（向后兼容的迁移，回滚到上一个 tag 也能跑），再起服务；健康检查用镜像自带的 wget
HEALTHCHECK --interval=15s --timeout=3s --start-period=30s CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1
CMD ["sh", "-c", "node_modules/.bin/prisma migrate deploy && exec node dist/main.js"]
