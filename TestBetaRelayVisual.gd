extends Node

var failures: Array[String] = []

func _ready() -> void:
	NetworkManager.use_isolated_session_storage("beta-ui")
	NetworkManager.clear_room_session()
	var original_language: String = Locale.language
	var output := "res://artifacts/cloudflare-migration-20261021/screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for language in ["zh", "en"]:
		Locale.language = language
		for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
			get_window().size = dimensions
			await get_tree().process_frame
			for scene in ["MultiplayerMenu", "Lobby", "BetaLobby"]:
				var ui: Control = load("res://%s.tscn" % scene).instantiate()
				add_child(ui)
				await get_tree().create_timer(0.8).timeout
				var panel: Control = ui.get_node("Panel") if scene != "MultiplayerMenu" else ui.get_node("CenterContainer/MultiplayerPanel")
				var viewport := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
				if not viewport.encloses(panel.get_global_rect()):
					failures.append("%s %s %s panel overflow: %s" % [scene, language, dimensions, panel.get_global_rect()])
				if scene != "MultiplayerMenu":
					ui.ip_input.text = "INVALID!"
					ui._on_join_pressed()
					assert(ui.status_label.text == Locale.t("beta.invalid_code"))
					ui._apply_texts()
					ui.ip_input.clear()
				else:
					assert(not ui.server_btn.is_visible_in_tree() and not ui.beta_btn.is_visible_in_tree(), "web relay entries are temporarily withdrawn")
					assert(ui.dedicated_btn.is_visible_in_tree() and ui.direct_btn.is_visible_in_tree())
					assert(ui.dedicated_btn.get_index() < ui.direct_btn.get_index(), "dedicated server stays first")
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%s-%s-%dx%d.png" % [output, scene, language, dimensions.x, dimensions.y])
				ui.queue_free()
				await get_tree().process_frame
	Locale.language = original_language
	if failures.is_empty():
		print("TEST_BETA_RELAY_VISUAL_OK")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
