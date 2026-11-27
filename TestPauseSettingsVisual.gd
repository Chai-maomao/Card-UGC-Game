extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _verify() -> void:
	battle.reparent(get_tree().root)
	get_tree().current_scene = battle
	var before := BattleRepro.state_hash(battle.game)
	assert(battle.battle_settings_btn.text == Locale.t("preferences.settings"))
	await _click(battle.battle_settings_btn.get_global_rect().get_center())
	var direct := UIMotion.top_popup()
	assert(direct != null and direct.name == "BattleSettingsOverlay" and get_tree().paused)
	var direct_settings = direct.get_child(0)
	assert(direct_settings.scene_file_path == "res://SettingsMenu.tscn")
	var appearance: OptionButton = direct_settings._preference_controls.appearance
	var dark_surface: Color = direct_settings._settings_panel.get_theme_stylebox("panel").bg_color
	await _click(appearance.get_global_rect().get_center())
	var choices := appearance.get_popup()
	assert(choices.visible and choices.item_count == 2)
	await _click(Vector2(choices.position) + Vector2(choices.size) * Vector2(0.5, 0.73))
	assert(appearance.selected == 1 and AppPreferences.get_value("appearance") == 1)
	assert(direct_settings._settings_panel.get_theme_stylebox("panel").bg_color.get_luminance() > dark_surface.get_luminance())
	var config := ConfigFile.new()
	assert(config.load(AppPreferences.PATH) == OK and config.get_value("presentation", "appearance") == 1)
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/appearance-settings-light.png")
	await _click(direct_settings.back_button.get_global_rect().get_center())
	if not AppPreferences.get_value("reduced_motion"):
		assert(is_instance_valid(direct) and direct_settings.modulate.a > 0.0, "closing settings should keep the layer visible during its fade")
	await get_tree().create_timer(0.2).timeout
	assert(not get_tree().paused and UIMotion.top_popup() == null and get_tree().current_scene == battle)
	NetworkManager.is_online = true
	await _click(battle.battle_settings_btn.get_global_rect().get_center())
	assert(UIMotion.top_popup() != null and not get_tree().paused)
	await _escape()
	assert(UIMotion.top_popup() == null and not get_tree().paused)
	NetworkManager.is_online = false
	await _escape()
	var pause := UIMotion.top_popup()
	assert(pause != null and get_tree().paused,"Escape must pause an offline battle")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/pause-local-blur.png")
	await _click(_button(pause,Locale.t("preferences.settings")).get_global_rect().get_center())
	var settings_layer := UIMotion.top_popup()
	assert(settings_layer != pause and get_tree().paused,"settings must open above the paused battle")
	var settings = settings_layer.get_child(0)
	assert(settings._preference_controls.appearance.selected == 1, "reopening settings must retain the appearance")
	if not AppPreferences.get_value("reduced_motion"):
		assert(settings.modulate.a < 1.0, "settings must fade in from the pause screen")
	await get_tree().create_timer(0.2).timeout
	settings._category_buttons.gameplay.pressed.emit()
	await get_tree().process_frame
	var toggle: CheckButton = settings._preference_controls.reduced_motion
	var previous_choice := toggle.button_pressed
	await _click(toggle.get_global_rect().get_center())
	assert(toggle.button_pressed != previous_choice,"clicking a setting must change its value")
	assert(toggle.button_pressed == AppPreferences.get_value("reduced_motion"),"visible setting must update the saved preference")
	var chosen: bool = toggle.button_pressed
	var saved := ConfigFile.new()
	assert(saved.load(AppPreferences.PATH) == OK and saved.get_value("presentation","reduced_motion") == chosen,"setting must persist to disk")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/pause-settings.png")
	await _click(settings.back_button.get_global_rect().get_center())
	await get_tree().create_timer(0.2).timeout
	assert(get_tree().paused and UIMotion.top_popup() == pause,"Back from settings must keep battle paused")
	await _click(_button(pause,Locale.t("preferences.settings")).get_global_rect().get_center())
	settings_layer = UIMotion.top_popup()
	settings = settings_layer.get_child(0)
	assert(settings._preference_controls.reduced_motion.button_pressed == chosen,"reopened settings must retain the chosen value")
	await _escape()
	assert(get_tree().paused and UIMotion.top_popup() == pause,"Escape must close settings before pause menu")
	await _click(_button(pause,Locale.t("preferences.leave")).get_global_rect().get_center())
	await get_tree().process_frame
	if not get_tree().paused or not is_instance_valid(pause) or UIMotion.top_popup() == pause:
		push_error("leaving from pause must keep the battle paused beneath a separate confirmation")
		get_tree().quit(1)
		return
	var confirmation := UIMotion.top_popup()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/pause-leave-confirmation.png")
	await _click(_button(confirmation,Locale.t("common.cancel")).get_global_rect().get_center())
	assert(get_tree().paused and UIMotion.top_popup() == pause,"Cancel must return to the paused menu")
	await _click(_button(pause,Locale.t("preferences.leave")).get_global_rect().get_center())
	await _escape()
	assert(get_tree().paused and UIMotion.top_popup() == pause,"Escape must dismiss confirmation before the pause menu")
	await _escape()
	assert(not get_tree().paused,"Escape from pause must resume battle")
	assert(BattleRepro.state_hash(battle.game) == before,"pause and settings must preserve the current battle")
	await _escape()
	pause = UIMotion.top_popup()
	await _click(_button(pause,Locale.t("preferences.leave")).get_global_rect().get_center())
	confirmation = UIMotion.top_popup()
	await _click(_button(confirmation,Locale.t("battle.abandon_confirm")).get_global_rect().get_center())
	await get_tree().scene_changed
	await get_tree().create_timer(.4).timeout
	assert(not get_tree().paused and get_tree().current_scene.scene_file_path == "res://MainMenu.tscn","confirmed exit must unpause and return to the main menu")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/appearance-main-menu-light.png")
	print("TEST_PAUSE_SETTINGS_VISUAL_OK")
	get_tree().quit(0)

func _escape() -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await get_tree().create_timer(.25).timeout

func _button(root: Node, label: String) -> Button:
	for child in root.find_children("*","Button",true,false):
		if child.text == label: return child
	return null
