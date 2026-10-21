# syntax=docker/dockerfile:1
# 项目基线 v2 · Node 服务（pnpm）。复制到 deploy/Dockerfile，按需改构建与启动命令。
# 规则：基础镜像与 pnpm 钉版本；版本号构建时注入并烘进镜像（APP_VERSION = tag，/health 返回它，发布流水线据此验收）；最终镜像要有 wget
# 私有公共包 @imelonkid/common（GitHub Packages）：读包令牌由 melon-ci 以 BuildKit secret npm_token 传入，
#   只在安装依赖这一步可见、不进镜像层；.npmrc 里只有 ${NODE_AUTH_TOKEN} 占位（模板 stacks/node/npmrc）
FROM node:22-alpine AS build
WORKDIR /src
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate
COPY package.json pnpm-lock.yaml .npmrc ./
RUN --mount=type=secret,id=npm_token NODE_AUTH_TOKEN="$(cat /run/secrets/npm_token 2>/dev/null)" pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build --if-present && pnpm prune --prod && rm -f .npmrc

FROM node:22-alpine
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} NODE_ENV=production
WORKDIR /srv/__NAME__
COPY --from=build /src ./
VOLUME ["/data"]
EXPOSE 8080
CMD ["node", "src/server.js"]
