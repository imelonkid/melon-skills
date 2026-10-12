# __NAME__

__一句话说明这个项目是什么、给谁用__

## 运行

```bash
__本地启动命令__
```

## 部署

- 主站点：__SITE__ · 目录 `/opt/__NAME__/` · 数据等级 __TIER__
- 发布：`scripts/deploy.sh`（本机构建 linux/amd64 → 传镜像 → 重建 → 健康检查，不过自动回滚）
- 配置：`.env.example` 列出全部变量；真实值在 1Password `ops/__NAME__/prod`，服务器上的 `.env` 只是副本
- 服务注册：`$OPS_REPO/registry/services/__NAME__.yaml`；服务器操作用 server-ops skill

## 约定

- 持久化数据只在 `data/`；SQLite 备份用 `sqlite3 .backup`，不要 `cp`
- 对象存储用 S3 兼容接口，不用厂商专有 SDK
- 日志 JSON 输出到 stdout，密码 / token / 手机号脱敏
- 数据库迁移必须向后兼容（先扩展、再收缩）
- 服务器上不手改 compose：改仓库里的 `deploy/docker-compose.prod.yml`，由部署脚本同步
