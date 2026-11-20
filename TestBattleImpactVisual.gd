extends Node

var _stage: SubViewport
var _battle: Node
var _failed := false


func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)


func _ready() -> void:
	NetworkManager.close_connection()
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	Locale.language = "zh"
	GamePreferences.set_battle_playback_speed(GamePreferences.PlaybackSpeed.FAST)
	AppPreferences.values["reduced_motion"] = false
	_stage = SubViewport.new()
	_stage.size = Vector2i(1280, 720)
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_stage)
	_battle = preload("res://Main.tscn").instantiate()
	_stage.add_child(_battle)
	await get_tree().create_timer(0.55).timeout
	if _battle.tabletop == null:
		_check(false, "the test must run on the real 3D table")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://artifacts/battle-impact")
	var shielded := await _strike(5, 8, false, "blocked")
	var light := await _strike(2, 0, false, "light")
	var heavy := await _strike(5, 0, false, "heavy")
	var reduced := await _strike(5, 0, true, "reduced-motion")
	print("BATTLE_IMPACT_DISPLACEMENT ", [shielded, light, heavy, reduced])
	_check(shielded < 0.003, "absorbed damage must only show the sub-pixel resting drift")
	_check(light > 0.01 and heavy > light + 0.02, "strong hits must displace the defender more than light hits")
	_check(is_zero_approx(reduced), "reduced motion must keep the defender seated")
	if not _failed:
		print("TEST_BATTLE_IMPACT_VISUAL_OK")
	get_tree().quit(1 if _failed else 0)


func _strike(attack: int, shield: int, reduced: bool, screenshot: String) -> float:
	AppPreferences.values["reduced_motion"] = reduced
	var game = _battle.game
	game.current_player = 1
	game.is_player_turn = true
	game.turn_number = 4
	game.player_field.action_points = 30
	var attacker := CardData.new("石庭守卫", 0, 10, attack)
	var target := CardData.new("暮色哨兵", 0, 12, 0)
	target.temp_hp = shield
	game.player_field.slots[1] = attacker
	game.player2_field.slots[3] = target
	_battle.update_entire_screen()
	await get_tree().create_timer(0.35).timeout
	var source_key: int = _battle._table_key(1, 1)
	var target_key: int = _battle._table_key(2, 3)
	var table = _battle.tabletop
	var source: Dictionary = table.cards[source_key]
	var defender: Dictionary = table.cards[target_key]
	var source_tint: Color = source.top.material_override.albedo_color
	var target_tint: Color = defender.top.material_override.albedo_color
	var face_before: Texture2D = defender.top.material_override.albedo_texture
	var start := Time.get_ticks_msec()
	_battle._on_attack_requested(1)
	_battle._on_enemy_slot_clicked(3)
	var resolved_damage := maxi(0, attack - shield)
	_check(target.hp == 12 - resolved_damage and target.temp_hp == maxi(0, shield - attack),
		"the normal combat action must resolve HP and shield exactly once")
	var peak := 0.0
	var source_peak := 0.0
	var captured := false
	for frame in range(18):
		await get_tree().physics_frame
		peak = maxf(peak, (defender.root.position as Vector3).distance_to(defender.target))
		source_peak = maxf(source_peak, (source.root.position as Vector3).distance_to(source.target))
		if not captured and frame >= 4 and defender.top.material_override.albedo_texture != face_before:
			captured = true
			await RenderingServer.frame_post_draw
			_stage.get_texture().get_image().save_png("res://artifacts/battle-impact/%s.png" % screenshot)
	_check(source_peak > 0.04 if not reduced else is_zero_approx(source_peak),
		"the attacker should move toward the target only with motion enabled")
	_check(source.top.material_override.albedo_color == source_tint and defender.top.material_override.albedo_color == target_tint,
		"impact must preserve the physical card face materials")
	_check(captured and defender.face.shown_hp == 12 - resolved_damage,
		"the updated HP must reach the rendered face alongside the contact feedback")
	if not OS.get_cmdline_user_args().has("--no-audio"):
		var impacts: Array[AudioStreamPlayer] = []
		for voice in AppAudio.players:
			if voice.get_meta("sound", "") in ["punch", "heavy", "blocked"] and int(voice.get_meta("started_at", 0)) >= start:
				impacts.append(voice)
		var expected_clip := "res://res/audio/sfx/punch.wav"
		if resolved_damage == 0:
			expected_clip = "res://res/audio/cardex-blockage.mp3"
		elif resolved_damage >= 4:
			expected_clip = "res://res/audio/cardex-heavy_punch.mp3"
		_check(impacts.size() == 1 and impacts[0].bus == "SFX"
			and impacts[0].stream != null
			and impacts[0].stream.resource_path == expected_clip and is_equal_approx(impacts[0].pitch_scale, 1.0),
			"the strike must play exactly one unpitched impact on SFX: " + expected_clip)
	await get_tree().create_timer(0.75).timeout
	return peak


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("TEST_BATTLE_IMPACT_VISUAL_FAILED: " + message)
