extends Node


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer; run scripts/run_tests.ps1 -Suite visual")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(), CardDatabase.playtest_deck())
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	battle.game.player_hand.clear()
	for index in range(SkillEngine.MAX_HAND_SIZE):
		battle.game.player_hand.append(CardData.new("满手牌 %d" % (index + 1), index % 4 + 1, 4 + index, 1 + index % 3, []))
	var overflow := CardData.new("溢出测试牌", 3, 9, 4, [])
	overflow.hp = 2
	overflow.field_atk_bonus = 5
	battle.game.shared_deck = [overflow]
	battle.game.shared_discard.clear()
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().create_timer(1.05).timeout
	battle._on_game_draw_cards(1)
	await get_tree().create_timer(0.30).timeout
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png("user://hand_overflow_visual.png")
	print("HAND_OVERFLOW_VISUAL=%s result=%d" % [ProjectSettings.globalize_path("user://hand_overflow_visual.png"), result])
	await get_tree().create_timer(0.55).timeout

	battle.game.player_hand.pop_back()
	var selected_a := CardData.new("选中入手", 2, 6, 2, [])
	var selected_b := CardData.new("选中溢出", 4, 8, 3, [])
	selected_b.hp = 1
	battle.game.shared_deck = [selected_a, selected_b]
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().process_frame
	battle._show_pile_selection_popup(battle.game.shared_deck, 2, "deck", battle.game.player_hand, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var dialog: Node = null
	for child in battle.get_children():
		if child is CanvasLayer and child.get_node_or_null("CardCollectionPanel") != null:
			dialog = child
			break
	if dialog == null:
		push_error("pile selection dialog not installed")
		get_tree().quit(1)
		return
	for index in range(2):
		dialog._select(true, index)
	dialog._confirm()
	await get_tree().create_timer(0.30).timeout
	var split_image := get_viewport().get_texture().get_image()
	var split_result := split_image.save_png("user://hand_entry_split_visual.png")
	print("HAND_ENTRY_SPLIT_VISUAL=%s result=%d hand=%d discard=%d" % [ProjectSettings.globalize_path("user://hand_entry_split_visual.png"), split_result, battle.game.player_hand.size(), battle.game.shared_discard.size()])
	await get_tree().create_timer(0.40).timeout
	if result != OK or split_result != OK:
		get_tree().quit(1)
		return
	print("TEST_HAND_OVERFLOW_VISUAL_OK")
	get_tree().quit(0)
