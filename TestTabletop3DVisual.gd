extends Node

@export var interactive := false
var battle: Node
func _ready() -> void:
	Locale.language = "zh"
	NetworkManager.close_connection()
	if OS.get_cmdline_user_args().has("--small"):
		AppPreferences.values["window_mode"] = 1
		await get_tree().process_frame
		get_window().size = Vector2i(960,540)
		await get_tree().process_frame
		assert(get_window().size == Vector2i(960, 540), "compact visual test must actually use the compact window")
	var deck: Array = []
	for i in range(12):
		var card := CardData.new("守望者 %d" % i,1,5,2)
		card.cost = 1
		deck.append(card)
	PlayerData.configure_hotseat_battle(deck,deck)
	battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await get_tree().create_timer(1.0).timeout
	for i in range(3):
		battle.game.player_field.slots[i] = CardData.new(["石庭守卫","烬火行者","星铸先知"][i],1,6+i,2+i)
		battle.game.player2_field.slots[4-i] = CardData.new(["暮色哨兵","灰羽术士","远山巡卫"][i],1,5+i,3+i)
	battle.game.player_field.slots[1].skills = [{"skill_name":"汲取知识","trigger":SkillEngine.TRIGGER_ON_ACTIVATE,"effects":[{"target":SkillEngine.TARGET_SELF,"effect":SkillRegistry.EFFECT_DRAW_CARDS,"value":1}]}]
	battle.game.allow_first_turn_attacks = true
	battle.update_entire_screen()
	await get_tree().create_timer(2.0).timeout
	if OS.get_cmdline_user_args().has("--capture"):
		var output := "res://artifacts/tabletop3d/first.png"
		DirAccess.make_dir_recursive_absolute("res://artifacts/tabletop3d")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output)
		print("TEST_TABLETOP_RENDERED ",output)
	if OS.get_cmdline_user_args().has("--quit-after-capture"):
		get_tree().quit(0)
		return
	if not interactive: await _verify()

func _click(at: Vector2, advance_frames: bool = true) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		get_viewport().push_input(event,true)
		if advance_frames:
			await get_tree().process_frame

func _drag(start: Vector2, target: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	get_viewport().push_input(press,true)
	await get_tree().process_frame
	var last := start
	for fraction in [0.2,0.4,0.7,1.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = start.lerp(target,fraction)
		motion.global_position = motion.position
		motion.relative = motion.position-last
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = motion.position
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
	assert(get_viewport().gui_is_dragging(),"actual GUI input must start a drag")
	var release := InputEventMouseButton.new()
	release.position = target
	release.global_position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	get_viewport().push_input(release,true)
	await get_tree().create_timer(0.25).timeout

func _center(control: Control) -> Vector2:
	return control.global_position+control.size*0.5

func _action(text: String) -> void:
	for button in battle.card_inspector.find_children("*","Button",true,false):
		if button.text == text:
			var deadline := Time.get_ticks_msec() + 3000
			while button.disabled and battle.is_resolution_locked() and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			await get_tree().process_frame
			assert(not button.disabled and button.is_visible_in_tree(), "inspector action must be available: " + text)
			await _click(_center(button))
			return
	assert(false,"missing inspector action: "+text)

func _verify() -> void:
	battle.reparent(get_tree().root)
	get_tree().current_scene = battle
	assert(battle.tabletop != null and battle.tabletop.cards.size() == 9,"field and hand must both have 3D cards")
	await _check_inspector_keyboard()
	var hash_before := BattleRepro.hash_state(battle.game.export_initial_state())
	var resting: Vector3 = battle.tabletop.cards[0].target
	battle.tabletop.impact(0,Vector3(0,0,0.4),true)
	await get_tree().create_timer(0.12).timeout
	assert(battle.tabletop.cards[0].root.position.distance_to(resting)>0.03,"impact must physically displace the card")
	assert(BattleRepro.hash_state(battle.game.export_initial_state())==hash_before,"visual physics must not modify the game state")
	var source: Control = battle.hand_container.get_child(0)
	var card: CardData = source.current_card_data
	var hand_count: int = battle.game.player_hand.size()
	var mana: int = battle.game.player_field.get_total_mana()
	await _drag(_center(source),_center(battle.player_side_ui.get_child(3)))
	assert(battle.game.player_field.slots[3] == card and battle.game.player_hand.size()==hand_count-1,"dragging a 3D hand card must deploy the same card")
	assert(battle.game.player_field.get_total_mana()==mana-card.cost,"3D deployment must pay the real rules cost")
	await _drag(_center(battle.player_side_ui.get_child(3)),_center(battle.player_side_ui.get_child(4)))
	assert(battle.game.player_field.slots[3] == null and battle.game.player_field.slots[4] == card,"field dragging must move the real unit")
	var hp: int = battle.game.player2_field.slots[2].hp
	await _click(_center(battle.player_side_ui.get_child(0)))
	assert(battle.card_inspector.visible,"clicking a 3D unit must reveal its actions")
	await _action("普通攻击")
	await _press_inspector_key(KEY_ESCAPE)
	assert(battle.current_attacker_idx == -1 and UIMotion.top_popup() == null
		and battle.game.player2_field.slots[2].hp == hp, "Escape must cancel aim without opening pause or attacking")
	await _click(_center(battle.player_side_ui.get_child(0)))
	await _action("普通攻击")
	await _click(_center(battle.enemy_side_ui.get_child(2)), false)
	assert(battle.game.player2_field.slots[2].hp == hp-2,"the inspector attack must resolve against the clicked enemy")
	var deadline := Time.get_ticks_msec() + 3000
	while not battle.is_resolution_locked() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(battle.is_resolution_locked(), "the hit must enter feedback before the next inspector opens")
	var deck_count: int = battle.game.shared_deck.size()
	await _click(_center(battle.player_side_ui.get_child(1)), false)
	var inspector: PanelContainer = battle.card_inspector
	var draw: Button = inspector.find_child("TabletopSkill0", true, false)
	assert(battle.is_resolution_locked() and draw.disabled and inspector.visible, "skill must stay disabled while attack feedback resolves")
	deadline = Time.get_ticks_msec() + 3000
	while draw.disabled and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(battle.card_inspector == inspector and inspector.visible and not draw.disabled,
		"the open inspector must enable its skill after attack feedback")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/tabletop3d/skill-ready.png")
	await _action("汲取知识")
	assert(battle.game.shared_deck.size()==deck_count-1,"inspector skills must use the shared rules engine")
	await get_tree().create_timer(0.3).timeout
	var discarded: int = battle.game.shared_discard.size()
	source = battle.hand_container.get_child(0)
	await _drag(_center(source),_center(battle.discard_zone))
	assert(battle.game.shared_discard.size()==discarded+1,"3D hand cards must remain discardable")
	source = battle.hand_container.get_child(0)
	var selected: CardData = source.current_card_data
	await _click(_center(source))
	await _action("部署")
	assert(battle.tabletop_selected_hand == selected, "deployment must be waiting for a destination")
	await _press_inspector_key(KEY_ESCAPE)
	assert(battle.tabletop_selected_hand == null and UIMotion.top_popup() == null and battle.game.player_hand.has(selected),
		"Escape must clear the pending placement and preserve the hand card")
	await _click(_center(source))
	await _action("部署")
	await _click(_center(battle.player_side_ui.get_child(3)))
	assert(battle.game.player_field.slots[3] == selected,"click selection must also deploy cards without dragging")
	var spell := CardData.new("星图预言",0,0,0)
	spell.card_type = "spell"
	spell.skills = [{"skill_name":"星图预言","trigger":SkillEngine.TRIGGER_ON_CAST,"effects":[{"target":SkillEngine.TARGET_SELF,"effect":SkillRegistry.EFFECT_DRAW_CARDS,"value":1}]}]
	battle.game.player_hand.push_front(spell)
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	source = battle.hand_container.get_child(0)
	var right := InputEventMouseButton.new()
	right.position = _center(source)
	right.global_position = right.position
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	get_viewport().push_input(right,true)
	await get_tree().process_frame
	right = right.duplicate()
	right.pressed = false
	get_viewport().push_input(right,true)
	await get_tree().process_frame
	assert(battle.card_inspector.visible,"right click must expose the hand card details")
	deck_count = battle.game.shared_deck.size()
	await _action("星图预言")
	assert(not battle.game.player_hand.has(spell) and battle.game.shared_deck.size()==deck_count-1,"hand inspector must cast spells through the real rules")
	var parasite := CardData.new("石苔",0,2,1)
	parasite.card_type = "parasite"
	battle.game.player_hand.push_front(parasite)
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var attachments: int = battle.game.player_field.slots[0].parasite_cards.size()
	await _click(_center(battle.hand_container.get_child(0)))
	await _action("依附")
	await _click(_center(battle.player_side_ui.get_child(0)))
	assert(battle.game.player_field.slots[0].parasite_cards.size()==attachments+1 and not battle.game.player_hand.has(parasite),"3D hand selection must attach parasite cards")
	await get_tree().process_frame
	assert(battle.tabletop.cards[0].face.shown_attack == 3,"the visible card face must include the attached parasite attack bonus")
	# Leave the inspected/hovered surface before measuring its resting pose.
	var leave := InputEventMouseMotion.new()
	leave.position = Vector2(4,get_viewport().get_visible_rect().size.y*0.5)
	leave.global_position = leave.position
	leave.relative = Vector2(-300,0)
	get_viewport().push_input(leave,true)
	await get_tree().create_timer(1.6).timeout
	for entry in battle.tabletop.cards.values():
		assert(entry.root.position.distance_to(entry.target)<0.12,"spring motion must settle without leaving cards off the table")
	await _press_inspector_key(KEY_ESCAPE)
	var pause := UIMotion.top_popup()
	assert(is_instance_valid(pause) and pause.get_script() == preload("res://presentation/BattlePause.gd"),
		"Escape without an active selection must still open the pause menu")
	await _press_inspector_key(KEY_ESCAPE)
	assert(UIMotion.top_popup() == null, "Escape must still close the pause menu")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/tabletop3d")
	get_viewport().get_texture().get_image().save_png("res://artifacts/tabletop3d/verified-%dx%d.png" % [get_window().size.x,get_window().size.y])
	print("TEST_TABLETOP_3D_VISUAL_OK deployment,move,attack,skill,discard,click-deploy,spell,parasite,physical-state-isolation,settling")
	get_tree().quit(0)


func _check_inspector_keyboard() -> void:
	var card: CardData = battle.game.player_field.slots[1]
	var original_skills := card.skills
	var first: Dictionary = original_skills[0].duplicate(true)
	for i in range(12):
		first.effects.append({"target": SkillEngine.TARGET_SELF, "effect": SkillRegistry.EFFECT_HEAL, "value": i + 1})
	card.skills = [first, original_skills[0]]
	var before := BattleRepro.hash_state(battle.game.export_initial_state())
	var source: Control = battle.player_side_ui.get_child(1).get_node("TabletopInput")
	source.grab_focus()
	await _press_inspector_key(KEY_ENTER)
	var inspector: Control = battle.card_inspector
	assert(is_instance_valid(inspector) and inspector.visible, "Enter on a field card must open its inspector")
	var button := inspector.find_child("TabletopSkill1", true, false) as Button
	var scroll := button.get_parent().get_parent() as ScrollContainer
	assert(not button.disabled and not scroll.get_global_rect().encloses(button.get_global_rect()),
		"the second available skill must initially be below the visible scroll area")
	for i in range(6):
		if button.has_focus():
			break
		await _press_inspector_key(KEY_TAB)
		assert(inspector.is_ancestor_of(get_viewport().gui_get_focus_owner()), "Tab must keep focus inside the inspector")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/tabletop3d/inspector-keyboard.png")
	# Godot rounds its scroll offset to integer layout units.
	assert(button.has_focus() and scroll.get_global_rect().grow(1.0).encloses(button.get_global_rect()),
		"focusing a skill with Tab must scroll it fully into view: focus=%s scroll=%s button=%s" % [
			get_viewport().gui_get_focus_owner(), scroll.get_global_rect(), button.get_global_rect()])
	await _press_inspector_key(KEY_ESCAPE)
	assert(not inspector.visible and source.has_focus(), "Escape must close the inspector and restore focus to its card")
	assert(BattleRepro.hash_state(battle.game.export_initial_state()) == before, "keyboard inspection must not execute any skill")
	source.release_focus()
	card.skills = original_skills


func _press_inspector_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame
