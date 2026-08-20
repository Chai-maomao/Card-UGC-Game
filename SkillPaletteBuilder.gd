class_name SkillPaletteBuilder
extends RefCounted

# ============================================
# Builds the left-hand palette of the skill editor: trigger hats, category
# effect blocks, control blocks (if / if-else / repeat / stop), boolean
# reporters (comparison / has-buff), logic reporters (and / or / not),
# variable ovals and math-expression reporters.
# Owns the palette button factories; the editor only forwards build().
# ============================================

var editor: Control


func build() -> void:
	var palette_vbox: VBoxContainer = editor.palette_vbox
	for child in palette_vbox.get_children():
		child.queue_free()

	# Trigger hat blocks. (Spells are locked to on_cast and have no hats.)
	if not editor.call("_is_spell"):
		_add_section(palette_vbox, Locale.t("skill_editor.palette_trigger"), true, func(box: VBoxContainer):
			for trigger_key: String in editor.call("_trigger_keys"):
				var name_text: String = Locale.term("trigger", trigger_key)
				box.add_child(palette_button(Locale.t("skill_editor.block_trigger", [name_text]),
						SkillBlock.trigger_color(), Callable(editor, "_select_trigger").bind(trigger_key)))
		)

	# Effect blocks grouped by category.
	for category in ["attack", "defense", "utility"]:
		var section_key := "skill_editor.palette_%s" % category
		_add_section(palette_vbox, Locale.t(section_key), true, func(box: VBoxContainer, cat: String = category):
			for effect_id: String in SkillRegistry.EFFECT_IDS:
				var meta: Dictionary = SkillRegistry.effect_meta(effect_id)
				if str(meta.get("category", "")) != cat:
					continue
				box.add_child(palette_button(Locale.term("effect", effect_id),
						SkillBlock.category_color(cat), Callable(editor, "_add_effect_block").bind(effect_id), effect_id))
		)

	# Control blocks (if / if-else / repeat / stop). Draggable like every other palette block.
	_add_section(palette_vbox, Locale.t("skill_editor.palette_control"), true, func(box: VBoxContainer):
		box.add_child(palette_button(Locale.t("skill_editor.palette_if"), SkillBlock.control_color(),
				Callable(editor, "_add_if_block"), SkillEngine.EFFECT_IF))
		box.add_child(palette_button(Locale.t("skill_editor.palette_if_else"), SkillBlock.control_color(),
				Callable(editor, "_add_if_else_block"), SkillEngine.EFFECT_IF_ELSE))
		box.add_child(palette_button(Locale.t("skill_editor.palette_repeat"), SkillBlock.repeat_color(),
				Callable(editor, "_add_repeat_block"), SkillEngine.EFFECT_REPEAT))
		box.add_child(palette_button(Locale.t("skill_editor.palette_stop"), SkillBlock.stop_color(),
				Callable(editor, "_add_stop_block"), SkillEngine.EFFECT_STOP))
	)

	# Boolean reporter blocks (Scratch-style comparisons) — dropped into an if
	# block's condition gap. Each comparison takes two number slots that accept
	# variable reporter ovals.
	_add_section(palette_vbox, Locale.t("skill_editor.palette_boolean"), true, func(box: VBoxContainer):
		box.add_child(boolean_palette_button(Locale.t("skill_editor.boolean_compare"), "compare"))
		box.add_child(boolean_palette_button(Locale.t("skill_editor.boolean_has_buff"), "has_buff"))
	)

	# The reporter drawers below (logic / variable / math / target) are for
	# advanced editing — collapsed by default so the common blocks stay in
	# sight. Click a section header to expand it.
	_add_section(palette_vbox, Locale.t("skill_editor.palette_logic"), false, func(box: VBoxContainer):
		for kind: String in ["and", "or", "not"]:
			box.add_child(logic_palette_button(logic_label(kind), kind))
	)

	_add_section(palette_vbox, Locale.t("skill_editor.palette_variable"), false, func(box: VBoxContainer):
		for var_id: String in SkillRegistry.VALUE_VAR_IDS:
			box.add_child(variable_palette_button(Locale.term("value_var", var_id), var_id))
	)

	_add_section(palette_vbox, Locale.t("skill_editor.palette_math"), false, func(box: VBoxContainer):
		for kind: String in ValueSlot.EXPR_OPS:
			box.add_child(expr_palette_button(expr_palette_label(kind), kind))
	)

	_add_section(palette_vbox, Locale.t("skill_editor.palette_target"), false, func(box: VBoxContainer):
		for t_id in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_ALL,
				SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES]:
			box.add_child(target_palette_button(Locale.term("target", t_id), t_id, true))
		for s_id in [SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALLY, SkillEngine.TARGET_SIDE_ALL]:
			box.add_child(target_palette_button(Locale.term("target_side", s_id), s_id, false))
	)


# Adds a collapsible palette section: a clickable header ("- 触发" / "+ 触发")
# followed by a VBox holding the section's blocks. Collapsed sections stay
# hidden so the palette scroll never buries the common blocks.
func _add_section(palette_vbox: VBoxContainer, title_text: String, default_open: bool, builder: Callable) -> void:
	var header := Button.new()
	header.text = "%s %s" % ["-" if default_open else "+", title_text]
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	header.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.72))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.35, 0.42, 0.58, 0.20)
	st.set_corner_radius_all(4)
	st.content_margin_left = 6
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	header.add_theme_stylebox_override("normal", st)
	var hover_st: StyleBoxFlat = st.duplicate()
	hover_st.bg_color = Color(0.45, 0.52, 0.68, 0.30)
	header.add_theme_stylebox_override("hover", hover_st)
	var pressed_st: StyleBoxFlat = st.duplicate()
	pressed_st.bg_color = Color(0.25, 0.30, 0.42, 0.30)
	header.add_theme_stylebox_override("pressed", pressed_st)
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.set_meta("section_title", title_text)
	header.set_meta("user_open", default_open)
	palette_vbox.add_child(header)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.visible = default_open
	palette_vbox.add_child(box)

	header.pressed.connect(func():
		box.visible = not box.visible
		header.set_meta("user_open", box.visible)
		header.text = "%s %s" % ["-" if box.visible else "+", title_text]
	)

	builder.call(box)


func palette_button(text: String, color: Color, cb: Callable, effect_id: String = "") -> Button:
	var btn: Button = SkillPaletteBlock.new() if effect_id != "" else Button.new()
	if btn is SkillPaletteBlock:
		(btn as SkillPaletteBlock).effect_id = effect_id
		(btn as SkillPaletteBlock).palette_drop_requested.connect(Callable(editor, "_on_block_delete_path"))
		# PASS keeps the button clickable (events also reach the parent) while
		# letting drag-drop resolution walk through it to the palette panel.
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 13)
	_apply_palette_style(btn, color, 6)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Locale.t("skill_editor.hint_click")
	btn.pressed.connect(cb)
	return btn


# Variable reporter palette block: an oval (Scratch-style) that can only be
# dragged into a number slot / comparison operand; clicking is a no-op.
func variable_palette_button(text: String, var_id: String) -> Button:
	var btn := SkillPaletteBlock.new()
	btn.var_id = var_id
	btn.palette_drop_requested.connect(Callable(editor, "_on_block_delete_path"))
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 13)
	var color := SkillBlock.condition_color()
	_apply_palette_style(btn, color, 14, false)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Locale.t("skill_editor.variable_drag_hint")
	btn.pressed.connect(func(): pass)
	return btn


# Boolean reporter palette block ("[op1] [op] [op2]" comparison or
# "target has buff"). Dropped into an if block's condition gap.
func boolean_palette_button(text: String, kind: String) -> Button:
	var btn := SkillPaletteBlock.new()
	btn.boolean_kind = kind
	btn.palette_drop_requested.connect(Callable(editor, "_on_block_delete_path"))
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 13)
	var color := SkillBlock.condition_color()
	_apply_palette_style(btn, color, 9)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Locale.t("skill_editor.condition_drag_hint")
	btn.pressed.connect(func(): pass)
	return btn


# Target / side reporter palette block: a blue (target) or amber (side) oval
# dropped into the matching slot of an effect sentence.
func target_palette_button(text: String, id: String, is_target: bool) -> Button:
	var btn := SkillPaletteBlock.new()
	if is_target:
		btn.target_kind = id
	else:
		btn.side_kind = id
	btn.palette_drop_requested.connect(Callable(editor, "_on_block_delete_path"))
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 13)
	var color: Color = SkillBlock.target_color() if is_target else SkillBlock.side_color()
	_apply_palette_style(btn, color, 14, false)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Locale.t("skill_editor.target_drag_hint")
	btn.pressed.connect(func(): pass)
	return btn


# Math-expression reporter palette block ("[a] [op] [b]"), draggable into any
# number slot. Round-cornered like the variable ovals, but a violet tint to
# match the operators.
func expr_palette_button(text: String, kind: String) -> Button:
	var btn := SkillPaletteBlock.new()
	btn.expr_kind = kind
	btn.palette_drop_requested.connect(Callable(editor, "_on_block_delete_path"))
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 13)
	var color := SkillBlock.math_color()
	_apply_palette_style(btn, color, 14, false)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Locale.t("skill_editor.math_drag_hint")
	btn.pressed.connect(func(): pass)
	return btn


func expr_palette_label(kind: String) -> String:
	match kind:
		"-":
			return "a - b"
		"*":
			return "a * b"
		"/":
			return "a / b"
		"rand":
			return Locale.t("skill_editor.op_random") + Locale.t("skill_editor.op_range")
		_:
			return "a + b"


# Logic reporter palette block ("A AND B" / "A OR B" / "NOT A"), dropped into
# an if condition gap or another logic node's sub-slot.
func logic_palette_button(text: String, kind: String) -> Button:
	var btn := SkillPaletteBlock.new()
	btn.logic_kind = kind
	btn.palette_drop_requested.connect(Callable(editor, "_on_block_delete_path"))
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 13)
	var color := SkillBlock.condition_color().darkened(0.15)
	_apply_palette_style(btn, color, 12, false)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Locale.t("skill_editor.logic_drag_hint")
	btn.pressed.connect(func(): pass)
	return btn


# One visual language for every palette block: a darker material base,
# semantic edge and lifted hover state. Keep horizontal borders and padding
# symmetric so pressed/focus layers cover the button evenly on both sides.
func _apply_palette_style(btn: Button, color: Color, radius: int, _left_accent: bool = true) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.08)
	normal.border_color = color.darkened(0.22)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(radius)
	normal.shadow_size = 0
	normal.content_margin_left = 9
	normal.content_margin_right = 9
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", normal)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = color.lightened(0.08)
	hover.border_color = color.lightened(0.14)
	hover.shadow_size = 0
	btn.add_theme_stylebox_override("hover", hover)

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = color.darkened(0.18)
	pressed.border_color = color.lightened(0.08)
	pressed.shadow_size = 0
	pressed.content_margin_top = 6
	pressed.content_margin_bottom = 4
	btn.add_theme_stylebox_override("pressed", pressed)

	# Focus must not paint another filled StyleBox over the current button
	# state; that overlay exposed the old asymmetric left/right border widths.
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.95, 1.0))


func logic_label(kind: String) -> String:
	match kind:
		"or":
			return Locale.t("skill_editor.logic_or")
		"not":
			return Locale.t("skill_editor.logic_not")
		_:
			return Locale.t("skill_editor.logic_and")
