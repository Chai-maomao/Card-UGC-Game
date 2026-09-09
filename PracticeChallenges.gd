class_name PracticeChallenges
extends RefCounted

const IDS := ["resource", "combination"]


static func title(id: String) -> String:
	if id == "resource": return "蓄势登场 / Build resources"
	return "协同突破 / Combine effects"


static func objective(id: String) -> String:
	if id == "resource":
		return "本回合内召唤巨人。先获得圣水，再打出高费用卡牌。" if Locale.language == "zh" else "Summon the giant this turn. Gain mana before playing the expensive unit."
	return "本回合内消灭守卫。先强化友军，再攻击。" if Locale.language == "zh" else "Defeat the guard this turn. Enhance an ally before attacking."


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
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
