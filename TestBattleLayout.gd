extends Node


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.battle_mode = "practice"
	var battle: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var root: Control = battle.get_node("CanvasLayer/MainBackground")
	var enemy_row: Control = battle.get_node("CanvasLayer/MainBackground/MainLayout/EnemySide")
	var player_row: Control = battle.get_node("CanvasLayer/MainBackground/MainLayout/PlayerSide")
	var enemy_aura: Control = battle.get_node("CanvasLayer/MainBackground/EnemyAura")
	var player_aura: Control = battle.get_node("CanvasLayer/MainBackground/PlayerAura")
	_assert_local_aura(root, enemy_row, enemy_aura, "enemy")
	_assert_local_aura(root, player_row, player_aura, "player")

	var middle: Control = battle.get_node("CanvasLayer/MainBackground/MainLayout/MiddleInfoBar")
	var enemy_hud: Control = battle.get_node("CanvasLayer/MainBackground/MainLayout/EnemyStatusRow/EnemyStatusHUD")
	_assert(absf(middle.size.x - enemy_hud.size.x) <= 1.0, "command strip must align with status HUD width")

	var hand_scroll: Control = battle.get_node("CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/HandArea/HandContent/HandScroll")
	var six_card_width: float = 6.0 * 120.0 + 5.0 * 8.0
	_assert(hand_scroll.size.x + 1.0 >= six_card_width, "six-card hand must fit without covering pile controls")

	print("TEST_BATTLE_LAYOUT_OK")
	get_tree().quit(0)


func _assert_local_aura(root: Control, row: Control, aura: Control, label: String) -> void:
	var local_row_top := row.global_position.y - root.global_position.y
	_assert(aura.position.y < local_row_top, "%s aura must fade in before its card row" % label)
	_assert(aura.position.y + aura.size.y > local_row_top + row.size.y, "%s aura must fade out after its card row" % label)
	_assert(aura.size.y < root.size.y * 0.5, "%s aura must remain local instead of splitting the battlefield" % label)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_BATTLE_LAYOUT_FAILED: %s" % message)
	get_tree().quit(1)
