# Cardex Cloudflare 联机服务

默认“服务器联机 · Cloudflare”的独立后端。使用用户自己的 Cloudflare Workers 与 D1，复用经过验证的 HTTPS 房间协议；无需阿里云服务器、公网 IP 或 UDP 端口映射。Sites Beta 使用另一个服务，房间不互通。P1 客户端保持战斗权威。

## 当前部署状态

已部署到用户通过 Google 注册并重新授权的 Cloudflare 账号 `b595dbcbe2f6cdaca7a7b3b95770d317`：

- 正式地址：https://cardex-online-relay.cardex-online.workers.dev
- Worker：`cardex-online-relay`，版本 `4fde82a3-dff2-4e5a-aa6c-e896ee8e4484`。
- D1：`cardex-online`，`bfa5593e-5ba6-4457-8b3a-ef1cbe936ec3`，APAC；0001迁移已应用。
- 客户端 `res/network/cloudflare.json` 已填写该正式地址，Windows导出也包含该配置。

匿名health200、无玩家令牌exchange401、版本不匹配426、房满409均通过。两个真实Godot客户端直接连接正式服务，完成48317字节PNG完整性、规则/牌组双确认、双方回合、重连后继续操作，双方revision3；见根目录artifacts/cloudflare-migration-20261021/integration-85347b63。测试房间已按精确房间码清理。

之前QQ账号的邮箱验证阻塞已通过改用用户指定Google账号解决；旧QQ账号的D1保留，不作为生产数据库。新账号首次开通workers.dev后，HTTPS短暂握手失败，等待首次开通生效后正常，无需关闭证书校验。

## 开发、验证与发布

在此目录执行（Node.js 24+，测试使用内置 node:sqlite）：

```powershell
npm ci
npm test
npm run check
npm run build
npm run migrate:local
npm run dev
```

本地预览为 `http://127.0.0.1:8791`。从游戏根目录运行 `pwsh -File scripts/run_cloud_integration.ps1 -WithArt`，使用隔离存档启动两客户端，测试实际默认大厅、卡图、规则/牌组确认、回合操作及重连后继续行动。

发布使用 Wrangler 本机 OAuth 登录；凭证保存在 Wrangler 用户配置，不进入源码或客户端。所需权限为 `account:read user:read workers_scripts:write d1:write`。`wrangler.jsonc` 固定已有账号与数据库身份，不应重新创建数据库。邮箱验证入口在账号首页顶部的提示条。

```powershell
node node_modules/wrangler/bin/wrangler.js login --scopes account:read user:read workers_scripts:write d1:write
npm run migrate:remote
npm run deploy
```

首次迁移已经完成；后续仅在添加新迁移时再次执行 migrate:remote。禁止修改已应用的 `0001_initialize.sql`。发布后从 Wrangler 输出取得实际 HTTPS origin，验证 `/api/health` 返回200，再写入游戏根目录的 `res/network/cloudflare.json`（schema=1）。发布客户端导出明确包含此 JSON；禁止填平台令牌或房间令牌。使用真实地址运行 `scripts/run_cloud_integration.ps1 -RelayUrl https://实际地址 -WithArt`，HTTPS测试使用已保存的客户端配置。

## 运行边界与回退

不启用付费方案；使用平台Free计划默认CPU限制，不配置`limits.cpu_ms`（Free计划拒绝自定义此项，100328）。平台免费配额耗尽仍可能导致服务不可用，实际校园网及异地网络需要玩家试玩确认。HTTPS轮询适合此回合制实验，延迟和请求量受轮询频率影响，不保证低延迟或无限免费。

每房间2人、1小时绝对过期、全局最多32房间、每来源IP最多4房间（校园网共享出口可能共用上限）。每发送者最多512条/8MiB待收消息，每HTTP请求512KiB。房间码为8位十六进制；每位玩家单独持有随机32字节令牌，数据库仅存哈希。公开后端不要求 Cloudflare 登录，但 attach/exchange/leave 需要正确房间身份。

紧急停用：将 `wrangler.jsonc` 中 `BETA_DISABLED` 改为 `"1"` 并重新部署，所有接口返回503。恢复改为 `"0"`。发布代码回退可用 Wrangler 官方 rollback；保持数据库身份与追加迁移历史。客户端若暂时清空配置URL则显示未配置，不回连已释放的阿里云IP；独立 Sites Beta 与 LAN 入口可继续使用。

旧阿里云房间无法迁入新房间；本地会话与快照保留，但阻止向已释放IP发起恢复。Cloudflare 和 Sites 会话使用不同模式与标识，不能互相恢复。
