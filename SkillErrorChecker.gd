class_name SkillErrorChecker
extends RefCounted

# ============================================
# Compile-error hints for the skill editor (Scratch-style "your script can't
# run" feedback). Walks the effect tree for syntax errors, shows a red banner
# above the script, and paints a red border on empty condition gaps.
# The editor only forwards collect_errors / refresh_banner / mark_invalid.
# ============================================

var editor: Control
var _error_banner: Label


func collect_errors() -> Array:
	var errors: Array = []
	var effect_data: Array = editor.get("effect_data")
	if effect_data.is_empty():
		errors.append(Locale.t("skill_editor.error_empty_skill"))
	walk_errors(effect_data, errors)
	return errors


func walk_errors(list: Array, errors: Array) -> void:
	for eff in list:
		var eff_dict: Dictionary = eff
		var effect_id: String = str(eff_dict.get("effect", ""))
		if effect_id == SkillEngine.EFFECT_IF_ELSE or effect_id == SkillEngine.EFFECT_IF:
			var cond := SkillEngine._condition_dict(eff_dict)
			# Valid = a dropped boolean comparison / logic block (lhs or logic)
			# OR a legacy condition reporter with a concrete condition_type.
			var has_cond: bool = cond.has("lhs") or cond.has("logic") \
					or str(cond.get("condition_type", "")) not in ["", SkillEngine.CONDITION_NONE]
			if not has_cond:
				errors.append(Locale.t("skill_editor.error_missing_condition"))
			walk_errors(eff_dict.get("then_effects", []), errors)
			walk_errors(eff_dict.get("else_effects", []), errors)
		elif effect_id == SkillEngine.EFFECT_REPEAT:
			# A variable reporter oval supplies the count — only a missing
			# fixed number (no variable) below 1 is a syntax error.
			var rep_var: String = str(eff_dict.get("repeat_var", ""))
			if rep_var == "" and int(eff_dict.get("repeat_count", 0)) <= 0:
				errors.append(Locale.t("skill_editor.error_repeat_count"))
			walk_errors(eff_dict.get("then_effects", []), errors)


# Shows a red banner above the script listing every compile error (hidden when
# the skill is valid). Rebuilt cheaply on every refresh / parameter change.
func refresh_banner() -> void:
	var effects_list: VBoxContainer = editor.get("effects_list")
	var parent: VBoxContainer = effects_list.get_parent()
	if _error_banner != null and is_instance_valid(_error_banner):
		_error_banner.queue_free()
		_error_banner = null
	var errors := collect_errors()
	if errors.is_empty():
		return
	_error_banner = Label.new()
	_error_banner.text = "%s\n%s" % [Locale.t("skill_editor.error_title"), "\n".join(errors)]
	_error_banner.add_theme_font_size_override("font_size", 12)
	_error_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.62, 0.16, 0.17, 0.92)
	st.border_color = Color(0.95, 0.4, 0.4)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	_error_banner.add_theme_stylebox_override("normal", st)
	_error_banner.add_theme_color_override("font_color", Color(1, 0.92, 0.92))
	parent.add_child(_error_banner)
	parent.move_child(_error_banner, effects_list.get_index())


# Paints a red border on every if-block's condition gap that is still empty
# (Scratch-like: an unfilled boolean hole is visibly "broken").
func mark_invalid_conditions() -> void:
	var effects_list: VBoxContainer = editor.get("effects_list")
	for c in effects_list.find_children("*", "SkillBlock", true, false):
		var block := c as SkillBlock
		if block == null or block.cond_slot == null:
			continue
		var cond := SkillEngine._condition_dict(block._effect)
		var has_cond: bool = cond.has("lhs") or cond.has("logic") \
				or str(cond.get("condition_type", "")) not in ["", SkillEngine.CONDITION_NONE]
		if not has_cond:
			var st := StyleBoxFlat.new()
			st.bg_color = SkillBlock.condition_color()
			st.border_color = Color(0.95, 0.35, 0.35)
			st.set_border_width_all(2)
			st.set_corner_radius_all(14)
			st.content_margin_left = 8
			st.content_margin_right = 8
			st.content_margin_top = 2
			st.content_margin_bottom = 2
			block.cond_slot.add_theme_stylebox_override("panel", st)
