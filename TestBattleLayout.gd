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
	var broadcast_strip := battle.get("combat_broadcast_panel") as Control
	_assert(broadcast_strip != null and not _overlap(enemy_row, broadcast_strip), "combat broadcast must stay outside the enemy field")
	battle.call("_show_combat_broadcast", "先锋攻击守卫，造成2点伤害", "attack")
	var broadcast_label := battle.get("combat_broadcast_label") as Label
	_assert(broadcast_label != null and "先锋" in broadcast_label.text and "守卫" in broadcast_label.text, "latest action must retain actor and target in the centre strip")
	var log_panel := battle.get("action_log_panel") as Control
	log_panel.visible = true
	_assert(not _overlap(enemy_row, log_panel), "opened battle log must not cover the enemy field")
	var log_text := battle.get("action_log_text") as RichTextLabel
	_assert(log_text != null and log_text.selection_enabled and "回合" in log_text.get_parsed_text(), "battle log must group selectable entries by turn")
	_assert(hand_container.get_child_count() == SkillEngine.MAX_HAND_SIZE, "the legal six-card hand must remain fully represented")
	for card in hand_container.get_children():
		_assert(_inside((card as Control).get_global_rect(), hand_area.get_global_rect(), 2.0), "a legal hand card exceeds the hand dock")

	var prior_acceleration := GamePreferences.animation_acceleration_enabled()
	GamePreferences.set_animation_acceleration(false)
	var attack_skill := {
		"skill_name": "Chain Hit", "trigger": SkillEngine.TRIGGER_ON_ATTACK, "probability": 100,
		"effects": [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SIDES, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1, "probability": 100}],
	}
	var sequence_attacker := CardData.new("Sequence Attacker", 1, 5, 2, [attack_skill])
	game.player_field.slots[2] = sequence_attacker
	for slot in [1, 2, 3]:
		game.player2_field.slots[slot] = CardData.new("Sequence Target %d" % slot, 1, 5, 1)
	game.current_player = 1
	game.turn_number = 2
	battle.call("_begin_action_broadcast", "attack", 1, sequence_attacker.card_name, game.player2_field.slots[2].card_name, {"target_player": 2, "target_slot": 2})
	game.execute_attack(2, 2)
	var staged_events: Array = battle.get("_action_hp_events").duplicate(true)
	var staged_correctly := staged_events.size() == 4 and int(staged_events[0].get("delta", 0)) == -2 \
		and int(staged_events[0].get("feedback_group", -1)) == 0
	for index in range(1, staged_events.size()):
		staged_correctly = staged_correctly and int(staged_events[index].get("delta", 0)) == -1 \
			and int(staged_events[index].get("feedback_group", -1)) == 1
	_assert(staged_correctly, "direct attack damage must precede simultaneous target-and-neighbor skill damage")
	battle.set("_action_broadcast", {})
	battle.set("_action_hp_events", [])
	battle.set("_action_feedback_group_stack", [])
	var layer := battle.get_node("CanvasLayer")
	var initial_minus_two := _count_label_text(layer, "-2")
	var initial_minus_one := _count_label_text(layer, "-1")
	battle.call("_queue_hp_feedback", staged_events)
	await get_tree().process_frame
	_assert(_count_label_text(layer, "-2") > initial_minus_two, "the direct attack result must play immediately")
	_assert(_count_label_text(layer, "-1") == initial_minus_one, "the triggered effect must not play in the attack frame")
	await get_tree().create_timer(0.1).timeout
	_assert(_count_label_text(layer, "-1") == initial_minus_one, "the triggered effect must wait for the 0.2-second presentation gap")
	await get_tree().create_timer(0.14).timeout
	_assert(_count_label_text(layer, "-1") > initial_minus_one, "the triggered effect must play after the presentation gap")
	GamePreferences.set_animation_acceleration(true)
	var accelerated_minus_one := _count_label_text(layer, "-1")
	battle.call("_queue_hp_feedback", staged_events)
	_assert(_count_label_text(layer, "-1") > accelerated_minus_one and (battle.get("_hp_feedback_batches") as Array).is_empty(),
			"accelerated mode must play every feedback stage immediately")
	GamePreferences.set_animation_acceleration(prior_acceleration)

	print("TEST_BATTLE_LAYOUT_OK")
	get_tree().quit(0)


func _overlap(first: Control, second: Control) -> bool:
	return first != null and second != null and first.visible and second.visible \
		and first.get_global_rect().grow(-1.0).intersects(second.get_global_rect().grow(-1.0))


func _inside(inner: Rect2, outer: Rect2, tolerance: float) -> bool:
	return outer.grow(tolerance).encloses(inner)


func _count_label_text(root: Node, expected: String) -> int:
	var count := 0
	if root is Label and root.text == expected:
		count += 1
	for child in root.get_children():
		count += _count_label_text(child, expected)
	return count


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_BATTLE_LAYOUT_FAILED: %s" % message)
	get_tree().quit(1)
