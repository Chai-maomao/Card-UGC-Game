extends Node

# ============================================
# Localization autoload — UI text + skill term tables (zh / en)
# Default language is Chinese. Selection persists to user://settings.cfg.
# ============================================

signal language_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_LANGUAGE := "zh"

var language: String = DEFAULT_LANGUAGE

# UI strings keyed by a stable id. Missing keys fall back to English, then to the key.
const STRINGS := {
	"zh": {
		# MainMenu
		"menu.start": "开始战斗",
		"menu.resume": "继续对局",
		"menu.reconnecting": "正在重连...",
		"menu.reconnect_failed": "重连失败，点击重试",
		"menu.card_editor": "卡牌编辑器",
		"menu.my_cards": "我的卡牌",
		"menu.online": "联机对战",
		"menu.language": "语言",
		"menu.language_prompt": "语言...",
		# MultiplayerMenu
		"mp.title": "多人游戏",
		"mp.connect_server": "连接服务器",
		"mp.direct": "直连 (P2P)",
		"common.back": "返回",
		# Lobby / DirectLobby shared
		"lobby.title": "联机对战",
		"lobby.server": "服务器:",
		"lobby.room_code": "房间号:",
		"lobby.room_placeholder": "例如 1234",
		"lobby.create": "创建房间",
		"lobby.join": "加入房间",
		"lobby.check_server": "检查服务器",
		"lobby.host": "创建主机",
		"lobby.ip": "IP 地址:",
		"lobby.enter_room_first": "请先输入房间号",
		"lobby.invalid_code": "房间号只能为 1-16 位字母或数字",
		"lobby.connecting_lobby": "正在连接大厅...",
		"lobby.failed_connect_lobby": "连接大厅失败 (err=%d)",
		"lobby.creating_room": "正在创建房间...",
		"lobby.joining_room": "正在加入房间...",
		"lobby.checking_status": "正在检查服务器状态...",
		"lobby.could_not_reach": "无法连接服务器。请检查 IP 以及服务器是否运行。",
		"lobby.could_not_reach_port": "无法连接游戏房间端口。请检查服务器防火墙。",
		"lobby.lost_game_room": "与游戏房间的连接已断开。",
		"lobby.room_created": "房间 %s 已创建！等待时可先选择卡牌...",
		"lobby.room_taken": "房间 '%s' 已被占用，请换一个房间号。",
		"lobby.server_rejected_code": "服务器拒绝了该房间号。",
		"lobby.server_full": "服务器已满（无空闲房间），请稍后再试。",
		"lobby.failed_join_room": "加入游戏房间失败 (err=%d)",
		"lobby.unknown_response": "未知的大厅响应: %s",
		"lobby.joined_room": "已加入房间 %s，请选择卡牌...",
		"lobby.room_not_found": "未找到房间 '%s'。",
		"lobby.room_full": "房间 '%s' 已满。",
		"lobby.connecting_server": "正在连接服务器...",
		"lobby.server_disconnected": "服务器已断开 (err=%d)",
		"lobby.server_status": "服务器已连接 | 房间数: %d | 端口: %d-%d",
		"lobby.opponent_connected": "对手已连接！",
		"lobby.opponent_joined_pick": "房间号 %s — 对手已连接，选择卡牌后点开始",
		"lobby.hosting": "正在创建主机...",
		"lobby.failed_host": "创建主机失败！(err=%d)",
		"lobby.joining": "正在加入 %s...",
		"lobby.failed_join": "加入失败！(err=%d)",
		"lobby.could_not_connect": "无法连接。请检查 IP、端口以及主机防火墙。",
		# DirectLobby
		"direct.title": "直接连接",
		"direct.join_by_ip": "按 IP 加入:",
		"direct.join_game": "加入游戏",
		# Waiting room
		"wait.exit": "退出到标题",
		"wait.create_card": "创建卡牌",
		"wait.select_start": "选择卡牌后点开始",
		"wait.opponent_pick": "对手已连接，选择卡牌后点开始",
		"wait.select": "选择",
		"wait.start_game": "开始游戏",
		"wait.waiting_opponent": "等待对手...",
		"wait.receiving_arts": "正在接收对手卡面 %d/%d...",
		"wait.transfer_arts": "卡面同步中：接收 %d/%d，上传确认 %d/%d...",
		"wait.no_arts": "对手无自定义卡面，准备进入...",
		"wait.waiting_ready": "等待对手准备...",
		"wait.arts_slow": "卡面接收较慢 (%d/%d)，可直接进入",
		"wait.enter_game": "进入游戏",
		# Battle (Main)
		"battle.draw_pile": "牌库",
		"battle.discard_zone": "弃牌区",
		"battle.discard_pile": "弃牌堆",
		"battle.debug_state": "调试状态",
		"battle.deck": "牌库: %d",
		"battle.discard": "弃牌: %d",
		"battle.enemy_info": "敌方信息",
		"battle.my_info": "我方信息",
		"battle.switching": "切换中...",
		"battle.waiting": "等待中...",
		"battle.reconnecting": "对手掉线，等待重连...",
		"battle.draw_pile_title": "牌库（%d 张）",
		"battle.discard_pile_title": "弃牌堆（%d 张）",
		"battle.close": "关闭",
		"battle.choose_keep": "选择要保留的卡牌",
		"battle.hand_remaining": "剩余手牌位: %d。最多可选 %d 张卡牌。",
		"battle.confirm": "确认",
		"battle.end_turn": "结束回合",
		"battle.status_line": "%s | 圣水: %d/%d | 生命: %d | 手牌: %d/%d | 回合 %d",
		"battle.view_turn": "P%d 回合",
		"battle.viewing": "查看 P%d %s",
		"battle.you": "我方",
		"battle.enemy": "敌方",
		# Tutorial toasts (contextual tips)
		"tip.no_attack_turn1": "第一回合不能攻击",
		"tip.no_enemy_skill_turn1": "第一回合不能对敌方使用技能",
		"tip.taunt_first": "必须先攻击带嘲讽的随从",
		"tip.taunt_skill_first": "必须先以带嘲讽的随从为目标",
		"tip.kill_mana": "击杀敌方随从，圣水 +1",
		"tip.discard_mana": "弃置卡牌，圣水 +1",
		"tip.hand_full": "手牌已满（上限 %d 张）",
		"tip.deck_reshuffle": "牌库已空，弃牌堆洗入牌库",
		# Rules manual
		"help.button": "玩法",
		"help.title": "玩法与机制",
		"help.close": "关闭",
		"help.body": "圣水（费用）\n· 召唤卡牌需要消耗等同其费用的圣水。\n· 新回合开始时圣水+2。\n· 击杀一个敌方随从，圣水 +1。\n· 将手牌或场上卡牌拖入弃牌区，圣水 +1。\n\n回合流程\n· 双方第一回合都不能攻击，也不能对敌方使用技能或效果。\n· 点击随从发起攻击，再点击敌方目标确认。\n· 每个随从每回合只能行动一次（攻击或主动技能）。\n· 点「结束回合」交给对手。\n\n战斗规则\n· 敌方存在嘲讽随从时，必须先攻击/指向它。\n· 当对手场上没有随从时，你的随从回合结束时会直接对玩家造成伤害，扣减玩家生命值。\n· 手牌上限为 %d 张。\n· 牌库抽空后，弃牌堆会洗回牌库。\n\n技能触发\n· 召唤时 / 主动 / 攻击时 / 受伤时 / 死亡时。\n· 主动技能每回合可用一次。被沉默的随从无法攻击或施放技能。",
		# CardUI
		"card.cost": "费用 %d",
		"card.cost_charmed": "费用 0",
		"card.hp": "生命 %d/%d",
		"card.hp_temp": "生命 %d/%d +%d",
		"card.atk": "攻击 %d",
		"card.atk_bonus": "攻击 %d (+%d)",
		"card.silenced": "[已沉默]",
		"card.basic_attack": "普通攻击\n对目标造成等同攻击力的伤害",
		"card.buff_tooltip": "%s: %d (剩余 %d 回合)",
		# MyCards
		"mycards.title": "我的卡牌",
		"mycards.create_new": "新建卡牌",
		"mycards.edit": "编辑",
		"mycards.delete": "删除",
		"mycards.skill_fallback": "技能 %d",
		# CardEditor
		"editor.title": "卡牌编辑器",
		"editor.card_art": "卡面:",
		"editor.none": "（无）",
		"editor.browse": "浏览...",
		"editor.name": "名称:",
		"editor.cost": "费用:",
		"editor.hp": "生命:",
		"editor.atk": "攻击:",
		"editor.gender": "性别:",
		"editor.gender_male": "男性",
		"editor.gender_female": "女性",
		"editor.gender_nonhuman": "非人类",
		"editor.skill_1": "技能 1:",
		"editor.skill_2": "技能 2:",
		"editor.edit_skill_1": "编辑技能 1",
		"editor.edit_skill_2": "编辑技能 2",
		"editor.save_card": "保存卡牌",
		"editor.update_card": "更新卡牌",
		"editor.empty": "（空）",
		"editor.no_fx": "（无效果）",
		"editor.unnamed": "未命名",
		"editor.copy_failed": "（复制失败）",
		"editor.select_art": "选择卡面",
		# SkillEditor
		"skill_editor.title": "编辑技能 %d",
		"skill_editor.name": "技能名称:",
		"skill_editor.name_placeholder": "例如 电磁炮",
		"skill_editor.trigger": "触发:",
		"skill_editor.probability": "概率 %:",
		"skill_editor.effects": "效果:",
		"skill_editor.add_effect": "+ 添加效果",
		"skill_editor.edit": "编辑",
		"skill_editor.target": "目标:",
		"skill_editor.effect": "效果:",
		"skill_editor.value": "数值:",
		"skill_editor.value_mode": "数值模式:",
		"skill_editor.value_mode_fixed": "固定",
		"skill_editor.value_mode_random": "随机范围",
		"skill_editor.value_mode_var": "变量",
		"skill_editor.value_min": "最小:",
		"skill_editor.value_max": "最大:",
		"skill_editor.value_var": "变量:",
		"skill_editor.value_offset": "偏移:",
		"skill_editor.effect_prob": "效果概率 %:",
		"skill_editor.max_targets": "最大目标数 (0=全部):",
		"skill_editor.duration": "持续:",
		"skill_editor.ok": "确定",
		"skill_editor.cancel": "取消",
		"skill_editor.save": "保存技能",
		# Skill tooltip section labels
		"skill.no_effects": "（无效果）",
		"skill.no_name": "（未命名）",
		"skill.chance": "（%d%% 概率）",
	},
	"en": {
		"menu.start": "Start",
		"menu.resume": "Resume Battle",
		"menu.reconnecting": "Reconnecting...",
		"menu.reconnect_failed": "Reconnect failed - retry",
		"menu.card_editor": "Card Editor",
		"menu.my_cards": "My Cards",
		"menu.online": "Online Battle",
		"menu.language": "Language",
		"menu.language_prompt": "Language...",
		"mp.title": "Multiplayer",
		"mp.connect_server": "Connect to Server",
		"mp.direct": "Direct Connect (P2P)",
		"common.back": "Back",
		"lobby.title": "Online Battle",
		"lobby.server": "Server:",
		"lobby.room_code": "Room Code:",
		"lobby.room_placeholder": "e.g. 1234",
		"lobby.create": "Create Room",
		"lobby.join": "Join Room",
		"lobby.check_server": "Check Server",
		"lobby.host": "Host Game",
		"lobby.ip": "IP Address:",
		"lobby.enter_room_first": "Enter a room code first",
		"lobby.invalid_code": "Room code must be 1-16 letters/digits",
		"lobby.connecting_lobby": "Connecting to lobby...",
		"lobby.failed_connect_lobby": "Failed to connect to lobby (err=%d)",
		"lobby.creating_room": "Creating room...",
		"lobby.joining_room": "Joining room...",
		"lobby.checking_status": "Checking server status...",
		"lobby.could_not_reach": "Could not reach server. Check the IP and that the server is running.",
		"lobby.could_not_reach_port": "Could not reach the game room port. Check server firewall.",
		"lobby.lost_game_room": "Lost connection to game room.",
		"lobby.room_created": "Room %s created! Select cards while waiting...",
		"lobby.room_taken": "Room '%s' is taken. Try another code.",
		"lobby.server_rejected_code": "Server rejected the room code.",
		"lobby.server_full": "Server is full (no free rooms). Try later.",
		"lobby.failed_join_room": "Failed to join game room (err=%d)",
		"lobby.unknown_response": "Unknown lobby response: %s",
		"lobby.joined_room": "Joined room %s. Select cards...",
		"lobby.room_not_found": "Room '%s' not found.",
		"lobby.room_full": "Room '%s' is full.",
		"lobby.connecting_server": "Connecting to server...",
		"lobby.server_disconnected": "Server disconnected (err=%d)",
		"lobby.server_status": "Server connected | Rooms: %d | Ports: %d-%d",
		"lobby.opponent_connected": "Opponent connected!",
		"lobby.opponent_joined_pick": "Room %s — opponent connected, select cards and press Start",
		"lobby.hosting": "Hosting...",
		"lobby.failed_host": "Failed to host! (err=%d)",
		"lobby.joining": "Joining %s...",
		"lobby.failed_join": "Failed to join! (err=%d)",
		"lobby.could_not_connect": "Could not connect. Check the IP, port, and host firewall.",
		"direct.title": "Direct Connect",
		"direct.join_by_ip": "Join by IP:",
		"direct.join_game": "Join Game",
		"wait.exit": "Exit to Title",
		"wait.create_card": "Create Card",
		"wait.select_start": "Select cards and press Start",
		"wait.opponent_pick": "Opponent connected. Select cards and press Start",
		"wait.select": "Select",
		"wait.start_game": "Start Game",
		"wait.waiting_opponent": "Waiting for opponent...",
		"wait.receiving_arts": "Receiving opponent art %d/%d...",
		"wait.transfer_arts": "Syncing art: receiving %d/%d, upload confirmed %d/%d...",
		"wait.no_arts": "Opponent has no custom art, getting ready...",
		"wait.waiting_ready": "Waiting for opponent to be ready...",
		"wait.arts_slow": "Art transfer is slow (%d/%d), you can enter now",
		"wait.enter_game": "Enter Game",
		"battle.draw_pile": "Draw Pile",
		"battle.discard_zone": "Discard",
		"battle.discard_pile": "Discard Pile",
		"battle.debug_state": "Debug State",
		"battle.deck": "Deck: %d",
		"battle.discard": "Discard: %d",
		"battle.enemy_info": "Enemy Info",
		"battle.my_info": "My Info",
		"battle.switching": "Switching...",
		"battle.waiting": "Waiting...",
		"battle.reconnecting": "Opponent disconnected - waiting for reconnect...",
		"battle.draw_pile_title": "Draw Pile (%d cards)",
		"battle.discard_pile_title": "Discard Pile (%d cards)",
		"battle.close": "Close",
		"battle.choose_keep": "Choose cards to keep",
		"battle.hand_remaining": "Hand slots remaining: %d. Choose up to %d cards.",
		"battle.confirm": "Confirm",
		"battle.end_turn": "End Turn",
		"battle.status_line": "%s | Elixir: %d/%d | HP: %d | Hand: %d/%d | Turn %d",
		"battle.view_turn": "P%d Turn",
		"battle.viewing": "Viewing P%d %s",
		"battle.you": "You",
		"battle.enemy": "Enemy",
		"tip.no_attack_turn1": "No attacking on turn 1",
		"tip.no_enemy_skill_turn1": "Can't target enemies with skills on turn 1",
		"tip.taunt_first": "Attack the Taunt minion first",
		"tip.taunt_skill_first": "Target the Taunt minion first",
		"tip.kill_mana": "Enemy minion killed, Elixir +1",
		"tip.discard_mana": "Card discarded, Elixir +1",
		"tip.hand_full": "Hand is full (max %d cards)",
		"tip.deck_reshuffle": "Deck empty, discard pile shuffled in",
		"help.button": "How to Play",
		"help.title": "How to Play",
		"help.close": "Close",
		"help.body": "Elixir (Cost)\n· Summoning a card costs Elixir equal to its cost.\n· Elixir refills 2 at the start of each turn.\n· Kill an enemy minion to gain Elixir +1.\n· Drag a card from hand or board to the discard zone for Elixir +1.\n\nTurn Flow\n· On turn 1 neither side may attack or affect enemy cards with skills/effects.\n· Click a minion to attack, then click an enemy target to confirm.\n· Each minion acts once per turn (attack or active skill).\n· Press End Turn to pass to your opponent.\n\nCombat Rules\n· If the enemy has a Taunt minion, you must attack/target it first.\n· When the opponent's board is empty, your minions deals damage to the player automatically and directly at the end of your turn.\n· Hand size is capped at %d cards.\n· When the deck runs out, the discard pile is shuffled back in.\n\nSkill Triggers\n· On Summon / Activate / On Attack / On Damaged / On Death.\n· Active skills work once per turn. Silenced minions can't attack or cast.",
		"card.cost": "C %d",
		"card.cost_charmed": "C 0",
		"card.hp": "HP %d/%d",
		"card.hp_temp": "HP %d/%d +%d",
		"card.atk": "ATK %d",
		"card.atk_bonus": "ATK %d (+%d)",
		"card.silenced": "[SILENCED]",
		"card.basic_attack": "Basic Attack\nDeal ATK damage to target",
		"card.buff_tooltip": "%s: %d (%d turns left)",
		"mycards.title": "My Cards",
		"mycards.create_new": "Create New",
		"mycards.edit": "Edit",
		"mycards.delete": "Delete",
		"mycards.skill_fallback": "Skill %d",
		"editor.title": "Card Editor",
		"editor.card_art": "Card Art:",
		"editor.none": "(none)",
		"editor.browse": "Browse...",
		"editor.name": "Name:",
		"editor.cost": "Cost:",
		"editor.hp": "HP:",
		"editor.atk": "ATK:",
		"editor.gender": "Gender:",
		"editor.gender_male": "Male",
		"editor.gender_female": "Female",
		"editor.gender_nonhuman": "Nonhuman",
		"editor.skill_1": "Skill 1:",
		"editor.skill_2": "Skill 2:",
		"editor.edit_skill_1": "Edit Skill 1",
		"editor.edit_skill_2": "Edit Skill 2",
		"editor.save_card": "Save Card",
		"editor.update_card": "Update Card",
		"editor.empty": "(empty)",
		"editor.no_fx": "(no fx)",
		"editor.unnamed": "Unnamed",
		"editor.copy_failed": "(copy failed)",
		"editor.select_art": "Select Card Art",
		"skill_editor.title": "Edit Skill %d",
		"skill_editor.name": "Skill Name:",
		"skill_editor.name_placeholder": "e.g. Railgun",
		"skill_editor.trigger": "Trigger:",
		"skill_editor.probability": "Probability %:",
		"skill_editor.effects": "Effects:",
		"skill_editor.add_effect": "+ Add Effect",
		"skill_editor.edit": "Edit",
		"skill_editor.target": "Target:",
		"skill_editor.effect": "Effect:",
		"skill_editor.value": "Val:",
		"skill_editor.value_mode": "Value Mode:",
		"skill_editor.value_mode_fixed": "Fixed",
		"skill_editor.value_mode_random": "Random Range",
		"skill_editor.value_mode_var": "Variable",
		"skill_editor.value_min": "Min:",
		"skill_editor.value_max": "Max:",
		"skill_editor.value_var": "Variable:",
		"skill_editor.value_offset": "Offset:",
		"skill_editor.effect_prob": "Effect Prob %:",
		"skill_editor.max_targets": "Max Targets (0=all):",
		"skill_editor.duration": "Dur:",
		"skill_editor.ok": "OK",
		"skill_editor.cancel": "Cancel",
		"skill_editor.save": "Save Skill",
		"skill.no_effects": "(no effects)",
		"skill.no_name": "(No Name)",
		"skill.chance": "(%d%% chance)",
	},
}

# ---- Skill term tables (by SkillEngine constant value) ----
# Long forms for tooltips, short forms for compact editor summaries.

const SKILL_TERMS := {
	"zh": {
		"trigger": {
			"on_attack": "攻击时", "on_activate": "主动", "on_summon": "召唤时",
			"on_death": "死亡时", "on_damaged": "受伤时",
		},
		"trigger_short": {
			"on_attack": "攻", "on_activate": "主", "on_summon": "召",
			"on_death": "亡", "on_damaged": "伤",
		},
		"target": {
			"target_single": "目标", "target_sides": "目标+相邻", "self": "自身",
			"self_sides": "自身+相邻", "all_enemies": "全体敌方", "all_allies": "全体友方",
			"target_male": "男性", "target_female": "女性", "target_nonhuman": "非人类",
		},
		"target_short": {
			"target_single": "目标", "target_sides": "目+邻", "self": "自身",
			"self_sides": "自+邻", "all_enemies": "全敌", "all_allies": "全友",
			"target_male": "男", "target_female": "女", "target_nonhuman": "非人",
		},
		"effect": {
			"damage": "伤害", "heal": "治疗", "add_buff": "增益",
			"draw_cards": "抽牌", "shield": "护盾", "charm": "魅惑",
		},
		"effect_value": {
			"damage": "%s 伤害", "heal": "%s 治疗", "add_buff": "增益",
			"draw_cards": "抽 %s 张", "shield": "%s 护盾", "charm": "魅惑",
		},
		"buff": {
			"atk_boost": "攻击提升", "regen": "回血", "mana_refund": "圣水返还",
			"thorns": "反伤", "damage_reduction": "减伤", "taunt": "嘲讽",
			"silence": "沉默", "misfortune": "霉运",
		},
		"buff_short": {
			"atk_boost": "攻击提升", "regen": "回血", "mana_refund": "圣水返还",
			"thorns": "反伤", "damage_reduction": "减伤", "taunt": "嘲讽",
			"silence": "沉默", "misfortune": "霉运",
		},
		"value_var": {
			"field_total": "场上卡牌总数", "field_ally": "己方卡牌数", "field_enemy": "敌方卡牌数",
			"empty_ally": "己方空槽位数", "empty_enemy": "敌方空槽位数",
			"hand_count": "己方手牌数", "mana_current": "当前圣水",
		},
	},
	"en": {
		"trigger": {
			"on_attack": "Attack", "on_activate": "Activate", "on_summon": "Summon",
			"on_death": "Death", "on_damaged": "Damaged",
		},
		"trigger_short": {
			"on_attack": "Atk", "on_activate": "Act", "on_summon": "Sum",
			"on_death": "Dth", "on_damaged": "Dmg",
		},
		"target": {
			"target_single": "Target", "target_sides": "Tgt+Sides", "self": "Self",
			"self_sides": "Self+Sides", "all_enemies": "All Enemies", "all_allies": "All Allies",
			"target_male": "Male", "target_female": "Female", "target_nonhuman": "Non-Human",
		},
		"target_short": {
			"target_single": "Tgt", "target_sides": "T+S", "self": "Slf",
			"self_sides": "S+S", "all_enemies": "AllE", "all_allies": "AllA",
			"target_male": "Male", "target_female": "Fem", "target_nonhuman": "NonH",
		},
		"effect": {
			"damage": "Damage", "heal": "Heal", "add_buff": "Buff",
			"draw_cards": "Draw Cards", "shield": "Shield", "charm": "Charm",
		},
		"effect_value": {
			"damage": "%s damage", "heal": "%s healing", "add_buff": "buff",
			"draw_cards": "draw %s card(s)", "shield": "%s shield", "charm": "Charm",
		},
		"buff": {
			"atk_boost": "Attack Boost", "regen": "Regeneration", "mana_refund": "Elixir Refund",
			"thorns": "Thorns", "damage_reduction": "Damage Reduction", "taunt": "Taunt",
			"silence": "Silence", "misfortune": "Misfortune",
		},
		"buff_short": {
			"atk_boost": "Attack Boost", "regen": "Regeneration", "mana_refund": "Elixir Refund",
			"thorns": "Thorns", "damage_reduction": "Damage Reduction", "taunt": "Taunt",
			"silence": "Silence", "misfortune": "Misfortune",
		},
		"value_var": {
			"field_total": "total cards on field", "field_ally": "ally cards", "field_enemy": "enemy cards",
			"empty_ally": "ally empty slots", "empty_enemy": "enemy empty slots",
			"hand_count": "cards in hand", "mana_current": "current elixir",
		},
	},
}


func _ready() -> void:
	_load_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved: String = str(cfg.get_value("locale", "language", DEFAULT_LANGUAGE))
		if STRINGS.has(saved):
			language = saved


func set_language(lang: String) -> void:
	if not STRINGS.has(lang):
		return
	language = lang
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep any other sections
	cfg.set_value("locale", "language", language)
	cfg.save(SETTINGS_PATH)
	language_changed.emit()


# Translate a UI string key. Optional args are applied with % formatting.
func t(key: String, args := []) -> String:
	var table: Dictionary = STRINGS.get(language, {})
	var text: String = table.get(key, "")
	if text == "":
		text = STRINGS["en"].get(key, key)
	if args.is_empty():
		return text
	return text % args


# Look up a skill term (trigger/target/effect/buff, optionally *_short) by its
# SkillEngine constant value. Falls back to English then the raw value.
func term(category: String, value: String) -> String:
	var lang_tbl: Dictionary = SKILL_TERMS.get(language, {})
	var cat_tbl: Dictionary = lang_tbl.get(category, {})
	if cat_tbl.has(value):
		return cat_tbl[value]
	var en_cat: Dictionary = SKILL_TERMS["en"].get(category, {})
	return en_cat.get(value, value)
