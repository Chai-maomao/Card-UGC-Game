extends Node

const Game = preload("res://GameState.gd")
var failures: Array[String] = []
var resolution_events: Array = []


func _ready() -> void:
	EventBus.hand_entry_resolved.connect(_on_hand_entry_resolved)
	_test_split_draw_and_reset()
	_test_no_same_batch_redraw()
	_test_charm_and_clone_overflow()
	_test_copy_hand_splits_per_card()
	_test_battle_stat_bonuses_reset_on_defeat()
	EventBus.hand_entry_resolved.disconnect(_on_hand_entry_resolved)
	if failures.is_empty():
		print("TEST_HAND_OVERFLOW_OK: draw/select admission, overflow lifecycle, charm/clone/copy, stat reset")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_HAND_OVERFLOW_FAILED: " + failure)
		get_tree().quit(1)


func _new_game() -> RefCounted:
	var game := Game.new()
	game.quiet = true
	game.player_field = BattleField.new("P1", 30, 10)
	game.player2_field = BattleField.new("P2", 30, 10)
	game.current_player = 1
	game.game_rng.seed = 73
	return game


func _card(name: String, hp: int = 4, atk: int = 2) -> CardData:
	return CardData.new(name, 2, hp, atk, [])


func _fill_hand(game, count: int) -> void:
	for index in range(count):
		game.player_hand.append(_card("占位%d" % index))


func _test_split_draw_and_reset() -> void:
	resolution_events.clear()
	var game = _new_game()
	_fill_hand(game, 5)
	var admitted := _card("入手")
	var overflow := _card("溢出", 7, 3)
	overflow.max_hp = 12
	overflow.hp = 1
	overflow.field_atk_bonus = 8
	overflow.temp_hp = 5
	overflow.apply_cost_reduction(2, false)
	game.shared_deck = [admitted, overflow]
	var drawn: Array = game.draw_cards_for_player(2, 1)
	_assert(drawn == [admitted], "two-card draw with one vacancy must admit only the first card")
	_assert(game.player_hand.size() == 6 and game.player_hand.back() == admitted, "admitted card must occupy the sole vacancy")
	_assert(game.shared_discard == [overflow], "the second card must move to discard instead of disappearing")
	_assert(overflow.hp == 7 and overflow.max_hp == 7 and overflow.effective_atk() == 3 and overflow.temp_hp == 0 and overflow.turn_cost_reduction == 0,
		"overflow must restore HP, max HP, attack, shield and turn cost before discard")
	_assert(resolution_events.size() == 2 and resolution_events[0]["destination"] == "hand" and resolution_events[1]["destination"] == "discard",
		"multi-card hand entry must emit ordered per-card destinations")


func _test_no_same_batch_redraw() -> void:
	var game = _new_game()
	_fill_hand(game, SkillEngine.MAX_HAND_SIZE)
	var only := _card("唯一牌")
	game.shared_deck = [only]
	game.draw_cards_for_player(2, 1)
	_assert(game.shared_deck.is_empty() and game.shared_discard == [only],
		"an overflowed card must not reshuffle and draw itself again in the same draw batch")


func _test_charm_and_clone_overflow() -> void:
	var charm_game = _new_game()
	_fill_hand(charm_game, SkillEngine.MAX_HAND_SIZE)
	var victim := _card("魅惑目标", 8, 4)
	victim.hp = 2
	victim.field_atk_bonus = 3
	charm_game.player2_field.slots[0] = victim
	SkillEffectApplier._apply_charm(victim, 1, {}, charm_game.make_skill_context(0, 0, 2))
	_assert(charm_game.player_hand.size() == SkillEngine.MAX_HAND_SIZE and charm_game.player2_field.slots[0] == null,
		"charm must remove its field target without exceeding the hand limit")
	_assert(charm_game.shared_discard.size() == 1 and charm_game.shared_discard[0].card_name == victim.card_name,
		"overflowed charm result must enter discard")
	var charmed_overflow: CardData = charm_game.shared_discard[0]
	_assert(charmed_overflow.hp == 8 and charmed_overflow.effective_atk() == 4 and not charmed_overflow.is_charmed(),
		"overflowed charm result must restore printed state before discard")

	var clone_game = _new_game()
	_fill_hand(clone_game, SkillEngine.MAX_HAND_SIZE)
	var enemy := _card("克隆目标", 6, 5)
	enemy.hp = 1
	clone_game.player2_field.slots[2] = enemy
	SkillEffectApplier._apply_clone_enemy(enemy, 1, {}, clone_game.make_skill_context(0, 2, 2))
	_assert(clone_game.player_hand.size() == SkillEngine.MAX_HAND_SIZE and clone_game.shared_discard.size() == 1,
		"clone at full hand must create then discard the clone")
	_assert(clone_game.shared_discard[0] != enemy and clone_game.shared_discard[0].instance_id != enemy.instance_id,
		"overflowed clone must keep an independent synchronized identity")


func _test_copy_hand_splits_per_card() -> void:
	var game = _new_game()
	_fill_hand(game, 5)
	SkillEffectApplier._apply_copy_hand(null, 2, {}, game.make_skill_context())
	_assert(game.player_hand.size() == SkillEngine.MAX_HAND_SIZE, "the first of two copies must fill the one open hand slot")
	_assert(game.shared_discard.size() == 1, "the second of two copies must overflow independently into discard")


func _test_battle_stat_bonuses_reset_on_defeat() -> void:
	var game = _new_game()
	var unit := _card("临时成长", 5, 2)
	game.player_field.slots[0] = unit
	SkillEffectApplier._apply_gain_max_hp(unit, 4, {}, game.make_skill_context())
	SkillEffectApplier._apply_gain_attack(unit, 3, {}, game.make_skill_context())
	_assert(unit.max_hp == 9 and unit.effective_atk() == 5, "max-HP and attack growth must apply while the card is in play")
	unit.hp = 0
	game.cleanup_deaths()
	_assert(game.shared_discard.has(unit) and unit.max_hp == 5 and unit.hp == 5 and unit.effective_atk() == 2,
		"defeat must restore printed max HP, current HP and attack before discard")


func _on_hand_entry_resolved(card: CardData, player: int, destination: String, source: String, _source_meta: Dictionary) -> void:
	resolution_events.append({"card": card, "player": player, "destination": destination, "source": source})


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
