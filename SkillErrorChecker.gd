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
		elif effect_id == SkillEngine.EFFECT_STOP:
			# Control block: halts the branch — no target/value to check.
			pass
		else:
			# Non-control effects must pick a target (and a side when the
			# target shape splits by faction). force_self effects skip this.
			if not SkillRegistry.force_self(effect_id):
				var tgt: String = str(eff_dict.get("target", ""))
				if tgt == "":
					errors.append(Locale.t("skill_editor.error_missing_target"))
				elif _target_needs_side(tgt):
					var side: String = str(eff_dict.get("target_side", ""))
					if side == "":
						errors.append(Locale.t("skill_editor.error_missing_target_side"))
					elif _target_side_ineffective(tgt, side):
						errors.append(Locale.t("skill_editor.error_target_ineffective"))


static func _target_needs_side(target: String) -> bool:
	return target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_ALL,
			SkillEngine.TARGET_MALE, SkillEngine.TARGET_FEMALE, SkillEngine.TARGET_NONHUMAN]


# A directed target ("单体" / "目标+相邻") with the side left at 全体 only
# ever resolves to the enemy field (see SkillTargetResolver), so the config
# silently never targets allies — surface it as a compile error.
static func _target_side_ineffective(target: String, side: String) -> bool:
	return target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] \
			and side == SkillEngine.TARGET_SIDE_ALL


# Shows a banner above the script listing every compile error (hidden when
# the skill is valid). Rebuilt cheaply on every refresh / parameter change.
# An untouched/empty skill is not an "error" — it gets a soft neutral hint so
# new users aren't scared by a red warning before they start building.
func refresh_banner() -> void:
	var effects_list: VBoxContainer = editor.get("effects_list")
	var parent: VBoxContainer = effects_list.get_parent()
	if _error_banner != null and is_instance_valid(_error_banner):
		_error_banner.queue_free()
		_error_banner = null
	var errors := collect_errors()
	if errors.is_empty():
		return
	var empty_only: bool = errors.size() == 1 and str(errors[0]) == Locale.t("skill_editor.error_empty_skill")
	_error_banner = Label.new()
	if empty_only:
		_error_banner.text = Locale.t("skill_editor.error_empty_skill")
		_error_banner.add_theme_font_size_override("font_size", 12)
		_error_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var hint_st := StyleBoxFlat.new()
		hint_st.bg_color = Color(0.16, 0.20, 0.28, 0.90)
		hint_st.border_color = Color(0.45, 0.52, 0.68, 0.6)
		hint_st.set_border_width_all(1)
		hint_st.set_corner_radius_all(4)
		hint_st.content_margin_left = 8
		hint_st.content_margin_right = 8
		hint_st.content_margin_top = 4
		hint_st.content_margin_bottom = 4
		_error_banner.add_theme_stylebox_override("normal", hint_st)
		_error_banner.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	else:
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
