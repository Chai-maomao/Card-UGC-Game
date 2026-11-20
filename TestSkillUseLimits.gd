extends Node

var failures: Array[String] = []


func _ready() -> void:
	for single in [false, true]:
		_test_recursive_heal(single)
	_test_probability_and_silence()
	_test_parasite_reentry()
	_test_identical_attachment_skills()
	_test_parasite_limits_and_replay()
	_test_live_rules_help()
	if failures.is_empty():
		print("TEST_SKILL_USE_LIMITS_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_SKILL_USE_LIMITS_FAILED: " + failure)
		get_tree().quit(1)


func _game() -> RefCounted:
	var game := HeadlessBattleSimulator._create_game([], [], 707, PlayerData.DEFAULT_BATTLE_CONFIG)
	game.turn_number = 2
	return game


func _skill(trigger: String, kind: String, value: int, uses: int) -> Dictionary:
	return {"trigger": trigger, "max_uses": uses, "effects": [{"effect": kind, "target": "self", "value": value}]}


func _test_recursive_heal(single: bool) -> void:
	var game := _game()
	var card := CardData.new("Limited self-healer", 0, 6, 0, [_skill("on_healed", "heal", 1, 2)])
	card.hp = 1
	game.player_field.slots[0] = card
	var context: Dictionary = game.make_skill_context(0)
	if single: SkillEngine.trigger_single_skill(card, 0, context)
	else: SkillEngine.trigger_skills("on_healed", card, context)
	_check(card.hp == 3 and int(card.skills_used_count.get(0, 0)) == 2, "limited self-healing must reserve each use before recursive triggers (single=%s)" % single)
	_check(not context.get("_ugc_budget", {}).get("aborted", false), "a two-use skill must stop at its own limit without exhausting the recursion budget")
	SkillEngine.trigger_skills("on_healed", card, game.make_skill_context(0))
	_check(card.hp == 3, "an exhausted passive must remain blocked on later triggers")


func _test_probability_and_silence() -> void:
	var game := _game()
	var skill := _skill("on_turn_start", "gain_attack", 1, 1)
	skill.probability = 0
	var card := CardData.new("Chance", 0, 6, 0, [skill])
	game.player_field.slots[0] = card
	SkillEngine.trigger_skills("on_turn_start", card, game.make_skill_context(0))
	_check(card.skills_used_count.is_empty() and card.field_atk_bonus == 0, "failed skill probability must not consume a use")
	card.skills[0].probability = 100
	card.apply_buff(SkillEngine.BUFF_SILENCE, 1, 1, 1)
	SkillEngine.trigger_single_skill(card, 0, game.make_skill_context(0))
	_check(card.skills_used_count.is_empty(), "silence must not consume a use")
	card.status_effects.clear()
	SkillEngine.trigger_single_skill(card, 0, game.make_skill_context(0))
	_check(card.field_atk_bonus == 1 and int(card.skills_used_count.get(0, 0)) == 1, "a passed skill must consume exactly one use")
	card.reset_to_base()
	_check(card.skills_used_count.is_empty() and SkillEngine.has_uses_remaining(card, card.skills[0], 0), "existing reset/discard lifecycle must restore use limits")


func _test_parasite_limits_and_replay() -> void:
	var game := _game()
	var host := CardData.new("Host", 0, 6, 1, [_skill("on_attack", "gain_attack", 1, 1)])
	host.card_id = "host"
	game.player_field.slots[4] = host
	game.player2_field.slots[1] = CardData.new("Target", 0, 9, 0)
	for identity in ["parasite-a", "parasite-b"]:
		var parasite := CardData.new(identity, 0, 3, 0, [_skill("on_attack", "gain_attack", 2, 1)])
		parasite.card_id = identity
		parasite.card_type = "parasite"
		parasite.parasite_damage_mode = CardData.PARASITE_DAMAGE_LINKED
		ParasiteRules.attach(parasite, host)
	BattlePosition.ensure_ids(game)
	var trace := SkillTrace.new()
	game.trace_callable = trace.record
	var record := BattleRepro.begin(game)
	var simulation: RefCounted = game.copy_for_simulation()
	for action in [{"type": "attack", "source_slot": 4, "target_slot": 1}, {"type": "end_turn"}, {"type": "end_turn"}, {"type": "attack", "source_slot": 4, "target_slot": 1}]:
		_check(BattleRepro.execute_and_record(game, record, action).ok, "lifetime limit fixture must allow a second turn's attack")
		_check(BattleRepro.apply_action(simulation, action).ok and BattleRepro.state_hash(simulation) == BattleRepro.state_hash(game), "simulation copies must preserve attachment limits and exact command outcomes")
	_check(host.field_atk_bonus == 5 and int(host.skills_used_count.get(0, 0)) == 1, "host and parasites must each apply their one-use skill only once across turns")
	for parasite: CardData in host.parasite_cards:
		_check(int(parasite.skills_used_count.get(0, 0)) == 1, "each parasite must track its own use count independently of host or identical skills")
		var attributed := false
		for entry in trace.entries:
			if entry.get("card_id") == parasite.card_id and entry.get("event") == "resolved" and entry.get("skill_index") == 0:
				attributed = true
		_check(attributed, "parasite traces must identify the parasite and its own skill index for editor navigation")
	_check(BattleRepro.verify(record).ok, "limited parasite counters must survive JSON normalization and complete replay")
	var restored := BattlePosition.read(BattleRepro.export_json(BattlePosition.capture(game)))
	_check(restored.ok, "exhausted attachment snapshot must restore")
	if restored.ok:
		var restored_host: CardData = restored.game.player_field.slots[4]
		ParasiteRules.trigger_host_passives("on_attack", restored_host, restored.game.make_skill_context(4, 1, 2))
		_check(restored_host.field_atk_bonus == 5, "restoring a snapshot must not replenish parasite uses")


func _test_parasite_reentry() -> void:
	var game := _game()
	var host := CardData.new("Recursive host", 0, 8, 0)
	game.player_field.slots[0] = host
	var parasite := CardData.new("Limited reaction", 0, 3, 0, [_skill("on_damaged", "damage", 1, 2)])
	parasite.card_type = "parasite"
	parasite.parasite_damage_mode = CardData.PARASITE_DAMAGE_LINKED
	ParasiteRules.attach(parasite, host)
	var context: Dictionary = game.make_skill_context(0)
	ParasiteRules.trigger_host_passives("on_damaged", host, context)
	_check(host.hp == 6 and int(parasite.skills_used_count.get(0, 0)) == 2 and not context.get("_ugc_budget", {}).get("aborted", false), "recursive parasite effects must consume their own limits before reentry, preserving host self target")
	_check(host.skills_used_count.is_empty(), "parasite reservations must not add host counters")
	parasite.reset_to_base()
	parasite.skills[0].probability = 0
	ParasiteRules.trigger_host_passives("on_damaged", host, game.make_skill_context(0))
	_check(parasite.skills_used_count.is_empty(), "failed external skill probability must not reserve a parasite use")
	parasite.skills[0].probability = 100
	host.apply_buff(SkillEngine.BUFF_SILENCE, 1, 1, 1)
	ParasiteRules.trigger_host_passives("on_damaged", host, game.make_skill_context(0))
	_check(parasite.skills_used_count.is_empty(), "host silence must not reserve a parasite use")


func _test_live_rules_help() -> void:
	var game := _game()
	var language_before: String = Locale.language
	var before := BattleRepro.state_hash(game)
	for language in ["zh", "en"]:
		Locale.language = language
		var text := preload("res://BattleRulesHelp.gd").description(game)
		_check(text.contains(Locale.t("help.skills")) and text.contains("0.5") and text.contains(Locale.t("help.first_turn")), "current help must describe consecutive actives and current AP coefficients")
		game.battle_config = {"action_base": 7, "action_empty_slot_factor": 1.25, "action_empty_hand_factor": 0.75, "action_mana_factor": 1.5, "mana_per_turn": 6, "draw_per_turn": 4, "second_extra_mana": 2, "second_extra_cards": 1}
		var configured := preload("res://BattleRulesHelp.gd").description(game)
		_check(configured.contains("1.25") and configured.contains("0.75") and configured.contains("1.5") and configured.contains(Locale.t("help.resources", [6, 4, 5, 3, 8])), "help must reflect customized rules rather than hardcoded defaults")
		game.battle_config = {}
		var legacy := preload("res://BattleRulesHelp.gd").description(game)
		_check(legacy.contains(Locale.t("help.actions_legacy")) and not legacy.contains("0.5"), "legacy snapshots must explain free unit actions")
		game.allow_first_turn_attacks = true
		_check(preload("res://BattleRulesHelp.gd").description(game).contains(Locale.t("help.first_turn_attacks_allowed")), "first-turn attack exceptions must be reflected in help")
		game.allow_first_turn_attacks = false
		game.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	Locale.language = language_before
	_check(BattleRepro.state_hash(game) == before, "help generation must preserve gameplay state, RNG and limits")


func _test_identical_attachment_skills() -> void:
	var game := _game()
	var skill := _skill("on_attack", "gain_attack", 1, 1)
	var host := CardData.new("Same skill host", 0, 6, 0, [skill.duplicate(true)])
	game.player_field.slots[0] = host
	var parasite := CardData.new("Two identical skills", 0, 3, 0, [skill.duplicate(true), skill.duplicate(true)])
	parasite.card_type = "parasite"
	parasite.parasite_damage_mode = CardData.PARASITE_DAMAGE_LINKED
	ParasiteRules.attach(parasite, host)
	for _i in range(2):
		var context: Dictionary = game.make_skill_context(0)
		SkillEngine.trigger_skills("on_attack", host, context)
		ParasiteRules.trigger_host_passives("on_attack", host, context)
	_check(host.field_atk_bonus == 3 and int(host.skills_used_count.get(0, 0)) == 1, "identical attachment definitions must remain independent of the host's same skill")
	_check(int(parasite.skills_used_count.get(0, 0)) == 1 and int(parasite.skills_used_count.get(1, 0)) == 1, "two equal skill dictionaries in one parasite must retain distinct indices and limits")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
