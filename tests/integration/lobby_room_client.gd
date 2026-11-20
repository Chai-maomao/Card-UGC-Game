extends Node
const EDITOR_DRAFT_NAME := "断线草稿验证"
var role := ""
var lobby: Control
var ready_sent := false
var complete := false
var rules_edited := false
var cancellation_requested := false
var cancellation_verified := false
var screenshot_path := ""
var stall_card_art := false
var editing_gate := ""
var editing_side := "host"
var editor_verified := false
var replacing_editor_peer := false
var drop_editor_link := false
var waiting_for_editor_link_loss := false
var test_rematch := false
var results_departure_order := ""
var results_host_ready := ""
var joined_endpoint := ""
var first_match_id := ""
var test_lan_protocol_mismatch := false
var observed_peer_protocol := 0
var invite_file := ""

func _ready() -> void:
	_start_room.call_deferred()

func _start_room() -> void:
	var port := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role=arg.get_slice("=",1)
		if arg.begins_with("--language="): Locale.set_language(arg.get_slice("=", 1))
		if arg.begins_with("--port="): port=int(arg.get_slice("=",1))
		if arg.begins_with("--screenshot="): screenshot_path=arg.trim_prefix("--screenshot=")
		if arg == "--stall-card-art": stall_card_art = true
		if arg == "--rematch": test_rematch = true
		if arg == "--test-lan-protocol-mismatch": test_lan_protocol_mismatch = true
		if arg.begins_with("--results-guest-leaves="): results_departure_order = arg.get_slice("=", 1)
		if arg.begins_with("--results-host-ready="): results_host_ready = arg.trim_prefix("--results-host-ready=")
		if arg.begins_with("--invite-file="): invite_file = arg.trim_prefix("--invite-file=")
		if arg.begins_with("--editing-gate="): editing_gate = arg.trim_prefix("--editing-gate=")
		if arg.begins_with("--editing-side="): editing_side = arg.trim_prefix("--editing-side=")
		if arg == "--replacing-editor-peer": replacing_editor_peer = true
		if arg == "--drop-editor-link": drop_editor_link = true
	PlayerData.prepare_online_selection("res://DirectLobby.tscn")
	PlayerData.return_to_waiting_room=false
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	lobby=preload("res://DirectLobby.tscn").instantiate()
	get_tree().root.add_child(lobby)
	get_tree().current_scene=lobby
	NetworkManager.opponent_disconnected.connect(_disconnected)
	if test_lan_protocol_mismatch:
		get_tree().create_timer(30).timeout.connect(func(): _fail("protocol mismatch scenario timed out"))
		await _exercise_protocol_mismatch(port)
		return
	if role == "client" and (results_departure_order == "guest-link-lost" or not invite_file.is_empty()):
		if invite_file.is_empty():
			joined_endpoint = "127.0.0.1:%d" % port
			NetworkManager.lan_rooms_updated.emit([{"name": "Integration LAN", "address": "127.0.0.1", "port": port}])
		else:
			joined_endpoint = FileAccess.get_file_as_string(invite_file)
			lobby.ip_input.text = joined_endpoint
		if lobby.ip_input.text != joined_endpoint:
			_fail("the discovered LAN room did not display its custom port"); return
		lobby.ip_input.text_submitted.emit(joined_endpoint)
		if not NetworkManager.is_online or not lobby._joining:
			_fail("submitting the LAN address did not start joining"); return
		while lobby._joining:
			await get_tree().process_frame
		if not is_instance_valid(lobby.waiting_ui):
			_fail("the verified connection did not open the LAN room"); return
		if not invite_file.is_empty():
			if lobby.waiting_ui.find_child("CopyLanAddressButton", true, false) != null:
				_fail("the LAN guest was offered the host's invite action"); return
			print("TEST_ROOM_COPIED_ENDPOINT_CLIENT")
	else:
		var result := NetworkManager.host_game(port) if role=="host" else NetworkManager.join_game("127.0.0.1",port)
		if result!=OK: _fail("transport creation failed");return
		lobby._show_waiting_room()
		if not invite_file.is_empty():
			if not await _copy_lan_invite(port):
				return
	var selected_cards := PlayerData.get_cards_for_deck(PlayerData.current_deck_id)
	if selected_cards.is_empty() or PlayerData.battle_deck != selected_cards:
		_fail("entering the room did not select the current library deck"); return
	if stall_card_art:
		if role == "client":
			EventBus.rpc_card_art_received.disconnect(lobby._on_card_art_received)
		else:
			var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
			image.fill(Color.DARK_CYAN)
			var path := "user://integration-card-art.png"
			if image.save_png(path) != OK:
				_fail("could not save the card art fixture"); return
			PlayerData.battle_deck[0].art_path = path
	get_tree().create_timer(45 if test_rematch or not results_departure_order.is_empty() or drop_editor_link else 25).timeout.connect(func(): _fail("room scenario timed out"))
	if not editing_gate.is_empty():
		await _exercise_room_editor()


func _copy_lan_invite(port: int) -> bool:
	var share := lobby.waiting_ui.find_child("CopyLanAddressButton", true, false) as MenuButton
	if not share or not share.is_visible_in_tree():
		_fail("the LAN host cannot copy a join address"); return false
	await get_tree().process_frame
	share.show_popup()
	var menu := share.get_popup()
	if not menu.visible or menu.item_count == 0 or menu.is_item_disabled(0):
		_fail("the host has no copyable network interface"); return false
	var endpoint := str(menu.get_item_metadata(0))
	if endpoint.begins_with("127.") or not endpoint.ends_with(":%d" % port):
		_fail("the invite must specify the listening port and a non-loopback address"); return false
	if not await _capture_room_screen("lan-invite-addresses.png"):
		return false
	var before := DisplayServer.clipboard_get()
	menu.id_pressed.emit(menu.get_item_id(0))
	var copied := DisplayServer.clipboard_get()
	menu.hide()
	var confirmed := copied == endpoint and share.text == Locale.t("lobby.code_copied")
	var captured := await _capture_room_screen("lan-invite-copied.png")
	DisplayServer.clipboard_set(before)
	if not confirmed:
		_fail("choosing an address did not copy the endpoint and confirm it"); return false
	if not captured:
		return false
	var invite := FileAccess.open(invite_file, FileAccess.WRITE)
	if not invite:
		_fail("could not pass the copied address to the guest"); return false
	invite.store_string(copied)
	invite.close()
	print("TEST_ROOM_COPIED_ENDPOINT_HOST")
	return true


func _exercise_protocol_mismatch(port: int) -> void:
	NetworkManager.protocol_mismatch.connect(func(version: int): observed_peer_protocol = version)
	if role == "host":
		if NetworkManager.host_game(port) != OK:
			_fail("could not create the room for the mismatched guest"); return
		lobby._show_waiting_room()
		var original_peer := NetworkManager.peer
		var original_session := NetworkManager.session_id
		while observed_peer_protocol == 0:
			await get_tree().process_frame
		while NetworkManager.is_online and NetworkManager.opponent_peer_id != 0:
			await get_tree().process_frame
		await get_tree().process_frame
		if NetworkManager.peer != original_peer or NetworkManager.session_id != original_session or not NetworkManager.has_live_lan_room() or not is_instance_valid(lobby.waiting_ui):
			_fail("an incompatible guest closed or replaced the host's room"); return
		var deadline := Time.get_ticks_msec() + 2500
		while lobby.waiting_ui.status.text != Locale.t("wait.lan_incompatible_guest") and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if not lobby.start_btn.disabled or lobby.waiting_ui.status.text != Locale.t("wait.lan_incompatible_guest"):
			_fail("the retained room did not explain the incompatible guest"); return
		if not await _capture_room_screen("lan-incompatible-host.png"):
			return
		print("TEST_ROOM_INCOMPATIBLE_HOST_RETAINED")
		return
	var endpoint := "127.0.0.1:%d" % port
	lobby.ip_input.text = endpoint
	lobby.join_btn.pressed.emit()
	while lobby._joining:
		await get_tree().process_frame
	if observed_peer_protocol == 0 or observed_peer_protocol == AppVersion.PROTOCOL_VERSION or lobby.status_label.text != Locale.t("direct.protocol_mismatch", [AppVersion.PROTOCOL_VERSION, observed_peer_protocol]):
		_fail("the guest did not see both protocol versions"); return
	if lobby.ip_input.text != endpoint or not lobby.ip_input.has_focus() or lobby.join_btn.disabled or NetworkManager.is_online or is_instance_valid(lobby.waiting_ui):
		_fail("the incompatible guest did not return to the original address"); return
	if not await _capture_room_screen("lan-incompatible-guest.png"):
		return
	print("TEST_ROOM_INCOMPATIBLE_GUEST_RETRY")
	get_tree().quit(0)


func _capture_room_screen(filename: String) -> bool:
	if screenshot_path.is_empty():
		return true
	await get_tree().create_timer(0.6).timeout
	if lobby.lobby_panel.visible:
		var previous := Rect2()
		for control in lobby.get_node("Panel/VBoxContainer").get_children():
			if not control is Control or not control.visible:
				continue
			var current: Rect2 = control.get_global_rect()
			if previous.intersects(current):
				_fail("the LAN form overlapped after showing the version error"); return false
			previous = current
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(screenshot_path.get_base_dir().path_join(filename)) != OK:
		_fail("could not capture the room screen"); return false
	return true

func _exercise_room_editor() -> void:
	var edit_before_join := editing_side == "solo-host"
	var peer_leaves := editing_side.ends_with("-leaves")
	var is_editor := role != editing_side.trim_suffix("-leaves") if peer_leaves else role == editing_side or (edit_before_join and role == "host")
	if not edit_before_join:
		while not lobby._can_submit_ready():
			await get_tree().process_frame
	var original_peer := NetworkManager.peer
	if is_editor:
		if not edit_before_join:
			while not lobby.opponent_ready:
				await get_tree().process_frame
		lobby.create_card_btn.pressed.emit()
		await get_tree().scene_changed
		var editor := get_tree().current_scene
		if editor.scene_file_path != "res://CardEditor.tscn":
			_fail("create card did not open the editor"); return
		if peer_leaves:
			await _finish_editor_after_departure(editor, original_peer)
			return
		while not FileAccess.file_exists(editing_gate):
			await get_tree().process_frame
		editor.get_node("BackButton").pressed.emit()
		await get_tree().scene_changed
		lobby = get_tree().current_scene
		if stall_card_art and role == "client":
			EventBus.rpc_card_art_received.disconnect(lobby._on_card_art_received)
	else:
		if not edit_before_join:
			lobby.start_btn.pressed.emit()
		var deadline := Time.get_ticks_msec() + 4000
		while lobby.waiting_ui.status.text != Locale.t("wait.opponent_editing") and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if lobby.waiting_ui.status.text != Locale.t("wait.opponent_editing") or not lobby.start_btn.disabled or lobby.i_am_ready:
			_fail("opponent editing did not clear ready and explain the pause"); return
		if peer_leaves:
			await _leave_while_opponent_edits()
			return
		if not screenshot_path.is_empty():
			await RenderingServer.frame_post_draw
			var evidence := screenshot_path.get_base_dir().path_join("opponent-editing.png")
			if get_viewport().get_texture().get_image().save_png(evidence) != OK:
				_fail("could not capture the editing status"); return
		var gate := FileAccess.open(editing_gate, FileAccess.WRITE)
		gate.store_string("guest saw the editing status")
		gate.close()
	while not lobby._can_submit_ready() or lobby.start_btn.disabled:
		await get_tree().process_frame
	if NetworkManager.peer != original_peer or lobby.i_am_ready or lobby.opponent_ready:
		_fail("returning from the editor changed the room connection or inherited readiness"); return
	var gate := FileAccess.open(editing_gate + "." + role + "-returned", FileAccess.WRITE)
	gate.store_string("player can ready again")
	gate.close()
	var other_role := "client" if role == "host" else "host"
	while not FileAccess.file_exists(editing_gate + "." + other_role + "-returned"):
		await get_tree().process_frame
	editor_verified = true
	print("TEST_ROOM_EDITOR_RETURN_", role.to_upper())

func _leave_while_opponent_edits() -> void:
	while not FileAccess.file_exists(editing_gate + ".draft-open"):
		await get_tree().process_frame
	if drop_editor_link:
		waiting_for_editor_link_loss = true
		print("TEST_ROOM_EDITOR_PEER_CUT_READY")
		await NetworkManager.opponent_disconnected
		if NetworkManager.is_online or is_instance_valid(lobby.waiting_ui):
			_fail("the disconnected guest did not leave the waiting room"); return
		print("TEST_ROOM_EDITOR_PEER_LEFT")
		get_tree().quit(0)
		return
	lobby.waiting_ui.find_child("ExitButton", true, false).pressed.emit()
	var dialog := lobby.waiting_ui.get_node_or_null("LeaveRoomConfirmation") as ConfirmationDialog
	if dialog == null:
		_fail("leaving the occupied room did not ask for confirmation"); return
	dialog.get_ok_button().pressed.emit()
	await get_tree().scene_changed
	if NetworkManager.is_online:
		_fail("the departing player kept a room connection"); return
	print("TEST_ROOM_EDITOR_PEER_LEFT")
	get_tree().quit(0)


func _finish_editor_after_departure(editor: Node, original_peer: MultiplayerPeer) -> void:
	var room_deck_id := PlayerData.online_room_deck_id
	var original_session := NetworkManager.session_id
	var host_port := NetworkManager.room_server_port
	editor.name_input.text = EDITOR_DRAFT_NAME
	var gate := FileAccess.open(editing_gate + ".draft-open", FileAccess.WRITE)
	gate.store_string("draft is open")
	gate.close()
	while NetworkManager.opponent_peer_id != 0:
		await get_tree().process_frame
	if get_tree().current_scene != editor or editor.name_input.text != EDITOR_DRAFT_NAME:
		_fail("the editor lost the draft after the peer disconnected"); return
	editor._on_save_button_pressed()
	if not _press_editor_dialog_button(editor, 105, Locale.t("editor.save_card")):
		_fail("the draft could not be saved after the peer disconnected"); return
	if not PlayerData.get_cards_for_deck(room_deck_id).any(func(card): return card.card_name == EDITOR_DRAFT_NAME):
		_fail("the saved draft is missing from the room deck"); return
	if not _press_editor_dialog_button(editor, 100, Locale.t("editor.after_save_return")):
		_fail("the saved draft did not show its confirmation"); return
	await get_tree().process_frame
	editor.get_node("BackButton").pressed.emit()
	await get_tree().scene_changed
	lobby = get_tree().current_scene
	if lobby.scene_file_path != "res://DirectLobby.tscn":
		_fail("leaving the editor did not return to LAN multiplayer"); return
	if role == "host":
		if NetworkManager.peer != original_peer or NetworkManager.session_id != original_session or not is_instance_valid(lobby.waiting_ui) or not lobby.start_btn.disabled:
			_fail("the host could not return to the original room after the guest left"); return
		if lobby.waiting_ui.status.text != Locale.t("wait.lan_guest_left") or not PlayerData.battle_deck.any(func(card): return card.card_name == EDITOR_DRAFT_NAME):
			_fail("the retained room did not show the vacancy or the saved card"); return
	else:
		if NetworkManager.peer != null or is_instance_valid(lobby.waiting_ui) or lobby.join_btn.disabled:
			_fail("the guest did not return to a usable LAN join screen"); return
		if lobby.status_label.text != Locale.t("lobby.lan_host_disconnected") or lobby.ip_input.text != "127.0.0.1:%d" % host_port:
			_fail("the guest lost the disconnect notice or address for retry"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("editor-after-disconnect.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the room after editing"); return
	if role == "host":
		editor_verified = true
		print("TEST_ROOM_EDITOR_HOST_RETAINED")
	else:
		print("TEST_ROOM_EDITOR_CLIENT_BACK")
		get_tree().quit(0)


func _press_editor_dialog_button(editor: Node, canvas_order: int, button_text: String) -> bool:
	for child in editor.get_children():
		if child is CanvasLayer and child.layer == canvas_order:
			for button in child.find_children("*", "Button", true, false):
				if button.text == button_text:
					button.pressed.emit()
					return true
	return false

func _process(_delta: float) -> void:
	if complete or not is_instance_valid(lobby): return
	if not editing_gate.is_empty() and not editor_verified: return
	if ready_sent and not cancellation_verified and NetworkManager.room_wait_reason == "cancelled":
		if not NetworkManager.is_online or lobby.i_am_ready or lobby.match_agreement.pending:
			_fail("cancelling rules did not return to room preparation"); return
		cancellation_verified = true
		ready_sent = false
		if stall_card_art and role == "client":
			EventBus.rpc_card_art_received.connect(lobby._on_card_art_received)
		print("TEST_ROOM_CANCEL_READY_", role.to_upper())
	if not ready_sent and lobby._can_submit_ready():
		if role == "host" and not rules_edited:
			rules_edited = true
			lobby.waiting_ui._show_rules()
			var dialog = lobby.waiting_ui.get_node("AdvancedSettings")
			dialog.find_child("starting_hp",true,false).value = 37
			dialog.find_child("mana_per_turn",true,false).value = 3
			for button in dialog.find_children("*","Button",true,false):
				if button.text==Locale.t("common.confirm"): button.pressed.emit(); break
		if int(PlayerData.battle_config.get("starting_hp",0)) != 37 or int(PlayerData.battle_config.get("mana_per_turn",0)) != 3: return
		print("TEST_ROOM_RULES_SYNC_",role.to_upper())
		ready_sent=true
		lobby._on_start_pressed()
	if lobby.i_am_ready and lobby.opponent_ready and lobby.match_agreement.pending:
		if not cancellation_verified:
			if role == "client" and not cancellation_requested:
				for dialog in lobby.match_agreement.get_children():
					if dialog is ConfirmationDialog and dialog.visible:
						if stall_card_art:
							var showed_fallback: bool = dialog.find_children("*", "Label", true, false).any(func(item: Label):
								return item.text.contains(Locale.t("wait.art_fallback"))
							)
							if not showed_fallback or lobby._art_transfer_complete() or NetworkManager.room_match_started:
								_fail("LAN card art timeout did not open the rules confirmation"); return
							print("TEST_ROOM_ART_FALLBACK_CLIENT")
						cancellation_requested = true
						dialog.get_cancel_button().pressed.emit()
						break
			return
		for dialog in lobby.match_agreement.get_children():
			if dialog is ConfirmationDialog and dialog.visible:
				complete = true
				var expected_size := PlayerData.battle_deck.size()
				if replacing_editor_peer:
					expected_size += 1
					if not PlayerData.opponent_battle_deck.any(func(card): return card.card_name == EDITOR_DRAFT_NAME):
						_fail("the replacement did not receive the card saved during the disconnect"); return
				elif editing_side == "client-leaves":
					expected_size -= 1
				if PlayerData.opponent_battle_deck.size() != expected_size: _fail("submitted deck has the wrong size");return
				print("TEST_ROOM_READY_", role.to_upper())
				dialog.get_ok_button().pressed.emit()
				await get_tree().scene_changed
				await _play_until_disconnect()
				return

func _play_until_disconnect() -> void:
	var battle := get_tree().current_scene
	if battle.scene_file_path != "res://Main.tscn": _fail("confirmed match did not start");return
	if battle.game.starting_player != NetworkManager.match_opening_player or battle.game.current_player != battle.game.starting_player:
		_fail("LAN battle did not use the transmitted coin result"); return
	print("TEST_ROOM_OPENING_PLAYER ", battle.game.starting_player)
	while not battle.is_my_turn() or battle.end_turn_button.disabled: await get_tree().process_frame
	battle._on_end_turn_pressed()
	if (test_rematch or not results_departure_order.is_empty()) and first_match_id.is_empty():
		await _return_for_rematch(battle)
		return
	if test_rematch:
		if NetworkManager.battle_match_id == first_match_id:
			_fail("the second match reused the first match identifier"); return
		print("TEST_ROOM_REMATCH_", role.to_upper())
	if not results_departure_order.is_empty() and NetworkManager.battle_match_id == first_match_id:
		_fail("the replacement match reused the first match identifier"); return
	if role == "client":
		return
	while battle.game.turn_number < 2: await get_tree().process_frame
	print("TEST_ROOM_MATCH_STARTED_HOST")
	NetworkManager.close_connection()
	get_tree().quit(0)

func _return_for_rematch(battle: Node) -> void:
	while battle.game.turn_number < 2:
		await get_tree().process_frame
	first_match_id = NetworkManager.battle_match_id
	var original_peer := NetworkManager.peer
	battle.game.player2_field.player_hp = 0
	if not battle._check_and_show_game_over():
		_fail("the first LAN match did not reach results"); return
	var result := battle.get_node("CanvasLayer/BattleResultLayer")
	if not results_departure_order.is_empty():
		await _exercise_results_departure(result, original_peer)
		return
	var back: Button
	for button in result.find_children("*", "Button", true, false):
		if button.text == Locale.t("result.back_room"):
			back = button
			break
	if back == null:
		_fail("LAN results do not offer to return to the existing room"); return
	if role == "host":
		var unrelated_match := Crypto.new().generate_random_bytes(12).hex_encode()
		if NetworkManager.rpc_id(NetworkManager.opponent_peer_id, "rpc_player_ready", [], unrelated_match) != OK:
			_fail("could not exercise an out-of-date return notice"); return
		await get_tree().create_timer(2.0).timeout
	back.pressed.emit()
	await get_tree().scene_changed
	lobby = get_tree().current_scene
	if lobby.scene_file_path != "res://DirectLobby.tscn" or NetworkManager.peer != original_peer:
		_fail("returning from results did not keep the same LAN room"); return
	if role == "client":
		await get_tree().create_timer(0.4).timeout
		if lobby._can_submit_ready() or not lobby.start_btn.disabled or lobby.waiting_ui.status.text != Locale.t("wait.opponent_viewing_results"):
			_fail("preparation reopened before the opponent returned from results"); return
		if not screenshot_path.is_empty():
			await RenderingServer.frame_post_draw
			var evidence := screenshot_path.get_base_dir().path_join("lan-awaiting-rematch.png")
			if get_viewport().get_texture().get_image().save_png(evidence) != OK:
				_fail("could not capture the waiting room before a rematch"); return
	ready_sent = false
	complete = false


func _exercise_results_departure(result: Control, original_peer: MultiplayerPeer) -> void:
	var guest_leaves_first := results_departure_order != "host-returns"
	var guest_link_lost := results_departure_order == "guest-link-lost"
	if role == "client" and guest_link_lost:
		await _exercise_results_link_loss(result)
		return
	if role == "host" and guest_leaves_first:
		var gate := FileAccess.open(results_host_ready, FileAccess.WRITE)
		gate.close()
		while NetworkManager.opponent_peer_id != 0:
			await get_tree().process_frame
		if not result.visible:
			_fail("the guest leaving dismissed the host's results"); return
	var label := Locale.t("result.back_room" if role == "host" else "result.back_menu")
	var exit_button: Button
	for button in result.find_children("*", "Button", true, false):
		if button.text == label:
			exit_button = button
			break
	if exit_button == null:
		_fail("the result is missing the requested exit"); return
	if role == "host" and guest_leaves_first:
		var room_notice := result.find_child("RoomNotice", true, false) as Label
		if not room_notice or not room_notice.is_visible_in_tree() or room_notice.text != Locale.t("result.lan_guest_left"):
			_fail("the result did not explain the available room"); return
	if role == "host" and guest_leaves_first and not screenshot_path.is_empty():
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("lan-results-after-guest-leaves.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the host's results after the guest left"); return
	if role == "client":
		if guest_leaves_first:
			while not FileAccess.file_exists(results_host_ready):
				await get_tree().process_frame
		else:
			while not NetworkManager._lan_opponent_returned:
				await get_tree().process_frame
		exit_button.pressed.emit()
		await get_tree().scene_changed
		if get_tree().current_scene.scene_file_path != "res://MainMenu.tscn" or NetworkManager.is_online:
			_fail("leaving results did not close the guest connection"); return
		print("TEST_ROOM_RESULTS_GUEST_LEFT")
		get_tree().quit(0)
		return
	exit_button.pressed.emit()
	await get_tree().scene_changed
	lobby = get_tree().current_scene
	while NetworkManager.opponent_peer_id != 0:
		await get_tree().process_frame
	if lobby.scene_file_path != "res://DirectLobby.tscn" or NetworkManager.peer != original_peer or not NetworkManager.has_live_lan_room():
		_fail("the host lost the room after the guest left results"); return
	var deadline := Time.get_ticks_msec() + 2500
	while lobby.waiting_ui.status.text != Locale.t("wait.lan_guest_left") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not lobby.start_btn.disabled or lobby.waiting_ui.status.text != Locale.t("wait.lan_guest_left"):
		_fail("the retained room did not explain the vacancy or kept preparation enabled"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("lan-results-vacancy.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the retained room"); return
	cancellation_verified = false
	ready_sent = false
	complete = false
	print("TEST_ROOM_RESULTS_HOST_RETAINED")


func _exercise_results_link_loss(result: Control) -> void:
	while not FileAccess.file_exists(results_host_ready):
		await get_tree().process_frame
	print("TEST_ROOM_RESULTS_CUT_READY")
	await NetworkManager.opponent_disconnected
	await get_tree().process_frame
	if not result.is_visible_in_tree() or NetworkManager.is_online:
		_fail("a lost connection replaced the guest's finished result or left them online"); return
	var notice := result.find_child("RoomNotice", true, false) as Label
	if not notice or not notice.is_visible_in_tree() or notice.text != Locale.t("result.lan_guest_connection_lost"):
		_fail("the guest's result changed its exit without explaining the lost connection"); return
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var evidence := screenshot_path.get_base_dir().path_join("lan-results-guest-link-lost.png")
		if get_viewport().get_texture().get_image().save_png(evidence) != OK:
			_fail("could not capture the guest's result after losing the link"); return
	for button in result.find_children("*", "Button", true, false):
		if button.text == Locale.t("result.back_multiplayer"):
			button.pressed.emit()
			await get_tree().scene_changed
			await get_tree().process_frame
			var page := get_tree().current_scene
			var choices := page.get_node_or_null("OnlineModePopup") as CanvasLayer
			if page.scene_file_path != "res://MainMenu.tscn" or not choices or not choices.visible:
				_fail("the disconnected guest could not return to multiplayer"); return
			var lan_button: Button
			for mode in choices.find_children("*", "Button", true, false):
				if mode.text == Locale.t("mp.direct"):
					lan_button = mode
					break
			if lan_button == null:
				_fail("multiplayer did not offer LAN after the guest disconnected"); return
			lan_button.pressed.emit()
			await get_tree().scene_changed
			await get_tree().process_frame
			var retry := get_tree().current_scene
			if retry.scene_file_path != "res://DirectLobby.tscn" or retry.ip_input.text != joined_endpoint or not retry.ip_input.has_focus() or retry.join_btn.disabled or NetworkManager.is_online:
				_fail("the disconnected guest could not retry their original address and port"); return
			print("TEST_ROOM_RESULTS_GUEST_LINK_LOST")
			get_tree().quit(0)
			return
	_fail("the disconnected guest's result did not offer multiplayer")


func _disconnected(_player: int) -> void:
	if test_lan_protocol_mismatch and not complete:
		return
	if waiting_for_editor_link_loss:
		return
	if not results_departure_order.is_empty() and role == "host":
		var page := get_tree().current_scene
		if page == lobby or (first_match_id != "" and page.scene_file_path == "res://Main.tscn" and page.battle_finished):
			return
	if results_departure_order == "guest-link-lost" and role == "client" and not first_match_id.is_empty():
		return
	if editing_side.ends_with("-leaves") and get_tree().current_scene.scene_file_path == "res://CardEditor.tscn":
		return
	if role!="client" or not complete: _fail("connection lost before preparation finished");return
	await get_tree().process_frame
	if NetworkManager._reconnect_active or NetworkManager.has_resumable_match_session(): _fail("withdrawn reconnect started after disconnect");return
	print("TEST_ROOM_DISCONNECT_NO_RECONNECT_OK")
	var battle := get_tree().current_scene
	var result := battle.get_node_or_null("CanvasLayer/BattleResultLayer")
	if not battle.battle_finished or result == null or not battle.end_turn_button.disabled:
		_fail("disconnect did not end the active battle"); return
	var body := result.find_child("BodyLabel", true, false) as Label
	if body == null or body.text != Locale.t("result.connection_lost_body"):
		_fail("disconnect result did not explain the lost direct connection"); return
	var back: Button
	for button in result.find_children("*", "Button", true, false):
		if button.text == Locale.t("result.back_multiplayer"):
			back = button
			break
	if back == null: _fail("disconnect result does not offer multiplayer"); return
	if not screenshot_path.is_empty():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
			_fail("could not save disconnect result screenshot"); return
	back.pressed.emit()
	await get_tree().scene_changed
	await get_tree().process_frame
	var page := get_tree().current_scene
	var choices := page.get_node_or_null("OnlineModePopup")
	if page.scene_file_path != "res://MainMenu.tscn" or choices == null or not choices.visible or not NetworkManager.session_mode.is_empty():
		_fail("return to multiplayer did not reopen the online choices and clear the old session"); return
	print("TEST_ROOM_DISCONNECT_BACK_TO_MULTIPLAYER_OK")
	get_tree().quit(0)
func _fail(message: String) -> void:
	push_error("TEST_ROOM_INTEGRATION_FAILED: "+role+": "+message)
	get_tree().quit(1)
