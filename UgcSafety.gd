class_name UgcSafety
extends RefCounted

# One policy shared by editor validation, import validation, and runtime guards.
const MAX_REPEAT_COUNT := 20
const MAX_EFFECT_NESTING_DEPTH := 8
const MAX_EXPRESSION_NESTING_DEPTH := 12
const MAX_EFFECT_NODES_PER_SKILL := 100
const MAX_EFFECT_NODES_PER_CARD := 200
const MAX_SKILLS_PER_CARD := 3
const MAX_EXECUTED_EFFECT_NODES := 200
const MAX_TRIGGER_CHAIN_DEPTH := 16
const MAX_SHARE_PACKAGE_BYTES := 12 * 1024 * 1024


static func validate_skill(skill: Variant) -> Array:
	var issues: Array = []
	if not (skill is Dictionary):
		return [_issue("skill_type", [], {})]
	var skill_dict: Dictionary = skill
	var effects = skill_dict.get("effects", [])
	if not (effects is Array):
		return [_issue("effects_type", ["effects"], {})]
	_validate_effect_tree(effects, issues)
	return issues


static func validate_serialized_card(card: Variant) -> Array:
	var issues: Array = []
	if not (card is Dictionary):
		return [_issue("card_type", [], {})]
	var card_dict: Dictionary = card
	var skills = card_dict.get("skills", [])
	if not (skills is Array):
		return [_issue("skills_type", ["skills"], {})]
	if skills.size() > MAX_SKILLS_PER_CARD:
		issues.append(_issue("too_many_skills", ["skills"], {"limit": MAX_SKILLS_PER_CARD, "actual": skills.size()}))
	var total_nodes := 0
	for index in range(mini(skills.size(), MAX_SKILLS_PER_CARD + 1)):
		var skill_issues := validate_skill(skills[index])
		for issue in skill_issues:
			var copy: Dictionary = issue.duplicate(true)
			var path: Array = ["skills", index]
			path.append_array(copy.get("path", []))
			copy["path"] = path
			issues.append(copy)
		total_nodes += count_effect_nodes(skills[index])
	if total_nodes > MAX_EFFECT_NODES_PER_CARD:
		issues.append(_issue("card_node_limit", ["skills"], {"limit": MAX_EFFECT_NODES_PER_CARD, "actual": total_nodes}))
	return issues


static func validate_draft_card(draft: Dictionary) -> Array:
	var serialized := {"skills": []}
	for key in ["skill1", "skill2", "skill3"]:
		var skill = draft.get(key, {})
		if skill is Dictionary and not skill.is_empty():
			serialized["skills"].append(skill)
	return validate_serialized_card(serialized)


static func count_effect_nodes(skill: Variant) -> int:
	if not (skill is Dictionary):
		return 0
	var effects = (skill as Dictionary).get("effects", [])
	if not (effects is Array):
		return 0
	var count := 0
	var stack: Array = [effects]
	while not stack.is_empty() and count <= MAX_EFFECT_NODES_PER_CARD + 1:
		var list = stack.pop_back()
		if not (list is Array):
			continue
		for effect in list:
			if not (effect is Dictionary):
				continue
			count += 1
			if count > MAX_EFFECT_NODES_PER_CARD:
				return count
			var effect_dict: Dictionary = effect
			for branch in ["then_effects", "else_effects"]:
				var nested = effect_dict.get(branch, [])
				if nested is Array and not nested.is_empty():
					stack.append(nested)
	return count


static func first_error_text(issues: Array) -> String:
	if issues.is_empty():
		return ""
	var issue: Dictionary = issues[0]
	return "%s (%s)" % [str(issue.get("code", "ugc_invalid")), path_text(issue.get("path", []))]


static func path_text(path: Array) -> String:
	if path.is_empty():
		return "root"
	var parts: Array[String] = []
	for part in path:
		parts.append(str(part))
	return ".".join(parts)


static func _validate_effect_tree(effects: Array, issues: Array) -> void:
	var node_count := 0
	var stack: Array = [{"effects": effects, "depth": 1, "path": ["effects"]}]
	while not stack.is_empty():
		var frame: Dictionary = stack.pop_back()
		var list: Array = frame.get("effects", [])
		var depth := int(frame.get("depth", 1))
		var base_path: Array = frame.get("path", [])
		if depth > MAX_EFFECT_NESTING_DEPTH:
			issues.append(_issue("effect_depth", base_path, {"limit": MAX_EFFECT_NESTING_DEPTH, "actual": depth}))
			continue
		for index in range(list.size()):
			var effect = list[index]
			var path := base_path.duplicate()
			path.append(index)
			if not (effect is Dictionary):
				issues.append(_issue("effect_type", path, {}))
				continue
			node_count += 1
			if node_count > MAX_EFFECT_NODES_PER_SKILL:
				issues.append(_issue("skill_node_limit", base_path, {"limit": MAX_EFFECT_NODES_PER_SKILL, "actual": node_count}))
				return
			var effect_dict: Dictionary = effect
			if str(effect_dict.get("effect", "")) == SkillRegistry.EFFECT_REPEAT:
				var repeat_count := int(effect_dict.get("repeat_count", 2))
				if effect_dict.has("repeat_count") and repeat_count > MAX_REPEAT_COUNT:
					issues.append(_issue("repeat_limit", path, {"limit": MAX_REPEAT_COUNT, "actual": repeat_count}))
			for expression_key in ["condition", "value_expr", "repeat_expr"]:
				var expression = effect_dict.get(expression_key, null)
				if expression is Dictionary:
					var expression_depth := _dictionary_depth(expression, MAX_EXPRESSION_NESTING_DEPTH + 1)
					if expression_depth > MAX_EXPRESSION_NESTING_DEPTH:
						var expression_path := path.duplicate()
						expression_path.append(expression_key)
						issues.append(_issue("expression_depth", expression_path, {"limit": MAX_EXPRESSION_NESTING_DEPTH, "actual": expression_depth}))
			for branch in ["then_effects", "else_effects"]:
				var nested = effect_dict.get(branch, [])
				if not (nested is Array):
					var bad_path := path.duplicate()
					bad_path.append(branch)
					issues.append(_issue("effects_type", bad_path, {}))
				elif not nested.is_empty():
					var nested_path := path.duplicate()
					nested_path.append(branch)
					stack.append({"effects": nested, "depth": depth + 1, "path": nested_path})


static func _dictionary_depth(root: Dictionary, stop_after: int) -> int:
	var maximum := 1
	var stack: Array = [{"value": root, "depth": 1}]
	while not stack.is_empty():
		var frame: Dictionary = stack.pop_back()
		var depth := int(frame.get("depth", 1))
		maximum = maxi(maximum, depth)
		if maximum > stop_after:
			return maximum
		var value = frame.get("value")
		if value is Dictionary:
			for child in value.values():
				if child is Dictionary or child is Array:
					stack.append({"value": child, "depth": depth + 1})
		elif value is Array:
			for child in value:
				if child is Dictionary or child is Array:
					stack.append({"value": child, "depth": depth + 1})
	return maximum


static func _issue(code: String, path: Array, details: Dictionary) -> Dictionary:
	return {"code": code, "path": path.duplicate(), "details": details.duplicate(true)}
