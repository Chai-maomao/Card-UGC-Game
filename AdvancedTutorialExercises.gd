extends RefCounted

const State = preload("res://GameState.gd")
const Clock = preload("res://BattleActionClock.gd")


static func _t(zh: String, en: String) -> String:
	return zh if Locale.language == "zh" else en


static func _unit(name: String, hp: int = 6, atk: int = 2) -> CardData:
	return CardData.new(name, 0, hp, atk)


static func _skill(name: String, effect: String, value: int, target: String, side: String) -> Dictionary:
	return {"skill_name": name, "trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
		"effects": [{"effect": effect, "value": value, "target": target, "target_side": side}]}


static func setup(game: RefCounted, id: String) -> void:
	game.initialize_fields(PlayerData.DEFAULT_BATTLE_CONFIG)
	game.game_rng.seed = 21
	game.turn_number = 2
	game.current_player = 1
	game.is_player_turn = true
	game.first_switch = false
	var source := _unit(_t("训练单位", "Training unit"), 8 if id == "damage" else 6)
	game.player_field.slots[0] = source
	match id:
		"deployment":
			var recruit := _unit(_t("护盾新兵", "Shield Recruit"))
			recruit.cost = 2
			var shield := _skill(_t("列阵", "Take Position"), SkillEngine.EFFECT_SHIELD, 2, SkillEngine.TARGET_SELF, SkillEngine.TARGET_SIDE_ALLY)
			shield["trigger"] = SkillEngine.TRIGGER_ON_SUMMON
			recruit.skills = [shield]
			game.player_hand = [recruit]
			game.player_field.current_mana = 4
		"triggers":
			var shield := _skill(_t("架起护盾", "Raise shield"), SkillEngine.EFFECT_SHIELD, 2, SkillEngine.TARGET_SELF, SkillEngine.TARGET_SIDE_ALLY)
			shield["probability"] = 0
			shield["max_uses"] = 2
			source.skills = [shield]
		"targets":
			source.skills = [_skill(_t("横扫", "Sweep"), SkillEngine.EFFECT_DAMAGE, 2, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SIDE_ENEMY)]
			game.player2_field.slots[0] = _unit(_t("斥候", "Scout"))
			game.player2_field.slots[2] = _unit(_t("卫兵", "Guard"))
			game.player2_field.slots[3] = _unit(_t("弓手", "Archer"))
		"taunt":
			game.player2_field.slots[0] = _unit(_t("斥候", "Scout"))
			var guard := _unit(_t("卫兵", "Guard"), 6, 0)
			guard.apply_buff(SkillEngine.BUFF_TAUNT, 1, 2, 2)
			game.player2_field.slots[2] = guard
		"damage":
			source.hp = 2
			source.skills = [_skill(_t("吸血", "Lifesteal"), SkillEngine.EFFECT_LIFESTEAL_DAMAGE, 6, SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDE_ENEMY)]
			var guard := _unit(_t("卫兵", "Guard"))
			guard.temp_hp = 1
			guard.apply_buff(SkillEngine.BUFF_DAMAGE_REDUCTION, 50, 2, 2)
			game.player2_field.slots[2] = guard
		"control":
			source.skills = [_skill(_t("净化", "Cleanse"), SkillEngine.EFFECT_CLEANSE, 0, SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDE_ALLY)]
			var guard := _unit(_t("卫兵", "Guard"))
			guard.apply_buff(SkillEngine.BUFF_TAUNT, 1, 2, 1)
			guard.apply_buff(SkillEngine.BUFF_POISON, 2, 2, 2)
			guard.temp_hp = 2
			game.player_field.slots[2] = guard
		"charm":
			source.skills = [_skill(_t("招降", "Recruit"), SkillEngine.EFFECT_CHARM, 0, SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDE_ENEMY)]
			var guard := _unit(_t("卫兵", "Guard"))
			guard.cost = 3
			game.player2_field.slots[2] = guard
		"hand":
			source.skills = [_skill(_t("补给", "Resupply"), SkillEngine.EFFECT_DRAW_CARDS, 1, SkillEngine.TARGET_SELF, SkillEngine.TARGET_SIDE_ALLY)]
			for _index in range(SkillEngine.MAX_HAND_SIZE):
				game.player_hand.append(_unit(_t("预备队", "Reserve")))
			game.shared_deck.append(_unit(_t("援军", "Reinforcement")))
			game.player_field.current_mana = 3
		"discard":
			game.player_hand = [_unit(_t("预备队", "Reserve"))]
			game.player_field.current_mana = 3
		"turn":
			game.player_field.slots[4] = _unit(_t("后卫", "Rear guard"), 6, 4)
		"custom":
			game.player_field.slots[0] = null
	game.reset_action_budget(1)
	game.reset_action_budget(2)
	if id == "triggers":
		game.player_field.actions_taken = 2
		game.player_field.action_points = 1
		game.player_field.current_mana = 3
	elif id == "turn":
		game.player_field.actions_taken = 1
		game.player_field.action_points = 1
		game.player_field.current_mana = 2


static func result(game: RefCounted, id: String, supplemented_damage: int) -> String:
	var source: CardData = game.player_field.slots[0]
	var enemy: Array = game.player2_field.slots
	match id:
		"deployment":
			var recruit: CardData = game.player_field.slots[2]
			return _t("新兵落在高亮位置，花了 2 圣水，还剩 %d。召唤效果自动给了新兵 %d 护盾。", "The recruit landed in the marked slot. It cost 2 Elixir, leaving %d. Its summon effect granted %d shield automatically.") % [game.player_field.current_mana, recruit.temp_hp]
		"taunt":
			return _t("斥候仍有 %d 生命，卫兵剩 %d。敌方有嘲讽时，普攻只能选带嘲讽的单位。", "The Scout still has %d life and the Guard has %d. While an enemy has Taunt, basic attacks must target a unit with Taunt.") % [enemy[0].hp, enemy[2].hp]
		"charm":
			var recruited: CardData = game.player_hand[0]
			return _t("敌方格子空了。卫兵进入你的手牌，本回合费用为 %d。", "The enemy slot is empty. The Guard moved to your hand and costs %d this turn.") % recruited.cost
		"discard":
			return _t("预备队进了弃牌堆，圣水由 3 变为 %d。主动弃牌回 1 圣水，满手溢出和技能弃牌没有这笔返还。", "The Reserve went to the discard pile, raising Elixir from 3 to %d. Manual discard refunds 1 Elixir. Overflow and forced discard do not.") % game.player_field.current_mana
		"triggers":
			return _t("行动力剩 %d，圣水剩 %d。没获得护盾，技能还剩 %d 次。费用在发动判定前已经支付。", "%d action points and %d Elixir remain. No shield appeared, and the skill has %d uses left. The cost was paid before the roll.") % [
				game.player_field.action_points, game.player_field.current_mana, 2 - int(source.skills_used_count.get(0, 0))]
		"targets":
			return _t("卫兵剩 %d 生命，弓手剩 %d，斥候仍有 %d。卫兵左边是空格，横扫没有跳过空格。", "Guard has %d life, Archer %d, and Scout still has %d. Sweep did not skip the empty slot.") % [enemy[2].hp, enemy[3].hp, enemy[0].hp]
		"damage":
			return _t("减伤把 6 点伤害减到 3 点，护盾再挡 1 点。卫兵实际失去 %d 生命，你回复了 %d。", "Damage reduction takes 6 down to 3, then shield absorbs 1. The Guard loses %d life and you restore %d.") % [6 - enemy[2].hp, source.hp - 2]
		"control":
			return _t("卫兵的中毒解除了，嘲讽还在，护盾还剩 %d 点。净化只移除负面状态。", "Poison is gone, Taunt is still active, and %d shield remains. Cleanse removes negative statuses.") % game.player_field.slots[2].temp_hp
		"hand":
			return _t("手牌仍有 %d 张，弃牌堆多了 %d 张，圣水还是 %d。满手时抽到的牌会溢出，只有主动弃牌才会返还圣水。", "You still have %d cards. Discard gained %d, and Elixir stays at %d. Only manual discard refunds Elixir.") % [
				game.player_hand.size(), game.shared_discard.size(), game.player_field.current_mana]
		"turn":
			return _t("关闭补付造成 %d 点本体伤害。同样的局面开启补付会造成 %d 点。左侧先用掉 1 行动力，右侧下一击需要 2 圣水。", "With supplement off, you deal %d player damage. With it on, the same position deals %d. The left unit spends the first point, and the right unit needs 2 Elixir.") % [
				game.player2_field.max_player_hp - game.player2_field.player_hp, supplemented_damage]
	return ""


static func sample_turn(config: Dictionary) -> Dictionary:
	var game := State.new()
	game.quiet = true
	game.initialize_fields(config)
	game.first_switch = false
	game.player2_field.current_mana = 0
	for _index in range(SkillEngine.MAX_HAND_SIZE):
		game.shared_deck.append(_unit(_t("预备队", "Reserve")))
	game.start_new_turn()
	return {"hand": game.player2_hand.size(), "points": game.player2_field.action_points,
		"mana": game.player2_field.current_mana, "hp": game.player2_field.player_hp}


static func rule_preview(config: Dictionary) -> String:
	var result := sample_turn(config)
	var observed := _t("第 2 回合，空场空手起步。获得 %d 圣水，摸到 %d 张牌，有 %d 行动力。本体初始生命为 %d。", "Round two, starting with an empty hand and board. Gain %d Elixir, draw %d cards, and receive %d action points. Starting player life is %d.") % [result.mana, result.hand, result.points, result.hp]
	if Clock.enabled(config):
		return observed + "\n" + _t("首次操作 %d 秒，随后每次 %d 秒。", "First action: %d seconds. Between actions: %d seconds.") % [Clock.seconds(config, true), Clock.seconds(config, false)]
	return observed + "\n" + _t("操作限时已关闭。", "The action timer is off.")
