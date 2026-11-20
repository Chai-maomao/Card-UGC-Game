class_name ValueSlot
extends PanelContainer

# ============================================
# Scratch-style number slot.
# Starts with an empty rounded literal field. Dropping a variable reporter
# oval ({"type": "var_block", "var_id": ...}) into the slot switches it to a
# variable chip — clicking the chip opens a variable picker. Dragging the
# chip back onto the palette leaves the rounded input empty. Used for effect
# values, repeat counts and comparison operands.
#
# Data contract (bound dictionary, shared reference):
#   fixed mode : data[num_field] = number; (optionally data[kind_field]="num")
#   var mode   : data[var_field] = var_id;  data.erase(num_field);
#                (optionally data[kind_field]="var")
# ============================================

signal changed

var data: Dictionary
var num_field: String = "value"
var var_field: String = "value_var"
var kind_field: String = ""     # if non-empty, write "num"/"var"/"expr" here too
var expr_field: String = ""     # if non-empty, a dropped math reporter writes data[expr_field]
var offset_field: String = ""   # if non-empty, var mode shows a +/- offset spin
var allow_negative: bool = false
var clamp_input := false
var accept_reporters := true
var max_value: float = 999.0
var min_value: float = 0.0

var _mode: String = "num"       # "num" / "var" / "expr"
var _drop_highlight: bool = false
var _dragging: bool = false
var _motion_tween: Tween


func setup(p_data: Dictionary, p_num_field: String, p_var_field: String,
		p_kind_field: String = "", p_allow_negative: bool = false, p_max_value: float = 999.0,
		p_expr_field: String = "", p_offset_field: String = "") -> void:
	data = p_data
	num_field = p_num_field
	var_field = p_var_field
	kind_field = p_kind_field
	expr_field = p_expr_field
	offset_field = p_offset_field
	allow_negative = p_allow_negative
	max_value = p_max_value
	min_value = -999.0 if p_allow_negative else 0.0
	_apply_slot_style()
	_rebuild()


func _apply_slot_style() -> void:
	if _slot_mode() == "expr":
		var st := StyleBoxFlat.new()
		var tint := SkillBlock.random_color() if _expr_inner().get("op") == "rand" else SkillBlock.math_color()
		st.bg_color = UITheme.COLOR_PANEL_SOFT.lerp(tint, 0.78)
		if _drop_highlight: st.bg_color = st.bg_color.lightened(0.10)
		st.border_color = Color(0.50, 0.95, 0.88) if _drop_highlight else tint.darkened(0.28)
		st.set_border_width_all(2 if _drop_highlight else 1)
		st.set_corner_radius_all(999)
		st.set_content_margin_all(2)
		st.content_margin_left = 6
		st.content_margin_right = 6
		add_theme_stylebox_override("panel", st)
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		for input in find_children("*", "LineEdit", false, false):
			input.add_theme_stylebox_override("normal", _param_style())
		if _slot_mode() == "var":
			for chip in find_children("*", "Button", true, false):
				chip.add_theme_stylebox_override("normal", _variable_style())
	custom_minimum_size = Vector2(52, 26)
	# PASS so a fixed-number slot does not swallow the press: when nothing is
	# draggable here (_slot_get_drag_data returns null), the drag bubbles up to
	# the enclosing reporter / block (Scratch: grab the whole reporter from
	# anywhere on it). Drop acceptance is unaffected — PASS controls still get
	# _can_drop_data/_drop_data called.
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_drag_forwarding(
		Callable(self, "_slot_get_drag_data"),
		Callable(self, "_can_drop_var"),
		Callable(self, "_drop_var"),
	)


func _init() -> void:
	set_meta("keyword_literal_fields",true)


func _ready() -> void:
	if get_meta("drag_preview", false): return
	gui_input.connect(_on_rounding_input.bind(self))
	if data.is_empty():
		return
	_apply_slot_style()
	_rebuild()


func _slot_mode() -> String:
	if kind_field != "":
		var k: String = str(data.get(kind_field, "num"))
		if k == "expr":
			return "expr"
		if k == "var":
			return "var"
		return "num"
	if data.has(var_field) and str(data.get(var_field, "")) != "":
		return "var"
	if expr_field != "" and data.has(expr_field):
		return "expr"
	return "num"


# The inner operand/expression dict this slot edits (the bound dict itself for
# comparison operands, or data[expr_field] for effect values / repeat counts).
func _expr_inner() -> Dictionary:
	if expr_field != "" and data.has(expr_field):
		var v: Variant = data.get(expr_field)
		if v is Dictionary:
			return v
	return data


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_mode = _slot_mode()
	_apply_slot_style()
	if _mode == "var":
		tooltip_text = SkillHelp.description("value_var", str(data.get(var_field, "")))
	elif _mode == "expr":
		tooltip_text = SkillHelp.description("math", str(_expr_inner().get("op", "+")))
	else:
		tooltip_text = ""
	match _mode:
		"var":
			_build_var_mode()
		"expr":
			_build_expr_mode()
		_:
			_build_num_mode()


# ============================================
# Fixed-number mode
# ============================================

func _build_num_mode() -> void:
	var input := LineEdit.new()
	input.custom_minimum_size = Vector2(52, 26)
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_stylebox_override("normal", _param_style())
	input.add_theme_stylebox_override("focus", _focus_style())
	input.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	input.add_theme_font_size_override("font_size", 14)
	input.text = str(int(data[num_field])) if data.has(num_field) else ""
	_set_param_pass(input)
	var commit := func():
		# Replacing the literal with a reporter retires this editor. Its focus
		# exit must not write the old literal over the newly inserted reporter.
		if input.is_queued_for_deletion() or _slot_mode() != "num": return
		var text := input.text.strip_edges()
		var before: Dictionary = data.duplicate(true)
		if text == "":
			data.erase(num_field)
		elif text.is_valid_int():
			var value := maxi(int(min_value), int(text))
			if clamp_input: value = mini(int(max_value), value)
			data[num_field] = value
			if kind_field != "": data[kind_field] = "num"
			data.erase(var_field)
			data.erase(offset_field)
			if expr_field != "": data.erase(expr_field)
		input.text = str(int(data[num_field])) if data.has(num_field) else ""
		if before != data: changed.emit()
	input.text_submitted.connect(func(_text: String): commit.call())
	input.focus_exited.connect(commit)
	add_child(input)


# ============================================
# Math-expression mode: "[a] [op] [b]" — a and b are nested number slots
# (number / variable / deeper expression), the op dropdown picks + - * / rand.
# ============================================

const EXPR_OPS := ["+", "-", "*", "/", "rand"]

static func make_expression(op: String) -> Dictionary:
	return {"kind":"expr", "op":op, "rounding":"round",
		"a":{}, "b":{}}


func _build_expr_mode() -> void:
	var inner := _expr_inner()
	if not inner.has("op"):
		inner["op"] = "+"
	if not inner.has("a"):
		inner["a"] = {}
	if not inner.has("b"):
		inner["b"] = {}
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var slot_a := ValueSlot.new()
	slot_a.setup(inner.get("a", {"kind": "num", "value": 1}), "value", "var_id", "kind", allow_negative, max_value)
	slot_a.changed.connect(func(): changed.emit())
	row.add_child(slot_a)
	var op_sel := OptionButton.new()
	for state in ["normal", "hover", "pressed"]:
		op_sel.add_theme_stylebox_override(state, _param_style())
	op_sel.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	op_sel.add_theme_font_size_override("font_size", 14)
	op_sel.add_theme_color_override("font_color", Color.WHITE)
	op_sel.custom_minimum_size = Vector2(34, 24)
	for i in range(EXPR_OPS.size()):
		op_sel.add_item(_op_label(EXPR_OPS[i]), i)
	op_sel.selected = maxi(0, EXPR_OPS.find(str(inner.get("op", "+"))))
	op_sel.item_selected.connect(func(_i: int):
		inner["op"] = EXPR_OPS[op_sel.selected]
		_rebuild()
		changed.emit()
	)
	_set_param_pass(op_sel)
	op_sel.gui_input.connect(_on_rounding_input.bind(op_sel))
	op_sel.tooltip_text = Locale.t("skill_editor.rounding_hint", [Locale.t("skill_editor.rounding_" + str(inner.get("rounding", "round")))])
	row.add_child(op_sel)
	var slot_b := ValueSlot.new()
	slot_b.setup(inner.get("b", {"kind": "num", "value": 1}), "value", "var_id", "kind", allow_negative, max_value)
	slot_b.changed.connect(func(): changed.emit())
	row.add_child(slot_b)
	add_child(row)


func _on_rounding_input(event: InputEvent, anchor: Control) -> void:
	if _slot_mode() != "expr" or not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if anchor == self and has_meta("loose_reporter_key"):
			var editor = get_meta("loose_reporter_editor").get_ref()
			if editor != null: editor._on_loose_reporter_context(str(get_meta("loose_reporter_key")), event.global_position)
			anchor.accept_event()
			return
		anchor.accept_event()
		_open_rounding_menu(anchor)


func _open_rounding_menu(anchor: Control) -> PopupMenu:
	var inner := _expr_inner()
	var modes := ["round", "ceil", "floor"]
	var menu := PopupMenu.new()
	for index in range(modes.size()):
		menu.add_radio_check_item(Locale.t("skill_editor.rounding_" + modes[index]), index)
		menu.set_item_checked(index, str(inner.get("rounding", "round")) == modes[index])
	menu.id_pressed.connect(func(index: int):
		inner["rounding"] = modes[index]
		_rebuild()
		changed.emit()
	)
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	UITheme.apply_popup_menu(menu)
	menu.position = Vector2i(anchor.get_global_rect().position + Vector2(0, anchor.size.y))
	menu.popup()
	return menu


func _op_label(op: String) -> String:
	match op:
		"-":
			return "-"
		"*":
			return "*"
		"/":
			return "/"
		"rand":
			return "~"
		_:
			return "+"


# ============================================
# Variable mode (reporter oval chip)
# ============================================

func _build_var_mode() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var var_id: String = str(data.get(var_field, ""))
	var chip := Button.new()
	chip.text = _clamp_chip(Locale.term("value_var", var_id), 14)
	# Do NOT set clip_text here: it removes the text from the button's minimum
	# size, collapsing the chip to its padding width inside the HBox row and
	# making the variable name invisible.
	chip.add_theme_font_size_override("font_size", 14)
	chip.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	var st := _variable_style()
	chip.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = Color(0.28, 0.60, 0.56, 0.85)
	chip.add_theme_stylebox_override("hover", hover)
	chip.add_theme_stylebox_override("pressed", hover)
	chip.add_theme_stylebox_override("focus", _focus_style())
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.pressed.connect(func(): _open_var_menu(chip))
	_set_param_pass(chip)
	row.add_child(chip)
	if offset_field != "" and int(data.get(offset_field, 0)) != 0:
		# Scratch has no offsets; this is a game-specific tweak: the variable
		# reporter reads the battlefield stat, then adds the given offset
		# ("手牌数 +2"), edited inline instead of via the config form.
		var offset := SpinBox.new()
		preload("res://SkillSocketStyle.gd").compact_number(offset)
		offset.add_theme_stylebox_override("normal", _param_style())
		offset.add_theme_stylebox_override("hover", _param_style())
		offset.add_theme_font_size_override("font_size", 14)
		offset.custom_minimum_size = Vector2(48, 24)
		offset.min_value = -999.0
		offset.max_value = 999.0
		offset.value = float(int(data.get(offset_field, 0)))
		offset.get_line_edit().add_theme_stylebox_override("normal", _param_style())
		offset.get_line_edit().add_theme_stylebox_override("focus", _focus_style())
		offset.tooltip_text = Locale.t("skill_editor.value_offset")
		offset.value_changed.connect(func(v: float):
			data[offset_field] = int(v)
			changed.emit()
		)
		_set_param_pass(offset)
		row.add_child(offset)
	add_child(row)


# Clear the slot to an empty literal input. Also used when the chip/expr is
# dragged onto the palette (drop-to-discard for variable / math reporters).
func clear_to_number(notify: bool = true) -> void:
	if has_meta("loose_reporter_key"):
		var editor = get_meta("loose_reporter_editor").get_ref()
		if editor != null: editor._remove_loose_reporter(str(get_meta("loose_reporter_key")), notify)
		return
	data.erase(var_field)
	data.erase(offset_field)
	if expr_field != "":
		data.erase(expr_field)
	if kind_field != "":
		data[kind_field] = "num"
		data.erase("op")
		data.erase("a")
		data.erase("b")
		data.erase("rounding")
	data.erase(num_field)
	_rebuild()
	if notify: changed.emit()


func _open_var_menu(anchor: Control) -> void:
	var menu := PopupMenu.new()
	menu.popup_hide.connect(menu.queue_free)
	var ids: Array = SkillRegistry.VALUE_VAR_IDS
	for i in range(ids.size()):
		menu.add_item(Locale.term("value_var", ids[i]), i)
		menu.set_item_tooltip(i, SkillHelp.description("value_var", ids[i]))
	menu.id_pressed.connect(func(id: int):
		data[var_field] = ids[id]
		if kind_field != "":
			data[kind_field] = "var"
		data.erase(num_field)
		_rebuild()
		changed.emit()
	)
	add_child(menu)
	menu.position = Vector2i(anchor.get_global_rect().position + Vector2(0, anchor.size.y))
	menu.popup()


# Truncates long reporter labels so a chip keeps a bounded width (deeply
# nested reporters otherwise grow past the script area edge).
static func _clamp_chip(t: String, max_chars: int) -> String:
	if t.length() <= max_chars:
		return t
	return t.substr(0, max_chars - 1) + "…"


# ============================================
# Drag & drop: accept variable reporter ovals / math reporters, and expose
# the current chip/expr as a drag source so it can be dragged away (drop on
# the palette deletes it, drop on another slot moves it). Without this the
# press would bubble up and drag the whole effect block instead.
# ============================================

func _slot_get_drag_data(_pos: Vector2):
	if _mode == "var":
		var var_id: String = str(data.get(var_field, ""))
		if var_id == "":
			return null
		_set_drag_preview_label(Locale.term("value_var", var_id), _pos)
		_dragging = true
		_animate_slot(Vector2.ONE, Color(0.72, 0.76, 0.84, 0.48), 0.07)
		return {"type": "var_block", "var_id": var_id, "offset": data.get(offset_field,0), "from_slot": self, "grab_offset":[_pos.x,_pos.y]}
	if _mode == "expr":
		var inner := _expr_inner()
		var op: String = str(inner.get("op", "+"))
		_set_drag_preview_label(_op_label(op), _pos)
		_dragging = true
		_animate_slot(Vector2.ONE, Color(0.72, 0.76, 0.84, 0.48), 0.07)
		return {"type": "expr_block", "expr_kind": op, "expression": inner.duplicate(true), "from_slot": self, "grab_offset":[_pos.x,_pos.y]}
	return null


func _set_drag_preview_label(_text: String, at: Vector2) -> void:
	var preview := ValueSlot.new()
	preview.set_meta("drag_preview", true)
	preview.setup(data.duplicate(true), num_field, var_field, kind_field, allow_negative, max_value, expr_field, offset_field)
	preview.scale = get_global_transform().get_scale()
	preview.position = -at * preview.scale
	preview.size = preview.get_combined_minimum_size()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(preview)
	set_drag_preview(wrap)


func _can_drop_var(_pos: Vector2, payload) -> bool:
	if not accept_reporters: return false
	var ok: bool = payload is Dictionary and payload.get("type", "") in ["var_block", "expr_block"]
	if ok:
		var source := payload.get("from_slot") as ValueSlot
		if is_instance_valid(source) and (source == self or source.is_ancestor_of(self) or is_ancestor_of(source)): ok = false
		if payload.get("type") == "var_block" and str(payload.get("var_id", "")) not in SkillRegistry.VALUE_VAR_IDS: ok = false
		var expression := _reporter_expression(payload)
		if not expression.is_empty() and not _fits_expression(expression): ok = false
		if ok and is_instance_valid(source):
			var displaced := source._reporter_expression(_current_reporter())
			if not displaced.is_empty() and not source._fits_expression(displaced): ok = false
	_set_drop_highlight(ok)
	return ok

func _fits_expression(expression: Dictionary) -> bool:
	var depth := _expression_depth(expression)
	var parent := get_parent()
	while parent != null:
		if parent is ValueSlot: depth += 1
		parent = parent.get_parent()
	return str(expression.get("op", "+")) in EXPR_OPS and depth < UgcSafety.MAX_EXPRESSION_NESTING_DEPTH


func _reporter_expression(payload: Dictionary) -> Dictionary:
	if payload.get("type") == "expr_block":
		return payload.get("expression", make_expression(str(payload.get("expr_kind", "+"))))
	# Some slots store only a bare variable ID. Use ordinary arithmetic
	# there so moving a variable with an offset preserves its result.
	var offset := int(payload.get("offset", 0))
	if offset_field != "" or offset == 0: return {}
	var expression := make_expression("-" if offset < 0 else "+")
	expression.a = {"kind":"var", "var_id":payload.get("var_id")}
	expression.b = {"kind":"num", "value":absi(offset)}
	return expression


func _current_reporter() -> Dictionary:
	match _slot_mode():
		"var":
			return {"type":"var_block", "var_id":str(data.get(var_field,"")), "offset":data.get(offset_field,0)}
		"expr":
			return {"type":"expr_block", "expression":_expr_inner().duplicate(true)}
	return {}


static func _expression_depth(expression: Dictionary) -> int:
	if not expression.has("op"): return 0
	return 1 + maxi(_expression_depth(expression.get("a", {})), _expression_depth(expression.get("b", {})))


func _drop_var(_pos: Vector2, payload) -> void:
	if not _can_drop_var(_pos, payload): return
	_set_drop_highlight(false)
	# Filled numeric reporters trade places as one change. Copy before writing
	# either binding: the two slots may be operands in the same expression.
	var src: Object = payload.get("from_slot", null)
	if src == self:
		return
	if src is Node and src.is_ancestor_of(self):
		return
	if src is ValueSlot and _slot_mode() in ["var", "expr"]:
		src._write_reporter(_current_reporter(), false)
	elif src != null and src != self and is_instance_valid(src) and src.has_method("clear_to_number"):
		src.call("clear_to_number", false)
	_write_reporter(payload)

func _write_reporter(payload: Dictionary, notify := true) -> void:
	var expression := _reporter_expression(payload)
	if not expression.is_empty():
		_drop_expr(expression, notify)
		return
	var var_id: String = str(payload.get("var_id", ""))
	if var_id == "":
		return
	data[var_field] = var_id
	if kind_field != "":
		data[kind_field] = "var"
	data.erase(num_field)
	if expr_field != "":
		data.erase(expr_field)
	# A nested expression may have been here before (operand dict carries
	# op/a/b directly); clear it so the slot goes cleanly back to var mode.
	data.erase("op")
	data.erase("a")
	data.erase("b")
	data.erase("rounding")
	if offset_field != "": data[offset_field] = int(payload.get("offset", 0))
	_rebuild()
	if notify: changed.emit()
	_play_drop_pulse()


# A math-expression reporter (a op b) dropped into this slot. Works for BOTH
# kinds of slot:
#   - outer value slot (expr_field set): stores into data[expr_field];
#   - a nested operand dict (kind_field set, expr_field empty — comparison
#     lhs/rhs, or an operand inside another expression): stores the expression
#     directly on the operand dict, so math reporters nest inside math
#     reporters exactly like Scratch.
func _drop_expr(expression: Dictionary, notify := true) -> void:
	var inner: Dictionary
	if expr_field != "" and data.has(expr_field) and data.get(expr_field) is Dictionary:
		inner = data.get(expr_field)
	elif expr_field != "":
		inner = {}
		data[expr_field] = inner
	else:
		inner = data
	inner.clear()
	inner.merge(expression.duplicate(true))
	data.erase(num_field)
	data.erase(var_field)
	data.erase(offset_field)
	if kind_field != "":
		data[kind_field] = "expr"
	_rebuild()
	if notify: changed.emit()
	_play_drop_pulse()


func _set_drop_highlight(on: bool) -> void:
	if _drop_highlight == on:
		return
	_drop_highlight = on
	_apply_slot_style()


func _animate_slot(target_scale: Vector2, target_modulate: Color, duration: float) -> void:
	pivot_offset = size * 0.5
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "scale", target_scale, duration)
	_motion_tween.tween_property(self, "modulate", target_modulate, duration)


func _play_drop_pulse() -> void:
	modulate = Color(1.10,1.10,1.10)
	_animate_slot(Vector2.ONE, Color.WHITE, 0.16)


func _notification(what: int) -> void:
	if get_meta("drag_preview", false): return
	if what == NOTIFICATION_DRAG_END:
		_dragging = false
		_set_drop_highlight(false)
		_animate_slot(Vector2.ONE, Color.WHITE, 0.10)
	elif what == NOTIFICATION_MOUSE_EXIT and _drop_highlight:
		if not get_global_rect().has_point(get_global_mouse_position()):
			_set_drop_highlight(false)


# ============================================
# Shared helpers
# ============================================

func _param_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.22)
	st.border_color = Color(1, 1, 1, 0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(999)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	if _drop_highlight:
		st.border_color = Color(0.50, 0.95, 0.88)
		st.set_border_width_all(2)
	return st


# PASS keeps the inner controls clickable/editable while drag-drop resolution
# walks through them to this slot (STOP controls swallow drops in this engine).
func _set_param_pass(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	if c is SpinBox:
		var le: LineEdit = c.get_line_edit()
		if le != null:
			le.mouse_filter = Control.MOUSE_FILTER_PASS

func _focus_style() -> StyleBoxFlat:
	var st := _param_style()
	st.bg_color = Color.TRANSPARENT
	st.border_color = Color(1, 1, 1, 0.9)
	st.set_border_width_all(2)
	return st

func _variable_style() -> StyleBoxFlat:
	var st := _param_style()
	st.bg_color = Color(0.28, 0.60, 0.56, 0.65)
	if not _drop_highlight: st.border_color = Color(0.28, 0.60, 0.56)
	st.content_margin_left = 8
	st.content_margin_right = 8
	return st
