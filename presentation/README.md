# 3D 桌面表现

默认标题与战斗由 BattleTable3D 构建暗石台、黄铜、纸卡与暖灯。Main.gd → BattleMain3D.gd → BattleMainNetwork；Control 槽位负责输入/教学，GameState 仍是规则权威。

- ClassicBattleCardFace 统一绘制卡面：战斗直接烘焙该绘制源；CardUI 与标题桌面的 TabletopCardFace 委托同一绘制。底部 HP、ATK 小标记分别配数值；卡牌选择共用 CardSelectionOverlay，不在卡外追加勾选框。
- 拖拽/点击部署，拖动场内卡换位；点击场内卡打开行动面板，右键手牌看详情。Tab/Enter 可操作代理控件；Esc 关闭弹层或打开本地暂停/联机菜单。
- 卡位运动采用解析临界阻尼、微小悬停与定向冲量；不使用物理碰撞改变玩法。桌面/卡片最低角有表现高度约束；交换时采用上层通道。碎屑是真刚体，预热48个，共享网格/形状/材质，超时回收。低画质与减少动态关闭碎屑。
- 低/中/高只影响 MSAA、主光阴影、碎屑与支持的后处理，布局与卡面不变。Compatibility 无 SSAO/glow；高档 Forward+ 启用克制的接触阴影与高光。
- 音频在实际反馈路径触发，避免后台复算重复发声；Master/BGM/SFX/UI 独立，总线限幅。用户提供的 cardex-title.mp3 用于菜单，cardex-battle.mp3 用于战斗；按场景切换并循环播放，同类场景之间保留播放进度；切换先淡出 0.45 秒，再淡入 1.2 秒，设置中退出到桌面也先淡出。原合成低频循环与电子悬停提示已停用。用户提供的音效经去除首尾空白、保守增益调整后位于 res/audio/sfx：punch 用于普通攻击，heal 用于治疗，magic_smite/dark_magic 用于伤害法术与状态效果，deploy_card 两变体用于落牌/附着，shuffle 两变体用于抽牌，swoosh 用于移动，mouse_over_menu 用于按钮点击，mouse_over_object 统一用于菜单与卡牌悬停；原 mouse_over_card 保留来源记录但不再用于悬停。悬停按控件去重，进入不同控件即时触发，最多允许3段短音自然重叠，抽牌按批次发声；均使用音效音量设置。处理参数及原始/运行资产校验值见 res/audio/sfx/SOURCES.json。许可来源见 legal/THIRD_PARTY_NOTICES.md。
- `TestTabletop3DVisual.tscn` 使用真实输入覆盖部署、移位、攻击、技能、弃牌、法术、寄生与状态隔离。旧视觉夹具通过 tests/VisualBattleInput.gd 点击实际行动面板，不再点击隐藏按钮。

本地验证证据放在 artifacts/release-readiness-20261112。不能用高端笔记本结果代表中端/集显或移动设备；不能把自动截图称作人工试玩。源码和本地候选包不代表已公开发布。

2026-11-14：shuffle/shuffle_2按用户复听确认保留原名；新增用户素材shuffle_3，洗回牌库使用三份轮换，批量抽牌及溢出仅使用短音效shuffle。所有拒绝声统一走SFX通道、相同素材与-1dB增益（原战斗+3dB）。

单张抽牌成功进入手牌时使用用户提供的distributing_single.wav；批量抽牌和溢出使用短音效shuffle，每批仅触发一次拿牌音。洗回牌库仍使用shuffle。

2026-11-14：shuffle_2仅用于洗牌；新增deploy_card_3，与deploy_card、deploy_card_2一起轮换用于部署。单张入手仍使用distributing_single。

当前发牌映射：单张成功入手使用distributing_single；多张发牌及溢出每批播放一次短音效shuffle；洗牌轮换shuffle、shuffle_2、shuffle_3。distribute_multi的MP3由用户MP4提取并保存在原视频旁，处理后的WAV保留在项目中，因过长暂不调用。

主动弃牌图标从卡牌位置飞入弃牌区，落点增加计数并播放纸牌落牌音；阵亡、溢出和洗回牌库的显示计数也等待图标到达。仅延迟显示，不延迟规则结算。
