# 联机稳定性（协议 v5）

## 当前边界

- 局域网模式使用 UDP 4569 广播发现可加入房间，对战使用 UDP 4568；自动发现失败时可手动填写 `IP` 或 `IP:端口`。
- 不内置 UPnP、打洞、主机迁移或公网中继。跨公网由玩家自行配置内网穿透；续局要求房主仍使用原地址和端口。
- 房间号模式用于公网联机。大厅监听 UDP 4567，房间进程使用配置的 UDP 端口范围。
- 客户端、大厅进程和房间进程必须使用同一构建；协议 v5 不与旧协议互通。

## 可靠性机制

- 通道 0：大厅、认证、协议握手和连接状态。
- 通道 1：战斗命令、权威快照和断线恢复；可靠有序。
- 通道 2：目标箭头和演出提示；不可靠有序，允许丢弃旧帧。
- 通道 3：卡图；24 KiB 分片、SHA-256 校验、逐帧限速。
- 通道 4：保留给后续可选的低延迟瞬时消息；不承载决定战局的操作。

从机输入指令与轻量接收回执统一走经过局域网和服务器中继验证的可靠通道 1。战局关键操作不再依赖较高编号的自定义通道，避免不同部署环境对该通道支持不完整时造成从机输入完全丢失。
- 非权威端的每条战斗命令携带唯一 `command_id` 和 `expected_revision`。
- 权威端丢弃重复命令；revision 不一致时返回最新快照，不执行过期操作。
- 客户端等待权威快照中的 ACK，超时会重发；连续无 ACK 时主动请求全量状态。
- 权威端收到指令后先立即返回轻量回执，从机显示结算状态并暂停重复输入；完整快照随后完成最终确认。
- 待确认指令有有限重试和 8 秒总超时；收到更新的权威快照或完整重同步后会清理遗留指令，保证输入不会永久锁死。
- 重连采用 0.5、1、2、4、8 秒封顶的指数退避，并加入随机抖动。
- 战斗中检测到断线会立即冻结操作、取消临时目标并落盘当前快照，然后在一小时恢复窗口内自动重试。
- 局域网双方保存同一个随机战局 ID。加入方自动重连原 IP/端口，房主重新监听原端口；程序重启后可在主菜单点击“继续对局”。
- 战局恢复后双方交换 revision 快照，选择更新状态并完成 ACK，再解除战斗暂停；显式放弃或正常结算才清除恢复记录。
- 大厅的 P2 加入占位在 15 秒后自动过期，避免连接房间失败后永久显示已满。

## 诊断

运行日志中的 `[NET]` 行是 JSON，可按 `event`、`phase`、`room`、`attempt`、
`pending_commands`、`heartbeat_age_ms`、`reason` 和 `revision` 聚合。

常见事件：

- `command_sent` / `command_resent` / `command_ack`
- `duplicate_command_dropped`
- `command_resync_requested`
- `reconnect_started` / `reconnect_attempt` / `reconnect_retry_scheduled`
- `room_authenticated` / `reconnect_failed`
- `art_transfer_queued` / `art_checksum_failed`

## 验证

```powershell
.\scripts\run_tests.ps1
```

```bash
bash scripts/run_reconnect_integration.sh /path/to/godot
```

```powershell
.\scripts\run_lan_reconnect_integration.ps1 -GodotBin C:\path\to\godot_console.exe
```

集成测试启动大厅、房间进程和两个独立客户端，故意延迟命令 ACK 触发重发，
验证重复命令只执行一次，再断开 P2 并验证令牌重连、revision 43 快照恢复和
存活端通知。

局域网集成测试使用两个独立进程验证 UDP 房间发现，再让双方保存战局、完整退出并重启，验证会话身份、ENet 连接与本地快照恢复。

真实公网发布前仍需在预发布服务器执行丢包、延迟、抖动和服务进程重启测试。
