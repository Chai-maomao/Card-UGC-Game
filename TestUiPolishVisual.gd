extends Node
var stage: SubViewport
var failures: Array[String]=[]
var hovered := 0
var rooms_only := false
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _ready() -> void:
	rooms_only=OS.get_cmdline_user_args().has("--room-only")
	NetworkManager.close_connection()
	PlayerData.skill_tutorial_active=false
	PlayerData.editing_skill_index=0
	stage=SubViewport.new()
	stage.gui_embed_subwindows=true
	stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(stage)
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		stage.size=dimensions
		for scene in ([] if rooms_only else ["MainMenu","SettingsMenu","CardEditor","SkillEditor","BattleDeckSelect","MyCards"]):
			PlayerData.card_draft={"card_type":"minion","name":"守卫","cost":2,"hp":3,"atk":2,"skill1":{},"skill2":{}}
			PlayerData.battle_select_mode="practice"
			var page=load("res://"+scene+".tscn").instantiate()
			stage.add_child(page)
			await get_tree().create_timer(0.35).timeout
			var buttons=page.find_children("*","Button",true,false)
			var selected: Array=[]
			for i in range(buttons.size()):
				if i<10 or i>=buttons.size()-8 or buttons[i].text=="条件": selected.append(buttons[i])
			for button in selected:
				if button.disabled or not button.is_visible_in_tree(): continue
				var ancestor=button.get_parent()
				while ancestor!=null:
					if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
					ancestor=ancestor.get_parent()
				await frames()
				var clip:=bounds(button)
				if not clip.grow(1).encloses(button.get_global_rect()): continue
				var motion:=InputEventMouseMotion.new()
				motion.position=button.get_global_rect().get_center()
				stage.push_input(motion,true)
				await get_tree().create_timer(0.15).timeout
				if not button.is_hovered(): continue
				hovered+=1
				_check(bounds(button).grow(0.8).encloses(button.get_global_rect()),scene+" hovered button clips: "+button.text)
			await capture("hover-"+scene+"-%d.png"%dimensions.x)
			if scene=="MainMenu":
				page._on_online_pressed()
				await get_tree().create_timer(0.25).timeout
				var popup=page.get_node_or_null("OnlineModePopup")
				_check(popup!=null,"online choices must open over the main menu")
				_check(popup.find_children("*","Button",true,false).size()==3,"online popup has server, LAN and back only")
				await capture("online-popup-%d.png"%dimensions.x)
			page.free()
			await frames()
	if not rooms_only: _check(hovered>30,"hover checks must exercise real enabled buttons")
	for type in ([] if rooms_only else ["minion","parasite","spell"]):
		PlayerData.card_draft={"card_type":type,"name":"守卫","cost":2,"hp":3,"atk":2,"skill1":{},"skill2":{}}
		var editor=load("res://SkillEditor.tscn").instantiate()
		stage.add_child(editor)
		await get_tree().create_timer(0.2).timeout
		_check(editor.skill_name_input.placeholder_text.is_empty(),"skill names have no test-card placeholder")
		if type=="parasite":
			for trigger in ["on_attack","on_damaged","on_death"]:
				editor.current_trigger_key=trigger
				editor._update_trigger_preview()
				_check(editor.trigger_preview_label.text.contains("宿主"),"parasite trigger must name its host: "+trigger)
			await capture("parasite-trigger-description.png")
		elif type=="minion": _check(not editor.trigger_preview_label.text.contains("宿主"),"unit trigger describes the unit")
		else: _check(editor.trigger_preview_label.text.contains("法术"),"spell trigger describes casting")
		editor.free()
		await frames()
	for dimensions in ([] if rooms_only else [Vector2i(1280,720),Vector2i(960,540)]):
		stage.size=dimensions
		PlayerData.begin_skill_tutorial()
		var tutorial=load("res://SkillEditor.tscn").instantiate()
		stage.add_child(tutorial)
		await get_tree().create_timer(0.4).timeout
		var guide=tutorial.skill_tutorial_controller
		guide.navigate_on_complete=false
		guide.set_phase(SkillEditorTutorialController.Phase.TRIGGER)
		await get_tree().create_timer(0.4).timeout
		var target=guide._trigger_button()
		var frame=guide.focus_frames[0]
		_check(frame.visible and frame.get_global_rect().position.distance_to(target.get_global_rect().position)<1 and frame.size.distance_to(target.get_global_rect().size)<1,"tutorial outline matches real palette block")
		await capture("tutorial-highlight-%d.png"%dimensions.x)
		tutorial.free()
		PlayerData.cancel_skill_tutorial()
		await frames()
	NetworkManager.set_process(false)
	var previous_decks := PlayerData.deck_library
	var previous_deck_id := PlayerData.current_deck_id
	var starter := CardDatabase.beginner_deck()
	var saved_room_decks := [
		{"id": "room-first", "name": "练习卡组", "cards": starter},
		{"id": "room-preferred", "name": "常用卡组", "cards": starter.map(func(card): return card.duplicate_card())},
	]
	PlayerData.deck_library = saved_room_decks
	for scene in ["DedicatedLobby","DirectLobby"]:
		PlayerData.current_deck_id = "room-preferred"
		PlayerData.prepare_online_selection("res://%s.tscn" % scene)
		var lobby=load("res://"+scene+".tscn").instantiate()
		stage.add_child(lobby)
		await frames()
		if scene=="DedicatedLobby":
			lobby._pending_room_code="92396148"
			var settings: Button = lobby.find_child("ServerSettingsButton", true, false)
			_check(not lobby.server_input.visible and lobby.room_input.visible, "room code is the default online entry")
			await capture("ServerRoomEntry.png")
			settings.button_pressed = true
			await frames()
			_check(lobby.server_input.visible and lobby.check_server_btn.visible, "server settings reveals address and connection check")
			await capture("ServerRoomSettings.png")
			settings.button_pressed = false
			lobby.server_input.text = "127.0.0.1"
			lobby.lobby_port = 1
			lobby.room_input.text = "RETRY123"
			lobby.join_btn.pressed.emit()
			await capture("ServerRoomConnecting.png")
			lobby.back_btn.pressed.emit()
			await frames()
			_check(lobby.room_input.text == "RETRY123" and lobby.room_input.editable and not lobby.join_btn.disabled, "cancelled connection keeps room code and restores the entry")
			await capture("ServerRoomCancelled.png")
		var transport:=BetaRelayPeer.new()
		transport.setup(NetworkManager,"http://127.0.0.1:1","A1B2C3D4","a".repeat(64),2,"b".repeat(32))
		transport._next_poll=9223372036854775807
		NetworkManager.peer=transport
		NetworkManager.multiplayer.multiplayer_peer=transport
		NetworkManager.is_online=true
		NetworkManager.player_number=2
		NetworkManager.opponent_peer_id=1
		lobby._show_waiting_room()
		await get_tree().create_timer(0.2).timeout
		_check(lobby.start_btn.disabled,"connecting room must not submit readiness")
		transport._status=MultiplayerPeer.CONNECTION_CONNECTED
		transport.peer_connected.emit(1)
		if scene=="DirectLobby":
			NetworkManager._direct_protocol_verified=true
			lobby._on_opponent_joined()
		else:
			NetworkManager.notify_room_ready()
		await get_tree().create_timer(0.2).timeout
		_check(not lobby.start_btn.disabled,"connected room enables ready: %s online=%s opponent=%s peers=%s"%[scene,NetworkManager.is_online,NetworkManager.opponent_peer_id,NetworkManager.multiplayer.get_peers()])
		var choice: OptionButton = lobby.waiting_ui.deck_choice
		_check(choice.get_selected_metadata() == "room-preferred" and PlayerData.battle_deck == saved_room_decks[1].cards, "room must preselect the current playable library deck")
		if scene == "DedicatedLobby":
			var share := lobby.waiting_ui.find_child("CopyRoomCodeButton", true, false) as Button
			_check(share != null, "the server room offers its room code to copy")
			if share != null and DisplayServer.get_name() != "headless":
				var before := DisplayServer.clipboard_get()
				share.pressed.emit()
				var copied := DisplayServer.clipboard_get()
				_check(copied == lobby._pending_room_code and share.text == Locale.t("wait.room_code_copied", [copied]), "copying a server room code puts the exact code on the clipboard and keeps it visible")
				await get_tree().create_timer(0.35).timeout
				DisplayServer.clipboard_set(before)
			choice.item_selected.emit(0)
			_check(choice.get_selected_metadata() == "room-first", "choosing a deck must update the visible selection")
			saved_room_decks[0].cards.append(starter[0].duplicate_card())
			lobby._show_waiting_room()
			await frames()
			choice = lobby.waiting_ui.deck_choice
			_check(choice.get_selected_metadata() == "room-first" and PlayerData.battle_deck == saved_room_decks[0].cards, "reopening the room must refresh the chosen deck from the library")
			PlayerData.deck_library = [{"id": "room-empty", "name": "空卡组", "cards": []}]
			lobby._show_waiting_room()
			await frames()
			_check(lobby.start_btn.disabled and lobby.waiting_ui.deck_choice.disabled and lobby.waiting_ui.status.text == Locale.t("wait.need_room_card"), "an empty library deck must explain how to get a playable deck")
			await capture("RoomNeedsCard.png")
			PlayerData.deck_library = saved_room_decks
			PlayerData.current_deck_id = "room-empty"
			lobby._show_waiting_room()
			await frames()
			_check(lobby.waiting_ui.deck_choice.get_selected_metadata() == "room-first" and not lobby.start_btn.disabled, "a missing current deck must fall back to the first playable deck")
			lobby.waiting_ui.find_child("ExitButton", true, false).pressed.emit()
			await frames()
			var leave := lobby.waiting_ui.get_node_or_null("LeaveRoomConfirmation") as ConfirmationDialog
			_check(leave != null and leave.visible, "leaving a connected room requires confirmation")
			if leave != null:
				_check(leave.get_ok_button().text == Locale.t("wait.leave_room") and leave.get_cancel_button().has_focus(), "leave dialog names the action and defaults focus to cancel")
				_check(leave.get_cancel_button().position.x < leave.get_ok_button().position.x, "the cancel action belongs on the left, as in the battle forfeit confirmation")
				await capture("ServerRoomLeaveConfirm.png")
				leave.get_cancel_button().pressed.emit()
				await frames()
			_check(NetworkManager.peer == transport and lobby.waiting_ui.visible, "cancelling departure keeps the room and transport intact")
		lobby._on_rpc_ready(PlayerData.battle_deck.map(func(card): return PlayerData.serialize_card(card)))
		await get_tree().create_timer(0.15).timeout
		_check(not lobby.waiting_ui.sidebar.get_node("ViewOpponentDeck").disabled,"opponent deck becomes available after submission")
		lobby.i_am_ready = true
		lobby._check_both_ready()
		var progress := lobby.waiting_ui.find_child("CardArtProgress", true, false) as ProgressBar
		await get_tree().create_timer(0.15).timeout
		_check(progress != null and not progress.visible, "waiting for manifests must not show a transfer progress bar")
		lobby._on_card_art_manifest(2)
		for art_index in [0, 1, 2, 2]:
			lobby._on_card_art_ack(art_index, 5)
		stage.size = Vector2i(1280, 720)
		await get_tree().create_timer(0.2).timeout
		_check(progress.visible and not progress.indeterminate and not progress.show_percentage and progress.value == 3 and progress.max_value == 7,
			"the room must show progress across upload and receipt, without a count label")
		_check(not lobby.waiting_ui.status.visible and progress.size.y <= 10.0, "the progress track must replace the status text and stay slim")
		var loading := lobby.waiting_ui.find_child("CardArtLoading", true, false) as Label
		_check(loading.visible and loading.text == Locale.t("wait.art_loading") + "......", "art transfer must show a six-dot loading label")
		_check(is_equal_approx(progress.position.x, 0.0) and loading.position.x >= progress.position.x + progress.size.x,
			"the progress bar must be left aligned with the label on its right")
		var initial_track := progress.get_global_rect()
		var counts: Array[int] = []
		var deadline := Time.get_ticks_msec() + 3500
		while counts.size() < 8 and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			var dot_count := loading.visible_characters - Locale.t("wait.art_loading").length()
			if (counts.is_empty() and dot_count == 0) or (not counts.is_empty() and counts.back() != dot_count):
				counts.append(dot_count)
				_check(progress.get_global_rect().is_equal_approx(initial_track), "the dots must not move the progress bar")
				if dot_count == 6:
					await capture("CardArtProgress-%s.png" % scene)
		_check(counts == [0, 1, 2, 3, 4, 5, 6, 0], "loading dots must appear individually and then clear together")
		lobby._on_card_art_ack(3, 5)
		lobby._on_card_art_ack(4, 5)
		await get_tree().create_timer(0.15).timeout
		_check(progress.visible and loading.visible and progress.value == 5, "the progress bar must remain visible while art is still being received")
		lobby._opponent_arts_received = 2
		await get_tree().create_timer(0.15).timeout
		_check(not progress.visible and not loading.visible, "completing both transfers must hide the loading indicator")
		lobby.i_am_ready = false
		lobby._art_wait_deadline = 0.0
		await get_tree().create_timer(0.15).timeout
		_check(not progress.visible and not loading.visible and lobby.waiting_ui.status.visible, "leaving art sync must restore the normal room status")
		lobby.waiting_ui.grid.find_child("InspectRoomCard",true,false).pressed.emit()
		await frames()
		var inspectors=lobby.waiting_ui.find_children("TabletopCardInspector","PanelContainer",true,false)
		_check(inspectors.size()==1 and inspectors[0].visible,"room cards open read-only details")
		if inspectors.size() == 1:
			var inspector: PanelContainer = inspectors[0]
			var abilities := inspector.find_child("CardAbilitiesFrame", true, false) as PanelContainer
			_check(abilities != null and abilities.is_visible_in_tree(), "room card details must show the shared abilities section")
			await capture("RoomCardInspector-%s.png" % scene)
			var close_button := inspector.find_children("*", "Button", true, false).front() as Button
			close_button.pressed.emit()
			await frames()
			_check(not is_instance_valid(inspector), "the close action must dismiss room card details")
		var dialogs=[]
		if not dialogs.is_empty(): dialogs[0].queue_free()
		await frames()
		lobby.waiting_ui.find_child("RoomRulesButton",true,false).pressed.emit()
		await frames()
		dialogs=lobby.waiting_ui.find_children("*","AcceptDialog",true,false)
		_check(dialogs.size()==1 and dialogs[0].visible,"room rules button opens the actual configured rules")
		if not dialogs.is_empty(): dialogs[0].queue_free()
		await frames()
		for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
			stage.size=dimensions
			await get_tree().create_timer(0.3).timeout
			_check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(lobby.start_btn.get_global_rect()),"room ready button fits")
			await capture(scene+"-%d.png"%dimensions.x)
		lobby.free()
		NetworkManager.close_connection()
		await frames()
	PlayerData.deck_library = previous_decks
	PlayerData.current_deck_id = previous_deck_id
	PlayerData.online_room_deck_id = ""
	_check(not NetworkManager.begin_saved_match_reconnect() and not NetworkManager.has_resumable_match_session(),"recovery entry is withdrawn")
	var exit_lobby=load("res://DedicatedLobby.tscn").instantiate()
	get_tree().root.add_child(exit_lobby)
	get_tree().current_scene=exit_lobby
	exit_lobby._show_waiting_room()
	exit_lobby.waiting_ui.find_child("ExitButton",true,false).pressed.emit()
	await get_tree().create_timer(1.2).timeout
	_check(get_tree().current_scene.scene_file_path=="res://DedicatedLobby.tscn","room back must return to the room entry page")
	_check(not NetworkManager.is_online and NetworkManager.room_code.is_empty(),"room exit closes connection and clears room identity")
	_check(get_tree().current_scene.get_node_or_null("OnlineModePopup")==null,"room exit does not reopen online choices")
	get_tree().current_scene.queue_free()
	get_tree().current_scene=self
	await frames()
	if failures.is_empty(): print("TEST_UI_POLISH_VISUAL_OK hovered=",hovered);get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_UI_POLISH_VISUAL_FAILED: "+failure)
		get_tree().quit(1)
func frames() -> void:
	for i in range(4): await get_tree().process_frame
func bounds(button: Control) -> Rect2:
	var result:=Rect2(Vector2.ZERO,Vector2(stage.size))
	var parent=button.get_parent()
	while parent!=null:
		if parent is Control and parent.clip_contents:
			result=result.intersection(parent.get_global_rect())
		if parent is ScrollContainer:
			var scroll_rect: Rect2=parent.get_global_rect()
			if parent.get_v_scroll_bar().visible: scroll_rect.size.x-=parent.get_v_scroll_bar().size.x
			if parent.get_h_scroll_bar().visible: scroll_rect.size.y-=parent.get_h_scroll_bar().size.y
			result=result.intersection(scroll_rect)
		parent=parent.get_parent()
	return result
func capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	stage.get_texture().get_image().save_png("res://artifacts/room-polish-20261114/"+file)
func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
