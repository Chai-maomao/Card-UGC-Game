extends Node

func _ready() -> void:
	var writing := OS.get_cmdline_user_args().has("--write")
	if writing:
		var settings := preload("res://SettingsMenu.tscn").instantiate()
		add_child(settings)
		await get_tree().process_frame
		settings._preference_controls.reduced_motion.button_pressed = true
		settings._preference_controls.camera_shake.button_pressed = false
		assert(AppPreferences.bind_key("ui_cancel",KEY_F10),"alternate cancel key must save")
		settings.queue_free()
		PlayerData.card_draft = PlayerData.card_to_draft(CardData.new("重启存档检查",2,7,4,[]))
		PlayerData.editing_index = -1
		PlayerData.editing_deck_id = ""
		PlayerData.editing_instance_id = ""
		var editor := preload("res://CardEditor.tscn").instantiate()
		add_child(editor)
		await get_tree().process_frame
		editor._save_card_without_conflict(PlayerData.build_card_from_draft())
		editor.queue_free()
	else:
		assert(AppPreferences.get_value("reduced_motion") and not AppPreferences.get_value("camera_shake"),"restart must load saved settings")
		assert(AppPreferences.bindings.ui_cancel == KEY_F10,"restart must restore the custom key binding")
		var cards := PlayerData.card_library.filter(func(card): return card.card_name == "重启存档检查")
		assert(cards.size() == 1 and cards[0].cost == 2 and cards[0].max_hp == 7 and cards[0].atk == 4,"restart must load exactly one saved card with its attributes")
	await get_tree().process_frame
	print("TEST_SAVE_RESTART_OK_", "WRITE" if writing else "READ")
	get_tree().quit(0)
