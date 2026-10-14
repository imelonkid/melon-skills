# __NAME__

__一句话说明：是什么、给谁用__

## 本地运行

```bash
__本地启动命令__
```

## 发布与回滚

发布和回滚都以 git tag 为单位，没有 tag 的代码不上线。**发布只在线上**：GitHub Actions 点「发布」（patch / minor / major），或在内网门户的流水线页发起；回滚同样点「回滚」。

发新版只在 08–23 点，窗口外勾「紧急变更」并在 24 小时内补复盘；回滚不受限。健康检查 60 秒不过自动切回上一版。

GitHub 或门户不可用时，在运维终端用应急指令（不构建、不产生新版本）：

```bash
melon status __NAME__          # 线上版本与最近的部署事件
melon rollback __NAME__        # 切回上一次上线前的版本（服务器保留最近 5 版，秒级）
pbpaste | melon config __NAME__  # 下发 .env（来自 1Password）
```

## 上线准入（运维规范 §9.2）

- [ ] 代码在 GitHub，线上版本是一个 tag（`melon status __NAME__`）
- [ ] `.env.example` 齐全；1Password 有 `ops/__NAME__/prod`
- [ ] 注册表 `registry/services/__NAME__.yaml` 通过字段检查
- [ ] T0/T1 资产首次备份成功，**做过一次恢复验证**；备份心跳接入 Gatus
- [ ] Gatus 有探活，告警实测触发过
- [ ] 容器有 `mem_limit` / `healthcheck` / `restart`
- [ ] 主、备站点已完成 ICP 接入；DNS TTL ≤ 300
- [ ] `panel` 索引、主机档案已更新，注册表 `status: active`

## 已知缺口

见注册表 `known_gaps`。
