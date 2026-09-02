extends Control

const _TextFormatter = preload("res://SkillTextFormatter.gd")
const SpellRules = preload("res://SpellRules.gd")

signal attack_requested
signal skill1_requested
signal skill2_requested
signal skill3_requested

@onready var background_panel = $Background
@onready var card_shadow = $CardShadow
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
var status_icons: HBoxContainer
var ui_scale: float = 1.0
var _is_layout_applying: bool = false
# Intent behind action_buttons visibility (true = show in battle): silence
# temporarily overrides it, and set_card restores it once the silence expires.
var _actions_visible: bool = true
# Hand cards (children of the hand container) grow on hover; field cards don't.
var is_hand_card: bool = false
var _hover_tween: Tween = null
var _pointer_inside := false
var _pointer_pressed := false
var _drag_source := false
var _surface_sheen: GradientTexture2D = null
# Layout caching: apply_ui_scale runs on every full-screen refresh for every
# card on screen (10 slots + hand). With unchanged scale AND card type the
# result is identical, so the 40+ rect overrides and 15+ theme overrides are
# skipped — a major chunk of the per-action frame cost.
var _last_layout_scale: float = -1.0
var _last_layout_type: String = ""
# Status badges: rebuilt from scratch on every set_card. The badge strip only
# changes when the (symbol, color, tooltip) content changes, so cache its
# signature and keep the existing nodes when it matches.
var _last_status_signature: String = ""
# Cost tint cache: _apply_hand_castability re-applies the same theme override
# on every refresh; skip it when the color is unchanged (invalid marker forces
# a re-apply after set_card resets the label color).
var _last_cost_color: Color = Color(-1.0, -1.0, -1.0, -1.0)


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
	var card_type := current_card_data.card_type if current_card_data != null else ""
	if is_equal_approx(_last_layout_scale, scale_value) and _last_layout_type == card_type and _last_layout_scale >= 0.0:
		# Same scale + same card type: the layout is already applied.
		ui_scale = scale_value
		return
	_last_layout_scale = scale_value
	_last_layout_type = card_type
	ui_scale = scale_value
	_is_layout_applying = true
	custom_minimum_size = Vector2(120, 160) * ui_scale
	size = custom_minimum_size
	_scaled_rect(0, 0, 120, 160)
	if background_panel:
		background_panel.custom_minimum_size = custom_minimum_size
		background_panel.size = custom_minimum_size
	# Leave a narrow physical rim around the card. This gives the surface shadow
	# a clean silhouette while its dedicated layer sits behind and below it.
	_scale_child_rect(card_shadow, 6, 8, 114, 164)
	_scale_child_rect($Background, 2, 1, 118, 157)
	# The sheen is inset past the border so its dark tail can never tint the
	# golden stroke drawn by Background.
	_scale_child_rect(card_surface, 4, 3, 116, 155)
	_scale_child_rect(type_accent, 6, 23, 114, 25)
	_scale_child_rect(type_label, 62, 26, 114, 40)
	var is_special_card := current_card_data != null and (current_card_data.is_spell() or current_card_data.is_parasite())
	if is_special_card:
		_scale_child_rect(name_label, 6, 4, 114, 22)
		_scale_child_rect(cost_label, 6, 26, 58, 40)
		_scale_child_rect(gender_label, 72, 24, 114, 40)
		_scale_child_rect(hp_label, 6, 42, 94, 72)
		_scale_child_rect(atk_label, 6, 58, 94, 72)
		_scale_child_rect(action_buttons, 6, 88, 114, 158)
	else:
		_scale_child_rect(name_label, 6, 4, 114, 22)
		_scale_child_rect(cost_label, 6, 26, 58, 40)
		_scale_child_rect(gender_label, 72, 24, 114, 40)
		_scale_child_rect(hp_label, 6, 42, 94, 56)
		_scale_child_rect(atk_label, 6, 58, 94, 72)
		_scale_child_rect(action_buttons, 6, 88, 114, 158)
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
	if status_icons:
		status_icons.position = Vector2(6, 73) * ui_scale
		status_icons.add_theme_constant_override("separation", max(1, int(1 * ui_scale)))
	_apply_card_visual_style()
	_update_card_layout_for_type()
	_is_layout_applying = false


func _apply_card_visual_style() -> void:
	if card_shadow:
		var shadow_style := StyleBoxFlat.new()
		shadow_style.bg_color = Color(0.0, 0.0, 0.0, 0.42)
		shadow_style.set_corner_radius_all(max(3, int(7 * ui_scale)))
		card_shadow.add_theme_stylebox_override("panel", shadow_style)
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
	_apply_surface_sheen()
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
	# Compact status strip sits below the stat lines; actions start at y=88, so
	# the font-backed badges have a measured 2px gap from the buttons below.
	status_icons = HBoxContainer.new()
	status_icons.add_theme_constant_override("separation", 1)
	status_icons.position = Vector2(6, 73)
	status_icons.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(status_icons)

	if normal_atk_btn:
		normal_atk_btn.pressed.connect(func(): attack_requested.emit())
		normal_atk_btn.tooltip_text = Locale.t("card.basic_attack")
	if skill1_btn:
		skill1_btn.pressed.connect(func(): skill1_requested.emit())
	if skill2_btn:
		skill2_btn.pressed.connect(func(): skill2_requested.emit())
	if skill3_btn:
		skill3_btn.pressed.connect(func(): skill3_requested.emit())

	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)
	gui_input.connect(_on_card_gui_input)

	_auto_hide_if_enemy()
	if current_card_data != null:
		set_card(current_card_data)
	else:
		apply_ui_scale(ui_scale)


# Hand cards pop up (scale from bottom-center + raise) while hovered so the
# player can see the card clearly before dragging it onto the battlefield.
func _on_hover_enter() -> void:
	_pointer_inside = true
	if not is_hand_card or not is_inside_tree():
		return
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	z_index = 20
	pivot_offset = Vector2(size.x * 0.5, size.y)
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(1.035, 1.035), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_hover_exit() -> void:
	_pointer_inside = false
	if not is_hand_card or not is_inside_tree():
		return
	if _drag_source:
		return
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	z_index = 0


func _on_card_gui_input(event: InputEvent) -> void:
	if not is_hand_card or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	_pointer_pressed = mouse_event.pressed
	if _drag_source:
		return
	_animate_pointer_state()


func _animate_pointer_state() -> void:
	if not is_inside_tree():
		return
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	pivot_offset = Vector2(size.x * 0.5, size.y)
	var target_scale := Vector2(0.985, 0.985) if _pointer_pressed else (Vector2(1.035, 1.035) if _pointer_inside else Vector2.ONE)
	var target_modulate := Color(0.90, 0.92, 0.96, 1.0) if _pointer_pressed else Color.WHITE
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(self, "scale", target_scale, 0.055 if _pointer_pressed else 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "modulate", target_modulate, 0.055 if _pointer_pressed else 0.11)


func _apply_surface_sheen() -> void:
	if card_surface == null:
		return
	if _surface_sheen == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.68, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.075),
			Color(1.0, 1.0, 1.0, 0.012),
			Color(0.0, 0.0, 0.0, 0.015),
			Color(0.0, 0.0, 0.0, 0.14),
		])
		_surface_sheen = GradientTexture2D.new()
		_surface_sheen.gradient = gradient
		_surface_sheen.width = 32
		_surface_sheen.height = 128
		_surface_sheen.fill_from = Vector2(0.5, 0.0)
		_surface_sheen.fill_to = Vector2(0.5, 1.0)
	card_surface.texture = _surface_sheen


func set_card(card_data: CardData):
	current_card_data = card_data

	if card_data == null:
		if name_label: name_label.text = ""
		if cost_label: cost_label.text = ""
		if gender_label: gender_label.text = ""
		if hp_label: hp_label.text = ""
		if atk_label: atk_label.text = ""
		if action_buttons: action_buttons.visible = false
		self.modulate = Color.WHITE
		_clear_status_icons()
		_last_status_signature = ""
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
	# set_card resets the label color, so the castability tint cache is stale.
	_last_cost_color = Color(-1.0, -1.0, -1.0, -1.0)

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

	_update_status_icons()
	_update_skill_buttons()
	if card_data.is_spell() and card_data.skills.size() > 0:
		tooltip_text = _TextFormatter.format_skill_tooltip(SpellRules.spell_skill(card_data))
	elif card_data.is_parasite():
		tooltip_text = Locale.t("card.parasite_tooltip", [card_data.hp, card_data.atk])
	else:
		tooltip_text = _parasite_tooltip(card_data)
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


func _clear_status_icons() -> void:
	if status_icons == null:
		return
	for child in status_icons.get_children():
		child.queue_free()


func _update_status_icons() -> void:
	if status_icons == null or current_card_data == null:
		return
	var entries: Array[Dictionary] = []
	var grouped: Dictionary = {
		"positive": [],
		"negative": [],
		"neutral": [],
	}
	for eff in current_card_data.status_effects:
		var val: int = eff.get("value", 0)
		if val <= 0:
			continue
		var buff_id: String = eff.get("buff_id", "")
		var polarity: String = SkillRegistry.buff_polarity(buff_id)
		if not grouped.has(polarity):
			polarity = "neutral"
		(grouped[polarity] as Array).append(eff)
	for polarity in ["positive", "negative", "neutral"]:
		var effects: Array = grouped[polarity]
		if effects.is_empty():
			continue
		var visual := _status_visual(polarity)
		var tooltip_lines: Array[String] = []
		for effect in effects:
			tooltip_lines.append(_format_buff_tooltip(effect))
		var symbol: String = visual.symbol
		if effects.size() > 1:
			symbol += str(effects.size())
		entries.append({
			"symbol": symbol,
			"color": visual.color,
			"tooltip": "\n".join(tooltip_lines),
		})
	var parasite_tooltips: Array[String] = []
	for parasite in current_card_data.parasite_cards:
		if not parasite is CardData:
			continue
		var p: CardData = parasite
		if p.skills.is_empty():
			continue
		parasite_tooltips.append(_format_parasite_passive_tooltip(p))
	if not parasite_tooltips.is_empty():
		var parasite_symbol := "⛓"
		if parasite_tooltips.size() > 1:
			parasite_symbol += str(parasite_tooltips.size())
		entries.append({
			"symbol": parasite_symbol,
			"color": Color(1.0, 0.74, 0.18),
			"tooltip": "\n\n".join(parasite_tooltips),
		})

	# Six compact badges fit inside the 108px strip. If a heavily modified card
	# exceeds that, reserve the final badge for a combined overflow indicator.
	const MAX_VISIBLE_STATUS_BADGES := 6
	var visible_count: int = min(entries.size(), MAX_VISIBLE_STATUS_BADGES)
	if entries.size() > MAX_VISIBLE_STATUS_BADGES:
		visible_count = MAX_VISIBLE_STATUS_BADGES - 1
	var badges: Array[Dictionary] = []
	for i in range(visible_count):
		badges.append(entries[i])
	if entries.size() > MAX_VISIBLE_STATUS_BADGES:
		var hidden_tooltips: Array[String] = []
		for i in range(visible_count, entries.size()):
			hidden_tooltips.append(entries[i].get("tooltip", ""))
		badges.append({
			"symbol": "+%d" % (entries.size() - visible_count),
			"color": Color(0.72, 0.78, 0.88),
			"tooltip": "\n\n".join(hidden_tooltips),
		})
	# Signature check: identical visible content means the existing badge nodes
	# are already correct — skip the teardown/rebuild entirely.
	var signature := ""
	for badge in badges:
		signature += "%s|%s|%s;" % [badge.get("symbol", ""), str(badge.get("color", "")), badge.get("tooltip", "")]
	if signature == _last_status_signature:
		return
	_last_status_signature = signature
	_clear_status_icons()
	for badge in badges:
		status_icons.add_child(_make_status_badge(
			badge.get("symbol", "•"),
			badge.get("color", Color.WHITE),
			badge.get("tooltip", "")
		))


func _status_visual(polarity: String) -> Dictionary:
	match polarity:
		"positive":
			return {"symbol": "↑", "color": Color(0.35, 0.95, 0.5)}
		"negative":
			return {"symbol": "↓", "color": Color(0.95, 0.34, 0.42)}
	return {"symbol": "•", "color": Color(0.72, 0.78, 0.88)}


func _make_status_badge(symbol: String, color: Color, tooltip: String) -> PanelContainer:
	var badge := PanelContainer.new()
	var badge_width: float = 16.0 if symbol.length() > 1 else 11.0
	badge.custom_minimum_size = Vector2(badge_width, 9) * ui_scale
	badge.tooltip_text = tooltip
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.055, 0.94)
	style.border_color = color
	var border_width: int = max(1, int(ui_scale))
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	var radius: int = max(2, int(2 * ui_scale))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = symbol
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var is_polarity_arrow := symbol.begins_with("↑") or symbol.begins_with("↓")
	label.add_theme_font_size_override("font_size", max(7, int((8 if is_polarity_arrow else 7) * ui_scale)))
	label.add_theme_color_override("font_color", color.lightened(0.18))
	if is_polarity_arrow:
		# A one-pixel same-colour outline gives the thin font arrow a readable
		# shaft at card scale without enlarging the badge or shifting its centre.
		label.add_theme_color_override("font_outline_color", color.lightened(0.18))
		label.add_theme_constant_override("outline_size", max(1, int(ui_scale)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge


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
	var unavailable_reason := ""
	var trig: String = skill.get("trigger", "")
	if current_card_data.skills_used.has(skill_index):
		unavailable = true
		unavailable_reason = Locale.t("card.skill_used")
	elif trig == SkillEngine.TRIGGER_ON_SUMMON and not current_card_data.summoned_this_turn:
		unavailable = true
		unavailable_reason = Locale.t("card.skill_summon_window")
	elif trig == SkillEngine.TRIGGER_ON_ACTIVATE and current_card_data.has_attacked:
		unavailable = true
		unavailable_reason = Locale.t("card.skill_action_spent")
	btn.disabled = unavailable
	btn.modulate = Color(0.5, 0.5, 0.5) if unavailable else Color.WHITE
	var base_tooltip := _TextFormatter.format_skill_tooltip(skill)
	btn.tooltip_text = "%s\n\n%s" % [base_tooltip, unavailable_reason] if unavailable else base_tooltip


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

	_drag_source = true
	_pointer_pressed = false
	z_index = 30
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2(0.97, 0.97)
	modulate = Color(1.0, 1.0, 1.0, 0.38)

	var preview_holder := Control.new()
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_holder.custom_minimum_size = Vector2.ONE
	var preview_shadow := Panel.new()
	preview_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_shadow.position = -size * 0.5 + Vector2(7, 10) * ui_scale
	preview_shadow.size = size
	preview_shadow.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.0, 0.0, 0.0, 0.34), Color(0, 0, 0, 0), 0,
		max(4, int(8 * ui_scale)), Color(0, 0, 0, 0.34), max(4, int(8 * ui_scale))
	))
	preview_holder.add_child(preview_shadow)
	var preview_card = duplicate()
	preview_card.modulate = Color(1.03, 1.03, 1.03, 0.94)
	preview_card.anchor_right = 0.0
	preview_card.anchor_bottom = 0.0
	preview_card.scale = Vector2(1.055, 1.055)
	if preview_card.has_method("apply_ui_scale"):
		preview_card.call("apply_ui_scale", ui_scale)
	else:
		preview_card.offset_right = 120.0 * ui_scale
		preview_card.offset_bottom = 160.0 * ui_scale
	preview_card.position = -preview_card.size * 0.5
	preview_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_holder.add_child(preview_card)
	set_drag_preview(preview_holder)

	return {
		"card_ui": self,
		"card_data": current_card_data
	}


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _drag_source:
		return
	_drag_source = false
	_pointer_pressed = false
	modulate = Color.WHITE
	z_index = 20 if _pointer_inside and is_hand_card else 0
	if is_inside_tree():
		_animate_pointer_state()
