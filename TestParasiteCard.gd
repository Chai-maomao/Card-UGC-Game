extends Node

const GameStateScript = preload("res://GameState.gd")
const ParasiteRules = preload("res://ParasiteRules.gd")

var failures: Array = []


func _ready() -> void:
	_test_parasite_card_type_flag()
	_test_attach_to_enemy_moves_from_hand_to_host()
	_test_attach_to_ally_is_allowed()
	_test_parasite_attack_grants_host_attack()
	_test_attack_damage_hits_parasite_hp_first()
	_test_parasite_uses_host_damage_reduction()
	_test_directed_skill_damage_hits_parasite_hp_first()
	_test_aoe_skill_bypasses_parasite()
	_test_parasite_breaks_to_discard()
	_test_host_death_discards_attached_parasite()
	_test_host_discard_discards_attached_parasite()
	_test_serialization_keeps_attached_parasites()
	_test_parasite_draft_keeps_passive_skills_only()
	_test_parasite_on_attack_passive_uses_host_context()
	_test_parasite_on_damaged_passive_targets_damage_source()
	_test_parasite_on_death_passive_resolves_before_discard()
	_test_silenced_host_disables_parasite_passive()
	_test_directed_ally_target_resolves_to_ally_field()
	if failures.is_empty():
		print("TEST_PARASITE_CARD_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _fail(message: String) -> void:
	failures.append(message)


func _new_game():
	var game = GameStateScript.new()
	game.init_game(Callable())
	# Parasite lifecycle assertions inspect the discard pile directly. Keep
	# unrelated catch-up rules off so a death-compensation draw cannot remove
	# the just-discarded host before the assertion runs.
	game.battle_config["death_compensation"] = false
	game.battle_config["face_damage_compensation"] = false
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


func _card(name: String, cost: int = 1, hp: int = 5, atk: int = 0, skills: Array = [], ctype: String = "minion") -> CardData:
	var card := CardData.new(name, cost, hp, atk, skills)
	card.card_type = ctype
	return card


func _parasite(name: String = "Parasite", cost: int = 1, hp: int = 3, atk: int = 2, skills: Array = []) -> CardData:
	return _card(name, cost, hp, atk, skills, "parasite")


func _damage_skill(name: String, target: String, value: int, trigger: String = SkillEngine.TRIGGER_ON_ACTIVATE, target_side: String = SkillEngine.TARGET_SIDE_ENEMY) -> Dictionary:
	return {"skill_name": name, "trigger": trigger, "effects": [{"target": target, "target_side": target_side, "effect": SkillEngine.EFFECT_DAMAGE, "value": value}]}


func _test_parasite_card_type_flag() -> void:
	var minion := _card("Minion")
	var parasite := _parasite()
	if minion.is_parasite():
		_fail("minion was marked as parasite")
	if not parasite.is_parasite():
		_fail("parasite card_type was not recognized")
	if parasite.card_type != "parasite":
		_fail("parasite card_type value is wrong")


func _test_attach_to_enemy_moves_from_hand_to_host() -> void:
	var game = _new_game()
	var parasite := _parasite("Enemy Parasite", 2, 3, 1)
	var enemy := _card("Enemy", 1, 5, 1)
	game.player_hand.append(parasite)
	game.player2_field.slots[0] = enemy
	game.player_field.current_mana = 5
	var ok := game.attach_parasite(0, 2, 0)
	if not ok:
		_fail("attach_parasite returned false for enemy target")
	if game.player_hand.has(parasite):
		_fail("attached parasite stayed in hand")
	if not enemy.parasite_cards.has(parasite):
		_fail("enemy host did not receive parasite")
	if game.player_field.current_mana != 3:
		_fail("attaching parasite did not spend mana correctly")


func _test_attach_to_ally_is_allowed() -> void:
	var game = _new_game()
	var parasite := _parasite("Ally Parasite", 1, 2, 1)
	var ally := _card("Ally", 1, 5, 1)
	game.player_hand.append(parasite)
	game.player_field.slots[0] = ally
	game.player_field.current_mana = 5
	if not game.attach_parasite(0, 1, 0):
		_fail("parasite could not attach to allied target")
	if not ally.parasite_cards.has(parasite):
		_fail("ally host did not receive parasite")


func _test_parasite_attack_grants_host_attack() -> void:
	var host := _card("Host", 1, 5, 2)
	var parasite := _parasite("Blade Bug", 1, 3, 4)
	ParasiteRules.attach(parasite, host)
	if host.effective_atk() != 6:
		_fail("parasite attack was not granted to host (atk=%d)" % host.effective_atk())


func _test_attack_damage_hits_parasite_hp_first() -> void:
	var game = _new_game()
	var attacker := _card("Attacker", 1, 5, 4)
	var victim := _card("Victim", 1, 5, 0)
	var parasite := _parasite("Shield Bug", 1, 3, 0)
	ParasiteRules.attach(parasite, victim)
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = victim
	game.execute_attack(0, 0)
	if victim.hp != 5:
		_fail("overflow attack damage passed through parasite (host hp=%d)" % victim.hp)
	if not game.shared_discard.has(parasite):
		_fail("broken parasite was not moved to discard after attack")
	if not victim.parasite_cards.is_empty():
		_fail("broken parasite stayed attached after attack")


func _test_parasite_uses_host_damage_reduction() -> void:
	var game = _new_game()
	var attacker := _card("Attacker", 1, 5, 3)
	var victim := _card("Victim", 1, 5, 0)
	var parasite := _parasite("Tiny Shield", 1, 1, 0)
	victim.apply_buff(SkillEngine.BUFF_DAMAGE_REDUCTION, 67, 1, 2)
	ParasiteRules.attach(parasite, victim)
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = victim
	game.execute_attack(0, 0)
	if victim.hp != 5:
		_fail("host took damage through parasite after reduction (host hp=%d)" % victim.hp)
	if parasite.hp != 1:
		_fail("parasite did not use host damage reduction before absorbing (parasite hp=%d)" % parasite.hp)
	if game.shared_discard.has(parasite):
		_fail("parasite was discarded even though reduced damage was 0")


func _test_directed_skill_damage_hits_parasite_hp_first() -> void:
	var game = _new_game()
	var caster := _card("Caster", 1, 5, 0, [_damage_skill("Bolt", SkillEngine.TARGET_SINGLE, 4)])
	var victim := _card("Victim", 1, 5, 0)
	var parasite := _parasite("Skill Shield", 1, 3, 0)
	ParasiteRules.attach(parasite, victim)
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = victim
	game.trigger_activate_skills(0, 0, 0)
	if victim.hp != 5:
		_fail("overflow directed skill damage passed through parasite (host hp=%d)" % victim.hp)
	if not game.shared_discard.has(parasite):
		_fail("broken parasite was not discarded after directed skill")


func _test_aoe_skill_bypasses_parasite() -> void:
	var game = _new_game()
	var caster := _card("Caster", 1, 5, 0, [_damage_skill("Nova", SkillEngine.TARGET_ALL, 2, SkillEngine.TRIGGER_ON_ACTIVATE, SkillEngine.TARGET_SIDE_ENEMY)])
	var victim := _card("Victim", 1, 5, 0)
	var parasite := _parasite("AoE Bypass", 1, 3, 0)
	ParasiteRules.attach(parasite, victim)
	game.player_field.slots[0] = caster
	game.player2_field.slots[0] = victim
	game.trigger_activate_skills(0, -1, 0)
	if victim.hp != 3:
		_fail("aoe skill should bypass parasite and damage host directly (host hp=%d)" % victim.hp)
	if parasite.hp != 3:
		_fail("aoe skill should not damage parasite (parasite hp=%d)" % parasite.hp)


func _test_parasite_breaks_to_discard() -> void:
	var host := _card("Host", 1, 5, 0)
	var parasite := _parasite("Small Bug", 1, 2, 0)
	ParasiteRules.attach(parasite, host)
	var discard: Array = []
	var remaining := ParasiteRules.absorb_damage(host, 2, discard)
	if remaining != 0:
		_fail("parasite did not absorb exact damage")
	if not discard.has(parasite):
		_fail("broken parasite was not discarded")
	if not host.parasite_cards.is_empty():
		_fail("broken parasite stayed on host")


func _test_host_death_discards_attached_parasite() -> void:
	var game = _new_game()
	var host := _card("Doomed Host", 1, 0, 0)
	var parasite := _parasite("Attached", 1, 2, 1)
	ParasiteRules.attach(parasite, host)
	game.player2_field.slots[0] = host
	game.cleanup_deaths()
	if not game.shared_discard.has(parasite):
		_fail("host death did not discard attached parasite")
	if game.player2_field.slots[0] != null:
		_fail("dead host stayed on field")


func _test_host_discard_discards_attached_parasite() -> void:
	var game = _new_game()
	var host := _card("Discarded Host", 1, 5, 0)
	var parasite := _parasite("Discarded Attached", 1, 2, 1)
	ParasiteRules.attach(parasite, host)
	game.player_field.slots[0] = host
	game.discard_card(host)
	if not game.shared_discard.has(parasite):
		_fail("discarding host did not release attached parasite to discard")
	if not game.shared_discard.has(host):
		_fail("discarding host did not discard host")
	if game.player_field.slots[0] != null:
		_fail("discarded host stayed on field")


func _test_serialization_keeps_attached_parasites() -> void:
	var host := _card("Host", 1, 5, 2)
	var parasite := _parasite("Serialized Bug", 1, 3, 4)
	ParasiteRules.attach(parasite, host)
	var data := PlayerData.serialize_card(host)
	var copy := PlayerData.deserialize_card(data)
	if copy.parasite_cards.size() != 1:
		_fail("attached parasite was not serialized/deserialized")
		return
	var restored: CardData = copy.parasite_cards[0]
	if restored.card_name != "Serialized Bug" or restored.atk != 4 or restored.hp != 3:
		_fail("serialized parasite values changed")
	if copy.effective_atk() != 6:
		_fail("deserialized parasite attack was not granted to host")


func _test_parasite_draft_keeps_passive_skills_only() -> void:
	PlayerData.init_parasite_draft()
	PlayerData.card_draft["name"] = "Draft Parasite"
	PlayerData.card_draft["skill1"] = _damage_skill("Passive", SkillEngine.TARGET_SINGLE, 1, SkillEngine.TRIGGER_ON_ATTACK)
	PlayerData.card_draft["skill2"] = _damage_skill("Should Remove", SkillEngine.TARGET_SINGLE, 1, SkillEngine.TRIGGER_ON_ACTIVATE)
	var card := PlayerData.build_card_from_draft()
	if not card.is_parasite():
		_fail("draft did not build parasite card")
	if card.skills.size() != 1:
		_fail("parasite draft did not keep exactly one passive skill")
	elif card.skills[0].get("trigger", "") != SkillEngine.TRIGGER_ON_ATTACK:
		_fail("parasite draft kept wrong trigger")


func _test_parasite_on_attack_passive_uses_host_context() -> void:
	var game = _new_game()
	var passive := _damage_skill("Bite", SkillEngine.TARGET_SINGLE, 2, SkillEngine.TRIGGER_ON_ATTACK)
	var parasite := _parasite("Biter", 1, 3, 0, [passive])
	var host := _card("Host", 1, 5, 1)
	var victim := _card("Victim", 1, 8, 0)
	ParasiteRules.attach(parasite, host)
	game.player_field.slots[0] = host
	game.player2_field.slots[0] = victim
	game.execute_attack(0, 0)
	if victim.hp != 5:
		_fail("parasite on_attack passive did not damage attack target with host context (hp=%d)" % victim.hp)


func _test_parasite_on_damaged_passive_targets_damage_source() -> void:
	var game = _new_game()
	var passive := _damage_skill("Revenge", SkillEngine.TARGET_SINGLE, 2, SkillEngine.TRIGGER_ON_DAMAGED)
	var parasite := _parasite("Revenge Bug", 1, 99, 0, [passive])
	var attacker := _card("Attacker", 1, 5, 1)
	var host := _card("Host", 1, 5, 0)
	ParasiteRules.attach(parasite, host)
	game.player_field.slots[0] = attacker
	game.player2_field.slots[0] = host
	game.execute_attack(0, 0)
	if attacker.hp != 3:
		_fail("parasite on_damaged passive did not target damage source (attacker hp=%d)" % attacker.hp)


func _test_parasite_on_death_passive_resolves_before_discard() -> void:
	var game = _new_game()
	var passive := _damage_skill("Death Burst", SkillEngine.TARGET_ALL, 1, SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TARGET_SIDE_ENEMY)
	var parasite := _parasite("Death Bug", 1, 3, 0, [passive])
	var host := _card("Host", 1, 0, 0)
	var enemy := _card("Enemy", 1, 5, 0)
	ParasiteRules.attach(parasite, host)
	game.player_field.slots[0] = host
	game.player2_field.slots[0] = enemy
	game.cleanup_deaths()
	if enemy.hp != 4:
		_fail("parasite on_death passive did not resolve before discard (enemy hp=%d)" % enemy.hp)


func _test_silenced_host_disables_parasite_passive() -> void:
	var game = _new_game()
	var passive := _damage_skill("Muted Bite", SkillEngine.TARGET_SINGLE, 2, SkillEngine.TRIGGER_ON_ATTACK)
	var parasite := _parasite("Muted Bug", 1, 3, 0, [passive])
	var host := _card("Host", 1, 5, 1)
	var victim := _card("Victim", 1, 8, 0)
	ParasiteRules.attach(parasite, host)
	host.apply_buff(SkillEngine.BUFF_SILENCE, 1, 1, 1)
	game.player_field.slots[0] = host
	game.player2_field.slots[0] = victim
	game.execute_attack(0, 0)
	if victim.hp != 8:
		_fail("silenced host should disable parasite passive")


func _test_directed_ally_target_resolves_to_ally_field() -> void:
	var game = _new_game()
	var healer := _card("Healer", 1, 5, 0, [{"skill_name": "Patch Ally", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 2}]}])
	var ally := _card("Ally", 1, 5, 0)
	ally.hp = 2
	game.player_field.slots[0] = healer
	game.player_field.slots[1] = ally
	game.trigger_activate_skills(0, 1, 0)
	if ally.hp != 4:
		_fail("directed ally target did not resolve to ally field (ally hp=%d)" % ally.hp)
