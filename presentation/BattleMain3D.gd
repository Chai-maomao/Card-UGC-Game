extends "res://BattleMainNetwork.gd"

const Table = preload("res://presentation/BattleTable3D.gd")
const HandInput = preload("res://presentation/TabletopHandInput.gd")
const SlotInput = preload("res://presentation/TabletopSlotInput.gd")
var tabletop: Node3D
var card_inspector: PanelContainer
var _inspector_action_refresh := Callable()
var _inspector_can_act := false
var _resource_hover_card: CardData
var _prediction_target := -1
var _prediction_cache := ""
var _prediction_shown: Array[int] = []
var _test_add_button: Button
var _swapping_enemy_slot := -1
var _enemy_drag_root: Node3D
var _hand_focus_overlays: Dictionary = {}
var _hand_lighting_buffer: BackBufferCopy
var tabletop_selected_hand: CardData
var opponent_hand_presentation: CanvasLayer

func _ready() -> void:
	super._ready()
	# Logic runners need no rendering resources. Production and visual tests use 3D.
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--tabletop-test"): return
	tabletop = Table.new()
	tabletop.classic_battle_ui = true
	tabletop.show_center_seal = false
	tabletop.name = "BattleTable3D"
	add_child(tabletop)
	opponent_hand_presentation = preload("res://presentation/OpponentHandPresentation.gd").new()
	opponent_hand_presentation.name = "OpponentHandPresentation"
	opponent_hand_presentation.battle = self
	add_child(opponent_hand_presentation)
	var random_wheel := preload("res://presentation/RandomWheelPresentation.gd").new()
	random_wheel.name = "RandomWheelPresentation"
	random_wheel.battle = self
	add_child(random_wheel)
	var status_fx := preload("res://presentation/BattleCardStatusFx.gd").new()
	status_fx.name = "BattleCardStatusFx"
	status_fx.battle = self
	# Board marks sit above the 3D table but beneath hand cards and inspectors.
	status_fx.z_index = 0
	$CanvasLayer.add_child(status_fx)
	$CanvasLayer.move_child(status_fx, 0)
	_hand_lighting_buffer = BackBufferCopy.new()
	_hand_lighting_buffer.name = "HandLightingBuffer"
	_hand_lighting_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_hand_lighting_buffer.hide()
	$CanvasLayer.add_child(_hand_lighting_buffer)
	$CanvasLayer.move_child(_hand_lighting_buffer,0)
	var background: Control = $CanvasLayer/MainBackground
	background.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	for name in ["BattleBackdrop2D","EnemyAura","PlayerAura"]:
		var decoration := background.get_node_or_null(name)
		if decoration != null: decoration.hide()
	for side in [player_side_ui,enemy_side_ui]:
		for slot in side.get_children():
			slot.modulate.a = 0
			slot.focus_mode = Control.FOCUS_NONE
			var input := SlotInput.new()
			input.name = "TabletopInput"
			input.battle = self
			input.slot = slot
			input.opposing = side == enemy_side_ui
			input.index = slot.get_index()
			input.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			input.mouse_filter = Control.MOUSE_FILTER_STOP
			input.focus_mode = Control.FOCUS_ALL
			input.mouse_entered.connect(func():
				if input.slot.current_card_data != null: AppAudio.play_hover(input.slot,true)
				tabletop.hover(input.index+(5 if input.opposing else 0),true)
				_prediction_target = input.index+(5 if input.opposing else 0))
			input.mouse_exited.connect(func():
				tabletop.hover(input.index+(5 if input.opposing else 0),false)
				_prediction_target = -1)
			slot.add_child(input)
	if PlayerData.is_card_playtest_active() and not PlayerData.is_online_battle() and not _is_party_battle():
		_test_add_button = Button.new()
		_test_add_button.name = "AddTestCard"
		_test_add_button.text = "添加测试卡到手牌" if Locale.language == "zh" else "Add test card to hand"
		UITheme.apply_button(_test_add_button, "secondary", false)
		$CanvasLayer.add_child(_test_add_button)
		_test_add_button.pressed.connect(func():
			if _my_hand().size() >= SkillEngine.MAX_HAND_SIZE: return
			var card := PlayerData.card_playtest_opening_card()
			if card == null: return
			card.instance_id = "test-copy-%d" % Time.get_ticks_usec()
			_my_hand().append(card)
			_refresh_hand_ui()
			update_entire_screen())
	_style_tabletop_ui()
	_sync_tabletop.call_deferred()

func _do_update_entire_screen() -> void:
	super._do_update_entire_screen()
	if tabletop != null:
		if is_instance_valid(card_inspector) and card_inspector.get_meta("turn",game.current_player) != game.current_player: card_inspector.hide()
		_update_inspector_actions(true)
		_sync_tabletop()
		_style_tabletop_ui()


func _on_appearance_preference_changed(key: String) -> void:
	super._on_appearance_preference_changed(key)
	if key != "appearance" or not is_instance_valid(tabletop):
		return
	$CanvasLayer/MainBackground.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for button in [end_turn_button, face_mana_button, help_btn, field_rules_btn, battle_settings_btn, battle_chat_button, action_log_button, _test_add_button]:
		if button != null:
			UITheme.apply_button(button, "primary" if button == end_turn_button else "secondary", bool(button.get_meta("uimotion_enabled", false)))
	_style_tabletop_ui()
	var broadcast_style := UITheme.panel_style(UITheme.COLOR_PANEL_DARK, UITheme.Tokens.BORDER, 1, 8)
	broadcast_style.content_margin_top = 2
	broadcast_style.content_margin_bottom = 2
	combat_broadcast_panel.add_theme_stylebox_override("normal", broadcast_style)
	_refresh_combat_broadcast_color()
	if is_instance_valid(action_log_panel):
		UITheme.apply_popup_frame(action_log_panel, "dark", false, true)
		UITheme.theme_tree(action_log_panel)
		action_log_text.add_theme_color_override("default_color", UITheme.COLOR_TEXT)
		_refresh_action_log_text()

func _on_enemy_hand_discarded(actor: int,before_count: int,removed: Array) -> void:
	if removed.is_empty(): return
	var snapshots: Array = []
	for outcome in removed:
		var item := {"card":PlayerData.serialize_card(outcome.card),"index":int(outcome.index)}
		if actor != _view_player():
			for child in hand_container.get_children():
				if child.current_card_data.instance_id == outcome.card.instance_id:
					var origin: Vector2 = child.get_global_rect().get_center()
					item["origin"] = [origin.x,origin.y]
					break
		snapshots.append(item)
	var event := {"kind":"enemy_hand","player":actor,"before_count":before_count,"cards":snapshots,"feedback_group":int(_action_feedback_group_stack.back()) if not _action_feedback_group_stack.is_empty() else 0}
	if opponent_hand_presentation != null:
		if actor != _view_player(): opponent_hand_presentation.preserve_own_faces(snapshots)
		opponent_hand_presentation.reserve_count(before_count if actor==_view_player() else -1,snapshots.size())
	if not _action_broadcast.is_empty():
		_action_presentation_events.append(event)
	elif not _random_unbatched_events.is_empty():
		_random_unbatched_events.append(event)
	else:
		_queue_presentation_feedback([event])

func _prime_remote_hand_entry(event: Dictionary,deferred: bool) -> void:
	super._prime_remote_hand_entry(event,deferred)
	if str(event.get("kind","")) != "enemy_hand" or opponent_hand_presentation == null: return
	var actor := int(event.get("player",0))
	if actor != _view_player():
		opponent_hand_presentation.preserve_own_faces(event.get("cards",[]))
		for item in event.get("cards",[]):
			for child in hand_container.get_children():
				if child.current_card_data.instance_id == str(item.get("card",{}).get("instance_id","")):
					var origin: Vector2 = child.get_global_rect().get_center()
					item["origin"] = [origin.x,origin.y]
					break
	opponent_hand_presentation.reserve_count(int(event.get("before_count",0)) if actor==_view_player() else -1,(event.get("cards",[]) as Array).size())

func _play_enemy_hand_event(event: Dictionary) -> void:
	if not battle_finished and is_instance_valid(opponent_hand_presentation):
		await opponent_hand_presentation.play(event)


func _prepare_finished_battle_result() -> void:
	super._prepare_finished_battle_result()
	if battle_finished and is_instance_valid(opponent_hand_presentation):
		opponent_hand_presentation.cancel_pending_pick()

func _sync_tabletop() -> void:
	if tabletop == null: return
	if is_instance_valid(_test_add_button):
		_test_add_button.disabled = _my_hand().size() >= SkillEngine.MAX_HAND_SIZE or not is_my_turn() or _turn_ending
		_test_add_button.position = Vector2(20, maxf(72,get_viewport_rect().size.y-230))
	_prediction_cache = ""
	tabletop.fit_opponent_lane(player_side_ui,enemy_side_ui)
	_layout_action_log_panel()
	for side in [player_side_ui,enemy_side_ui]:
		var enemy: bool = side == enemy_side_ui
		for slot in side.get_children():
			if slot.current_card_ui != null: slot.current_card_ui.hide()
			var index: int = slot.get_index()
			var key := index + (5 if enemy else 0)
			var player := _opponent_player() if enemy else _view_player()
			var hp: Dictionary = _hp_presentation_overrides.get(_hp_presentation_key(player, index), {})
			tabletop.sync_slot(slot, key, slot.current_card_data, enemy, true, hp)
			var proxy: Control = slot.get_node_or_null("TabletopInput")
			if proxy != null: slot.move_child(proxy,slot.get_child_count()-1)

func _apply_hp_presentation_override(value: Dictionary) -> void:
	super._apply_hp_presentation_override(value)
	if tabletop != null:
		tabletop.present_hp(_table_key(int(value.player), int(value.slot)), int(value.hp), int(value.max_hp))

func tabletop_slot_clicked(enemy: bool, index: int) -> void:
	if _enemy_swap_is_pending():
		return
	if not enemy and tabletop_selected_hand != null:
		var selected := tabletop_selected_hand
		tabletop_selected_hand = null
		if is_instance_valid(card_inspector): card_inspector.hide()
		if _my_hand().has(selected): _on_card_drag_summoned(selected,null,index)
		return
	var targeting := summon_targeting or activate_targeting or cast_targeting or parasite_targeting or current_attacker_idx != -1
	if enemy: _on_enemy_slot_clicked(index)
	else: _on_player_slot_clicked(index)
	if targeting: return
	var card: CardData = _their_field().slots[index] if enemy else _my_field().slots[index]
	if card == null: return
	var slot: Control = enemy_side_ui.get_child(index) if enemy else player_side_ui.get_child(index)
	_show_card_details(card,enemy,index,slot)

func tabletop_hand_inspect(source: Control) -> void:
	if source.get_meta("tabletop_arriving",false): return
	_show_card_details(source.current_card_data,false,-1,source,source)

func _show_card_details(card: CardData, enemy: bool, index: int, slot: Control, hand_source: Control = null, preview_only: bool = false, popup_parent: Node = null) -> void:
	if is_instance_valid(card_inspector): card_inspector.queue_free()
	_inspector_action_refresh = Callable()
	card_inspector = PanelContainer.new()
	card_inspector.name = "TabletopCardInspector"
	card_inspector.add_to_group("battle_modal")
	card_inspector.set_meta("suppress_hover_hint",true)
	card_inspector.set_meta("turn",game.current_player)
	card_inspector.set_meta("friendly_slot", index if not enemy and hand_source == null else -1)
	var parent_node: Node = $CanvasLayer
	var detail_layer: CanvasLayer
	if popup_parent is CanvasLayer:
		var popup := UITheme.make_popup_layer(popup_parent, popup_parent.layer + 1)
		detail_layer = popup.layer
		detail_layer.name = "CollectionCardDetails"
		detail_layer.set_meta("popup_close", detail_layer.queue_free)
		var shade: ColorRect = popup.bg
		shade.color.a = 0.24
		shade.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				detail_layer.queue_free())
		parent_node = detail_layer
	elif popup_parent != null:
		parent_node = popup_parent
	parent_node.add_child(card_inspector)
	if detail_layer != null:
		var details := card_inspector
		details.visibility_changed.connect(func():
			if not details.visible:
				detail_layer.queue_free())
		details.tree_exiting.connect(func():
			if not detail_layer.is_queued_for_deletion():
				detail_layer.queue_free())
	card_inspector.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var columns: BoxContainer = HBoxContainer.new() if get_viewport_rect().size.x >= 680 else VBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	card_inspector.add_child(columns)
	var main_panel := PanelContainer.new()
	if card.is_parasite(): main_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UITheme.apply_popup_frame(main_panel, "tooltip", false)
	columns.add_child(main_panel)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,18)
	main_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 270
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",12)
	margin.add_child(box)
	var title := Label.new()
	title.set_meta("keyword_literal",true)
	title.text = card.card_name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_title(title, 22)
	box.add_child(title)
	var stats := Label.new()
	stats.text = Locale.t("tabletop.stats",[card.effective_atk(),card.hp,card.max_hp])
	UITheme.apply_label(stats)
	box.add_child(stats)
	var descriptions := preload("res://presentation/SkillDescription.gd")
	var detail_frame := descriptions.make_abilities_frame()
	box.add_child(detail_frame)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation",12)
	detail_frame.add_child(detail_box)
	var attack: Button
	var deploy: Button
	var skill_actions: Dictionary[int, Button] = {}
	var skill_use_refreshers: Array[Callable] = []
	if not preview_only and not enemy and hand_source == null and game.battle_config.has("action_base"):
		attack = Button.new()
		attack.name = "TabletopAttack"
		attack.text = Locale.t("tabletop.attack")
		attack.gui_input.connect(func(event):
			_inspector_resource_input(event, attack.disabled, false,
				"tip.no_attack_turn1" if _opening_attack_blocked() else ""))
		attack.pressed.connect(func(): card_inspector.hide(); _on_attack_requested(index))
		detail_box.add_child(attack)
		UITheme.apply_button(attack,"secondary",false)
	if not card.is_spell() and not card.is_parasite():
		detail_box.add_child(descriptions.build_basic_attack(card.effective_atk(), _is_party_battle()))
	if not preview_only and not enemy and hand_source == null:
		var payment: Dictionary = game.next_action_payment()
		var price := Label.new()
		price.name = "ActionPaymentLabel"
		price.text = ("消耗 %d 行动和 %d 圣水" if Locale.language == "zh" else "Costs %d AP and %d Elixir") % [payment.points,payment.mana]
		UITheme.apply_label(price)
		if not payment.ok: price.add_theme_color_override("font_color",UITheme.COLOR_ENEMY)
		detail_box.add_child(price)
	var skill_box: VBoxContainer
	if not card.skills.is_empty() and not card.is_parasite():
		var skill_section := VBoxContainer.new()
		skill_section.add_theme_constant_override("separation", 0)
		detail_box.add_child(skill_section)
		if not card.is_spell():
			var boundary := HSeparator.new()
			boundary.add_theme_constant_override("separation", 1)
			UITheme.apply_separator(boundary)
			skill_section.add_child(boundary)
		skill_box = VBoxContainer.new()
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0,minf(220,get_viewport_rect().size.y*0.28))
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		skill_section.add_child(scroll)
		skill_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_box.add_theme_constant_override("separation",8)
		scroll.add_child(skill_box)
	for i in range(card.skills.size()):
		if card.is_parasite(): break
		var skill: Dictionary = card.skills[i]
		if skill.is_empty(): continue
		if skill_box.get_child_count()>0:
			skill_box.add_child(descriptions.make_skill_separator(i))
		var button := Button.new()
		button.name = "TabletopSkill%d" % i
		button.set_meta("keyword_literal",true)
		button.text = SkillTextFormatter.skill_display_name(skill,i)
		button.disabled = preview_only or enemy
		skill_actions[i] = button
		button.gui_input.connect(func(event):
			_inspector_resource_input(event, button.disabled, enemy or preview_only or hand_source != null,
				_opening_skill_block_reason(skill)))
		button.pressed.connect(func():
			card_inspector.hide()
			if hand_source != null:
				if is_instance_valid(hand_source): _tabletop_use_hand_skill(hand_source,i)
			else: _on_skill_activated(index,i)
		)
		skill_box.add_child(button)
		var description := descriptions.build_battle_skill(card, i, skill_use_refreshers)
		skill_box.add_child(description)
	if hand_source != null and not card.is_spell() and not preview_only:
		deploy = Button.new()
		deploy.name = "TabletopDeploy"
		deploy.text = ("依附" if card.is_parasite() else "部署") if Locale.language == "zh" else ("Attach" if card.is_parasite() else "Deploy")
		deploy.pressed.connect(func():
			card_inspector.hide()
			if card.is_parasite(): _tabletop_use_hand_skill(hand_source)
			else: tabletop_selected_hand = card
		)
		box.add_child(deploy)
	if card.is_parasite(): detail_frame.hide()
	if skill_box != null: UITheme.theme_tree(skill_box)
	var close := Button.new()
	close.text = Locale.t("common.close")
	close.pressed.connect(card_inspector.hide)
	box.add_child(close)
	var state_panel := preload("res://presentation/CardStatePanel.gd").build(card, skill_use_refreshers)
	if state_panel != null:
		columns.add_child(state_panel)
	var pos := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	pos = slot.global_position+Vector2(slot.size.x+12,0)
	card_inspector.position = Vector2(clampf(pos.x,8,viewport_size.x-330),clampf(pos.y,55,viewport_size.y-box.get_combined_minimum_size().y-48))
	# Keep the inspector above the raised card without sending the card below the HUD.
	card_inspector.z_index = 54
	for child in box.get_children():
		if child is Button: UITheme.apply_button(child,"secondary")
	card_inspector.reset_size()
	card_inspector.position = Vector2(clampf(pos.x,8,viewport_size.x-card_inspector.size.x-8),clampf(pos.y,8,maxf(8,viewport_size.y-card_inspector.size.y-8)))
	card_inspector.show()
	if not preview_only:
		var in_hand := hand_source != null
		_inspector_action_refresh = func(can_act: bool):
			var current := card
			var readiness := {}
			if in_hand:
				if not is_instance_valid(hand_source) or hand_source.current_card_data != card or not _my_hand().has(card):
					card_inspector.hide()
					return
			else:
				current = (_their_field() if enemy else _my_field()).slots[index]
				if current == null or (current != card and (card.instance_id.is_empty() or current.instance_id != card.instance_id)):
					card_inspector.hide()
					return
				if can_act and not enemy:
					readiness = game.unit_action_readiness(index)
			for refresh in skill_use_refreshers:
				refresh.call(current)
			if attack != null:
				attack.disabled = not readiness.get("attack", false)
				attack.tooltip_text = Locale.t("tip.no_attack_turn1") if _opening_attack_blocked() else ""
			for skill_index in skill_actions:
				var skill_available: bool = card.is_spell() if in_hand else skill_index in readiness.get("skills", [])
				skill_actions[skill_index].disabled = enemy or not can_act or not skill_available
				if not in_hand and not enemy:
					var reason := _opening_skill_block_reason(current.skills[skill_index])
					skill_actions[skill_index].tooltip_text = Locale.t(reason) if not reason.is_empty() else ""
			if deploy != null:
				deploy.disabled = not can_act
		_update_inspector_actions(true)
	_fit_card_inspector.call_deferred(pos)
	if detail_layer == null:
		UIMotion.register_popup(card_inspector)
	else:
		UIMotion.register_popup(detail_layer, close)


func _opening_attack_blocked() -> bool:
	return game.turn_number <= 1 and not game.allow_first_turn_attacks


func _opening_skill_block_reason(skill: Dictionary) -> String:
	if game.turn_number <= 1 and skill.get("trigger") == SkillEngine.TRIGGER_ON_ACTIVATE \
			and SkillRegistry.skill_changes_enemy_hp_or_presence(skill):
		return "tip.no_enemy_hp_effect_turn1"
	return ""


func _update_inspector_actions(force: bool = false) -> void:
	if not _inspector_action_refresh.is_valid() or not is_instance_valid(card_inspector) or not card_inspector.visible:
		return
	var can_act := is_my_turn()
	if force or can_act != _inspector_can_act:
		_inspector_can_act = can_act
		_inspector_action_refresh.call(can_act)

func tabletop_hand_hover(source: Control, hovered: bool) -> void:
	if hovered:
		_resource_hover_card = source.current_card_data
	elif _resource_hover_card == source.current_card_data:
		_resource_hover_card = null
	_refresh_resource_preview()

func _refresh_resource_preview() -> void:
	_refresh_end_turn_damage_preview()
	var hud: Node = player_status_hud.get_node("Margin/Content")
	var field := _my_field()
	var card := _resource_hover_card
	var dragged: Variant = get_viewport().gui_get_drag_data()
	if dragged is Dictionary and dragged.get("card_data") is CardData:
		card = dragged.card_data
	var active := card != null and is_my_turn() and _my_hand().has(card)
	var mana_cost := maxi(0,card.cost) if active else 0
	var points_cost := 0
	if is_my_turn() and (current_attacker_idx != -1 or activate_targeting):
		var payment: Dictionary = game.next_action_payment()
		mana_cost = int(payment.mana)
		points_cost = int(payment.points)
		active = true
	# Playing a hand card costs Elixir only. Unit actions use a separate payment.
	var insufficient := active and mana_cost > field.get_total_mana()
	preload("res://presentation/ResourceCostPreview.gd").update(hud.get_node("ManaBar"),mana_cost,field.get_total_mana(),insufficient)
	preload("res://presentation/ResourceCostPreview.gd").update(hud.get_node("ActionBar"),points_cost,field.action_points,insufficient)


func _process(delta: float) -> void:
	super._process(delta)
	if tabletop == null: return
	_update_inspector_actions()
	_refresh_resource_preview()
	_sync_card_outlines()
	_refresh_target_prediction()
	for overlay in _hand_focus_overlays.values():
		overlay.face.hide()
		overlay.shadow.hide()
	var dragged: Variant = get_viewport().gui_get_drag_data()
	var enemy_drag := int(dragged.get("enemy_swap_source", -1)) if dragged is Dictionary else -1
	if enemy_drag != _swapping_enemy_slot:
		if is_instance_valid(_enemy_drag_root):
			_enemy_drag_root.show()
		_enemy_drag_root = null
		_swapping_enemy_slot = enemy_drag
		if enemy_drag >= 0 and tabletop.cards.has(enemy_drag + 5):
			_enemy_drag_root = tabletop.cards[enemy_drag + 5].root
			_enemy_drag_root.hide()
	_reindex_tabletop_hand()
	var needs_hand_lighting := false
	for i in range(hand_container.get_child_count()):
		var card_ui: Control = hand_container.get_child(i)
		tabletop.sync_slot(card_ui,10+i,card_ui.current_card_data,false,false)
		if tabletop.cards.has(10+i):
			tabletop.cards[10+i].root.visible = not card_ui.get_meta("tabletop_arriving",false) and not (dragged is Dictionary and dragged.get("card_data") == card_ui.current_card_data)
			var entry: Dictionary = tabletop.cards[10+i]
			if entry.root.visible and card_ui.get_meta("hand_foreground",false):
				var points := _hand_face_points(entry)
				var bounds := Rect2(points[0],Vector2.ZERO)
				for point in points: bounds = bounds.expand(point)
				if card_ui.get_meta("hand_focused",false) or card_ui.get_meta("hand_returning",false) or _hand_lift_phase(entry,card_ui)>.015 or bounds.intersects(player_status_hud.get_global_rect()):
					_sync_hand_focus_overlay(entry,card_ui,points)
					needs_hand_lighting = true
				else: card_ui.set_meta("hand_foreground",false)
		card_ui.modulate.a = 0
		if not card_ui.has_node("TabletopHandInput"):
			for hidden in card_ui.find_children("*","Control",true,false): hidden.focus_mode = Control.FOCUS_NONE
			var input := HandInput.new()
			input.name = "TabletopHandInput"
			input.battle = self
			input.source = card_ui
			input.focus_mode = Control.FOCUS_ALL
			input.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			card_ui.add_child(input)
			card_ui.move_child(input,card_ui.get_child_count()-1)
	tabletop.remove_hand_after(hand_container.get_child_count())
	# Only the raised hand overlays sample the pre-HUD screen texture.
	_hand_lighting_buffer.visible = needs_hand_lighting

func _hand_face_points(entry: Dictionary) -> PackedVector2Array:
	var quad: QuadMesh = entry.top.mesh
	var points := PackedVector2Array()
	for corner in [Vector2(-1,1),Vector2(1,1),Vector2(1,-1),Vector2(-1,-1)]:
		var world: Vector3 = entry.top.global_transform*Vector3(corner.x*quad.size.x*0.5,corner.y*quad.size.y*0.5,0)
		points.append(tabletop.camera.unproject_position(world))
	return points


func _hand_lift_phase(entry: Dictionary,source: Control) -> float:
	var parent_transform: Transform2D = source.get_parent_control().get_global_transform()
	var rest: Vector2 = source.get_meta("hand_rest_position",source.position)
	var rest_center: Vector2 = parent_transform*(rest+source.size*.5)
	var rise: float = (32.0*source.size.x/120.0+source.size.y*.08)*parent_transform.y.length()
	var shown_center: Vector2 = tabletop.camera.unproject_position(entry.top.global_position)
	return clampf((rest_center.y-shown_center.y)/maxf(1.0,rise),0.0,1.0)

func _sync_hand_focus_overlay(entry: Dictionary, source: Control, points: PackedVector2Array) -> void:
	var id := source.get_instance_id()
	if not _hand_focus_overlays.has(id):
		var shadow := Polygon2D.new()
		shadow.color = Color(0,0,0,0.35)
		$CanvasLayer.add_child(shadow)
		var face := Polygon2D.new()
		var ink := ShaderMaterial.new()
		ink.shader = preload("res://presentation/HandLiftLighting.gdshader")
		face.material = ink
		$CanvasLayer.add_child(face)
		_hand_focus_overlays[id] = {"face":face,"shadow":shadow}
		source.tree_exiting.connect(func():
			if not _hand_focus_overlays.has(id): return
			_hand_focus_overlays[id].face.queue_free()
			_hand_focus_overlays[id].shadow.queue_free()
			_hand_focus_overlays.erase(id))
	var face: Polygon2D = _hand_focus_overlays[id].face
	var shadow: Polygon2D = _hand_focus_overlays[id].shadow
	face.z_index = 52 if source.get_meta("hand_focused",false) else 50
	(face.material as ShaderMaterial).set_shader_parameter("lift_phase",_hand_lift_phase(entry,source))
	shadow.z_index = face.z_index-1
	var texture: Texture2D = entry.top.material_override.albedo_texture
	face.texture = texture
	face.polygon = points
	var tex_size := texture.get_size()
	face.uv = PackedVector2Array([Vector2.ZERO,Vector2(tex_size.x,0),tex_size,Vector2(0,tex_size.y)])
	shadow.polygon = points
	shadow.position = Vector2(4,6)*_ui_scale()
	shadow.show()
	face.show()


func _sync_card_outlines() -> void:
	var swapping := _enemy_swap_is_pending()
	for side in [player_side_ui, enemy_side_ui]:
		for slot in side.get_children():
			var card: CardData = slot.current_card_data
			var color := Color.TRANSPARENT
			var key: int = slot.get_index() + (5 if side == enemy_side_ui else 0)
			var swap_hint := Color.TRANSPARENT
			if swapping and side == enemy_side_ui and slot._target_hint != "none":
				swap_hint = Color("f0c747") if slot._target_hint == "hover" else Color("40c8df")
			if card != null:
				if swap_hint.a > 0.0: color = swap_hint
				elif slot._lethal_hint: color = Color("ff5144")
				elif card.is_selectable() and card.has_taunt(): color = Color("d6ad58")
				elif slot._target_hint != "none": color = Color("f0c747") if slot._target_hint == "hover" else Color("40c8df")
			tabletop.set_card_outline(key, color)
			tabletop.set_swap_highlight(key, swap_hint if card == null else Color.TRANSPARENT)


func _prepare_hand_entry_ui(card_ui: Control, data: CardData) -> void:
	card_ui.set_meta("tabletop_proxy",true)
	card_ui.set_meta("suppress_hover_hint", true)
	super._prepare_hand_entry_ui(card_ui,data)


func _play_hand_card_enter_feedback(card_ui: Control) -> void:
	_finish_hand_arrival(card_ui)
	if tabletop == null:
		super._play_hand_card_enter_feedback(card_ui)
		return
	var key := 10+hand_container.get_children().find(card_ui)
	if tabletop.cards.has(key):
		tabletop.cards[key].root.position.y = tabletop.cards[key].target.y+0.25
		tabletop.cards[key].velocity = Vector3.ZERO


func _refresh_hand_ui() -> void:
	super._refresh_hand_ui()
	if tabletop != null: _sync_hand_faces.call_deferred()


func _sync_hand_faces() -> void:
	if tabletop == null: return
	_reindex_tabletop_hand()
	for i in range(hand_container.get_child_count()):
		var item: Control = hand_container.get_child(i)
		tabletop.sync_slot(item,10+i,item.current_card_data,false)

func _reindex_tabletop_hand() -> void:
	var values: Array = []
	for item in hand_container.get_children(): values.append(item.current_card_data)
	tabletop.reindex_hand(values)


func tabletop_hand_clicked(source: Control) -> void:
	# Inspecting never plays a card; drag/drop and explicit actions retain their paths.
	var card: CardData = source.current_card_data
	tabletop_selected_hand = null
	tabletop_hand_inspect(source)

func inspect_collection_card(card: CardData, source: Control, dialog: Node) -> void:
	_show_card_details(card,false,-1,source,null,true,dialog)

func _fit_card_inspector(pos: Vector2) -> void:
	if not is_instance_valid(card_inspector): return
	card_inspector.reset_size()
	var viewport_size := get_viewport_rect().size
	card_inspector.position = Vector2(clampf(pos.x,8,maxf(8,viewport_size.x-card_inspector.size.x-8)),clampf(pos.y,8,maxf(8,viewport_size.y-card_inspector.size.y-8)))


func _tabletop_use_hand_skill(source: Control, skill_index: int = 0) -> void:
	if not is_my_turn() or not is_instance_valid(source): return
	var index := _hand_index_of(source)
	if index < 0: return
	tabletop_selected_hand = null
	var card: CardData = source.current_card_data
	if card.is_spell(): _start_spell_cast_from_hand(index,skill_index)
	elif card.is_parasite(): _start_parasite_attach_from_hand(index)

func _apply_status_hud_theme(hud: Panel, enemy: bool, active: bool) -> void:
	if tabletop == null:
		super._apply_status_hud_theme(hud,enemy,active)
		return
	_style_tabletop_status_hud(hud)

func _style_tabletop_status_hud(hud: Panel) -> void:
	hud.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.COLOR_PANEL_DARK, 0.94), UITheme.Tokens.BORDER, 1, 4))
	var content: Node = hud.get_node("Margin/Content")
	for label_name in ["SideLabel","HpLabel","ManaLabel","HandLabel"]:
		content.get_node(label_name).add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	for pair in [["HpBar",BattleStatusHud.resource_color("生命")],["ManaBar",BattleStatusHud.resource_color("圣水")],["ActionBar",UITheme.COLOR_GOLD]]:
		var bar: ProgressBar = content.get_node(pair[0])
		var fill := UITheme.panel_style(pair[1],Color.TRANSPARENT,0,2)
		fill.set_content_margin_all(0)
		bar.add_theme_stylebox_override("fill",fill)
		bar.add_theme_stylebox_override("background", UITheme.panel_style(UITheme.COLOR_BG, Color.TRANSPARENT, 0, 2))


func _style_tabletop_ui() -> void:
	var status_surface := UITheme.panel_style(Color(UITheme.COLOR_PANEL_DARK, 0.94), UITheme.Tokens.BORDER, 1, 4)
	$CanvasLayer/MainBackground/MainLayout/MiddleInfoBar.add_theme_stylebox_override("panel", status_surface)
	hand_area.get_node("HandBackdrop").add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	for hud in [enemy_status_hud,player_status_hud]: _style_tabletop_status_hud(hud)
	for button in [end_turn_button,face_mana_button,help_btn,field_rules_btn,battle_settings_btn,battle_chat_button,action_log_button,_test_add_button]:
		if button == null: continue
		var primary: bool = button == end_turn_button
		for state in ["normal","hover","pressed","disabled"]:
			var color := UITheme.COLOR_PRIMARY if primary else UITheme.COLOR_BUTTON
			if state == "hover": color = UITheme.COLOR_PRIMARY_HOVER if primary else UITheme.COLOR_BUTTON_HOVER
			if state == "disabled": color = UITheme.Tokens.DISABLED
			var border := UITheme.COLOR_GOLD if primary else UITheme.Tokens.BORDER
			button.add_theme_stylebox_override(state, UITheme.panel_style(color, border, 1, 4))

	var selected := UITheme.panel_style(UITheme.COLOR_BUTTON_HOVER, UITheme.COLOR_GOLD, 1, 4)
	face_mana_button.add_theme_stylebox_override("pressed",selected)
	face_mana_button.add_theme_stylebox_override("hover_pressed",selected)

func _on_battle_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tabletop_selected_hand = null
		if is_instance_valid(card_inspector): card_inspector.hide()
	super._on_battle_background_gui_input(event)

func _table_key(player: int, index: int) -> int:
	return index+(0 if player == _view_player() else 5)

func _play_attack_feedback(player: int, source_slot: int, target_slot: int = -1) -> void:
	if not _playing_random_action and _defer_action_feedback(_play_attack_feedback.bind(player,source_slot,target_slot)):
		_random_attack_motion = {"kind":"attack_motion","player":player,"source_slot":source_slot,"target_slot":target_slot,"feedback_group":0}
		return
	if not _playing_random_action and (_random_feedback_pending>0 or not _random_unbatched_events.is_empty()): return
	if tabletop == null:
		super._play_attack_feedback(player,source_slot,target_slot)
		return
	_show_unit_action_splash(player,source_slot)
	var key := _table_key(player,source_slot)
	var direction := Vector3(0,0,-1 if player == _view_player() else 1)
	var target_key := _table_key(_opponent_of_player(player), target_slot) if target_slot >= 0 else -1
	AppAudio.play("swoosh")
	tabletop.strike(key, target_key, direction)

func _show_combat_feedback_for(player: int, slot: int, delta: int, zero_damage: bool = false) -> void:
	if tabletop == null or delta > 0:
		super._show_combat_feedback_for(player, slot, delta, zero_damage)
		return
	if (delta == 0 and not zero_damage) or slot not in range(5):
		return
	var slot_ui := _slot_ui_for_player(player, slot)
	if slot_ui == null:
		return
	var center := slot_ui.get_global_rect().get_center()
	var key := _table_key(player, slot)
	if tabletop.cards.has(key):
		center = tabletop.camera.unproject_position(tabletop.cards[key].top.global_position)
	var strong := delta <= -4
	var tint := Color(0.85, 0.69, 0.49, 0.85) if delta < 0 else Color(0.69, 0.75, 0.76, 0.70)
	BattleFx.impact_ring($CanvasLayer, center, delta < 0, tint, _ui_scale() * (0.85 if strong else 0.60))
	BattleFx.combat_text($CanvasLayer, center, delta, strong, _ui_scale(), zero_damage)
	if delta < 0:
		tabletop.receive_hit(key, -delta)
		AppAudio.play("heavy" if strong else "hurt")
	else:
		AppAudio.play("blocked")

func _play_summon_feedback(slot_ui: Control) -> void:
	if tabletop == null:
		super._play_summon_feedback(slot_ui)
		return
	_begin_deployment_feedback()
	AppAudio.play("summon")
	var index := _my_slots_ui().find(slot_ui)
	if index >= 0: _show_unit_action_splash(_view_player(),index)
	else:
		index = _their_slots_ui().find(slot_ui)
		if index >= 0: _show_unit_action_splash(_opponent_player(),index)
	# New card instances enter the 3D spring above the table, never delaying rules.

func _play_move_feedback(player: int, source_slot: int, target_slot: int, reverse: bool = false) -> void:
	if tabletop != null: AppAudio.play("swoosh")
	if tabletop == null:
		super._play_move_feedback(player,source_slot,target_slot,reverse)
		return
	var source := _table_key(player,source_slot)
	var target := _table_key(player,target_slot)
	var first: Variant = tabletop.cards.get(source)
	var second: Variant = tabletop.cards.get(target)
	tabletop.cards.erase(source)
	tabletop.cards.erase(target)
	if first != null:
		first["travel"] = {"from":first.root.position,"age":0.0,"lift":0.4}
		tabletop.cards[target] = first
	if second != null:
		second["travel"] = {"from":second.root.position,"age":0.0,"lift":0.8}
		tabletop.cards[source] = second

func _play_skill_cast_feedback(player: int, slot: int, skill_index: int = -1) -> void:
	if _defer_action_feedback(_play_skill_cast_feedback.bind(player,slot,skill_index)): return
	if _defer_random_feedback(_play_skill_cast_feedback.bind(player,slot,skill_index)): return
	if _defer_deployment_feedback(_play_skill_cast_feedback.bind(player, slot, skill_index)): return
	super._play_skill_cast_feedback(player,slot,skill_index)
	if tabletop != null and slot >= 0: tabletop.impact(_table_key(player,slot),Vector3.ZERO,true)

func _show_toast(key: String, args := []) -> void:
	if key in ["tip.insufficient_mana","tip.insufficient_action"] and tabletop != null:
		var hud := player_status_hud.get_node("Margin/Content")
		var reject := preload("res://presentation/ResourceRejection.gd")
		if key == "tip.insufficient_mana": reject.play(hud.get_node("ManaBar"))
		else:
			var payment: Dictionary = game.next_action_payment()
			if int(payment.cost)>_my_field().action_points: reject.play(hud.get_node("ActionBar"))
			if int(payment.mana)>_my_field().get_total_mana(): reject.play(hud.get_node("ManaBar"))
		AppAudio.play("denied")
	super._show_toast(key,args)

func _inspector_resource_input(event: InputEvent, disabled: bool, read_only: bool, reason: String = "") -> void:
	if read_only or not disabled or not is_my_turn(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not reason.is_empty():
			_show_toast(reason)
		elif not game.can_pay_action():
			_show_toast("tip.insufficient_action")

func _play_hero_attack_feedback(player: int, source_slot: int) -> void:
	if tabletop == null:
		super._play_hero_attack_feedback(player,source_slot)
		return
	AppAudio.play("swoosh")
	tabletop.strike(_table_key(player, source_slot), -1, Vector3(0, 0, -1 if player == _view_player() else 1))

func _refresh_target_prediction() -> void:
	var targeting := current_attacker_idx >= 0 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting
	var signature := str([_prediction_target,targeting,current_attacker_idx,summon_targeting,summon_skill_idx,activate_skill_idx,cast_hand_index,cast_skill_index,parasite_hand_index,game.state_revision,game.current_player])
	if signature == _prediction_cache: return
	_prediction_cache = signature
	for key in _prediction_shown:
		_set_face_prediction(key,{})
	_prediction_shown.clear()
	if not targeting or _prediction_target < 0 or not is_my_turn(): return
	var enemy := _prediction_target >= 5
	var slot := _prediction_target % 5
	var target_player := _opponent_player() if enemy else _view_player()
	var field := _field_for_player(target_player)
	var target: CardData = field.slots[slot]
	if target == null or not target.is_selectable(): return
	var skill := _current_targeting_skill()
	if _prediction_is_random(skill): return
	var copy = game.copy_for_simulation()
	# Only the executed chain can make this prediction uncertain. Unrelated
	# random skills elsewhere on the board must not hide deterministic damage.
	var rng_before: int = copy.game_rng.state
	var hidden_information := {"used":false}
	copy.trace_callable = func(row: Dictionary):
		if row.get("event","") == "resolved" and row.get("effect","") in ["draw_cards","view_deck","view_discard"]:
			hidden_information.used = true
	var was_blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	var accepted := false
	if current_attacker_idx >= 0 and enemy:
		accepted = not copy.execute_attack(current_attacker_idx, slot, _skill_target_is_hostile(target_player)).is_empty()
	elif activate_targeting and _can_target_skill_slot(target_player, slot):
		accepted = copy.trigger_activate_skills(activate_source_slot,slot,activate_skill_idx,target_player)
	elif summon_targeting and _can_target_skill_slot(target_player, slot):
		copy.trigger_summon_skills(summon_source_slot,slot,summon_skill_idx,target_player)
		accepted = true
	elif cast_targeting and _can_target_skill_slot(target_player, slot):
		accepted = copy.cast_spell(cast_hand_index,cast_skill_index,slot,target_player)
	elif parasite_targeting:
		accepted = copy.attach_parasite(parasite_hand_index,target_player,slot)
	EventBus.set_block_signals(was_blocked)
	if not accepted or copy.game_rng.state != rng_before or hidden_information.used: return
	for key in range(10):
		var before: CardData = (game.player2_field if key >= 5 else game.player_field).slots[key%5] if _view_player()==1 else (game.player_field if key >= 5 else game.player2_field).slots[key%5]
		if before == null: continue
		var after: CardData = (copy.player_field if _view_player()==1 else copy.player2_field).slots[key%5] if key < 5 else (copy.player2_field if _view_player()==1 else copy.player_field).slots[key%5]
		var delta := {"shield":(after.temp_hp if after != null else 0)-before.temp_hp,"hp":(after.hp if after != null else 0)-before.hp,"atk":(after.effective_atk() if after != null else before.effective_atk())-before.effective_atk(),"effects":(after.status_effects.size()+after.parasite_cards.size() if after != null else 0)-before.status_effects.size()-before.parasite_cards.size()}
		if int(delta.hp)!=0 or int(delta.atk)!=0 or int(delta.effects)!=0 or int(delta.shield)!=0:
			_set_face_prediction(key,delta)
			_prediction_shown.append(key)

func _set_face_prediction(key: int, value: Dictionary) -> void:
	if not tabletop.cards.has(key): return
	var entry: Dictionary = tabletop.cards[key]
	if not entry.face.has_method("set_prediction"): return
	entry.face.set_prediction(value)
	tabletop.queue_face_bake(entry)

func _prediction_is_random(value: Variant) -> bool:
	if value is CardData:
		return value.skill_activation_probability(100)<100 or _prediction_is_random(value.skills) or _prediction_is_random(value.parasite_cards)
	if value is Dictionary:
		if value.get("effect","") in ["draw_cards","clone_enemy","clone_random"]: return true
		if int(value.get("probability",100)) < 100 or int(value.get("random_count",0)) > 0 or value.get("op","")=="rand" or value.has("value_min"): return true
		for nested in value.values():
			if _prediction_is_random(nested): return true
	elif value is Array:
		for nested in value:
			if _prediction_is_random(nested): return true
	return false

func cancel_pending_battle_selection() -> bool:
	var had_pending_placement := tabletop_selected_hand != null
	tabletop_selected_hand = null
	return super.cancel_pending_battle_selection() or had_pending_placement


func cancel_attack() -> void:
	super.cancel_attack()
	_prediction_cache = ""
	if tabletop == null: return
	for key in _prediction_shown: _set_face_prediction(key,{})
	_prediction_shown.clear()

func _on_viewport_size_changed() -> void:
	super._on_viewport_size_changed()
	# Container anchors settle after size_changed; project the final rectangles.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and tabletop != null: _sync_tabletop()
