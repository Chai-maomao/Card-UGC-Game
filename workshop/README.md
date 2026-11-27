# 创意工坊

游戏主菜单进入。无需登录浏览卡包；熟人测试期间，注册时需要邀请码；登录后可以上传、举报、下架自己的卡包。下载后先预览，确认后导入为新卡组，不覆盖已有卡组。

工坊目前临时部署在联机大厅所在服务器。客户端默认连接 `https://103.236.54.24`，由 Nginx 转发到监听本机的独立工坊服务。部署沿用原有数据库和邀请码。

## 本机运行

需要 Python 3.11 或更新版本，无第三方 Python 依赖。

```powershell
python workshop/server.py --allow-http --db artifacts/workshop-dev.sqlite3
```

启动游戏时附加 `-- --workshop-url=http://127.0.0.1:8765`。仅本机测试允许 HTTP；正式地址必须使用 HTTPS。

## 公网配置

- 使用独立系统用户 `cardex-workshop`，将 `server.py` 放入 `/opt/cardex-workshop`。
- 在 `/etc/cardex-workshop.env` 设置随机的 `CARDEX_WORKSHOP_ADMIN_TOKEN`，文件权限 600。用 `python3 -c 'import secrets; print(secrets.token_urlsafe(48))'` 生成，勿提交到仓库或放进客户端。
- 如仅向熟人开放上传，另设 `CARDEX_WORKSHOP_INVITE`。不设置则允许公开注册。
- 使用附带的 systemd 配置运行，仅监听 127.0.0.1:8765。管理接口只允许服务器本机访问。
- 当前使用 Let's Encrypt 短期 IP 证书。Certbot 通过现有 HTTP 站点的 webroot 完成验证，续签定时器会重新加载 Nginx。
- `nginx-ip.conf` 作为独立站点配置接入现有 Nginx，公网只转发工坊 API，并拦截管理接口。其他主机有域名时也可使用附带的 Caddy 配置。
- 将正式 HTTPS 地址写入项目根目录 `workshop_config.json` 的 `url`。
- `backup.py` 使用 SQLite backup API，校验备份并保留 14 天。服务器每天备份到 `/var/backups/cardex-workshop`。手动备份时也应使用该脚本，以纳入 WAL 中的写入。

## 审核

新上传默认待审核，只有作者和管理员能查看。管理员在服务器环境使用：

```sh
python3 admin.py review
python3 admin.py download PACKAGE_ID --output review-package.json
python3 admin.py publish PACKAGE_ID
python3 admin.py hide PACKAGE_ID
```

审核下载的卡包可导入测试游戏查看。举报出现在 `review` 结果中。隐藏后不再允许下载；已被玩家保存的副本无法远程收回。作者下架会清除服务器保存的卡包内容，保留元数据用于处理举报。

## 数据与限制

保存用户名、加盐密码哈希、登录会话、上传卡包及举报。服务器不接收游戏存档、房间密码或联机私钥。会话30天过期；选择“记住登录”后，客户端保存绑定服务地址的会话凭据，不保存明文密码。退出登录会撤销会话并删除本机凭据。应用仅用原始 IP 做内存限流；代理的安全错误日志另按部署配置保留。

每包最多200张卡牌、16 MB，每张图片最多2 MB、4096边长和4194304像素。服务端检查图片头的尺寸；上传前和服务端均清除本地图片路径与技能工作区数据，保留原作者来源。内容只作为 JSON 保存，不执行卡包代码；下载仍须通过游戏现有格式与复杂度检查。

工坊和联机大厅共用主机，各自由独立的服务进程和端口提供。当前没有邮件验证或自助找回密码。

## 检查

```powershell
python -m unittest workshop.test_server -v
python scripts/run_workshop_integration.py
```

集成检查使用临时账号、数据库和隔离存档，覆盖游戏注册、上传、待审核可见性、预览、导入、记住登录、退出登录及服务地址间凭据隔离。原生界面另以实际渲染检查，不能由无头检查替代。

## Steam 接口预留

`WorkshopBackend.gd` 定义浏览、上传、下载、账号及下架等接口；`WorkshopProviders.gd` 可注册平台实现，当前默认使用自建 HTTPS 服务。未来 Steam 适配应通过 ISteamUGC 和 Steam 账号完成，客户端不应收集 Steam 密码。目前未集成 Steam SDK、App ID 或真实 Steam 工坊。
