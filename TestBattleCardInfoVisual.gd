extends "res://TestTabletop3DVisual.gd"
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _ready() -> void:
	get_tree().auto_accept_quit = false
	AppPreferences.set_value("window_mode",1)
	get_window().size = Vector2i(1280,720)
	await super._ready()

func _verify() -> void:
	var literal := "[[color=red]自定义名字[/color]] 主动\n造成 2 点伤害；恢复 1 点生命；获得圣水。"
	var colored := preload("res://presentation/SkillDescription.gd").build(literal)
	add_child(colored)
	await get_tree().process_frame
	assert(preload("res://presentation/SkillDescription.gd").plain(colored.get_parsed_text())==literal,"keyword styling must preserve literal UGC names and description text")
	colored.queue_free()
	var card: CardData = battle.game.player_field.slots[0]
	card.skills = [{"skill_name":"", "trigger":SkillEngine.TRIGGER_ON_ACTIVATE,"effects":[{"effect":SkillEngine.EFFECT_DAMAGE,"value":1,"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY}]},{"skill_name":"   ","trigger":SkillEngine.TRIGGER_ON_ATTACK,"effects":[]}]
	card.temp_hp = 4
	card.apply_buff(SkillEngine.BUFF_POISON,2,3,1)
	var parasite := CardData.new("共生芽",1,3,0,[{"skill_name":"汲取","trigger":"on_damaged","max_uses":1,"effects":[{"effect":"heal","target":"self","value":1}]}])
	parasite.card_type = "parasite"
	card.parasite_cards.append(parasite)
	battle.update_entire_screen()
	await get_tree().create_timer(0.3).timeout
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		get_window().size = dimensions
		await get_tree().create_timer(0.3).timeout
		await _click(_center(battle.player_side_ui.get_child(0)))
		await get_tree().process_frame
		assert(battle.card_inspector.visible)
		var abilities: Control = battle.card_inspector.find_child("CardAbilitiesFrame",true,false)
		var attack_button: Control = battle.card_inspector.find_child("TabletopAttack",true,false)
		await get_tree().process_frame
		assert(attack_button.get_node_or_null("KeywordText")==null,"普通攻击 stays an unmodified action name")
		assert(abilities.is_ancestor_of(attack_button) and attack_button.get_parent()==battle.card_inspector.find_child("BasicAttackDescription",true,false).get_parent(),"attack button and description must share the abilities section")
		var skill_scroll := abilities.find_children("*", "ScrollContainer", true, false).front() as ScrollContainer
		var boundary := skill_scroll.get_parent().get_child(skill_scroll.get_index() - 1) as HSeparator
		assert(boundary != null and is_equal_approx(boundary.get_global_rect().end.y, skill_scroll.get_global_rect().position.y),
			"the fixed divider must touch the skill text's clipping edge")
		assert(preload("res://presentation/SkillDescription.gd").plain(battle.card_inspector.find_child("BasicAttackDescription",true,false).get_parsed_text()).contains("%d点伤害"%card.effective_atk()))
		assert(battle.card_inspector.find_child("TabletopSkill0",true,false).text == "技能1")
		assert(preload("res://UIHoverHints.gd").hint_for(battle.card_inspector.find_child("TabletopSkill0",true,false)).is_empty(),"inspector must not repeat descriptions in a hover popup")
		assert(battle.card_inspector.find_child("TabletopSkill1",true,false).text == "技能2")
		var panel = battle.card_inspector.find_child("CardStatePanel",true,false)
		assert(panel != null and panel.is_visible_in_tree())
		var text := ""
		for label in panel.find_children("*","Label",true,false): text += label.text+"\n"
		assert(text.contains("护盾") and text.contains("+4") and text.contains("3 回合"))
		assert(text.contains("下个己方回合开始时清除") and text.contains("己方回合结束时失去 2 点生命"),
			"status details must show the shield and poison timing")
		var parasite_skills: Control = panel.find_child("ParasiteSkills",true,false)
		assert(parasite_skills!=null and panel.is_ancestor_of(parasite_skills),"attached parasite abilities belong in the status panel")
		assert(not abilities.is_ancestor_of(parasite_skills),"parasite skills must not become host action buttons")
		await get_tree().create_timer(0.15).timeout
		assert(battle.get_viewport_rect().encloses(battle.card_inspector.get_global_rect()),"whole inspector must fit viewport")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/card-info-%d.png"%dimensions.x)
		var skill_bar := skill_scroll.get_v_scroll_bar()
		assert(skill_bar.visible, "the fixture must have enough skill text to scroll")
		skill_scroll.scroll_vertical = roundi((skill_bar.max_value - skill_bar.page) * 0.5)
		await get_tree().process_frame
		assert(skill_scroll.scroll_vertical > 0 and is_equal_approx(boundary.get_global_rect().end.y, skill_scroll.get_global_rect().position.y),
			"the divider must stay at the clipping edge while skills scroll")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/card-info-scrolled-%d.png"%dimensions.x)
		battle.card_inspector.hide()
	battle._show_card_details(parasite,false,-1,battle.player_side_ui.get_child(0),null,true)
	await get_tree().process_frame
	assert(battle.card_inspector.find_child("CardStatePanel",true,false).find_child("ParasiteSkills",true,false)!=null,"a parasite's own preview must also show its skills in status")
	assert(battle.card_inspector.find_children("TabletopSkill*","Button",true,false).is_empty(),"parasite preview must not duplicate abilities in the main action section")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/parasite-status-skills.png")
	battle.card_inspector.hide()
	var source: Control = battle.hand_container.get_child(0)
	var count: int = battle.game.player_hand.size()
	var field: BattleField = battle._my_field()
	field.current_mana = 3
	field.temp_mana = 0
	source.current_card_data.cost = 2
	var mana_bar: ProgressBar = battle.player_status_hud.get_node("Margin/Content/ManaBar")
	mana_bar.value = 3
	battle._resource_hover_card = null
	await RenderingServer.frame_post_draw
	var before_image := get_viewport().get_texture().get_image()
	var motion := InputEventMouseMotion.new()
	motion.position = _center(source)
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	var shade: Control = mana_bar.get_node("ResourceCostPreview")
	assert(shade.visible and shade.get_meta("after")==1 and shade.get_node("TintFill").material is ShaderMaterial,"affordable hover must outline and hatch the payable resources")
	await RenderingServer.frame_post_draw
	var preview_image := get_viewport().get_texture().get_image()
	preview_image.save_png("res://artifacts/ui-refinement-20261113/resource-preview-yellow.png")
	battle._resource_hover_card = null
	battle._refresh_resource_preview()
	mana_bar.value = 1
	await RenderingServer.frame_post_draw
	var after_image := get_viewport().get_texture().get_image()
	var pixel_scale: Vector2 = Vector2(before_image.get_width(),before_image.get_height())/battle.get_viewport_rect().size
	var area := mana_bar.get_global_rect()
	var y := roundi(area.get_center().y*pixel_scale.y)
	var expected: Array[int] = []
	var observed: Array[int] = []
	for x in range(ceili(area.position.x*pixel_scale.x),floori(area.end.x*pixel_scale.x)):
		if _pixel_diff(before_image.get_pixel(x,y),after_image.get_pixel(x,y))>0.08: expected.append(x)
		if _pixel_diff(before_image.get_pixel(x,y),preview_image.get_pixel(x,y))>0.08: observed.append(x)
	assert(not expected.is_empty() and not observed.is_empty())
	assert(absi(expected.front()-observed.front())<=1 and absi(expected.back()-observed.back())<=1,"forecast must align with actual rendered resource loss")
	# Check proportional lengths from rendered bars, not source constants.
	for resource_bar in [mana_bar,battle.player_status_hud.get_node("Margin/Content/ActionBar")]:
		battle._resource_hover_card = null
		battle._refresh_resource_preview()
		resource_bar.max_value = 10
		resource_bar.value = 2
		await RenderingServer.frame_post_draw
		var two := get_viewport().get_texture().get_image()
		resource_bar.value = 3
		await RenderingServer.frame_post_draw
		var three := get_viewport().get_texture().get_image()
		var rect: Rect2 = resource_bar.get_global_rect()
		var py := roundi(rect.get_center().y*pixel_scale.y)
		var left := ceili(rect.position.x*pixel_scale.x)
		var right := floori(rect.end.x*pixel_scale.x)-2
		var background := three.get_pixel(right,py)
		var widths := [0,0]
		for px in range(left,right):
			if _pixel_diff(two.get_pixel(px,py),background)>0.08: widths[0]=px-left+1
			if _pixel_diff(three.get_pixel(px,py),background)>0.08: widths[1]=px-left+1
		assert(widths[0]>0 and absi(widths[0]*3-widths[1]*2)<=3,"2 resources must render as two thirds of 3 resources")
	field.current_mana = 2
	source.current_card_data.cost = 3
	mana_bar.value = 2
	motion.position = Vector2(2,2)
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	motion.position = _center(source)
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(shade.visible and not mana_bar.has_node("ForecastShortfall") and shade.get_meta("after")==-1,"insufficient hover must retain the hatch without extra resource text")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/resource-preview-red.png")
	motion.position = Vector2(2,2)
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	assert(not shade.visible and field.current_mana==2,"leaving must clear forecast without spending resources")
	source.current_card_data.skills = [{
		"skill_name": "架盾", "trigger": SkillEngine.TRIGGER_ON_SUMMON,
		"effects": [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 50, SkillEngine.BUFF_DAMAGE_REDUCTION, 2)],
	}]
	source.set_card(source.current_card_data)
	motion.position = _center(source)
	get_viewport().push_input(motion,true)
	await get_tree().create_timer(0.6).timeout
	var hints = UIMotion.get_node("HoverHints")
	assert(not hints.panel.visible, "hovering a hand card must not open the skill preview")
	await _click(_center(source))
	assert(battle.card_inspector.visible and battle.game.player_hand.size()==count,"single-click must inspect without playing")
	var skill_button := battle.card_inspector.find_child("TabletopSkill0",true,false) as Button
	assert(skill_button != null,"clicking still shows the hand card's skills")
	var skill_description := skill_button.get_parent().get_child(skill_button.get_index() + 1) as RichTextLabel
	var displayed := preload("res://presentation/SkillDescription.gd").plain(skill_description.get_parsed_text())
	assert(displayed.contains("减伤 50%，持续 2 回合"), "the rendered skill should state the reduction percentage directly")
	await _check_keyword_hover(skill_description, hints)
	await get_tree().process_frame
	var raised_card: Polygon2D = battle._hand_focus_overlays[source.get_instance_id()].face
	assert(raised_card.is_visible_in_tree() and raised_card.z_index < battle.card_inspector.z_index,
		"the inspected hand card must stay above the HUD and below its inspector")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/hand-card-inspector-layer.png")
	assert(battle.card_inspector.find_child("CardStatePanel",true,false)==null,"plain cards need no empty status panel")
	battle.card_inspector.hide()
	battle.tabletop_selected_hand = null
	var dialog = preload("res://CardCollectionDialog.gd").show_cards(battle,[card],"弃牌堆")
	await get_tree().create_timer(0.3).timeout
	var snapshot := BattleRepro.hash_state(battle.game.export_initial_state())
	var inspect = dialog.card_uis[0].get_node("InspectCard")
	await _click(_center(inspect))
	await get_tree().create_timer(0.2).timeout
	var details := battle.card_inspector.get_parent() as CanvasLayer
	assert(battle.card_inspector.visible and details != null and details.get_parent() == dialog and details.layer > dialog.layer,
		"pile cards use the same inspector above their collection")
	assert(battle.card_inspector.find_child("TabletopSkill0",true,false).disabled,"collection inspection must be read only")
	assert(snapshot==BattleRepro.hash_state(battle.game.export_initial_state()),"inspection must not change battle state")
	dialog.queue_free()
	await get_tree().process_frame
	motion.position = _center(battle.end_turn_button)
	get_viewport().push_input(motion,true)
	await get_tree().create_timer(0.65).timeout
	assert(is_instance_valid(battle.end_turn_button._preview_panel) and battle.end_turn_button._preview_panel.is_visible_in_tree())
	assert(not hints.panel.is_visible_in_tree(),"End Turn must not open a second global tooltip")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/end-turn-single.png")
	motion.position = Vector2(2,2)
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	field.actions_taken = 2
	field.action_points = 3
	card.has_acted = false
	card.has_attacked = false
	battle.tabletop_selected_hand = null
	battle._on_attack_requested(0)
	await get_tree().process_frame
	var action_bar: ProgressBar = battle.player_status_hud.get_node("Margin/Content/ActionBar")
	var action_shade: Control = action_bar.get_node("ResourceCostPreview")
	assert(battle.current_attacker_idx==0 and action_shade.visible and action_shade.get_meta("cost")==2,"target selection must forecast the real action payment")
	battle.cancel_attack()
	await get_tree().process_frame
	assert(not action_shade.visible and field.action_points==3,"cancel targeting must clear forecast without payment")
	field.action_points = 0
	field.current_mana = 0
	var rest_mana := mana_bar.position
	var rest_action := action_bar.position
	battle.tabletop_slot_clicked(false,0)
	await get_tree().process_frame
	await _click(_center(battle.card_inspector.find_child("TabletopAttack",true,false)))
	assert(action_bar.get_node("ResourceRejection").visible and mana_bar.get_node("ResourceRejection").visible,"failed payment must mark both exhausted resources")
	assert(field.action_points==0 and field.current_mana==0,"denial feedback must not spend resources")
	await get_tree().create_timer(0.5).timeout
	assert(not action_bar.get_node("ResourceRejection").visible and action_bar.position.is_equal_approx(rest_action) and mana_bar.position.is_equal_approx(rest_mana),"denial shake and border must restore cleanly")
	battle.card_inspector.hide()
	await _verify_skill_uses(card, field)
	# A real empty-field settlement emits per-attacker hit feedback at the hero HUD.
	for i in range(5): battle.game.player2_field.slots[i] = null
	battle.game.turn_number = 2
	field.actions_taken = 0
	field.action_points = 10
	field.current_mana = 10
	for unit in field.slots:
		if unit != null:
			unit.has_acted=false
			unit.has_attacked=false
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var hp_before: int = battle.game.player2_field.player_hp
	var result: Dictionary = battle.game.end_player_turn()
	assert(result.get("total_damage",0)>0)
	battle._show_direct_damage(result)
	battle.update_entire_screen()
	await get_tree().create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/hero-hit-origin.png")
	assert(battle.get_node("CanvasLayer").find_child("HeroStrikeTrail",true,false)!=null,"automatic hits must connect the attacking card to the hero HUD")
	assert(battle.game.player2_field.player_hp==maxi(0,hp_before-int(result.total_damage)),"feedback must not apply damage a second time")


func _check_keyword_hover(description: RichTextLabel, hints: CanvasLayer) -> void:
	await RenderingServer.frame_post_draw
	var hits: Array[Vector2] = []
	for y in range(0, int(description.size.y), 2):
		for x in range(int(description.size.x)):
			if description.get_tooltip(Vector2(x, y)) == SkillHelp.KEYWORD_PREFIX + "reduction":
				hits.append(Vector2(x, y))
		if hits.size() > description.get_theme_font_size("normal_font_size") * 2:
			break
	assert(hits.size() > description.get_theme_font_size("normal_font_size") * 2,
		"the reduction icon and its two Chinese characters must all accept hover")
	for point in [hits[2], hits[-3]]:
		var motion := InputEventMouseMotion.new()
		motion.position = description.get_global_transform_with_canvas() * point
		get_viewport().push_input(motion, true)
		await get_tree().create_timer(0.55).timeout
		assert(hints.panel.visible and hints.current_text == SkillHelp.keyword_description("reduction"),
			"battle hover must show the same explanation on the icon and colored word")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/battle-keyword-hover.png")
	print("TEST_BATTLE_KEYWORD_HOVER_OK")
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/hero-hit-midpoint.png")
	await get_tree().create_timer(2.3).timeout
	assert(battle.get_node("CanvasLayer").find_child("HeroStrikeTrail",true,false)==null,"hero trails must clean up")
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_BATTLE_CARD_INFO_VISUAL_OK click,numbered-skills,status-values,durations,plain-card,pile,read-only,viewport")
	get_tree().quit(0)

func _verify_skill_uses(card: CardData, field: BattleField) -> void:
	field.actions_taken = 0
	field.action_points = 10
	field.current_mana = 5
	card.skills[0] = {"skill_name":"固守", "trigger":"on_activate", "max_uses":2,
		"effects":[{"effect":"shield", "target":"self", "value":1}]}
	var slot: Control = battle.player_side_ui.get_child(0)
	await _click(_center(slot))
	var skill: Button = battle.card_inspector.find_child("TabletopSkill0",true,false)
	var description := skill.get_parent().get_child(skill.get_index()+1) as RichTextLabel
	assert(description.get_parsed_text().begins_with("[固守] 主动，剩余 2 次"))
	var unlimited: Button = battle.card_inspector.find_child("TabletopSkill1",true,false)
	var unlimited_description := unlimited.get_parent().get_child(unlimited.get_index()+1) as RichTextLabel
	assert(not unlimited_description.get_parsed_text().contains("剩余"))
	var parasite_description := battle.card_inspector.find_child("ParasiteSkills",true,false).get_child(0) as RichTextLabel
	assert(parasite_description.get_parsed_text().contains("剩余 1 次"))
	ParasiteRules.trigger_host_passives("on_damaged", card, battle.game.make_skill_context(0))
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(parasite_description.get_parsed_text().contains("次数已用完"), "an attached passive must refresh in the open inspector")
	assert(not skill.disabled)
	await _click(_center(skill))
	await get_tree().create_timer(0.65).timeout
	await _click(_center(slot))
	skill = battle.card_inspector.find_child("TabletopSkill0",true,false)
	description = skill.get_parent().get_child(skill.get_index()+1) as RichTextLabel
	assert(description.get_parsed_text().begins_with("[固守] 主动，剩余 1 次"), "clicking the skill must visibly consume a use")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/battle-skill-uses.png")
	SkillEngine.trigger_single_skill(card, 0, battle.game.make_skill_context(0))
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(description.get_parsed_text().begins_with("[固守] 主动，次数已用完"))
	assert(skill.disabled)
	battle.card_inspector.hide()
	print("TEST_BATTLE_SKILL_USES_VISIBLE_OK")

func _pixel_diff(a: Color,b: Color) -> float:
	return Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()
