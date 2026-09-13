extends Node

const Analyzer = preload("res://CardUsabilityAnalyzer.gd")


func _ready() -> void:
	var healthy := Analyzer.analyze({
		"name": "卫兵", "card_type": "minion", "cost": 2, "hp": 3,
		"skill1": {}, "skill2": {}, "skill3": {},
	})
	_assert(bool(healthy.get("playable", false)), "ordinary minion should be playable")

	var broken_spell := Analyzer.analyze({
		"name": "空法术", "card_type": "spell", "cost": 1, "hp": 0,
		"skill1": {}, "skill2": {}, "skill3": {},
	})
	_assert(not bool(broken_spell.get("playable", true)), "spell without effects must be rejected")
	_assert(_has_issue(broken_spell, "usability.spell_no_effect"), "missing spell effect issue must be localized")

	var expensive := Analyzer.analyze({
		"name": "巨物", "card_type": "minion", "cost": 14, "hp": 8,
		"skill1": {}, "skill2": {}, "skill3": {},
	})
	_assert(not bool(expensive.get("playable", true)), "cost above cap must be an error")
	var linked_parasite := Analyzer.analyze({
		"name": "依附虫", "card_type": "parasite", "parasite_damage_mode": CardData.PARASITE_DAMAGE_LINKED,
		"cost": 1, "hp": 0, "skill1": {"trigger": SkillEngine.TRIGGER_ON_ATTACK, "effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}]},
		"skill2": {}, "skill3": {}, "talent": {},
	})
	_assert(bool(linked_parasite.get("playable", false)) and not _has_issue(linked_parasite, "usability.no_health"), "linked parasite HP must be excluded from usability checks")
	print("TEST_CARD_USABILITY_OK")
	get_tree().quit(0)


func _has_issue(result: Dictionary, key: String) -> bool:
	for issue in result.get("issues", []):
		if str(issue.get("key", "")) == key:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_CARD_USABILITY_FAILED: %s" % message)
	get_tree().quit(1)
