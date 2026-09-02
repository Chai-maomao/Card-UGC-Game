extends Node

const BattleScene = preload("res://Main.tscn")
const TutorialController = preload("res://BattleTutorialController.gd")
const ProgressStore = preload("res://TutorialProgress.gd")

var failures: Array[String] = []
var progress_path := "user://test_tutorial_progress.cfg"


func _ready() -> void:
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
	tutorial._on_next()
	tutorial._on_next()
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

	battle._on_skill_activated(2, 0)
	_assert(trainee.skills_used.has(0), "guided skill must be applied by real battle logic")
	_assert(tutorial.phase == TutorialController.Phase.ATTACK_SOURCE, "skill must advance to attack step")
	battle._on_attack_requested(2)
	_assert(tutorial.phase == TutorialController.Phase.ATTACK_TARGET, "attack button must advance to target step")
	var target: CardData = battle.game.player2_field.slots[2]
	var target_hp := target.hp
	battle._on_enemy_slot_clicked(2)
	_assert(target.hp < target_hp, "guided attack must damage the real target")
	_assert(tutorial.phase == TutorialController.Phase.END_TURN, "attack must advance to end-turn step")

	battle._on_end_turn_pressed()
	await get_tree().create_timer(0.7).timeout
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
	PlayerData.clear_battle_preparation()
	ProgressStore.new(progress_path).clear()
	NetworkManager.close_connection()
	if failures.is_empty():
		print("TEST_TUTORIAL_FLOW_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_TUTORIAL_FLOW_FAILED: %s" % failure)
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
