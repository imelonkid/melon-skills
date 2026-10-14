# 项目基线 v1 · Node 服务（pnpm）。复制到 deploy/Dockerfile，按需改构建与启动命令。
# 规则：基础镜像与 pnpm 钉版本；版本号构建时注入并烘进镜像（APP_VERSION = tag，/health 返回它）；最终镜像要有 wget
FROM node:22-alpine AS build
WORKDIR /src
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build --if-present && pnpm prune --prod

FROM node:22-alpine
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} NODE_ENV=production
WORKDIR /srv/__NAME__
COPY --from=build /src ./
VOLUME ["/data"]
EXPOSE 8080
CMD ["node", "src/server.js"]
