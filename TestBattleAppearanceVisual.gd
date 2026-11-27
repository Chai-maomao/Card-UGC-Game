extends "res://TestTabletop3DVisual.gd"

var tracking := false
var samples: Array = []


func _process(_delta: float) -> void:
	if tracking and is_instance_valid(battle) and is_instance_valid(battle.tabletop):
		samples.append(_layout_snapshot())


func _layout_snapshot() -> Array:
	return [battle.player_side_ui.get_global_rect(), battle.enemy_side_ui.get_global_rect(),
		battle.player_status_hud.get_global_rect(), battle.enemy_status_hud.get_global_rect(),
		battle.get_node("CanvasLayer").offset, battle.tabletop.camera.global_transform,
		battle.tabletop.projected_slot_corners(4), battle.tabletop.projected_slot_corners(9)]


func _set_appearance(value: int) -> void:
	AppPreferences.values["appearance"] = value
	UITheme.Tokens.set_appearance(value == 1)
	AppPreferences.changed.emit("appearance")


func _assert_stable_layout() -> void:
	assert(not samples.is_empty())
	for sample in samples:
		assert(sample == samples[0], "card actions must not move the battlefield or camera")
	samples.clear()


func _verify() -> void:
	var original_appearance: int = AppPreferences.values["appearance"]
	var viewport := get_viewport().get_visible_rect()
	for hud: Control in [battle.enemy_status_hud, battle.player_status_hud]:
		assert(viewport.encloses(hud.get_global_rect()), "status bars must fit inside the viewport")
	assert(not battle.hand_area.get_node("HandRail").visible)
	var status_top: float = battle.player_status_hud.get_global_rect().position.y
	for key in range(5):
		for point in battle.tabletop.projected_slot_corners(key):
			assert(point.y < status_top, "player slots and cards must remain above the status bar")
	if battle._action_timer.visible:
		var bar_rect: Rect2 = battle.middle_info_bar.get_global_rect()
		var button_rect: Rect2 = battle.end_turn_button.get_global_rect()
		assert(button_rect.position.x >= bar_rect.position.x - 2.0 and button_rect.end.x <= bar_rect.end.x + 2.0,
			"the end-turn button must remain inside the bar when the timer appears")
	for appearance in [0, 1, 0, 1]:
		_set_appearance(appearance)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(battle.get_node("CanvasLayer/MainBackground").get_theme_stylebox("panel") is StyleBoxEmpty)
		assert(battle.hand_area.get_node("HandBackdrop").get_theme_stylebox("panel") is StyleBoxEmpty)
	assert(UIMotion.get_node("HoverHints").label.get_theme_color("default_color").is_equal_approx(UITheme.COLOR_TEXT))
	var card: CardData = battle.game.player_field.slots[0]
	battle._show_card_details(card, false, 0, battle.player_side_ui.get_child(0), null, true)
	await get_tree().process_frame
	var title := battle.card_inspector.find_children("*", "Label", true, false).filter(func(label): return label.text == card.card_name)[0] as Label
	assert(title.get_theme_color("font_color").is_equal_approx(UITheme.Tokens.TITLE))
	battle.card_inspector.hide()
	_set_appearance(0)
	var popup = preload("res://CardCollectionDialog.gd").show_cards(battle, [], "弃牌堆")
	assert(popup.panel.get_meta("ui_popup_fill"))
	popup.queue_free()
	await get_tree().create_timer(0.3).timeout
	samples.append(_layout_snapshot())
	tracking = true
	var source: Control = battle.hand_container.get_child(0)
	var hand_count: int = battle._my_hand().size()
	await _drag(_center(source), _center(battle.player_side_ui.get_child(3)))
	assert(battle._my_hand().size() == hand_count - 1 and battle._my_field().slots[3] != null)
	await get_tree().create_timer(0.7).timeout
	tracking = false
	_assert_stable_layout()
	samples.append(_layout_snapshot())
	tracking = true
	source = battle.hand_container.get_child(0)
	hand_count = battle._my_hand().size()
	await _drag(_center(source), _center(battle.discard_zone))
	assert(battle._my_hand().size() == hand_count - 1)
	await get_tree().create_timer(0.7).timeout
	tracking = false
	_assert_stable_layout()
	samples.append(_layout_snapshot())
	tracking = true
	source = battle.hand_container.get_child(0)
	await _drag(_center(source), _center(battle.discard_zone))
	assert(battle._my_hand().is_empty())
	await get_tree().create_timer(0.7).timeout
	tracking = false
	_assert_stable_layout()
	_set_appearance(original_appearance)
	print("TEST_BATTLE_APPEARANCE_OK")
	get_tree().quit(0)
