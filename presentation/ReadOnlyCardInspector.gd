extends RefCounted
static func show_card(parent: Node, card: CardData, source: Control) -> CanvasLayer:
	var popup := UITheme.make_popup_layer(parent, 130)
	var layer: CanvasLayer = popup.layer
	popup.bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: layer.queue_free())
	var panel := PanelContainer.new()
	panel.name = "TabletopCardInspector"
	UITheme.apply_popup_frame(panel, "dark", false)
	layer.add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	panel.add_child(columns)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = minf(360, parent.get_viewport().get_visible_rect().size.x-80)
	box.add_theme_constant_override("separation",12)
	columns.add_child(box)
	var title := Label.new()
	title.set_meta("keyword_literal",true)
	title.text = card.card_name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_title(title,22)
	box.add_child(title)
	if not card.is_spell():
		var stats := Label.new()
		stats.text = Locale.t("tabletop.stats",[card.effective_atk(),card.hp,card.max_hp])
		box.add_child(stats)
	var frame := PanelContainer.new()
	frame.name = "CardAbilitiesFrame"
	UITheme.apply_panel(frame,"soft")
	box.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = minf(220,parent.get_viewport().get_visible_rect().size.y*0.35)
	frame.add_child(scroll)
	var skills := VBoxContainer.new()
	skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills.add_theme_constant_override("separation",12)
	scroll.add_child(skills)
	if not card.is_spell() and not card.is_parasite():
		var attack := Label.new()
		attack.text = ("[普通攻击]\n对敌方造成%d点伤害" if Locale.language == "zh" else "[Basic attack]\nDeal %d damage to an enemy") % card.effective_atk()
		skills.add_child(attack)
	for i in range(card.skills.size()):
		if card.skills[i].is_empty(): continue
		var label := preload("res://presentation/SkillDescription.gd").build(SkillTextFormatter.format_skill_tooltip(card.skills[i],i))
		skills.add_child(label)
	var state_panel := preload("res://presentation/CardStatePanel.gd").build(card)
	if state_panel != null: columns.add_child(state_panel)
	var close := Button.new()
	close.text = Locale.t("common.close")
	UITheme.apply_button(close,"secondary",false)
	close.pressed.connect(layer.queue_free)
	box.add_child(close)
	UITheme.theme_tree(skills)
	panel.reset_size()
	var viewport := parent.get_viewport().get_visible_rect().size
	var origin := source.global_position+Vector2(source.size.x+12,0) if is_instance_valid(source) else viewport*0.5-panel.size*0.5
	panel.position = origin.clamp(Vector2(12,12),(viewport-panel.size-Vector2(12,12)).max(Vector2(12,12)))
	_fit.call_deferred(weakref(panel),weakref(skills),weakref(scroll),weakref(source))
	return layer

static func _fit(panel_ref: WeakRef, skills_ref: WeakRef, scroll_ref: WeakRef, source_ref: WeakRef) -> void:
	var panel: Control = panel_ref.get_ref()
	if panel == null or not panel.is_inside_tree(): return
	await panel.get_tree().process_frame
	await panel.get_tree().process_frame
	panel = panel_ref.get_ref()
	var skills: Control = skills_ref.get_ref()
	var scroll: ScrollContainer = scroll_ref.get_ref()
	if panel == null or skills == null or scroll == null: return
	scroll.custom_minimum_size.y = minf(skills.get_combined_minimum_size().y,minf(220,panel.get_viewport_rect().size.y*0.35))
	await panel.get_tree().process_frame
	panel = panel_ref.get_ref()
	if panel == null: return
	panel.reset_size()
	var viewport := panel.get_viewport_rect().size
	var source: Control = source_ref.get_ref()
	var origin := source.global_position+Vector2(source.size.x+12,0) if source != null else viewport*0.5-panel.size*0.5
	panel.position = origin.clamp(Vector2(12,12),(viewport-panel.size-Vector2(12,12)).max(Vector2(12,12)))
