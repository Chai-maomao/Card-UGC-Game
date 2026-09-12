extends Node

var failures: Array[String] = []
var event_count := 0


func _ready() -> void:
	_test_balance()
	_test_search_and_challenges()
	_test_trace()
	_test_sharing_and_rules()
	if failures.is_empty():
		print("TEST_PROJECT_IMPROVEMENTS_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_PROJECT_IMPROVEMENTS_FAILED: " + failure)
		get_tree().quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)


func _score(effects: Array, extra: Dictionary = {}) -> float:
	var skill := {"trigger": "on_cast", "effects": effects}
	skill.merge(extra, true)
	return float(BalanceEvaluator.evaluate_values(1, 0, 1, [skill], "spell").score)


func _test_balance() -> void:
	var damage := {"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 3}
	_check(is_equal_approx(_score([damage, damage]), _score([{"effect": "__repeat__", "repeat_count": 2, "then_effects": [damage]}])), "repeat must score its body")
	var condition := {"op": ">=", "lhs": {"kind": "num", "value": 2}, "rhs": {"kind": "num", "value": 1}}
	_check(is_equal_approx(_score([damage]), _score([{"effect": "__if_else__", "condition": condition, "then_effects": [damage], "else_effects": []}])), "constant true branch must match direct effect")
	_check(is_equal_approx(_score([damage]), _score([damage, {"effect": "__stop__"}, damage])), "stop must exclude later effects")
	var expression := damage.duplicate(true)
	expression.erase("value")
	expression.value_expr = {"kind": "expr", "op": "+", "a": {"value": 1}, "b": {"value": 2}}
	_check(is_equal_approx(_score([damage]), _score([expression])), "constant expression must match literal")
	_check(_score([damage], {"trigger": "on_attack", "max_uses": 1}) < _score([damage], {"trigger": "on_attack"}), "limited use must reduce recurring value")
	var minion := BalanceEvaluator.evaluate_values(2, 5, 8, [], "minion")
	var spell := BalanceEvaluator.evaluate_values(2, 5, 8, [], "spell")
	_check(float(minion.score) > float(spell.score) and float(spell.score) == 0, "spells must not score a unit body")
	expression.value_expr = {"kind": "var", "var_id": "hand_count"}
	var estimate := BalanceEvaluator.evaluate_values(2, 0, 1, [{"trigger": "on_cast", "effects": [expression]}], "spell")
	_check(estimate.uncertain and estimate.scenario_max > estimate.scenario_min, "dynamic value needs scenario uncertainty")


func _game() -> RefCounted:
	return HeadlessBattleSimulator._create_game([], [], 77)


func _on_event(_card: CardData, _delta: int, _hp: int) -> void:
	event_count += 1


func _test_search_and_challenges() -> void:
	var preferences := PlayerData.battle_config.duplicate(true)
	EventBus.hp_changed.connect(_on_event)
	for id in PracticeChallenges.IDS:
		var game := _game()
		PracticeChallenges.configure(game, id)
		_check(PracticeChallenges.stage(game, id) == "setup", "challenge must begin at setup stage: " + id)
		if id == "resource":
			_check(game.player_hand.size() == 3 and game.player_hand[2].card_name == "斥候", "resource challenge needs a tempting legal misplay")
			var trap := _game()
			PracticeChallenges.configure(trap, id)
			_check(trap.summon_card(trap.player_hand[2], 0), "resource distractor must be playable")
			_check(PracticeChallenges.failed(trap, id), "resource challenge must explain an unrecoverable wrong order")
		else:
			var early_attack := _game()
			PracticeChallenges.configure(early_attack, id)
			_check(not early_attack.execute_attack(0, 0).is_empty(), "combination challenge early attack must be legal")
			early_attack.cleanup_deaths()
			_check(PracticeChallenges.failed(early_attack, id), "combination challenge must detect attack-before-buff order")
			event_count = 0
		var trace := SkillTrace.new()
		game.trace_callable = trace.record
		var before := BattleRepro.state_hash(game)
		var rng_state: int = game.game_rng.state
		var first := BattleAiPlanner.choose_action(game, "hard", game.game_rng)
		_check(first.get("type") == "cast", "challenge must start with setup spell: " + id)
		_check(int(first.get("search_nodes", 0)) > 0 and int(first.get("search_nodes", 999)) <= BattleSearch.MAX_NODES, "bounded search required")
		_check(BattleRepro.state_hash(game) == before and game.game_rng.state == rng_state, "search mutated live state/RNG")
		_check(trace.entries.is_empty() and event_count == 0, "search leaked events or trace")
		_check(PlayerData.battle_config == preferences, "search mutated preferences")
		_check(BattleRepro.apply_action(game, first).ok, "setup action illegal")
		_check(PracticeChallenges.stage(game, id) == "payoff", "setup action must advance challenge progress: " + id)
		var second := BattleAiPlanner.choose_action(game, "hard", game.game_rng)
		_check(BattleRepro.apply_action(game, second).ok, "follow-up action illegal")
		game.cleanup_deaths()
		_check(PracticeChallenges.succeeded(game, id), "two actions must solve challenge: " + id)
		_check(PracticeChallenges.stage(game, id) == "success", "challenge must expose completed progress: " + id)
		event_count = 0
	EventBus.hp_changed.disconnect(_on_event)


func _test_trace() -> void:
	var game := _game()
	PracticeChallenges.configure(game, "combination")
	var trace := SkillTrace.new()
	game.trace_callable = trace.record
	var card: CardData = game.player_field.slots[0]
	card.skills = [{"trigger": "on_activate", "effects": [{"effect": "__repeat__", "repeat_count": 2, "then_effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 1}]}]}]
	SkillEngine.trigger_single_skill(card, 0, game.make_skill_context(0, 0, 2))
	var resolved := trace.entries.filter(func(row): return row.event == "resolved")
	_check(resolved.size() == 2, "trace needs both repeated effects")
	if not resolved.is_empty():
		_check(resolved[0].path == [0, "then_effects", 0] and resolved[0].value == 1 and resolved[0].skill_index == 0, "trace path/value/skill must locate editor block")
	card.status_effects.append({"buff_id": "silence", "value": 1, "duration": 2})
	SkillEngine.trigger_single_skill(card, 0, game.make_skill_context(0, 0, 2))
	_check(trace.entries.back().event == "silenced", "silence explanation missing")
	for i in range(350): trace.record({"event": "test", "index": i})
	_check(trace.entries.size() == SkillTrace.LIMIT and trace.dropped > 0, "trace must be bounded")


func _test_sharing_and_rules() -> void:
	var card := PlayerData.serialize_card(CardData.new("Shared", 2, 3, 1))
	var package := SharePackage.build([card], {}, {"author": "Creator", "revision": "2", "source": "Original"})
	_check(PlayerData.parse_share_package(JSON.stringify(package)).ok, "new share package must validate")
	var diff := SharePackage.changes(package, [card])
	_check(diff.unchanged == 1, "same cards must not be marked changed")
	var previous := card.duplicate(true)
	previous.atk = 9
	_check(SharePackage.changes(package, [previous]).changed == 1, "gameplay change missing")
	package.erase("provenance")
	_check(PlayerData.parse_share_package(JSON.stringify(package)).ok, "legacy package must still import")
	_check(MatchAgreement.valid_config(PlayerData.DEFAULT_BATTLE_CONFIG), "default agreement config invalid")
	var bad := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	bad.starting_hp = 0
	_check(not MatchAgreement.valid_config(bad), "invalid agreement config accepted")
	_check(MatchAgreement.digest({"a": 1, "b": 2}) == MatchAgreement.digest({"b": 2, "a": 1}), "agreement hash must be canonical")
