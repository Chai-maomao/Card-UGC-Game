extends "res://TestTurnPlanning.gd"

func _ready() -> void:
	for status in [SkillEngine.BUFF_SILENCE, SkillEngine.BUFF_STUN]:
		var game = _game()
		var card := _card("Controlled",4,12)
		var victim := _card("Victim",0,12)
		game.player_field.slots[0] = card
		game.player2_field.slots[0] = victim
		game.player_field.current_mana = 1
		game.player_field.action_points = 20
		var gain := {"trigger":"on_activate","effects":[{"effect":"gain_mana","target":"self","value":3}]}
		var passive := gain.duplicate(true)
		passive.trigger = "on_damaged"
		passive.skill_type = SkillEngine.SKILL_TYPE_TALENT
		card.skills = [gain,passive,{"trigger":SkillEngine.TRIGGER_ALWAYS,"skill_type":SkillEngine.SKILL_TYPE_TALENT,"effects":[{"effect":"damage_cap","value":1}]}]
		_check(card.single_damage_cap()==1,"continuous talent must work before control")
		card.apply_buff(status,1,2,1)
		var context: Dictionary = game.make_skill_context(0,0)
		SkillEngine.trigger_single_skill(card,0,context)
		SkillEngine.trigger_skills("on_damaged",card,context)
		SkillEngine.trigger_external_skill(passive,card,context)
		_check(game.player_field.current_mana==1,"control must disable active, passive, talent and external skills")
		_check(card.single_damage_cap()==0,"control must disable continuous talents")
		_check(not game.trigger_activate_skills(0,0,0),"controlled active skill must be rejected before spending resources")
		var attack: Dictionary = game.execute_attack(0,0)
		_check(victim.hp==(8 if status==SkillEngine.BUFF_SILENCE else 12),"silence permits basic attacks; stun blocks them")
		_check(attack.is_empty()==(status==SkillEngine.BUFF_STUN),"attack acceptance must reflect the control status")
		var before := card.hp
		card.take_damage(4)
		_check(card.hp==before-4 and game.player_field.slots[0]==card,"controlled unit remains in its slot and takes damage without its disabled talent")
		card.status_effects.clear()
		SkillEngine.trigger_single_skill(card,0,context)
		_check(game.player_field.current_mana==4,"clearing control restores skills")
	_test_stun_lifecycle()
	_test_configured_stun_duration()
	_test_directed_dodge()
	_test_dodge_expiry()
	_test_untargetable()
	if failures.is_empty():
		print("TEST_CONTROL_STATUSES_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)

func _test_stun_lifecycle() -> void:
	var game = _game()
	var card := _card("Stunned defender",4,12)
	card.skills = [{"trigger":"on_turn_end","skill_type":SkillEngine.SKILL_TYPE_TALENT,"effects":[{"effect":"gain_mana","target":"self","value":3}]}]
	game.player_field.slots[0] = card
	game.player2_field.slots[0] = _card("Attacker",3,12)
	card.apply_buff(SkillEngine.BUFF_STUN,1,1,2)
	game.current_player = 2
	_check(game.preview_end_turn_attacks().reason=="defended","stunned unit must still block attacks on its player")
	game.start_new_turn()
	_check(card.has_stun() and card.has_acted and card.has_attacked,"stun must persist during the skipped friendly turn")
	var restored = _game()
	restored.apply_initial_state(game.export_initial_state(),false)
	_check(restored.player_field.slots[0].has_stun(),"serialized active stun must survive restoration")
	game.player_field.current_mana = 1
	game.end_player_turn()
	_check(game.player_field.current_mana==1 and not card.has_stun(),"turn-end talent stays disabled before active stun expires")
	game.start_new_turn()
	game.end_player_turn()
	game.start_new_turn()
	_check(not card.has_acted and not card.has_stun(),"unit can act on the following friendly turn")

func _test_configured_stun_duration() -> void:
	var game = _game()
	var caster := _card("Caster", 1, 12)
	var target := _card("Target", 3, 12)
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = target
	game.player_field.action_points = 20
	caster.skills = [{"trigger": "on_activate", "effects": [
		{"effect": "add_buff", "buff_id": "stun", "duration": 2, "target": "target_single", "target_side": "enemy"},
		{"effect": "add_buff", "buff_id": "stun", "target": "target_single", "target_side": "enemy"},
	]}]
	_check(game.trigger_activate_skills(0, 0, 0, 2) and target.has_stun(), "the skill must apply both stuns immediately")
	for remaining in [1, 0]:
		game.end_player_turn()
		_check(target.has_stun(), "ending the caster's turn must not consume the target's stun")
		game.start_new_turn()
		_check(target.has_stun() and game.execute_attack(0, 0).is_empty(), "stun must block attacks on both target turns")
		game.end_player_turn()
		_check(target.status_effects.size() == remaining and target.has_stun() == (remaining > 0),
			"stuns with overlapping durations must count down together at the end of the target's turn")
		game.start_new_turn()
	game.end_player_turn()
	game.start_new_turn()
	_check(not game.execute_attack(0, 0).is_empty(), "the target can attack again on its third turn")

func _test_untargetable() -> void:
	var game = _game()
	var attacker := _card("Attacker", 4, 12)
	var warded := _card("Warded defender", 2, 12)
	var visible := _card("Visible defender", 0, 12)
	var protect := {"trigger": "on_activate", "effects": [{"effect": "add_buff",
		"buff_id": SkillEngine.BUFF_UNTARGETABLE, "target": "self", "duration": 1}]}
	warded.skills = [protect]
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = warded
	game.player2_field.slots[1] = visible
	game.current_player = 2
	game.player2_field.action_points = 20
	_check(game.trigger_activate_skills(0, -1, 0) and not warded.is_selectable(),
		"the written status must make its unit unselectable")
	warded.apply_buff(SkillEngine.BUFF_TAUNT, 1, 2, 2)
	game.current_player = 1
	game.player_field.action_points = 20
	var directed := {"trigger": "on_activate", "effects": [{"effect": "damage",
		"target": "target_sides", "target_side": "enemy", "value": 2}]}
	attacker.skills = [directed]
	_check(game.execute_attack(0, 0).is_empty() and not game.trigger_activate_skills(0, 0, 0)
		and game.player_field.actions_taken == 0 and warded.hp == 12 and visible.hp == 12,
		"choosing a protected unit must be rejected before paying or hitting adjacent units")
	_check(not game.player2_field.has_any_taunt() and game.preview_end_turn_attacks().reason == "defended",
		"protected taunt cannot make the remaining legal defender unreachable")
	_check(game.trigger_activate_skills(0, 1, 0) and warded.hp == 10 and visible.hp == 10,
		"a protected unit can still be hit as an unselected adjacent unit")
	var second := _card("Second attacker", 3, 10)
	game.player_field.slots[1] = second
	game.player2_field.slots[1] = null
	var hp: int = game.player2_field.player_hp
	_check(game.preview_end_turn_attacks().total_damage == 3, "only selectable units block end-turn attacks")
	var result: Dictionary = game.end_player_turn()
	_check(result.total_damage == 3 and game.player2_field.player_hp == hp - 3 and warded.hp == 10,
		"an eligible unit must hit the player before the defending ward expires")
	_check(warded.is_selectable(), "the one-turn ward must expire after that attack window")


func _test_directed_dodge() -> void:
	var game = _game()
	var attacker := _card("Attacker", 4, 12)
	var target := _card("Dodger", 0, 12)
	var neighbor := _card("Neighbor", 0, 12)
	game.player_field.slots[0] = attacker
	game.player2_field.slots[2] = target
	game.player2_field.slots[3] = neighbor
	game.player_field.current_mana = 8
	game.player_field.action_points = 20
	target.apply_buff(SkillEngine.BUFF_DODGE, 40, 2, 2)
	target.apply_buff(SkillEngine.BUFF_DODGE, 80, 2, 2)
	var seed_value := 1259
	game.game_rng.seed = seed_value
	var expected := RandomNumberGenerator.new()
	expected.seed = seed_value
	expected.randi_range(1, 100)
	var attack: Dictionary = game.execute_attack(0, 2)
	_check(attack.get("dodged", false) and target.hp == 12 and attacker.has_attacked,
		"a successful dodge must cancel the entire attack and consume the attacker's action")
	_check(game.game_rng.state == expected.state, "stacked Dodge must roll once for the attack")
	attacker.has_attacked = false
	attacker.has_acted = false
	var splash := {"effect": "damage", "target": SkillEngine.TARGET_SIDES, "target_side": "enemy", "value": 2}
	attacker.skills = [{"trigger": "on_activate", "effects": [splash, splash.duplicate()]}]
	expected.randi_range(1, 100)
	_check(game.trigger_activate_skills(0, 2, 0, 2) and target.hp == 12 and neighbor.hp == 12,
		"dodging at the chosen center must cancel the multi-effect action")
	_check(game.game_rng.state == expected.state, "a multi-effect skill must roll Dodge only once")
	attacker.skills_used.clear()
	_check(game.trigger_activate_skills(0, 3, 0, 2) and target.hp < 12,
		"an adjacent card that was not chosen is still hit")
	var damage := {"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 3}
	var spell := CardData.new("Spell", 2, 1, 0, [{"trigger": "on_cast", "effects": [damage]}])
	spell.card_type = "spell"
	var parasite := CardData.new("Parasite", 1, 2, 1)
	parasite.card_type = "parasite"
	game.player_hand.assign([spell, parasite])
	var saved_hp := target.hp
	var mana: int = game.player_field.current_mana
	_check(game.cast_spell(0, 0, 2, 2) and target.hp == saved_hp and game.shared_discard.has(spell),
		"a targeted spell is paid for and discarded when dodged")
	_check(game.attach_parasite(0, 2, 2) and target.parasite_cards.is_empty() and game.shared_discard.has(parasite),
		"a dodged parasite is discarded without attaching")
	_check(game.player_field.current_mana == mana - 3, "dodged cards still cost mana")


func _test_dodge_expiry() -> void:
	var game = _game()
	var attacker := _card("Attacker", 4, 12)
	var target := _card("Defender", 0, 12)
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = target
	var reference := RandomNumberGenerator.new()
	reference.seed = 400
	game.game_rng.seed = reference.seed
	var roll := reference.randi_range(1, 100)
	target.apply_buff(SkillEngine.BUFF_DODGE, roll - 1, 1, 2)
	_check(not game.execute_attack(0, 0).get("dodged", false) and target.hp == 8,
		"a roll above the configured Dodge chance must deal damage normally")
	target.tick_buffs(2)
	attacker.has_acted = false
	attacker.has_attacked = false
	var rng_state: int = game.game_rng.state
	_check(not game.execute_attack(0, 0).get("dodged", false) and target.hp == 4 and game.game_rng.state == rng_state,
		"expired Dodge must no longer change an attack or consume randomness")
