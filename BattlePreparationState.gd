class_name BattlePreparationState
extends RefCounted


static func empty() -> Dictionary:
	return {
		"mode": "hotseat", "difficulty": "normal",
		"player_deck": [], "opponent_deck": [], "pending_p1": [],
		"select_mode": "practice", "next_scene": "res://Main.tscn", "select_step": 1,
		"return_to_waiting_room": false,
	}


static func practice(player_cards: Array, opponent_cards: Array, difficulty: String) -> Dictionary:
	var state := empty()
	state["mode"] = "practice"
	state["difficulty"] = difficulty if difficulty in ["easy", "normal", "hard"] else "normal"
	state["player_deck"] = player_cards.duplicate()
	state["opponent_deck"] = opponent_cards.duplicate()
	state["select_mode"] = "practice"
	return state


static func tutorial(player_cards: Array = [], opponent_cards: Array = []) -> Dictionary:
	var state := empty()
	state["mode"] = "tutorial"
	state["select_mode"] = "tutorial"
	state["difficulty"] = "normal"
	state["player_deck"] = player_cards.duplicate()
	state["opponent_deck"] = opponent_cards.duplicate()
	return state


static func hotseat_pending(player_one_cards: Array) -> Dictionary:
	var state := empty()
	state["pending_p1"] = player_one_cards.duplicate()
	state["select_mode"] = "hotseat_p2"
	state["select_step"] = 2
	return state


static func hotseat(player_one_cards: Array, player_two_cards: Array) -> Dictionary:
	var state := empty()
	state["mode"] = "hotseat"
	state["player_deck"] = player_one_cards.duplicate()
	state["opponent_deck"] = player_two_cards.duplicate()
	state["select_mode"] = "hotseat_p2"
	return state


static func online(player_cards: Array, next_scene: String) -> Dictionary:
	var state := empty()
	state["mode"] = "online"
	state["player_deck"] = player_cards.duplicate()
	state["select_mode"] = "online"
	state["next_scene"] = next_scene
	return state
