class_name ActionPlanningChallenges
extends RefCounted

const IDS := ["action_reserve", "action_finish"]


static func _t(zh: String, en: String) -> String:
	return zh if Locale.language == "zh" else en


static func title(id: String) -> String:
	return _t("预算接力", "Budget relay") if id == "action_reserve" else _t("收尾顺序", "Closing order")


static func objective(id: String) -> String:
	if id == "action_reserve":
		return _t("本回合击败 7 血守卫。你已行动 4 次，剩 3 行动力、1 圣水；先规划整备官的技能与重击手的攻击。", "Defeat the 7-HP Guard this turn. After 4 actions, you have 3 AP and 1 Elixir. Plan the Officer's skill and Striker's attack.")
	return _t("结束本回合，并将敌方本体从 6 血压到 1 血。你已行动 4 次，剩 2 行动力、4 圣水，其中 2 点临时圣水会到期。", "End this turn with the enemy HQ at 1 HP. After 4 actions, you have 2 AP and 4 Elixir; 2 Elixir expires at turn end.")


static func hint(id: String) -> String:
	if id == "action_reserve":
		return _t("下一行动要 4 点：3 行动力加 1 圣水。先让整备官强化重击手并补充 6 圣水；后续攻击要 5 圣水。不要先花掉启动费用。", "The next action costs 4: 3 AP plus 1 Elixir. Have the Officer buff the Striker and gain 6 Elixir; the attack then costs 5 Elixir. Preserve the setup payment.")
	return _t("悬停或在触屏上长按「结束回合」查看预览：自动攻击从左到右。可用收整将左侧策应兵收回手牌，也可将它拖到弃牌区，再结束。", "Hover over End Turn or hold it on a touchscreen: automatic attacks go left to right. Return the left Support to hand with Regroup, or drag it to Discard, then end.")


static func lesson(id: String) -> String:
	if id == "action_reserve":
		return _t("行动费用先支付，技能收益随后到账；增加资源的技能也占一次行动，要同时预算下一步的费用。", "Pay action costs before skill rewards arrive. Resource skills also use an action; budget for the following move.")
	return _t("临时圣水先到期，自动攻击再支付递增费用。撤下单位不会重算本回合行动力；预览可帮助保留高伤害单位的行动。", "Temporary Elixir expires before automatic attacks pay escalating costs. Removing a unit does not refill this turn's AP; use the preview to preserve the stronger attack.")


static func configure(game: RefCounted, id: String) -> void:
	# Training uses the confirmed defaults, without changing player preferences.
	game.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	for field in [game.player_field, game.player2_field]:
		field.max_mana = 10
		field.max_player_hp = 30
		field.player_hp = 30
	game.player_field.slots[1] = CardData.new(_t("重击手", "Striker"), 3, 6, 4 if id == "action_reserve" else 5)
	game.player_field.slots[1].card_id = "training-" + id + "-striker"
	if id == "action_reserve":
		game.player_field.slots[0] = CardData.new(_t("整备官", "Officer"), 2, 5, 0, [{"skill_name": _t("接力整备", "Relay supply"), "trigger": "on_activate", "effects": [
			{"effect": "gain_mana", "value": 6, "target": "self", "target_side": "ally"},
			{"effect": "gain_attack", "value": 3, "target": "target_single", "target_side": "ally"},
		]}])
		game.player2_field.slots[0] = CardData.new(_t("重甲守卫", "Armored Guard"), 4, 7, 1)
		game.player_hand.append(PracticeChallenges._spell(_t("仓促射击", "Hasty shot"), "damage", 1, "target_single", "enemy", 1))
	else:
		game.player_field.slots[2] = CardData.new(_t("已行动哨兵", "Spent Sentry"), 1, 4, 0)
		game.player_field.slots[2].has_acted = true
		game.player_field.slots[2].has_attacked = true
		game.player_field.slots[0] = CardData.new(_t("策应兵", "Support"), 1, 4, 1)
		game.player2_field.player_hp = 6
		game.player_field.temp_mana = 2
		game.player_hand.append(PracticeChallenges._spell(_t("收整", "Regroup"), SkillRegistry.EFFECT_CHARM, 0, "target_single", "ally", 1))
	game.player_field.current_mana = 1 if id == "action_reserve" else 2


static func prepare_budget(game: RefCounted) -> void:
	# A late-turn position after costs 0+1+2+3, from the default 8/9-AP budget.
	game.player_field.actions_taken = 4
	game.player_field.action_points -= 6


static func succeeded(game: RefCounted, id: String) -> bool:
	if id == "action_reserve":
		return game.player2_field.get_alive_count() == 0
	return game.player2_field.player_hp == 1 and (game.current_player == 2 or not game.is_player_turn)


static func stage(game: RefCounted, id: String) -> String:
	if id == "action_finish":
		return _finish_stage(game)
	var striker: CardData = game.player_field.slots[1]
	var guard: CardData = game.player2_field.slots[0]
	if striker == null or striker.has_acted or guard == null or not game.can_pay_action():
		return "failed"
	if striker.effective_atk() >= guard.hp:
		return "payoff"
	var officer: CardData = game.player_field.slots[0]
	if officer == null or officer.has_acted:
		return "failed"
	# Account for payment before the skill's resource gain, then the next cost.
	var quote: Dictionary = game.next_action_payment()
	var after_mana: int = mini(game.player_field.max_mana, game.player_field.current_mana - int(quote.mana) + 6)
	var next_cost: int = game.player_field.actions_taken + 1
	return "setup" if after_mana >= next_cost and striker.effective_atk() + 3 >= guard.hp else "failed"


static func _finish_stage(game: RefCounted) -> String:
	var striker: CardData
	var in_hand := false
	var refundable := 0
	for card in game.player_field.slots:
		if card == null: continue
		if card.card_id == "training-action_finish-striker":
			striker = card
		else: refundable += 1
	for card in game.player_hand:
		if card.card_id == "training-action_finish-striker":
			striker = card
			in_hand = true
		else: refundable += 1
	if striker == null or striker.has_acted:
		return "failed"
	# Free discard is a legal recovery; do not declare failure while it can
	# fund the remaining attack. Regroup may also return the Striker to hand.
	var available: int = mini(game.player_field.max_mana, game.player_field.current_mana + refundable)
	if in_hand: available -= striker.cost
	if available < int(game.next_action_payment().mana): return "failed"
	return "payoff" if game.preview_end_turn_attacks().total_damage == 5 else "setup"


static func progress(game: RefCounted, id: String) -> String:
	var phase := PracticeChallenges.stage(game, id)
	var text: String
	if phase == "success": text = _t("进度 2/2：目标完成。", "Progress 2/2: objective complete.")
	elif phase == "failed": text = _t("当前资源或行动已不足以完成目标。", "The remaining resources or actions cannot complete the objective.")
	elif phase == "setup": text = _t("进度 0/2：先规划资源与行动顺序。", "Progress 0/2: plan resources and action order.")
	else: text = _t("进度 1/2：准备完成，执行收尾行动。", "Progress 1/2: setup is ready; complete the final move.")
	if game.current_player == 1 and game.is_player_turn and phase not in ["success", "failed"]:
		var quote: Dictionary = game.next_action_payment()
		text += "\n" + _t("下一行动：%d 行动力＋%d 圣水。", "Next action: %d AP + %d Elixir.") % [quote.points, quote.mana]
	return text


static func failure_reason(id: String) -> String:
	if id == "action_reserve":
		return _t("启动技能前花掉了圣水，或重击手过早行动。技能不能用尚未到账的收益支付自身费用。", "Elixir was spent before setup, or the Striker acted too early. A skill cannot pay its own cost with rewards that have not arrived.")
	return _t("临时圣水到期后，左侧低伤害行动占用了预算，或重击手已被弃置。重试并用预览保留高伤害单位的行动。", "After temporary Elixir expired, the left low-damage attack used the budget, or the Striker was discarded. Retry and preserve the stronger attack using the preview.")
