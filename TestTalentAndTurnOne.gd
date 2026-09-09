extends Node

const Game = preload("res://GameState.gd")
var failures: Array[String] = []


func _ready() -> void:
	_test_first_turn_runtime_guard()
	_test_card_lifecycle_talents()
	_test_damage_cap_and_death_charm_guard()
	_test_talent_draft_round_trip()
	if failures.is_empty():
		print("TEST_TALENT_AND_TURN_ONE_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_TALENT_AND_TURN_ONE_FAILED: " + failure)
		get_tree().quit(1)


func _test_first_turn_runtime_guard() -> void:
	var game := Game.new()
	game.quiet = true
	game.init_game(Callable(), 1)
	var source := CardData.new("首回合测试", 1, 4, 1, [{
		"skill_name": "处决", "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100,
		"effects": [{"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_EXECUTE, "value": 99}],
	}])
	var enemy := CardData.new("目标", 1, 4, 1)
	game.player_field.slots[0] = source
	game.player2_field.slots[0] = enemy
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_SUMMON, source, game.make_skill_context_for_player(1, 0))
	_assert(enemy.hp == 4, "turn-one execute must be blocked inside the engine")
	game.turn_number = 2
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_SUMMON, source, game.make_skill_context_for_player(1, 0))
	_assert(enemy.hp == 0, "the same effect must resolve after turn one")


func _test_card_lifecycle_talents() -> void:
	var game := Game.new()
	game.quiet = true
	game.init_game(Callable(), 1)
	game.player_hand.clear()
	var card := CardData.new("成长牌", 1, 3, 1, [
		{"skill_name": "成长", "skill_type": SkillEngine.SKILL_TYPE_TALENT, "trigger": SkillEngine.TRIGGER_ON_ADDED, "probability": 100, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_MATCH_MAX_HP, "value": 1}]},
		{"skill_name": "回收", "skill_type": SkillEngine.SKILL_TYPE_TALENT, "trigger": SkillEngine.TRIGGER_ON_DISCARDED, "probability": 100, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_MANA, "value": 1}]},
	])
	game.resolve_hand_entry_for_player(card, "generated", {}, 1)
	_assert(card.max_hp == 4 and card.base_max_hp == 4 and card.hp == 4, "On Added match growth must happen before entering hand")
	game.player_field.current_mana = 0
	game.discard_card(card)
	_assert(game.player_field.current_mana == 2, "discard talent and the ordinary discard refund must both resolve")
	_assert(card.max_hp == 4 and card.base_max_hp == 4, "match growth must survive discard cleanup")
	game.player_hand.clear()
	for index in SkillEngine.MAX_HAND_SIZE:
		game.player_hand.append(CardData.new("占位%d" % index, 1, 1, 0))
	var overflow := CardData.new("溢出成长牌", 1, 2, 0, [{
		"skill_name": "入手成长", "skill_type": SkillEngine.SKILL_TYPE_TALENT, "trigger": SkillEngine.TRIGGER_ON_ADDED, "probability": 100,
		"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_MATCH_MAX_HP, "value": 1}],
	}])
	game.resolve_hand_entry_for_player(overflow, "generated", {}, 1)
	_assert(overflow.base_max_hp == 3, "On Added must resolve even when the full hand will overflow")
	_assert(overflow in game.shared_discard and overflow not in game.player_hand, "an overflowed added card must finish in the shared discard")


func _test_damage_cap_and_death_charm_guard() -> void:
	var capped := CardData.new("坚韧", 1, 5, 1, [{
		"skill_name": "不可逾越", "skill_type": SkillEngine.SKILL_TYPE_TALENT, "trigger": SkillEngine.TRIGGER_ALWAYS,
		"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_DAMAGE_CAP, "value": 1}],
	}])
	_assert(capped.take_damage_without_reduction(4) == 1 and capped.hp == 4, "continuous talent must cap each hit")
	var wrong_trigger := CardData.new("错误触发", 1, 5, 1, [{
		"skill_name": "错误上限", "skill_type": SkillEngine.SKILL_TYPE_TALENT, "trigger": SkillEngine.TRIGGER_ON_ADDED,
		"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_DAMAGE_CAP, "value": 1}],
	}])
	_assert(wrong_trigger.take_damage_without_reduction(4) == 4, "an event-triggered damage cap must not become an always-on modifier")
	var trigger_issues := SkillErrorChecker.collect_semantic_issues(wrong_trigger.skills[0].get("effects", []), SkillEngine.TRIGGER_ON_ADDED)
	_assert(not trigger_issues.is_empty(), "the editor must reject a continuous modifier under On Added")
	var dead := CardData.new("死亡魅惑", 1, 1, 1)
	dead.hp = 0
	var game := Game.new()
	game.quiet = true
	game.init_game(Callable(), 1)
	game.player_hand.clear()
	game.player_field.slots[0] = dead
	SkillEffectApplier._apply_charm(dead, 0, {}, game.make_skill_context_for_player(1, 0).merged({"source_card": dead, "trigger": SkillEngine.TRIGGER_ON_DEATH}, true))
	_assert(game.player_hand.is_empty() and game.player_field.slots[0] == dead, "dead source must never charm itself into hand")
	var issues := SkillErrorChecker.collect_semantic_issues([{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_CHARM}], SkillEngine.TRIGGER_ON_DEATH)
	_assert(not issues.is_empty(), "editor validation must reject On Death self-charm")


func _test_talent_draft_round_trip() -> void:
	var backup: Dictionary = PlayerData.card_draft.duplicate(true)
	PlayerData.init_card_draft()
	PlayerData.card_draft["name"] = "天赋往返"
	PlayerData.card_draft["skill1"] = {"skill_name": "普通", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_HEAL, "value": 1}]}
	PlayerData.card_draft["skill2"] = {"skill_name": "技能二", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_HEAL, "value": 1}]}
	PlayerData.card_draft["skill3"] = {"skill_name": "技能三", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_HEAL, "value": 1}]}
	PlayerData.card_draft["talent"] = {"skill_name": "天赋", "trigger": SkillEngine.TRIGGER_ALWAYS, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_DAMAGE_CAP, "value": 1}]}
	var card := PlayerData.build_card_from_draft()
	_assert(card.skills.size() == 3 and str(card.skills[2].get("skill_type", "")) == SkillEngine.SKILL_TYPE_TALENT, "talent must replace skill 1 while skills 2 and 3 remain")
	var draft := PlayerData.card_to_draft(card)
	_assert(not draft.get("talent", {}).is_empty() and draft.get("skill1", {}).is_empty(), "talent and skill 1 must remain mutually exclusive after round-trip")
	_assert(str(draft.get("skill2", {}).get("skill_name", "")) == "技能二" and str(draft.get("skill3", {}).get("skill_name", "")) == "技能三", "the remaining two skill slots must round-trip beside the talent")
	_assert(not UgcSafety.validate_draft_card(PlayerData.card_draft).is_empty(), "draft validation must reject legacy data containing both skill 1 and talent")
	PlayerData.card_draft = backup


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
