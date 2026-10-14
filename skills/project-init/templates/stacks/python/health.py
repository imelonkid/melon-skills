"""项目基线 v1 · 健康检查示例（Python 标准库 http.server）。

GET /health → 200 {"ok": true, "version": APP_VERSION}；数据库等依赖不可用时返回 503 {"ok": false, "error": …}。
- version 取环境变量 APP_VERSION（镜像构建时由 tag 注入）；本地开发时为 "dev"
- 只检查「能不能正常服务」：数据库能读、必要的目录可写。不检查外部服务（外部挂了不该让本服务被判不健康而反复切回）
- 不需要登录；不返回任何配置或密钥
"""
import json
import os
import sqlite3

VERSION = os.environ.get("APP_VERSION", "dev")


def health(db_path):
    try:
        with sqlite3.connect(db_path, timeout=2) as db:
            db.execute("SELECT 1")
        return 200, {"ok": True, "version": VERSION}
    except Exception as e:  # noqa: BLE001
        return 503, {"ok": False, "version": VERSION, "error": str(e)[:200]}


# 在 BaseHTTPRequestHandler.do_GET 里：
#   if self.path == "/health":
#       code, body = health(DB_PATH)
#       raw = json.dumps(body).encode()
#       self.send_response(code); self.send_header("Content-Type", "application/json")
#       self.send_header("Content-Length", str(len(raw))); self.end_headers(); self.wfile.write(raw)
