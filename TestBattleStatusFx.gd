extends Node

var failures: Array[String] = []


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.battle_mode = "practice"
	var battle: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var game = battle.get("game")
	var layer := battle.get_node("CanvasLayer") as CanvasLayer
	var hud := battle.get("player_status_hud") as Panel
	var content := hud.get_node("Margin/Content") as HBoxContainer
	var hp_bar := content.get_node("HpBar") as ProgressBar
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	battle.call("_update_battle_status_huds")
	_assert(_count_named(layer, "StatusFx_") == 0, "initial status binding must not fabricate feedback")

	var hp_before: int = game.player_field.player_hp
	var mana_before: int = game.player_field.get_total_mana()
	game.player_field.damage_player(5)
	game.player_field.add_mana(2)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(_has_named(layer, "StatusFx_Damage"), "player damage must create red status feedback")
	_assert(_has_named(layer, "StatusFx_Mana"), "permanent mana gain must create cyan status feedback")
	_assert(hp_bar.value > game.player_field.player_hp and hp_bar.value <= hp_before, "HP bar must animate from its previous value")
	_assert(mana_bar.value < game.player_field.get_total_mana() and mana_bar.value >= mana_before, "mana bar must animate toward its gain")
	await get_tree().create_timer(0.72).timeout
	_assert(is_equal_approx(hp_bar.value, float(game.player_field.player_hp)), "HP animation must settle on authoritative health")
	_assert(is_equal_approx(mana_bar.value, float(game.player_field.get_total_mana())), "mana animation must settle on authoritative mana")

	game.player_field.heal_player(3)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(_has_named(layer, "StatusFx_Heal"), "player healing must create green status feedback")
	await get_tree().create_timer(0.72).timeout

	game.player_field.add_temp_mana(1)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(_has_named(layer, "StatusFx_Mana"), "temporary mana gain must use the same recovery feedback")
	await get_tree().create_timer(0.72).timeout

	game.player_field.spend_mana(1)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(not _has_named(layer, "StatusFx_Mana"), "mana spending must not look like mana recovery")

	game.player_field.damage_player(1)
	battle.set("_suppress_status_feedback_once", true)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(not _has_named(layer, "StatusFx_Damage"), "recovery-state application must not fabricate damage feedback")
	_assert(is_equal_approx(hp_bar.value, float(game.player_field.player_hp)), "suppressed state refresh must snap to the authoritative HP")

	if failures.is_empty():
		print("TEST_BATTLE_STATUS_FX_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_BATTLE_STATUS_FX_FAILED: %s" % failure)
		get_tree().quit(1)


func _has_named(root: Node, node_name: String) -> bool:
	return root.find_child(node_name, true, false) != null


func _count_named(root: Node, prefix: String) -> int:
	var count := 0
	for node in root.find_children("%s*" % prefix, "", true, false):
		if not node.name.ends_with("Value"):
			count += 1
	return count


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
