# Card UGC Game

一款基于 Godot 4 制作的卡牌 UGC（用户生成内容）对战游戏。玩家可以创建拥有自定义属性、技能和插画的卡牌，组建卡组，与其他玩家进行在线或本地对战。

## 特性

### 卡牌创作
- **卡牌编辑器**：自定义卡名、性别、攻防数值、圣水消耗、插画
- **技能编辑器**：可视化构建技能的触发器、效果、目标、条件、随机范围
- **三种卡牌类型**：普通单位、法术（spell）、寄生体（parasite）
- **天赋技能**：被动技能可标记为天赋，无法被沉默阻止
- **限定技**：可设置技能累计次数；跨回合保留，卡牌退场重置后恢复，连锁和寄生物独立遵守次数。见 [SKILL_USE_LIMITS.md](SKILL_USE_LIMITS.md)。
- **试打诊断**：记录技能触发、条件、目标、计算值和跳过原因，可保存同一局面反复调试
- **反应连锁一致性**：受伤、治疗被动的资源与手牌归反应单位所属玩家，定向反应选中实际施加者；玩家、AI与静音重放共用规则。见 [REACTION_CONTEXT.md](REACTION_CONTEXT.md)。
- **行动经济诊断**：用当前开战规则试算递增行动费用，提示资源先付后得、技能击杀与普攻回费的区别；试打显示真实下一行动支付。使用与验收见 [ACTION_ECONOMY_DIAGNOSTICS.md](ACTION_ECONOMY_DIAGNOSTICS.md)。
- **批量模拟诊断**：把当前草稿加入单位、法术和辅助标准共享牌池，以固定种子运行多局 AI 对战；按实际事件记录行动力、圣水、伤害和治疗，区分自动攻击、连锁与寄生来源。口径见 [BATTLE_METRICS.md](BATTLE_METRICS.md)。
- **卡牌版本历史**：每张卡自动保留最近 10 个不同保存版本，显示相对当前草稿的属性与技能变化；旧版本先恢复到草稿，确认后再正常保存
- **分享溯源**：分享包可填写作者、内容版本和来源，导入前显示玩法差异摘要

### 战斗系统
- **3D 实体卡牌桌面**：暗石台、黄铜线脚与纸质卡牌；战斗、收藏、准备与编辑预览共用大插画卡面，底部对称显示 HP 与 ATK。选牌直接点击卡面，以遮罩和边框标记选中。
- **卡图裁切**：上传图片后，在卡牌预览上拖动定位并调整缩放；确认保存裁切结果，取消保留之前的卡图。
- **战场布局**：每方 5 个固定槽位 + 最多 8 张弧形手牌 + 抽牌堆 + 弃牌堆
- **圣水系统**：永久圣水 + 临时圣水（消耗优先扣临时）
- **战斗机制**：嘲讽、反伤、护盾、沉默、魅惑、免疫致命伤害
- **战败补偿**：默认后手额外 2 点首回合圣水并开启卡牌死亡抽牌；所有补偿项仍可在开战前编辑
- **基地卡牌 UI**：敌我双方各自一张卡牌大小的基地牌，显示 HP 与圣水
- **三技能支持**：单张卡牌最多 3 个技能按钮

### 多人对战
- **热座模式**：本地两人轮流
- **练习模式**：与 AI 对战
- **局域网联机**：自动发现同网段房间，或通过 IP/端口手动连接；跨公网由玩家自行配置内网穿透
- **网页中转联机**：暂时关闭入口，保留实现供以后恢复
- **统一战斗准备**：练习、热座与各联机入口共用卡组组件；单击选中高亮、双击查看卡牌。常用战场参数同页调整，完整参数通过“高级战斗设置”打开；热座玩家2只读玩家1规则。
- **专用服务器**：支持独立服务器托管
- **连接状态提示**：检测连接中断并提示玩家；当前版本不提供断线续局或重启后恢复联机对局。
- **开战确认**：双方查看相同的规则和已提交牌组，并分别确认后开战

### 技能引擎
- **触发时机**：召唤、攻击、受伤、死亡、激活、回合开始/结束
- **效果类型**：伤害、治疗、抽牌、护盾、魅惑、增益、法力、攻击力、血量上限、查看弃牌堆/抽牌堆、零费施放等
- **条件系统**：基于 HP 百分比、手牌数、圣水数、场上单位数、buff 状态等条件触发
- **目标选取**：自身、单体、单边、全部；支持随机数量
- **可负值效果**：获得圣水、攻击力、血量上限允许负值（用于减益）
- **组合挑战**：7 个由浅入深的可重复练习，覆盖资源连锁、增益顺序、嘲讽、净化、驱散、斩杀阈值与寄生附着，并提供分阶段进度、可选提示、错误反馈和通关要点

### 新手引导

新手教程使用真实创卡、技能编辑和战斗操作；战场篇按15步介绍生命/胜负、五格战场、共享牌堆、圣水与行动力、卡牌数值及结束结算，并高亮对应目标。教程范围与验证见 [TUTORIAL_BASICS.md](TUTORIAL_BASICS.md)。

首次启动会从原有标题页自动进入四步引导，然后接入创卡与战场教程，每页均可跳过。完成或跳过后不再自动出现；已有牌库存档的老玩家兼容迁移，手动教学入口继续保留。进度使用 `user://tutorial_progress.cfg`，见 [FIRST_LAUNCH_TUTORIAL.md](FIRST_LAUNCH_TUTORIAL.md)。

## 技术栈

- **引擎**：Godot 4.6.3+（GDScript；项目元数据兼容 4.7）
- **网络**：Cloudflare Workers/D1 HTTPS 中转 + 独立 Sites Beta + ENet 局域网/专用服务器
- **国际化**：内置中英双语切换
- **无外部依赖**：纯 Godot 项目，无需第三方库

## 项目结构

```
.
├── Main.tscn / Main.gd             # 战斗主场景与逻辑
├── BattleMainFoundation.gd         # 2D 战场基础设施与公共状态
├── BattleMainActions.gd            # 召唤、攻击、技能和回合操作
├── BattleMainPresentation.gd       # 2D 卡牌、手牌、反馈和动画
├── BattleMainNetwork.gd            # 联机战斗命令与同步
├── GameState.gd                    # 游戏状态机：回合、伤害、死亡清理
├── BattleField.gd                  # 战场：圣水、HP、槽位
├── CardData.gd                     # 卡牌数据模型
├── CardUI.tscn / CardUI.gd         # 卡牌 UI 控件
├── SlotUI.tscn / SlotUI.gd         # 战场槽位
├── SkillEngine.gd                  # 技能触发与效果分发
├── SkillEffectApplier.gd           # 技能效果应用
├── SkillEditor.tscn / SkillEditor.gd   # 技能编辑器
├── CardEditor.tscn / CardEditor.gd     # 卡牌编辑器
├── MyCards.tscn / MyCards.gd       # 卡组管理
├── BattleDeckSelect.tscn           # 战斗卡组选择与规则配置
├── NetworkManager.gd               # 网络层（P2P / 房间 / 专用服务器）
├── Lobby.gd / DirectLobby.gd       # 联机大厅
├── server.gd / room_server.gd      # 服务端
├── PlayerData.gd                   # 玩家数据 autoload
├── EventBus.gd                     # 全局事件总线 autoload
├── Locale.gd                       # 国际化 autoload
├── ParasiteRules.gd                # 寄生体规则
├── SpellRules.gd                   # 法术规则
├── BalanceEvaluator.gd             # 卡牌平衡评估
├── UITheme.gd                      # UI 主题
└── Test*.tscn                      # 测试场景
```

## 如何运行

### 玩家
1. 安装 [Godot 4.6.3+](https://godotengine.org/download/)
2. 用 Godot 打开项目文件夹
3. 按 F5 运行（或导出为可执行文件）

### Android

将 `build/android/CARDEX.apk` 传到设备并打开安装。APK 包含 ARM64 手机和平板以及 x86_64 模拟器所用的原生库。游戏使用横屏，可从任一侧握持。

- 拖动手牌出牌，长按手牌查看详情。轻点「结束回合」提交操作，长按可先查看结算预览。系统返回键可以关闭弹窗或暂停战斗。
- 在技能编辑器中拖动积木，在空白画布上拖动平移，双指或使用「＋」「－」缩放。插画和卡组文件通过系统文件选择器读写。
- 切到后台时会保存正在编辑的卡牌和技能草稿。系统回收游戏后，重新打开「卡牌编辑器 → 继续上次的草稿」即可接着制作。
- 与 Windows 玩家联机时，两端使用相同协议版本，在「进入战斗 → 联机对战 → 局域网联机」创建或加入房间。卡组可在「我的卡牌」内导出并跨设备导入，分享文件包含自定义卡图。
- 自行构建时，安装 Godot 4.6.3 对应的 Android 导出模板，在编辑器设置中配置 Android SDK 和 JDK 17。创建 `build/android` 后运行 `godot --headless --path . --export-debug Android build/android/CARDEX.apk`。Release 导出使用同一预设和自己的签名密钥。

### 开发者
```bash
git clone https://github.com/Chai-maomao/Card-UGC-Game.git
cd Card-UGC-Game
# 用 Godot 4.6.3+ 打开 project.godot
```

在桌面调试构建中，按 Esc 下方的反引号键打开开发者控制台。输入 `help` 查看命令，Tab 补全，上下键翻阅本次运行的命令历史，F11 展开或收起控制台，Esc 关闭。

本地战斗中输入 `give 盾卫`，可以把一张同名卡牌加入当前玩家的手牌，并写入战斗记录。离线输入 `init` 可以从欢迎页重走首次引导，引导进度保存到本次调试会话的临时文件。

### 启动专用服务器（可选）
```bash
start_server.bat
```

### 自动测试
```bash
# 运行所有无界面回归场景；各场景使用隔离存档，不改动玩家收藏
python scripts/verify_release.py /path/to/godot --suite logic

# 在有图形环境的机器上运行截图验收
python scripts/verify_release.py /path/to/godot --suite visual --timeout 180

# 验证当前局域网房间的规则同步、双方准备和断线处理
python scripts/run_room_integration.py /path/to/godot
```

逻辑检查中的千局对战模拟单独允许最多 900 秒；其他场景默认 100 秒。可通过 `--simulation-timeout` 和 `--timeout` 分别调整。断线续局已关闭，旧 `run_reconnect_integration.sh` 不作为当前版本的验收入口。

### 3D 桌面操作

- 将手牌拖到高亮的我方空槽完成召唤；法术和寄生牌按高亮目标释放。
- 点击我方场上卡牌打开行动面板，选择攻击或技能，再点击高亮目标。右键手牌查看完整详情。
- 点击战场空白处取消当前目标选择。
- 悬停卡牌可查看完整技能说明；牌堆、弃牌区、状态条与结束回合始终保持在固定位置。
- 手牌上限为 8，合法满手状态会完整收纳在手牌区域内。

默认表现为 3D 桌面；原 Control 槽位继续负责输入与教学定位。规则层、回放、AI 与联机同步共用同一份 `GameState`，表现物理不参与规则。

## 战斗规则

- 起始 HP：30（可在战斗配置中调整）
- 起始圣水：4（默认每回合 +2，上限 10）
- 手牌上限：8
- 抽牌：默认每回合开始抽 2 张（可在战斗配置中调整）
- 行动力：回合开始抽牌后，按 `floor(3 + 空战场格数 + 0.5 × 空手牌格数)` 固定本回合额度；四项参数可在开战规则中调整。
- 普攻与主动技能共享行动计数，第一个行动免费，后续依次消耗 1、2、3…行动力；不足部分按系数折算圣水并向上取整。部署、法术与被动连锁不计入行动。
- 攻击：直接攻击卡牌或本体（无嘲讽时）
- 胜利条件：将对方 HP 降至 0

## 联机模式

| 模式 | 描述 | 主机权限 |
|------|------|---------|
| 热座 | 本地双人轮流 | 双方均为主机 |
| 练习 | 单人 vs AI | 玩家为主机 |
| 局域网联机 | UDP 自动发现或 IP + 端口连接 | 房主为主机；不内置公网穿透 |
| 服务器联机 | 输入或分享房间号，服务器设置可切换地址 | 房主可设置规则，退出后由留在房间的玩家接管 |
| 服务器联机（Cloudflare） | HTTPS 八位房间码 | P1 为主机 |
| 联机 Beta | 独立 Sites HTTPS 中转，八位房间码 | P1 为主机 |

**仅 P1（主机）可自定义战斗规则**，包括起始 HP、圣水上限、战败补偿等。

联机协议 v15 的房间流程、对局确认、局域网发现和部署边界见 [NETWORK_RELIABILITY.md](NETWORK_RELIABILITY.md)。

Cloudflare 迁移状态与部署步骤见 [Cloudflare 联机服务](cloudflare/online-relay/README.md)，独立 Beta 见 [ONLINE_BETA.md](ONLINE_BETA.md)。已释放的阿里云地址不会再用于恢复旧房间；本地旧数据保留。

## 已知机制

- **沉默**：阻止普通被动技能，但不阻止天赋
- **免疫致命伤害**：`immune_lethal` buff 可让卡牌在致命伤害下保留 1 HP
- **永久属性提升**：仅卡牌在场时生效，退场后恢复基础值
- **致命伤害时不触发受伤技能**：HP 归零后跳过 `ON_DAMAGED` 触发器
- **结束回合防双击**：所有路径禁用按钮直到回合切换完成

## 协议

源码权利说明见 [LICENSE](LICENSE)，第三方许可与待核实素材见 [许可清单](legal/THIRD_PARTY_NOTICES.md)。

## 致谢

- Godot Engine
- 所有参与测试与反馈的玩家

## 中盘翻盘率验证

新增 `RunComebackBenchmark.tscn` 无头入口，可指定牌池、局面、随机种子及行动力参数变体，从确定的中盘快照继续对局。`scripts/analyze_comeback.py` 输出配对统计、按随机种子聚类的区间、CSV 与图表。完整方法、结果及复现命令见 [COMEBACK_BALANCE_REPORT.md](COMEBACK_BALANCE_REPORT.md)。

持续维护的约束、每轮现状、验收与接续任务见 [DEVELOPMENT_ITERATIONS.md](DEVELOPMENT_ITERATIONS.md)。战斗中悬停“结束回合”可查看预计自动攻击、行动力/圣水消耗和因资源不足无法行动的单位；回合结束技能或状态可能改变结果时会显示估算提示。

本地对局可在“战斗记录”底部保存完整局面，使用 `RunNaturalPositions.tscn` 无头验证并按同一状态配对续局。自然对局采样条件、当前结果和复现命令见 [NATURAL_POSITIONS.md](NATURAL_POSITIONS.md)。

“组合挑战”新增“预算接力”“收尾顺序”，练习技能付款、后续圣水预算、临时圣水到期及自动攻击顺序。玩法、解法和验收见 [ACTION_CHALLENGES.md](ACTION_CHALLENGES.md)。

无头自然采样新增固定复杂UGC测试牌池 `pool=ugc-v1`，保留完整内容指纹、逐卡实际事件与配对重放。定义、复现和小样本边界见 [UGC_BENCHMARK.md](UGC_BENCHMARK.md)；不会写入玩家牌库。

AI 对简单恢复技能按付款后实际到账圣水和缺血量估值，避免优先浪费满圣水回费或满血治疗；治疗触发被动和复杂UGC保留保守估值。范围与复现见 [AI_RECOVERY_PLANNING.md](AI_RECOVERY_PLANNING.md)。

完整录像可生成逐行动决策与实际收益的离线交互报告，比较原理由和当前启发评分、筛选行动并核对状态哈希。运行与证据边界见 [AI_DECISION_TRACE.md](AI_DECISION_TRACE.md)。


## 发行候选与本地构建

1.0.0-rc.13 源码与当前公网房间号服务器使用联机协议 18。先前构建的 1.0.0-rc.4 使用协议 9，官网的 1.0.0-rc.2 测试包使用协议 7。进入当前公网房间须使用协议 18 的客户端。默认构建 Windows x64 便携候选包。

- 设置按画面、声音、游戏、操作分类。首次启动默认全屏，可选择全屏、窗口化、桌面无边框窗口化，选择会保存；保留分辨率、VSync、帧率、画质、音量、播放速度等选项。设置保存在原有 settings.cfg 中，保持卡库与战局存档格式。
- Esc 优先关闭顶层弹层；本地对局可暂停，联机菜单持续收发网络，不冻结对手。设置 → 支持与说明提供许可、隐私、UGC、诊断与本地目录入口。诊断不会自动上传。
- 构建使用 `python scripts/build_windows.py <Godot 4.6.3 可执行文件>`。产物在 `build/windows/1.0.0-rc.13/` 与同级 ZIP。便携包未签名，运行时需保持 Cardex.exe 和 Cardex.pck 同目录。
- 图形默认 Vulkan，并允许引擎回退到 D3D12/OpenGL。图形启动失败时可用包内 Compatibility.cmd 强制 OpenGL 3；旧驱动、集显和移动设备仍需实机验证。
- 发行检查：`python scripts/verify_release.py <Godot> --suite logic`；视觉用 `--suite visual`，必须打开生成截图复核。每个场景使用隔离资料目录；视觉检查需要 GPU 或 Xvfb/Mesa。长跑脚本 `scripts/run_presentation_soak.py` 按真实时钟运行，不加速。
- 包冒烟：`Cardex.exe -- --release-smoke`，在隔离用户目录与空解压目录验证。其检查资源、中文字体、说明文件、默认菜单、写入与测试文件排除；不代替完整试玩。

存档位于 `%APPDATA%/Godot/app_userdata/CardUGCGame`。更新前备份；删除便携包不会删除存档。原素材权利与公共服务运营者信息仍需核实，详见 [第三方清单](legal/THIRD_PARTY_NOTICES.md) 和 [发行说明](RELEASE_NOTES.md)。
