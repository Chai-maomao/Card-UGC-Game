extends Node

var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer; run scripts/run_tests.ps1 -Suite visual")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(), CardDatabase.playtest_deck())
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await _settle(12)
	await get_tree().create_timer(0.8).timeout

	# A defeated unit must stay legible while visibly travelling to the shared
	# discard pile; authoritative state has already resolved underneath it.
	battle.game.player_hand.clear()
	battle.game.player2_hand.clear()
	var fallen := CardData.new("余烬守卫", 2, 6, 3, [])
	battle.game.player_field.slots[0] = fallen
	battle.update_entire_screen()
	await _settle(4)
	fallen.hp = 0
	battle._apply_deaths()
	await get_tree().create_timer(0.29).timeout
	_assert(_count_fx(battle, "death_discard_card") == 1, "defeated card must have one face-up discard-flight ghost")
	await _capture("card-death-discard-flow.png")
	await get_tree().create_timer(0.45).timeout
	_assert(battle.game.shared_discard.has(fallen), "defeated card must remain in the authoritative discard pile")

	# A multi-card draw should read as an ordered stream instead of several
	# perfectly overlapping backs, then reveal the real cards at their slots.
	battle.game.player_hand.clear()
	battle.game.shared_deck = [
		CardData.new("晨星", 1, 4, 1, []),
		CardData.new("远望", 2, 5, 2, []),
		CardData.new("回响", 3, 6, 3, []),
	]
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await _settle(3)
	battle._on_game_draw_cards(3)
	await get_tree().create_timer(0.19).timeout
	_assert(_count_fx(battle, "draw_card") >= 2, "draw batch must visibly stagger multiple travelling cards")
	for child in battle.hand_container.get_children():
		_assert(child.modulate.a < 0.01, "real hand cards must stay hidden until their travelling backs arrive")
	await _capture("card-draw-flow.png")
	await get_tree().create_timer(0.75).timeout
	_assert(battle.game.player_hand.size() == 3, "draw animation must not change resolved hand contents")
	for child in battle.hand_container.get_children():
		_assert(child.modulate.a > 0.99, "arriving hand cards must be fully visible after landing")

	if failures.is_empty():
		print("TEST_CARD_FLOW_ANIMATION_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_CARD_FLOW_ANIMATION_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _count_fx(battle: Node, kind: String) -> int:
	var count := 0
	var layer: CanvasLayer = battle.get_node("CanvasLayer")
	for child in layer.get_children():
		if str(child.get_meta("battle_fx_kind", "")) == kind:
			count += 1
	return count


func _settle(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://artifacts/" + file_name)
	_assert(result == OK, "failed to save " + file_name)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
