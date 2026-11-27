# 联机稳定性

## 当前边界

- 局域网模式使用 UDP 4569 广播发现可加入房间，对战使用 UDP 4568；自动发现失败时可手动填写 `IP` 或 `IP:端口`。
- 局域网模式不内置打洞或主机迁移。公网联机使用房间号模式。
- 房间号模式用于公网联机。大厅监听 UDP 4567，房间进程使用配置的 UDP 端口范围。
- 客户端、大厅进程和房间进程必须使用同一协议。公网大厅和房间进程现使用 v19，「目标」和「目标及相邻」随所选单位结算。

## 可靠性机制

- 双方提交牌组后等待卡图同步，最多等待 10 秒。同步完成或超时后，房主发送完整规则及双方牌组内容摘要。超时的一方会在同一个确认弹窗中看到卡图占位提示。双方均确认同一份摘要后才进入战斗。协议拒绝越界规则、错误牌组摘要和不匹配的确认哈希。
- 卡图清单、分片和确认消息先入队，仅在当前 SceneMultiplayer 绑定的实际连接为 CONNECTED、且收件方已登记时发送；RPC 提交成功才出队。连接中或背压时保留队头，确认消息优先于本地上传积压。退出房间清队列，退出后的迟到回调不能重新入队。等待室的准备按钮还要求应用层握手完成。

- 通道 0：大厅、房间认证和连接状态。
- 通道 1：局域网握手、编辑与准备、战斗命令和权威快照。消息可靠有序。
- 通道 2：等待室可靠探测。进入对局后用于不可靠有序的目标箭头和演出提示，允许丢弃旧帧。玩家持续指向同一格时，每 250 毫秒刷新一次箭头。接收端超过 1.25 秒未收到刷新便清除箭头，结束瞄准时仍立即发送清除消息。
- 通道 3：卡图；24 KiB 分片、SHA-256 校验、逐帧限速。
- 通道 4：房间号联机补取已确认战局。请求可丢失并定期重发，战局补发可靠有序。
- 通道 5：房间号联机复线后重发待确认指令；可靠有序。

从机输入指令与轻量接收回执走通道 1。房间号联机等候结算满 1 秒时，从机会通过通道 4 请求房间服务器补发已保存的更新战局。服务器只在对局中的从机发来请求且已有更新状态时响应。补取只恢复战局，不重放迟到的战斗演出。
- 非权威端的每条战斗命令携带唯一 `command_id` 和 `expected_revision`。
- 双方确认开局后使用本局独立的对局编号。房间号可以沿用。战斗指令、结算快照和补发都携带本局编号，玩家与房间进程忽略迟到的上一局消息。
- 房间号模式由房间进程确定先手，局域网由房主确定。双方使用开局消息里的同一个结果，后手补偿随实际顺序发放。
- 权威端丢弃重复命令；revision 不一致时返回最新快照，不执行过期操作。
- 客户端等待权威快照中的 ACK，超时会重发；连续无 ACK 时主动请求全量状态。
- 权威端收到指令后先立即返回轻量回执，从机显示结算状态并暂停重复输入；完整快照随后完成最终确认。
- 初始战局和权威快照在发送时按需压缩，接收后恢复完整状态。诊断分别记录指令发送、到达主机、主机发出战局、从机收到确认的时间，以及压缩前后的数据字节数。
- 待确认指令在连接可用时最多等候 8 秒；超时后请求权威快照，并告知玩家正在同步战局。收到更新的权威快照或完整重同步后会清理遗留指令。
- 房间号模式在对局中每秒向房间服务器验证一次往返连接。连续约 4 秒收不到有效回执时暂停本地操作，保留已提交指令并暂停其超时计时。连接恢复后按原顺序通过独立通道重发待确认指令，保留原指令编号和版本。收到确认后开放操作。房间连接两端的 ENet 最短超时为 20 秒，为短时断网后仍在重传的常规消息留出时间。
- 房间号模式验证席位后也在等待室探测往返连接。常态使用可靠探测，失联后另发即时探测，便于在可靠队列恢复前确认链路已通。短时失联时显示恢复提示，暂停新增准备、进入卡牌编辑和确认开局。玩家仍可取消准备或离房，连接恢复后沿用原席位、卡组和确认状态。
- 服务端根据房间实际席位拒绝满房和对局中的加入请求。尚未认证的加入名额 15 秒后过期。
- 发出建房或加入请求之后取消时，客户端保留连接做席位清理，再回到原表单。取消后等待房间认证最多 3 秒，认证成功则走离房确认流程；房间不可达时，席位仍按服务端租期过期。
- 房间号入口在建房或加入失败后保留地址和房号。房号无效、找不到房间或建房号已被占用时选中原房号，便于替换。满房、正在对局或连接超时时保留现有内容并聚焦房号，回车可重试加入。
- 主动离房或连接中断达到超时会释放席位。留在房间的玩家接管房主，沿用原房间号。对局中断后，结算页会接管当前界面，区分对手主动离开、本端断开和对手断开。原房间仍可用时优先返回同一等待室，连接丢失时返回联机方式选择。
- 房间号模式和双方均支持再战的局域网模式可从结算返回同一等待室。双方回房后才可准备下一局。局域网通过同一有序通道发送回房和准备消息，并用上局编号校验回房消息。取消规则确认会解除双方准备。房间号和局域网里，一方编辑卡牌时会解除双方准备并显示对手编辑状态。编辑结束并同步到对方后可重新准备。
- 房间号联机中，一方离房结束对局后，补位玩家可在留房方查看结算时加入。加入后显示留房方正在查看结算，并等候房主同步当前规则。留房方返回房间后开放准备和创建卡牌。
- 房间号联机由服务器为每轮准备分配编号。取消准备、进入卡牌编辑、席位变化或开局会使上一轮编号失效。客户端忽略已取消轮次的规则确认，服务器忽略该轮迟到的准备、取消和开局请求。
- 局域网开局前，对方离房或断线时，正在编辑的玩家可以继续编辑和保存。访客离开后房主保留原等待室，可接收新访客。房主离开后访客返回加入页，保留原地址，可重试或搜索其他房间。
- 等待室优先使用卡牌库当前正在使用的可用卡组，也可以在房间里更换。房间会记住选中的卡组，回房时读取卡组的最新内容。房间内创建卡牌时，编辑器默认选中这副卡组作为保存目标。
- 房间号与局域网模式都允许在确认前取消准备，双方回到等待室。房主可在双方未准备时修改规则。任一方准备后，规则只能查看，未保存的修改会被丢弃并提示。离房按钮和 Esc 使用同一条路径，房间有另一位玩家时先确认。
- 当前版本不开放断线续局或重启客户端后恢复联机对局。

## 诊断

运行日志中的 `[NET]` 行是 JSON，可按 `event`、`phase`、`room`、`attempt`、
`pending_commands`、`heartbeat_age_ms`、`reason` 和 `revision` 聚合。

常见事件：

- `command_sent` / `command_resent` / `command_ack`
- `duplicate_command_dropped`
- `command_resync_requested`
- `room_checkpoint_applied`
- `room_link_interrupted` / `room_link_restored`
- `prior_match_message_ignored`
- `reconnect_started` / `reconnect_attempt` / `reconnect_retry_scheduled`
- `room_authenticated` / `reconnect_failed`
- `art_transfer_queued` / `art_checksum_failed`

## 验证

```powershell
.\scripts\run_tests.ps1
```

```bash
python scripts/run_dedicated_integration.py /path/to/godot
python scripts/run_dedicated_integration.py /path/to/godot --weak-network
python scripts/run_dedicated_integration.py /path/to/godot --hold-gameplay-replies
python scripts/run_dedicated_integration.py /path/to/godot --short-outage --native
python scripts/run_dedicated_integration.py /path/to/godot --waiting-outage --native
python scripts/run_dedicated_integration.py /path/to/godot --short-outage --block-resumed-intents
python scripts/run_dedicated_integration.py /path/to/godot --long-outage --native
python scripts/run_dedicated_integration.py /path/to/godot --replay-prior-match
python scripts/run_dedicated_integration.py /path/to/godot --replay-prior-offer
python scripts/run_dedicated_integration.py /path/to/godot --join-during-results --native
python scripts/run_dedicated_integration.py /path/to/godot --stall-card-art --native
python scripts/run_dedicated_integration.py /path/to/godot --cancel-entry --native
python scripts/run_dedicated_integration.py /path/to/godot --native --language en
python scripts/run_room_integration.py /path/to/godot
python scripts/run_room_integration.py /path/to/godot --stall-card-art
python scripts/run_room_integration.py /path/to/godot --edit-in-room --native
python scripts/run_room_integration.py /path/to/godot --edit-in-room client
python scripts/run_room_integration.py /path/to/godot --edit-in-room solo-host
python scripts/run_room_integration.py /path/to/godot --edit-in-room client-leaves --native
python scripts/run_room_integration.py /path/to/godot --edit-in-room host-leaves --native
python scripts/run_room_integration.py /path/to/godot --edit-in-room client-leaves --drop-editor-link
```

专用服务器集成测试使用独立进程检查满房、房主移交、替补加入、编辑期间暂停准备、取消确认、对局、回房再战以及进行中的房主退出。局域网集成测试覆盖双方准备、规则同步、回合推进，以及断开后从结果页返回联机入口。

弱网检查在本机转发实际 ENet 数据，为两个方向各加入 80 毫秒单程延迟、±35 毫秒抖动和 7% 随机丢包。报告会记录各链路的实际转发和丢包数量。主动离房等待服务器确认释放席位，再关闭连接。

定向丢包检查在从机结束回合后阻断通道 1 的下行数据 5 秒。测试要求从机在阻断期间通过通道 4 确认新回合，并验证双方战局摘要一致。

短时断网检查在从机提交结束回合时双向丢弃所有数据 9.5 秒。测试在断网期间检查恢复提示、按钮和未确认指令，并验证原连接恢复后该回合只结算一次。可叠加 `--weak-network` 验证恢复期间仍有随机丢包的情况。`--block-resumed-intents` 额外阻断常规上行通道 5 秒，验证恢复时同一条指令经备用通道抵达主机。

等待室断网检查在访客准备前和规则确认期间分别切断其双向连接 8.5 秒。测试验证恢复提示、暂停新增准备和确认操作、保留可用的取消与离房入口，并检查在原房间完成开局和再战。报告记录每次流量恢复到客户端解除暂停的时间。

持续断网检查在再战时隔离正在查看暂停设置的房主。测试验证结算页接管界面，掉线方可按 Esc 返回联机入口，留在房间的玩家接管房主并可用原房间号邀请替补，双方可重新准备。

卡图超时检查发送一张实际卡图，暂时停用从机的卡图接收回调。测试验证超时后自动打开规则确认，取消后双方可重新准备。房间号模式还在卡图仍未收到的情况下确认并进入对局。

局域网编辑检查分别让房主和访客在对手已准备时进入卡牌编辑，并验证等待方解除准备。也检查访客加入一个房主正在编辑的房间。编辑结束后双方沿用原连接，重新准备并完成开局和回合。

局域网编辑中断检查在打开卡牌草稿后让对手主动离房，或切断访客双向 UDP 流量。测试执行保存和返回，验证房主的原房间接收新访客、对局读取新卡，也验证访客返回加入页时保留原地址。

取消加入检查在大厅分配席位、房间认证尚未完成时按下取消。验证客户端回到原表单且保留房间号，随后独立客户端立即加入同一房间。

房间号入口检查使用真实大厅验证房号占用、无此房间、满房、正在对局和连接超时，确认失败后仍可操作原表单。满房检查从建房号已被占用的提示中通过回车提交加入请求。`--native` 会在未启用弱网时捕获满房提示。

再战检查会在新一局的相同回合阶段重发上一局实际产生的指令和快照。测试确认两个玩家都收到并拒绝了旧消息，随后本局双方的回合仍能正常结算。

取消准备检查在访客重新准备后，通过实际房间连接重发取消的规则确认和取消请求。测试检查当前准备仍有效，双方确认新一轮规则后能开局和再战。

结算补位检查让房主在再战中离房，留房方停在结算页。新访客加入原房间后能看到结算状态、规则等待提示和离房确认。留房方返回后，新访客在原连接上看到同步后的规则并准备，留房方收到准备状态。

真实公网发布前仍需在预发布服务器执行丢包、延迟、抖动和服务进程重启测试。

## 行动力同步

战场快照包含行动力余额、回合额度及已执行行动次数。房主校验行动付款，规则配置参与双方确认。
