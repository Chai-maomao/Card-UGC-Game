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

	# Trigger hat blocks.
	palette_vbox.add_child(section_title(Locale.t("skill_editor.palette_trigger")))
	if not editor.call("_is_spell"):
		for trigger_key: String in editor.call("_trigger_keys"):
			var name_text: String = Locale.term("trigger", trigger_key)
			palette_vbox.add_child(palette_button(Locale.t("skill_editor.block_trigger", [name_text]),
					SkillBlock.trigger_color(), Callable(editor, "_select_trigger").bind(trigger_key)))

	# Effect blocks grouped by category.
	for category in ["attack", "defense", "utility"]:
		var section_key := "skill_editor.palette_%s" % category
		palette_vbox.add_child(section_title(Locale.t(section_key)))
		for effect_id: String in SkillRegistry.EFFECT_IDS:
			var meta: Dictionary = SkillRegistry.effect_meta(effect_id)
			if str(meta.get("category", "")) != category:
				continue
			palette_vbox.add_child(palette_button(Locale.term("effect", effect_id),
					SkillBlock.category_color(category), Callable(editor, "_add_effect_block").bind(effect_id), effect_id))

	# Control blocks (if / if-else / repeat / stop). Draggable like every other palette block.
	palette_vbox.add_child(section_title(Locale.t("skill_editor.palette_control")))
	palette_vbox.add_child(palette_button(Locale.t("skill_editor.palette_if"), SkillBlock.control_color(),
			Callable(editor, "_add_if_block"), SkillEngine.EFFECT_IF))
	palette_vbox.add_child(palette_button(Locale.t("skill_editor.palette_if_else"), SkillBlock.control_color(),
			Callable(editor, "_add_if_else_block"), SkillEngine.EFFECT_IF_ELSE))
	palette_vbox.add_child(palette_button(Locale.t("skill_editor.palette_repeat"), SkillBlock.repeat_color(),
			Callable(editor, "_add_repeat_block"), SkillEngine.EFFECT_REPEAT))
	palette_vbox.add_child(palette_button(Locale.t("skill_editor.palette_stop"), SkillBlock.stop_color(),
			Callable(editor, "_add_stop_block"), SkillEngine.EFFECT_STOP))

	# Boolean reporter blocks (Scratch-style comparisons) — dropped into an if
	# block's condition gap. Each comparison takes two number slots that accept
	# variable reporter ovals.
	palette_vbox.add_child(section_title(Locale.t("skill_editor.palette_boolean")))
	palette_vbox.add_child(boolean_palette_button(Locale.t("skill_editor.boolean_compare"), "compare"))
	palette_vbox.add_child(boolean_palette_button(Locale.t("skill_editor.boolean_has_buff"), "has_buff"))

	# Logic reporters — combine comparisons ("hand>=2 AND target<=50%").
	palette_vbox.add_child(section_title(Locale.t("skill_editor.palette_logic")))
	for kind: String in ["and", "or", "not"]:
		palette_vbox.add_child(logic_palette_button(logic_label(kind), kind))

	# Variable reporter ovals — dragged into number slots (effect values,
	# repeat counts, comparison operands).
	palette_vbox.add_child(section_title(Locale.t("skill_editor.palette_variable")))
	for var_id: String in SkillRegistry.VALUE_VAR_IDS:
		palette_vbox.add_child(variable_palette_button(Locale.term("value_var", var_id), var_id))

	# Math-expression reporters — dragged into number slots; both sides are
	# themselves fillable number slots (Scratch-style nested math).
	palette_vbox.add_child(section_title(Locale.t("skill_editor.palette_math")))
	for kind: String in ValueSlot.EXPR_OPS:
		palette_vbox.add_child(expr_palette_button(expr_palette_label(kind), kind))

	# Target selector reporters — dropped into the target / side slots of an
	# effect sentence ("对 [友方/敌方] [目标] 造成 …").
	palette_vbox.add_child(section_title(Locale.t("skill_editor.palette_target")))
	for t_id in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_ALL,
			SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES]:
		palette_vbox.add_child(target_palette_button(Locale.term("target", t_id), t_id, true))
	for s_id in [SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALLY, SkillEngine.TARGET_SIDE_ALL]:
		palette_vbox.add_child(target_palette_button(Locale.term("target_side", s_id), s_id, false))


func section_title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	return lbl


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
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = color.darkened(0.25)
	st.set_border_width_all(1)
	st.set_corner_radius_all(5)
	st.content_margin_left = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = st.duplicate()
	pressed.bg_color = color.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = color.darkened(0.25)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = st.duplicate()
	pressed.bg_color = color.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
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
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = color.darkened(0.25)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.content_margin_left = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = st.duplicate()
	pressed.bg_color = color.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
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
	var color: Color = Color(0.30, 0.50, 0.80) if is_target else Color(0.62, 0.52, 0.30)
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = color.darkened(0.25)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = st.duplicate()
	pressed.bg_color = color.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
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
	var color := Color(0.45, 0.35, 0.68)  # violet — math / operators
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = color.darkened(0.25)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = st.duplicate()
	pressed.bg_color = color.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
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
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = color.darkened(0.25)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 10
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal", st)
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = st.duplicate()
	pressed.bg_color = color.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Locale.t("skill_editor.logic_drag_hint")
	btn.pressed.connect(func(): pass)
	return btn


func logic_label(kind: String) -> String:
	match kind:
		"or":
			return Locale.t("skill_editor.logic_or")
		"not":
			return Locale.t("skill_editor.logic_not")
		_:
			return Locale.t("skill_editor.logic_and")
