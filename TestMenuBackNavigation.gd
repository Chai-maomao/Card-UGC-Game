extends Node


class NavigationRunner extends Node:
	var failures: Array[String] = []


	func run() -> void:
		UIMotion.clear_history()
		UIMotion.replace_scene("res://MainMenu.tscn", true)
		await get_tree().scene_changed
		await _settle()

		var menu = get_tree().current_scene
		var title_position: Vector2 = menu.start_battle_btn.global_position
		menu._show_battle_hub_popup()
		await get_tree().create_timer(0.25).timeout
		_assert(menu.battle_hub_layer != null, "battle hub must open from the title screen")
		_assert(not menu.start_battle_btn.is_visible_in_tree()
			and menu.battle_hub_layer.heading_label.text == Locale.t("menu.battle_hub_title")
			and menu.battle_hub_layer.heading_label.get_theme_font_size("font_size") > menu.start_battle_btn.get_theme_font_size("font_size"),
			"the entry must transition to the larger battle hub heading")
		var idle_color: Color = menu.my_cards_btn.get_theme_color("font_color")
		_assert(menu.start_battle_btn.get_theme_color("font_color") == idle_color
			and menu.card_editor_btn.get_theme_color("font_color") == idle_color,
			"battle and card editor entries must match the regular menu text")
		_assert(menu.battle_hub_layer.entries.global_position.distance_to(title_position) < 1.5,
			"battle options must use the original list origin")

		# An in-scene submenu must reveal its immediate parent when Back is used.
		var local_button := _find_button(menu.battle_hub_layer, Locale.t("menu.battle_local"))
		_assert(local_button != null, "battle hub must expose local battle")
		if local_button:
			local_button.grab_focus()
			local_button.pressed.emit()
			await _settle()
			_assert(is_instance_valid(menu.battle_hub_layer), "local-mode popup must retain battle hub as its parent")
			var mode_layer := _find_layer(menu, 120)
			_assert(mode_layer != null, "local-mode popup must be above the battle hub")
			var mode_back := _find_button(mode_layer, Locale.t("common.back"))
			_assert(mode_back != null, "local-mode popup must provide Back")
			if mode_back:
				_assert(not local_button.is_visible_in_tree()
					and mode_layer.heading_label.global_position.y < title_position.y
					and mode_layer.entries.global_position.distance_to(title_position) < 1.5,
					"local mode must place its heading above the anchored options")
				var escape := InputEventKey.new()
				escape.keycode = KEY_ESCAPE
				escape.pressed = true
				get_viewport().push_input(escape, true)
				escape.pressed = false
				get_viewport().push_input(escape, true)
				await _settle()
				_assert(is_instance_valid(menu.battle_hub_layer), "Back from local mode must reveal battle hub")
				_assert(local_button.is_visible_in_tree() and local_button.has_focus(), "Escape must restore the exact parent choice")

		# Cross-scene Back must restore both the scene and its parent-menu state.
		var online_button := _find_button(menu.battle_hub_layer, Locale.t("menu.online"))
		_assert(online_button != null, "battle hub must expose online battle")
		if online_button:
			online_button.pressed.emit()
			await _settle()
			var online_layer := menu.get_node_or_null("OnlineModePopup")
			_assert(online_layer != null, "online entry must open the current connection-method popup")
			var modal_back := _find_button(online_layer, Locale.t("common.back"))
			var server_button := _find_button(online_layer, Locale.t("mp.dedicated"))
			await _check_focus_reentry(modal_back, server_button)
			var lan_button := _find_button(online_layer, Locale.t("mp.direct"))
			_assert(lan_button != null, "online popup must expose LAN play")
			if lan_button: lan_button.pressed.emit()
			await get_tree().scene_changed
			await _settle()
			var lobby = get_tree().current_scene
			_assert(lobby.scene_file_path == "res://DirectLobby.tscn", "LAN entry must open the direct lobby")
			lobby.ip_input.text = "127.0.0.1:32123"
			lobby.back_btn.pressed.emit()
			await get_tree().scene_changed
			await _settle()
			menu = get_tree().current_scene
			_assert(menu.scene_file_path == "res://MainMenu.tscn", "Back from LAN must return to title scene")
			_assert(is_instance_valid(menu.battle_hub_layer) and menu.get_node_or_null("OnlineModePopup") != null, "Back from LAN must restore the online popup above the battle hub")
			_find_button(menu.get_node("OnlineModePopup"), Locale.t("mp.direct")).pressed.emit()
			await get_tree().scene_changed
			await _settle()
			lobby = get_tree().current_scene
			_assert(lobby.ip_input.text == "127.0.0.1:32123" and lobby.ip_input.has_focus(), "Reopening LAN must restore the address and focus")
			_assert(not NetworkManager.is_online and not lobby.join_btn.disabled, "Restoring the address must wait for the player to join")
			if not OS.has_feature("headless") and DisplayServer.get_name() != "headless":
				await get_tree().create_timer(0.65).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://artifacts/lan-room-reentry.png")
			lobby.back_btn.pressed.emit()
			await get_tree().scene_changed
			await _settle()
			menu = get_tree().current_scene
			var online_back := _find_button(menu.get_node("OnlineModePopup"),Locale.t("common.back"))
			online_back.pressed.emit()
			await _settle()
			_assert(is_instance_valid(menu.battle_hub_layer), "Back from online choices must reveal the battle hub")

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

		await _check_dedicated_entry_return()
		await _check_terminal_routes_and_failure()
		await _check_new_card_back_navigation()
		PlayerData.cancel_skill_tutorial()
		UIMotion.clear_history()
		if failures.is_empty():
			print("TEST_MENU_BACK_NAVIGATION_OK")
			get_tree().quit(0)
		else:
			for failure in failures:
				push_error("TEST_MENU_BACK_NAVIGATION_FAILED: %s" % failure)
			get_tree().quit(1)



	func _check_dedicated_entry_return() -> void:
		var menu = get_tree().current_scene
		menu._on_online_pressed()
		await _settle()
		_find_button(menu.get_node("OnlineModePopup"), Locale.t("mp.dedicated")).pressed.emit()
		await get_tree().scene_changed
		await _settle()
		var lobby = get_tree().current_scene
		lobby.room_input.text = "70517814"
		lobby._server_settings.button_pressed = true
		lobby.server_input.text = "192.0.2.12"
		lobby.back_btn.pressed.emit()
		await get_tree().scene_changed
		await _settle()
		menu = get_tree().current_scene
		_find_button(menu.get_node("OnlineModePopup"), Locale.t("mp.dedicated")).pressed.emit()
		await get_tree().scene_changed
		await _settle()
		lobby = get_tree().current_scene
		_assert(lobby.room_input.text == "70517814", "reopening the server room form must retain its room code")
		_assert(lobby.server_input.text == "192.0.2.12" and lobby.server_input.is_visible_in_tree(),
			"reopening the form must retain the custom address and expanded settings")
		_assert(lobby.room_input.has_focus() and not NetworkManager.is_online,
			"reopening the form must restore keyboard focus without submitting a connection")
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/server-room-reentry.png")
		lobby.server_input.text = "127.0.0.1"
		lobby.lobby_port = 1
		lobby.join_btn.pressed.emit()
		_assert(lobby.join_btn.disabled, "join must enter the pending state before cancellation")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		get_viewport().push_input(escape, true)
		await _settle()
		_assert(lobby.room_input.editable and lobby.status_label.text == Locale.t("lobby.connection_cancelled"),
			"Escape must cancel the connection and restore the form")
		var repeated := escape.duplicate() as InputEventKey
		repeated.echo = true
		get_viewport().push_input(repeated, true)
		await get_tree().create_timer(0.45).timeout
		_assert(is_instance_valid(lobby) and get_tree().current_scene == lobby,
			"holding Escape after cancellation must keep the player on the room form")
		if not is_instance_valid(lobby) or get_tree().current_scene != lobby:
			return
		_assert(lobby.room_input.text == "70517814" and lobby.room_input.has_focus(),
			"cancelled connection keeps the code and keyboard focus")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/server-room-escape-cancelled.png")
		var released := escape.duplicate() as InputEventKey
		released.pressed = false
		get_viewport().push_input(released, true)
		get_viewport().push_input(escape, true)
		await get_tree().create_timer(0.45).timeout
		_assert(get_tree().current_scene.get_node_or_null("OnlineModePopup") != null,
			"a separate Escape press must still return to connection choices")


	func _check_terminal_routes_and_failure() -> void:
		UIMotion.replace_scene("res://MainMenu.tscn",true)
		await get_tree().scene_changed
		await _settle()
		var main = get_tree().current_scene
		main._show_battle_hub_popup()
		main._on_online_pressed()
		await _settle()
		_find_button(main.get_node("OnlineModePopup"),Locale.t("mp.direct")).pressed.emit()
		await get_tree().scene_changed
		await _settle()
		var lobby = get_tree().current_scene
		await _check_lan_room_selection(lobby)
		await _check_lan_cancel_and_timeout(lobby)
		lobby._on_host_pressed()
		lobby._exit_waiting_room()
		await get_tree().scene_changed
		await _settle()
		_assert(not NetworkManager.is_online,"leaving a waiting room must close its transport")
		var parent = get_tree().current_scene
		_assert(parent.scene_file_path == "res://MainMenu.tscn" and parent.get_node_or_null("OnlineModePopup") != null,"waiting-room exit must restore connection choices")
		_find_button(parent.get_node("OnlineModePopup"),Locale.t("common.back")).pressed.emit()
		await _settle()
		_assert(get_tree().current_scene.scene_file_path == "res://MainMenu.tscn","Back after room exit must not resurrect the closed lobby")
		var keyboard_menu = get_tree().current_scene
		keyboard_menu._show_battle_hub_popup()
		await _settle()
		var modal = UIMotion.top_popup()
		_assert(modal != null,"menu overlays must register with the shared modal stack")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		get_viewport().push_input(escape,true)
		escape.pressed = false
		get_viewport().push_input(escape,true)
		if not AppPreferences.get_value("reduced_motion"):
			_assert(UIMotion.top_popup() == modal and not modal.is_queued_for_deletion(),
				"the closing overlay must own input until its return animation finishes")
			await get_tree().create_timer(0.25).timeout
		await _settle()
		_assert(not is_instance_valid(modal) or modal.is_queued_for_deletion() or not modal.visible,"Escape must close the top overlay before navigating")
		var original = get_tree().current_scene
		var depth := UIMotion.history_depth()
		UIMotion.change_scene("res://__missing_navigation_test__.tscn")
		await get_tree().create_timer(0.3).timeout
		_assert(not UIMotion._busy and get_tree().current_scene == original,"a failed route must unlock and retain the visible page")
		_assert(UIMotion.history_depth() == depth,"a failed route must roll back its tentative history entry")
		_assert(not UIMotion.last_navigation_error.is_empty(),"a failed route must expose diagnostic information")
		# Dismiss the native error window before exercising another exclusive dialog.
		for child in UIMotion.get_children():
			if child is AcceptDialog and child.visible:
				child.hide()
				child.confirmed.emit()
		await get_tree().process_frame
		PlayerData.init_card_draft()
		PlayerData.cancel_skill_tutorial()
		UIMotion.change_scene("res://SkillEditor.tscn")
		await get_tree().scene_changed
		await _settle()
		var editor = get_tree().current_scene
		editor.skill_name_input.text = "Unsaved navigation probe"
		editor._on_cancel_pressed()
		await _settle()
		_assert(get_tree().current_scene == editor,"Cancel must not discard dirty skill edits before confirmation")
		_assert(is_instance_valid(editor._discard_dialog) and editor._discard_dialog.visible,"dirty skill edits must show a confirmation")
		editor._discard_dialog.canceled.emit()
		editor._discard_dialog.hide()
		_assert(editor.skill_name_input.text == "Unsaved navigation probe","declining discard must retain the edit")
		UIMotion.replace_scene("res://MainMenu.tscn",true)
		await get_tree().scene_changed
		await _settle()

	func _check_new_card_back_navigation() -> void:
		for kind in ["minion", "spell", "parasite"]:
			var menu = get_tree().current_scene
			menu.card_editor_btn.pressed.emit()
			await _settle()
			var type_button := _find_button(UIMotion.top_popup(), Locale.t("editor.create_" + kind))
			if type_button == null:
				_assert(false, "card type menu must expose " + kind)
				return
			type_button.pressed.emit()
			await get_tree().scene_changed
			await _settle()
			var editor = get_tree().current_scene
			var initial_cost: float = editor.cost_input.value
			editor.cost_input.value = initial_cost + 1
			editor.back_button.pressed.emit()
			await _settle()
			var discard := editor._discard_dialog as ConfirmationDialog
			_assert(is_instance_valid(discard) and discard.visible, kind + " edits must require discard confirmation")
			if is_instance_valid(discard):
				discard.canceled.emit()
				discard.hide()
			_assert(editor.cost_input.value == initial_cost + 1, kind + " edit must survive declining discard")
			editor.cost_input.value = initial_cost
			editor.back_button.pressed.emit()
			await get_tree().create_timer(0.6).timeout
			var returned: bool = get_tree().current_scene.scene_file_path == "res://MainMenu.tscn"
			_assert(returned, kind + " default draft must go back without a discard prompt")
			if not returned:
				if is_instance_valid(discard): discard.hide()
				UIMotion.replace_scene("res://MainMenu.tscn", true)
				await get_tree().scene_changed
				await _settle()

	func _check_lan_room_selection(lobby: Control) -> void:
		NetworkManager.stop_lan_room_discovery()
		var room_a := {"address": "192.0.2.1", "port": 32121, "name": "LAN A"}
		var room_b := {"address": "192.0.2.2", "port": 32122, "name": "LAN B"}
		lobby.ip_input.text = ""
		NetworkManager.lan_rooms_updated.emit([room_a, room_b])
		var rooms: OptionButton = lobby.room_list
		_assert(rooms.selected == 0 and lobby.ip_input.text == "192.0.2.1:32121", "First discovery must present the address it selected")
		if DisplayServer.get_name() != "headless":
			rooms.show_popup()
			await _settle()
			NetworkManager.lan_rooms_updated.emit([room_b])
			_assert(rooms.get_popup().visible and rooms.item_count == 2 and rooms.get_item_text(0).contains("LAN A"), "A discovery update must not reassign an open menu's rows")
			rooms.get_popup().hide()
			await _settle()
			_assert(rooms.item_count == 1 and rooms.selected == -1 and lobby.ip_input.text == "192.0.2.1:32121", "Closing the list must apply the new rooms and keep the chosen address")
		else:
			NetworkManager.lan_rooms_updated.emit([room_b])
		lobby.ip_input.text = "192.0.2.2:32122"
		lobby.ip_input.text_changed.emit(lobby.ip_input.text)
		_assert(rooms.selected == 0, "The discovery list must follow a manually entered matching address")
		lobby.ip_input.text = ""
		lobby.ip_input.text_changed.emit("")
		NetworkManager.lan_rooms_updated.emit([room_a, room_b])
		_assert(rooms.selected == -1 and lobby.ip_input.text.is_empty(), "Discovery updates must respect a manually cleared address")
		lobby.join_btn.pressed.emit()
		_assert(not NetworkManager.is_online and lobby.status_label.text == Locale.t("direct.choose_room_or_address"), "Joining with no address must explain how to choose a room")
		if NetworkManager.is_online:
			NetworkManager.close_connection()
			NetworkManager.clear_room_session()
			lobby._show_room_entry("")
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/lan-discovery-manual-address.png")


	func _check_lan_cancel_and_timeout(lobby: Control) -> void:
		lobby.ip_input.text = "127.0.0.1:65536"
		lobby.join_btn.pressed.emit()
		_assert(not NetworkManager.is_online and lobby.status_label.text == Locale.t("direct.invalid_port") and lobby.ip_input.has_focus(), "An invalid LAN port must be rejected on the address page")
		var unreachable := "127.0.0.1:1"
		lobby.ip_input.text = unreachable
		lobby.join_btn.pressed.emit()
		var pending_on_entry: bool = lobby.lobby_panel.visible and lobby.back_btn.visible and lobby.back_btn.text == Locale.t("lobby.cancel_connection")
		_assert(pending_on_entry, "LAN joining must keep the address page and offer Cancel connection")
		if not pending_on_entry:
			NetworkManager.close_connection()
			NetworkManager.clear_room_session()
			lobby._show_room_entry("")
			return
		_assert(NetworkManager.is_online and lobby.join_btn.disabled and not lobby.ip_input.editable, "LAN joining must prevent changing or submitting the pending address")
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/lan-joining.png")
		lobby.back_btn.pressed.emit()
		_assert(get_tree().current_scene == lobby and not NetworkManager.is_online and lobby.ip_input.text == unreachable, "Cancelling LAN must close the pending connection and retain the address")
		_assert(lobby.status_label.text == Locale.t("direct.connection_cancelled") and lobby.ip_input.has_focus(), "Cancelling LAN must explain the outcome and restore address focus")
		lobby.join_btn.pressed.emit()
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		get_viewport().push_input(esc, true)
		await _settle()
		_assert(get_tree().current_scene == lobby and not NetworkManager.is_online, "Escape must cancel the pending join without leaving LAN")
		esc.pressed = false
		get_viewport().push_input(esc, true)
		lobby.join_btn.pressed.emit()
		var deadline := Time.get_ticks_msec() + int((NetworkManager.CONNECT_TIMEOUT + 2.0) * 1000.0)
		while NetworkManager.is_online and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_assert(not NetworkManager.is_online and NetworkManager.session_mode.is_empty() and lobby.ip_input.text == unreachable, "LAN timeout must clear the pending connection and retain the address")
		_assert(lobby.status_label.text == Locale.t("lobby.could_not_connect") and not lobby.join_btn.disabled and lobby.ip_input.has_focus(), "LAN timeout must explain failure and enable retry")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/lan-join-timeout.png")


	func _settle() -> void:
		await get_tree().process_frame
		await get_tree().process_frame


	func _check_focus_reentry(last: Button, first: Button) -> void:
		_assert(last != null and first != null, "online popup must have server and back actions")
		if last == null or first == null:
			return
		first.grab_focus()
		first.release_focus()
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.shift_pressed = true
		tab.pressed = true
		get_viewport().push_input(tab, true)
		_assert(last.has_focus(), "Shift+Tab without focus must enter the popup at its last action")
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/online-popup-reverse-tab.png")
		tab.pressed = false
		get_viewport().push_input(tab, true)
		last.grab_focus()
		last.release_focus()
		tab.shift_pressed = false
		tab.pressed = true
		get_viewport().push_input(tab, true)
		_assert(first.has_focus(), "Tab without focus must enter the popup at its first action")
		tab.pressed = false
		get_viewport().push_input(tab, true)


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
