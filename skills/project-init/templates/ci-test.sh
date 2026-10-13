#!/usr/bin/env bash
# CI 的测试入口（melon-ci pr-check 约定：scripts/ci-test.sh 存在就跑；本机也能跑）。
# 要求：不碰外网和真实数据（用桩服务、临时目录）；失败时把有助于排查的日志打出来；退出码非 0 即失败。
# 依赖版本与 deploy/Dockerfile 保持一致（例如 pnpm、Python 版本），否则 CI 和镜像行为不一样。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ 安装依赖"
__安装依赖的命令__

echo "▸ 测试"
__测试命令（单元测试 / 服务端冒烟）__
