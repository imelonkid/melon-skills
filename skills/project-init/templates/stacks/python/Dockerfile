# 项目基线 v1 · Python 服务。复制到 deploy/Dockerfile，按需改依赖与启动命令。
# 规则：基础镜像钉版本；版本号构建时注入并烘进镜像（APP_VERSION = tag，/health 返回它）；最终镜像要有 wget（compose 健康检查用）
FROM python:3.13-alpine

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
WORKDIR /srv/__NAME__

# 有第三方依赖才需要 requirements.txt（钉版本）；只用标准库可以删掉这两行
COPY requirements.txt* ./
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

COPY app/ ./app/
# 持久化数据只在 /data（compose 挂 ./data）
VOLUME ["/data"]
EXPOSE 8080
CMD ["python", "-u", "app/main.py", "--data", "/data", "--port", "8080"]
