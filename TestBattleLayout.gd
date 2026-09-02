extends Node


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.battle_mode = "practice"
	var battle: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var layout := battle.get_node("CanvasLayer/MainBackground/MainLayout") as Control
	_assert(layout.visible, "2D battle layout must be the active composition")
	_assert(battle.get_node_or_null("BattleStage3D") == null, "retired 3D stage must not remain in the battle scene")

	var game = battle.get("game")
	game.player_hand.clear()
	for index in range(SkillEngine.MAX_HAND_SIZE):
		game.player_hand.append(CardData.new("Layout Hand %d" % index, 1, 2, 1, []))
	battle.call("_refresh_hand_ui")
	battle.call("_apply_responsive_layout")
	await get_tree().process_frame
	await get_tree().process_frame

	var enemy_hud := battle.get("enemy_status_hud") as Control
	var player_hud := battle.get("player_status_hud") as Control
	var enemy_row := battle.get("enemy_side_ui") as Control
	var player_row := battle.get("player_side_ui") as Control
	var hand_area := battle.get("hand_area") as Control
	var hand_container := battle.get("hand_container") as Control
	var discard_zone := battle.get("discard_zone") as Control
	var draw_button := battle.get("draw_pile_btn") as Control

	for toolbar_name in ["abandon_battle_button", "action_log_button", "help_btn"]:
		var toolbar := battle.get(toolbar_name) as Control
		_assert(not _overlap(enemy_hud, toolbar), "enemy HUD overlaps %s" % toolbar_name)
	_assert(not _overlap(enemy_hud, enemy_row), "enemy HUD overlaps the enemy field")
	_assert(not _overlap(player_hud, player_row), "player HUD overlaps the player field")
	_assert(not _overlap(player_hud, hand_area), "player HUD overlaps the hand dock")
	_assert(not _overlap(hand_area, discard_zone), "discard zone overlaps the hand dock")
	_assert(not _overlap(hand_area, draw_button), "draw pile overlaps the hand dock")
	_assert(hand_container.get_child_count() == SkillEngine.MAX_HAND_SIZE, "the legal six-card hand must remain fully represented")
	for card in hand_container.get_children():
		_assert(_inside((card as Control).get_global_rect(), hand_area.get_global_rect(), 2.0), "a legal hand card exceeds the hand dock")

	print("TEST_BATTLE_LAYOUT_OK")
	get_tree().quit(0)


func _overlap(first: Control, second: Control) -> bool:
	return first != null and second != null and first.visible and second.visible \
		and first.get_global_rect().grow(-1.0).intersects(second.get_global_rect().grow(-1.0))


func _inside(inner: Rect2, outer: Rect2, tolerance: float) -> bool:
	return outer.grow(tolerance).encloses(inner)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_BATTLE_LAYOUT_FAILED: %s" % message)
	get_tree().quit(1)
