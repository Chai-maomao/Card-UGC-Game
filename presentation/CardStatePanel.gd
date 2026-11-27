extends RefCounted

static func build(card: CardData, skill_use_refreshers: Array[Callable]) -> PanelContainer:
	var rows: Array[Array] = []
	var zh := Locale.language == "zh"
	if card.temp_hp > 0:
		rows.append(["护盾" if zh else "Shield", "+%d" % card.temp_hp, Locale.t("card.status_shield_expiry")])
	for effect in card.status_effects:
		var buff := str(effect.get("buff_id",""))
		var value := int(effect.get("value",0))
		if buff == SkillEngine.BUFF_IMMUNE_LETHAL or (value == 0 and buff != SkillEngine.BUFF_TAUNT):
			continue
		var detail := SkillTextFormatter.format_buff_value(buff, str(value)) if SkillRegistry.buff_uses_value(buff) else ""
		rows.append([Locale.term("buff", buff), detail, SkillTextFormatter.status_time_left(effect)])
	if card.immune_lethal:
		rows.append([Locale.term("buff", SkillEngine.BUFF_IMMUNE_LETHAL), Locale.t("card.status_lethal_detail"), Locale.t("card.status_lethal_once")])
	if card.turn_cost_reduction > 0:
		rows.append(["本回合费用降低" if zh else "Turn cost reduction", "−%d" % card.turn_cost_reduction,"回合结束到期" if zh else "Until turn end"])
	var attachment_row_begin := rows.size()
	for attachment in card.parasite_cards:
		rows.append([attachment.card_name,"HP %d/%d  ATK %d" % [attachment.hp,attachment.max_hp,attachment.effective_atk()],Locale.t("card.parasite_absorb_help") if attachment.parasite_absorbs_host_damage() else Locale.t("card.parasite_linked_help")])
	var has_own_parasite_skills := card.is_parasite() and not card.skills.is_empty()
	if rows.is_empty() and not has_own_parasite_skills: return null
	var panel := PanelContainer.new()
	panel.name = "CardStatePanel"
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UITheme.apply_popup_frame(panel, "dark", false)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 210
	box.add_theme_constant_override("separation",12)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "当前状态" if zh else "Current status"
	UITheme.apply_title(heading,20)
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(210,minf(300,panel.get_viewport_rect().size.y*0.4) if panel.is_inside_tree() else 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "StateList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12)
	scroll.add_child(list)
	if has_own_parasite_skills: _add_parasite_skills(list, card, skill_use_refreshers)
	for row_index in range(rows.size()):
		var row: Array = rows[row_index]
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation",4)
		list.add_child(entry)
		for i in range(row.size()):
			if row[i] == "": continue
			var label := Label.new()
			if i == 0 and row_index >= attachment_row_begin: label.set_meta("keyword_literal",true)
			label.text = row[i]
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UITheme.apply_label(label)
			if i == 0:
				label.add_theme_font_override("font",UITheme.bold_font())
				label.add_theme_font_size_override("font_size",18)
			elif i == 1: label.add_theme_color_override("font_color",UITheme.COLOR_GOLD)
			entry.add_child(label)
		if row_index>=attachment_row_begin:
			var attachment_index := row_index - attachment_row_begin
			_add_parasite_skills(entry, card.parasite_cards[attachment_index], skill_use_refreshers, attachment_index)
	return panel

static func _add_parasite_skills(parent: Control, parasite: CardData, refreshers: Array[Callable], attachment_index: int = -1) -> void:
	var box := VBoxContainer.new()
	box.name = "ParasiteSkills"
	box.add_theme_constant_override("separation",8)
	parent.add_child(box)
	for index in range(parasite.skills.size()):
		var skill: Dictionary = parasite.skills[index]
		if skill.is_empty(): continue
		box.add_child(preload("res://presentation/SkillDescription.gd").build_battle_skill(parasite, index, refreshers, attachment_index))
