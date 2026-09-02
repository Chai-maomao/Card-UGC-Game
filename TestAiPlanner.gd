extends Node

const Planner = preload("res://BattleAiPlanner.gd")
const GameStateScript = preload("res://GameState.gd")

var failures: Array[String] = []
var puzzle_count := 0


func _ready() -> void:
	_test_attack_puzzles()
	_test_taunt_and_legality()
	_test_skill_targets()
	_test_resource_use()
	_test_difficulty_and_explanations()
	_assert(puzzle_count >= 20, "fewer than 20 fixed AI puzzles executed")
	if failures.is_empty():
		print("TEST_AI_PLANNER_OK puzzles=%d" % puzzle_count)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_AI_PLANNER_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_attack_puzzles() -> void:
	var game = _game()
	game.player_field.slots[0] = _card("Attacker", 2, 4, 3)
	game.player2_field.slots[0] = _card("Lethal", 4, 3, 4)
	game.player2_field.slots[1] = _card("Healthy", 4, 8, 4)
	_expect("lethal target", _pick(game).get("target_slot") == 0)

	game = _game()
	game.player_field.slots[0] = _card("Attacker", 2, 5, 3)
	game.player2_field.slots[0] = _card("Low threat", 1, 2, 1)
	game.player2_field.slots[1] = _card("High threat", 5, 2, 6)
	_expect("kill higher threat", _pick(game).get("target_slot") == 1)

	game = _game()
	game.player_field.slots[0] = _card("Cheap attacker", 1, 4, 3)
	game.player_field.slots[1] = _card("Expensive attacker", 6, 4, 3)
	game.player2_field.slots[0] = _card("Victim", 2, 2, 0)
	_expect("preserve expensive attacker", _pick(game).get("source_slot") == 0)

	game = _game()
	game.player_field.slots[0] = _card("Fragile", 5, 3, 2)
	game.player2_field.slots[0] = _card("Safe", 1, 10, 0)
	game.player2_field.slots[1] = _card("Punisher", 1, 10, 10)
	_expect("avoid obvious losing trade", _pick(game).get("target_slot") == 0)

	game = _game()
	game.player_field.slots[0] = _card("Striker", 2, 5, 4)
	game.player2_field.slots[0] = _card("Small", 1, 2, 1)
	game.player2_field.slots[1] = _card("Taunt", 2, 6, 1)
	_add_taunt(game.player2_field.slots[1])
	_expect("remove taunt", _pick(game).get("target_slot") == 1)


func _test_taunt_and_legality() -> void:
	var game = _game()
	game.player_field.slots[0] = _card("Striker", 2, 5, 4)
	game.player2_field.slots[0] = _card("Normal", 2, 5, 2)
	game.player2_field.slots[1] = _card("Taunt", 2, 5, 2)
	_add_taunt(game.player2_field.slots[1])
	var attacks := _actions_of(game, "attack")
	_expect("taunt restricts all attacks", attacks.all(func(a): return int(a["target_slot"]) == 1))

	game.player2_field.slots[2] = _card("Taunt2", 2, 5, 2)
	_add_taunt(game.player2_field.slots[2])
	attacks = _actions_of(game, "attack")
	_expect("multiple taunts remain legal", attacks.size() == 2 and attacks.all(func(a): return int(a["target_slot"]) in [1, 2]))

	game.turn_number = 1
	_expect("turn one blocks attacks", _actions_of(game, "attack").is_empty())
	game.turn_number = 2
	_expect("turn two enables attacks", not _actions_of(game, "attack").is_empty())
	game.player_field.slots[0].has_acted = true
	_expect("acted unit cannot attack", _actions_of(game, "attack").is_empty())


func _test_skill_targets() -> void:
	var game = _game()
	game.turn_number = 1
	game.player_field.slots[0] = _skill_card("Mage", _effect_skill(SkillEngine.EFFECT_DAMAGE, 3, SkillEngine.TARGET_SIDE_ENEMY))
	game.player2_field.slots[0] = _card("Killable", 2, 2, 1)
	game.player2_field.slots[1] = _card("Healthy", 2, 10, 1)
	_expect("damage skill finds lethal", _pick(game).get("target_slot") == 0)

	game.player2_field.slots[0] = _card("Low threat", 1, 10, 1)
	game.player2_field.slots[1] = _card("High threat", 5, 10, 7)
	_expect("damage skill prioritizes threat", _pick(game).get("target_slot") == 1)

	game = _game()
	game.turn_number = 1
	game.player_field.slots[0] = _skill_card("Healer", _effect_skill(SkillEngine.EFFECT_HEAL, 4, SkillEngine.TARGET_SIDE_ALLY))
	game.player_field.slots[1] = _card("Injured", 2, 8, 3)
	game.player_field.slots[1].hp = 2
	game.player_field.slots[2] = _card("Full", 2, 8, 3)
	_expect("heal targets missing health", _pick(game).get("target_slot") == 1)

	game = _game()
	game.turn_number = 1
	game.player_field.slots[0] = _skill_card("Buffer", _effect_skill(SkillEngine.EFFECT_ADD_BUFF, 2, SkillEngine.TARGET_SIDE_ALLY, SkillEngine.BUFF_ATK_BOOST))
	game.player_field.slots[1] = _card("Weak ally", 2, 5, 1)
	game.player_field.slots[2] = _card("Carry", 4, 5, 7)
	_expect("buff targets valuable ally", _pick(game).get("target_slot") == 2)

	var ally_actions := _actions_of(game, "activate")
	_expect("ally skill does not target enemy", ally_actions.all(func(a): return int(a["target_player"]) == 1))
	game.player_field.slots[0].skills = [_effect_skill(SkillEngine.EFFECT_DAMAGE, 2, SkillEngine.TARGET_SIDE_ENEMY)]
	var enemy_actions := _actions_of(game, "activate")
	_expect("enemy skill does not target ally", enemy_actions.all(func(a): return int(a["target_player"]) == 2))


func _test_resource_use() -> void:
	var game = _game()
	game.player_hand = [_card("Small", 1, 2, 1), _card("Strong", 3, 8, 5)]
	_expect("summon strongest affordable body", _pick(game).get("hand_index") == 1)

	game = _game()
	game.player_hand = [_card("Efficient", 1, 3, 2), _card("Inefficient", 4, 5, 4)]
	_expect("prefer resource efficiency", _pick(game).get("hand_index") == 0)

	game = _game()
	game.player_hand = [_card("Reserve", 2, 4, 2), _card("Drain", 4, 4, 2)]
	_expect("retain useful mana", _pick(game).get("hand_index") == 0)

	game = _game()
	for slot in range(5):
		game.player_field.slots[slot] = _card("Full%d" % slot, 1, 2, 1)
		game.player_field.slots[slot].has_acted = true
	game.player_hand = [_card("Blocked", 1, 8, 8)]
	_expect("full board blocks summon", _actions_of(game, "summon").is_empty())
	_expect("end turn when no useful action", str(_pick(game).get("type")) == "end_turn")


func _test_difficulty_and_explanations() -> void:
	var game = _game()
	game.player_hand = [_card("One", 1, 3, 2), _card("Two", 2, 5, 3)]
	var legal := Planner.generate_legal_actions(game)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var hard := Planner.choose_action(game, "hard", rng)
	_expect("hard choice is legal", _contains_action(legal, hard))
	_expect("hard choice is explainable", hard.get("explanation", []).size() > 0)
	rng.seed = 9
	var easy := Planner.choose_action(game, "easy", rng)
	_expect("easy uses same legal action space", _contains_action(legal, easy))
	_expect("difficulty uses controlled score error", easy.has("score") and hard.has("score"))


func _game():
	var game := GameStateScript.new()
	game.quiet = true
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.player_field.quiet = true
	game.player2_field.quiet = true
	game.player_field.current_mana = 4
	game.player2_field.current_mana = 4
	game.current_player = 1
	game.turn_number = 2
	game.game_rng.seed = 123
	return game


func _card(name: String, cost: int, hp: int, atk: int) -> CardData:
	var card := CardData.new(name, cost, hp, atk, [])
	card.card_id = name
	card.instance_id = name + "_instance"
	return card


func _skill_card(name: String, skill: Dictionary) -> CardData:
	var card := _card(name, 2, 6, 0)
	card.skills = [skill]
	return card


func _effect_skill(effect: String, value: int, side: String, buff: String = "") -> Dictionary:
	var data := {"effect": effect, "target": SkillEngine.TARGET_SINGLE, "target_side": side, "value": value}
	if not buff.is_empty():
		data["buff_id"] = buff
	return {"skill_name": "Puzzle", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100, "effects": [data]}


func _add_taunt(card: CardData) -> void:
	card.status_effects.append({"buff_id": SkillEngine.BUFF_TAUNT, "value": 1, "duration": 2})


func _pick(game) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return Planner.choose_action(game, "hard", rng)


func _actions_of(game, action_type: String) -> Array:
	return Planner.generate_legal_actions(game).filter(func(action): return str(action.get("type", "")) == action_type)


func _contains_action(actions: Array, candidate: Dictionary) -> bool:
	var clean := candidate.duplicate(true)
	clean.erase("score")
	clean.erase("explanation")
	for action in actions:
		if action == clean:
			return true
	return false


func _expect(label: String, condition: bool) -> void:
	puzzle_count += 1
	_assert(condition, "puzzle %02d: %s" % [puzzle_count, label])


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
