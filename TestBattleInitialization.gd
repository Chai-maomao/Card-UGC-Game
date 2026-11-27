extends Node

const Game = preload("res://GameState.gd")
var failures: Array[String] = []


func _ready() -> void:
	var preparation := PlayerData.battle_preparation_snapshot()
	var config := PlayerData.battle_config.duplicate(true)
	var playtest := PlayerData.card_playtest_context.duplicate(true)
	var was_online := NetworkManager.is_online
	NetworkManager.is_online = false
	var previously_blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	for draw_amount in [0, 2, 5, 8]:
		for hp in [1, 50]:
			_compare_opening(draw_amount, hp)
	_test_explicit_config_isolation()
	_test_second_seat_opens()
	_test_regular_elixir_refill()
	EventBus.set_block_signals(previously_blocked)
	NetworkManager.is_online = was_online
	PlayerData._apply_battle_preparation(preparation)
	PlayerData.battle_config = config
	PlayerData.card_playtest_context = playtest
	if failures.is_empty():
		print("TEST_BATTLE_INITIALIZATION_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_BATTLE_INITIALIZATION_FAILED: " + failure)
		get_tree().quit(1)


func _compare_opening(draw_amount: int, hp: int) -> void:
	var config := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	config.starting_hp = hp
	config.draw_per_turn = draw_amount
	PlayerData.battle_config = config
	var p1 := _deck("P1")
	var p2 := _deck("P2")
	PlayerData.configure_hotseat_battle(p1, p2)
	var real_game = Game.new()
	real_game.quiet = true
	real_game.init_game(Callable(), 123)
	var simulated := HeadlessBattleSimulator._create_game(p1, p2, 123, config)
	var expected_hand := mini(8, draw_amount + 1)
	_check(simulated.player_field.player_hp == hp and simulated.player2_field.max_player_hp == hp,
		"simulated HP must use starting_hp=%d" % hp)
	_check(simulated.player_hand.size() == expected_hand and simulated.player2_hand.size() == expected_hand,
		"simulated opening must follow draw_per_turn=%d and the hand cap" % draw_amount)
	_check(BattleRepro.state_hash(real_game) == BattleRepro.state_hash(simulated),
		"real and simulated opening states, stats, action budgets and RNG must match (hp=%d draw=%d)" % [hp, draw_amount])
	_check(BattleRepro.state_hash(simulated) == BattleRepro.state_hash(HeadlessBattleSimulator._create_game(p1, p2, 123, config)),
		"fixed-seed initialization must be deterministic")
	_check(p1.size() == 12 and p2.size() == 12 and p1[0].hp == 3,
		"initialization must not mutate the supplied decks")
	var verified := BattleRepro.verify(BattleRepro.begin(simulated))
	_check(verified.ok, "custom opening must survive JSON-compatible replay validation")


func _test_explicit_config_isolation() -> void:
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	PlayerData.battle_config.starting_hp = 7
	var before := PlayerData.battle_config.duplicate(true)
	# An active editor playtest must not reserve instruments in batch simulation.
	PlayerData.card_playtest_context = {"test_card": {"name": "Do not inject", "cost": 0, "hp": 2, "atk": 0}}
	var explicit := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	explicit.starting_hp = 50
	explicit.draw_per_turn = 5
	var game := HeadlessBattleSimulator._create_game(_deck("A"), _deck("B"), 456, explicit)
	_check(game.player_field.player_hp == 50 and game.player_hand.size() == 6,
		"explicit simulation rules must take priority over preferences and playtest state")
	game.battle_config.starting_hp = 20
	_check(explicit.starting_hp == 50 and PlayerData.battle_config == before,
		"simulation must isolate caller rules and player preferences")
	var fallback := HeadlessBattleSimulator._create_game(_deck("A"), _deck("B"), 456)
	_check(fallback.player_field.player_hp == 7, "omitted rules must use the current configured HP")


func _test_regular_elixir_refill() -> void:
	for amount in [3, 5]:
		var rules := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
		if amount == 5:
			rules.mana_per_turn = 5
		var game := HeadlessBattleSimulator._create_game(_deck("A"), _deck("B"), 98, rules)
		game.start_new_turn()
		game.player_field.current_mana = 2
		game.start_new_turn()
		_check(game.player_field.current_mana == 2 + amount, "regular turns use the default or explicitly configured Elixir refill")
		game.player2_field.current_mana = 9
		game.start_new_turn()
		_check(game.player2_field.current_mana == 10, "Elixir refill respects the player's maximum")


func _test_second_seat_opens() -> void:
	PlayerData.configure_hotseat_battle(_deck("A"), _deck("B"))
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	PlayerData.battle_config.second_extra_cards = 1
	var game = Game.new()
	game.quiet = true
	game.init_game(Callable(), 529, 2)
	_check(game.current_player == 2 and game.turn_number == 1, "the toss can give the second seat the opening turn")
	var hands_before: int = game.player_hand.size()
	var mana_before: int = game.player_field.current_mana
	game.start_new_turn()
	_check(game.current_player == 1 and game.turn_number == 1, "the round stays at one until both players have acted")
	_check(game.player_field.current_mana == mana_before + 3 and game.player_hand.size() == hands_before + 2,
		"the first seat receives the second-player catch-up when they go second")
	var snapshot: Dictionary = game.export_initial_state()
	var restored = Game.new()
	restored.quiet = true
	restored.apply_initial_state(snapshot, false)
	_check(restored.starting_player == 2 and game.copy_for_simulation().starting_player == 2,
		"authoritative snapshots and simulation copies must preserve the opening seat")
	restored.start_new_turn()
	_check(restored.current_player == 2 and restored.turn_number == 2, "the next round starts with the same opening seat")
	snapshot.erase("starting_player")
	restored.apply_initial_state(snapshot, false)
	_check(restored.starting_player == 1, "snapshots from before the coin toss retain the original round order")


func _deck(prefix: String) -> Array:
	var cards: Array = []
	for index in range(12):
		var card := CardData.new("%s-%d" % [prefix, index], 1, 3, 1, [])
		card.card_id = "%s-card-%d" % [prefix, index]
		card.instance_id = "%s-instance-%d" % [prefix, index]
		cards.append(card)
	return cards


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
