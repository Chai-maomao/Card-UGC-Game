class_name ValueSlot
extends PanelContainer

# ============================================
# Scratch-style number slot.
# Defaults to a plain SpinBox (fixed number). Dropping a variable reporter
# oval ({"type": "var_block", "var_id": ...}) into the slot switches it to a
# variable chip — clicking the chip opens a variable picker, and the small
# "x" button restores the fixed-number mode. Used for effect values, repeat
# counts and comparison operands.
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
var max_value: float = 999.0
var min_value: float = 0.0

var _mode: String = "num"       # "num" / "var" / "expr"


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
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.28, 0.60, 0.56, 0.30)
	st.border_color = Color(0.28, 0.60, 0.56, 0.85)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	add_theme_stylebox_override("panel", st)
	custom_minimum_size = Vector2(58, 26)
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


func _ready() -> void:
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
	var spin := SpinBox.new()
	spin.add_theme_stylebox_override("normal", _param_style())
	spin.add_theme_stylebox_override("hover", _param_style())
	spin.add_theme_font_size_override("font_size", 12)
	spin.custom_minimum_size = Vector2(52, 24)
	spin.allow_greater = true
	spin.min_value = min_value
	spin.max_value = max_value
	spin.value = float(int(data.get(num_field, 1)))
	var le: LineEdit = spin.get_line_edit()
	if le != null:
		le.add_theme_stylebox_override("normal", _param_style())
		le.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
		le.add_theme_font_size_override("font_size", 12)
		le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_param_pass(spin)
	spin.value_changed.connect(func(v: float):
		data[num_field] = int(v)
		if kind_field != "":
			data[kind_field] = "num"
		data.erase(var_field)
		data.erase(offset_field)
		if expr_field != "":
			data.erase(expr_field)
		changed.emit()
	)
	add_child(spin)


# ============================================
# Math-expression mode: "[a] [op] [b]" — a and b are nested number slots
# (number / variable / deeper expression), the op dropdown picks + - * / rand.
# ============================================

const EXPR_OPS := ["+", "-", "*", "/", "rand"]


func _build_expr_mode() -> void:
	var inner := _expr_inner()
	if not inner.has("op"):
		inner["op"] = "+"
	if not inner.has("a"):
		inner["a"] = {"kind": "num", "value": 1}
	if not inner.has("b"):
		inner["b"] = {"kind": "num", "value": 1}
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var slot_a := ValueSlot.new()
	slot_a.setup(inner.get("a", {"kind": "num", "value": 1}), "value", "var_id", "kind", allow_negative, max_value)
	slot_a.changed.connect(func(): changed.emit())
	row.add_child(slot_a)
	var op_sel := OptionButton.new()
	op_sel.add_theme_font_size_override("font_size", 12)
	op_sel.add_theme_color_override("font_color", Color.WHITE)
	op_sel.custom_minimum_size = Vector2(34, 24)
	for i in range(EXPR_OPS.size()):
		op_sel.add_item(_op_label(EXPR_OPS[i]), i)
	op_sel.selected = maxi(0, EXPR_OPS.find(str(inner.get("op", "+"))))
	op_sel.item_selected.connect(func(_i: int):
		inner["op"] = EXPR_OPS[op_sel.selected]
		changed.emit()
	)
	_set_param_pass(op_sel)
	row.add_child(op_sel)
	var slot_b := ValueSlot.new()
	slot_b.setup(inner.get("b", {"kind": "num", "value": 1}), "value", "var_id", "kind", allow_negative, max_value)
	slot_b.changed.connect(func(): changed.emit())
	row.add_child(slot_b)
	# The restore button must live INSIDE the row: a direct child of the
	# PanelContainer gets stretched to cover the whole slot, which would sit on
	# top of the operand slots and swallow the GUI drag/drop walk (a drop over
	# [a] [op] [b] would land on the restore button and bubble to this slot,
	# never reaching the nested operand ValueSlots).
	row.add_child(_make_restore_button())
	add_child(row)


func _op_label(op: String) -> String:
	match op:
		"-":
			return "-"
		"*":
			return "*"
		"/":
			return "/"
		"rand":
			return Locale.t("skill_editor.op_random")
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
	chip.add_theme_font_size_override("font_size", 12)
	chip.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.28, 0.60, 0.56, 0.65)
	st.border_color = Color(0.28, 0.60, 0.56)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	chip.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = Color(0.28, 0.60, 0.56, 0.85)
	chip.add_theme_stylebox_override("hover", hover)
	chip.add_theme_stylebox_override("pressed", hover)
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.pressed.connect(func(): _open_var_menu(chip))
	_set_param_pass(chip)
	row.add_child(chip)
	if offset_field != "":
		# Scratch has no offsets; this is a game-specific tweak: the variable
		# reporter reads the battlefield stat, then adds the given offset
		# ("手牌数 +2"), edited inline instead of via the config form.
		var offset := SpinBox.new()
		offset.add_theme_stylebox_override("normal", _param_style())
		offset.add_theme_stylebox_override("hover", _param_style())
		offset.add_theme_font_size_override("font_size", 12)
		offset.custom_minimum_size = Vector2(48, 24)
		offset.min_value = -999.0
		offset.max_value = 999.0
		offset.value = float(int(data.get(offset_field, 0)))
		offset.tooltip_text = Locale.t("skill_editor.value_offset")
		offset.value_changed.connect(func(v: float):
			data[offset_field] = int(v)
			changed.emit()
		)
		_set_param_pass(offset)
		row.add_child(offset)
	row.add_child(_make_restore_button())
	add_child(row)


# The small "x" button that restores a slot from variable / expression mode
# back to a plain fixed number.
func _make_restore_button() -> Button:
	var restore := Button.new()
	restore.text = "x"
	restore.tooltip_text = Locale.t("skill_editor.restore_number")
	restore.add_theme_font_size_override("font_size", 12)
	restore.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	restore.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	restore.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	restore.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	restore.custom_minimum_size = Vector2(18, 22)
	restore.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	restore.pressed.connect(clear_to_number)
	_set_param_pass(restore)
	return restore


# Restore the slot to a plain fixed number. Also used when the chip/expr is
# dragged onto the palette (drop-to-discard for variable / math reporters).
func clear_to_number() -> void:
	data.erase(var_field)
	data.erase(offset_field)
	if expr_field != "":
		data.erase(expr_field)
	if kind_field != "":
		data[kind_field] = "num"
		data.erase("op")
		data.erase("a")
		data.erase("b")
	if not data.has(num_field):
		data[num_field] = 1
	_rebuild()
	changed.emit()


func _open_var_menu(anchor: Control) -> void:
	var menu := PopupMenu.new()
	var ids: Array = SkillRegistry.VALUE_VAR_IDS
	for i in range(ids.size()):
		menu.add_item(Locale.term("value_var", ids[i]), i)
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
		_set_drag_preview_label(Locale.term("value_var", var_id))
		return {"type": "var_block", "var_id": var_id, "from_slot": self}
	if _mode == "expr":
		var inner := _expr_inner()
		var op: String = str(inner.get("op", "+"))
		_set_drag_preview_label(_op_label(op))
		return {"type": "expr_block", "expr_kind": op, "from_slot": self}
	return null


func _set_drag_preview_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.28, 0.60, 0.56, 0.85)
	st.border_color = Color(0.28, 0.60, 0.56)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	lbl.add_theme_stylebox_override("normal", st)
	var wrap := Control.new()
	wrap.add_child(lbl)
	set_drag_preview(wrap)


func _can_drop_var(_pos: Vector2, payload) -> bool:
	return payload is Dictionary and payload.get("type", "") in ["var_block", "expr_block"]


func _drop_var(_pos: Vector2, payload) -> void:
	# Move semantics: if the reporter came from another slot, clear that slot
	# (Scratch-style dragging moves the reporter, it is not copied).
	var src: Object = payload.get("from_slot", null)
	if src != null and src != self and is_instance_valid(src) and src.has_method("clear_to_number"):
		src.call("clear_to_number")
	var ptype: String = str(payload.get("type", ""))
	if ptype == "expr_block":
		_drop_expr(payload)
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
	_rebuild()
	changed.emit()


# A math-expression reporter (a op b) dropped into this slot. Works for BOTH
# kinds of slot:
#   - outer value slot (expr_field set): stores into data[expr_field];
#   - a nested operand dict (kind_field set, expr_field empty — comparison
#     lhs/rhs, or an operand inside another expression): stores the expression
#     directly on the operand dict, so math reporters nest inside math
#     reporters exactly like Scratch.
func _drop_expr(payload) -> void:
	var inner: Dictionary
	if expr_field != "" and data.has(expr_field) and data.get(expr_field) is Dictionary:
		inner = data.get(expr_field)
	elif expr_field != "":
		inner = {}
		data[expr_field] = inner
	else:
		inner = data
	inner["kind"] = "expr"
	inner["op"] = str(payload.get("expr_kind", "+"))
	inner["a"] = {"kind": "num", "value": 1}
	inner["b"] = {"kind": "num", "value": 1}
	data.erase(num_field)
	data.erase(var_field)
	data.erase(offset_field)
	if kind_field != "":
		data[kind_field] = "expr"
	_rebuild()
	changed.emit()


# ============================================
# Shared helpers
# ============================================

func _param_style() -> StyleBoxFlat:
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


# PASS keeps the inner controls clickable/editable while drag-drop resolution
# walks through them to this slot (STOP controls swallow drops in this engine).
func _set_param_pass(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	if c is SpinBox:
		var le: LineEdit = c.get_line_edit()
		if le != null:
			le.mouse_filter = Control.MOUSE_FILTER_PASS
