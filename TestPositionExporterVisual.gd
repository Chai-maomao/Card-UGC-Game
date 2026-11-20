extends Node

const Position = preload("res://BattlePosition.gd")
var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.card_playtest_context = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/position-export-ui"))
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
			await get_tree().create_timer(2.0).timeout
			var exporter = battle.get_node("PositionExporter")
			battle.action_log_panel.visible = true
			for frame in range(6): await get_tree().process_frame
			_check(exporter.can_export() and not exporter.button.disabled, "settled local position must be exportable")
			_check(battle.action_log_panel.get_global_rect().encloses(exporter.button.get_global_rect()), "save button must fit the log panel")
			_check(battle.action_log_panel.get_global_rect().encloses(exporter.status.get_global_rect()), "localized status must fit the log panel")
			await _capture(viewport, "%s-%dx%d" % [language, dimensions.x, dimensions.y])
			var before: Dictionary = Position.capture(battle.game)
			_click(viewport, exporter.button.get_global_rect().get_center())
			await get_tree().create_timer(0.25).timeout
			_check(is_instance_valid(exporter.dialog) and exporter.dialog.visible, "real pointer click must open the file dialog")
			_check(not exporter.pending.is_empty(), "export must capture the chosen position")
			exporter.dialog.current_dir = ProjectSettings.globalize_path("res://artifacts/position-export-ui")
			await get_tree().process_frame
			await _capture(viewport, "%s-%dx%d-dialog" % [language, dimensions.x, dimensions.y])
			var path := "res://artifacts/position-export-ui/%s-%dx%d.json" % [language, dimensions.x, dimensions.y]
			var absolute := ProjectSettings.globalize_path(path)
			if FileAccess.file_exists(path): DirAccess.remove_absolute(absolute)
			exporter.dialog.current_path = absolute
			exporter.dialog.get_ok_button().pressed.emit()
			await get_tree().create_timer(0.25).timeout
			_check(FileAccess.file_exists(path), "confirming the file dialog must write a position file")
			if FileAccess.file_exists(path):
				var loaded := Position.read(FileAccess.get_file_as_string(path))
				_check(loaded.ok and loaded.record.state_hashes[0] == before.state_hashes[0], "UI export must restore the same state")
			_check(exporter.pending.is_empty() and exporter.status.text == Locale.t("battle.position_saved"), "export completion must clear pending state and show localized feedback")
			battle.summon_targeting = true
			_check(not exporter.can_export(), "pending skill targeting must block partial exports")
			battle.summon_targeting = false
			NetworkManager.is_online = true
			_check(not exporter.can_export(), "online battles must not export hidden opponent state")
			NetworkManager.is_online = false
			viewport.remove_child(battle)
			battle.free()
		remove_child(viewport)
		viewport.free()
	Locale.language = "zh"
	if failures.is_empty():
		print("TEST_POSITION_EXPORTER_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_POSITION_EXPORTER_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)


func _capture(viewport: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png("res://artifacts/position-export-ui/" + name + ".png") == OK, "UI evidence must save")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
