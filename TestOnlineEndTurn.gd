extends Node

const BattleScene = preload("res://Main.tscn")


func _ready() -> void:
	NetworkManager.close_connection()
	NetworkManager.is_online = true
	NetworkManager.is_host = true
	NetworkManager.is_dedicated_server = false
	NetworkManager.player_number = 1
	PlayerData.battle_mode = "multiplayer"

	var battle = BattleScene.instantiate()
	add_child(battle)
	await get_tree().process_frame
	var initial_revision: int = battle.game.state_revision
	_assert(battle.game.current_player == 1, "online authority test must start on P1")

	battle._on_end_turn_pressed()
	# The old regression performed a second local end-turn after 0.5 seconds.
	# Waiting beyond that boundary proves the authority path returned instead.
	await get_tree().create_timer(0.7).timeout
	_assert(battle.game.current_player == 2, "one authority click must advance exactly once to P2")
	_assert(battle.game.turn_number == 1, "one authority click must not advance to the next round")
	_assert(battle.game.state_revision == initial_revision + 1, "one authority click must create exactly one committed revision")

	battle.queue_free()
	NetworkManager.close_connection()
	print("TEST_ONLINE_END_TURN_OK")
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_ONLINE_END_TURN_FAILED: %s" % message)
	NetworkManager.close_connection()
	get_tree().quit(1)
