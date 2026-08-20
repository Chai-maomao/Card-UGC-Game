class_name CardUsabilityAnalyzer
extends RefCounted


static func analyze(draft: Dictionary) -> Dictionary:
	var issues: Array = []
	var cost := int(draft.get("cost", 0))
	var card_type := str(draft.get("card_type", "minion"))
	if str(draft.get("name", "")).strip_edges().is_empty():
		issues.append({"severity": "warning", "key": "usability.missing_name"})
	if cost > 10:
		issues.append({"severity": "error", "key": "usability.cost_over_cap", "args": [cost]})
	if cost < 0:
		issues.append({"severity": "error", "key": "usability.negative_cost"})
	var skills: Array = []
	for key in ["skill1", "skill2", "skill3"]:
		var skill = draft.get(key, {})
		if skill is Dictionary and not skill.is_empty():
			skills.append(skill)
	if card_type == "spell":
		if skills.is_empty() or (skills[0].get("effects", []) as Array).is_empty():
			issues.append({"severity": "error", "key": "usability.spell_no_effect"})
	elif card_type == "parasite":
		if skills.is_empty():
			issues.append({"severity": "warning", "key": "usability.parasite_no_effect"})
	elif skills.is_empty():
		issues.append({"severity": "info", "key": "usability.vanilla_card"})
	if card_type != "spell" and int(draft.get("hp", 1)) <= 0:
		issues.append({"severity": "error", "key": "usability.no_health"})
	var manual_actions := 0
	for skill in skills:
		if str(skill.get("trigger", "")) in [SkillEngine.TRIGGER_ON_ACTIVATE, SkillEngine.TRIGGER_ON_SUMMON]:
			manual_actions += 1
	if manual_actions >= 2:
		issues.append({"severity": "warning", "key": "usability.action_competition", "args": [manual_actions]})
	return {
		"playable": not issues.any(func(issue): return issue.get("severity", "") == "error"),
		"issues": issues,
	}
