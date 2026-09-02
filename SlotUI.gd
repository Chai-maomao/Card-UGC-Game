extends Button

# ============================================
# Battlefield slot — receives cards, forwards signals
# ============================================

signal slot_attack_requested
signal slot_skill1_requested
signal slot_skill2_requested
signal slot_skill3_requested
signal card_dropped_here(card_data, dragging_card_ui)

var card_ui_scene = preload("res://CardUI.tscn")
var current_card_ui = null
var current_card_data: CardData = null
var ui_scale: float = 1.0
var visual_variant: String = "player"
var _highlighted: bool = false
var _target_hint: String = "none"
var _action_glow: Panel = null
var _action_tween: Tween = null


func apply_ui_scale(scale_value: float) -> void:
	ui_scale = scale_value
	custom_minimum_size = Vector2(120, 160) * ui_scale
	size = custom_minimum_size
	if current_card_ui and is_instance_valid(current_card_ui):
		if current_card_ui.has_method("apply_ui_scale"):
			current_card_ui.call("apply_ui_scale", ui_scale)
		current_card_ui.position = Vector2.ZERO
	queue_redraw()


func _ready():
	text = ""
	_build_action_glow()
	_refresh_visual()
	apply_ui_scale(ui_scale)


func _build_action_glow() -> void:
	_action_glow = Panel.new()
	_action_glow.name = "ActionGlow"
	_action_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_glow.anchor_right = 1.0
	_action_glow.anchor_bottom = 1.0
	_action_glow.grow_horizontal = 2
	_action_glow.grow_vertical = 2
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(max(2, int(4 * ui_scale)))
	style.border_color = Color(1.0, 0.85, 0.35)
	style.set_corner_radius_all(max(4, int(8 * ui_scale)))
	_action_glow.add_theme_stylebox_override("panel", style)
	_action_glow.modulate = Color(1, 1, 1, 0.35)
	_action_glow.visible = false
	add_child(_action_glow)


func set_visual_variant(variant: String) -> void:
	visual_variant = variant
	_refresh_visual()


func _refresh_visual() -> void:
	UITheme.apply_slot(self, visual_variant, current_card_data != null)
	if _target_hint != "none" or _highlighted:
		var hovered := _target_hint == "hover" or _highlighted
		var edge := Color(0.98, 0.78, 0.28) if hovered else Color(0.20, 0.78, 0.92)
		var style := UITheme.panel_style(Color(0.035, 0.11, 0.16, 0.94), edge, 4 if hovered else 2, 8, Color(edge.r, edge.g, edge.b, 0.55), 8 if hovered else 4)
		add_theme_stylebox_override("normal", style)
		add_theme_stylebox_override("hover", style)
		add_theme_stylebox_override("pressed", style)
	queue_redraw()


func _draw() -> void:
	# Empty slots read as intentional placement sockets rather than blank cards.
	# Occupied slots stay clean so these marks never compete with card text.
	if current_card_data != null:
		return
	var accent := UITheme.COLOR_ENEMY if visual_variant == "enemy" else UITheme.COLOR_PLAYER
	var alpha := 0.50 if _target_hint == "hover" or _highlighted else (0.34 if _target_hint == "valid" else 0.18)
	var color := Color(accent.r, accent.g, accent.b, alpha)
	var pad := 13.0 * ui_scale
	var tick := 11.0 * ui_scale
	var thickness: float = maxf(1.0, 1.5 * ui_scale)
	var left := pad
	var top := pad
	var right := size.x - pad
	var bottom := size.y - pad
	# Four corner registration marks keep the middle visually quiet.
	draw_line(Vector2(left, top), Vector2(left + tick, top), color, thickness)
	draw_line(Vector2(left, top), Vector2(left, top + tick), color, thickness)
	draw_line(Vector2(right, top), Vector2(right - tick, top), color, thickness)
	draw_line(Vector2(right, top), Vector2(right, top + tick), color, thickness)
	draw_line(Vector2(left, bottom), Vector2(left + tick, bottom), color, thickness)
	draw_line(Vector2(left, bottom), Vector2(left, bottom - tick), color, thickness)
	draw_line(Vector2(right, bottom), Vector2(right - tick, bottom), color, thickness)
	draw_line(Vector2(right, bottom), Vector2(right, bottom - tick), color, thickness)
	var centre := size * 0.5
	var diamond := PackedVector2Array([
		centre + Vector2(0, -4) * ui_scale,
		centre + Vector2(4, 0) * ui_scale,
		centre + Vector2(0, 4) * ui_scale,
		centre + Vector2(-4, 0) * ui_scale,
	])
	draw_colored_polygon(diamond, Color(accent.r, accent.g, accent.b, alpha * 0.8))


# Gold frame highlight for valid drop/target slots while aiming or dragging.
func set_highlighted(highlighted: bool) -> void:
	if _highlighted == highlighted:
		return
	_highlighted = highlighted
	_refresh_visual()


func set_target_hint(valid: bool, hovered: bool = false) -> void:
	var next := "hover" if valid and hovered else ("valid" if valid else "none")
	if _target_hint == next:
		return
	_target_hint = next
	_highlighted = false
	_refresh_visual()


# Pulsing gold border shown on cards that can still act this turn.
func set_action_glow(enabled: bool) -> void:
	if _action_glow == null:
		return
	if enabled == _action_glow.visible:
		return
	if not enabled:
		_action_glow.visible = false
		if _action_tween and _action_tween.is_valid():
			_action_tween.kill()
		return
	_action_glow.visible = true
	_action_glow.modulate = Color(1, 1, 1, 0.35)
	if _action_tween and _action_tween.is_valid():
		_action_tween.kill()
	_action_tween = create_tween().set_loops()
	_action_tween.tween_property(_action_glow, "modulate:a", 0.9, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_action_tween.tween_property(_action_glow, "modulate:a", 0.35, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_card(card_data: CardData):
	if card_data != null and card_data == current_card_data and current_card_ui and is_instance_valid(current_card_ui):
		text = ""
		current_card_ui.set_card(card_data)
		apply_ui_scale(ui_scale)
		return

	clear_card()

	if card_data == null:
		text = ""
		_refresh_visual()
		return

	current_card_data = card_data
	text = ""
	var card_ui = card_ui_scene.instantiate()

	# Forward signals from CardUI
	if card_ui.has_signal("attack_requested"):
		card_ui.attack_requested.connect(func(): slot_attack_requested.emit())
	if card_ui.has_signal("skill1_requested"):
		card_ui.skill1_requested.connect(func(): slot_skill1_requested.emit())
	if card_ui.has_signal("skill2_requested"):
		card_ui.skill2_requested.connect(func(): slot_skill2_requested.emit())
	if card_ui.has_signal("skill3_requested"):
		card_ui.skill3_requested.connect(func(): slot_skill3_requested.emit())

	add_child(card_ui)
	card_ui.set_card(card_data)
	current_card_ui = card_ui
	_refresh_visual()
	apply_ui_scale(ui_scale)


func clear_card():
	text = ""
	if current_card_ui and is_instance_valid(current_card_ui):
		current_card_ui.queue_free()
	current_card_ui = null
	current_card_data = null
	_refresh_visual()


func _can_drop_data(_position: Vector2, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("card_data"):
		return false
	return true


func _drop_data(_position: Vector2, data):
	var dragging_card_ui = data["card_ui"]
	var card_data: CardData = data["card_data"] as CardData

	print("Card dropped into slot: %s" % card_data.card_name)
	set_target_hint(false)
	emit_signal("card_dropped_here", card_data, dragging_card_ui)
