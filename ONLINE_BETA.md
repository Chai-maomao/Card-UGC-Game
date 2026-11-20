# 联机 Beta

游戏入口：对战 → 联机对战 → 联机 Beta → 选择牌组。创建房间后复制八位房间码，朋友在同一入口输入房间码。双方准备并确认规则和牌组后进入战斗。

此版本使用 Sites 托管的 HTTPS 后端与 D1 数据库中转 Godot 消息，P1 客户端负责现有权威计算。玩家无需公网 IP、路由端口映射或额外安装组网工具。独立“服务器联机 · Cloudflare”和局域网入口继续保留；Cloudflare 默认入口的迁移与部署状态见 cloudflare/online-relay/README.md，两种服务房间不互通。

当前已按用户授权公开：[Beta 后端](https://cardex-online-beta.ycn3258823137.chatgpt.site)。游戏客户端和朋友可以直接连接，无需 ChatGPT 登录。游戏不会携带任何 Sites 平台访问密钥；玩家操作仍由各自的房间令牌验证。

实验限制：每房间最多两人、一小时过期；HTTP轮询会有延迟。服务最多32个活跃房间，每来源IP最多创建4个，校园网共享出口也可能计为同一来源。房间令牌仅用于自己的玩家身份。房间码不要发给不希望加入的人。Sites 免费额度、长期免费和大陆网络连通性未获保证。

已验证：62项逻辑、16项实际GL视觉；本地Worker+D1及SQLite夹具通过后，两个真实游戏进程直接连接线上HTTPS服务，完成创建/加入、牌组与规则确认、双方回合操作、断线恢复后继续操作；48317字节卡图分两片传输后双方哈希一致。匿名健康接口返回200，无玩家令牌的操作被应用层401拒绝。中英文1280×720/960×540布局通过。真正异地/校园网、移动设备和导出包尚未验证。

主要文件：BetaLobby.gd/.tscn、BetaRelayPeer.gd、BetaRelayConfig.gd、NetworkManager.gd、MultiplayerMenu.gd/.tscn、sites/cardex-online-beta。服务协议、部署和停用方法见后端README；固定Sites身份保存在该子项目.openai/hosting.json。

回归：scripts/run_tests.ps1；两个进程集成：scripts/run_beta_integration.ps1（可加-WithArt）。本地HTTP只允许调试构建以CARDEX_BETA_TEST_URL覆盖至127.0.0.1/localhost；发布客户端使用固定HTTPS服务。测试使用隔离存档，原游戏存档和ENet协议保持兼容。
