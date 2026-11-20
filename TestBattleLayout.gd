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
	battle.call("_show_toast", "tip.insufficient_mana")
	var toast_feed := battle.get_node_or_null("CanvasLayer/ToastStack") as Control
	_assert(toast_feed != null and toast_feed.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"battle warnings must delegate to the input-transparent message component")
	var warning := toast_feed.get_child(toast_feed.get_child_count() - 1).get_child(0) as Label
	_assert(warning.text == Locale.t("tip.insufficient_mana"), "delegated battle warnings must retain localized wording")
	_assert(hand_container.get_child_count() == SkillEngine.MAX_HAND_SIZE, "the legal eight-card hand must remain fully represented")
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
	var silent_blocker := battle.get("_resolution_blocker") as Control
	_assert(silent_blocker != null and silent_blocker.visible and silent_blocker.get_child_count() == 0,
			"multi-stage feedback must block input without displaying a resolving panel")
	_assert(_count_label_text(layer, "-2") > initial_minus_two, "the direct attack result must play immediately")
	_assert(_count_label_text(layer, "-1") == initial_minus_one, "the triggered effect must not play in the attack frame")
	await get_tree().create_timer(0.1).timeout
	_assert(_count_label_text(layer, "-1") == initial_minus_one, "the triggered effect must wait for the 0.2-second presentation gap")
	await get_tree().create_timer(0.14).timeout
	_assert(_count_label_text(layer, "-1") > initial_minus_one, "the triggered effect must play after the presentation gap")
	GamePreferences.set_animation_acceleration(true)
	var accelerated_minus_one := _count_label_text(layer, "-1")
	battle.call("_queue_hp_feedback", staged_events)
	await get_tree().process_frame
	_assert(_count_label_text(layer, "-1") > accelerated_minus_one and (battle.get("_hp_feedback_batches") as Array).is_empty(),
			"accelerated mode must play every non-random stage together after the synchronous trigger chain is collected")
	GamePreferences.set_animation_acceleration(false)
	var double_effect := {
		"skill_name": "Double Effect", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100,
		"effects": [
			{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1, "probability": 100},
			{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1, "probability": 100},
		],
	}
	var skill_source := CardData.new("Double Caster", 1, 5, 1, [double_effect])
	var skill_target := CardData.new("Double Target", 1, 5, 1)
	game.player_field.slots[0] = skill_source
	game.player2_field.slots[0] = skill_target
	battle.call("_begin_action_broadcast", "skill", 1, skill_source.card_name, skill_target.card_name, {"skill": "Double Effect", "target_player": 2, "target_slot": 0})
	game.trigger_activate_skills(0, 0, 0, 2)
	var double_events: Array = battle.get("_action_hp_events")
	_assert(double_events.size() == 2 and int(double_events[0].get("feedback_group", -1)) == 1 \
		and int(double_events[1].get("feedback_group", -1)) == 2 \
		and int(double_events[0].get("feedback_origin_group", -1)) == 1 \
		and int(battle.call("_feedback_stage_span", double_events)) == 2,
			"separate effects inside one skill must receive separate presentation stages")
	battle.set("_action_broadcast", {})
	battle.set("_action_hp_events", [])
	battle.set("_action_presentation_events", [])
	battle.set("_action_feedback_group_stack", [])

	# Nested reactions must stay in actual causal order. A 4/4 wall that heals
	# 3 after damage visually resolves 4->2, 2->4, 4->3, then 3->4.
	var wall_recovery := {
		"skill_name": "Recover after hit", "trigger": SkillEngine.TRIGGER_ON_DAMAGED, "probability": 100,
		"effects": [{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "value": 3, "probability": 100}],
	}
	var followup_hit := {
		"skill_name": "Follow-up spark", "trigger": SkillEngine.TRIGGER_ON_ATTACK, "probability": 100,
		"effects": [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1, "probability": 100}],
	}
	var misaka := CardData.new("御坂美琴", 1, 5, 2, [followup_hit])
	var wall := CardData.new("肉墙", 1, 4, 0, [wall_recovery])
	game.player_field.slots[2] = misaka
	game.player2_field.slots[2] = wall
	game.current_player = 1
	game.turn_number = 2
	battle.call("_begin_action_broadcast", "attack", 1, misaka.card_name, wall.card_name, {"target_player": 2, "target_slot": 2})
	game.execute_attack(2, 2)
	var causal_events: Array = []
	for event: Dictionary in battle.get("_action_presentation_events"):
		if str(event.get("kind", "")) == "hp":
			causal_events.append(event)
	var expected_deltas := [-2, 2, -1, 1]
	var causal_order_ok := causal_events.size() == expected_deltas.size()
	for index in range(mini(causal_events.size(), expected_deltas.size())):
		causal_order_ok = causal_order_ok \
			and int(causal_events[index].get("delta", 0)) == expected_deltas[index] \
			and int(causal_events[index].get("feedback_group", -1)) == index
	_assert(causal_order_ok and wall.hp == 4,
			"nested damage recovery must present -2, +2, -1, +1 in exact trigger order")
	_assert(int(battle.call("_feedback_stage_span", battle.get("_action_presentation_events"))) == 4,
			"nested attack feedback must retain four contiguous 0.2-second stages")
	battle.set("_action_broadcast", {})
	battle.set("_action_hp_events", [])
	battle.set("_action_presentation_events", [])
	battle.set("_action_feedback_group_stack", [])

	# Zhang Xuefeng's three-effect skill must expose three distinct stages:
	# self damage, draw travel, then the status pulse on enemy targets.
	var three_bites := {
		"skill_name": "三口一个巧乐兹", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100,
		"effects": [
			{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SELF, "value": 1, "probability": 100},
			{"effect": SkillEngine.EFFECT_DRAW_CARDS, "target": SkillEngine.TARGET_SELF, "value": 1, "probability": 100},
			{"effect": SkillEngine.EFFECT_ADD_BUFF, "target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "buff_id": SkillEngine.BUFF_MISFORTUNE, "value": 33, "duration": 1, "probability": 100},
		],
	}
	var zhang := CardData.new("张雪峰", 1, 5, 1, [three_bites])
	var status_target := CardData.new("状态目标", 1, 5, 1)
	var drawn_card := CardData.new("抽到的牌", 1, 3, 1)
	game.player_field.slots[0] = zhang
	game.player2_field.slots[0] = status_target
	game.player_hand.clear()
	game.shared_deck = [drawn_card]
	battle.call("_begin_action_broadcast", "skill", 1, zhang.card_name, "", {"skill": "三口一个巧乐兹"})
	game.trigger_activate_skills(0, -1, 0, 0)
	var visible_kinds: Array[String] = []
	var visible_groups: Array[int] = []
	for event: Dictionary in battle.get("_action_presentation_events"):
		var kind := str(event.get("kind", ""))
		if kind in ["hp", "hand_entry", "effect"]:
			visible_kinds.append(kind)
			visible_groups.append(int(event.get("feedback_group", -1)))
	_assert(visible_kinds == ["hp", "hand_entry", "effect"] and visible_groups == [1, 2, 3],
			"damage, draw and status application must play as three ordered stages")
	battle.set("_action_broadcast", {})
	battle.set("_action_hp_events", [])
	battle.set("_action_presentation_events", [])
	battle.set("_action_feedback_group_stack", [])
	battle.get("_pending_hand_entry_ids").clear()

	var blocked_attacker := CardData.new("零伤攻击者", 1, 4, 2)
	var blocked_target := CardData.new("完全减伤目标", 1, 4, 0)
	blocked_target.apply_buff(SkillEngine.BUFF_DAMAGE_REDUCTION, 100, 1, 2)
	game.player_field.slots[4] = blocked_attacker
	game.player2_field.slots[4] = blocked_target
	battle.call("_begin_action_broadcast", "attack", 1, blocked_attacker.card_name, blocked_target.card_name, {"target_player": 2, "target_slot": 4})
	game.execute_attack(4, 4)
	var zero_timeline: Array = battle.get("_action_presentation_events").duplicate(true)
	var zero_damage_ok := zero_timeline.size() == 1 \
		and int(zero_timeline[0].get("delta", -1)) == 0 \
		and bool(zero_timeline[0].get("zero_damage", false))
	_assert(zero_damage_ok and blocked_target.hp == 4, "fully prevented damage must remain a staged -0 event")
	battle.set("_action_broadcast", {})
	battle.set("_action_hp_events", [])
	battle.set("_action_presentation_events", [])
	battle.set("_action_feedback_group_stack", [])
	var zero_text_before := _count_label_text(layer, "-0")
	battle.call("_queue_presentation_feedback", zero_timeline)
	await get_tree().process_frame
	_assert(_count_label_text(layer, "-0") > zero_text_before, "prevented damage must display a -0 floating number")
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
