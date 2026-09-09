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
var _lethal_hint: bool = false
var _action_glow: Panel = null
var _action_tween: Tween = null
var _arrival_glow: Panel = null
var _arrival_tween: Tween = null
var _card_arrival_tween: Tween = null


func apply_ui_scale(scale_value: float) -> void:
	ui_scale = scale_value
	custom_minimum_size = Vector2(120, 160) * ui_scale
	size = custom_minimum_size
	if _arrival_glow:
		_arrival_glow.offset_left = -4.0 * ui_scale
		_arrival_glow.offset_top = -4.0 * ui_scale
		_arrival_glow.offset_right = 4.0 * ui_scale
		_arrival_glow.offset_bottom = 4.0 * ui_scale
	if current_card_ui and is_instance_valid(current_card_ui):
		if current_card_ui.has_method("apply_ui_scale"):
			current_card_ui.call("apply_ui_scale", ui_scale)
		current_card_ui.position = Vector2.ZERO
	queue_redraw()


func _ready():
	text = ""
	_build_action_glow()
	_build_arrival_glow()
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


func _build_arrival_glow() -> void:
	_arrival_glow = Panel.new()
	_arrival_glow.name = "ArrivalGlow"
	_arrival_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrival_glow.anchor_right = 1.0
	_arrival_glow.anchor_bottom = 1.0
	_arrival_glow.offset_left = -4.0
	_arrival_glow.offset_top = -4.0
	_arrival_glow.offset_right = 4.0
	_arrival_glow.offset_bottom = 4.0
	_arrival_glow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_arrival_glow.grow_vertical = Control.GROW_DIRECTION_BOTH
	_arrival_glow.visible = false
	add_child(_arrival_glow)


func set_visual_variant(variant: String) -> void:
	visual_variant = variant
	if current_card_ui and is_instance_valid(current_card_ui):
		current_card_ui.set_battle_drag_enabled(visual_variant == "player")
	_refresh_visual()


func _refresh_visual() -> void:
	UITheme.apply_slot(self, visual_variant, current_card_data != null)
	if _lethal_hint:
		# Lethal affordance deliberately outranks the ordinary cyan/gold target
		# frame. A transparent fill keeps the card readable while the red outer
		# glow communicates "this action kills" at a glance.
		var lethal_edge := Color(1.0, 0.20, 0.16)
		var lethal_style := UITheme.panel_style(Color(0.10, 0.015, 0.02, 0.32), lethal_edge, 3, 8, Color(1.0, 0.08, 0.06, 0.72), 9)
		add_theme_stylebox_override("normal", lethal_style)
		add_theme_stylebox_override("hover", lethal_style)
		add_theme_stylebox_override("pressed", lethal_style)
	elif _target_hint != "none" or _highlighted:
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


func set_lethal_hint(enabled: bool) -> void:
	if _lethal_hint == enabled:
		return
	_lethal_hint = enabled
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
	# The slot itself provides the frame/depth. A second card shadow makes the
	# card look like it is hovering above the socket instead of seated in it.
	card_ui.set_embedded_in_slot(true)
	card_ui.set_battle_drag_enabled(visual_variant == "player")
	card_ui.set_card(card_data)
	current_card_ui = card_ui
	# Both frames must sit above the card face; the arrival frame is last so its
	# brief locking flash remains legible without becoming a persistent outline.
	if _action_glow:
		move_child(_action_glow, get_child_count() - 1)
	if _arrival_glow:
		move_child(_arrival_glow, get_child_count() - 1)
	_refresh_visual()
	apply_ui_scale(ui_scale)


# Called after the authoritative state has rebuilt the slot. The motion is
# deliberately short and shallow: the card seats into the socket instead of
# appearing to leap far above the battlefield.
func play_card_arrival(kind: String = "summon") -> void:
	if current_card_ui == null or not is_instance_valid(current_card_ui):
		return
	if _card_arrival_tween and _card_arrival_tween.is_valid():
		_card_arrival_tween.kill()
	var card: Control = current_card_ui
	var card_id := card.get_instance_id()
	var base_pivot: Vector2 = card.pivot_offset
	card.visible = true
	card.pivot_offset = card.size * 0.5
	card.position = Vector2(0, -9 if kind == "summon" else -4) * ui_scale
	card.rotation = deg_to_rad(-1.4 if visual_variant == "player" else 1.4)
	card.scale = Vector2.ONE * (0.90 if kind == "summon" else 0.95)
	card.modulate = Color(1.0, 1.0, 1.0, 0.76 if kind == "summon" else 0.86)
	_card_arrival_tween = create_tween()
	_card_arrival_tween.set_parallel(true)
	_card_arrival_tween.tween_property(card, "position", Vector2.ZERO, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_arrival_tween.tween_property(card, "rotation", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_arrival_tween.tween_property(card, "scale", Vector2.ONE * 1.025, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_card_arrival_tween.tween_property(card, "modulate", Color.WHITE, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_arrival_tween.chain().tween_property(card, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_arrival_tween.chain().tween_callback(_finish_card_arrival.bind(card_id, base_pivot))
	_play_arrival_glow(kind)


func _finish_card_arrival(card_id: int, base_pivot: Vector2) -> void:
	var card = instance_from_id(card_id)
	if card == null or not is_instance_valid(card):
		return
	card.position = Vector2.ZERO
	card.rotation = 0.0
	card.scale = Vector2.ONE
	card.modulate = Color.WHITE
	card.pivot_offset = base_pivot


func _play_arrival_glow(kind: String) -> void:
	if _arrival_glow == null:
		return
	if _arrival_tween and _arrival_tween.is_valid():
		_arrival_tween.kill()
	var accent := Color(0.98, 0.78, 0.28) if kind == "summon" else Color(0.30, 0.84, 1.0)
	var style := StyleBoxFlat.new()
	# Edge-only response: any filled background here sits above CardUI and reads
	# as a coloured mask over the whole card.
	style.bg_color = Color.TRANSPARENT
	style.set_border_width_all(max(2, int(3 * ui_scale)))
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.set_corner_radius_all(max(5, int(9 * ui_scale)))
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	_arrival_glow.add_theme_stylebox_override("panel", style)
	_arrival_glow.visible = true
	_arrival_glow.pivot_offset = _arrival_glow.size * 0.5
	_arrival_glow.scale = Vector2(1.07, 1.05)
	_arrival_glow.modulate.a = 0.0
	_arrival_tween = create_tween()
	_arrival_tween.set_parallel(true)
	_arrival_tween.tween_property(_arrival_glow, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arrival_tween.tween_property(_arrival_glow, "modulate:a", 1.0, 0.08)
	_arrival_tween.chain().tween_property(_arrival_glow, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_arrival_tween.chain().tween_callback(func(): _arrival_glow.visible = false)


func clear_card():
	text = ""
	if _card_arrival_tween and _card_arrival_tween.is_valid():
		_card_arrival_tween.kill()
	_card_arrival_tween = null
	if _arrival_tween and _arrival_tween.is_valid():
		_arrival_tween.kill()
	_arrival_tween = null
	if _arrival_glow:
		_arrival_glow.visible = false
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
