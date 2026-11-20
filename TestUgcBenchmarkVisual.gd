extends Node

var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	var old_setup := PlayerData.battle_preparation_snapshot()
	var old_config := PlayerData.battle_config.duplicate(true)
	var old_context := PlayerData.card_playtest_context.duplicate(true)
	var old_language := Locale.language
	var library_hash := FileAccess.get_sha256("user://card_library.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ugc-benchmark"))
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			PlayerData.card_playtest_context = {}
			PlayerData.configure_hotseat_battle(UgcBenchmarkPool.deck(), UgcBenchmarkPool.deck())
			var battle = preload("res://Main.tscn").instantiate()
			viewport.add_child(battle)
			await get_tree().create_timer(1.0).timeout
			await _exercise(viewport, battle, "%s-%dx%d" % [language, dimensions.x, dimensions.y])
			battle.free()
		viewport.free()
	PlayerData._apply_battle_preparation(old_setup)
	PlayerData.battle_config = old_config
	PlayerData.card_playtest_context = old_context
	Locale.language = old_language
	_check(FileAccess.get_sha256("user://card_library.json") == library_hash, "visual fixtures must preserve the persisted card library")
	if failures.is_empty():
		print("TEST_UGC_BENCHMARK_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_UGC_BENCHMARK_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _exercise(viewport: SubViewport, battle: Node, prefix: String) -> void:
	var game = battle.game
	game.current_player = 1
	game.turn_number = 2
	game.player_field.slots.fill(null)
	game.player2_field.slots.fill(null)
	game.player_hand = UgcBenchmarkPool.deck().slice(0, 8)
	game.player2_hand.clear()
	game.player_field.current_mana = 5
	game.player_field.action_points = 3
	game.player_field.action_budget = 3
	game.player_field.actions_taken = 0
	game.player2_field.current_mana = 0
	var relay := UgcBenchmarkPool.card("relay")
	var grower := UgcBenchmarkPool.card("grower")
	var reactor := UgcBenchmarkPool.card("reactor")
	var parasite := UgcBenchmarkPool.card("parasite")
	ParasiteRules.attach(parasite, relay)
	game.player_field.slots[0] = relay
	game.player_field.slots[1] = grower
	game.player2_field.slots[3] = reactor
	var metrics := BattleMetrics.new()
	game.metrics_callable = metrics.record
	BattlePosition.ensure_ids(game)
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(battle.hand_container.get_child_count() == 8, "all eight frozen archetypes must render as hand cards")
	for card_ui in battle.hand_container.get_children():
		_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(card_ui.get_global_rect().get_center()), "every frozen hand-card center must fit the viewport")
		if card_ui.current_card_data.is_parasite():
			await _verify_parasite_rows(card_ui)
	var relay_ui = battle.player_side_ui.get_child(0).current_card_ui
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,relay_ui,0)
	await _settle(battle)
	relay_ui = battle.player_side_ui.get_child(0).current_card_ui
	_check(game.player_field.current_mana == 7 and not relay_ui.skill2_btn.disabled and relay_ui.normal_atk_btn.disabled and battle.player_side_ui.get_child(0).get_node("ActionGlow").visible, "real frozen relay must generate income and retain its second active affordance")
	await _capture(viewport, battle, prefix + "-relay-ready")
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,relay_ui,1)
	await get_tree().process_frame
	_check(battle.activate_targeting, "frozen directed active must request an actual enemy target")
	_click_target(viewport, battle.enemy_side_ui.get_child(3))
	await _settle(battle)
	_check(reactor.hp == 4 and relay.hp == 5 and parasite.skills_used_count == {1: 1}, "actual reaction must damage the initiator and run its independently limited parasite heal")
	var grower_ui = battle.player_side_ui.get_child(1).current_card_ui
	await preload("res://tests/VisualBattleInput.gd").action(viewport,battle,grower_ui)
	await get_tree().process_frame
	_click_target(viewport, battle.enemy_side_ui.get_child(3))
	await _settle(battle)
	_check(grower.hp == 3 and grower.field_atk_bonus == 2 and reactor.hp == 4 and reactor.skills_used_count == {0: 2}, "real zero-attack growth must run alongside the second receiver reaction")
	_check(game.player_field.actions_taken == 3 and game.player_field.action_points == 0 and game.player_field.current_mana == 8 and game.player2_field.current_mana == 2 and game.player2_hand.size() == 2, "actual fixture resources must match the exact 0/1/2 payment sequence")
	_check(metrics.by_identity[parasite.card_id].mana_gained == 1 and metrics.by_identity[parasite.card_id].healing == 1, "UI chain must retain independent parasite contribution identity")
	_check(not battle.player_side_ui.get_child(0).get_node("ActionGlow").visible and not battle.player_side_ui.get_child(1).get_node("ActionGlow").visible, "completed frozen units must have no stale action glow")
	await _capture(viewport, battle, prefix + "-resolved")
	var snapshot := BattlePosition.capture(game, {"origin": "visual_mechanism_fixture", "pool": UgcBenchmarkPool.ID, "pool_sha256": UgcBenchmarkPool.manifest().sha256})
	var path := "res://artifacts/ugc-benchmark/" + prefix + ".json"
	_check(BattlePosition.save(snapshot, path) == OK, "resolved UI fixture must save as a complete position")
	var restored := BattlePosition.read(FileAccess.get_file_as_string(path))
	_check(restored.ok and BattleRepro.state_hash(restored.game) == BattleRepro.state_hash(game), "UI position must restore full identities, RNG and lifetime counters")


func _verify_parasite_rows(card_ui: Control) -> void:
	var original: CardData = card_ui.current_card_data
	for mode in [CardData.PARASITE_DAMAGE_LINKED, CardData.PARASITE_DAMAGE_ABSORB]:
		var display_fixture := original.duplicate_card()
		display_fixture.parasite_damage_mode = mode
		display_fixture.hp = 12
		display_fixture.max_hp = 12
		card_ui.set_card(display_fixture)
		await get_tree().process_frame
		_check(card_ui.hp_label.get_global_rect().end.y <= card_ui.atk_label.get_global_rect().position.y and card_ui.hp_label.get_line_count() <= 2, "wrapped parasite mode/HP and attack grant must occupy separate rows")
		var text_width: float = card_ui.hp_label.get_theme_font("font").get_string_size(card_ui.hp_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, card_ui.hp_label.get_theme_font_size("font_size")).x
		_check(text_width <= card_ui.hp_label.size.x and card_ui.hp_label.tooltip_text.begins_with(card_ui.hp_label.text), "compact mode and 12/12 HP must fit without clipping and retain their complete tooltip")
		_check(card_ui.atk_label.get_global_rect().end.y <= card_ui.status_icons.global_position.y and card_ui.status_icons.global_position.y <= card_ui.action_buttons.get_global_rect().position.y, "parasite stats and badges must stay above their action chip")
	card_ui.set_card(original)
	await get_tree().process_frame


func _settle(battle: Node) -> void:
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 5000
	while battle.is_resolution_locked() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not battle.is_resolution_locked(), "complex UGC feedback must release its input lock")
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(viewport: SubViewport, battle: Node, name: String) -> void:
	if battle.splash_tween != null and battle.splash_tween.is_running():
		await battle.splash_tween.finished
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(20, 200)
	viewport.push_input(motion, true)
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png("res://artifacts/ugc-benchmark/" + name + ".png") == OK, "actual renderer evidence must save")


func _click_target(viewport: SubViewport, slot: Control) -> void:
	_click(viewport, slot.get_global_rect().position + slot.size * Vector2(0.5, 0.35))


func _click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
