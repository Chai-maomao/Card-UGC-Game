class_name PracticeChallenges
extends RefCounted

const IDS := ["resource", "combination"]


static func title(id: String) -> String:
	if id == "resource": return "资源连锁：蓄势登场 / Resource chain"
	return "协同突破 / Combine effects"


static func objective(id: String) -> String:
	if id == "resource":
		return "本回合召唤 5 费巨人。你只有 2 点圣水，需要规划三张手牌的使用顺序。" if Locale.language == "zh" else "Summon the 5-cost Giant this turn. You have 2 mana and must plan the order of three cards."
	return "本回合内消灭守卫。先强化友军，再攻击。" if Locale.language == "zh" else "Defeat the guard this turn. Enhance an ally before attacking."


static func hint(id: String) -> String:
	if id == "resource":
		return "提示：卡牌效果会立即结算。先找出能增加圣水的牌，再判断剩余圣水是否足够召唤巨人。" if Locale.language == "zh" else "Hint: card effects resolve immediately. Find the mana-generating card, then check whether enough mana remains for the Giant."
	return "提示：先锋当前攻击不足以击败守卫；先让增益结算，再发起攻击。" if Locale.language == "zh" else "Hint: the Vanguard cannot defeat the Guard yet. Resolve the buff before attacking."


static func lesson(id: String) -> String:
	if id == "resource":
		return "要点：临时圣水应在本回合使用；先花掉基础圣水会让后续连锁断裂。" if Locale.language == "zh" else "Lesson: temporary mana should be used this turn; spending the base mana first breaks the sequence."
	return "要点：增益先结算，随后攻击才能把提升的数值转化为有效交换。" if Locale.language == "zh" else "Lesson: resolve the buff first, then turn the increased stat into a favorable attack."


static func configure(game: RefCounted, id: String) -> void:
	game.current_player = 1
	game.is_player_turn = true
	game.turn_number = 2
	game.player_field.slots = [null, null, null, null, null]
	game.player2_field.slots = [null, null, null, null, null]
	game.player_field.current_mana = 2
	game.player_field.temp_mana = 0
	game.player_hand.clear()
	game.player2_hand.clear()
	game.shared_deck.clear()
	game.shared_discard.clear()
	game.game_rng.seed = 3109
	if id == "resource":
		game.player_hand.append(_spell("蓄势", "gain_mana", 3, "self", "ally", 0))
		game.player_hand.append(CardData.new("巨人", 5, 8, 5))
		game.player_hand.append(CardData.new("斥候", 2, 3, 2))
		game.player2_field.slots[0] = CardData.new("守卫", 2, 5, 1)
	else:
		game.player_hand.append(_spell("鼓舞", "gain_attack", 3, "target_single", "ally", 1))
		game.player_field.slots[0] = CardData.new("先锋", 2, 5, 2)
		game.player2_field.slots[0] = CardData.new("守卫", 3, 5, 1)


static func _spell(name: String, effect: String, value: int, target: String, side: String, cost: int) -> CardData:
	var card := CardData.new(name, cost, 1, 0, [{"skill_name": name, "trigger": "on_cast", "effects": [{"effect": effect, "value": value, "target": target, "target_side": side}]}])
	card.card_type = "spell"
	return card


static func succeeded(game: RefCounted, id: String) -> bool:
	if game.turn_number != 2: return false
	if id == "resource":
		for card in game.player_field.slots:
			if card != null and card.card_name == "巨人": return true
		return false
	return game.player2_field.slots[0] == null or not game.player2_field.slots[0].is_alive()


static func stage(game: RefCounted, id: String) -> String:
	if succeeded(game, id):
		return "success"
	if game.turn_number != 2:
		return "failed"
	if id == "resource":
		var giant: CardData = _hand_card(game.player_hand, "巨人")
		if giant == null:
			return "failed"
		var available: int = int(game.player_field.get_total_mana())
		if _hand_card(game.player_hand, "蓄势") != null:
			available += 3
		if available < giant.cost:
			return "failed"
		return "payoff" if _hand_card(game.player_hand, "蓄势") == null else "setup"
	var ally: CardData = game.player_field.slots[0]
	if ally == null or ally.has_acted:
		return "failed"
	return "payoff" if ally.effective_atk() >= 5 else "setup"


static func failed(game: RefCounted, id: String) -> bool:
	return stage(game, id) == "failed"


static func progress(game: RefCounted, id: String) -> String:
	var current_stage := stage(game, id)
	if current_stage == "success":
		return "进度 2/2：目标完成。" if Locale.language == "zh" else "Progress 2/2: objective complete."
	if current_stage == "failed":
		return "当前顺序已无法在本回合完成目标。" if Locale.language == "zh" else "The objective can no longer be completed this turn."
	if current_stage == "payoff":
		if id == "resource":
			return "进度 1/2：圣水已经补足，现在召唤巨人。" if Locale.language == "zh" else "Progress 1/2: mana is ready; summon the Giant."
		return "进度 1/2：强化已完成，现在攻击守卫。" if Locale.language == "zh" else "Progress 1/2: the buff is ready; attack the Guard."
	if id == "resource":
		return "进度 0/2：先找出能启动资源连锁的手牌。" if Locale.language == "zh" else "Progress 0/2: find the card that starts the resource chain."
	return "进度 0/2：先提升先锋的攻击力。" if Locale.language == "zh" else "Progress 0/2: increase the Vanguard's attack first."


static func failure_reason(game: RefCounted, id: String) -> String:
	if id == "resource":
		if game.turn_number != 2:
			return "本回合已经结束，巨人仍未登场。" if Locale.language == "zh" else "The turn ended before the Giant entered play."
		if _hand_card(game.player_hand, "巨人") == null:
			return "巨人已经离开手牌，目标无法完成。" if Locale.language == "zh" else "The Giant has left your hand, so the objective cannot be completed."
		return "你先消耗了基础圣水，剩余资源即使加上“蓄势”也不足 5 点。" if Locale.language == "zh" else "Base mana was spent too early; even Momentum can no longer reach 5 mana."
	var ally: CardData = game.player_field.slots[0]
	if ally != null and ally.has_acted:
		return "先锋在获得强化前已经行动，本回合无法再次攻击。" if Locale.language == "zh" else "The Vanguard acted before receiving the buff and cannot attack again this turn."
	return "本回合已经结束，守卫仍在场上。" if Locale.language == "zh" else "The turn ended while the Guard was still in play."


static func _hand_card(hand: Array, card_name: String) -> CardData:
	for card in hand:
		if card != null and card.card_name == card_name:
			return card
	return null


static func show_picker(parent: Node) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "组合挑战 / Skill challenges"
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 450
	dialog.add_child(box)
	for id in IDS:
		var button := Button.new()
		button.text = title(id)
		UITheme.apply_button(button, "primary")
		button.pressed.connect(func():
			NetworkManager.close_connection()
			PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
			PlayerData.practice_challenge_id = id
			parent.get_tree().change_scene_to_file("res://Main.tscn")
		)
		box.add_child(button)
		var label := Label.new()
		label.text = objective(id)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	parent.add_child(dialog)
	dialog.get_ok_button().text = "关闭" if Locale.language == "zh" else "Close"
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
