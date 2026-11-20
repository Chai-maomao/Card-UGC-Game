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
