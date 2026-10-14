# 项目基线 v1 · 静态站：构建 → Caddy 提供。复制到 deploy/Dockerfile。
# 静态站也按镜像发布：和服务走同一条 tag 发布 / 回滚路径（部署入口、健康检查、自动切回）
FROM node:22-alpine AS build
WORKDIR /src
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build                      # 产物在 dist/（按框架改）

FROM caddy:2.10-alpine
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/dist /srv
EXPOSE 8080
