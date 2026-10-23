# __NAME__

__一句话说明这个项目是什么、给谁用__

## 边界（强制）

Claude 在本项目里只做下面「负责」的事；越界的需求先停下来和用户确认，不要顺手改到别的项目里。

- **本项目负责**：__这个项目做什么（模块、目录）__
- **本项目不负责**：__容易被误放进来的东西，以及它们归哪个项目__
- **与其他项目的关系**：__依赖谁（按什么固定版本）、谁依赖它、接口 / 契约在哪；没有就写「无」__

## 运行

```bash
__本地启动命令__
```

## 运维约定（melonkid 多云运维规范，原文在 `$OPS_REPO/docs/01-standard.md`）

- 定级：数据 __TIER__ · 灾备 __DR__ · 主站点 __SITE__（备 __FAILOVER__，裁判 __WITNESS__）
- 注册表：`$OPS_REPO/registry/services/__NAME__.yaml` —— 改部署方式、数据位置、端口、域名时同步改它
- 发布与回滚一律走 tag，**只在内网门户上点**（GitHub「发布 / 回滚」表单兜底）；本仓库不放部署脚本。版本号：修 bug → patch，新功能 → minor，不兼容 → major应急只用运维终端的 `melon status / rollback / config`；不要手动在服务器上改镜像或 compose
- 新版只在 08–23 点发，窗口外 `EMERGENCY=1` 并补复盘；健康检查不过自动切回上一版
- 配置：`.env.example` 列全部变量；真实值在 1Password `ops/__NAME__/prod`；服务器 `.env` 只是副本
- 服务器操作用 server-ops skill；本项目代码里不写任何主机地址
- PR 一律以 `main` 为目标，不开叠加 PR

## 编码约定

- 持久化数据只在 `data/`；SQLite 开 WAL，备份用 `sqlite3 .backup`，不要 `cp`
- 对象存储用 S3 兼容接口，不用厂商专有 SDK；**用户上传的文件（头像、图片）一律放对象存储**，不存 `data/`
- 日志与客户端错误上报用公共包 `@imelonkid/common`（钉确切版本；规范在 `$OPS_REPO/docs/11-logging.md`）：stdout 一行一条 JSON，带 trace_id；追踪号 `X-Request-Id`，错误响应体带 `traceId`；密码 / token / 手机号脱敏
- 运营后台只在内网 `__NAME__.in.melonkid.cn`，不做自己的账号密码：凭网关转来的门户身份头 `X-Melon-*` 登录
- 版本号：镜像里的 `APP_VERSION`（= tag），初始化 OTel 时设为 `service.version`；`/health` 返回 `{"ok", "version"}`，`version` = tag 原样（发布流水线据此验收）
- OTel 埋点；业务指标 `<服务名，连字符换下划线>_<领域>_<事件>_total`，标签不放 user_id、URL 原文
- 数据库迁移必须向后兼容（先扩展、再收缩）
- 新增持久化数据 → 注册表 `assets` 加一条；新增环境变量 → `.env.example` 加一行
