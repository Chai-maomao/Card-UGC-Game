extends Node

var failures: Array[String] = []


func _ready() -> void:
	var backup := PlayerData.battle_preparation_snapshot()
	var old_challenge_id := PlayerData.practice_challenge_id
	var expected_hands := {
		"resource": ["蓄势", "巨人", "斥候"],
		"combination": ["鼓舞"],
		"taunt": [],
		"cleanse": ["净化术", "治疗术"],
		"dispel": ["破法", "净化术"],
		"execute": ["精准削弱", "仓促射击"],
		"action_reserve": ["仓促射击"],
		"action_finish": ["收整"],
		"parasite": ["共生虫", "新兵"],
	}
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	for index in range(PracticeChallenges.IDS.size()):
		var id: String = PracticeChallenges.IDS[index]
		PlayerData.practice_challenge_id = id
		var battle := preload("res://Main.tscn").instantiate()
		add_child(battle)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_card_names(battle.game.player_hand) == expected_hands[id], "challenge game hand differs after startup: " + id)
		_check(_visible_hand_names(battle) == expected_hands[id], "challenge UI hand differs after startup: " + id)
		_check(PracticeChallenges.stage(battle.game, id) == "setup", "challenge state was replaced during startup: " + id)
		var controller := _challenge_controller(battle)
		_check(controller != null and controller.popup_layer != null, "challenge must use the in-game popup: " + id)
		if controller != null:
			_check(not _tree_contains_window(controller.popup_layer), "challenge popup must not use a native window: " + id)
			await _check_retry_restores_hand(battle, controller, expected_hands[id], id)
		if index == 0 and controller != null:
			battle.game.player_field.slots[0] = CardData.new("巨人", 5, 8, 5)
			controller.finished = true
			controller._show()
			_check(controller.popup_layer.find_child("NextChallengeButton", true, false) != null, "completed challenge needs a next button")
			_check(controller.popup_layer.find_child("ChallengePickerButton", true, false) != null, "completed challenge needs a picker button")
		if index == 0:
			# Reproduce a queued scene exit after the next selection is already set.
			PlayerData.practice_challenge_id = PracticeChallenges.IDS[index + 1]
			battle.queue_free()
			await get_tree().process_frame
			_check(PlayerData.practice_challenge_id == PracticeChallenges.IDS[index + 1], "old challenge cleared the new selection")
		else:
			battle.queue_free()
			await get_tree().process_frame
	PlayerData._apply_battle_preparation(backup)
	PlayerData.practice_challenge_id = old_challenge_id
	if failures.is_empty():
		print("TEST_CHALLENGE_STARTUP_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_CHALLENGE_STARTUP_FAILED: " + failure)
		get_tree().quit(1)


func _card_names(cards: Array) -> Array:
	var names: Array = []
	for card in cards:
		names.append(card.card_name)
	return names


func _visible_hand_names(battle: Node) -> Array:
	var names: Array = []
	for card_ui in battle.hand_container.get_children():
		var card: CardData = card_ui.current_card_data
		if card != null:
			names.append(card.card_name)
	return names


func _challenge_controller(battle: Node) -> ChallengeController:
	for child in battle.get_children():
		if child is ChallengeController:
			return child
	return null


func _check_retry_restores_hand(battle: Node, controller: ChallengeController, expected: Array, id: String) -> void:
	var stale_nodes: Array = battle.hand_container.get_children()
	if stale_nodes.is_empty():
		var stale_ui = preload("res://CardUI.tscn").instantiate()
		battle.hand_container.add_child(stale_ui)
		stale_ui.set_card(CardData.new("污染手牌", 9, 9, 9))
		stale_nodes.append(stale_ui)
	else:
		for stale in stale_nodes:
			if stale.current_card_data != null:
				stale.current_card_data.card_name = "污染手牌"
	battle.game.player_hand.clear()
	battle.game.player_hand.append(CardData.new("错误手牌", 9, 9, 9))
	controller._reset()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_card_names(battle.game.player_hand) == expected, "retry did not restore challenge hand state: " + id)
	_check(_visible_hand_names(battle) == expected, "retry did not rebuild visible hand: " + id)
	for stale in stale_nodes:
		_check(not is_instance_valid(stale) or stale.get_parent() != battle.hand_container, "retry reused a stale hand card node: " + id)


func _tree_contains_window(root: Node) -> bool:
	if root is Window:
		return true
	for child in root.get_children():
		if _tree_contains_window(child):
			return true
	return false


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
