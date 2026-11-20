extends Node
var failures: Array[String] = []
var stage: SubViewport
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _ready() -> void:
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id=""
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(),CardDatabase.beginner_deck())
	GamePreferences.set_battle_playback_speed(GamePreferences.PlaybackSpeed.FAST)
	stage=SubViewport.new()
	stage.size=Vector2i(1280,720)
	stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var battle=load("res://Main.tscn").instantiate()
	stage.add_child(battle)
	await get_tree().create_timer(1.5).timeout
	_check(battle.draw_pile_btn.disabled,"draw pile is hidden by default")
	_check(battle.discard_zone==battle.discard_pile_btn,"discard drop and inspection share one control")
	_check(battle.draw_pile_btn.get_global_rect().end.x<battle.hand_area.get_global_rect().position.x,"draw pile stays left of the hand")
	_check(battle.discard_pile_btn.get_global_rect().position.x>battle.hand_area.get_global_rect().end.x,"discard pile stays right of the hand")
	_check(battle.get_node_or_null("CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/DiscardColumn/DiscardZone")==null,"old independent discard zone is removed")
	var count_position: Vector2 = battle.draw_pile_btn.count_label.global_position
	var art_position: Vector2 = battle.draw_pile_btn.artwork.position
	await click(battle.draw_pile_btn.get_global_rect().get_center())
	_check(viewer(battle)==null,"hidden draw pile cannot open by clicking")
	await get_tree().create_timer(0.06).timeout
	_check(battle.draw_pile_btn.get_node("UnavailableFeedback") is TextureRect,"unavailable pile feedback follows artwork instead of a rectangle")
	_check(battle.draw_pile_btn.count_label.global_position.is_equal_approx(count_position),"pile count stays still during rejection")
	_check(not battle.draw_pile_btn.artwork.position.is_equal_approx(art_position),"only pile artwork shakes during rejection")
	await capture("draw-denied.png")
	await get_tree().create_timer(0.5).timeout
	await click(battle.field_rules_btn.get_global_rect().get_center())
	await get_tree().create_timer(0.3).timeout
	var info = battle.get_node("BattleFieldRules")
	var card_page = info.find_child("MatchCardScroll",true,false)
	var rule_page = info.find_child("MatchRuleScroll",true,false)
	_check(rule_page.visible and not card_page.visible,"match info opens on field rules")
	for button in info.find_children("*","Button",true,false):
		if button.text==Locale.t("battle.match_cards"): await click(button.get_global_rect().get_center()); break
	await settle()
	_check(card_page.visible and not rule_page.visible,"match card tab switches pages")
	var grid = info.find_child("MatchCardGrid",true,false)
	_check(grid.get_child_count()==PlayerData.battle_deck.size()+PlayerData.opponent_battle_deck.size(),"match card browser contains both starting decks")
	await capture("match-cards.png")
	var inspect = grid.get_child(0).find_child("InspectMatchCard",true,false)
	await click(inspect.get_global_rect().get_center())
	_check(info.has_node("TabletopCardInspector"),"match cards open the read-only inspector")
	if info.has_node("TabletopCardInspector"): info.get_node("TabletopCardInspector").queue_free()
	stage.size=Vector2i(960,540)
	await get_tree().create_timer(0.3).timeout
	await capture("match-cards-960.png")
	stage.size=Vector2i(1280,720)
	await settle()
	info.queue_free()
	await settle()
	var unit := CardData.new("唐太宗",2,2,2,[{"skill_name":"唐你一下","trigger":SkillEngine.TRIGGER_ON_ATTACK,"effects":[{"effect":SkillEngine.EFFECT_DAMAGE,"value":1,"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY}]}])
	battle.game.player_field.slots[0]=unit
	battle.update_entire_screen()
	await settle()
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		stage.size=dimensions
		await get_tree().create_timer(0.2).timeout
		battle._show_card_details(unit,false,0,battle.player_side_ui.get_child(0))
		await settle()
		var attack = battle.card_inspector.find_child("TabletopAttack",true,false)
		var description = battle.card_inspector.find_child("BasicAttackDescription",true,false)
		var cost = battle.card_inspector.find_child("ActionPaymentLabel",true,false)
		_check(attack.get_parent()==description.get_parent() and cost.get_parent()==attack.get_parent(),"attack, description and cost share one section")
		_check(description.get_index()==attack.get_index()+1,"damage explanation immediately follows attack button")
		await capture("attack-section-%d.png"%dimensions.x)
		battle.card_inspector.queue_free()
		await settle()
	stage.size=Vector2i(1280,720)
	battle.game.player_field.slots[0]=null
	await settle()
	battle._show_help_popup()
	await get_tree().create_timer(0.25).timeout
	await capture("help-rewritten.png")
	battle.get_node("BattleRulesHelp").queue_free()
	await settle()
	battle.game.current_player=1
	battle.game.is_player_turn=true
	battle.game.turn_number=2
	battle.game.player_hand.clear()
	battle.game.player2_hand.clear()
	battle.game.shared_deck.clear()
	for i in range(6): battle.game.shared_deck.append(CardData.new("牌 %d" % (i+1),0,1,1,[]))
	battle.game.shared_discard.clear()
	var discarded:=CardData.new("待弃牌",0,2,1,[])
	battle.game.player_hand.append(discarded)
	battle.reset_hand_ui_from_game_state()
	battle.update_entire_screen()
	await settle()
	await capture("layout-hidden.png")
	var source: Control=battle.hand_container.get_child(0)
	source.force_drag({"card_data":discarded,"card_ui":source},null)
	var motion:=InputEventMouseMotion.new()
	motion.position=battle.discard_pile_btn.get_global_rect().get_center()
	stage.push_input(motion,true)
	await get_tree().create_timer(0.15).timeout
	_check(battle.discard_pile_btn.get("_highlighted"),"discard pile highlights during a valid drag")
	await capture("drop-hover.png")
	var release:=InputEventMouseButton.new()
	release.position=motion.position
	release.button_index=MOUSE_BUTTON_LEFT
	release.pressed=false
	stage.push_input(release,true)
	await settle()
	_check(battle.game.player_hand.is_empty() and battle.game.shared_discard==[discarded],"dropping on right pile discards exactly one card")
	_check(viewer(battle)==null,"dropping does not also open the viewer")
	_check(battle._last_pile_counts.y==0,"count waits until arrival")
	await get_tree().create_timer(0.07).timeout
	var icon = battle.get_node("CanvasLayer").get_children().filter(func(n): return n.get_meta("battle_fx_kind","")=="manual_discard_card").front()
	_check(icon.row_progress(1.0)>icon.row_progress(0.0),"discard lower edge enters before upper edge")
	_check(icon.row_point(1.0,-1).distance_to(icon.row_point(1.0,1))<icon.row_point(0.0,-1).distance_to(icon.row_point(0.0,1)),"discard lower edge narrows first")
	await capture("absorb-start.png")
	await get_tree().create_timer(0.07).timeout
	await capture("absorb-tail.png")
	await get_tree().create_timer(0.65).timeout
	_check(battle._last_pile_counts.y==1,"arrival updates the right pile count")
	await click(battle.discard_pile_btn.get_global_rect().get_center())
	var dialog=viewer(battle)
	_check(dialog!=null and dialog.cards==[discarded],"clicking right pile shows discarded cards")
	if dialog!=null:
		await capture("discard-viewer.png")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		get_viewport().push_input(escape, true)
		await settle()
		_check(viewer(battle) == null and UIMotion.top_popup() == null, "Escape closes discard viewer before opening pause")
	await settle()
	battle.game.battle_config["draw_pile_visible"]=true
	battle.game.battle_config["draw_pile_ordered"]=true
	battle.update_entire_screen()
	await settle()
	var original: Array=battle.game.shared_deck.duplicate()
	var rng_before: int=battle.game.game_rng.state
	await click(battle.draw_pile_btn.get_global_rect().get_center())
	dialog=viewer(battle)
	_check(dialog!=null and dialog.cards==original,"ordered view starts with the actual next draw")
	if dialog!=null: dialog.queue_free()
	await settle()
	battle.game.battle_config["draw_pile_ordered"]=false
	var saw_shuffled:=false
	for attempt in range(5):
		await click(battle.draw_pile_btn.get_global_rect().get_center())
		dialog=viewer(battle)
		_check(dialog!=null,"visible draw pile opens")
		if dialog!=null:
			_check(dialog.cards.size()==original.size() and original.all(func(card): return dialog.cards.has(card)),"random view preserves pile membership")
			if dialog.cards!=original: saw_shuffled=true
			dialog.queue_free()
		await settle()
	_check(saw_shuffled,"random mode actually rearranges display order")
	_check(battle.game.shared_deck==original and battle.game.game_rng.state==rng_before,"inspection preserves real draw order and gameplay RNG")
	var copy=battle.game.copy_for_simulation()
	_check(copy.battle_config.draw_pile_visible and not copy.battle_config.draw_pile_ordered,"view rules survive state copies")
	stage.size=Vector2i(960,540)
	await get_tree().create_timer(0.4).timeout
	await settle()
	await capture("layout-960.png")
	battle.queue_free()
	await settle()
	PlayerData.battle_config=PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	PlayerData.battle_select_mode="practice"
	var prep=load("res://BattleDeckSelect.tscn").instantiate()
	stage.add_child(prep)
	await settle()
	var hover := InputEventMouseMotion.new()
	hover.position=prep.advanced_button.get_global_rect().get_center()
	stage.push_input(hover,true)
	await get_tree().create_timer(0.2).timeout
	var advanced_rect: Rect2 = prep.advanced_button.get_global_rect()
	_check(prep.settings_panel.get_global_rect().encloses(advanced_rect) and not prep.settings_scroll.get_global_rect().intersects(advanced_rect),
		"the fixed Advanced button fits below the scrolling rules")
	await capture("advanced-hover-padding.png")
	await click(advanced_rect.get_center())
	await settle()
	var toggle: BaseButton=prep.advanced_layer.find_child("DrawPileVisibleToggle",true,false)
	var choice: OptionButton=prep.advanced_layer.find_child("DrawPileOrderChoice",true,false)
	_check(not toggle.button_pressed and not choice.get_parent().visible,"order selection stays hidden until visibility is enabled")
	toggle.button_pressed=true
	choice.select(1)
	_check(choice.get_parent().visible,"enabling visibility reveals order selection")
	await get_tree().create_timer(0.4).timeout
	await capture("visibility-settings.png")
	for button in prep.advanced_layer.find_children("*","Button",true,false):
		if button.text==Locale.t("common.confirm"): button.pressed.emit(); break
	await settle()
	_check(PlayerData.battle_config.draw_pile_visible and PlayerData.battle_config.draw_pile_ordered,"confirm saves both visibility settings")
	_check(MatchAgreement.valid_config(PlayerData.battle_config),"shared agreement accepts new rules")
	var legacy:=PlayerData.battle_config.duplicate()
	legacy.erase("draw_pile_visible"); legacy.erase("draw_pile_ordered")
	_check(MatchAgreement.valid_config(legacy),"legacy rule dictionaries remain valid")
	legacy["draw_pile_visible"]="true"
	_check(not MatchAgreement.valid_config(legacy),"agreement rejects invalid visibility types")
	prep.queue_free()
	await settle()
	if failures.is_empty(): print("TEST_BATTLE_PILE_VISUAL_OK");get_tree().quit(0)
	else:
		for message in failures:push_error("TEST_BATTLE_PILE_VISUAL_FAILED: "+message)
		get_tree().quit(1)
func viewer(battle: Node):
	for child in battle.get_children():
		if child.get_script()==preload("res://CardCollectionDialog.gd"):return child
	return null
func settle() -> void:
	for i in range(4):await get_tree().process_frame
func click(point: Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		stage.push_input(event,true)
		await get_tree().process_frame
	await settle()
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	stage.get_texture().get_image().save_png("res://artifacts/pile-layout-20261114/"+name)
func _check(ok: bool,message: String) -> void:
	if not ok:failures.append(message)
