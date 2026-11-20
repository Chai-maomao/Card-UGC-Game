CARDEX 隐私说明 / Privacy notice
更新：2026-11-14，适用于当前桌面预发行版本

本地模式：卡库、卡图、牌组、设置、教学进度、战绩、回放与恢复快照保存在本机 user://。单机模式无需账号。没有广告、遥测或自动诊断上传。设置 → 支持与说明可打开存档、日志目录。便携包删除不会自动删除这些数据；备份后可手动删除该目录。

联机为主动选择。LAN、直连和自有服务器会向对端或所选服务器传递连接信息、房间标识、指令、对局状态；对端及运营商能够看到连接 IP。双端预测会交换完整手牌与牌堆等隐藏信息，因此目前只适合可信对手，不具备反作弊保密保证。启用卡图传输时，图像也会发给对端/中继；请勿使用含私人信息的图像。

Cloudflare / Sites 中继会处理房间凭据、请求与对局包；第三方基础设施可能处理网络与安全日志。仓库内 CF 实现的房间有效期为创建后一小时，过期数据在后续请求时清理；这不代表运营商日志或备份也在一小时内清除。自建或第三方服务器可采用不同保留策略，请咨询其运营者。Cloudflare 隐私说明：https://www.cloudflare.com/privacypolicy/

诊断摘要仅在你点击“复制设备信息”时复制版本、引擎、系统类别、渲染器、显卡、窗口与画质信息。不会复制 IP、房间 token、卡库或原始日志。原始日志可能包含路径、房间或连接信息；提交反馈前请自行检查与删去私密内容。反馈入口为公开 GitHub Issues，不适合提交密码、私钥、个人信息。

当前仓库的公开联系渠道：https://github.com/Chai-maomao/Card-UGC-Game/issues
若将本版本用作公共服务，运营者须补充其真实身份、联系渠道和实际数据处理政策后再上线。本文件不会替第三方服务器作数据保留承诺。

创意工坊：浏览无需登录，上传和举报需要账号。工坊服务器保存用户名、加盐密码哈希、登录会话、卡包和举报；不保存明文密码。登录会话最长有效30天。选择“记住登录”后，本机会保存当前工坊的登录凭据，退出登录时删除；不会保存密码。上传内容审核通过后公开，下载者可以保留副本。作者下架后服务器清除卡包内容并保留元数据与举报，用于处理投诉；备份中的副本按运营者的备份周期清理。不会自动上传本地卡库。需要删除账号或处理投诉时，请通过上述联系渠道提出，勿公开密码。正式服务开放时须补充实际运营者、域名及保留期限。

English
Local libraries, art, decks, settings, tutorial progress, history, replays and recovery snapshots stay in the local user data folder. Offline play needs no account. No advertising, analytics or automatic diagnostic uploads are implemented. Deleting the portable application does not erase this folder.
Online play is optional. Peers/servers receive connection data, room identifiers, commands and match state. Prediction exchanges full hands/decks: play with trusted opponents; hidden information is not protected against modified clients. Enabled card-art transfer also sends your images. Infrastructure operators can observe IP addresses and network/security logs.
The bundled Cloudflare relay expires rooms after one hour from creation and purges expired rows on later requests. This is not a promise about provider logs/backups. Other operators may use different policies. Review your server operator and Cloudflare privacy policy above.
Copy diagnostics is explicit and copies only technical summary fields, excluding room credentials, IPs, cards and raw logs. Review raw logs yourself before sharing. The linked public issue tracker is the project contact; never post secrets or personal information. A public service operator must supply its actual identity, contacts and processing policy before launch.

Workshop browsing is public; uploading and reporting require an account. The service stores usernames, salted password hashes, sessions, packages and reports. Sessions expire after 30 days. Remember login saves an address-bound session credential locally, never your password; signing out removes it. Approved uploads are public and recipients may retain copies. Withdrawing a package clears its server payload while metadata and reports remain for complaints; backup retention depends on the operator. Your local library is never uploaded automatically. Contact the project for account deletion without posting credentials. Before public launch, the operator must publish its identity, domain and retention periods.
