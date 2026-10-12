# __NAME__

__一句话说明：是什么、给谁用__

## 本地运行

```bash
__本地启动命令__
```

## 部署

发布和回滚都以 git tag 为单位，没有 tag 的代码不上线。

```bash
scripts/deploy.sh patch      # 发新版：打下一个 vX.Y.Z（minor / major 同理），推到 GitHub 后构建上线
scripts/deploy.sh rollback   # 回滚到上一个成功上线的版本（服务器保留最近 5 版，秒级）
scripts/deploy.sh v1.2.0     # 上线 / 回滚到指定 tag
scripts/deploy.sh status     # 线上版本与最近的部署事件
```

发新版只在 08–23 点，窗口外用 `EMERGENCY=1` 并在 24 小时内补复盘；回滚不受限。健康检查 60 秒不过自动切回上一版。

## 上线准入（运维规范 §9.2）

- [ ] 代码在 GitHub，线上版本是一个 tag（`scripts/deploy.sh status`）
- [ ] `.env.example` 齐全；1Password 有 `ops/__NAME__/prod`
- [ ] 注册表 `registry/services/__NAME__.yaml` 通过字段检查
- [ ] T0/T1 资产首次备份成功，**做过一次恢复验证**；备份心跳接入 Gatus
- [ ] Gatus 有探活，告警实测触发过
- [ ] 容器有 `mem_limit` / `healthcheck` / `restart`
- [ ] 主、备站点已完成 ICP 接入；DNS TTL ≤ 300
- [ ] `panel` 索引、主机档案已更新，注册表 `status: active`

## 已知缺口

见注册表 `known_gaps`。
