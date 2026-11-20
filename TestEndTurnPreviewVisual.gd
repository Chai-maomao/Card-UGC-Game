extends Node

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.card_playtest_context = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/end-turn-preview"))
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
			PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
			var battle = load("res://Main.tscn").instantiate()
			viewport.add_child(battle)
			await get_tree().create_timer(0.4).timeout
			var game = battle.game
			game.current_player = 1
			game.is_player_turn = true
			game.turn_number = 3
			game.player2_field.slots.fill(null)
			game.player_field.slots.fill(null)
			for slot in range(3):
				game.player_field.slots[slot] = CardData.new("先锋 %d / Vanguard %d" % [slot + 1, slot + 1], 1, 5, 2 + slot)
			game.player_field.current_mana = 2
			game.player_field.temp_mana = 9
			game.player_field.actions_taken = 1
			game.player_field.action_points = 1
			battle._sync_face_mana_toggle()
			battle.face_mana_button.set_pressed_no_signal(true)
			battle.update_entire_screen()
			await get_tree().create_timer(0.3).timeout
			var button: Button = battle.end_turn_button
			var hp_bar: ProgressBar = battle.enemy_status_hud.get_node("Margin/Content/HpBar")
			var overlay = hp_bar.get_node_or_null("ResourceCostPreview")
			_check(overlay != null and overlay.visible and overlay.get_meta("cost")==5,"enemy HP bar must preview the real damage amount with the existing resource hatch")
			_check(overlay.get_node("TintFill").material.get_shader_parameter("forecast_color").is_equal_approx(Color("f4cf61")),"HP forecast must be gold against the red HP bar")
			_check(overlay.get_node("DamageAmount").text=="5","outlined number must show the same total as the damage quote")
			var hp_before: int = battle.game.player2_field.player_hp
			battle.face_mana_button.set_pressed_no_signal(false)
			battle.update_entire_screen()
			await get_tree().process_frame
			_check(overlay.get_meta("cost")==2 and battle.game.player2_field.player_hp==hp_before,"forecast must update its hatch without changing actual HP")
			_check(overlay.get_node("DamageAmount").text=="2","the number must update together with the hatch when Elixir is disabled")
			battle.face_mana_button.set_pressed_no_signal(true)
			battle.update_entire_screen()
			await get_tree().process_frame
			_check(button.tooltip_text.begins_with(Locale.t("battle.end_preview_title")), "preview title must be localized")
			_check(Locale.t("battle.end_preview_total", [5, 1, 2]) in button.tooltip_text, "preview must display damage and payment")
			_check(Locale.t("battle.end_preview_blocked", [1]) in button.tooltip_text, "preview must explain blocked attacks")
			var motion := InputEventMouseMotion.new()
			motion.position = button.get_global_rect().get_center()
			viewport.push_input(motion, true)
			await get_tree().create_timer(0.9).timeout
			var preview := viewport.find_child("EndTurnPreview", true, false) as Control
			_check(preview != null and preview.is_visible_in_tree(), "real button hover must open the custom preview")
			if preview != null:
				_check(preview.size.x <= 390 and preview.size.y < dimensions.y * 0.65, "localized preview must fit the desktop viewport")
				_check(not preview.get_global_rect().intersects(button.get_global_rect()), "the forecast must leave its action visible")
				_check(preview.get_theme_stylebox("panel") is StyleBoxFlat, "preview must use the shared panel theme")
				_check(preview.get_child(0).get_child(0).get_node_or_null("KeywordText")==null,"hover preview heading must remain literal")
			await RenderingServer.frame_post_draw
			_check(viewport.get_texture().get_image().save_png("res://artifacts/end-turn-preview/%s-%dx%d.png" % [language, dimensions.x, dimensions.y]) == OK, "preview screenshot must save")
			motion = InputEventMouseMotion.new()
			motion.position = Vector2(12, 12)
			viewport.push_input(motion, true)
			await get_tree().create_timer(0.15).timeout
			_check(viewport.find_child("EndTurnPreview", true, false) == null, "leaving the button must dismiss the preview")
			motion.position = battle.face_mana_button.get_global_rect().get_center()
			viewport.push_input(motion,true)
			await get_tree().create_timer(0.6).timeout
			var elixir_hint := battle.face_mana_button.get_node_or_null("EndTurnPreview") as Control
			_check(elixir_hint != null and elixir_hint.is_visible_in_tree(),"hovering the Elixir toggle must show its explanation")
			if elixir_hint != null:
				_check(elixir_hint.get_global_rect().end.x <= dimensions.x and elixir_hint.get_global_rect().end.y <= dimensions.y,"Elixir explanation must stay on screen")
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://artifacts/end-turn-preview/elixir-%s-%dx%d.png" % [language, dimensions.x, dimensions.y])
			viewport.remove_child(battle)
			battle.free()
		remove_child(viewport)
		viewport.free()
	Locale.language = "zh"
	if failures.is_empty():
		print("TEST_END_TURN_PREVIEW_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_END_TURN_PREVIEW_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
