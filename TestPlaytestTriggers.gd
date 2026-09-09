extends Node

const Game = preload("res://GameState.gd")
var failures: Array[String] = []
var covered: Array[String] = []


func _ready() -> void:
	var original := PlayerData.battle_preparation_snapshot()
	var original_context := PlayerData.card_playtest_context.duplicate(true)
	var original_config := PlayerData.battle_config.duplicate(true)
	NetworkManager.close_connection()
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	for helper: CardData in CardDatabase.playtest_deck():
		_assert(UgcSafety.validate_serialized_card(PlayerData.serialize_card(helper)).is_empty(), "valid test fixture: " + helper.card_name)
		for skill: Dictionary in helper.skills:
			_assert(SkillErrorChecker.collect_semantic_issues(skill.effects, skill.trigger).is_empty(), "valid fixture targets: " + helper.card_name)
	for trigger: String in SkillRegistry.TRIGGER_META:
		_test_trigger(trigger)
	_test_cross_side_heal_and_damage()
	_test_parasite_passives()
	_assert(covered.size() == SkillRegistry.TRIGGER_META.size(), "new trigger requires an explicit playtest route")
	PlayerData._apply_battle_preparation(original)
	PlayerData.card_playtest_context = original_context
	PlayerData.battle_config = original_config
	if failures.is_empty():
		print("TEST_PLAYTEST_TRIGGERS_OK: %d/%d triggers, ally/enemy helpers, 3 parasite passives" % [covered.size(), SkillRegistry.TRIGGER_META.size()])
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_PLAYTEST_TRIGGERS_FAILED: " + failure)
		get_tree().quit(1)


func _new_game(trigger: String, parasite: bool = false):
	var mana_probe := trigger in [SkillEngine.TRIGGER_ON_CAST, SkillEngine.TRIGGER_ON_DEATH]
	var skill := CardDatabase._fx_skill("触发验证", trigger, [
		CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MANA if mana_probe else SkillEngine.EFFECT_GAIN_ATTACK, 1),
	])
	var card := CardData.new("待测 " + trigger, 0, 12, 1, [skill])
	if trigger == SkillEngine.TRIGGER_ON_CAST:
		card.card_type = "spell"
	if parasite:
		card.card_type = "parasite"
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(), CardDatabase.playtest_deck())
	PlayerData.card_playtest_context = {"test_card": PlayerData.serialize_card(card)}
	var game := Game.new()
	game.quiet = true
	game.init_game(Callable(), 120)
	return game


func _deploy_helpers(game) -> void:
	for index in range(2):
		var support_id: String = CardDatabase.PLAYTEST_SUPPORT_IDS[index]
		for card: CardData in game.active_hand().duplicate():
			if card.card_id == support_id:
				_assert(game.summon_card(card, index), "helper must deploy for free")
	_assert(game.active_field().slots[0] != null and game.active_field().slots[1] != null, "both instruments must deploy")


func _switch(game) -> void:
	game.end_player_turn()
	game.start_new_turn()


func _test_trigger(trigger: String) -> void:
	if trigger in SkillRegistry.TALENT_EFFECTS_BY_TRIGGER:
		_test_talent_route(trigger)
		covered.append(trigger)
		return
	var game = _new_game(trigger)
	var specimen: CardData = game.player_hand[0]
	if trigger == SkillEngine.TRIGGER_ON_CAST:
		var mana_before: int = game.player_field.current_mana
		_assert(game.cast_spell(0), "test spell must use the actual cast path")
		_assert(game.player_field.current_mana == mana_before + 1, "on_cast must resolve")
		covered.append(trigger)
		return
	_assert(game.summon_card(specimen, 2), "test minion must deploy from reserved hand")
	_deploy_helpers(game)
	match trigger:
		SkillEngine.TRIGGER_ON_SUMMON:
			game.trigger_summon_skills(2, -1, 0)
		SkillEngine.TRIGGER_ON_ACTIVATE:
			game.trigger_activate_skills(2, -1, 0)
		SkillEngine.TRIGGER_ON_DAMAGED:
			game.trigger_activate_skills(0, 2, 1, 1)
			_assert(specimen.hp == 11, "ally light-damage helper must deal one damage")
		SkillEngine.TRIGGER_ON_HEALED:
			game.trigger_activate_skills(0, 2, 1, 1)
			game.trigger_activate_skills(0, 2, 0, 1)
			_assert(specimen.hp == 12, "ally healer must restore lost HP")
		SkillEngine.TRIGGER_ON_DEATH:
			var mana_before: int = game.player_field.current_mana
			game.trigger_activate_skills(0, 2, 2, 1)
			game.cleanup_deaths()
			_assert(game.player_field.slots[2] == null, "execute helper must reach normal death cleanup")
			_assert(game.player_field.current_mana == mana_before + 1, "on_death must resolve before reset")
			covered.append(trigger)
			return
		SkillEngine.TRIGGER_ON_TURN_END:
			_switch(game)
		SkillEngine.TRIGGER_ON_TURN_START:
			_switch(game)
			_deploy_helpers(game)
			_switch(game)
		SkillEngine.TRIGGER_ON_ATTACK:
			_switch(game)
			_deploy_helpers(game)
			_switch(game)
			_assert(not game.execute_attack(2, 1).is_empty(), "attack test needs an enemy sparring partner")
		SkillEngine.TRIGGER_ON_ATTACKED:
			_switch(game)
			_deploy_helpers(game)
			_switch(game)
			_switch(game)
			_assert(not game.execute_attack(1, 2).is_empty(), "sparring partner must attack the test card")
		_:
			_assert(false, "unsupported new trigger: " + trigger)
			return
	_assert(specimen.field_atk_bonus == 1, "trigger must produce its actual effect exactly once: " + trigger)
	covered.append(trigger)


func _test_cross_side_heal_and_damage() -> void:
	for trigger in [SkillEngine.TRIGGER_ON_HEALED, SkillEngine.TRIGGER_ON_DAMAGED]:
		var game = _new_game(trigger)
		var specimen: CardData = game.player_hand[0]
		game.summon_card(specimen, 2)
		_deploy_helpers(game)
		_switch(game)
		_deploy_helpers(game)
		# Built-in helper skills intentionally target allies. For cross-side
		# semantics use a legal enemy-directed custom support skill instead.
		game.turn_number = 2
		var support: CardData = game.player2_field.slots[1]
		var skill_index := 0 if trigger == SkillEngine.TRIGGER_ON_HEALED else 1
		support.skills[skill_index]["effects"][0]["target_side"] = SkillEngine.TARGET_SIDE_ENEMY
		if trigger == SkillEngine.TRIGGER_ON_HEALED: specimen.hp = 11
		game.trigger_activate_skills(1, 2, skill_index, 1)
		_assert(specimen.field_atk_bonus == 1, "enemy support must trigger the recipient: " + trigger)


func _test_parasite_passives() -> void:
	for trigger in [SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_DAMAGED, SkillEngine.TRIGGER_ON_DEATH]:
		var game = _new_game(trigger, true)
		_deploy_helpers(game)
		var host: CardData = game.player_field.slots[1]
		_assert(game.attach_parasite(0, 1, 1), "test parasite must attach to available sparring host")
		if trigger == SkillEngine.TRIGGER_ON_DEATH:
			var mana_before: int = game.player_field.current_mana
			game.trigger_activate_skills(0, 1, 2, 1)
			game.cleanup_deaths()
			_assert(game.player_field.current_mana == mana_before + 1, "host death must trigger attached parasite")
			continue
		_switch(game)
		_deploy_helpers(game)
		_switch(game)
		if trigger == SkillEngine.TRIGGER_ON_ATTACK:
			game.execute_attack(1, 1)
		else:
			# Existing parasite rules forward the host damage event even when the
			# attached parasite absorbs the hit. Use its actual saved HP, not a mock.
			game.trigger_activate_skills(0, 1, 1, 1)
		_assert(host.field_atk_bonus == 1, "supported parasite passive must be testable: " + trigger)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_talent_route(trigger: String) -> void:
	var game = _new_game(SkillEngine.TRIGGER_ON_ACTIVATE)
	game.player_field.current_mana = 10
	game.player_hand.clear()
	var card := CardData.new("Lifecycle specimen", 5, 12, 1)
	var effect := "change_cost"
	var value := -1
	if trigger == SkillEngine.TRIGGER_ON_DISCARDED:
		effect = "gain_mana"
		value = 1
	elif trigger == SkillEngine.TRIGGER_ALWAYS:
		effect = "damage_cap"
		value = 2
	card.skills = [{"trigger": trigger, "skill_type": "talent", "effects": [{"target": "self", "effect": effect, "value": value}]}]
	if trigger == SkillEngine.TRIGGER_ON_ADDED:
		game.resolve_hand_entry_for_player(card, "generated", {}, 1)
		_assert(card.cost == 4 and game.player_hand.has(card), "added talent must run on real hand entry")
	elif trigger == SkillEngine.TRIGGER_ON_DISCARDED:
		game.player_hand.append(card)
		game.player_field.current_mana = 3
		game.discard_card(card)
		_assert(game.shared_discard.has(card) and game.player_field.current_mana == 5, "discard talent plus normal discard refund")
	elif trigger == SkillEngine.TRIGGER_ON_BOARD_CHANGED:
		game.player_hand.append(card)
		game.summon_card(card, 2)
		var before: int = card.cost
		var other := CardData.new("Other", 0, 2, 1)
		game.player_hand.append(other)
		game.summon_card(other, 3)
		_assert(card.cost == before - 1, "board talent must react to another unit entering")
	else:
		card.take_damage(7)
		_assert(card.hp == 10, "continuous talent must cap a real hit")
