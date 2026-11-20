extends Node

class SelectionProbe:
	extends "res://BattleDeckSelect.gd"
	var submitted: Array = []
	func _start_battle_with_cards(cards: Array) -> void:
		submitted = cards

func _ready() -> void:
	var first := CardData.new("First", 1, 4, 2)
	var second := CardData.new("Second", 2, 6, 3)
	PlayerData.deck_library = [{"id": "first", "name": "First deck", "cards": [first]}, {"id": "second", "name": "Second deck", "cards": [second, first]}, {"id": "empty", "name": "Empty", "cards": []}]
	PlayerData.current_deck_id = "first"
	var library_hash := FileAccess.get_sha256(PlayerData.save_path)
	for context in [["practice", "easy"], ["practice", "normal"], ["practice", "hard"], ["hotseat_p1", ""], ["hotseat_p2", ""], ["online", "res://Lobby.tscn"], ["online", "res://BetaLobby.tscn"], ["online", "res://DirectLobby.tscn"]]:
		PlayerData.battle_select_mode = context[0]
		if context[0] == "practice": PlayerData.practice_ai_difficulty = context[1]
		if context[0] == "online": PlayerData.battle_select_next_scene = context[1]
		PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
		var ui = preload("res://BattleDeckSelect.tscn").instantiate()
		ui.set_script(SelectionProbe)
		add_child(ui)
		assert(ui.deck_tiles.size() == 3 and ui.deck_tiles[0].chosen)
		ui.deck_tiles[1].pressed.emit()
		assert(ui.selected_deck_id == "second" and not ui.deck_tiles[0].chosen and ui.deck_tiles[1].chosen)
		assert(ui.deck_tiles[1].button_pressed and not ui.confirm_button.disabled)
		ui._show_deck_details("second")
		assert(ui.details_grid.get_child_count() == 2)
		ui._close_details()
		assert(ui.selected_deck_id == "second")
		var copy: Array = ui._selected_cards()
		copy[0].hp = 1
		assert(second.hp == 6, "inspection and submission must not mutate library cards")
		var locked: bool = context[0] == "hotseat_p2"
		assert(ui.basic_controls.starting_hp.editable == not locked)
		ui._show_battle_config_popup()
		var advanced_hp := ui.advanced_layer.find_child("starting_hp", true, false) as SpinBox
		var advanced_action := ui.advanced_layer.find_child("action_base", true, false) as SpinBox
		assert(advanced_hp != null and advanced_action != null, "advanced settings must offer HP and action points")
		assert(advanced_hp.editable == not locked and advanced_action.editable == not locked)
		advanced_hp.value = 45
		ui._close_advanced()
		assert(PlayerData.battle_config.starting_hp == 30, "closing advanced settings must discard unconfirmed edits")
		await get_tree().process_frame
		if not locked:
			ui.basic_controls.starting_hp.value = 50
			assert(PlayerData.battle_config.starting_hp == 50)
			ui._show_battle_config_popup()
			advanced_hp = ui.advanced_layer.find_child("starting_hp", true, false) as SpinBox
			advanced_action = ui.advanced_layer.find_child("action_base", true, false) as SpinBox
			assert(advanced_hp.value == 50)
			advanced_action.value = 7
			advanced_hp.value = 46
			for button in ui.advanced_layer.find_children("*", "Button", true, false):
				if button.text == Locale.t("common.confirm"): button.pressed.emit()
			assert(PlayerData.battle_config.action_base == 7 and PlayerData.battle_config.starting_hp == 46)
			assert(ui.basic_controls.starting_hp.value == 46 and ui.submitted.is_empty(), "advanced confirmation saves rules without starting combat")
		ui._on_confirm_pressed()
		assert(ui.submitted.size() == 2 and not is_instance_valid(ui.advanced_layer), "all modes confirm directly using the selected deck")
		ui._select_deck("empty")
		assert(ui.confirm_button.disabled)
		ui.queue_free()
		await get_tree().process_frame
	PlayerData.deck_library = []
	var empty_ui = preload("res://BattleDeckSelect.tscn").instantiate()
	add_child(empty_ui)
	assert(empty_ui.confirm_button.disabled and empty_ui.view_button.disabled)
	empty_ui.queue_free()
	assert(FileAccess.get_sha256(PlayerData.save_path) == library_hash, "preparation must not write the collection")
	print("TEST_BATTLE_PREPARATION_OK modes=8 selection=exclusive advanced=transactional p2=readonly")
	get_tree().quit(0)
