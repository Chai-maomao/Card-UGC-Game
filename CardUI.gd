extends Control

const _TextFormatter = preload("res://SkillTextFormatter.gd")
const SpellRules = preload("res://SpellRules.gd")

signal attack_requested
signal skill1_requested
signal skill2_requested
signal skill3_requested

@onready var background_panel = $Background
@onready var card_surface = $CardSurface
@onready var type_accent = $TypeAccent
@onready var type_label = $TypeLabel
@onready var name_label = $NameLabel
@onready var cost_label = $CostLabel
@onready var gender_label = $GenderLabel
@onready var hp_label = $HpLabel
@onready var atk_label = $AtkLabel
@onready var action_buttons = $ActionButtons
@onready var normal_atk_btn = $ActionButtons/NormalAtkButton
@onready var skill1_btn = $ActionButtons/Skill1Button
@onready var skill2_btn = $ActionButtons/Skill2Button
@onready var skill3_btn = $ActionButtons/Skill3Button

var current_card_data: CardData = null
var buff_dots: HBoxContainer
var silence_label: Label
var ui_scale: float = 1.0
var _is_layout_applying: bool = false
# Intent behind action_buttons visibility (true = show in battle): silence
# temporarily overrides it, and set_card restores it once the silence expires.
var _actions_visible: bool = true


func _scaled_rect(left: float, top: float, right: float, bottom: float) -> void:
	offset_left = left * ui_scale
	offset_top = top * ui_scale
	offset_right = right * ui_scale
	offset_bottom = bottom * ui_scale


func _scale_child_rect(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	if control == null:
		return
	control.offset_left = left * ui_scale
	control.offset_top = top * ui_scale
	control.offset_right = right * ui_scale
	control.offset_bottom = bottom * ui_scale


func apply_ui_scale(scale_value: float) -> void:
	ui_scale = scale_value
	_is_layout_applying = true
	custom_minimum_size = Vector2(120, 160) * ui_scale
	size = custom_minimum_size
	_scaled_rect(0, 0, 120, 160)
	if background_panel:
		background_panel.custom_minimum_size = custom_minimum_size
		background_panel.size = custom_minimum_size
	_scale_child_rect($Background, 0, 0, 120, 160)
	_scale_child_rect(card_surface, 0, 0, 120, 160)
	_scale_child_rect(type_accent, 6, 27, 114, 29)
	_scale_child_rect(type_label, 62, 26, 114, 40)
	var is_special_card := current_card_data != null and (current_card_data.is_spell() or current_card_data.is_parasite())
	if is_special_card:
		_scale_child_rect(name_label, 6, 4, 114, 22)
		_scale_child_rect(cost_label, 6, 26, 58, 40)
		_scale_child_rect(gender_label, 72, 24, 114, 40)
		_scale_child_rect(hp_label, 6, 42, 94, 72)
		_scale_child_rect(atk_label, 6, 58, 94, 72)
		_scale_child_rect(action_buttons, 6, 82, 114, 158)
	else:
		_scale_child_rect(name_label, 6, 4, 114, 22)
		_scale_child_rect(cost_label, 6, 26, 58, 40)
		_scale_child_rect(gender_label, 72, 24, 114, 40)
		_scale_child_rect(hp_label, 6, 42, 94, 56)
		_scale_child_rect(atk_label, 6, 58, 94, 72)
		_scale_child_rect(action_buttons, 6, 82, 114, 158)
	if name_label:
		name_label.add_theme_font_size_override("font_size", max(10, int(13 * ui_scale)))
	if gender_label:
		gender_label.add_theme_font_size_override("font_size", max(8, int(10 * ui_scale)))
	if type_label:
		type_label.add_theme_font_size_override("font_size", max(7, int(8 * ui_scale)))
	for label in [cost_label, hp_label, atk_label]:
		if label:
			label.add_theme_font_size_override("font_size", max(9, int(11 * ui_scale)))
	# Action buttons are compact chips; a slightly smaller font keeps 4 stacked
	# buttons (basic attack + 3 skills) inside the ~76px action column.
	for button in [normal_atk_btn, skill1_btn, skill2_btn, skill3_btn]:
		if button:
			button.add_theme_font_size_override("font_size", max(9, int(10 * ui_scale)))
	if action_buttons:
		action_buttons.add_theme_constant_override("separation", max(1, int(2 * ui_scale)))
	if buff_dots:
		buff_dots.position = Vector2(6, 74) * ui_scale
		buff_dots.add_theme_constant_override("separation", max(1, int(2 * ui_scale)))
	if silence_label:
		silence_label.position = Vector2(6, 140) * ui_scale
		silence_label.add_theme_font_size_override("font_size", max(10, int(13 * ui_scale)))
	_apply_card_visual_style()
	_update_card_layout_for_type()
	_is_layout_applying = false


func _apply_card_visual_style() -> void:
	if background_panel:
		var card_type := current_card_data.card_type if current_card_data != null else "minion"
		UITheme.apply_card_surface(background_panel, card_type, ui_scale)
	for label in [name_label, cost_label, hp_label, atk_label]:
		if label:
			label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
			label.add_theme_constant_override("shadow_offset_x", max(1, int(1 * ui_scale)))
			label.add_theme_constant_override("shadow_offset_y", max(1, int(1 * ui_scale)))
	if name_label:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72))
	for label in [cost_label, hp_label, atk_label]:
		if label:
			label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	if gender_label:
		gender_label.add_theme_color_override("font_color", Color(0.78, 0.86, 1.0))
		gender_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
		gender_label.add_theme_constant_override("shadow_offset_x", max(1, int(1 * ui_scale)))
		gender_label.add_theme_constant_override("shadow_offset_y", max(1, int(1 * ui_scale)))
	if type_accent:
		var accent := UITheme.COLOR_GOLD
		if current_card_data != null and current_card_data.is_spell():
			accent = UITheme.COLOR_ARCANE
		elif current_card_data != null and current_card_data.is_parasite():
			accent = Color(0.68, 0.38, 0.78)
		type_accent.color = accent
	if type_label:
		UITheme.apply_label(type_label, true)
	if normal_atk_btn:
		UITheme.apply_button(normal_atk_btn, "primary")
	for button in [skill1_btn, skill2_btn, skill3_btn]:
		if button:
			UITheme.apply_button(button)
	# Action buttons are compact chips stacked in a fixed-height column. Shrink
	# their vertical padding so up to 4 buttons (basic attack + 3 skills) fit
	# the ~76px action area without pushing any button past the card bounds.
	var chip_margin: int = max(1, int(1 * ui_scale))
	for button in [normal_atk_btn, skill1_btn, skill2_btn, skill3_btn]:
		if button == null:
			continue
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			var style := button.get_theme_stylebox(style_name) as StyleBoxFlat
			if style != null:
				style.content_margin_top = chip_margin
				style.content_margin_bottom = chip_margin


func _ready():
	# Buff indicator dots
	buff_dots = HBoxContainer.new()
	buff_dots.add_theme_constant_override("separation", 2)
	buff_dots.position = Vector2(6, 74)
	add_child(buff_dots)

	# Silence indicator
	silence_label = Label.new()
	silence_label.text = Locale.t("card.silenced")
	silence_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	silence_label.add_theme_font_size_override("font_size", 13)
	silence_label.position = Vector2(6, 140)
	silence_label.visible = false
	add_child(silence_label)

	if normal_atk_btn:
		normal_atk_btn.pressed.connect(func(): attack_requested.emit())
		normal_atk_btn.tooltip_text = Locale.t("card.basic_attack")
	if skill1_btn:
		skill1_btn.pressed.connect(func(): skill1_requested.emit())
	if skill2_btn:
		skill2_btn.pressed.connect(func(): skill2_requested.emit())
	if skill3_btn:
		skill3_btn.pressed.connect(func(): skill3_requested.emit())

	_auto_hide_if_enemy()
	if current_card_data != null:
		set_card(current_card_data)
	else:
		apply_ui_scale(ui_scale)


func set_card(card_data: CardData):
	current_card_data = card_data

	if card_data == null:
		if name_label: name_label.text = ""
		if cost_label: cost_label.text = ""
		if gender_label: gender_label.text = ""
		if hp_label: hp_label.text = ""
		if atk_label: atk_label.text = ""
		if action_buttons: action_buttons.visible = false
		if silence_label: silence_label.visible = false
		self.modulate = Color.WHITE
		_clear_buff_dots()
		return

	_update_card_layout_for_type()
	if name_label:
		name_label.text = card_data.card_name
	if gender_label:
		gender_label.text = ""
	if type_label:
		type_label.text = _card_type_text(card_data)
	if card_data.is_charmed():
		if cost_label:
			cost_label.text = Locale.t("card.cost_charmed")
			cost_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))  # green for charmed
	else:
		if cost_label:
			cost_label.text = Locale.t("card.cost", [card_data.cost])
			cost_label.add_theme_color_override("font_color", Color.WHITE)

	# HP: show current/max, plus temp HP if any
	if card_data.temp_hp > 0:
		if hp_label:
			hp_label.text = Locale.t("card.hp_temp", [card_data.hp, card_data.max_hp, card_data.temp_hp])
	else:
		if hp_label:
			hp_label.text = Locale.t("card.hp", [card_data.hp, card_data.max_hp])

	# ATK: show effective, plus bonus — hidden for spell cards (no body)
	if card_data.is_spell():
		if hp_label:
			hp_label.text = ""
		if atk_label:
			atk_label.text = ""
	elif card_data.is_parasite():
		if hp_label:
			hp_label.text = Locale.t("card.parasite_hp", [card_data.hp, card_data.max_hp])
		if atk_label:
			atk_label.text = Locale.t("card.parasite_atk", [card_data.atk])
	else:
		if hp_label:
			hp_label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
		var eff_atk: int = card_data.effective_atk()
		var bonus: int = eff_atk - card_data.atk
		if bonus > 0:
			if atk_label:
				atk_label.text = Locale.t("card.atk_bonus", [eff_atk, bonus])
		else:
			if atk_label:
				atk_label.text = Locale.t("card.atk", [eff_atk])

	_update_buff_dots()
	_update_skill_buttons()
	if card_data.is_spell() and card_data.skills.size() > 0:
		tooltip_text = _TextFormatter.format_skill_tooltip(SpellRules.spell_skill(card_data))
	elif card_data.is_parasite():
		tooltip_text = Locale.t("card.parasite_tooltip", [card_data.hp, card_data.atk])
	else:
		tooltip_text = _parasite_tooltip(card_data)
	if silence_label:
		silence_label.visible = card_data.is_silenced()
	if action_buttons:
		action_buttons.visible = _actions_visible and not card_data.is_silenced()
	self.modulate = Color(0.5, 0.5, 0.5) if card_data.is_silenced() else Color.WHITE
	_auto_hide_if_enemy()


func _update_card_layout_for_type() -> void:
	var is_special_card := current_card_data != null and (current_card_data.is_spell() or current_card_data.is_parasite())
	if gender_label:
		gender_label.visible = false
		gender_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if hp_label:
		hp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if is_special_card else TextServer.AUTOWRAP_OFF
		hp_label.clip_text = not is_special_card
		hp_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if normal_atk_btn:
		normal_atk_btn.visible = not is_special_card
	if skill2_btn and is_special_card:
		skill2_btn.visible = false
	if skill3_btn and is_special_card:
		skill3_btn.visible = false
	if not _is_layout_applying:
		apply_ui_scale(ui_scale)


func _card_type_text(card_data: CardData) -> String:
	if card_data.is_spell():
		return Locale.t("card.spell")
	if card_data.is_parasite():
		return Locale.t("card.parasite")
	return _gender_text(card_data.gender)


func _clear_buff_dots():
	if buff_dots == null:
		return
	for child in buff_dots.get_children():
		child.queue_free()


func _update_buff_dots():
	if buff_dots == null or current_card_data == null:
		return
	_clear_buff_dots()
	for eff in current_card_data.status_effects:
		var val: int = eff.get("value", 0)
		if val <= 0:
			continue
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10) * ui_scale
		if eff.get("buff_id", "") == SkillEngine.BUFF_TAUNT:
			dot.color = Color(0.3, 0.5, 1.0)  # blue for taunt
		elif eff.get("buff_id", "") == SkillEngine.BUFF_SILENCE:
			dot.color = Color(0.9, 0.2, 0.2)  # red for silence
		elif eff.get("buff_id", "") == SkillEngine.BUFF_MANA_REFUND:
			dot.color = Color(0.2, 0.8, 1.0)
		elif eff.get("buff_id", "") == SkillEngine.BUFF_MISFORTUNE:
			dot.color = Color(0.3, 0.3, 0.3)  # dark grey for misfortune
		elif eff.get("buff_id", "") == SkillEngine.BUFF_POISON:
			dot.color = Color(0.7, 0.4, 0.85)  # purple for poison
		elif eff.get("buff_id", "") == SkillEngine.BUFF_STUN:
			dot.color = Color(0.95, 0.9, 0.35)  # yellow for stun
		else:
			dot.color = Color.GREEN
		dot.tooltip_text = _format_buff_tooltip(eff)
		buff_dots.add_child(dot)
	for parasite in current_card_data.parasite_cards:
		if not parasite is CardData:
			continue
		var p: CardData = parasite
		if p.skills.is_empty():
			continue
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10) * ui_scale
		dot.color = Color(1.0, 0.74, 0.18)
		dot.tooltip_text = _format_parasite_passive_tooltip(p)
		buff_dots.add_child(dot)


func _format_parasite_passive_tooltip(parasite: CardData) -> String:
	var lines: Array = [Locale.t("card.parasite_passive_marker", [parasite.card_name])]
	for skill in parasite.skills:
		if skill is Dictionary:
			lines.append(_TextFormatter.format_skill_tooltip(skill))
	return "\n\n".join(lines)


func _format_buff_tooltip(eff: Dictionary) -> String:
	var bid: String = eff.get("buff_id", "")
	var val: int = eff.get("value", 0)
	var dur: int = eff.get("duration", 0)
	var name: String = Locale.term("buff", bid)
	var detail := SkillEngine.format_buff_value(bid, str(val))
	return Locale.t("card.buff_tooltip_detail", [name, detail, dur])


func _parasite_tooltip(card_data: CardData) -> String:
	if card_data == null or card_data.parasite_cards.is_empty():
		return ""
	var parts: Array = []
	for parasite in card_data.parasite_cards:
		if parasite is CardData:
			parts.append(Locale.t("card.parasite_attached_item", [parasite.card_name, parasite.hp, parasite.max_hp, parasite.atk]))
	return Locale.t("card.parasite_attached", ["\n".join(parts)])


func _gender_text(gender: String) -> String:
	match gender:
		"male":
			return Locale.t("editor.gender_male")
		"female":
			return Locale.t("editor.gender_female")
	return Locale.t("editor.gender_nonhuman")


func _update_skill_buttons():
	if current_card_data == null:
		return
	var silenced: bool = current_card_data.is_silenced()
	if current_card_data != null and current_card_data.is_parasite():
		if skill1_btn:
			if current_card_data.skills.size() >= 1:
				var s: Dictionary = current_card_data.skills[0]
				var sname: String = s.get("skill_name", "")
				skill1_btn.text = sname if sname != "" else Locale.t("mycards.skill_fallback", [1])
				skill1_btn.tooltip_text = _TextFormatter.format_skill_tooltip(s)
				skill1_btn.visible = true
			else:
				skill1_btn.visible = false
			skill1_btn.disabled = false
			skill1_btn.modulate = Color.WHITE
		if skill2_btn:
			skill2_btn.visible = false
		if skill3_btn:
			skill3_btn.visible = false
		return
	if skill1_btn:
		if current_card_data.skills.size() >= 1:
			var s: Dictionary = SpellRules.spell_skill(current_card_data) if current_card_data.is_spell() else current_card_data.skills[0]
			var sname: String = s.get("skill_name", "")
			# Spell cards show a generic "Cast" button instead of the skill name.
			if current_card_data.is_spell():
				skill1_btn.text = Locale.t("card.spell_cast")
			else:
				skill1_btn.text = sname if sname != "" else Locale.t("mycards.skill_fallback", [1])
			skill1_btn.tooltip_text = _TextFormatter.format_skill_tooltip(s)
			skill1_btn.visible = true
			_apply_skill_button_state(skill1_btn, s, 0)
		else:
			skill1_btn.visible = false

	if skill2_btn:
		if current_card_data.skills.size() >= 2:
			var s: Dictionary = current_card_data.skills[1]
			var sname: String = s.get("skill_name", "")
			if current_card_data.is_spell():
				skill2_btn.text = Locale.t("card.spell_cast")
			else:
				skill2_btn.text = sname if sname != "" else Locale.t("mycards.skill_fallback", [2])
			skill2_btn.tooltip_text = _TextFormatter.format_skill_tooltip(s)
			skill2_btn.visible = true
			_apply_skill_button_state(skill2_btn, s, 1)
		else:
			skill2_btn.visible = false
		if current_card_data.is_spell():
			skill2_btn.visible = false

	if skill3_btn:
		if current_card_data.skills.size() >= 3 and not current_card_data.is_spell():
			var s: Dictionary = current_card_data.skills[2]
			var sname: String = s.get("skill_name", "")
			skill3_btn.text = sname if sname != "" else Locale.t("mycards.skill_fallback", [3])
			skill3_btn.tooltip_text = _TextFormatter.format_skill_tooltip(s)
			skill3_btn.visible = true
			_apply_skill_button_state(skill3_btn, s, 2)
		else:
			skill3_btn.visible = false
		if current_card_data.is_spell():
			skill3_btn.visible = false

	# Silence: grey out all skill buttons and normal attack. When silence
	# expires the next set_card re-runs this method with silenced=false and
	# restores each button's proper state (see the else branch below).
	if silenced:
		for btn in [skill1_btn, skill2_btn, skill3_btn, normal_atk_btn]:
			if btn and btn.visible:
				btn.disabled = true
				btn.modulate = Color(0.5, 0.5, 0.5)
	else:
		if normal_atk_btn:
			normal_atk_btn.disabled = false
			normal_atk_btn.modulate = Color.WHITE
		if skill1_btn and skill1_btn.visible and current_card_data.skills.size() >= 1:
			var s1: Dictionary = SpellRules.spell_skill(current_card_data) if current_card_data.is_spell() else current_card_data.skills[0]
			_apply_skill_button_state(skill1_btn, s1, 0)
		if skill2_btn and skill2_btn.visible and current_card_data.skills.size() >= 2:
			_apply_skill_button_state(skill2_btn, current_card_data.skills[1], 1)
		if skill3_btn and skill3_btn.visible and current_card_data.skills.size() >= 3:
			_apply_skill_button_state(skill3_btn, current_card_data.skills[2], 2)


# Grey out + disable a skill button when its skill can't be activated now:
# already used this turn, an on_summon skill outside its summon turn, or an
# on_activate skill on a card that has already attacked.
func _apply_skill_button_state(btn: Button, skill: Dictionary, skill_index: int) -> void:
	var unavailable := false
	var trig: String = skill.get("trigger", "")
	if current_card_data.skills_used.has(skill_index):
		unavailable = true
	elif trig == SkillEngine.TRIGGER_ON_SUMMON and not current_card_data.summoned_this_turn:
		unavailable = true
	elif trig == SkillEngine.TRIGGER_ON_ACTIVATE and current_card_data.has_attacked:
		unavailable = true
	btn.disabled = unavailable
	btn.modulate = Color(0.5, 0.5, 0.5) if unavailable else Color.WHITE


func _auto_hide_if_enemy():
	pass  # 2P mode: buttons always visible


func set_actions_visible(visible: bool):
	_actions_visible = visible
	if action_buttons:
		action_buttons.visible = visible


func set_skill_preview_visible(visible: bool):
	_actions_visible = visible
	if action_buttons:
		action_buttons.visible = visible
	if normal_atk_btn:
		normal_atk_btn.visible = false
	if skill1_btn:
		skill1_btn.disabled = false
		skill1_btn.modulate = Color.WHITE
	if skill2_btn:
		skill2_btn.disabled = false
		skill2_btn.modulate = Color.WHITE
	if skill3_btn:
		skill3_btn.disabled = false
		skill3_btn.modulate = Color.WHITE


func _get_drag_data(_position: Vector2):
	if current_card_data == null:
		return null

	var preview_card = duplicate()
	preview_card.modulate.a = 0.6
	preview_card.anchor_right = 0.0
	preview_card.anchor_bottom = 0.0
	if preview_card.has_method("apply_ui_scale"):
		preview_card.call("apply_ui_scale", ui_scale)
	else:
		preview_card.offset_right = 120.0 * ui_scale
		preview_card.offset_bottom = 160.0 * ui_scale
	set_drag_preview(preview_card)

	return {
		"card_ui": self,
		"card_data": current_card_data
	}
