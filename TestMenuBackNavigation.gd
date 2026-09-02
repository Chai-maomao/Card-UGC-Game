extends Node


class NavigationRunner extends Node:
	var failures: Array[String] = []


	func run() -> void:
		UIMotion.clear_history()
		UIMotion.replace_scene("res://MainMenu.tscn", true)
		await get_tree().scene_changed
		await _settle()

		var menu = get_tree().current_scene
		menu._show_battle_hub_popup()
		await _settle()
		_assert(menu.battle_hub_layer != null, "battle hub must open from the title screen")

		# An in-scene submenu must reveal its immediate parent when Back is used.
		var local_button := _find_button(menu.battle_hub_layer, Locale.t("menu.battle_local"))
		_assert(local_button != null, "battle hub must expose local battle")
		if local_button:
			local_button.pressed.emit()
			await _settle()
			_assert(is_instance_valid(menu.battle_hub_layer), "local-mode popup must retain battle hub as its parent")
			var mode_layer := _find_layer(menu, 120)
			_assert(mode_layer != null, "local-mode popup must be above the battle hub")
			var mode_back := _find_button(mode_layer, Locale.t("common.back"))
			_assert(mode_back != null, "local-mode popup must provide Back")
			if mode_back:
				mode_back.pressed.emit()
				await _settle()
				_assert(is_instance_valid(menu.battle_hub_layer), "Back from local mode must reveal battle hub")

		# Cross-scene Back must restore both the scene and its parent-menu state.
		var online_button := _find_button(menu.battle_hub_layer, Locale.t("menu.online"))
		_assert(online_button != null, "battle hub must expose online battle")
		if online_button:
			online_button.pressed.emit()
			await get_tree().scene_changed
			await _settle()
			var multiplayer = get_tree().current_scene
			_assert(multiplayer.scene_file_path == "res://MultiplayerMenu.tscn", "online entry must open multiplayer menu")
			multiplayer.back_btn.pressed.emit()
			await get_tree().scene_changed
			await _settle()
			menu = get_tree().current_scene
			_assert(menu.scene_file_path == "res://MainMenu.tscn", "Back from multiplayer must return to title scene")
			_assert(is_instance_valid(menu.battle_hub_layer), "Back from multiplayer must restore battle hub, not title root")

		# Exiting the real full-card tutorial follows the same parent route.
		var guide_button := _find_button(menu.battle_hub_layer, Locale.t("menu.tutorial"))
		_assert(guide_button != null, "battle hub must expose tutorial")
		if guide_button:
			guide_button.pressed.emit()
			await get_tree().scene_changed
			await _settle()
			var editor = get_tree().current_scene
			_assert(editor.scene_file_path == "res://CardEditor.tscn", "tutorial entry must open the full card editor")
			_assert(editor.card_tutorial_controller != null, "tutorial card editor must create its controller")
			if editor.card_tutorial_controller:
				editor.card_tutorial_controller._on_exit()
				await get_tree().scene_changed
				await _settle()
				menu = get_tree().current_scene
				_assert(menu.scene_file_path == "res://MainMenu.tscn", "tutorial exit must return to title scene")
				_assert(is_instance_valid(menu.battle_hub_layer), "tutorial exit must restore battle hub")

		PlayerData.cancel_skill_tutorial()
		UIMotion.clear_history()
		if failures.is_empty():
			print("TEST_MENU_BACK_NAVIGATION_OK")
			get_tree().quit(0)
		else:
			for failure in failures:
				push_error("TEST_MENU_BACK_NAVIGATION_FAILED: %s" % failure)
			get_tree().quit(1)


	func _settle() -> void:
		await get_tree().process_frame
		await get_tree().process_frame


	func _find_button(root: Node, label: String) -> Button:
		if root == null:
			return null
		for node in root.find_children("*", "Button", true, false):
			var button := node as Button
			if button != null and button.text == label:
				return button
		return null


	func _find_layer(root: Node, layer_value: int) -> CanvasLayer:
		for child in root.get_children():
			if child is CanvasLayer and (child as CanvasLayer).layer == layer_value:
				return child
		return null


	func _assert(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


func _ready() -> void:
	var runner := NavigationRunner.new()
	get_tree().root.add_child.call_deferred(runner)
	await get_tree().process_frame
	runner.run()
