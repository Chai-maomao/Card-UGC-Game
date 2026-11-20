extends Node

func _ready() -> void:
	await get_tree().scene_changed
	await get_tree().create_timer(1.5).timeout
	var failures: Array[String] = []
	for path in ["res://Main.tscn","res://MainMenu.tscn","res://CardEditor.tscn","res://SkillEditor.tscn","res://SettingsMenu.tscn","res://Workshop.tscn","res://res/audio/cardex-card_editor_1.mp3","res://res/audio/cardex-card_editor_2.mp3","res://res/fonts/NotoSansSC.ttf","res://res/audio/cardex-title.mp3","res://res/audio/cardex-battle.mp3","res://res/audio/cardex-ui_deny.mp3","res://res/tabletop/title-dice.png","res://res/tabletop/title-wheel.png"]:
		if ResourceLoader.load(path) == null: failures.append("missing resource: "+path)
	for path in ["res://legal/PRIVACY.md","res://legal/TERMS.md","res://legal/UGC.md","res://legal/GODOT_LICENSE.txt","res://legal/GODOT_COPYRIGHT.txt","res://res/fonts/OFL.txt","res://LICENSE"]:
		if FileAccess.get_file_as_string(path).is_empty(): failures.append("missing document: "+path)
	var workshop_config = JSON.parse_string(FileAccess.get_file_as_string("res://workshop_config.json"))
	if not workshop_config is Dictionary or not workshop_config.get("url", null) is String:
		failures.append("missing or invalid workshop configuration")
	var roots = JSON.parse_string(FileAccess.get_file_as_string("res://res/network/cacert-source.json"))
	if not roots is Dictionary or FileAccess.get_sha256("res://res/network/cacert.pem") != roots.get("sha256",""):
		failures.append("bundled HTTPS public roots failed integrity check")
	if OS.get_cmdline_user_args().has("--release-network-smoke"):
		var request := HTTPRequest.new()
		request.timeout = 15
		add_child(request)
		if request.request(CloudRelayConfig.server_url()+"/api/health") != OK:
			failures.append("public HTTPS health request did not start")
		else:
			var response: Array = await request.request_completed
			if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200: failures.append("public HTTPS health validation failed")
		request.queue_free()
	if not UITheme.regular_font().has_char("战".unicode_at(0)): failures.append("missing CJK glyph")
	var probe := "user://release-self-check.tmp"
	var file := FileAccess.open(probe,FileAccess.WRITE)
	if file == null: failures.append("user folder is not writable")
	else:
		file.store_string(AppVersion.VERSION)
		file.close()
		if FileAccess.get_file_as_string(probe) != AppVersion.VERSION: failures.append("user write verification failed")
		DirAccess.remove_absolute(probe)
	if not OS.has_feature("editor"):
		for path in ["res://TestBattleRepro.gd","res://tests/integration/reconnect_client.gd","res://tests/VisualBattleInput.gd","res://RunComebackBenchmark.tscn","res://artifacts/release-readiness-20261112/WORK_STATE.json"]:
			if FileAccess.file_exists(path) or ResourceLoader.exists(path): failures.append("test artifact exported: "+path)
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://MainMenu.tscn": failures.append("default menu did not open")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smoke-capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--smoke-capture="))
	var report := {"version":AppVersion.VERSION,"protocol":AppVersion.PROTOCOL_VERSION,"renderer":RenderingServer.get_current_rendering_method(),"failures":failures}
	DirAccess.make_dir_recursive_absolute("user://logs")
	var evidence := FileAccess.open("user://logs/release-self-check.json",FileAccess.WRITE)
	if evidence != null:
		evidence.store_string(JSON.stringify(report))
		evidence.close()
	print("RELEASE_SELF_CHECK ",JSON.stringify(report))
	AppAudio._exit_tree()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
