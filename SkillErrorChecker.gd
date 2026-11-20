class_name SkillErrorChecker
extends RefCounted

const _UgcSafety = preload("res://UgcSafety.gd")

# ============================================
# Compile-error hints for the skill editor (Scratch-style "your script can't
# run" feedback). Walks the effect tree for syntax errors, shows a red banner
# above the script, and paints a red border on empty condition gaps.
# The editor only forwards collect_errors / refresh_banner / mark_invalid.
# ============================================

var editor: Control
var _error_banner: Button


func collect_errors() -> Array:
	var errors: Array = []
	for issue in collect_issues():
		if not errors.has(issue.get("message", "")):
			errors.append(issue.get("message", ""))
	return errors


func collect_issues() -> Array:
	var issues: Array = []
	var effect_data: Array = editor.get("effect_data")
	if effect_data.is_empty():
		issues.append({"message": Locale.t("skill_editor.error_empty_skill"), "path": [], "kind": "empty"})
	walk_issues(effect_data, issues, [])
	var trigger_id := str(editor.get("current_trigger_key"))
	for issue in collect_semantic_issues(effect_data, trigger_id, editor.call("_is_talent_mode")):
		issues.append(issue)
	for safety_issue in _UgcSafety.validate_skill({"effects": effect_data}):
		var path: Array = safety_issue.get("path", []).duplicate()
		if not path.is_empty() and path[0] == "effects":
			path.pop_front()
		issues.append({"message": _safety_issue_message(safety_issue), "path": path, "kind": "ugc_safety"})
	return issues


static func collect_semantic_issues(effects: Array, trigger_id: String = "", talent_mode: bool = false) -> Array:
	var issues: Array = []
	_walk_semantic_issues(effects, trigger_id, issues, [], talent_mode)
	var directed_sides: Dictionary = {}
	_collect_directed_sides(effects, directed_sides)
	if directed_sides.has(SkillEngine.TARGET_SIDE_ENEMY) and directed_sides.has(SkillEngine.TARGET_SIDE_ALLY):
		issues.append({"message": Locale.t("skill_editor.error_mixed_directed_sides"), "path": [], "kind": "target_side"})
	return issues


static func _collect_directed_sides(effects: Array, found: Dictionary) -> void:
	for value in effects:
		if not value is Dictionary:
			continue
		var eff: Dictionary = value
		var effect_id := str(eff.get("effect", ""))
		if SkillRegistry.requires_live_target(effect_id) \
				and str(eff.get("target", "")) in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			var side := str(eff.get("target_side", ""))
			if side in [SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALLY]:
				found[side] = true
		for branch in ["then_effects", "else_effects"]:
			var nested = eff.get(branch, [])
			if nested is Array:
				_collect_directed_sides(nested, found)


static func _walk_semantic_issues(effects: Array, trigger_id: String, issues: Array, base_path: Array, talent_mode: bool = false) -> void:
	for index in range(effects.size()):
		if not effects[index] is Dictionary:
			continue
		var eff: Dictionary = effects[index]
		var path := base_path + [index]
		var effect_id := str(eff.get("effect", ""))
		if effect_id in [SkillEngine.EFFECT_IF, SkillEngine.EFFECT_IF_ELSE]:
			if _condition_uses_target(SkillEngine._condition_dict(eff)):
				issues.append({"message": Locale.t("skill_editor.error_target_reporter_without_target"), "path": path, "kind": "condition"})
		elif effect_id == SkillEngine.EFFECT_REPEAT:
			if SkillRegistry.is_target_relative_var(str(eff.get("repeat_var", ""))) \
					or _operand_uses_target(eff.get("repeat_expr", {})):
				issues.append({"message": Locale.t("skill_editor.error_target_reporter_without_target"), "path": path, "kind": "repeat"})
		elif not SkillRegistry.requires_live_target(effect_id):
			if SkillRegistry.is_target_relative_var(str(eff.get("value_var", ""))) \
					or _operand_uses_target(eff.get("value_expr", {})) \
					or _condition_uses_target(SkillEngine._condition_dict(eff)):
				issues.append({"message": Locale.t("skill_editor.error_target_reporter_without_target"), "path": path, "kind": "value"})
		elif str(eff.get("target", "")) in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] \
				and trigger_id in [SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_TURN_START,
					SkillEngine.TRIGGER_ON_TURN_END, SkillEngine.TRIGGER_ON_HEALED, SkillEngine.TRIGGER_ON_BOARD_CHANGED]:
			issues.append({"message": Locale.t("skill_editor.error_trigger_has_no_target"), "path": path, "kind": "target"})
		if str(eff.get("target", "")) == SkillEngine.TARGET_PLAYER \
				and not SkillRegistry.allows_player_target(effect_id):
			issues.append({"message": Locale.t("skill_editor.error_player_target_effect"), "path": path, "kind": "target"})
		if effect_id == SkillEngine.EFFECT_CLONE_ENEMY:
			if str(eff.get("target", "")) not in SkillRegistry.allowed_targets(effect_id):
				issues.append({"message": Locale.t("skill_editor.error_clone_target"), "path": path, "kind": "target"})
			if str(eff.get("target_side", "")) != SkillEngine.TARGET_SIDE_ENEMY:
				issues.append({"message": Locale.t("skill_editor.error_clone_side"), "path": path, "kind": "target_side"})
		if effect_id == SkillEngine.EFFECT_CHARM and trigger_id == SkillEngine.TRIGGER_ON_DEATH \
				and str(eff.get("target", "")) in [SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES]:
			issues.append({"message": Locale.t("skill_editor.error_death_charm_self"), "path": path, "kind": "target"})
		var is_talent_trigger := talent_mode or trigger_id == SkillEngine.TRIGGER_ALWAYS
		if (is_talent_trigger or SkillRegistry.is_talent_only_effect(effect_id)) and not SkillRegistry.is_effect_allowed_for_talent_trigger(effect_id, trigger_id):
			issues.append({"message": Locale.t("skill_editor.error_talent_effect_trigger"), "path": path, "kind": "effect"})
		if effect_id == SkillEngine.EFFECT_ADD_BUFF and str(eff.get("buff_id", "")) == "":
			issues.append({"message": Locale.t("skill_editor.error_missing_buff"), "path": path, "kind": "buff"})
		for branch in ["then_effects", "else_effects"]:
			var nested = eff.get(branch, [])
			if nested is Array:
				_walk_semantic_issues(nested, trigger_id, issues, path + ["then" if branch == "then_effects" else "else"], talent_mode)


static func _missing_condition_slots(cond: Dictionary, path: Array = [], depth: int = 0) -> Array:
	if depth > _UgcSafety.MAX_EXPRESSION_NESTING_DEPTH: return []
	if cond.has("logic"):
		var missing: Array = []
		var keys: Array = ["child"] if cond.get("logic") == "not" else ["lhs", "rhs"]
		for key in keys:
			missing.append_array(_missing_condition_slots(cond.get(key, {}), path + [key], depth + 1))
		return missing
	if cond.has("lhs") and cond.has("rhs") or str(cond.get("condition_type", "")) not in ["", SkillEngine.CONDITION_NONE]: return []
	return [path]

static func _condition_uses_target(cond: Dictionary) -> bool:
	if SkillRegistry.is_target_relative_condition(str(cond.get("condition_type", ""))):
		return true
	if cond.has("logic"):
		if str(cond.get("logic", "")) == "not":
			return _condition_uses_target(cond.get("child", {}))
		return _condition_uses_target(cond.get("lhs", {})) or _condition_uses_target(cond.get("rhs", {}))
	if str(cond.get("op", "")) == "has":
		return true
	return _operand_uses_target(cond.get("lhs", {})) or _operand_uses_target(cond.get("rhs", {}))


static func _operand_uses_target(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var operand: Dictionary = value
	if str(operand.get("kind", "")) == "var":
		return SkillRegistry.is_target_relative_var(str(operand.get("var_id", "")))
	if str(operand.get("kind", "")) == "expr":
		return _operand_uses_target(operand.get("a", {})) or _operand_uses_target(operand.get("b", {}))
	return false


func _safety_issue_message(issue: Dictionary) -> String:
	var code := str(issue.get("code", ""))
	var details: Dictionary = issue.get("details", {})
	match code:
		"repeat_limit":
			return Locale.t("skill_editor.error_repeat_limit", [int(details.get("limit", _UgcSafety.MAX_REPEAT_COUNT))])
		"effect_depth":
			return Locale.t("skill_editor.error_effect_depth", [int(details.get("limit", _UgcSafety.MAX_EFFECT_NESTING_DEPTH))])
		"expression_depth":
			return Locale.t("skill_editor.error_expression_depth", [int(details.get("limit", _UgcSafety.MAX_EXPRESSION_NESTING_DEPTH))])
		"skill_node_limit":
			return Locale.t("skill_editor.error_skill_node_limit", [int(details.get("limit", _UgcSafety.MAX_EFFECT_NODES_PER_SKILL))])
	return Locale.t("skill_editor.error_invalid_structure")


func walk_errors(list: Array, errors: Array) -> void:
	var issues: Array = []
	walk_issues(list, issues, [])
	for issue in issues:
		if not errors.has(issue.get("message", "")):
			errors.append(issue.get("message", ""))


func walk_issues(list: Array, issues: Array, base_path: Array, talent_mode: bool = false) -> void:
	for index in range(list.size()):
		var eff = list[index]
		var eff_dict: Dictionary = eff
		var path := base_path.duplicate()
		path.append(index)
		var effect_id: String = str(eff_dict.get("effect", ""))
		if effect_id in [SkillEngine.EFFECT_IF, SkillEngine.EFFECT_IF_ELSE]:
			_number_issues_in_condition(SkillEngine._condition_dict(eff_dict), issues, path)
		elif effect_id == SkillEngine.EFFECT_REPEAT and eff_dict.has("repeat_expr"):
			_number_issues(eff_dict.repeat_expr, issues, path, "repeat")
		elif effect_id != SkillEngine.EFFECT_REPEAT and SkillRegistry.effect_uses_value(eff_dict):
			if eff_dict.has("value_expr"):
				_number_issues(eff_dict.value_expr, issues, path)
			elif str(eff_dict.get("value_var", "")) == "" and not eff_dict.has("value") and not (eff_dict.has("value_min") and eff_dict.has("value_max")):
				issues.append({"message":Locale.t("skill_editor.error_missing_value"), "path":path, "kind":"value", "operand":eff_dict})
		if effect_id == SkillEngine.EFFECT_IF_ELSE or effect_id == SkillEngine.EFFECT_IF:
			var cond := SkillEngine._condition_dict(eff_dict)
			# Valid = a dropped boolean comparison / logic block (lhs or logic)
			# OR a legacy condition reporter with a concrete condition_type.
			for socket_path in _missing_condition_slots(cond):
				issues.append({"message": Locale.t("skill_editor.error_missing_condition"), "path": path, "kind": "condition", "condition_path":socket_path})
			var then_path := path.duplicate()
			then_path.append("then")
			walk_issues(eff_dict.get("then_effects", []), issues, then_path)
			var else_path := path.duplicate()
			else_path.append("else")
			walk_issues(eff_dict.get("else_effects", []), issues, else_path)
		elif effect_id == SkillEngine.EFFECT_REPEAT:
			# A variable reporter oval supplies the count — only a missing
			# fixed number (no variable) below 1 is a syntax error.
			var rep_var: String = str(eff_dict.get("repeat_var", ""))
			if rep_var == "" and not eff_dict.has("repeat_expr") and int(eff_dict.get("repeat_count", 0)) <= 0:
				issues.append({"message": Locale.t("skill_editor.error_repeat_count"), "path": path, "kind": "repeat"})
			var repeat_path := path.duplicate()
			repeat_path.append("then")
			walk_issues(eff_dict.get("then_effects", []), issues, repeat_path)
		elif effect_id == SkillEngine.EFFECT_STOP:
			# Control block: halts the branch — no target/value to check.
			pass
		else:
			# Non-control effects must pick a target (and a side when the
			# target shape splits by faction). force_self effects skip this.
			if not SkillRegistry.force_self(effect_id):
				var checked_effect := SkillEngine.normalize_effect_target(eff_dict)
				var tgt: String = str(checked_effect.get("target", ""))
				if tgt == "":
					issues.append({"message": Locale.t("skill_editor.error_missing_target"), "path": path, "kind": "target"})
				# Reduce-cost's target is a hand-card selection shape. Its side is
				# intentionally "all" and must not be checked as a battlefield side.
				elif effect_id != SkillEngine.EFFECT_ZERO_COST and _target_needs_side(tgt):
					var side: String = str(checked_effect.get("target_side", ""))
					if side == "":
						issues.append({"message": Locale.t("skill_editor.error_missing_target_side"), "path": path, "kind": "target_side"})
					elif _target_side_ineffective(tgt, side):
						var message_key := "skill_editor.error_player_target_side" if tgt == SkillEngine.TARGET_PLAYER else "skill_editor.error_target_ineffective"
						issues.append({"message": Locale.t(message_key), "path": path, "kind": "target_side"})
			if effect_id == SkillEngine.EFFECT_ZERO_COST \
					and str(eff_dict.get("cost_reduction_mode", SkillRegistry.COST_REDUCTION_TURN)) not in SkillRegistry.COST_REDUCTION_MODES:
				issues.append({"message": Locale.t("skill_editor.error_cost_reduction_mode"), "path": path, "kind": "cost_mode"})


static func _target_needs_side(target: String) -> bool:
	return target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_ALL,
			SkillEngine.TARGET_PLAYER, SkillEngine.TARGET_MALE, SkillEngine.TARGET_FEMALE, SkillEngine.TARGET_NONHUMAN]

static func _number_issues(operand: Dictionary, issues: Array, path: Array, kind := "value") -> void:
	if operand.get("kind") == "expr":
		_number_issues(operand.get("a", {}), issues, path, kind)
		_number_issues(operand.get("b", {}), issues, path, kind)
	elif operand.get("kind") != "var" and not operand.has("value"):
		issues.append({"message":Locale.t("skill_editor.error_missing_value"), "path":path, "kind":kind, "operand":operand})

static func _number_issues_in_condition(condition: Dictionary, issues: Array, path: Array) -> void:
	if condition.has("logic"):
		for key in (["child"] if condition.logic == "not" else ["lhs", "rhs"]):
			_number_issues_in_condition(condition.get(key, {}), issues, path)
	elif condition.has("lhs") and condition.get("op") != "has":
		_number_issues(condition.get("lhs", {}), issues, path)
		_number_issues(condition.get("rhs", {}), issues, path)


# A directed target ("单体" / "目标+相邻") with the side left at 全体 only
# ever resolves to the enemy field (see SkillTargetResolver), so the config
# silently never targets allies — surface it as a compile error.
static func _target_side_ineffective(target: String, side: String) -> bool:
	return target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_PLAYER] \
			and side == SkillEngine.TARGET_SIDE_ALL


# Kept as a cleanup hook for an already-open editor; errors are shown on demand.
func refresh_banner() -> void:
	# Validation belongs to explicit Compile/Save actions, not a permanent
	# document header. Retire any banner retained by an already-open editor.
	if is_instance_valid(_error_banner):
		_error_banner.queue_free()
		_error_banner = null


func mark_invalid_conditions() -> void:
	var requested: bool = editor.get("validation_requested")
	var issues: Array = collect_issues() if requested else []
	for candidate in editor.effects_list.find_children("*", "SkillBlock", true, false):
		var block := candidate as SkillBlock
		if block.is_hat: continue
		var own_issues: Array = []
		for issue in issues:
			var path: Array = issue.get("path", [])
			if path == block.effect_path:
				own_issues.append(issue)
			elif str(issue.get("kind", "")) == "ugc_safety" and path.slice(0,block.effect_path.size()) == block.effect_path:
				# A structural path can name an expression field within this block.
				if path.size() > block.effect_path.size() and path[block.effect_path.size()] is String and str(path[block.effect_path.size()]) not in ["then","else"]:
					own_issues.append(issue)
		block.mark_validation_fields(own_issues)
