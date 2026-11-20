class_name UgcBenchmarkPool
extends RefCounted

# Frozen diagnostic content, never installed into the player's collection.
# Changes to these definitions require a new pool ID/version for comparisons.
const ID := "ugc-v1"
const VERSION := 1
const COPIES := 2
const DEFINITIONS := [
	{"key": "relay", "name": "接力工程师", "cost": 2, "max_hp": 5, "atk": 1, "tags": ["distinct_actives", "payment_before_income"], "skills": [
		{"skill_name": "补给", "trigger": "on_activate", "max_uses": 2, "effects": [{"effect": "gain_mana", "target": "self", "value": 2}]},
		{"skill_name": "点射", "trigger": "on_activate", "max_uses": 3, "effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 2}]},
	]},
	{"key": "reactor", "name": "反馈守卫", "cost": 3, "max_hp": 6, "atk": 1, "tags": ["limited_reaction", "receiver_resources", "initiator_target"], "skills": [
		{"skill_name": "反馈", "trigger": "on_damaged", "max_uses": 2, "effects": [{"effect": "gain_mana", "target": "self", "value": 1}, {"effect": "draw_cards", "target": "self", "value": 1}, {"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 1}]},
	]},
	{"key": "grower", "name": "蓄势学徒", "cost": 2, "max_hp": 4, "atk": 0, "tags": ["zero_attack_growth", "lifetime_limit"], "skills": [
		{"skill_name": "蓄势", "trigger": "on_attack", "max_uses": 3, "effects": [{"effect": "gain_attack", "target": "self", "value": 2}]},
	]},
	{"key": "parasite", "name": "共鸣寄生体", "cost": 1, "max_hp": 2, "atk": 1, "card_type": "parasite", "parasite_damage_mode": "linked", "tags": ["parasite_identity", "host_resources", "independent_limits"], "skills": [
		{"skill_name": "共鸣", "trigger": "on_attack", "max_uses": 2, "effects": [{"effect": "gain_attack", "target": "self", "value": 1}]},
		{"skill_name": "回响", "trigger": "on_damaged", "max_uses": 1, "effects": [{"effect": "gain_mana", "target": "self", "value": 1}, {"effect": "heal", "target": "self", "value": 1}]},
	]},
	{"key": "random", "name": "游走术士", "cost": 3, "max_hp": 5, "atk": 1, "tags": ["seeded_probability", "random_target"], "skills": [
		{"skill_name": "游走冲击", "trigger": "on_activate", "probability": 75, "max_uses": 3, "effects": [{"effect": "damage", "target": "all", "target_side": "enemy", "random_count": 1, "value": 2}]},
	]},
	{"key": "conditional", "name": "条件医师", "cost": 2, "max_hp": 4, "atk": 1, "tags": ["nested_condition", "post_payment_condition"], "skills": [
		{"skill_name": "应急处置", "trigger": "on_activate", "max_uses": 3, "effects": [{"effect": "__if_else__", "condition": {"condition_type": "mana_current", "condition_op": ">=", "condition_value": 2}, "then_effects": [{"effect": "gain_mana", "target": "self", "value": 1}], "else_effects": [{"effect": "heal", "target": "self", "value": 2}]}]},
	]},
	{"key": "timed", "name": "定时补给兵", "cost": 3, "max_hp": 5, "atk": 2, "tags": ["deployment_passive", "end_turn_income"], "skills": [
		{"skill_name": "掩护", "trigger": "on_summon", "max_uses": 1, "effects": [{"effect": "shield", "target": "self", "value": 2}]},
		{"skill_name": "整备", "trigger": "on_turn_end", "max_uses": 2, "effects": [{"effect": "gain_mana", "target": "self", "value": 1}]},
	]},
	{"key": "spell", "name": "精确冲击", "cost": 2, "max_hp": 0, "atk": 0, "card_type": "spell", "tags": ["spell_cost", "damage_and_draw"], "skills": [
		{"skill_name": "冲击", "trigger": "on_cast", "effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 3}, {"effect": "draw_cards", "target": "self", "value": 1}]},
	]},
]


static func card(key: String) -> CardData:
	for definition in DEFINITIONS:
		if definition.key == key:
			var data: Dictionary = definition.duplicate(true)
			data["card_id"] = "benchmark:" + ID + ":" + key
			return PlayerData.deserialize_card(data)
	return null


static func deck() -> Array:
	var result: Array = []
	for _copy in range(COPIES):
		for definition in DEFINITIONS:
			result.append(card(definition.key))
	return result


static func manifest() -> Dictionary:
	var content := {"id": ID, "version": VERSION, "copies_per_card": COPIES, "definitions": DEFINITIONS.duplicate(true)}
	content["sha256"] = BattleRepro.canonical_text(content).sha256_text()
	return content
