extends Node

const SOUNDS := ["death"]
const DENY_SOUND := "res://res/audio/cardex-ui_deny.mp3"
# The supplied file has 280 ms of silence before its transient.
const DENY_START_SECONDS := 0.26
const DENY_LEVEL_DB := -1.0
const EFFECT_FILES := {
	"punch":["punch"], "heal":["heal"], "skill":["magic_smite"],
	"dark_magic":["dark_magic"], "draw":["shuffle"],
	"draw_single":["distributing_single"],
	"shuffle":["shuffle_2","shuffle","shuffle_3"], "click":["mouse_over_menu"], "hover":["mouse_over_object"],
	"card_hover":["mouse_over_object"], "summon":["deploy_card","deploy_card_2","deploy_card_3"],
	"swoosh":["swoosh"], "discard":["deploy_card","deploy_card_2","deploy_card_3"]
}
var _effect_variants: Dictionary = {}
var _variant_index: Dictionary = {}
const MUSIC_TRACK := "res://res/audio/cardex-title.mp3"
const BATTLE_MUSIC_TRACK := "res://res/audio/cardex-battle.mp3"
const EDITOR_MUSIC_TRACKS := ["res://res/audio/cardex-card_editor_1.mp3", "res://res/audio/cardex-card_editor_2.mp3"]
const EDITOR_SCENES := ["res://MyCards.tscn", "res://CardEditor.tscn", "res://SkillEditor.tscn", "res://Workshop.tscn"]
var _editor_music_active := false
var _editor_music_index := 0
var _music_streams: Dictionary = {}
var streams: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var _music_tween: Tween
var _requested_music: AudioStreamMP3
var _quitting := false
const MUSIC_LEVEL := 0.7079458 # -3 dB; the user's volume remains on the BGM bus.
const MUSIC_FADE_OUT := 0.45
const MUSIC_FADE_IN := 1.2
var _focused := true
var _cursor := 0
var _shutting_down := false
var _last_sound: Dictionary = {}
var _hover_source_id := 0
var _hover_source_time := -1000

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_cmdline_user_args().has("--no-audio"): return
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--audio-test"): return
	if OS.get_cmdline_user_args().has("--server") or OS.get_cmdline_user_args().has("--room-server"): return
	for bus in ["BGM","SFX","UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count-1
			AudioServer.set_bus_name(index,bus)
			AudioServer.set_bus_send(index,"Master")
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -3.0
	AudioServer.add_bus_effect(0,limiter)
	for sound in SOUNDS: streams[sound] = load("res://res/audio/%s.wav" % sound)
	var denied := load(DENY_SOUND) as AudioStreamMP3
	if denied != null:
		denied.loop = false
		streams["denied"] = denied
	for sound in EFFECT_FILES:
		var variants: Array = []
		for file in EFFECT_FILES[sound]: variants.append(load("res://res/audio/sfx/%s.wav" % file))
		_effect_variants[sound] = variants
		streams[sound] = variants[0]
	streams["blocked"] = load("res://res/audio/cardex-blockage.mp3")
	streams["heavy"] = load("res://res/audio/cardex-heavy_punch.mp3")
	for i in range(12):
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	music = AudioStreamPlayer.new()
	music.bus = "BGM"
	for path in [MUSIC_TRACK, BATTLE_MUSIC_TRACK] + EDITOR_MUSIC_TRACKS:
		var track := load(path) as AudioStreamMP3
		if track != null:
			track.loop = path not in EDITOR_MUSIC_TRACKS
			_music_streams[path] = track
	music.volume_db = -40
	add_child(music)
	music.finished.connect(_on_music_finished)
	AppPreferences.changed.connect(func(_key): _apply_levels())
	_apply_levels()
	get_tree().node_added.connect(_hook_button)
	get_tree().scene_changed.connect(_scene_music)
	_scene_music.call_deferred()

func _hook_button(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(func(): play("click","SFX"))
		node.mouse_entered.connect(func():
			if not node.disabled and not _inside_card(node): play_hover(node))

func play_hover(source: Control, card: bool = false) -> void:
	if source == null or not source.is_inside_tree() or source.get_viewport().gui_is_dragging(): return
	# Card children and selection overlays describe the same hovered card.
	var identity := source
	var ancestor: Node = source
	while ancestor != null:
		if ancestor is Control and ancestor.has_method("set_card") and ancestor.has_method("set_battle_layout_preview"):
			identity = ancestor
			break
		ancestor = ancestor.get_parent()
	var now := Time.get_ticks_msec()
	if identity.get_instance_id() == _hover_source_id and now-_hover_source_time < 40: return
	_hover_source_id = identity.get_instance_id()
	_hover_source_time = now
	play("card_hover" if card else "hover")

func _inside_card(node: Node) -> bool:
	while node != null:
		if node.has_method("set_card") and node.has_method("set_battle_layout_preview"): return true
		node = node.get_parent()
	return false

func _scene_music() -> void:
	if _shutting_down or _quitting or music == null: return
	var scene := get_tree().current_scene
	if scene == null: return
	var editing := scene.scene_file_path in EDITOR_SCENES
	if editing and not _editor_music_active: _editor_music_index = 0
	_editor_music_active = editing
	var path: String = EDITOR_MUSIC_TRACKS[_editor_music_index] if editing else (BATTLE_MUSIC_TRACK if scene.has_method("_show_abandon_confirmation") else MUSIC_TRACK)
	var track := _music_streams.get(path) as AudioStreamMP3
	if track == null: return
	if _requested_music == track and music.playing: return
	_requested_music = track
	if _music_tween != null: _music_tween.kill()
	if music.stream == track and music.playing:
		_fade_music_in()
	elif music.playing and music.volume_linear > 0.001:
		_music_tween = create_tween()
		_music_tween.tween_property(music,"volume_linear",0.0,MUSIC_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_music_tween.tween_callback(_start_requested_music)
	else:
		_start_requested_music()

func _on_music_finished() -> void:
	if _shutting_down or _quitting or not _editor_music_active: return
	if music.stream != _requested_music: return
	_editor_music_index = (_editor_music_index + 1) % EDITOR_MUSIC_TRACKS.size()
	_requested_music = _music_streams.get(EDITOR_MUSIC_TRACKS[_editor_music_index]) as AudioStreamMP3
	if _requested_music == null: return
	if _music_tween != null: _music_tween.kill()
	_start_requested_music()

func _start_requested_music() -> void:
	if _shutting_down or _quitting or music == null: return
	music.stop()
	music.stream = _requested_music
	music.volume_linear = 0.0
	music.play()
	_fade_music_in()

func _fade_music_in() -> void:
	_music_tween = create_tween()
	_music_tween.tween_property(music,"volume_linear",MUSIC_LEVEL,MUSIC_FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func quit_to_desktop() -> void:
	if _quitting: return
	_quitting = true
	if _music_tween != null: _music_tween.kill()
	if music == null or not music.playing:
		get_tree().quit()
		return
	_music_tween = create_tween()
	_music_tween.tween_property(music,"volume_linear",0.0,MUSIC_FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_music_tween.tween_callback(func(): get_tree().quit())

func _apply_levels() -> void:
	for pair in [["Master","master"],["BGM","bgm"],["SFX","sfx"],["UI","ui"]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index < 0: continue
		AudioServer.set_bus_volume_db(index,linear_to_db(maxf(0.0001,float(AppPreferences.get_value(pair[1])))))
	AudioServer.set_bus_mute(0,bool(AppPreferences.get_value("mute")))
	AudioServer.set_bus_volume_db(0,AudioServer.get_bus_volume_db(0)+(0 if _focused else -15))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _focused = false; _apply_levels()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: _focused = true; _apply_levels()

func play(sound: String, bus: String = "SFX") -> void:
	if sound in ["attack","hurt"]: sound = "punch"
	if sound == "error": sound = "denied"
	# One rejection sound uses one mixer setting in editors and battles alike.
	if sound == "denied": bus = "SFX"
	if _shutting_down or players.is_empty() or not streams.has(sound): return
	var now := Time.get_ticks_msec()
	var cooldown := 300 if sound in ["denied","heal","skill","dark_magic"] else (0 if sound in ["hover","card_hover"] else (220 if sound in ["draw","shuffle"] else 65))
	var cooldown_key := "hover" if sound == "card_hover" else sound
	if now-int(_last_sound.get(cooldown_key,-1000)) < cooldown: return
	_last_sound[cooldown_key] = now
	var player := players[_cursor]
	_cursor = (_cursor+1)%players.size()
	player.stop()
	player.bus = bus
	var variants: Array = _effect_variants.get(sound,[streams[sound]])
	var variant := int(_variant_index.get(sound,0)) % variants.size()
	player.stream = variants[variant]
	_variant_index[sound] = variant+1
	player.set_meta("sound",sound)
	player.set_meta("started_at",now)
	if sound == "denied":
		for other in players:
			if other != player and other.playing and other.get_meta("sound","") == "denied": other.stop()
	player.volume_db = DENY_LEVEL_DB if sound == "denied" else (-18 if sound in ["hover","card_hover","swoosh"] else -13)
	if sound == "heavy":
		player.volume_db = -10.0
	# Let short transients finish instead of cutting them off on every entry.
	# A small voice limit prevents a rapid sweep from accumulating loudness.
	if sound in ["hover","card_hover"]:
		var active: Array[AudioStreamPlayer] = []
		for other in players:
			if other != player and other.playing and other.get_meta("sound","") in ["hover","card_hover"]: active.append(other)
		active.sort_custom(func(a,b): return int(a.get_meta("started_at",0)) < int(b.get_meta("started_at",0)))
		while active.size() >= 3: active.pop_front().stop()
	player.play(DENY_START_SECONDS if sound == "denied" else 0.0)

func _exit_tree() -> void:
	_shutting_down = true
	if _music_tween != null: _music_tween.kill()
	for player in players:
		player.stop()
		player.stream = null
	if music != null:
		music.stop()
		music.stream = null
	streams.clear()
	_effect_variants.clear()
	_music_streams.clear()
