extends Node

const BattleScene = preload("res://Main.tscn")
const TutorialController = preload("res://BattleTutorialController.gd")
const ProgressStore = preload("res://TutorialProgress.gd")

var failures: Array[String] = []
var progress_path := "user://test_tutorial_progress.cfg"


func _ready() -> void:
	var config_before := PlayerData.battle_config.duplicate(true)
	var setup_before := PlayerData.battle_preparation_snapshot()
	var created_before := PlayerData.tutorial_created_card
	PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	ProgressStore.new(progress_path).clear()
	ProgressStore.new(progress_path).mark_editor_completed()
	NetworkManager.close_connection()
	PlayerData.prepare_tutorial_battle()
	var battle = BattleScene.instantiate()
	add_child(battle)
	await get_tree().process_frame
	var tutorial: BattleTutorialController = battle.tutorial_controller
	tutorial.progress_path = progress_path
	_assert(tutorial != null, "tutorial mode must create a guide controller")
	_assert(battle.game.turn_number == 1 and battle.game.current_player == 1, "tutorial battle must begin on its deterministic first turn")
	_assert(battle.game.player_hand.size() == 1, "tutorial must start with one guided hand card")

	await get_tree().process_frame
	var next_x := tutorial.next_button.position.x
	var skip_x := tutorial.skip_button.position.x
	var exit_x := tutorial.exit_button.position.x
	var opening_hash := BattleRepro.state_hash(battle.game)
	var seen: Array[int] = []
	while tutorial.phase != TutorialController.Phase.SUMMON and seen.size() < TutorialController.Phase.size():
		seen.append(tutorial.phase)
		_assert(not tutorial.allows("summon", {"slot": 2}), "orientation pages must not permit premature deployment")
		tutorial._on_next()
	_assert(seen == [TutorialController.Phase.INTRO, TutorialController.Phase.HUD, TutorialController.Phase.BOARD, TutorialController.Phase.HAND, TutorialController.Phase.RESOURCES, TutorialController.Phase.ACTIONS],
			"orientation must teach health, board, piles, resources and action economy before deployment")
	_assert(BattleRepro.state_hash(battle.game) == opening_hash, "orientation must not run game actions or change RNG")
	_assert(battle.game.player_field.action_budget == 11, "training budget must reflect its five empty slots and seven empty hand spaces")
	await get_tree().process_frame
	_assert(tutorial.phase == TutorialController.Phase.SUMMON, "intro must advance to summon step")
	_assert(tutorial.next_button.visible and tutorial.next_button.disabled, "action steps must retain a disabled primary navigation slot")
	_assert(is_equal_approx(tutorial.next_button.position.x, next_x) and is_equal_approx(tutorial.skip_button.position.x, skip_x)
			and is_equal_approx(tutorial.exit_button.position.x, exit_x), "tutorial navigation buttons must never exchange positions")
	var trainee: CardData = battle.game.player_hand[0]
	battle._on_card_drag_summoned(trainee, null, 0)
	_assert(battle.game.player_hand.size() == 1, "wrong tutorial slot must be blocked")
	battle._on_card_drag_summoned(trainee, null, 2)
	_assert(battle.game.player_field.slots[2] == trainee, "guided summon must use the real summon path")
	_assert(tutorial.phase == TutorialController.Phase.SKILL, "summon must advance to skill step")

	_assert(trainee.skills_used.has(0), "summon skill must resolve automatically through real battle logic")
	tutorial._on_next()
	_assert(tutorial.phase == TutorialController.Phase.CARD_STATS, "summon explanation must lead to unit stats")
	tutorial._on_next()
	_assert(tutorial.phase == TutorialController.Phase.ATTACK_SOURCE, "skill must advance to attack step")
	battle._on_attack_requested(2)
	_assert(tutorial.phase == TutorialController.Phase.ATTACK_TARGET, "attack button must advance to target step")
	var target: CardData = battle.game.player2_field.slots[2]
	var target_hp := target.hp
	battle._on_enemy_slot_clicked(2)
	_assert(target.hp < target_hp, "guided attack must damage the real target")
	_assert(tutorial.phase == TutorialController.Phase.COMBAT_RESULT, "attack must explain its real outcome before end turn")
	_assert(tutorial.body_label.text.contains(str(target_hp)) and tutorial.body_label.text.contains(str(target.hp)), "result must use actual target HP")
	_assert(tutorial._attack_payment.points == 0 and tutorial._attack_payment.mana == 0 and battle.game.next_action_payment().cost == 1,
			"first free attack must explain the next army-wide action cost")
	tutorial._on_next()
	_assert(tutorial.phase == TutorialController.Phase.FACE_DAMAGE, "tutorial must explain the route from units to player Health")
	tutorial._on_next()
	_assert(tutorial.phase == TutorialController.Phase.END_TURN, "face damage explanation must lead to end-turn action")

	battle._on_end_turn_pressed()
	var completion_deadline := Time.get_ticks_msec() + 10000
	while tutorial.phase != TutorialController.Phase.COMPLETE and Time.get_ticks_msec() < completion_deadline:
		await get_tree().process_frame
	_assert(tutorial.phase == TutorialController.Phase.COMPLETE, "ending the turn must complete the tutorial")
	_assert(ProgressStore.new(progress_path).status() == "completed", "tutorial completion must persist")
	_assert(ProgressStore.new(progress_path).editor_completed(), "battle completion must preserve skill editor tutorial progress")
	await get_tree().process_frame
	_assert(not tutorial.skip_button.visible and tutorial.next_button.visible and tutorial.exit_button.visible,
			"completion must replace skip with explicit continue and exit choices")
	_assert(tutorial.next_button.custom_minimum_size.x >= 164 and tutorial.exit_button.custom_minimum_size.x >= 96,
			"completion choices must reserve enough width for localized labels")

	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_lethal_tutorial()
	PlayerData.clear_battle_preparation()
	PlayerData._apply_battle_preparation(setup_before)
	PlayerData.battle_config = config_before
	PlayerData.tutorial_created_card = created_before
	ProgressStore.new(progress_path).clear()
	NetworkManager.close_connection()
	if failures.is_empty():
		print("TEST_TUTORIAL_FLOW_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_TUTORIAL_FLOW_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_lethal_tutorial() -> void:
	# The real card editor accepts ATK >= 6; the result page must also work when
	# the dummy has already left play and been reset in the shared discard pile.
	var trainee := CardData.new("Finisher", 2, 6, 9, [{"trigger": "on_summon", "effects": [{"effect": "draw_cards", "target": "self", "value": 1}]}])
	PlayerData.prepare_tutorial_battle(trainee)
	var battle = BattleScene.instantiate()
	add_child(battle)
	await get_tree().process_frame
	var guide: BattleTutorialController = battle.tutorial_controller
	guide.progress_path = progress_path
	guide.set_phase(TutorialController.Phase.SUMMON)
	battle._on_card_drag_summoned(battle.game.player_hand[0], null, 2)
	guide._on_next()
	guide._on_next()
	battle._on_attack_requested(2)
	battle._on_enemy_slot_clicked(2)
	_assert(battle.game.player2_field.slots[2] == null and guide.phase == TutorialController.Phase.COMBAT_RESULT,
			"a lethal tutorial attack must still reach the result page")
	_assert(guide.body_label.text == Locale.t("tutorial.result_body", [6, 0, 0, 0, 1]) and battle.game.player_field.current_mana == 4,
			"lethal result must show HP zero, actual payment and the real kill refund")
	# Finish the queued landing feedback before ending this test process.
	# The assertions above deliberately exercise immediate tutorial actions.
	await battle._wait_for_deployment_feedback()
	var feedback_deadline := Time.get_ticks_msec() + 10000
	while (battle._hp_feedback_running or not battle._hp_feedback_batches.is_empty()) and Time.get_ticks_msec() < feedback_deadline:
		await get_tree().process_frame
	_assert(not battle._hp_feedback_running and battle._hp_feedback_batches.is_empty(), "lethal tutorial feedback must finish")
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
