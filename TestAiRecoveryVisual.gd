extends Node

var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Recovery visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	var old_setup := PlayerData.battle_preparation_snapshot()
	var old_config := PlayerData.battle_config.duplicate(true)
	var old_context := PlayerData.card_playtest_context.duplicate(true)
	var old_language := Locale.language
	var library_hash := FileAccess.get_sha256("user://card_library.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ai-recovery"))
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			for effect in ["gain_mana", "heal"]:
				PlayerData.card_playtest_context = {}
				PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
				PlayerData.configure_practice_battle(UgcBenchmarkPool.deck(), UgcBenchmarkPool.deck(), "normal")
				var battle = preload("res://Main.tscn").instantiate()
				viewport.add_child(battle)
				await get_tree().create_timer(0.8).timeout
				await _exercise(viewport, battle, effect, "%s-%dx%d-%s" % [language, dimensions.x, dimensions.y, effect])
				battle.free()
		viewport.free()
	PlayerData._apply_battle_preparation(old_setup)
	PlayerData.battle_config = old_config
	PlayerData.card_playtest_context = old_context
	Locale.language = old_language
	_check(FileAccess.get_sha256("user://card_library.json") == library_hash, "practice verification must preserve the collection")
	if failures.is_empty():
		print("TEST_AI_RECOVERY_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_AI_RECOVERY_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _exercise(viewport: SubViewport, battle: Node, effect: String, prefix: String) -> void:
	var game = battle.game
	game.current_player = 1
	game.is_player_turn = true
	game.turn_number = 3
	game.first_switch = false
	game.player_field.slots.fill(null)
	game.player2_field.slots.fill(null)
	game.player_hand.clear()
	game.player2_hand.clear()
	game.shared_deck.clear()
	game.player_field.slots[0] = CardData.new("守卫 / Guard", 0, 9, 0)
	var recovery := CardData.new("补给员 / Support", 1, 6, 1, [{"skill_name": "恢复 / Recovery", "trigger": "on_activate", "effects": [{"effect": effect, "target": "self", "value": 5}]}])
	game.player2_field.slots[0] = recovery
	game.player2_field.current_mana = 8
	game.game_rng.seed = 1
	BattlePosition.ensure_ids(game)
	var metrics := BattleMetrics.new()
	game.metrics_callable = metrics.record
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var guard_before: Texture2D = battle.tabletop.cards[0].top.material_override.albedo_texture
	_check(not battle.end_turn_button.disabled and not battle.is_resolution_locked(), "practice end-turn input must be available")
	_click(viewport, battle.end_turn_button.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 8000
	while game.player2_field.actions_taken == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	while (game.current_player != 1 or battle.practice_ai_running or battle.is_resolution_locked()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(game.current_player == 1 and not battle.practice_ai_running and not battle.is_resolution_locked(), "actual practice AI must return control within the bounded deadline")
	var observed: Dictionary = metrics.cards.get(recovery.card_name, BattleMetrics.empty())
	_check(game.player_field.slots[0].hp == 8 and observed.attacks == 1 and observed.skills == 0 and observed.damage == 1, "practice AI must attack instead of using a full-cap/full-health skill: %s hp=%d events=%s" % [prefix, game.player_field.slots[0].hp, str(observed)])
	_check(game.player2_field.actions_taken == 1 and game.player2_field.current_mana == 10, "practice AI must spend exactly its free first action and keep capped Elixir")
	_check(not battle.end_turn_button.disabled, "player controls must unlock after AI turn")
	if battle.splash_tween != null and battle.splash_tween.is_running():
		await battle.splash_tween.finished
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(20, 200)
	viewport.push_input(motion, true)
	await RenderingServer.frame_post_draw
	var guard_after: Texture2D = battle.tabletop.cards[0].top.material_override.albedo_texture
	_check(guard_after is ImageTexture and guard_after != guard_before and guard_after.get_image().has_mipmaps(),
		"the changed guard must reach the 3D table as a new baked texture: " + prefix)
	_check(viewport.get_texture().get_image().save_png("res://artifacts/ai-recovery/" + prefix + ".png") == OK, "practice evidence must save")


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
