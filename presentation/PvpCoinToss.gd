extends CanvasLayer

signal finished

const CoinModel = preload("res://presentation/PvpCoinModel.gd")
const GOLD := Color("e5c38c")
const JADE := Color("9ae0d4")

var _coin: Node3D
var _stage: TextureRect
var _result: Label
var _root: Control
var _winner := 1
var _viewer := 0


func setup(winner: int, viewer: int) -> void:
	_winner = winner
	_viewer = viewer


func _init() -> void:
	layer = 165
	set_meta("popup_close_locked", true)


func _ready() -> void:
	add_to_group("battle_modal")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	UITheme.apply_overlay(shade)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	UITheme.apply_popup_frame(panel, "gold", false, true)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 30)
	for edge in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var title := Label.new()
	title.text = Locale.t("battle.coin_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 23)
	body.add_child(title)
	var line := HSeparator.new()
	UITheme.apply_separator(line)
	body.add_child(line)
	_stage = TextureRect.new()
	_stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_stage)
	_result = Label.new()
	_result.name = "OpeningPlayerResult"
	_result.custom_minimum_size.y = 36
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_title(_result, 28)
	var result_color := (UITheme.Tokens.BRASS if _winner == 1 else UITheme.Tokens.TEAL) if UITheme.Tokens.light_mode else (GOLD if _winner == 1 else JADE)
	_result.add_theme_color_override("font_color", result_color)
	body.add_child(_result)
	_create_coin_stage()
	get_viewport().size_changed.connect(_resize_stage)
	_resize_stage()
	_play.call_deferred()


func _resize_stage() -> void:
	var bounds := get_viewport().get_visible_rect().size
	var factor := clampf(minf(bounds.x / 1000.0, bounds.y / 620.0), 0.48, 1.0)
	_stage.custom_minimum_size = Vector2(352, 230) * factor


func _create_coin_stage() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 416)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_stage.texture = viewport.get_texture()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d2bea9")
	environment.environment.ambient_light_energy = 0.75
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.22
	camera.position.z = 7.0
	viewport.add_child(camera)
	_add_light(viewport, Vector3(-22, -25, 0), Color("ffe0a8"), 2.4)
	_add_light(viewport, Vector3(27, 33, 0), Color("89d4d6"), 1.3)
	_add_light(viewport, Vector3(-12, 166, 0), Color("e9c990"), 1.8)
	_coin = CoinModel.new()
	viewport.add_child(_coin)


func _add_light(parent: Node, angles: Vector3, color: Color, energy: float) -> void:
	var lamp := DirectionalLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.rotation_degrees = angles
	parent.add_child(lamp)


func _play() -> void:
	var facing := 0.0 if _winner == 1 else PI
	var animation := create_tween()
	if not bool(AppPreferences.get_value("reduced_motion")):
		_coin.position.y = -0.38
		_coin.rotation = Vector3(0.2, -0.32, -0.14)
		_root.modulate.a = 0.0
		animation.tween_property(_root, "modulate:a", 1.0, 0.17)
		animation.tween_callback(AppAudio.play.bind("swoosh"))
		animation.tween_method(_flight.bind(facing), 0.0, 1.0, 1.03)
		animation.tween_method(_settle.bind(facing), 0.0, 1.0, 0.26)
	animation.tween_callback(_show_result.bind(facing))
	animation.tween_interval(0.86)
	animation.tween_property(_root, "modulate:a", 0.0, 0.17)
	animation.tween_callback(_finish_toss)


func _show_result(facing: float) -> void:
	_coin.rotation = Vector3(-0.16, facing + 0.16, -0.035)
	_coin.position = Vector3.ZERO
	_result.text = (Locale.t("battle.coin_player_first", [_winner]) if _viewer == 0
		else Locale.t("battle.coin_you_first" if _viewer == _winner else "battle.coin_opponent_first"))


func _finish_toss() -> void:
	finished.emit()
	queue_free()


func _flight(t: float, facing: float) -> void:
	_coin.position = Vector3(0.13 * sin(PI * t), lerpf(-0.38, 0.0, t) + 1.06 * sin(PI * t), 0)
	_coin.rotation = Vector3(lerpf(0.2, -0.16, t) + 0.28 * sin(TAU * t), lerpf(-0.32, TAU * 3.0 + facing + 0.16, t), lerpf(-0.14, -0.035, t) + 0.42 * sin(PI * t))


func _settle(t: float, facing: float) -> void:
	var bounce := sin(t * TAU) * (1.0 - t)
	_coin.position.y = 0.22 * absf(bounce)
	_coin.rotation = Vector3(-0.16 + 0.44 * bounce, facing + 0.16 + 0.52 * bounce, -0.035 - 0.29 * bounce)
