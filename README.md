# Card UGC Game

一款基于 Godot 4 制作的卡牌 UGC（用户生成内容）对战游戏。玩家可以创建拥有自定义属性、技能和插画的卡牌，组建卡组，与其他玩家进行在线或本地对战。

## 特性

### 卡牌创作
- **卡牌编辑器**：自定义卡名、性别、攻防数值、圣水消耗、插画
- **技能编辑器**：可视化构建技能的触发器、效果、目标、条件、随机范围
- **三种卡牌类型**：普通单位、法术（spell）、寄生体（parasite）
- **天赋技能**：被动技能可标记为天赋，无法被沉默阻止
- **限定技**：每局游戏仅可使用一次的强力技能

### 战斗系统
- **战场布局**：每方 5 个槽位 + 手牌区 + 抽牌堆 + 弃牌堆
- **圣水系统**：永久圣水 + 临时圣水（消耗优先扣临时）
- **战斗机制**：嘲讽、反伤、护盾、沉默、魅惑、免疫致命伤害
- **战败补偿**：卡牌死亡抽牌、本体受击获得临时圣水（可开关）
- **基地卡牌 UI**：敌我双方各自一张卡牌大小的基地牌，显示 HP 与圣水
- **三技能支持**：单张卡牌最多 3 个技能按钮

### 多人对战
- **热座模式**：本地两人轮流
- **练习模式**：与 AI 对战
- **直连 P2P**：通过 IP/端口直接连接
- **房间号联机**：通过房间服务器中转
- **专用服务器**：支持独立服务器托管
- **断线续局**：心跳与连接事件双重检测；房间号模式保留稳定席位和本地战局快照，可在断线或程序重启后继续

### 技能引擎
- **触发时机**：召唤、攻击、受伤、死亡、激活、回合开始/结束
- **效果类型**：伤害、治疗、抽牌、护盾、魅惑、增益、法力、攻击力、血量上限、查看弃牌堆/抽牌堆、零费施放等
- **条件系统**：基于 HP 百分比、手牌数、圣水数、场上单位数、buff 状态等条件触发
- **目标选取**：自身、单体、单边、全部；支持随机数量
- **可负值效果**：获得圣水、攻击力、血量上限允许负值（用于减益）

## 技术栈

- **引擎**：Godot 4.6.3+（GDScript；项目元数据兼容 4.7）
- **网络**：ENetMultiplayerPeer（P2P） + 自建房间服务器
- **国际化**：内置中英双语切换
- **无外部依赖**：纯 Godot 项目，无需第三方库

## 项目结构

```
.
├── Main.tscn / Main.gd             # 战斗主场景与逻辑
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

### 开发者
```bash
git clone https://github.com/Chai-maomao/Card-UGC-Game.git
cd Card-UGC-Game
# 用 Godot 4.6.3+ 打开 project.godot
```

### 启动专用服务器（可选）
```bash
start_server.bat
```

### 自动测试
```bash
# 运行所有无界面回归场景
GODOT_BIN=/path/to/godot ./scripts/run_tests.sh

# 启动本地大厅和两个客户端，验证断线后令牌重连
GODOT_BIN=/path/to/godot ./scripts/run_reconnect_integration.sh
```

## 战斗规则

- 起始 HP：30（可在战斗配置中调整）
- 起始圣水：4（默认每回合 +2，上限 10）
- 手牌上限：6
- 抽牌：默认每回合开始抽 2 张（可在战斗配置中调整）
- 攻击：直接攻击卡牌或本体（无嘲讽时）
- 胜利条件：将对方 HP 降至 0

## 联机模式

| 模式 | 描述 | 主机权限 |
|------|------|---------|
| 热座 | 本地双人轮流 | 双方均为主机 |
| 练习 | 单人 vs AI | 玩家为主机 |
| 直连 | IP + 端口连接 | 房主为主机 |
| 房间号 | 通过房间服务器中转 | P1 为主机 |
| 专用服务器 | 独立房间进程负责认证与中转 | P1 为战局权威端 |

**仅 P1（主机）可自定义战斗规则**，包括起始 HP、圣水上限、战败补偿等。

## 已知机制

- **沉默**：阻止普通被动技能，但不阻止天赋
- **免疫致命伤害**：`immune_lethal` buff 可让卡牌在致命伤害下保留 1 HP
- **永久属性提升**：仅卡牌在场时生效，退场后恢复基础值
- **致命伤害时不触发受伤技能**：HP 归零后跳过 `ON_DAMAGED` 触发器
- **结束回合防双击**：所有路径禁用按钮直到回合切换完成

## 协议

详见仓库 LICENSE（如有）。

## 致谢

- Godot Engine
- 所有参与测试与反馈的玩家
