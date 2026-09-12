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


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
