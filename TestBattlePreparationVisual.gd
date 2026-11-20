extends Node

func _ready() -> void:
	assert(DisplayServer.get_name() != "headless")
	var output := "res://artifacts/battle-preparation-ui-20261021/screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var cards := CardDatabase.beginner_deck()
	PlayerData.current_deck_id = "first"
	for language in ["zh", "en"]:
		Locale.language = language
		var other_name := "进攻卡组" if language == "zh" else "Vanguard"
		var empty_name := "空卡组" if language == "zh" else "Empty Deck"
		PlayerData.deck_library = [{"id": "first", "name": "默认卡组", "cards": cards}, {"id": "second", "name": other_name, "cards": cards.slice(0, 8)}, {"id": "third", "name": empty_name, "cards": []}]
		for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
			var viewport := SubViewport.new()
			viewport.size = dimensions
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			for mode in ["practice", "hotseat_p1", "hotseat_p2", "online"]:
				PlayerData.battle_select_mode = mode
				PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
				var ui = preload("res://BattleDeckSelect.tscn").instantiate()
				viewport.add_child(ui)
				await get_tree().create_timer(0.2).timeout
				var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
				for control in [ui.panel, ui.settings_panel, ui.confirm_button, ui.advanced_button, ui.view_button]:
					assert(bounds.encloses(control.get_global_rect()), "preparation controls must fit the viewport")
				assert(not ui.settings_panel.get_global_rect().intersects(ui.scroll_container.get_global_rect()))
				var advanced_rect: Rect2 = ui.advanced_button.get_global_rect()
				assert(ui.settings_panel.get_global_rect().encloses(advanced_rect) and not ui.settings_scroll.get_global_rect().intersects(advanced_rect))
				assert(viewport.gui_get_focus_owner() == ui.deck_tiles[0])
				assert(ui.deck_tiles[0].name_label.text == ("默认卡组" if language == "zh" else "Default Deck"))
				assert(ui.deck_tiles[1].name_label.text == other_name)
				var hover := InputEventMouseMotion.new()
				hover.position = ui.deck_tiles[1].get_global_rect().get_center()
				viewport.push_input(hover, true)
				await get_tree().process_frame
				assert(viewport.gui_get_focus_owner() == ui.deck_tiles[1] and ui.selected_deck_id == "first")
				await _click(viewport, ui.deck_tiles[1].get_global_rect().get_center())
				assert(ui.selected_deck_id == "second" and ui.deck_tiles[1].chosen and not ui.deck_tiles[0].chosen)
				await _capture(viewport, "%s/%s-%s-%dx%d.png" % [output, mode, language, dimensions.x, dimensions.y])
				await _click(viewport, ui.deck_tiles[1].get_global_rect().get_center(), true)
				assert(is_instance_valid(ui.details_layer), "a real double click must open the deck")
				assert(ui.details_grid.get_child_count() == 8)
				assert(bounds.encloses(ui.details_layer.get_node("PopupPanel").get_global_rect()))
				await _capture(viewport, "%s/cards-%s-%s-%dx%d.png" % [output, mode, language, dimensions.x, dimensions.y])
				if mode == "practice" and dimensions.x == 1280:
					viewport.size = Vector2i(960, 540)
					await get_tree().create_timer(0.15).timeout
					assert(Rect2(Vector2.ZERO, Vector2(960, 540)).encloses(ui.details_layer.get_node("PopupPanel").get_global_rect()))
					viewport.size = dimensions
					await get_tree().create_timer(0.15).timeout
				var close: Button = ui.details_layer.find_child("BackToPreparation", true, false)
				await _click(viewport, close.get_global_rect().get_center())
				assert(not is_instance_valid(ui.details_layer) and ui.selected_deck_id == "second")
				assert(viewport.gui_get_focus_owner() == ui.deck_tiles[1])
				await get_tree().process_frame
				await _click(viewport, ui.advanced_button.get_global_rect().get_center())
				assert(is_instance_valid(ui.advanced_layer))
				var frame: Panel = ui.advanced_layer.get_node("PopupPanel")
				assert(bounds.encloses(frame.get_global_rect()))
				await _capture(viewport, "%s/advanced-%s-%s-%dx%d.png" % [output, mode, language, dimensions.x, dimensions.y])
				var spins: Array[Node] = ui.advanced_layer.find_children("*", "SpinBox", true, false)
				assert(spins[0].editable == (mode != "hotseat_p2"))
				var recovery := ui.advanced_layer.find_child("ManaRecoveryMode", true, false) as OptionButton
				assert(recovery.disabled == (mode == "hotseat_p2"))
				if mode == "practice" and dimensions.x == 1280:
					recovery.select(1)
					recovery.item_selected.emit(1)
					var increment := ui.advanced_layer.find_child("mana_increment", true, false) as SpinBox
					increment.value = 2
					increment.get_line_edit().grab_focus()
					await get_tree().process_frame
					await _capture(viewport, "%s/elixir-increasing-%s.png" % [output, language])
					for button in ui.advanced_layer.find_children("*", "Button", true, false):
						if button.text == Locale.t("common.confirm"):
							await _click(viewport, button.get_global_rect().get_center())
							break
					assert(PlayerData.battle_config.get("mana_increment") == 2)
				ui._close_advanced()
				viewport.remove_child(ui)
				ui.free()
				await get_tree().process_frame
			viewport.queue_free()
			await get_tree().process_frame
	print("TEST_BATTLE_PREPARATION_VISUAL_OK real_input=click,double_click,advanced languages=2 sizes=2 modes=4")
	get_tree().quit(0)

func _click(viewport: SubViewport, point: Vector2, double: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.double_click = double and pressed
		viewport.push_input(event, true)
		await get_tree().process_frame
	await get_tree().create_timer(0.12).timeout

func _capture(viewport: SubViewport, path: String) -> void:
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(path) == OK)
