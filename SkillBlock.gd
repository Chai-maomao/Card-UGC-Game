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
signal insertion_requested(parent_vbox: VBoxContainer, index: int)  # show insertion line while hovering this block
signal insertion_hidden()  # dragging left the block (or it can't accept a drop)

var effect_path: Array = []
var is_hat: bool = false
var draggable: bool = true
var _effect: Dictionary = {}
var _sentence_row: HBoxContainer
var has_else: bool = false
var body_container: VBoxContainer
var then_container: VBoxContainer
var else_container: VBoxContainer
var cond_slot: PanelContainer
var _drag_highlight: bool = false


static func category_color(category: String) -> Color:
	match category:
		"attack":
			return Color(0.72, 0.27, 0.28)  # red — damage / offense
		"defense":
			return Color(0.24, 0.58, 0.40)  # green — heal / buffs
		"utility":
			return Color(0.26, 0.50, 0.68)  # blue — hand / resources
	return Color(0.50, 0.38, 0.62)         # purple — advanced / default


static func trigger_color() -> Color:
	return Color(0.78, 0.55, 0.16)  # orange — events / triggers


static func control_color() -> Color:
	return Color(0.72, 0.60, 0.16)  # yellow — control / if-else


static func stop_color() -> Color:
	return Color(0.72, 0.18, 0.20)  # red — stop


static func repeat_color() -> Color:
	return Color(0.45, 0.35, 0.68)  # violet — repeat / loop


static func condition_color() -> Color:
	return Color(0.28, 0.60, 0.56)  # teal — condition reporters


func _apply_style(bg: Color, radius: int = 6) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = bg.darkened(0.28)
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	# Soft drop shadow gives the blocks the raised "physical puzzle piece" feel
	# of Scratch; the drag highlight temporarily enlarges it.
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)


func _make_label(text: String, size: int = 13) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	# Single-line by default: autowrap inside an HBox collapses the minimum
	# width to 1px and inflates the row height (text becomes invisible).
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	return lbl


func _make_icon_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.custom_minimum_size = Vector2(30, 26)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = text
	return btn


# Action row shared by effect / if / stop blocks. Uses plain CJK labels —
# the previous ↑/↓/⚙/✕ glyphs are not covered by Godot's default font and
# collapsed into invisible slivers.
func _build_action_buttons(head: HBoxContainer, with_edit: bool = true) -> void:
	var up_btn := _make_icon_button(Locale.t("skill_editor.btn_up"))
	up_btn.pressed.connect(func(): move_requested.emit(effect_path, -1))
	head.add_child(up_btn)
	var down_btn := _make_icon_button(Locale.t("skill_editor.btn_down"))
	down_btn.pressed.connect(func(): move_requested.emit(effect_path, 1))
	head.add_child(down_btn)
	if with_edit:
		var edit_btn := _make_icon_button(Locale.t("skill_editor.btn_edit"))
		edit_btn.pressed.connect(func(): edit_requested.emit(effect_path))
		head.add_child(edit_btn)
	var del_btn := _make_icon_button(Locale.t("skill_editor.btn_delete"))
	del_btn.pressed.connect(func(): delete_requested.emit(effect_path))
	head.add_child(del_btn)


# A recessed slot that nested blocks are stacked into (C-shaped nesting).
# Creates a dark PanelContainer attached to `parent`, then returns its inner
# VBox so blocks are stacked inside the recessed panel. The slot keeps a
# minimum height so an empty slot stays visible and hittable for the first
# drag-drop (otherwise it collapses to a sliver and drops miss it).
func _make_slot(parent: Node) -> VBoxContainer:
	var slot := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.16)
	st.set_corner_radius_all(5)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	slot.add_theme_stylebox_override("panel", st)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.custom_minimum_size = Vector2(0, 30)
	parent.add_child(slot)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.add_child(inner)
	return inner


# Event hat container: "当 攻击时" wrapping the whole skill body.
func setup_event_block(trigger_key: String) -> void:
	is_hat = true
	_apply_style(trigger_color(), 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)
	var name_text: String = Locale.term("trigger", trigger_key)
	outer.add_child(_make_label(Locale.t("skill_editor.block_trigger", [name_text]), 15))
	body_container = _make_slot(outer)


# Trigger hat block (standalone, used when the event block is hidden).
func setup_hat(trigger_key: String) -> void:
	is_hat = true
	_apply_style(trigger_color())
	var name_text: String = Locale.term("trigger", trigger_key)
	add_child(_make_label(Locale.t("skill_editor.block_trigger", [name_text]), 15))


# Effect block: colored card with title, sentence + inline parameter
# controls (Scratch-style "（）" slots), badges and action buttons.
func setup_effect(eff: Dictionary, path: Array) -> void:
	effect_path = path
	_effect = eff
	var effect_id: String = eff.get("effect", "")
	var category: String = str(SkillRegistry.effect_meta(effect_id).get("category", "utility"))
	_apply_style(category_color(category))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)

	var head := HBoxContainer.new()
	var title := _make_label(Locale.term("effect", effect_id), 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_make_probability_spin(eff))
	# Effects whose sentence already carries a draw/"最多N个" spin (the
	# view_*_draw templates) must not get a duplicate random_count control.
	var has_draw := false
	for t in _TextFormatter.effect_sentence_tokens(eff):
		if t.get("type", "") == "draw":
			has_draw = true
			break
	if not has_draw:
		head.add_child(_make_random_count_spin(eff))
	_build_action_buttons(head)
	box.add_child(head)

	_sentence_row = _build_sentence_row(eff)
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
			"value":
				# Scratch-style: the value slot accepts a variable reporter
				# oval or a nested math-expression reporter.
				var slot := ValueSlot.new()
				slot.setup(eff, "value", "value_var", "", SkillRegistry.allows_negative(effect_id), 999.0, "value_expr", "value_offset")
				slot.changed.connect(_on_param_changed)
				row.add_child(slot)
			"draw":
				row.add_child(_make_number_spin(eff, "draw"))
			"buff":
				row.add_child(_make_buff_option(eff))
			"duration":
				row.add_child(_make_number_spin(eff, "duration"))
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
	opt.add_theme_font_size_override("font_size", 12)
	for i in range(SkillRegistry.BUFF_IDS.size()):
		opt.add_item(Locale.term("buff", SkillRegistry.BUFF_IDS[i]), i)
	opt.selected = _idx_of(str(eff.get("buff_id", SkillEngine.BUFF_ATK_BOOST)), SkillRegistry.BUFF_IDS)
	opt.item_selected.connect(func(_i: int):
		_effect["buff_id"] = SkillRegistry.BUFF_IDS[opt.selected]
		_on_param_changed()
	)
	_set_param_pass(opt)
	return opt


# Inline numeric parameter (value / draw / duration / repeat count).
func _make_number_spin(eff: Dictionary, kind: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.add_theme_stylebox_override("normal", _make_param_style())
	spin.add_theme_font_size_override("font_size", 12)
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
			spin.min_value = 0.0
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
		line_edit.add_theme_font_size_override("font_size", 12)
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


# Inline per-effect trigger probability (0-100%). Rendered in the block
# header so any effect can be gated by a chance without opening the config
# form (the form keeps the same field for parity).
func _make_probability_spin(eff: Dictionary) -> SpinBox:
	var spin := SpinBox.new()
	spin.add_theme_stylebox_override("normal", _make_param_style())
	spin.add_theme_stylebox_override("hover", _make_param_style())
	spin.add_theme_font_size_override("font_size", 12)
	spin.custom_minimum_size = Vector2(52, 24)
	spin.min_value = 0.0
	spin.max_value = 100.0
	spin.value = float(int(eff.get("probability", 100)))
	spin.tooltip_text = Locale.t("skill_editor.probability")
	spin.value_changed.connect(func(v: float):
		_effect["probability"] = int(v)
		_on_param_changed()
	)
	_set_param_pass(spin)
	return spin


# Inline "最多N个目标" (random_count): when a multi-target effect resolves, the
# engine picks at most this many targets at random. 0 = no limit.
func _make_random_count_spin(eff: Dictionary) -> SpinBox:
	var spin := SpinBox.new()
	spin.add_theme_stylebox_override("normal", _make_param_style())
	spin.add_theme_stylebox_override("hover", _make_param_style())
	spin.add_theme_font_size_override("font_size", 12)
	spin.custom_minimum_size = Vector2(44, 24)
	spin.min_value = 0.0
	spin.max_value = 9.0
	spin.value = float(int(eff.get("random_count", 0)))
	spin.tooltip_text = Locale.t("skill_editor.random_count")
	spin.value_changed.connect(func(v: float):
		_effect["random_count"] = int(v)
		_on_param_changed()
	)
	_set_param_pass(spin)
	return spin


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
	effect_path = path
	_effect = eff
	has_else = str(eff.get("effect", "")) == SkillEngine.EFFECT_IF_ELSE
	_apply_style(control_color(), 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(_make_label(Locale.t("skill_editor.if_word"), 13))
	cond_slot = _make_cond_slot()
	head.add_child(cond_slot)
	head.add_child(_make_label(Locale.t("skill_editor.then_word"), 13))
	# No edit button: the condition is edited inline (Scratch-style boolean
	# block with number slots), not via a legacy condition popup.
	_build_action_buttons(head, false)
	outer.add_child(head)

	outer.add_child(_make_label(Locale.t("skill_editor.satisfy_label"), 12))
	then_container = _make_slot(outer)

	if has_else:
		outer.add_child(_make_label(Locale.t("skill_editor.else_label"), 12))
		else_container = _make_slot(outer)


# "Repeat N times" C-shaped control block: "重复 [N] 次" header plus a loop
# body slot. The count is edited inline; the body is filled by dragging blocks.
func setup_repeat_block(eff: Dictionary, path: Array) -> void:
	effect_path = path
	_effect = eff
	_apply_style(repeat_color(), 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

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

	outer.add_child(_make_label(Locale.t("skill_editor.loop_label"), 12))
	then_container = _make_slot(outer)


# The recessed condition gap in the if header. Accepts dropped boolean blocks
# (Scratch-style comparison / has-buff) and hosts the current condition (or a
# placeholder). The gap uses the same teal as the boolean palette blocks so the
# whole condition reads as one coordinated reporter.
func _make_cond_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	var st := StyleBoxFlat.new()
	var teal := condition_color()
	st.bg_color = teal
	st.border_color = teal.darkened(0.3)
	st.set_border_width_all(1)
	st.set_corner_radius_all(14)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	slot.add_theme_stylebox_override("panel", st)
	slot.set_drag_forwarding(
		Callable(self, "_cond_get_drag_data"),
		Callable(self, "_can_drop_condition"),
		Callable(self, "_drop_condition"),
	)
	# Fill the slot with the current boolean reporter (or a placeholder).
	var cond := _current_condition(_effect)
	if _cond_has_value(cond):
		slot.add_child(_build_boolean_tree(cond))
	else:
		var ph := _make_label(Locale.t("skill_editor.cond_gap_hint"), 12)
		ph.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		slot.add_child(ph)
	return slot


func _cond_has_value(cond: Dictionary) -> bool:
	if cond.has("lhs") or cond.has("logic"):
		return true
	var ctype: String = str(cond.get("condition_type", ""))
	return ctype != "" and ctype != SkillEngine.CONDITION_NONE


func _cond_get_drag_data(_pos: Vector2):
	return null


func _can_drop_condition(_pos: Vector2, data) -> bool:
	return data is Dictionary and data.get("type", "") in ["boolean_block", "logic_block", "condition_block"]


func _drop_condition(_pos: Vector2, data) -> void:
	var ptype: String = str(data.get("type", ""))
	var cond: Dictionary = {}
	if ptype == "logic_block":
		cond = _make_logic(str(data.get("logic_kind", "and")))
	elif ptype == "boolean_block":
		cond = data.get("boolean", {})
	else:
		cond = data.get("condition", {})
	if not cond.is_empty():
		# Move semantics: dragging a reporter from another if gap also clears
		# the source gap (the editor erases it via from_path).
		var src: Object = data.get("from_cond_slot", null)
		var src_path: Array = src.effect_path if src != null and is_instance_valid(src) else []
		condition_dropped.emit(effect_path, cond, src_path)


# A fresh logic block with default comparison leaves.
func _make_logic(kind: String) -> Dictionary:
	var leaf := {"op": SkillEngine.CONDITION_OP_GTE,
			"lhs": {"kind": "num", "value": 1},
			"rhs": {"kind": "num", "value": 1}}
	if kind == "not":
		return {"logic": "not", "child": leaf}
	return {"logic": kind, "lhs": leaf, "rhs": leaf}


# Condition fields may be a nested "condition" dict (new) or on the effect
# itself (legacy). Reuses the engine's accessor for consistency.
func _current_condition(eff: Dictionary) -> Dictionary:
	var c: Variant = eff.get("condition", {})
	if c is Dictionary and not c.is_empty():
		return c
	return eff


# Recursively renders a boolean condition tree: logic nodes (and/or/not) wrap
# child boolean slots; leaves are comparisons / has-buff / legacy reporters.
func _build_boolean_tree(cond: Dictionary) -> Control:
	var root: Control
	if cond.has("logic"):
		var row := _CondReporter.new()
		row.add_theme_constant_override("separation", 4)
		var logic: String = str(cond.get("logic", "and"))
		if logic == "not":
			row.add_child(_make_label(Locale.t("skill_editor.logic_not"), 12))
			row.add_child(_make_bool_sub_slot(cond, "child"))
		else:
			row.add_child(_make_bool_sub_slot(cond, "lhs"))
			var logic_sel := OptionButton.new()
			logic_sel.add_theme_stylebox_override("normal", _make_param_style())
			logic_sel.add_theme_stylebox_override("hover", _make_param_style())
			logic_sel.add_theme_stylebox_override("pressed", _make_param_style())
			logic_sel.add_theme_color_override("font_color", Color.WHITE)
			logic_sel.add_theme_font_size_override("font_size", 12)
			logic_sel.add_item(Locale.t("skill_editor.logic_and"), 0)
			logic_sel.add_item(Locale.t("skill_editor.logic_or"), 1)
			logic_sel.selected = 1 if logic == "or" else 0
			logic_sel.item_selected.connect(func(_i: int):
				cond["logic"] = "or" if logic_sel.selected == 1 else "and"
				_on_cond_tree_changed()
			)
			_set_param_pass(logic_sel)
			row.add_child(logic_sel)
			row.add_child(_make_bool_sub_slot(cond, "rhs"))
		root = row
	else:
		root = _build_leaf_boolean(cond)
	_attach_cond_drag(root, cond)
	return root


# The whole condition reporter is draggable (Scratch-style): drag it away to
# remove the condition (drop on the palette) or onto another if block's gap
# (drop there replaces that condition). The payload carries a from_cond_slot
# marker so the editor knows which block's condition to clear.
func _attach_cond_drag(root: Control, cond: Dictionary) -> void:
	var payload := {}
	if cond.has("logic"):
		payload = {"type": "logic_block", "logic_kind": str(cond.get("logic", "and")), "from_cond_slot": self}
	else:
		payload = {"type": "boolean_block", "boolean": cond.duplicate(true), "from_cond_slot": self}
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
		var lhs: Dictionary = cond.get("lhs", {"kind": "num", "value": 1})
		var rhs: Dictionary = cond.get("rhs", {"kind": "num", "value": 1})
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
func _make_bool_sub_slot(parent_cond: Dictionary, field_key: String) -> PanelContainer:
	var slot := PanelContainer.new()
	var st := StyleBoxFlat.new()
	var teal := condition_color()
	st.bg_color = Color(0, 0, 0, 0.15)
	st.border_color = teal
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	slot.add_theme_stylebox_override("panel", st)
	slot.custom_minimum_size = Vector2(120, 28)
	slot.set_drag_forwarding(
		Callable(self, "_cond_get_drag_data"),
		func(_pos: Vector2, data) -> bool:
			return data is Dictionary and data.get("type", "") in ["boolean_block", "logic_block"],
		func(_pos: Vector2, data) -> void: _drop_bool_sub(parent_cond, field_key, data),
	)
	var child: Dictionary = parent_cond.get(field_key, {})
	if not child.is_empty():
		slot.add_child(_build_boolean_tree(child))
	else:
		var ph := _make_label(Locale.t("skill_editor.cond_gap_hint"), 11)
		ph.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		slot.add_child(ph)
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
	opt.add_theme_font_size_override("font_size", 12)
	for i in range(SkillRegistry.CONDITION_OP_IDS.size()):
		opt.add_item(Locale.term("condition_op", SkillRegistry.CONDITION_OP_IDS[i]), i)
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
	spin.add_theme_font_size_override("font_size", 12)
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
	opt.add_theme_font_size_override("font_size", 12)
	for i in range(SkillRegistry.BUFF_IDS.size()):
		opt.add_item(Locale.term("buff", SkillRegistry.BUFF_IDS[i]), i)
	var cur_buff: String = str(cond.get("condition_buff_id", ""))
	if cond.has("lhs"):
		cur_buff = str(cond.get("rhs", {}).get("buff_id", ""))
	if cur_buff == "":
		cur_buff = SkillEngine.BUFF_ATK_BOOST
	opt.selected = _idx_of(cur_buff, SkillRegistry.BUFF_IDS)
	opt.item_selected.connect(func(_i: int):
		var buff_id: String = SkillRegistry.BUFF_IDS[opt.selected]
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
	effect_path = path
	_effect = {"effect": SkillEngine.EFFECT_STOP}
	_apply_style(stop_color())
	var head := HBoxContainer.new()
	var title := _make_label(Locale.t("skill_editor.stop_word"), 13)
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
	if rcount > 0:
		result.append(Locale.t("skill.max_targets", [rcount]))
	if eff.has("value_var"):
		result.append(Locale.term("value_var", eff.get("value_var", "")))
	elif eff.has("value_min") and eff.has("value_max"):
		result.append("%d-%d" % [int(eff.get("value_min", 0)), int(eff.get("value_max", 0))])
	var condition_type: String = eff.get("condition_type", SkillEngine.CONDITION_NONE)
	if condition_type != "" and condition_type != SkillEngine.CONDITION_NONE:
		result.append(Locale.t("skill_editor.condition_badge", [Locale.term("condition", condition_type)]))
	if eff.get("effect", "") == SkillEngine.EFFECT_ADD_BUFF and int(eff.get("duration", 0)) > 0:
		result.append(Locale.t("skill_editor.duration_badge", [int(eff.get("duration", 0))]))
	return result


# ============================================
# Drag & drop (Scratch-style stacking)
# ============================================

func _get_drag_data(_at_position: Vector2):
	if not draggable or is_hat or _effect.is_empty():
		return null
	var preview := duplicate()
	preview.modulate.a = 0.7
	var drag_control := Control.new()
	drag_control.add_child(preview)
	set_drag_preview(drag_control)
	return {"type": "effect_block", "effect": _effect.duplicate(true), "from_path": effect_path}


func _can_drop_data(at_position: Vector2, data) -> bool:
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
	var current: StyleBox = get_theme_stylebox("panel")
	var st: StyleBoxFlat = current.duplicate()
	if on:
		st.border_color = Color(1, 1, 1, 0.95)
		st.set_border_width_all(3)
		st.shadow_color = Color(1, 1, 1, 0.3)
		st.shadow_size = 8
	else:
		# Restore the original border tint based on block category (shadow was
		# cloned from the resting style, so it needs no special handling).
		var base: Color = st.bg_color
		st.border_color = base.darkened(0.28)
		st.set_border_width_all(2)
	add_theme_stylebox_override("panel", st)


# Dropping onto a block inserts the dragged block before/after this block
# (upper half = before, lower half = after), Scratch-style insertion. The full
# drag payload (palette effect_id OR script-internal from_path) is forwarded so
# the editor can decide: insert a fresh block or move an existing one.
func _drop_data(at_position: Vector2, data) -> void:
	_set_drag_highlight(false)
	var from_path: Array = data.get("from_path", [])
	if from_path.size() > 0 and from_path == effect_path:
		return
	var insert_after: bool = at_position.y > size.y * 0.5
	drop_requested.emit(from_path, effect_path, insert_after, data)


# Removes this block's drop highlight and hides the shared insertion line.
# Used when the drag leaves the block: blocks the pointer merely swept over
# must not stay lit (their _can_drop_data is not called again once unhovered).
func _clear_drag_feedback() -> void:
	_set_drag_highlight(false)
	insertion_hidden.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_drag_highlight(false)
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
	if mouse_ev != null and mouse_ev.button_index == MOUSE_BUTTON_RIGHT and mouse_ev.pressed:
		var at := get_global_rect().position + mouse_ev.position
		context_requested.emit(effect_path, at)
		accept_event()
