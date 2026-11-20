class_name SkillBlock
extends PanelContainer

# ============================================
# Scratch-style skill block.
# - Event block: hat container "当 攻击时" wrapping the whole skill body.
# - Effect block: colored stack block with sentence + badges.
# - if/else block: C-shaped wrapper with then/else slots.
# - Stop block: red "跳出当前条件" that halts the current block.
# Blocks are identified by a path into the skill effect tree so nested
# children can be edited the same way as top-level effects.
# ============================================

const UITheme = preload("res://UITheme.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _CondReporter = preload("res://SkillConditionReporter.gd")

signal edit_requested(path: Array)
signal delete_requested(path: Array)
signal move_requested(path: Array, offset: int)
signal drop_requested(from_path: Array, to_path: Array, insert_after: bool, data)
signal changed(path: Array)             # inline parameter edited
signal context_requested(path: Array, at: Vector2)  # right-click menu
signal condition_dropped(path: Array, cond: Dictionary, from_path: Array)  # condition dropped into the if slot
signal condition_inserted(path: Array, socket_path: Array, payload: Dictionary)
signal insertion_requested(parent_vbox: VBoxContainer, index: int)  # show insertion line while hovering this block
signal insertion_hidden()  # dragging left the block (or it can't accept a drop)

var effect_path: Array = []
var is_hat: bool = false
var draggable: bool = true
var _effect: Dictionary = {}
var _sentence_row: HBoxContainer
var _sentence_refresh_pending := false
var has_else: bool = false
var body_container: VBoxContainer
var then_container: VBoxContainer
var else_container: VBoxContainer
var cond_slot: PanelContainer
var _drag_highlight: bool = false
var _base_bg := Color(0.26, 0.50, 0.68)
var _base_radius: int = 6
var _has_socket_notch: bool = false
var _motion_installed: bool = false
var _dragging: bool = false
var _motion_tween: Tween
var _press_shadow_alpha: float = 0.0
var _press_tween: Tween
var _validation_markers: Array[Node] = []

func _init() -> void:
	set_meta("keyword_literal_fields",true)
	# Each stack block follows its own content width. C-shaped blocks still
	# grow around their children through the normal minimum-size propagation.
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _ready() -> void:
	if get_meta("drag_preview",false):
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for control in find_children("*","Control",true,false): control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	# Structural containers must not intercept drags from the block's label or
	# empty face. Scripted value/target/condition controls keep their own input.
	for control in find_children("*", "Container", true, false):
		if control.get_script() == null:
			control.mouse_filter = Control.MOUSE_FILTER_PASS


static func category_color(category: String) -> Color:
	match category:
		"attack":
			return Color(0.64, 0.18, 0.25)  # crimson — damage / offense
		"defense":
			return Color(0.14, 0.46, 0.34)  # emerald — heal / buffs
		"utility":
			return Color(0.16, 0.38, 0.64)  # sapphire — hand / resources
		"status":
			return Color(0.48, 0.28, 0.60)
	return Color(0.42, 0.28, 0.58)         # purple — advanced / default


static func trigger_color() -> Color:
	return Color(0.68, 0.40, 0.10)  # amber — events / triggers


static func control_color() -> Color:
	return Color(0.70, 0.32, 0.12)  # orange — control / branching


static func stop_color() -> Color:
	return Color(0.64, 0.12, 0.18)  # red — stop


static func repeat_color() -> Color:
	return Color(0.40, 0.25, 0.64)  # violet — repeat / loop


static func condition_color() -> Color:
	return Color(0.08, 0.48, 0.48)  # teal — condition reporters


static func math_color() -> Color:
	return Color(0.48, 0.27, 0.66)  # purple — numeric expressions

static func random_color() -> Color:
	return Color(0.16, 0.38, 0.64)


static func target_color() -> Color:
	return Color(0.12, 0.48, 0.72)  # cyan-blue — target reporters


static func side_color() -> Color:
	return Color(0.62, 0.40, 0.12)  # ochre — side reporters


func _apply_style(bg: Color, radius: int = 6) -> void:
	_base_bg = bg
	_base_radius = radius
	_apply_rest_style()
	_install_motion()


func _make_block_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_SOFT.lerp(bg, 0.78)
	# Stacked blocks sit almost flush. An outward StyleBox shadow from the
	# lower sibling is drawn over the block above it, producing a dark centre
	# with an unnaturally bright rim. Keep script blocks shadow-free and use a
	# restrained dark edge for depth instead.
	style.border_color = bg.darkened(0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(_base_radius)
	style.shadow_size = 0
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _apply_rest_style() -> void:
	var style := _make_block_style(_base_bg)
	if _has_socket_notch:
		style.border_width_left = 1
		style.border_color = _base_bg.darkened(0.28)
	add_theme_stylebox_override("panel", style)
	if _has_socket_notch or _effect.get("effect") == SkillEngine.EFFECT_STOP:
		add_theme_stylebox_override("panel", preload("res://SkillSocketStyle.gd").from_flat(style, "terminal" if _effect.get("effect") == SkillEngine.EFFECT_STOP else "stack"))

func _process(_delta: float) -> void:
	if not _has_socket_notch: return
	var style = get_theme_stylebox("panel")
	if style.get_script() != preload("res://SkillSocketStyle.gd"): return
	var gaps: Array[Rect2] = []
	for body in [then_container, else_container]:
		if is_instance_valid(body):
			gaps.append(Rect2(get_global_transform().affine_inverse() * body.global_position, body.size))
	if style.cavities != gaps:
		style.cavities = gaps
		queue_redraw()


func _install_motion() -> void:
	if _motion_installed:
		return
	_motion_installed = true
	resized.connect(_update_motion_pivot)
	mouse_entered.connect(_on_block_mouse_entered)
	mouse_exited.connect(_on_block_mouse_exited)
	call_deferred("_play_appear_motion")


func _update_motion_pivot() -> void:
	pivot_offset = Vector2.ZERO if get_meta("drag_preview", false) else size * 0.5


func _play_appear_motion() -> void:
	if not is_inside_tree() or get_meta("drag_preview",false) or has_meta("skill_workspace"):
		return
	_update_motion_pivot()
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.14)


func _on_block_mouse_entered() -> void:
	if is_hat or _dragging or (get_viewport() != null and get_viewport().gui_is_dragging()):
		return
	_animate_motion(Vector2.ONE, Color(1.035, 1.035, 1.035, 1.0), 0.10)


func _on_block_mouse_exited() -> void:
	if _dragging:
		return
	_animate_motion(Vector2.ONE, Color.WHITE, 0.10)


func _animate_motion(target_scale: Vector2, target_modulate: Color, duration: float) -> void:
	_update_motion_pivot()
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "scale", target_scale, duration)
	_motion_tween.tween_property(self, "modulate", target_modulate, duration)


func _play_drop_pulse() -> void:
	_update_motion_pivot()
	modulate = Color(1.10, 1.10, 1.10, 1.0)
	_animate_motion(Vector2.ONE, Color.WHITE, 0.16)


func _draw() -> void:
	if _press_shadow_alpha <= 0.001:
		return
	# Reuse the material's current outline, including live C-shaped cavities.
	# A separate rectangle misses the connector and paints across the opening.
	var shading: StyleBox = get_theme_stylebox("panel").duplicate()
	var tint := Color(0.015,0.02,0.03,0.24*_press_shadow_alpha)
	if shading.get_script() == preload("res://SkillSocketStyle.gd"):
		shading.cavities = get_theme_stylebox("panel").cavities.duplicate()
		shading.fill = tint
		shading.edge = Color.TRANSPARENT
	elif shading is StyleBoxFlat:
		shading.bg_color = tint
		shading.border_color = Color.TRANSPARENT
		shading.shadow_size = 0
	else:
		return
	draw_style_box(shading,Rect2(Vector2.ZERO,size))


func _set_press_shadow_alpha(value: float) -> void:
	_press_shadow_alpha = value
	queue_redraw()


func _set_press_shadow(on: bool, immediate: bool = false) -> void:
	if is_hat:
		return
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	var target_alpha := 1.0 if on else 0.0
	if immediate:
		_set_press_shadow_alpha(target_alpha)
		return
	_press_tween = create_tween()
	_press_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press_tween.tween_method(_set_press_shadow_alpha, _press_shadow_alpha, target_alpha, 0.045 if on else 0.08)


# Puzzle "socket" cue: a thicker, darker bottom edge suggests the notch where
# the next block plugs in, so stacked blocks read as one connected script
# instead of loose cards. Blocks that stack below keep the notch; the event
# hat (top of the stack) and the stop block do not.
func _apply_socket_notch() -> void:
	_has_socket_notch = true
	_apply_rest_style()


func _make_label(text: String, size: int = 13) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", maxi(14, size))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	# Single-line by default: autowrap inside an HBox collapses the minimum
	# width to 1px and inflates the row height (text becomes invisible).
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Decorative text must not become the drag target. Ignoring pointer hits
	# keeps the enclosing block's valid-drop outline stable over its full area.
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_icon_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(30, 24)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
	# Pill buttons: faint translucent capsule with a visible edge, so the row
	# of CJK action labels reads as clickable controls (plain text was
	# indistinguishable from the block title).
	var normal_st := StyleBoxFlat.new()
	normal_st.bg_color = Color(1, 1, 1, 0.06)
	normal_st.border_color = Color(1, 1, 1, 0.18)
	normal_st.set_border_width_all(1)
	normal_st.set_corner_radius_all(4)
	normal_st.content_margin_left = 6
	normal_st.content_margin_right = 6
	normal_st.content_margin_top = 2
	normal_st.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", normal_st)
	var hover_st: StyleBoxFlat = normal_st.duplicate()
	hover_st.bg_color = Color(1, 1, 1, 0.16)
	btn.add_theme_stylebox_override("hover", hover_st)
	var pressed_st: StyleBoxFlat = normal_st.duplicate()
	pressed_st.bg_color = Color(1, 1, 1, 0.07)
	btn.add_theme_stylebox_override("pressed", pressed_st)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The button remains clickable, while drag/drop lookup can continue to the
	# enclosing block instead of making its cyan outline flicker off.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.tooltip_text = text
	return btn


# Order is conveyed by the connected stack itself.
func set_order(_n: int) -> void:
	pass


# Action row shared by effect / if / stop blocks. Uses plain CJK labels —
# the previous ↑/↓/⚙/✕ glyphs are not covered by Godot's default font and
# collapsed into invisible slivers.
func _build_action_buttons(head: HBoxContainer, _with_edit: bool = true) -> void:
	var more := _make_icon_button(Locale.t("skill_editor.more"))
	more.pressed.connect(func(): context_requested.emit(effect_path, more.get_global_rect().end))
	head.add_child(more)


# A recessed slot that nested blocks are stacked into (C-shaped nesting).
# Creates a dark PanelContainer attached to `parent`, then returns its inner
# VBox so blocks are stacked inside the recessed panel. The slot keeps a
# minimum height so an empty slot stays visible and hittable for the first
# drag-drop (otherwise it collapses to a sliver and drops miss it).
func _make_slot(parent: Node, event_body := false) -> VBoxContainer:
	var slot := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color.TRANSPARENT
	st.set_corner_radius_all(5)
	st.content_margin_left = 0 if event_body else 12
	st.content_margin_right = 0
	st.content_margin_top = 0
	st.content_margin_bottom = 0 if event_body else 8
	slot.add_theme_stylebox_override("panel", st)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.custom_minimum_size = Vector2(0, 30)
	parent.add_child(slot)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", -preload("res://SkillSocketStyle.gd").JOIN_OVERLAP)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not event_body:
		# Keep the cavity the same size when the last child is hidden or removed.
		inner.custom_minimum_size.y = 36
	slot.add_child(inner)
	return inner


# Event hat container: "当 攻击时" wrapping the whole skill body.
func setup_event_block(trigger_key: String, trigger_side: String = SkillEngine.TARGET_SIDE_ALL) -> void:
	tooltip_text = SkillHelp.description("trigger", trigger_key)
	is_hat = true
	_apply_style(trigger_color(), 10)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", -preload("res://SkillSocketStyle.gd").JOIN_OVERLAP)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)
	var name_text: String = Locale.term("trigger", trigger_key)
	if trigger_key == SkillEngine.TRIGGER_ON_BOARD_CHANGED:
		name_text = Locale.t("skill_editor.board_change_trigger", [Locale.term("board_side", trigger_side)])
	var heading := _make_label(Locale.t("skill_editor.block_trigger", [name_text]), 15)
	heading.set_meta("keyword_literal",true)
	var cap := PanelContainer.new()
	cap.custom_minimum_size.x = 130
	cap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cap.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := _make_block_style(trigger_color())
	style.content_margin_top = 18
	style.content_margin_bottom = 10
	style.content_margin_right = 24
	cap.add_theme_stylebox_override("panel", preload("res://SkillSocketStyle.gd").from_flat(style, "hat"))
	cap.add_child(heading)
	outer.add_child(cap)
	body_container = _make_slot(outer, true)


# Trigger hat block (standalone, used when the event block is hidden).
func setup_hat(trigger_key: String) -> void:
	tooltip_text = SkillHelp.description("trigger", trigger_key)
	is_hat = true
	_apply_style(trigger_color())
	var style := _make_block_style(trigger_color())
	style.content_margin_top = 18
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", preload("res://SkillSocketStyle.gd").from_flat(style, "hat"))
	custom_minimum_size.x = 130
	var name_text: String = Locale.term("trigger", trigger_key)
	var heading := _make_label(Locale.t("skill_editor.block_trigger", [name_text]), 15)
	heading.set_meta("keyword_literal",true)
	add_child(heading)


# Effect block: one sentence with typed parameter sockets and a command menu.
func setup_effect(eff: Dictionary, path: Array) -> void:
	effect_path = path
	_effect = eff
	var effect_id: String = eff.get("effect", "")
	tooltip_text = SkillHelp.description("effect", effect_id)
	var category: String = SkillRegistry.palette_category(effect_id)
	_apply_style(category_color(category))
	_apply_socket_notch()
	mouse_default_cursor_shape = Control.CURSOR_DRAG

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)

	_sentence_row = _build_sentence_row(eff)
	_build_action_buttons(_sentence_row)
	box.add_child(_sentence_row)

	var badges := _effect_badges(eff)
	if not badges.is_empty():
		var badge_row := HFlowContainer.new()
		badge_row.add_theme_constant_override("h_separation", 4)
		badge_row.add_theme_constant_override("v_separation", 3)
		for b in badges:
			badge_row.add_child(_make_badge(b))
		box.add_child(badge_row)


# Builds the sentence line: static text labels and inline parameter controls
# (target dropdown, value slot, buff dropdown, duration spinbox). The row is
# single-line; long reporters widen the block, and the script area's
# horizontal scroll bar reveals the overflow (no ugly auto-wrapping).
func _build_sentence_row(eff: Dictionary) -> HBoxContainer:
	SkillRegistry.normalize_editor_value(eff)
	tooltip_text = SkillHelp.description("buff", str(eff.get("buff_id", ""))) if eff.get("effect") == SkillEngine.EFFECT_ADD_BUFF else SkillHelp.description("effect", str(eff.get("effect", "")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var effect_id: String = str(eff.get("effect", ""))
	var tokens: Array = _TextFormatter.effect_sentence_tokens(eff)
	for t in tokens:
		var type: String = t.get("type", "text")
		match type:
			"text":
				var lbl := _make_label(t.get("text", ""), 13)
				# Autowrap inside an HBox collapses the minimum width (text becomes
				# invisible); keep one line so the label keeps its natural width.
				lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
				lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				lbl.custom_minimum_size.y = 24
				row.add_child(lbl)
			"target":
				# Target selector slots: [友方/敌方] [目标], both accepting
				# dragged-in reporter ovals (side_block / target_block).
				var side_slot := TargetSlot.new()
				side_slot.setup(eff, "side")
				side_slot.changed.connect(_on_param_changed)
				row.add_child(side_slot)
				var tgt_slot := TargetSlot.new()
				tgt_slot.setup(eff, "target")
				tgt_slot.changed.connect(_on_param_changed)
				row.add_child(tgt_slot)
				# The side chip only appears for targets that actually split by
				# faction (单体/目标+相邻/全部/性别); self / self+adjacent targets
				# have no faction dimension, and an unset target shows just the
				# empty target socket.
				var _sync_side := func():
					var tgt: String = str(eff.get("target", ""))
					var needs_side: bool = tgt in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES,
							SkillEngine.TARGET_ALL, SkillEngine.TARGET_PLAYER, SkillEngine.TARGET_MALE,
							SkillEngine.TARGET_FEMALE, SkillEngine.TARGET_NONHUMAN]
					side_slot.visible = needs_side
					if tgt in [SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES] and eff.get("target_side") != SkillEngine.TARGET_SIDE_ALL:
						eff["target_side"] = SkillEngine.TARGET_SIDE_ALL
						side_slot._rebuild()
				_sync_side.call()
				tgt_slot.selection_updated.connect(_sync_side)
			"value":
				# Scratch-style: the value slot accepts a variable reporter
				# oval or a nested math-expression reporter.
				var slot := ValueSlot.new()
				slot.clamp_input = SkillRegistry.percentage_value(eff)
				slot.setup(eff, "value", "value_var", "", SkillRegistry.allows_negative(effect_id), 100.0 if slot.clamp_input else 999.0, "value_expr", "value_offset")
				slot.changed.connect(_on_param_changed)
				row.add_child(slot)
			"draw":
				row.add_child(_make_number_spin(eff, "draw"))
			"buff":
				row.add_child(_make_buff_option(eff))
			"duration":
				row.add_child(_make_number_spin(eff, "duration"))
			"cost_mode":
				row.add_child(_make_cost_mode_option(eff))
	return row


func _make_param_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.22)
	st.border_color = Color(1, 1, 1, 0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	return st


# Inline parameter controls keep mouse_filter PASS: they stay fully clickable /
# editable (PASS controls receive events) while drag-drop resolution is allowed
# to walk through them to the enclosing slot/block. STOP controls swallow the
# drop entirely in this engine (observed repeatedly), breaking block nesting.
func _set_param_pass(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	if c is SpinBox:
		var le: LineEdit = c.get_line_edit()
		if le != null:
			le.mouse_filter = Control.MOUSE_FILTER_PASS


func _make_buff_option(eff: Dictionary) -> OptionButton:
	var opt := OptionButton.new()
	opt.add_theme_stylebox_override("normal", _make_param_style())
	opt.add_theme_stylebox_override("hover", _make_param_style())
	opt.add_theme_stylebox_override("pressed", _make_param_style())
	opt.add_theme_color_override("font_color", Color.WHITE)
	opt.add_theme_font_size_override("font_size", 14)
	preload("res://SkillStatusPicker.gd").fill(opt, str(eff.get("buff_id", SkillEngine.BUFF_ATK_BOOST)))
	opt.tooltip_text = SkillHelp.description("buff", str(eff.get("buff_id", "")))
	opt.item_selected.connect(func(_i: int):
		_effect["buff_id"] = preload("res://SkillStatusPicker.gd").value(opt)
		SkillRegistry.normalize_editor_value(_effect)
		_on_param_changed()
		if not _sentence_refresh_pending:
			_sentence_refresh_pending = true
			_refresh_sentence_row.call_deferred()
	)
	_set_param_pass(opt)
	return opt

func _refresh_sentence_row() -> void:
	_sentence_refresh_pending = false
	if not is_instance_valid(_sentence_row): return
	var parent := _sentence_row.get_parent()
	var index := _sentence_row.get_index()
	parent.remove_child(_sentence_row)
	_sentence_row.queue_free()
	_sentence_row = _build_sentence_row(_effect)
	_build_action_buttons(_sentence_row)
	parent.add_child(_sentence_row)
	parent.move_child(_sentence_row, index)


func _make_cost_mode_option(eff: Dictionary) -> OptionButton:
	var opt := OptionButton.new()
	for style_name in ["normal", "hover", "pressed"]:
		opt.add_theme_stylebox_override(style_name, _make_param_style())
	opt.add_theme_color_override("font_color", Color.WHITE)
	opt.add_theme_font_size_override("font_size", 14)
	for i in range(SkillRegistry.COST_REDUCTION_MODES.size()):
		var mode: String = SkillRegistry.COST_REDUCTION_MODES[i]
		opt.add_item(Locale.term("cost_reduction_mode", mode), i)
	opt.selected = _idx_of(str(eff.get("cost_reduction_mode", SkillRegistry.COST_REDUCTION_TURN)), SkillRegistry.COST_REDUCTION_MODES)
	opt.item_selected.connect(func(_i: int):
		_effect["cost_reduction_mode"] = SkillRegistry.COST_REDUCTION_MODES[opt.selected]
		_on_param_changed()
	)
	_set_param_pass(opt)
	return opt


# Inline numeric parameter (value / draw / duration / repeat count).
func _make_number_spin(eff: Dictionary, kind: String) -> SpinBox:
	var spin := SpinBox.new()
	preload("res://SkillSocketStyle.gd").compact_number(spin)
	spin.add_theme_stylebox_override("normal", _make_param_style())
	spin.add_theme_font_size_override("font_size", 14)
	spin.custom_minimum_size = Vector2(58, 24)
	spin.allow_greater = true
	match kind:
		"value":
			if SkillRegistry.allows_negative(str(eff.get("effect", ""))):
				spin.min_value = -999.0
			else:
				spin.min_value = 0.0
			spin.max_value = 999.0
			spin.value = float(int(eff.get("value", 1)))
		"draw":
			spin.min_value = 0.0
			spin.max_value = 20.0
			spin.value = float(int(eff.get("random_count", 0)))
		"duration":
			spin.min_value = 1.0
			spin.max_value = 99.0
			spin.value = float(int(eff.get("duration", 0)))
		"repeat":
			spin.min_value = 0.0
			spin.max_value = 20.0
			spin.value = float(int(eff.get("repeat_count", 2)))
	var line_edit: LineEdit = spin.get_line_edit()
	if line_edit != null:
		line_edit.add_theme_stylebox_override("normal", _make_param_style())
		line_edit.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
		line_edit.add_theme_font_size_override("font_size", 14)
		line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.value_changed.connect(func(v: float):
		match kind:
			"value":
				_effect["value"] = int(v)
			"draw":
				_effect["random_count"] = int(v)
			"duration":
				_effect["duration"] = int(v)
			"repeat":
				_effect["repeat_count"] = int(v)
		_on_param_changed()
	)
	_set_param_pass(spin)
	return spin


# Inline per-effect trigger probability (0-100%) is tuned in the config form
# (SkillEffectForm); non-default values surface as badges. No inline control
# is rendered in the block header to keep it clean.


# ============================================
# Inline parameter edits
# ============================================

func _on_param_changed() -> void:
	# Inline parameter edits mutate the shared effect dict directly. The
	# sentence row keeps a fixed structure (static labels + self-updating
	# controls), so no full row rebuild is needed here — rebuilding would
	# release the focused SpinBox and drop subsequent keystrokes (typing a
	# multi-digit value only kept the first digit). The editor's changed
	# handler refreshes the summary and pushes the undo snapshot instead.
	changed.emit(effect_path)


func _idx_of(key: String, keys: Array) -> int:
	var i := keys.find(key)
	return i if i >= 0 else 0


# if / if-else control block (C-shaped): "如果 [条件] 那么" header with a
# condition reporter slot, plus an optional else slot for EFFECT_IF_ELSE.
func setup_if_else(eff: Dictionary, path: Array) -> void:
	tooltip_text = SkillHelp.description("effect", str(eff.get("effect", SkillEngine.EFFECT_IF)))
	effect_path = path
	_effect = eff
	has_else = str(eff.get("effect", "")) == SkillEngine.EFFECT_IF_ELSE
	_apply_style(control_color(), 8)
	_apply_socket_notch()
	mouse_default_cursor_shape = Control.CURSOR_DRAG

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var if_lbl := _make_label(Locale.t("skill_editor.if_word"), 13)
	head.add_child(if_lbl)
	cond_slot = _make_cond_slot()
	head.add_child(cond_slot)
	var then_lbl := _make_label(Locale.t("skill_editor.then_word"), 13)
	head.add_child(then_lbl)
	# No edit button: the condition is edited inline (Scratch-style boolean
	# block with number slots), not via a legacy condition popup.
	_build_action_buttons(head, false)
	outer.add_child(head)

	then_container = _make_slot(outer)

	if has_else:
		var else_lbl := _make_label(Locale.t("skill_editor.else_label"), 12)
		outer.add_child(else_lbl)
		else_container = _make_slot(outer)


# "Repeat N times" C-shaped control block: "重复 [N] 次" header plus a loop
# body slot. The count is edited inline; the body is filled by dragging blocks.
func setup_repeat_block(eff: Dictionary, path: Array) -> void:
	tooltip_text = SkillHelp.description("effect", SkillEngine.EFFECT_REPEAT)
	effect_path = path
	_effect = eff
	_apply_style(repeat_color(), 8)
	_apply_socket_notch()
	mouse_default_cursor_shape = Control.CURSOR_DRAG

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(_make_label(Locale.t("skill_editor.repeat_word"), 13))
	# The repeat count is a Scratch-style number slot: fixed number, a
	# variable reporter oval, or a math-expression reporter.
	var count_slot := ValueSlot.new()
	count_slot.setup(eff, "repeat_count", "repeat_var", "", false, 20.0, "repeat_expr")
	count_slot.changed.connect(_on_param_changed)
	head.add_child(count_slot)
	head.add_child(_make_label(Locale.t("skill_editor.times_word"), 13))
	_build_action_buttons(head, false)
	outer.add_child(head)


	then_container = _make_slot(outer)


# The recessed condition gap in the if header. Accepts dropped boolean blocks
# (Scratch-style comparison / has-buff) and hosts the current condition (or a
# placeholder). The gap uses the same teal as the boolean palette blocks so the
# whole condition reads as one coordinated reporter.
func _make_cond_slot() -> PanelContainer:
	var slot := preload("res://SkillConditionSocket.gd").new()
	slot.custom_minimum_size = Vector2(120, 28)
	slot.block = self
	# Fill the slot with the current boolean reporter (or a placeholder).
	var cond := _current_condition(_effect)
	if _cond_has_value(cond):
		slot.add_child(_build_boolean_tree(cond))
	return slot


static func _cond_has_value(cond: Dictionary) -> bool:
	if cond.has("lhs") or cond.has("logic"):
		return true
	var ctype: String = str(cond.get("condition_type", ""))
	return ctype != "" and ctype != SkillEngine.CONDITION_NONE


func _cond_get_drag_data(_pos: Vector2):
	return null


func _can_drop_condition(_pos: Vector2, data) -> bool:
	return _can_drop_condition_at([], data)

func _can_drop_condition_at(path: Array, data) -> bool:
	if not data is Dictionary or data.get("type", "") not in ["boolean_block", "logic_block", "condition_block"]: return false
	var source: Object = data.get("from_cond_slot")
	if source != null and is_instance_valid(source):
		var source_path: Array = data.get("from_condition_path", [])
		if source.effect_path == effect_path and (condition_path_prefix(source_path, path) or condition_path_prefix(path, source_path)):
			return false
		var displaced := condition_at_path(SkillEngine._condition_dict(_effect), path)
		if not displaced.is_empty() and source_path.size() + condition_depth(displaced) > UgcSafety.MAX_EXPRESSION_NESTING_DEPTH:
			return false
	return path.size() + condition_depth(_condition_from_payload(data)) <= UgcSafety.MAX_EXPRESSION_NESTING_DEPTH

static func condition_at_path(root: Dictionary, path: Array) -> Dictionary:
	var condition := root
	for key in path:
		var child: Variant = condition.get(key)
		if not child is Dictionary:
			return {}
		condition = child
	if not _cond_has_value(condition):
		return {}
	if not condition.has("effect"):
		return condition
	var legacy := {}
	for key in ["condition_type", "condition_op", "condition_value", "condition_buff_id"]:
		if condition.has(key):
			legacy[key] = condition[key]
	return legacy

static func condition_path_prefix(prefix: Array, path: Array) -> bool:
	return prefix.size() <= path.size() and path.slice(0, prefix.size()) == prefix

static func condition_depth(cond: Dictionary) -> int:
	return UgcSafety._dictionary_depth(cond, UgcSafety.MAX_EXPRESSION_NESTING_DEPTH + 1)

func _condition_from_payload(data: Dictionary) -> Dictionary:
	if data.has("boolean"): return data.boolean.duplicate(true)
	if data.get("type") == "logic_block": return _make_logic(str(data.get("logic_kind", "and")))
	return data.get("condition", {}).duplicate(true)


func _drop_condition(_pos: Vector2, data) -> void:
	_drop_condition_at([], data)

func _drop_condition_at(path: Array, data: Dictionary) -> void:
	if not _can_drop_condition_at(path, data): return
	var payload := data.duplicate()
	payload["boolean"] = _condition_from_payload(data)
	condition_inserted.emit(effect_path, path, payload)


# A fresh logic block with default comparison leaves.
func _make_logic(kind: String) -> Dictionary:
	if kind == "not":
		return {"logic": "not", "child": {}}
	return {"logic": kind, "lhs": {}, "rhs": {}}


# Condition fields may be a nested "condition" dict (new) or on the effect
# itself (legacy). Reuses the engine's accessor for consistency.
func _current_condition(eff: Dictionary) -> Dictionary:
	var c: Variant = eff.get("condition", {})
	if c is Dictionary and not c.is_empty():
		return c
	return eff


# Recursively renders a boolean condition tree: logic nodes (and/or/not) wrap
# child boolean slots; leaves are comparisons / has-buff / legacy reporters.
func _build_boolean_tree(cond: Dictionary, path: Array = []) -> Control:
	var root: Control
	if cond.has("logic"):
		var row := _CondReporter.new()
		row.add_theme_constant_override("separation", 4)
		var logic: String = str(cond.get("logic", "and"))
		if logic == "not":
			row.add_child(_make_label(Locale.t("skill_editor.logic_not"), 12))
			row.add_child(_make_bool_sub_slot(cond, "child", path))
		else:
			row.add_child(_make_bool_sub_slot(cond, "lhs", path))
			var logic_sel := OptionButton.new()
			logic_sel.add_theme_stylebox_override("normal", _make_param_style())
			logic_sel.add_theme_stylebox_override("hover", _make_param_style())
			logic_sel.add_theme_stylebox_override("pressed", _make_param_style())
			logic_sel.add_theme_color_override("font_color", Color.WHITE)
			logic_sel.add_theme_font_size_override("font_size", 14)
			logic_sel.add_item(Locale.t("skill_editor.logic_and"), 0)
			logic_sel.add_item(Locale.t("skill_editor.logic_or"), 1)
			logic_sel.selected = 1 if logic == "or" else 0
			logic_sel.item_selected.connect(func(_i: int):
				cond["logic"] = "or" if logic_sel.selected == 1 else "and"
				_on_cond_tree_changed()
			)
			_set_param_pass(logic_sel)
			row.add_child(logic_sel)
			row.add_child(_make_bool_sub_slot(cond, "rhs", path))
		root = row
	else:
		root = _build_leaf_boolean(cond)
	_attach_cond_drag(root, cond, path)
	return root


# The whole condition reporter is draggable (Scratch-style): drag it away to
# remove the condition (drop on the palette) or move it to another socket.
# The origin lets the editor put a displaced reporter back into this socket.
func _attach_cond_drag(root: Control, cond: Dictionary, path: Array = []) -> void:
	var payload := {"type": "boolean_block", "boolean": condition_at_path(cond, []).duplicate(true), "from_cond_slot": self, "from_condition_path": path.duplicate()}
	if root is _CondReporter:
		(root as _CondReporter).setup(self, cond, payload)


# Renders a boolean / legacy condition reporter inside the if gap.
# New Scratch-style form: [operand] [op] [operand] (or "目标 拥有 [buff]");
# the legacy condition reporter (condition_type + op + value) is kept for
# skills saved before the boolean-block format.
func _build_leaf_boolean(cond: Dictionary) -> HBoxContainer:
	var row := _CondReporter.new()
	row.add_theme_constant_override("separation", 4)
	if cond.has("lhs"):
		var op: String = str(cond.get("op", SkillEngine.CONDITION_OP_GTE))
		if op == "has":
			row.add_child(_make_label(Locale.t("skill_editor.has_target_word"), 12))
			row.add_child(_make_label(Locale.t("skill_editor.has_buff_word"), 12))
			row.add_child(_make_cond_buff_option(cond))
			return row
		var lhs: Dictionary = cond.get("lhs", {})
		var rhs: Dictionary = cond.get("rhs", {})
		row.add_child(_make_operand_slot(lhs))
		row.add_child(_make_cond_op_option(cond))
		row.add_child(_make_operand_slot(rhs))
		return row
	var type_id: String = str(cond.get("condition_type", SkillEngine.CONDITION_NONE))
	row.add_child(_make_label(Locale.term("condition", type_id), 12))
	if type_id == SkillEngine.CONDITION_TARGET_HAS_BUFF:
		row.add_child(_make_cond_buff_option(cond))
	else:
		row.add_child(_make_cond_op_option(cond))
		row.add_child(_make_cond_value_spin(cond))
	return row


# A boolean sub-slot inside a logic node: holds a nested comparison / logic
# block and accepts drops that replace it (Scratch-style nesting).
func _make_bool_sub_slot(parent_cond: Dictionary, field_key: String, path: Array = []) -> PanelContainer:
	var slot := preload("res://SkillConditionSocket.gd").new()
	slot.block = self
	slot.condition_path = path + [field_key]
	slot.custom_minimum_size = Vector2(120, 28)
	var child: Dictionary = parent_cond.get(field_key, {})
	if not child.is_empty():
		slot.add_child(_build_boolean_tree(child, slot.condition_path))

	return slot


func _drop_bool_sub(parent_cond: Dictionary, field_key: String, data) -> void:
	var new_bool: Dictionary = {}
	if str(data.get("type", "")) == "logic_block":
		new_bool = _make_logic(str(data.get("logic_kind", "and")))
	else:
		new_bool = data.get("boolean", {})
	parent_cond[field_key] = new_bool.duplicate(true)
	_on_cond_tree_changed()


func _on_cond_tree_changed() -> void:
	# The whole condition tree changed structurally — rewrite the if block's
	# condition and let the editor rebuild the script.
	condition_dropped.emit(effect_path, _current_condition(_effect), [])


# One side of a comparison: a Scratch-style number slot (fixed number or a
# variable reporter oval) bound to the operand dict.
func _make_operand_slot(opd: Dictionary) -> ValueSlot:
	var slot := ValueSlot.new()
	slot.setup(opd, "value", "var_id", "kind", false, 999.0)
	slot.changed.connect(_on_cond_changed)
	return slot


func _make_cond_op_option(cond: Dictionary) -> OptionButton:
	var opt := OptionButton.new()
	opt.add_theme_stylebox_override("normal", _make_param_style())
	opt.add_theme_stylebox_override("hover", _make_param_style())
	opt.add_theme_stylebox_override("pressed", _make_param_style())
	opt.add_theme_color_override("font_color", Color.WHITE)
	opt.add_theme_font_size_override("font_size", 14)
	for i in range(SkillRegistry.CONDITION_OP_IDS.size()):
		opt.add_item({">=":"≥", "<=":"≤", "==":"="}.get(SkillRegistry.CONDITION_OP_IDS[i], SkillRegistry.CONDITION_OP_IDS[i]), i)
	var cur_op: String = str(cond.get("op", cond.get("condition_op", SkillEngine.CONDITION_OP_GTE)))
	opt.selected = _idx_of(cur_op, SkillRegistry.CONDITION_OP_IDS)
	opt.item_selected.connect(func(_i: int):
		if cond.has("lhs"):
			cond["op"] = SkillRegistry.CONDITION_OP_IDS[opt.selected]
		else:
			cond["condition_op"] = SkillRegistry.CONDITION_OP_IDS[opt.selected]
		_on_cond_changed()
	)
	_set_param_pass(opt)
	return opt


func _make_cond_value_spin(cond: Dictionary) -> SpinBox:
	var spin := SpinBox.new()
	spin.add_theme_stylebox_override("normal", _make_param_style())
	spin.add_theme_font_size_override("font_size", 14)
	spin.custom_minimum_size = Vector2(56, 24)
	spin.allow_greater = true
	var is_pct: bool = str(cond.get("condition_type", "")) in [SkillEngine.CONDITION_SOURCE_HP_PCT, SkillEngine.CONDITION_TARGET_HP_PCT]
	spin.min_value = 0.0 if is_pct else -999.0
	spin.max_value = 100.0 if is_pct else 999.0
	spin.value = float(int(cond.get("condition_value", 0)))
	var le: LineEdit = spin.get_line_edit()
	if le != null:
		le.add_theme_stylebox_override("normal", _make_param_style())
		le.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
		le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.value_changed.connect(func(v: float):
		cond["condition_value"] = int(v)
		_on_cond_changed()
	)
	_set_param_pass(spin)
	return spin


func _make_cond_buff_option(cond: Dictionary) -> OptionButton:
	var opt := OptionButton.new()
	opt.add_theme_stylebox_override("normal", _make_param_style())
	opt.add_theme_stylebox_override("hover", _make_param_style())
	opt.add_theme_stylebox_override("pressed", _make_param_style())
	opt.add_theme_color_override("font_color", Color.WHITE)
	opt.add_theme_font_size_override("font_size", 14)
	var cur_buff: String = str(cond.get("condition_buff_id", ""))
	if cond.has("lhs"):
		cur_buff = str(cond.get("rhs", {}).get("buff_id", ""))
	if cur_buff == "":
		cur_buff = SkillEngine.BUFF_ATK_BOOST
	preload("res://SkillStatusPicker.gd").fill(opt, cur_buff)
	opt.item_selected.connect(func(_i: int):
		var buff_id: String = preload("res://SkillStatusPicker.gd").value(opt)
		if cond.has("lhs"):
			var rhs: Dictionary = cond.get("rhs", {})
			rhs["buff_id"] = buff_id
			cond["rhs"] = rhs
		else:
			cond["condition_buff_id"] = buff_id
		_on_cond_changed()
	)
	_set_param_pass(opt)
	return opt


func _on_cond_changed() -> void:
	changed.emit(effect_path)


# Stop block: halts the current block when executed.
func setup_stop_block(path: Array) -> void:
	tooltip_text = SkillHelp.description("effect", SkillEngine.EFFECT_STOP)
	effect_path = path
	_effect = {"effect": SkillEngine.EFFECT_STOP}
	_apply_style(stop_color())
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	var head := HBoxContainer.new()
	var title := _make_label(Locale.t("skill_editor.stop_word"), 13)
	title.set_meta("keyword_literal",true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_build_action_buttons(head, false)
	add_child(head)


func _make_badge(text: String) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 11)
	# Single line (autowrap inside a flow row collapses the min width to 1px).
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.18)
	st.set_corner_radius_all(3)
	st.content_margin_left = 5
	st.content_margin_right = 5
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	badge.add_theme_stylebox_override("normal", st)
	badge.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	return badge


func _effect_badges(eff: Dictionary) -> Array:
	var result: Array = []
	var prob: int = int(eff.get("probability", 100))
	if prob < 100:
		result.append(Locale.t("skill.chance", [prob]))
	var rcount: int = int(eff.get("random_count", 0))
	if rcount > 0 and SkillRegistry.supports_random_count(str(eff.get("effect", ""))):
		result.append(Locale.t("skill.max_targets", [rcount]))
	if SkillRegistry.effect_uses_value(eff) and eff.has("value_var"):
		result.append(Locale.term("value_var", eff.get("value_var", "")))
	elif SkillRegistry.effect_uses_value(eff) and eff.has("value_min") and eff.has("value_max"):
		result.append("%d~%d" % [int(eff.get("value_min", 0)), int(eff.get("value_max", 0))])
	var condition_type: String = eff.get("condition_type", SkillEngine.CONDITION_NONE)
	if condition_type != "" and condition_type != SkillEngine.CONDITION_NONE:
		result.append(Locale.t("skill_editor.condition_badge", [Locale.term("condition", condition_type)]))

	return result


# ============================================
# Drag & drop (Scratch-style stacking)
# ============================================

func _get_drag_data(_at_position: Vector2):
	if not draggable or is_hat or _effect.is_empty():
		return null
	_at_position = _workspace_pointer(_at_position, true)
	var drag_control := Control.new()
	drag_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := VBoxContainer.new()
	stack.name = "DraggedStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.scale = get_parent().get_global_transform().get_scale()
	stack.position = -_at_position * stack.scale
	stack.add_theme_constant_override("separation",get_parent().get_theme_constant("separation"))
	drag_control.add_child(stack)
	var following := false
	for sibling in get_parent().get_children():
		if sibling == self: following = true
		if not following or not sibling is SkillBlock: continue
		var preview := make_preview(sibling._effect)
		preview.custom_minimum_size = sibling.size
		stack.add_child(preview)
	stack.size = stack.get_combined_minimum_size()
	set_drag_preview(drag_control)
	_set_press_shadow(false,true)
	_dragging = true
	if has_meta("skill_workspace"):
		var workspace: Control = get_meta("skill_workspace")
		var owner_editor = workspace.editor_ref.get_ref()
		if owner_editor != null: owner_editor.hide_drag_tail(self)
	return {"type":"effect_block","effect":_effect.duplicate(true),"from_path":effect_path,
		"tail":true,"grab_offset":[_at_position.x,_at_position.y]}



func _can_drop_data(at_position: Vector2, data) -> bool:
	if has_meta("skill_workspace"):
		var editor = get_meta("skill_workspace").editor_ref.get_ref()
		if editor != null: return editor._preview_stack_drop(data)
	at_position = _workspace_pointer(at_position)
	if is_hat or _effect.is_empty():
		return false
	var ok: bool = data is Dictionary and data.get("type", "") == "effect_block"
	_set_drag_highlight(ok)
	if ok:
		# Scratch-style: hovering a block also shows the insertion line at the
		# exact gap the drop would land in (upper half = before, lower = after),
		# so the preview line and the block highlight always agree.
		insertion_requested.emit(get_parent() as VBoxContainer, _sibling_insert_index(at_position.y > size.y * 0.5))
	else:
		insertion_hidden.emit()
	return ok


# Index of this block inside its parent slot, +1 when inserting after it.
# Ignores non-block children (e.g. the empty-slot hint label).
func _sibling_insert_index(insert_after: bool) -> int:
	var parent: Node = get_parent()
	var idx := 0
	if parent != null:
		for c in parent.get_children():
			if c == self:
				break
			if c is SkillBlock:
				idx += 1
	if insert_after:
		idx += 1
	return idx


func _set_drag_highlight(on: bool) -> void:
	if _drag_highlight == on:
		return
	_drag_highlight = on
	if on:
		var st := _make_block_style(_base_bg.lightened(0.04))
		st.border_color = Color(0.36, 0.88, 1.0, 0.98)
		st.set_border_width_all(1)
		# Do not add an outward glow here: it overlaps neighbouring blocks in a
		# tight stack. The cyan border is sufficient drop feedback.
		st.shadow_size = 0
		if _has_socket_notch:
			var shaped = preload("res://SkillSocketStyle.gd").from_flat(st, "stack")
			var current = get_theme_stylebox("panel")
			if current.get_script() == preload("res://SkillSocketStyle.gd"): shaped.cavities = current.cavities.duplicate()
			add_theme_stylebox_override("panel", shaped)
		else:
			add_theme_stylebox_override("panel", st)
	else:
		_apply_rest_style()


# Dropping onto a block inserts the dragged block before/after this block
# (upper half = before, lower half = after), Scratch-style insertion. The full
# drag payload (palette effect_id OR script-internal from_path) is forwarded so
# the editor can decide: insert a fresh block or move an existing one.
func _drop_data(at_position: Vector2, data) -> void:
	if has_meta("skill_workspace"):
		var editor = get_meta("skill_workspace").editor_ref.get_ref()
		if editor != null:
			editor._commit_stack_drop(data)
			return
	at_position = _workspace_pointer(at_position)
	_set_drag_highlight(false)
	var from_path: Array = data.get("from_path", [])
	if from_path.size() > 0 and from_path == effect_path:
		return
	var insert_after: bool = at_position.y > size.y * 0.5
	drop_requested.emit(from_path, effect_path, insert_after, data)
	_play_drop_pulse()

func _workspace_pointer(fallback: Vector2, start: bool = false) -> Vector2:
	if not has_meta("skill_workspace"): return fallback
	var workspace: Control = get_meta("skill_workspace")
	var point: Vector2 = workspace.press_pointer if start else workspace.last_pointer
	return get_global_transform().affine_inverse() * (workspace.get_global_transform() * point)

func mark_validation_fields(issues: Array) -> void:
	for marker in _validation_markers:
		if is_instance_valid(marker):
			marker.get_parent().remove_child(marker)
			marker.queue_free()
	_validation_markers.clear()
	var fields: Array[Control] = []
	for issue in issues:
		var kind := str(issue.get("kind",""))
		if kind == "condition" and cond_slot != null:
			var socket_path: Array = issue.get("condition_path", [])
			if socket_path.is_empty(): fields.append(cond_slot)
			else:
				for socket in find_children("*", "PanelContainer", true, false):
					if socket.get_script() == preload("res://SkillConditionSocket.gd") and socket.block == self and socket.condition_path == socket_path: fields.append(socket)
		for candidate in find_children("*","Control",true,false):
			var ancestor: Node = candidate.get_parent()
			while ancestor != null and not ancestor is SkillBlock: ancestor = ancestor.get_parent()
			if ancestor != self: continue
			if candidate is TargetSlot and kind in ["target","target_side"]:
				if candidate.kind == ("side" if kind=="target_side" else "target"): fields.append(candidate)
			elif candidate is ValueSlot and kind in ["value","repeat","ugc_safety"]:
				if issue.has("operand"):
					if is_same(candidate.data, issue.operand): fields.append(candidate)
					continue
				if kind != "repeat" or candidate.num_field == "repeat_count": fields.append(candidate)
	for field in fields:
		if field.has_node("ValidationOutline"): continue
		var outline := preload("res://SkillFieldOutline.gd").new()
		outline.name = "ValidationOutline"
		outline.radius = 10 if field is TargetSlot or field == cond_slot else 6
		if field.get_script() == preload("res://SkillConditionSocket.gd"): outline.shape = "boolean"
		field.add_child(outline)
		_validation_markers.append(outline)


# Removes this block's drop highlight and hides the shared insertion line.
# Used when the drag leaves the block: blocks the pointer merely swept over
# must not stay lit (their _can_drop_data is not called again once unhovered).
func _clear_drag_feedback() -> void:
	_set_drag_highlight(false)
	if has_meta("skill_workspace"): return
	insertion_hidden.emit()


func _notification(what: int) -> void:
	if get_meta("drag_preview",false): return
	if what == NOTIFICATION_DRAG_END:
		_dragging = false
		_set_press_shadow(false, true)
		_set_drag_highlight(false)
		_animate_motion(Vector2.ONE, Color.WHITE, 0.12)
	elif what == NOTIFICATION_MOUSE_EXIT:
		# During a drag the GUI fires MOUSE_EXIT when the pointer leaves a
		# block — clear its highlight and hide the insertion line. A child
		# control (e.g. an action button) stealing hover also fires MOUSE_EXIT
		# while the pointer is still inside the block; ignore that so the
		# highlight does not flicker mid-block.
		if get_viewport() != null and get_viewport().gui_is_dragging() \
				and not get_global_rect().has_point(get_global_mouse_position()):
			_clear_drag_feedback()


# Right-click a block to open the duplicate/delete context menu.
func _gui_input(event: InputEvent) -> void:
	var mouse_ev: InputEventMouseButton = event as InputEventMouseButton
	if mouse_ev == null:
		return
	if is_hat and has_meta("skill_workspace") and mouse_ev.button_index == MOUSE_BUTTON_LEFT and mouse_ev.pressed:
		var point := get_global_transform() * mouse_ev.position
		if body_container == null or point.y < body_container.get_global_rect().position.y:
			var workspace: Control = get_meta("skill_workspace")
			workspace.begin_script_drag(point)
			accept_event()
			return
	if mouse_ev.button_index == MOUSE_BUTTON_RIGHT and mouse_ev.pressed and not is_hat:
		var at := get_global_rect().position + mouse_ev.position
		context_requested.emit(effect_path, at)
		accept_event()
	elif mouse_ev.button_index == MOUSE_BUTTON_LEFT and not is_hat:
		if mouse_ev.pressed:
			_set_press_shadow(true)
			_animate_motion(Vector2.ONE, Color(0.94,0.94,0.94), 0.05)
		elif not _dragging:
			_set_press_shadow(false)
			_on_block_mouse_entered()


func setup_chance_block(eff: Dictionary, path: Array) -> void:
	effect_path = path
	_effect = eff
	_apply_style(control_color(), 8)
	_apply_socket_notch()
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(_make_label(Locale.t("skill_editor.chance_prefix"), 13))
	var percent := ValueSlot.new()
	percent.name = "ChancePercent"
	percent.clamp_input = true
	percent.accept_reporters = false
	percent.setup(eff.condition.rhs,"value","var_id","kind",false,100)
	percent.changed.connect(_on_param_changed)
	head.add_child(percent)
	head.add_child(_make_label(Locale.t("skill_editor.chance_suffix"), 13))
	_build_action_buttons(head, false)
	outer.add_child(head)
	then_container = _make_slot(outer)

static func make_preview(effect: Dictionary) -> SkillBlock:
	var block := SkillBlock.new()
	block.set_meta("drag_preview", true)
	var eff := effect.duplicate(true)
	match str(eff.get("effect", "")):
		SkillEngine.EFFECT_IF, SkillEngine.EFFECT_IF_ELSE:
			if SkillRegistry.is_chance_block(eff): block.setup_chance_block(eff, [])
			else: block.setup_if_else(eff, [])
		SkillEngine.EFFECT_REPEAT: block.setup_repeat_block(eff, [])
		SkillEngine.EFFECT_STOP: block.setup_stop_block([])
		_: block.setup_effect(eff, [])
	if block.then_container != null:
		for child in eff.get("then_effects", []): block.then_container.add_child(make_preview(child))
	if block.else_container != null:
		for child in eff.get("else_effects", []): block.else_container.add_child(make_preview(child))
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return block

static func make_condition_preview(condition: Dictionary) -> SkillBlock:
	var block := SkillBlock.new()
	block.set_meta("drag_preview", true)
	block._effect = {"condition":condition.duplicate(true)}
	block.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	block.cond_slot = block._make_cond_slot()
	block.add_child(block.cond_slot)
	return block
