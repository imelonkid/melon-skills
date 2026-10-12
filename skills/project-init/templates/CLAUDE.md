# __NAME__

__一句话说明这个项目是什么、给谁用__

## 运行

```bash
__本地启动命令__
```

## 运维约定（melonkid 多云运维规范，原文在 `$OPS_REPO/docs/01-standard.md`）

- 定级：数据 __TIER__ · 灾备 __DR__ · 主站点 __SITE__（备 __FAILOVER__，裁判 __WITNESS__）
- 注册表：`$OPS_REPO/registry/services/__NAME__.yaml` —— 改部署方式、数据位置、端口、域名时同步改它
- 发布与回滚一律走 tag：`scripts/deploy.sh patch|minor|major` 发新版，`rollback` 或 `vX.Y.Z` 回滚；不要手动在服务器上改镜像或 compose
- 新版只在 08–23 点发，窗口外 `EMERGENCY=1` 并补复盘；健康检查不过自动切回上一版
- 配置：`.env.example` 列全部变量；真实值在 1Password `ops/__NAME__/prod`；服务器 `.env` 只是副本
- 服务器操作用 server-ops skill；本项目代码里不写任何主机地址

## 编码约定

- 持久化数据只在 `data/`；SQLite 开 WAL，备份用 `sqlite3 .backup`，不要 `cp`
- 对象存储用 S3 兼容接口，不用厂商专有 SDK
- 日志 JSON 到 stdout，带 trace_id；密码 / token / 手机号脱敏
- 版本号：镜像里的 `APP_VERSION`（= tag），初始化 OTel 时设为 `service.version`，`/health` 返回里也带上
- OTel 埋点；业务指标 `<服务名，连字符换下划线>_<领域>_<事件>_total`，标签不放 user_id、URL 原文
- 数据库迁移必须向后兼容（先扩展、再收缩）
- 新增持久化数据 → 注册表 `assets` 加一条；新增环境变量 → `.env.example` 加一行
