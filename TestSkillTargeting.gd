extends Node

const GameStateScript = preload("res://GameState.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

var failures: Array = []


func _ready() -> void:
	_test_target_normalization_helpers()
	_test_skill_text_formatter_helpers()
	_test_skill_tooltip_shows_skill_probability()
	_test_status_descriptions()
	_test_effect_description_details()
	_test_thorns_added_on_damaged_is_delayed()
	_test_old_all_enemy_mapping()
	_test_target_side_filter()
	_test_activate_target_single_requires_manual_target()
	_test_target_single_all_side_uses_selected_player()
	_test_directed_adjacent_skips_the_caster()
	_test_player_targets_and_unit_areas_are_disjoint()
	_test_on_attack_target_matrix()
	_test_on_damaged_target_matrix()
	_test_death_self_sides_and_filter_targets()
	_test_death_single_target_does_not_fallback()
	_test_effect_conditions()
	_test_new_effect_pack()
	_test_party_enemy_slot_swap()
	_test_party_skill_targets_another_teammates_field()
	_test_party_friendly_attack()
	_test_party_spells_on_teammates()
	_test_party_parasite_on_teammate()
	_test_party_area_spells()
	if failures.is_empty():
		print("TEST_SKILL_TARGETING_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _fail(message: String) -> void:
	failures.append(message)


func _test_party_enemy_slot_swap() -> void:
	var party := preload("res://TeamBattleState.gd").new()
	party.start_match({1: [], 2: [], 3: []}, [1, 2, 3], 813)
	var skill := {"trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
		"effects": [{"effect": SkillRegistry.EFFECT_SWAP_ENEMY_SLOTS, "target": SkillEngine.TARGET_SELF}]}
	party.fields[1].slots[0] = _card("Caster", 6, 1, [skill])
	party.fields[1].action_points = 20
	var other_enemy := _card("Other rival")
	var first := _card("First")
	var last := _card("Last")
	party.fields[2].slots[0] = other_enemy
	party.fields[3].slots[0] = first
	party.fields[3].slots[4] = last
	if not party.apply_action(1, party.state_revision, "skill", 0, 3, -1, 0):
		_fail("party swap must queue through an ordinary unit skill")
		return
	var revision: int = party.state_revision
	var own: Dictionary = party.player_view(1)
	var rival: Dictionary = party.player_view(3)
	if own.choice.get("target_seat") != 3 or not rival.choice.is_empty() or party.apply_card_choice(3, revision, [4]):
		_fail("only the caster can select the swap against the chosen opposing seat")
	if party.apply_card_choice(1, revision, [0]) or not party.apply_card_choice(1, revision, [4]):
		_fail("same-slot moves must fail and the valid swap must resolve")
	if party.fields[3].slots[4] != first or party.fields[3].slots[0] != last or party.fields[2].slots[0] != other_enemy \
			or party.apply_card_choice(1, revision, [4]):
		_fail("party swap must exchange exactly two positions once and leave the other rival alone")


func _test_party_skill_targets_another_teammates_field() -> void:
	var party := preload("res://TeamBattleState.gd").new()
	party.start_match({1: [], 2: [], 3: [], 4: []}, [1, 2, 3, 4], 813)
	party.turn_number = 2
	var skill := {"trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SIDES,
			"target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 2},
		{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_ALL,
			"target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1},
	]}
	var retaliation := {"trigger": SkillEngine.TRIGGER_ON_DAMAGED, "effects": [
		{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "value": 1},
	]}
	var caster := _card("Caster", 5, 1, [skill])
	var teammate := _card("Selected teammate unit", 5, 1, [retaliation])
	var other_teammate_unit := _card("Adjacent teammate unit", 2)
	var enemy := _card("Opposing unit")
	party.fields[1].slots[0] = caster
	party.fields[2].slots[0] = teammate
	party.fields[2].slots[1] = other_teammate_unit
	party.fields[3].slots[0] = enemy
	party.fields[1].action_points = 8
	if not party.apply_action(1, party.state_revision, "skill", 0, 2, 0, 0):
		_fail("Party skills must accept a valid unit on another teammate's field")
	elif caster.hp != 4 or teammate.hp != 3 or party.fields[2].slots[1] != null or enemy.hp != 4:
		_fail("Party skills must resolve adjacent targets, reactions and enemy-wide effects on their respective fields")


func _test_party_friendly_attack() -> void:
	var party := preload("res://TeamBattleState.gd").new()
	party.start_match({1: [], 2: [], 3: [], 4: []}, [3, 4, 1, 2], 813)
	party.turn_number = 2
	var hit_again := {"trigger": SkillEngine.TRIGGER_ON_ATTACK, "effects": [
		{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "value": 1},
	]}
	var retaliation := {"trigger": SkillEngine.TRIGGER_ON_ATTACKED, "effects": [
		{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "value": 1},
	]}
	var attacker := _card("Blue attacker", 5, 2, [hit_again])
	var teammate := _card("Blue teammate", 5, 1, [retaliation])
	var enemy := _card("Red unit in the same slot")
	party.fields[1].slots[0] = attacker
	party.fields[2].slots[0] = teammate
	party.fields[3].slots[0] = enemy
	party.active_seat = 1
	party.fields[1].action_points = 8
	if not party.apply_action(1, party.state_revision, "attack", 0, 2, 0, -1):
		_fail("Blue can attack a unit on another Blue player's field")
	elif not attacker.has_acted or attacker.hp != 4 or teammate.hp != 2 or enemy.hp != 5:
		_fail("The attack and both directed triggers must resolve on the selected teammates")


func _test_party_spells_on_teammates() -> void:
	var party := preload("res://TeamBattleState.gd").new()
	party.start_match({1: [], 2: [], 3: []}, [1, 2, 3], 813)
	party.active_seat = 2
	var caster_field: BattleField = party.fields[2]
	var ally_field: BattleField = party.fields[3]
	var ally := _card("Wounded teammate unit")
	var enemy := _card("Wounded enemy unit")
	ally.hp = 1
	enemy.hp = 1
	ally_field.slots[0] = ally
	party.fields[1].slots[0] = enemy
	ally_field.player_hp -= 5
	caster_field.player_hp -= 5
	var original_hp := caster_field.player_hp
	var spell := _party_spell(SkillEngine.EFFECT_HEAL, SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDE_ALLY, 2)
	party.hands[2].append(spell)
	if not party.apply_action(2, party.state_revision, "cast", 0, 3, 0, -1) or ally.hp != 3 or enemy.hp != 1:
		_fail("A friendly unit spell dropped on a teammate must affect that teammate's unit, even in round one")
	var player_heal := _party_spell(SkillEngine.EFFECT_HEAL, SkillEngine.TARGET_PLAYER, SkillEngine.TARGET_SIDE_ALLY, 2)
	party.hands[2].append(player_heal)
	if not party.apply_action(2, party.state_revision, "cast", 0, 3, 4, -1) \
			or ally_field.player_hp != ally_field.max_player_hp - 3 or caster_field.player_hp != original_hp:
		_fail("An allied player spell dropped on a teammate's empty slot must affect that player")


func _test_party_parasite_on_teammate() -> void:
	var party := preload("res://TeamBattleState.gd").new()
	party.start_match({1: [], 2: [], 3: []}, [1, 2, 3], 813)
	party.active_seat = 2
	var ally := _card("Teammate unit")
	var enemy := _card("Enemy in the same slot")
	var parasite := _card("Parasite")
	parasite.card_type = "parasite"
	party.fields[3].slots[0] = ally
	party.fields[1].slots[0] = enemy
	party.hands[2].append(parasite)
	if not party.apply_action(2, party.state_revision, "parasite", 0, 3, 0, -1) \
			or not ally.parasite_cards.has(parasite) or not enemy.parasite_cards.is_empty() or not party.hands[2].is_empty():
		_fail("A party parasite must attach to the selected teammate, not the enemy in the same slot")


func _test_party_area_spells() -> void:
	for side in [SkillEngine.TARGET_SIDE_ALL, SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALLY]:
		var party := preload("res://TeamBattleState.gd").new()
		party.start_match({1: [], 2: [], 3: [], 4: [], 5: []}, [1, 2, 3, 4, 5], 813)
		party.turn_number = 2
		var spell := _party_spell(SkillEngine.EFFECT_DAMAGE, SkillEngine.TARGET_ALL, side, 2)
		party.hands[1].append(spell)
		for seat in range(1, 6):
			party.fields[seat].slots[0] = _card("Unit %d" % seat)
		var casualty := _card("Off-screen casualty", 2)
		party.fields[4].slots[1] = casualty
		var compensation := _card("Death compensation")
		party.shared_deck.append(compensation)
		if not party.apply_action(1, party.state_revision, "cast", 0, 3, -1, -1):
			_fail("The %s area spell must resolve" % side)
			continue
		for seat in range(1, 6):
			var affected: bool = side == SkillEngine.TARGET_SIDE_ALL or (side == SkillEngine.TARGET_SIDE_ALLY) == (seat <= 2)
			if party.fields[seat].slots[0].hp != (3 if affected else 5):
				_fail("The %s area spell hit the wrong units at seat %d" % [side, seat])
		var kills_enemy: bool = side != SkillEngine.TARGET_SIDE_ALLY
		if (party.fields[4].slots[1] == null) != kills_enemy or party.shared_discard.has(casualty) != kills_enemy:
			_fail("The %s area spell must clean up casualties on off-screen fields" % side)
		if party.hands[4].has(compensation) != kills_enemy or not party.hands[3].is_empty():
			_fail("The %s area spell must give death compensation to the affected seat" % side)


func _party_spell(effect: String, target: String, side: String, value: int) -> CardData:
	var spell := _card("Party spell", 0, 0, [{"trigger": SkillEngine.TRIGGER_ON_CAST,
		"effects": [{"effect": effect, "target": target, "target_side": side, "value": value}]}])
	spell.card_type = "spell"
	return spell


func _test_target_normalization_helpers() -> void:
	var enemy_aoe := _TargetResolver.normalize_effect_target({"target": "all_enemies", "effect": SkillEngine.EFFECT_DAMAGE, "value": 1})
	if enemy_aoe.get("target", "") != SkillEngine.TARGET_ALL or enemy_aoe.get("target_side", "") != SkillEngine.TARGET_SIDE_ENEMY:
		_fail("target resolver did not normalize old all_enemies target")
	if not _TargetResolver.is_directed_target(SkillEngine.TARGET_SINGLE):
		_fail("target resolver did not identify target_single as directed")
	if _TargetResolver.default_target_side("all_allies") != SkillEngine.TARGET_SIDE_ALLY:
		_fail("target resolver returned wrong default side for all_allies")


func _test_skill_text_formatter_helpers() -> void:
	var old_lang := Locale.language
	Locale.language = "zh"
	var sentence := _TextFormatter.format_effect_sentence({"target": "all_enemies", "effect": SkillEngine.EFFECT_DAMAGE, "value_min": 1, "value_max": 3, "random_count": 2})
	if not sentence.contains("敌方") or not sentence.contains("1~3"):
		_fail("skill text formatter did not describe normalized enemy random damage")
	Locale.language = old_lang


func _test_skill_tooltip_shows_skill_probability() -> void:
	var old_lang := Locale.language
	Locale.language = "zh"
	var tooltip := _TextFormatter.format_skill_tooltip({"skill_name": "自我修复", "trigger": SkillEngine.TRIGGER_ON_DAMAGED, "probability": 33, "effects": [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_HEAL, "value": 3}
	]})
	if not tooltip.contains("33%") or not tooltip.contains("为自身回复 3 点生命"):
		_fail("skill tooltip did not show skill-level trigger probability: " + tooltip)
	Locale.language = old_lang


func _test_status_descriptions() -> void:
	var old_lang := Locale.language
	Locale.language = "zh"
	var reduction := CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 50, SkillEngine.BUFF_DAMAGE_REDUCTION, 2)
	var text := _TextFormatter.format_effect_sentence(reduction)
	if text != "减伤 50%，持续 2 回合":
		_fail("self damage reduction should read directly: " + text)
	reduction.erase("value")
	reduction.merge({"target": "all_allies", "value_min": 25, "value_max": 50, "probability": 60}, true)
	text = _TextFormatter.format_effect_sentence(reduction)
	if not text.begins_with("所有友方单位减伤 25~50%，持续 2 回合") or not text.contains("60%"):
		_fail("status text must keep the faction, range, duration and probability: " + text)
	var poison := CardDatabase._fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_ADD_BUFF, 2, SkillEngine.BUFF_POISON, 3, 0, 100, SkillEngine.TARGET_SIDE_ENEMY)
	text = _TextFormatter.format_effect_sentence(poison)
	if not text.begins_with("目标中毒") or not text.contains("回合结束时失去 2 点生命") or not text.contains("持续 3 回合"):
		_fail("poison text must describe the recurring HP loss: " + text)
	var stun := CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 1, SkillEngine.BUFF_STUN, 9)
	if _TextFormatter.format_effect_sentence(stun) != "陷入眩晕，持续 9 回合":
		_fail("stun text must show the configured duration")
	Locale.language = "en"
	reduction.duration = 1
	text = _TextFormatter.format_effect_sentence(reduction)
	if not text.begins_with("Give all allied units 25~50% damage reduction for 1 turn") or text.contains("1 turns"):
		_fail("English status text must use the singular turn: " + text)
	Locale.language = old_lang


func _test_effect_description_details() -> void:
	var old_lang := Locale.language
	Locale.language = "zh"
	var mana_loss := CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MANA, -2)
	if _TextFormatter.format_effect_sentence(mana_loss) != "失去 2 点圣水":
		_fail("negative elixir must be described as a loss")
	var search := CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_VIEW_DECK, 2)
	if _TextFormatter.format_effect_sentence(search) != "查看牌库顶 4 张，最多选 2 张加入手牌":
		_fail("deck search must explain the default two-to-one inspection")
	search.random_count = 3
	if _TextFormatter.format_effect_sentence(search) != "查看牌库顶 3 张，最多选 2 张加入手牌":
		_fail("explicit deck search must distinguish inspection from selection")
	var random_damage := CardDatabase._fx(SkillEngine.TARGET_ALL, SkillEngine.EFFECT_DAMAGE, 2, "", 0, 2, 100, SkillEngine.TARGET_SIDE_ENEMY)
	var text := _TextFormatter.format_effect_sentence(random_damage)
	if text != "对敌方单位造成 2 点伤害，随机选取最多 2 个目标":
		_fail("a random target limit must not promise damage to every unit: " + text)
	for lang in ["zh", "en"]:
		Locale.language = lang
		for status: String in SkillRegistry.BUFF_IDS:
			var effect := CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 2, status, 1)
			var sentence := _TextFormatter.format_effect_sentence(effect)
			if sentence.is_empty() or sentence.contains("{") or SkillHelp.description("buff", status).is_empty():
				_fail("missing %s status description for %s" % [lang, status])
	Locale.language = old_lang


func _new_game():
	var game = GameStateScript.new()
	game.init_game(Callable())
	game.shared_deck.clear()
	game.shared_discard.clear()
	game.player_hand.clear()
	game.player2_hand.clear()
	for i in range(5):
		game.player_field.slots[i] = null
		game.player2_field.slots[i] = null
	game.current_player = 1
	game.turn_number = 2
	return game


func _card(name: String, hp: int = 5, atk: int = 0, skills: Array = []) -> CardData:
	return CardData.new(name, 1, hp, atk, skills)


func _test_thorns_added_on_damaged_is_delayed() -> void:
	var game = _new_game()
	var attacker := _card("Attacker", 10, 2)
	var victim := _card("Thorns Later", 10, 0, [
		CardDatabase._fx_skill("Grow Thorns", SkillEngine.TRIGGER_ON_DAMAGED, [
			CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 3, SkillEngine.BUFF_THORNS, 2),
		]),
	])
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = victim
	game.execute_attack(0, 0)
	if attacker.hp != 10:
		_fail("on_damaged thorns reflected the current attack")
	if victim.get_thorns_damage() != 3:
		_fail("on_damaged thorns buff was not applied for later attacks")


func _test_old_all_enemy_mapping() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var enemy_a := _card("Enemy A")
	var enemy_b := _card("Enemy B")
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy_a
	game.player2_field.slots[1] = enemy_b
	caster.skills = [{"skill_name": "Old AoE", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": "all_enemies", "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	if enemy_a.hp != 4 or enemy_b.hp != 4:
		_fail("old all_enemies target did not damage all enemies")
	if caster.hp != 5:
		_fail("old all_enemies target damaged the caster")


func _test_target_side_filter() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var ally_male := _card("Ally Male")
	ally_male.gender = "male"
	var enemy_male := _card("Enemy Male")
	enemy_male.gender = "male"
	var enemy_female := _card("Enemy Female")
	enemy_female.gender = "female"
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally_male
	game.player2_field.slots[0] = enemy_male
	game.player2_field.slots[1] = enemy_female
	caster.skills = [{"skill_name": "Enemy Male Only", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_MALE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	if enemy_male.hp != 4:
		_fail("enemy male target_side filter missed enemy male")
	if ally_male.hp != 5 or enemy_female.hp != 5:
		_fail("enemy male target_side filter hit a wrong target")


func _test_activate_target_single_requires_manual_target() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var enemy := _card("Enemy")
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy
	caster.skills = [{"skill_name": "Manual Bolt", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	if enemy.hp != 5:
		_fail("manual target_single fell back without a selected target")
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if enemy.hp != 3:
		_fail("manual target_single did not hit the selected target")


func _test_target_single_all_side_uses_selected_player() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var ally := _card("Ally")
	ally.hp = 2
	var enemy := _card("Enemy")
	enemy.hp = 2
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally
	game.player2_field.slots[1] = enemy
	caster.skills = [{"skill_name": "Open Heal", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALL, "effect": SkillEngine.EFFECT_HEAL, "value": 3}
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 1, 1))
	if ally.hp != 5:
		_fail("target_single all-side did not resolve the selected allied slot")
	if enemy.hp != 2:
		_fail("target_single all-side ignored the selected battlefield side")


func _test_directed_adjacent_skips_the_caster() -> void:
	var game = _new_game()
	var caster := _card("Caster")
	var center := _card("Selected")
	var neighbor := _card("Adjacent")
	var other_field := _card("Same slot on other field")
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = center
	game.player_field.slots[2] = neighbor
	game.player2_field.slots[1] = other_field
	caster.skills = [{"skill_name": "Legacy enemy splash", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SIDES, "target_side": SkillEngine.TARGET_SIDE_ENEMY,
			"effect": SkillEngine.EFFECT_DAMAGE, "value": 1}
	]}]
	game.player_field.action_points = 8
	if game.trigger_activate_skills(0, 0, 0, 1) or caster.has_acted:
		_fail("A caster must not be able to select itself")
	if not game.trigger_activate_skills(0, 1, 0, 1) or center.hp != 4 or neighbor.hp != 4 or caster.hp != 5 or other_field.hp != 5:
		_fail("Directed splash must follow the selected field and exclude the caster")


func _test_player_targets_and_unit_areas_are_disjoint() -> void:
	var game = _new_game()
	var caster := _card("Hero Target Caster")
	var ally_unit := _card("Ally Unit")
	var enemy_unit := _card("Enemy Unit")
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally_unit
	game.player2_field.slots[0] = enemy_unit
	game.player_field.player_hp = 20
	game.player2_field.player_hp = 20
	caster.skills = [{"skill_name": "Hero Matrix", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_PLAYER, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 4},
		{"target": SkillEngine.TARGET_PLAYER, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 3},
		{"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1},
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, -1))
	if game.player2_field.player_hp != 16:
		_fail("enemy player target did not damage the enemy player body")
	if game.player_field.player_hp != 23:
		_fail("ally player target did not heal the allied player body")
	if enemy_unit.hp != 4 or ally_unit.hp != 5:
		_fail("enemy/ally area semantics did not remain unit-only")
	var all_units := _TargetResolver.resolve_targets(SkillEngine.TARGET_ALL, caster, game.make_skill_context(0, -1), SkillEngine.TARGET_SIDE_ALL)
	if game.player_field in all_units or game.player2_field in all_units:
		_fail("TARGET_ALL unexpectedly includes a player body")
	if not SpellRules.targets_enemy({"effects": [{"target": SkillEngine.TARGET_PLAYER, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}]}):
		_fail("enemy player spell target was not recognized by first-turn protection")
	var invalid := SkillErrorChecker.collect_semantic_issues([
		{"target": SkillEngine.TARGET_PLAYER, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_SHIELD, "value": 1},
	], SkillEngine.TRIGGER_ON_ACTIVATE)
	if invalid.is_empty():
		_fail("unit-only effects must reject player targets")
	var sentence := _TextFormatter.format_effect_sentence({"target": SkillEngine.TARGET_PLAYER, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 4})
	if not sentence.contains("敌方玩家"):
		_fail("player target text must read as enemy player")


func _test_on_attack_target_matrix() -> void:
	var game = _new_game()
	var attacker := _card("Attacker", 8, 0, [
		{"skill_name": "Attack Matrix", "trigger": SkillEngine.TRIGGER_ON_ATTACK, "effects": [
			{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1},
			{"target": SkillEngine.TARGET_SELF_SIDES, "effect": SkillEngine.EFFECT_HEAL, "value": 1},
		]}
	])
	var ally := _card("Ally", 5)
	ally.hp = 3
	var defender := _card("Defender", 5)
	var defender_side := _card("Defender Side", 5)
	game.player_field.slots[1] = ally
	game.player_field.slots[2] = attacker
	game.player2_field.slots[3] = defender
	game.player2_field.slots[4] = defender_side
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ATTACK, attacker, game.make_skill_context(2, 3))
	if defender.hp != 4:
		_fail("on_attack target_single did not resolve to defender")
	if defender_side.hp != 5:
		_fail("on_attack target_single incorrectly hit adjacent defender")
	if attacker.hp != 8 or ally.hp != 4:
		_fail("on_attack self_sides did not resolve around attacker and adjacent ally")


func _test_on_damaged_target_matrix() -> void:
	var game = _new_game()
	var attacker := _card("Damage Source", 5)
	var attacker_side := _card("Source Side", 5)
	var victim := _card("Victim", 5, 0, [
		{"skill_name": "Damaged Matrix", "trigger": SkillEngine.TRIGGER_ON_DAMAGED, "effects": [
			{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1},
			{"target": SkillEngine.TARGET_SELF_SIDES, "effect": SkillEngine.EFFECT_HEAL, "value": 1},
		]}
	])
	var victim_side := _card("Victim Side", 5)
	victim_side.hp = 3
	game.player_field.slots[1] = attacker
	game.player_field.slots[2] = attacker_side
	game.player2_field.slots[1] = victim
	game.player2_field.slots[0] = victim_side
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DAMAGED, victim, game.make_skill_context_for_player(2, 1, 1))
	if attacker.hp != 4:
		_fail("on_damaged target_single did not resolve to damage source")
	if attacker_side.hp != 5:
		_fail("on_damaged target_single incorrectly hit source adjacent")
	if victim.hp != 5 or victim_side.hp != 4:
		_fail("on_damaged self_sides did not resolve around damaged card")


func _test_death_self_sides_and_filter_targets() -> void:
	var game = _new_game()
	var dying := _card("Dying", 0, 0, [
		{"skill_name": "Death Matrix", "trigger": SkillEngine.TRIGGER_ON_DEATH, "effects": [
			{"target": SkillEngine.TARGET_SELF_SIDES, "effect": SkillEngine.EFFECT_HEAL, "value": 2},
			{"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1},
		]}
	])
	var ally := _card("Death Ally", 5)
	ally.hp = 2
	var enemy := _card("Death Enemy", 5)
	game.player_field.slots[1] = ally
	game.player_field.slots[2] = dying
	game.player2_field.slots[0] = enemy
	game.cleanup_deaths()
	if ally.hp != 4:
		_fail("on_death self_sides did not affect adjacent ally before removal")
	if enemy.hp != 4:
		_fail("on_death all+enemy did not affect enemy field")
	if game.player_field.slots[2] != null:
		_fail("dead source was not removed after on_death trigger")


func _test_death_single_target_does_not_fallback() -> void:
	var game = _new_game()
	var dying := _card("Dying", 0, 0, [
		{"skill_name": "No Free Target", "trigger": SkillEngine.TRIGGER_ON_DEATH, "effects": [
			{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}
		]}
	])
	var enemy := _card("Enemy")
	game.player_field.slots[0] = dying
	game.player2_field.slots[0] = enemy
	game.cleanup_deaths()
	if enemy.hp != 5:
		_fail("on_death target_single fell back to the first enemy")


func _test_effect_conditions() -> void:
	var game = _new_game()
	var caster := _card("Conditional Caster", 10, 0)
	caster.hp = 4
	var enemy := _card("Conditional Enemy", 10, 0)
	var ally := _card("Conditional Ally", 5, 0)
	game.player_field.slots[0] = caster
	game.player_field.slots[1] = ally
	game.player2_field.slots[0] = enemy

	caster.skills = [{"skill_name": "Low HP Shield", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_SHIELD, "value": 2,
			"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT, "condition_op": SkillEngine.CONDITION_OP_LTE, "condition_value": 50},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2,
			"condition_type": SkillEngine.CONDITION_TARGET_HP_PCT, "condition_op": SkillEngine.CONDITION_OP_LTE, "condition_value": 30},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1,
			"condition_type": SkillEngine.CONDITION_FIELD_ALLY, "condition_op": SkillEngine.CONDITION_OP_GTE, "condition_value": 2},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1,
			"condition_type": SkillEngine.CONDITION_TARGET_HAS_BUFF, "condition_buff_id": SkillEngine.BUFF_MISFORTUNE},
	]}]

	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if caster.temp_hp != 2:
		_fail("source HP condition did not apply shield when caster was low")
	if enemy.hp != 9:
		_fail("target HP/buff conditions should fail while ally-count condition deals 1 damage")

	enemy.hp = 3
	enemy.apply_buff(SkillEngine.BUFF_MISFORTUNE, 10, 1)
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if enemy.hp != 0:
		_fail("target HP, ally count, and target buff conditions did not all apply")


func _test_new_effect_pack() -> void:
	var game = _new_game()
	var caster := _card("New Effect Caster", 10, 1)
	caster.hp = 4
	var enemy := _card("New Effect Enemy", 10, 0)
	enemy.temp_hp = 2
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = enemy
	game.player_field.current_mana = 8

	caster.skills = [{"skill_name": "New Effects", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_LIFESTEAL_DAMAGE, "value": 9},
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_EXECUTE, "value": 3},
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_MANA, "value": 5},
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_ATTACK, "value": 2},
		{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_MAX_HP, "value": 3},
	]}]

	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 0))
	if enemy.hp != 0:
		_fail("execute should defeat enemy after lifesteal reduces HP to threshold")
	if caster.hp != 13:
		_fail("lifesteal plus max HP gain should heal caster to new max HP")
	if game.player_field.current_mana != 10:
		_fail("gain mana should increase current player's mana up to max")
	if caster.atk != 1 or caster.base_atk != 1 or caster.field_atk_bonus != 2 or caster.effective_atk() != 3:
		_fail("gain attack should add a field-only permanent bonus without changing base attack")
	if caster.max_hp != 13 or caster.base_max_hp != 10:
		_fail("gain max HP should increase battlefield max HP while preserving the base for discard reset")
	var high_hp_enemy := _card("High HP Enemy", 10, 0)
	game.player2_field.slots[2] = high_hp_enemy
	caster.skills = [{"skill_name": "Execute Check", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_EXECUTE, "value": 3},
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 2))
	if high_hp_enemy.hp != 10:
		_fail("execute should not defeat targets above the HP threshold")

	var status_target := _card("Status Target", 10, 0)
	status_target.apply_buff(SkillEngine.BUFF_SILENCE, 1, 2)
	status_target.apply_buff(SkillEngine.BUFF_MISFORTUNE, 10, 2)
	status_target.apply_buff(SkillEngine.BUFF_ATK_BOOST, 2, 2)
	status_target.apply_buff(SkillEngine.BUFF_TAUNT, 1, 2)
	game.player2_field.slots[1] = status_target
	caster.skills = [{"skill_name": "Status Remove", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_CLEANSE, "value": 1},
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 1))
	if status_target.is_silenced() or status_target.get_misfortune() != 0:
		_fail("cleanse should remove negative statuses")
	if not status_target.has_taunt() or status_target.effective_atk() != 2:
		_fail("cleanse should not remove positive statuses")
	caster.skills = [{"skill_name": "Status Remove", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [
		{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DISPEL, "value": 1},
	]}]
	SkillEngine.trigger_single_skill(caster, 0, game.make_skill_context(0, 1))
	if status_target.has_taunt() or status_target.effective_atk() != 0:
		_fail("dispel should remove positive statuses")
