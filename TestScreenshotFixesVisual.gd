extends Node
var stage: SubViewport
var failures: Array[String] = []
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _ready() -> void:
	Locale.language = "zh"
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.skill_tutorial_active = false
	GamePreferences.set_battle_playback_speed(GamePreferences.PlaybackSpeed.FAST)
	stage = SubViewport.new()
	stage.size = Vector2i(1280,720)
	stage.gui_embed_subwindows = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	PlayerData.configure_card_playtest(CardData.new("待测卡",1,4,2))
	var battle = preload("res://Main.tscn").instantiate()
	stage.add_child(battle)
	await get_tree().create_timer(1.3).timeout
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		stage.size = dimensions
		battle.game.turn_number = 2
		battle.game.player_field.slots.fill(null)
		battle.game.player2_field.slots.fill(null)
		battle.game.player_field.slots[0] = CardData.new("攻击者",1,5,2)
		battle.game.player2_field.slots[1] = CardData.new("目标",1,6,1)
		battle.game.player_field.action_points = 10
		battle.update_entire_screen()
		await get_tree().create_timer(0.4).timeout
		var original := BattleRepro.state_hash(battle.game)
		battle._on_attack_requested(0)
		move(battle.enemy_side_ui.get_child(1).get_global_rect().get_center())
		await get_tree().create_timer(0.25).timeout
		var face = battle.tabletop.cards[6].face
		check(int(face.prediction.get("hp",0)) == -2,"target hover must preview actual attack damage")
		check(BattleRepro.state_hash(battle.game) == original,"hover preview must preserve the live state and RNG")
		await capture("prediction-%d"%dimensions.x)
		battle.cancel_attack()
		move(Vector2(2,2))
		await get_tree().process_frame
		check(face.prediction.is_empty(),"leaving targeting must clear the prediction")
		if dimensions.x == 1280:
			var actor: CardData = battle.game.player_field.slots[0]
			actor.skills = [{"trigger":"on_activate","effects":[{"effect":"add_buff","buff_id":"atk_boost","value":1,"duration":2,"target":"target_single","target_side":"ally"}]}]
			battle.update_entire_screen()
			await get_tree().create_timer(0.1).timeout
			var before_buff := BattleRepro.state_hash(battle.game)
			battle._on_skill_activated(0,0)
			move(battle.player_side_ui.get_child(0).get_global_rect().get_center())
			await get_tree().create_timer(0.15).timeout
			var buff_face = battle.tabletop.cards[0].face
			check(int(buff_face.prediction.get("atk",0))==1 and int(buff_face.prediction.get("effects",0))==1,"targeted buff preview shows the actual attack and status gain")
			check(BattleRepro.state_hash(battle.game)==before_buff,"buff prediction preserves live state and RNG")
			await capture("buff-prediction")
			battle.cancel_attack()
			actor.skills = []
			var spell := PracticeChallenges._spell("法术预览","damage",2,"target_single","enemy",1)
			battle._my_hand().append(spell)
			battle._refresh_hand_ui()
			await get_tree().create_timer(0.15).timeout
			var before_spell := BattleRepro.state_hash(battle.game)
			battle._start_spell_cast_from_hand(battle._my_hand().size()-1,0)
			move(battle.enemy_side_ui.get_child(1).get_global_rect().get_center())
			await get_tree().create_timer(0.15).timeout
			var spell_face = battle.tabletop.cards[6].face
			check(int(spell_face.prediction.get("hp",0))==-2,"targeted spell preview shows actual damage")
			check(BattleRepro.state_hash(battle.game)==before_spell,"spell prediction preserves live state and RNG")
			battle.cancel_attack()
		var button: Button = battle.find_child("AddTestCard",true,false)
		check(button != null and not button.disabled,"test mode offers an add-card button")
		var count: int = battle._my_hand().size()
		click(button.get_global_rect().get_center())
		await get_tree().create_timer(0.15).timeout
		check(battle._my_hand().size() == count+1 and battle._my_hand().back().card_name == "待测卡","add-card button adds the actual specimen to the active hand")
		while battle._my_hand().size() < SkillEngine.MAX_HAND_SIZE: battle._my_hand().append(CardData.new("Full",0,1,0))
		battle.update_entire_screen()
		await get_tree().process_frame
		check(button.disabled,"full hand must disable specimen injection")
		click(button.get_global_rect().get_center())
		await get_tree().process_frame
		check(battle._my_hand().size() == SkillEngine.MAX_HAND_SIZE,"full-hand click must not overfill")
		battle._show_splash(battle.game.player_field.slots[0],"发动技能")
		await get_tree().create_timer(0.25).timeout
		check(battle.splash_panel.card_view.visible,"opaque artwork uses the complete card for the skill reveal")
		await capture("skill-reveal-%d"%dimensions.x)
		battle._my_hand().resize(2)
		battle._refresh_hand_ui()
	battle.game.current_player = 1
	battle.game.turn_number = 2
	battle.game.player_field.slots = [CardData.new("A",1,3,2),CardData.new("B",1,3,4),null,null,null]
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.current_mana = 4
	battle.game.player_field.action_points = 0
	battle.game.player_field.actions_taken = 1
	battle.update_entire_screen()
	await get_tree().create_timer(0.3).timeout
	check(not battle.face_mana_button.button_pressed,"Elixir supplement starts off")
	await battle._on_end_turn_pressed()
	await get_tree().create_timer(0.3).timeout
	check(battle.find_children("*","AcceptDialog",true,false).is_empty(),"ending the turn must not open a supplement dialog")
	check(battle.game.current_player==2 and battle.game.player_field.current_mana==4 and battle.game.player2_field.player_hp==30,"off must finish the turn without Elixir-funded hero attacks")
	battle.game.current_player = 1
	battle.game.turn_number = 3
	battle.game.player_field.slots = [CardData.new("A",1,3,2),CardData.new("B",1,3,4),null,null,null]
	battle.game.player_field.current_mana = 4
	battle.game.player_field.action_points = 0
	battle.game.player_field.actions_taken = 1
	battle.update_entire_screen()
	await get_tree().create_timer(0.4).timeout
	click(battle.face_mana_button.get_global_rect().get_center())
	move(Vector2(3,3))
	await get_tree().create_timer(0.15).timeout
	check(battle.face_mana_button.button_pressed,"supplement remains pressed after pointer leaves")
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		stage.size = dimensions
		await get_tree().create_timer(0.25).timeout
		check(battle.face_mana_button.get_global_rect().intersects(battle.end_turn_button.get_global_rect())==false,"middle-bar buttons must not overlap")
		await capture("elixir-toggle-%d"%dimensions.x)
	await battle._on_end_turn_pressed()
	await get_tree().create_timer(0.3).timeout
	check(battle.game.current_player==2 and battle.game.player_field.current_mana==1 and battle.game.player2_field.player_hp==24,"enabled supplement funds the actual automatic attacks")
	check(not battle.face_mana_button.button_pressed,"turn end releases the supplement toggle")
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.slots[0] = CardData.new("Opponent end skill",0,3,1,[{"trigger":"on_turn_end","effects":[{"effect":"gain_mana","target":"self","value":1}]}])
	battle.update_entire_screen()
	await get_tree().create_timer(0.4).timeout
	await battle._on_end_turn_pressed()
	check(battle.find_children("*","AcceptDialog",true,false).is_empty(),"empty hotseat side must end without a popup even with conditional effects")
	PlayerData.practice_challenge_id = PracticeChallenges.IDS[0]
	battle._show_help_popup(true)
	await get_tree().create_timer(0.15).timeout
	var info = battle.find_child("BattleFieldRules",true,false)
	check(info.find_children("*","CardUI",true,false).is_empty(),"challenge info must not list the collection")
	var challenge_tab: Button
	for button in info.find_children("*","Button",true,false):
		if button.text == "挑战目标": challenge_tab=button
	check(challenge_tab != null,"challenge replaces the card tab with its objective")
	if challenge_tab != null: challenge_tab.pressed.emit()
	await capture("challenge-objective")
	info.queue_free()
	PlayerData.practice_challenge_id = ""
	battle.free()
	await get_tree().process_frame
	# Check actual tutorial review/save placement against the visible right pane.
	PlayerData.begin_skill_tutorial()
	var editor = preload("res://SkillEditor.tscn").instantiate()
	stage.add_child(editor)
	await get_tree().create_timer(0.3).timeout
	var guide = editor.skill_tutorial_controller
	guide.navigate_on_complete = false
	editor.skill_name_input.text = "补给"
	editor.current_trigger_key = "on_summon"
	editor.effect_data = [{"effect":"draw_cards","target":"self","value":1}]
	for phase in [guide.Phase.REVIEW,guide.Phase.SAVE]:
		guide.set_phase(phase)
		await get_tree().create_timer(0.25).timeout
		check(not guide.instruction_panel.get_global_rect().intersects(editor.workbench.inspector.get_global_rect()),"tutorial must leave the right-side inspector visible")
		await capture("skill-guide-%d"%phase)
	editor.queue_free()
	await get_tree().process_frame
	PlayerData.cancel_skill_tutorial()
	await _other_surfaces()
	await _return_routes()
	if failures.is_empty(): print("TEST_SCREENSHOT_FIXES_VISUAL_OK");get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)
func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	stage.push_input(event,true)
func click(point: Vector2) -> void:
	move(point)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		stage.push_input(event,true)
func capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	stage.get_texture().get_image().save_png("res://artifacts/screenshot-fixes-20261114/"+file+".png")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _other_surfaces() -> void:
	var history = preload("res://MatchHistory.tscn").instantiate()
	stage.add_child(history)
	await get_tree().create_timer(0.25).timeout
	for label in history.find_children("*","Label",true,false):
		if label.text == Locale.t("history.title"):
			check(absf(label.get_global_rect().get_center().x-stage.size.x*0.5)<1.0,"history heading must be centered on the page")
	await capture("history-centered")
	history.queue_free()
	await get_tree().process_frame
	PlayerData.card_draft = {"card_type":"minion","name":"卡牌预览","hp":4,"atk":2,"cost":2}
	var editor = preload("res://CardEditor.tscn").instantiate()
	stage.add_child(editor)
	await get_tree().create_timer(0.3).timeout
	check(editor._preview_damaged.text == "预览受伤","damaged preview control must identify itself as a preview")
	var popup = editor._open_balance_simulation(CardData.new("候选",1,1,1),false)
	await get_tree().create_timer(0.25).timeout
	var note = popup.find_child("SimulationNote",true,false)
	check(note.visible and note.text.contains("100"),"strength scoring explanation must be visible")
	await capture("strength-explanation")
	wheel(Vector2(3,3))
	await get_tree().process_frame
	check(is_instance_valid(popup) and not popup.is_queued_for_deletion(),"wheel outside the score popup must not dismiss it")
	click(Vector2(3,3))
	await get_tree().process_frame
	check(not is_instance_valid(popup),"left click outside still dismisses the score popup")
	PlayerData.card_draft["skill1"] = {"skill_name":"补给","trigger":"on_summon","effects":[{"effect":"draw_cards","target":"self","value":1}]}
	editor._update_skill_labels()
	var card_guide := CardEditorTutorialController.new()
	editor.add_child(card_guide)
	card_guide.start(editor)
	card_guide.navigate_on_complete = false
	card_guide.set_phase(CardEditorTutorialController.Phase.REVIEW)
	await get_tree().create_timer(0.25).timeout
	check(not card_guide.instruction_panel.get_global_rect().intersects(editor.card_preview_panel.get_global_rect()),"card tutorial review must leave the preview and damaged-art switch visible")
	check(not card_guide.instruction_panel.get_global_rect().intersects(editor.skill1_summary.get_global_rect()),"card tutorial review must leave the skill summary visible")
	await capture("card-guide-review")
	editor.queue_free()
	await get_tree().process_frame
	PlayerData.card_draft = {"card_type":"spell","name":"法术预览","cost":2,"damaged_art_path":CardArtwork.DAMAGED}
	var spell_editor = preload("res://CardEditor.tscn").instantiate()
	stage.add_child(spell_editor)
	await get_tree().create_timer(0.3).timeout
	check(spell_editor._preview_damaged == null and spell_editor._damaged_art_browse == null,"spell editor must not offer damaged art or wounded preview")
	await capture("spell-no-damaged-art")
	spell_editor.queue_free()
	await get_tree().process_frame
	PlayerData.battle_deck = CardDatabase.beginner_deck()
	var lobby = preload("res://DedicatedLobby.tscn").instantiate()
	stage.add_child(lobby)
	await get_tree().process_frame
	var transport := BetaRelayPeer.new()
	var room_code := "A1B2C3D4"
	transport.setup(NetworkManager, "http://127.0.0.1:1", room_code, "a".repeat(64), 2, "b".repeat(32))
	transport._next_poll = 9223372036854775807
	NetworkManager.peer = transport
	NetworkManager.multiplayer.multiplayer_peer = transport
	NetworkManager.is_dedicated_server = true
	NetworkManager.session_mode = NetworkManager.SESSION_MODE_ROOM
	NetworkManager.player_number = 1
	NetworkManager.room_code = room_code
	transport._status = MultiplayerPeer.CONNECTION_CONNECTED
	transport.peer_connected.emit(1)
	lobby._show_waiting_room()
	NetworkManager.notify_room_ready()
	await get_tree().create_timer(0.25).timeout
	var room = lobby.waiting_ui
	room.grid.find_child("InspectRoomCard",true,false).pressed.emit()
	await get_tree().create_timer(0.15).timeout
	check(room.find_child("TabletopCardInspector",true,false) != null,"room uses a compact card inspector")
	await capture("room-card-inspector")
	var inspector = room.find_child("TabletopCardInspector",true,false)
	inspector.get_parent().queue_free()
	await get_tree().process_frame
	room._show_rules()
	await get_tree().create_timer(0.15).timeout
	var rules = room.get_node_or_null("AdvancedSettings")
	check(rules != null,"host may edit rules using the same popup as solo preparation")
	if rules != null:
		for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
			stage.size = dimensions
			await get_tree().create_timer(0.2).timeout
			var scroll = rules.find_children("*","ScrollContainer",true,false)[0]
			check(scroll.get_v_scroll_bar().size.x<16,"room rules must retain Godot's narrow default scrollbar")
			var toggle = rules.find_child("ActionEnabledToggle",true,false)
			check(toggle.get_global_rect().size.x<120,"action toggle must not stretch across the whole row")
			await capture("room-rules-editor-%d" % dimensions.x)
			wheel(scroll.get_global_rect().get_center())
			await get_tree().process_frame
			check(scroll.scroll_vertical>0,"real wheel input must scroll the rule form")
			scroll.scroll_vertical = 0
		var scroll := rules.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		var first_toggle := rules.find_child("ActionEnabledToggle", true, false) as Control
		var mana := rules.find_child("second_extra_mana", true, false) as SpinBox
		var mana_input := mana.get_line_edit()
		first_toggle.grab_focus()
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		for _step in range(32):
			if mana_input.has_focus():
				break
			tab.pressed = true
			stage.push_input(tab, true)
			tab.pressed = false
			stage.push_input(tab, true)
			await get_tree().process_frame
		await get_tree().process_frame
		check(mana_input.has_focus(), "Tab must reach the lower rule inputs")
		check(scroll.scroll_vertical > 0 and scroll.get_global_rect().encloses(mana_input.get_global_rect()),
			"keyboard focus must scroll lower rule inputs into view")
		await capture("room-rules-keyboard")
		rules.find_child("starting_hp",true,false).value = 37
		for button in rules.find_children("*","Button",true,false):
			if button.text==Locale.t("common.confirm"): button.pressed.emit(); break
		await get_tree().process_frame
		check(PlayerData.battle_config.starting_hp==37,"room rules save the edited gameplay value")
	await capture("room-rules")
	lobby.queue_free()
	await get_tree().process_frame
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
func wheel(point: Vector2) -> void:
	move(point)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.position = point
		event.pressed = down
		stage.push_input(event,true)
func _return_routes() -> void:
	PlayerData.card_editor_return_scene = "res://MyCards.tscn"
	PlayerData.card_draft = {"name":"返回测试","card_type":"minion","hp":4,"atk":2,"cost":1}
	var editor = preload("res://CardEditor.tscn").instantiate()
	get_tree().root.add_child(editor)
	get_tree().current_scene = editor
	await get_tree().create_timer(0.25).timeout
	editor._start_solo_test(CardData.new("返回测试",1,4,2))
	await get_tree().create_timer(1.4).timeout
	check(get_tree().current_scene.scene_file_path=="res://Main.tscn","saved-card test must enter battle")
	get_tree().current_scene._abandon_battle_now()
	await get_tree().create_timer(0.8).timeout
	check(get_tree().current_scene.scene_file_path=="res://MyCards.tscn","surrender returns to the page where saved-card testing started")
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(),CardDatabase.beginner_deck())
	UIMotion.replace_scene("res://Main.tscn",true)
	await get_tree().create_timer(1.4).timeout
	NetworkManager.is_online = true
	get_tree().current_scene._abandon_battle_now()
	await get_tree().create_timer(0.9).timeout
	check(get_tree().current_scene.scene_file_path=="res://MainMenu.tscn","online surrender must use the current menu")
	check(get_tree().current_scene.get_node_or_null("OnlineModePopup")!=null,"online surrender returns to the current online choices")
	for pair in [["mp.dedicated","DedicatedLobby"],["mp.direct","DirectLobby"]]:
		if pair[1] == "DirectLobby":
			UIMotion.replace_scene("res://MainMenu.tscn",true,"online")
			await get_tree().create_timer(0.7).timeout
		var popup = get_tree().current_scene.get_node("OnlineModePopup")
		for button in popup.find_children("*","Button",true,false):
			if button.text == Locale.t(pair[0]): button.pressed.emit(); break
		await get_tree().create_timer(0.7).timeout
		check(get_tree().current_scene.scene_file_path=="res://"+pair[1]+".tscn","online mode enters its lobby before deck selection: "+pair[1])
	get_tree().current_scene.queue_free()
	get_tree().current_scene = self
	await get_tree().process_frame
