extends Node

const ActionClock = preload("res://BattleActionClock.gd")


func _ready() -> void:
	Locale.language = "zh"
	AppPreferences.set_value("window_mode", 1)
	get_window().size = Vector2i(1280, 720)
	_verify_clock()
	await _verify_settings()
	await _verify_battle()
	await _verify_enemy_swap()
	print("TEST_BATTLE_ACTION_TIMER_OK defaults,settings,move,rejected_action,reset,timeout")
	get_tree().quit(0)


func _verify_clock() -> void:
	var clock := ActionClock.new()
	var turn := Vector2i(1, 1)
	assert(not clock.tick({}, turn, 0, false, 0) and clock.remaining_ms == 30000)
	clock.tick({}, turn, 0, false, 2000)
	clock.tick({}, turn, 0, true, 2000)
	clock.tick({}, turn, 0, false, 14000)
	assert(clock.remaining_ms == 28000, "resolution and reconnection must pause the countdown")
	assert(clock.tick({}, turn, 0, false, 42000))
	assert(not clock.tick({}, turn, 1, false, 42000) and clock.remaining_ms == 20000)
	assert(not clock.tick({"action_time_enabled": false}, turn, 0, false, 50000) and clock.limit_ms == 0)


func _verify_settings() -> void:
	var surface := Control.new()
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var config := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	var popup := preload("res://presentation/BattleRulesEditor.gd").open(surface, config, func(): return false, func(_value): pass)
	var toggle := popup.find_child("ActionTimeEnabledToggle", true, false) as CheckButton
	var interval := popup.find_child("action_time_seconds", true, false) as SpinBox
	var first := popup.find_child("first_action_time_seconds", true, false) as SpinBox
	assert(toggle.button_pressed and interval.value == 20 and first.value == 30)
	toggle.button_pressed = false
	assert(not interval.is_visible_in_tree() and not first.is_visible_in_tree())
	toggle.button_pressed = true
	assert(first.is_visible_in_tree())
	interval.value = 2
	first.value = 4
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://artifacts/battle-timer-settings.png") == OK)
	for child in popup.find_children("*", "Button", true, false):
		if child.text == Locale.t("common.confirm"):
			child.pressed.emit()
			break
	assert(config.action_time_enabled and config.action_time_seconds == 2 and config.first_action_time_seconds == 4)
	assert(MatchAgreement.valid_config(config))
	config.first_action_time_seconds = 0
	assert(not MatchAgreement.valid_config(config))
	surface.queue_free()
	await get_tree().process_frame


func _verify_battle() -> void:
	var deck: Array[CardData] = []
	for i in range(10):
		deck.append(CardData.new("石庭守卫 %d" % i, 0, 5, 2))
	PlayerData.configure_hotseat_battle(deck, deck)
	PlayerData.hotseat_opening_player = 0
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	PlayerData.battle_config.action_time_seconds = 1
	PlayerData.battle_config.first_action_time_seconds = 8
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await get_tree().create_timer(0.25).timeout
	var field: BattleField = battle.game.active_field()
	var existing := CardData.new("换位测试", 0, 5, 2)
	field.slots[0] = existing
	battle.update_entire_screen()
	await get_tree().process_frame
	var before: int = battle._action_clock.remaining_ms
	assert(battle._action_clock.limit_ms == 8000 and before > 0 and before < 8000)
	get_tree().paused = true
	await get_tree().create_timer(0.3).timeout
	get_tree().paused = false
	await get_tree().process_frame
	assert(battle._action_clock.remaining_ms >= before - 125, "the local pause menu must not consume time")
	battle._on_card_drag_summoned(existing, null, 1)
	await get_tree().process_frame
	assert(field.slots[1] == existing and battle._action_clock.remaining_ms <= before)
	var card: CardData = battle.game.active_hand()[0]
	battle._on_card_drag_summoned(card, null, 1)
	await get_tree().process_frame
	assert(card in battle.game.active_hand() and battle._action_clock.remaining_ms <= before)
	battle._on_card_drag_summoned(card, null, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(field.slots[2] == card and battle._action_clock.limit_ms == 1000)
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://artifacts/battle-timer-expiring.png") == OK)
	var actor: int = battle.game.current_player
	var deadline := Time.get_ticks_msec() + 5000
	while battle.game.current_player == actor and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(battle.game.current_player != actor, "expiry must end the turn through the regular battle flow")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(battle._action_clock.limit_ms == 8000)
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://artifacts/battle-timer-hud.png") == OK)
		AppPreferences.set_value("text_size", 2)
		get_window().size = Vector2i(960, 540)
		await get_tree().create_timer(0.3).timeout
		assert(get_viewport().get_visible_rect().encloses(battle._action_timer.get_global_rect()))
		assert(not battle._action_timer.get_global_rect().intersects(battle.end_turn_button.get_global_rect()))
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://artifacts/battle-timer-compact.png") == OK)
	battle.queue_free()
	await get_tree().process_frame


func _verify_enemy_swap() -> void:
	var deck: Array[CardData] = []
	for index in range(10):
		deck.append(CardData.new("石庭守卫 %d" % index, 0, 5, 2))
	PlayerData.configure_hotseat_battle(deck, deck)
	PlayerData.hotseat_opening_player = 0
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	PlayerData.battle_config.action_time_enabled = false
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await get_tree().create_timer(0.3).timeout
	var game: RefCounted = battle.game
	var actor: int = game.current_player
	var own: BattleField = battle._field_for_player(actor)
	var enemy: BattleField = battle._field_for_player(3 - actor)
	var first := CardData.new("一号守卫", 0, 4, 2)
	var third := CardData.new("三号守卫", 0, 6, 3)
	var fifth := CardData.new("五号守卫", 0, 5, 3)
	enemy.slots = [first, null, third, null, fifth]
	var skill := {"trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
		"effects": [{"effect": SkillRegistry.EFFECT_SWAP_ENEMY_SLOTS, "target": SkillEngine.TARGET_SELF}]}
	for destination in [5, 4]:
		var caster := CardData.new("换位术士", 0, 5, 2, [skill])
		own.slots[0] = caster
		assert(game.trigger_activate_skills(0, -1, 0, 0), "swap must resolve through a normal skill")
		var actions: int = game.effective_actions_this_turn
		assert(game.pending_cost_choices.size() == 1 and not battle.is_my_turn(), "the skill must queue exactly one choice")
		battle.update_entire_screen()
		await get_tree().process_frame
		await get_tree().process_frame
		assert(battle.enemy_swap_drag_payload(3).is_empty() and not battle.enemy_swap_drag_payload(2).is_empty())
		if DisplayServer.get_name() == "headless":
			battle.drop_enemy_swap(battle.enemy_swap_drag_payload(2), destination - 1)
		else:
			await _drag_enemy_card(battle, 2, destination - 1)
		assert(game.pending_cost_choices.is_empty() and game.effective_actions_this_turn == actions)
		assert(battle.enemy_swap_drag_payload(destination - 1).is_empty(), "the enemy drag must relock after one move")
		await get_tree().process_frame
		if destination == 5:
			assert(enemy.slots == [first, null, fifth, null, third], "slots 3 and 5 must swap cards")
		else:
			assert(enemy.slots == [first, null, null, fifth, third], "moving to slot 4 must leave slot 3 empty")
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_ENEMY_SLOT_SWAP_OK")


func _drag_enemy_card(battle: Node, from: int, to: int) -> void:
	var source: Control = battle.enemy_side_ui.get_child(from)
	var destination: Control = battle.enemy_side_ui.get_child(to)
	var start := source.get_global_rect().get_center()
	var finish := destination.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.pressed = true
	click.position = start
	get_viewport().push_input(click, true)
	await get_tree().process_frame
	var previous := start
	for step in range(1, 7):
		var motion := InputEventMouseMotion.new()
		motion.position = start.lerp(finish, float(step) / 6)
		motion.relative = motion.position - previous
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion, true)
		previous = motion.position
		await get_tree().process_frame
	assert(get_viewport().gui_is_dragging() and get_viewport().gui_get_drag_data().enemy_swap_source == from,
		"the drag must start on the enemy card")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("res://artifacts/battle-swap-drag.png") == OK)
	click.position = finish
	click.button_mask = 0
	click.pressed = false
	get_viewport().push_input(click, true)
	await get_tree().process_frame
