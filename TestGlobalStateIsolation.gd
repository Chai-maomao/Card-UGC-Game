extends Node

var failures: Array[String] = []


func _ready() -> void:
	var original := PlayerData.battle_preparation_snapshot()
	var original_playtest := PlayerData.card_playtest_context.duplicate(true)
	var a := CardData.new("A", 1, 1, 1, [])
	var b := CardData.new("B", 1, 1, 1, [])
	PlayerData.card_playtest_context = {"draft": {"name": "old"}}
	PlayerData.configure_practice_battle([a], [b], "hard")
	_assert(PlayerData.battle_mode == "practice" and PlayerData.practice_ai_difficulty == "hard", "practice setup not applied")
	_assert(PlayerData.card_playtest_context.is_empty(), "ordinary practice inherited editor playtest state")
	PlayerData.return_to_waiting_room = true
	PlayerData.configure_online_battle([b], "res://Lobby.tscn")
	_assert(PlayerData.battle_mode == "online" and PlayerData.opponent_battle_deck.is_empty(), "online setup inherited practice opponent")
	_assert(PlayerData.pending_hotseat_p1_deck.is_empty() and not PlayerData.return_to_waiting_room, "online setup inherited transient flags")
	PlayerData.set_online_opponent_deck([a])
	PlayerData.prepare_hotseat_selection()
	_assert(PlayerData.battle_select_mode == "hotseat_p1", "hotseat selection phase is wrong")
	_assert(PlayerData.battle_deck.is_empty() and PlayerData.opponent_battle_deck.is_empty(), "hotseat selection inherited online decks")
	PlayerData.begin_hotseat_battle_selection([a])
	PlayerData.configure_hotseat_battle(PlayerData.pending_hotseat_p1_deck, [b])
	_assert(PlayerData.battle_mode == "hotseat" and PlayerData.battle_deck.size() == 1 and PlayerData.opponent_battle_deck.size() == 1, "hotseat setup failed")
	PlayerData.clear_battle_preparation()
	_assert(PlayerData.battle_deck.is_empty() and PlayerData.opponent_battle_deck.is_empty() and PlayerData.card_playtest_context.is_empty(), "battle cleanup left cross-scene state")
	PlayerData._apply_battle_preparation(original)
	PlayerData.card_playtest_context = original_playtest
	if failures.is_empty():
		print("TEST_GLOBAL_STATE_ISOLATION_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_GLOBAL_STATE_ISOLATION_FAILED: %s" % failure)
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
