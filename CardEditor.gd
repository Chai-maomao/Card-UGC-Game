extends Control

# ============================================
# Card Editor
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")
const _BalanceEvaluator = preload("res://BalanceEvaluator.gd")
const _UsabilityAnalyzer = preload("res://CardUsabilityAnalyzer.gd")

var card_ui_scene = preload("res://CardUI.tscn")
var pending_save_card: CardData = null
var pending_save_target_ids: Array = []
var pending_save_index: int = 0
var pending_saved_card: CardData = null
var pending_save_popup_layer: CanvasLayer = null

@onready var title_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TitleLabel
@onready var template_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TemplateButton
@onready var art_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtLabel
@onready var browse_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/BrowseButton
@onready var clear_art_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/ClearArtButton
@onready var name_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/NameLabel
@onready var name_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/NameInput
@onready var cost_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/CostLabel
@onready var cost_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/CostInput
@onready var hp_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/HpLabel
@onready var hp_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/HpInput
@onready var atk_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AtkLabel
@onready var atk_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AtkInput
@onready var gender_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/GenderLabel
@onready var gender_select = $Panel/MarginContainer/ScrollContainer/VBoxContainer/GenderSelect
@onready var balance_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/BalanceLabel
@onready var balance_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/BalanceSummary
@onready var usability_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/UsabilitySummary
@onready var art_path_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/ArtPathLabel
@onready var art_dialog = $ArtFileDialog
@onready var card_preview_panel = $CardPreviewPanel
@onready var preview_title = $CardPreviewPanel/PreviewBox/PreviewTitle
@onready var preview_card = $CardPreviewPanel/PreviewBox/PreviewCenter/PreviewCard

@onready var skill1_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill1Label
@onready var skill1_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill1Summary
@onready var skill2_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill2Label
@onready var skill2_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill2Summary
@onready var skill3_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill3Label
@onready var skill3_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill3Summary
@onready var edit_skill1_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EditSkill1Button
@onready var edit_skill2_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EditSkill2Button
@onready var edit_skill3_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EditSkill3Button
@onready var save_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/SaveButton
@onready var back_button = $BackButton

signal card_created(new_card_data: CardData)


func _apply_texts() -> void:
	title_label.text = Locale.t("editor.title")
	template_button.text = Locale.t("editor.use_template")
	art_label.text = Locale.t("editor.art_label")
	browse_button.text = Locale.t("editor.browse")
	name_label.text = Locale.t("editor.name")
	cost_label.text = Locale.t("editor.cost")
	hp_label.text = Locale.t("editor.hp")
	atk_label.text = Locale.t("editor.atk")

	var is_spell: bool = PlayerData.card_draft.get("card_type", "minion") == "spell"
	var is_parasite: bool = PlayerData.card_draft.get("card_type", "minion") == "parasite"

	gender_label.text = Locale.t("editor.gender")
	gender_label.visible = not is_spell
	gender_select.visible = not is_spell
	hp_label.visible = not is_spell
	hp_input.visible = not is_spell
	atk_label.visible = not is_spell
	atk_input.visible = not is_spell
	# For minions/parasites, restore visibility in case they were hidden by a previous spell edit.
	if not is_spell:
		hp_input.editable = true
		atk_input.editable = true
	balance_label.text = Locale.t("balance.title")

	if is_spell:
		skill1_label.text = Locale.t("editor.card_effect_label")
		edit_skill1_btn.text = Locale.t("editor.edit_effect")
	elif is_parasite:
		skill1_label.text = Locale.t("editor.parasite_passive_label")
		edit_skill1_btn.text = Locale.t("editor.edit_parasite_passive")
	else:
		skill1_label.text = Locale.t("editor.skill_1")
		edit_skill1_btn.text = Locale.t("editor.edit_skill_1")

	skill2_label.text = Locale.t("editor.skill_2")
	edit_skill2_btn.text = Locale.t("editor.edit_skill_2")
	skill3_label.text = Locale.t("editor.skill_3")
	edit_skill3_btn.text = Locale.t("editor.edit_skill_3")
	save_button.text = Locale.t("editor.update_card") if PlayerData.editing_index >= 0 else Locale.t("editor.save_card")
	back_button.text = Locale.t("common.back")
	art_dialog.title = Locale.t("editor.select_art")
	preview_title.text = Locale.t("editor.preview_title")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()

	# MarginContainer
	var margin := $Panel/MarginContainer
	margin.add_theme_constant_override("margin_left", int(120 * s))
	margin.add_theme_constant_override("margin_right", int(330 * s))
	margin.add_theme_constant_override("margin_top", int(40 * s))
	margin.add_theme_constant_override("margin_bottom", int(40 * s))

	# Back button
	var back_btn := $BackButton
	back_btn.position = Vector2(8, 8) * s
	back_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	if card_preview_panel:
		card_preview_panel.position = Vector2(-294 * s, 72 * s)
		card_preview_panel.size = Vector2(266 * s, 270 * s)
		preview_title.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		if preview_card:
			preview_card.apply_ui_scale(max(0.9, 1.35 * s))

	# VBox container
	var vbox := $Panel/MarginContainer/ScrollContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", int(8 * s))
	var art_row := vbox.get_node("ArtRow") as HBoxContainer
	if art_row:
		art_row.add_theme_constant_override("separation", int(4 * s))

	# Scale all labels and inputs in the VBox
	for child in vbox.get_children():
		if child is Label:
			var base_font := 14
			if child.name == "TitleLabel":
				base_font = 22
			child.add_theme_font_size_override("font_size", max(10, int(base_font * s)))
		elif child is LineEdit or child is SpinBox or child is OptionButton:
			child.custom_minimum_size = Vector2(200 * s, 0)
		elif child is Button:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _apply_theme() -> void:
	UITheme.apply_app_background($Panel)
	UITheme.apply_panel($Panel, "dark")
	UITheme.apply_title(title_label, max(18, int(22 * _ui_scale())))
	for label in [art_label, name_label, cost_label, hp_label, atk_label, gender_label, balance_label, balance_summary, usability_summary, skill1_label, skill1_summary, skill2_label, skill2_summary, skill3_label, skill3_summary]:
		UITheme.apply_label(label, label == balance_summary or label == usability_summary or label == skill1_summary or label == skill2_summary or label == skill3_summary)
	for input in [name_input, cost_input, hp_input, atk_input, gender_select]:
		UITheme.apply_input(input)
	for btn in [template_button, browse_button, clear_art_button, edit_skill1_btn, edit_skill2_btn, edit_skill3_btn, save_button, back_button]:
		UITheme.apply_button(btn, "primary" if btn == save_button or btn == template_button else "secondary")
	UITheme.apply_label(art_path_label, true)
	UITheme.apply_panel(card_preview_panel, "gold")
	UITheme.apply_title(preview_title, 14)
	# Entrance: fade the whole editor panel in (full-rect, no scale).
	UITheme.fade_enter($Panel, 0.22)


func _ready():
	_apply_theme()
	_configure_skill_summaries()
	_setup_gender_dropdown()
	var is_fresh_entry: bool = PlayerData.card_draft.is_empty()

	if is_fresh_entry:
		if PlayerData.has_card_draft_recovery() and PlayerData.restore_card_draft_recovery():
			pass
		elif PlayerData.editing_deck_id != "" and PlayerData.editing_instance_id != "":
			var card: CardData = PlayerData.find_deck_card(PlayerData.editing_deck_id, PlayerData.editing_instance_id)
			if card != null:
				PlayerData.load_card_to_draft(card)
			else:
				PlayerData.init_card_draft()
		elif PlayerData.editing_index >= 0 and PlayerData.editing_index < PlayerData.card_library.size():
			var card: CardData = PlayerData.card_library[PlayerData.editing_index]
			PlayerData.load_card_to_draft(card)
		else:
			PlayerData.init_card_draft()

	_apply_texts()
	_restore_form_from_draft()
	_update_skill_labels()
	_update_balance_summary()
	_update_usability_summary()
	_refresh_card_preview()
	_connect_live_balance_updates()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# Re-apply card-type restrictions AFTER form is restored so locked fields reflect the final values.
	_apply_card_type_restrictions()


func _setup_gender_dropdown():
	gender_select.clear()
	gender_select.add_item(Locale.t("editor.gender_male"), 0)
	gender_select.add_item(Locale.t("editor.gender_female"), 1)
	gender_select.add_item(Locale.t("editor.gender_nonhuman"), 2)


# Apply read-only card-type restrictions from the draft.
# For spell cards, ensure HP/ATK values are 0 (controls are hidden by _apply_texts).
func _apply_card_type_restrictions() -> void:
	var card_type: String = PlayerData.card_draft.get("card_type", "minion")
	var is_spell: bool = card_type == "spell"
	if is_spell:
		hp_input.value = 0
		atk_input.value = 0
		PlayerData.card_draft["hp"] = 0
		PlayerData.card_draft["atk"] = 0


func _restore_form_from_draft():
	name_input.text = PlayerData.card_draft.get("name", "")
	cost_input.value = PlayerData.card_draft.get("cost", 0)
	hp_input.value = PlayerData.card_draft.get("hp", 1)
	atk_input.value = PlayerData.card_draft.get("atk", 0)
	var gmap: Dictionary = {"male": 0, "female": 1, "nonhuman": 2}
	gender_select.selected = gmap.get(PlayerData.card_draft.get("gender", "female"), 1)

	var art: String = PlayerData.card_draft.get("art_path", "")
	if art != "":
		art_path_label.text = art.get_file()
	else:
		art_path_label.text = Locale.t("editor.none")


func _save_form_to_draft():
	PlayerData.card_draft["name"] = name_input.text if name_input.text != "" else Locale.t("editor.unnamed")
	PlayerData.card_draft["cost"] = int(cost_input.value)
	PlayerData.card_draft["hp"] = int(hp_input.value)
	PlayerData.card_draft["atk"] = int(atk_input.value)
	var genders: Array = ["male", "female", "nonhuman"]
	PlayerData.card_draft["gender"] = genders[gender_select.selected]
	PlayerData.queue_card_draft_recovery()


func _refresh_card_preview() -> void:
	if preview_card == null:
		return
	var preview_data: CardData = PlayerData.build_card_from_draft()
	preview_card.set_card(preview_data)
	preview_card.set_actions_visible(false)


func _connect_live_balance_updates() -> void:
	name_input.text_changed.connect(func(_text: String): _update_balance_from_form())
	cost_input.value_changed.connect(func(_value: float): _update_balance_from_form())
	hp_input.value_changed.connect(func(_value: float): _update_balance_from_form())
	atk_input.value_changed.connect(func(_value: float): _update_balance_from_form())
	gender_select.item_selected.connect(func(_idx: int): _update_balance_from_form())


func _update_balance_from_form() -> void:
	_save_form_to_draft()
	_update_balance_summary()
	_update_usability_summary()
	_refresh_card_preview()


func _update_usability_summary() -> void:
	var result := _UsabilityAnalyzer.analyze(PlayerData.card_draft)
	var issues: Array = result.get("issues", [])
	if issues.is_empty():
		usability_summary.text = Locale.t("usability.ready")
		usability_summary.add_theme_color_override("font_color", Color(0.45, 0.92, 0.62))
		return
	var lines: Array = []
	var has_error := false
	for issue in issues:
		var severity := str(issue.get("severity", "info"))
		has_error = has_error or severity == "error"
		var marker := "!" if severity == "error" else ("△" if severity == "warning" else "·")
		lines.append("%s %s" % [marker, Locale.t(str(issue.get("key", "")), issue.get("args", []))])
	usability_summary.text = "\n".join(lines)
	usability_summary.add_theme_color_override("font_color", Color(1.0, 0.45, 0.42) if has_error else Color(0.95, 0.78, 0.42))


func _update_balance_summary() -> void:
	if balance_summary == null:
		return
	var skills: Array = []
	for key in ["skill1", "skill2", "skill3"]:
		var skill: Dictionary = PlayerData.card_draft.get(key, {})
		if not skill.is_empty():
			skills.append(skill)
	var result: Dictionary = _BalanceEvaluator.evaluate_values(
		int(PlayerData.card_draft.get("cost", 0)),
		int(PlayerData.card_draft.get("atk", 0)),
		int(PlayerData.card_draft.get("hp", 1)),
		skills
	)
	var level: String = result.get("level", "balanced")
	var reasons: Array = result.get("reasons", [])
	var reason_text: String = _balance_reason_text(reasons)
	var summary: String = Locale.t("balance.summary") % [
		Locale.t("balance.%s" % level),
		int(result.get("recommended_cost", 0)),
		float(result.get("score", 0.0)),
		reason_text,
	]
	balance_summary.text = summary
	balance_summary.add_theme_color_override("font_color", _balance_color(level))


func _balance_reason_text(reasons: Array) -> String:
	if reasons.is_empty():
		return Locale.t("balance.reason_ok")
	var parts: Array = []
	if "cost_high" in reasons:
		parts.append(Locale.t("balance.reason_cost_high"))
	if "body" in reasons:
		parts.append(Locale.t("balance.reason_body"))
	if "skill" in reasons:
		parts.append(Locale.t("balance.reason_skill"))
	return "、".join(parts) if Locale.language == "zh" else ", ".join(parts)


func _balance_color(level: String) -> Color:
	match level:
		"severe":
			return Color(1.0, 0.35, 0.25)
		"strong":
			return Color(1.0, 0.72, 0.28)
		"weak":
			return Color(0.55, 0.75, 1.0)
	return Color(0.68, 0.95, 0.72)


# ============================================
# Art picker
# ============================================

func _on_browse_art_pressed():
	art_dialog.popup_centered()


func _on_art_file_selected(path: String):
	var fname: String = path.get_file()
	var dest_dir: String = ProjectSettings.globalize_path("user://arts")
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dest: String = dest_dir + "/" + fname

	var err = DirAccess.copy_absolute(path, dest)
	if err != OK:
		print("Failed to copy art: %d" % err)
		art_path_label.text = Locale.t("editor.copy_failed")
		return

	PlayerData.card_draft["art_path"] = "user://arts/" + fname
	PlayerData.queue_card_draft_recovery()
	art_path_label.text = fname
	print("Art saved: %s" % dest)


func _on_clear_art_pressed():
	PlayerData.card_draft["art_path"] = ""
	PlayerData.queue_card_draft_recovery()
	art_path_label.text = Locale.t("editor.none")


# ============================================
# Skill preview
# ============================================

func _configure_skill_summaries() -> void:
	for summary in [skill1_summary, skill2_summary, skill3_summary]:
		if summary == null:
			continue
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.custom_minimum_size.x = 0.0
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary.max_lines_visible = 3


func _update_skill_labels():
	var card_type: String = PlayerData.card_draft.get("card_type", "minion")
	var is_spell: bool = card_type == "spell"
	var is_parasite: bool = card_type == "parasite"
	skill1_summary.text = _format_skill_short(PlayerData.card_draft.get("skill1", {}))
	skill2_summary.text = _format_skill_short(PlayerData.card_draft.get("skill2", {}))
	skill3_summary.text = _format_skill_short(PlayerData.card_draft.get("skill3", {}))
	skill1_summary.tooltip_text = skill1_summary.text
	skill2_summary.tooltip_text = skill2_summary.text
	skill3_summary.tooltip_text = skill3_summary.text
	var has_skill2: bool = not PlayerData.card_draft.get("skill2", {}).is_empty()
	var has_skill3: bool = not PlayerData.card_draft.get("skill3", {}).is_empty()
	# Spell cards only have one skill; parasite cards currently expose one passive skill slot.
	skill2_label.visible = not is_spell and not is_parasite
	skill2_summary.visible = not is_spell and not is_parasite
	skill3_label.visible = not is_spell and not is_parasite
	skill3_summary.visible = not is_spell and not is_parasite
	edit_skill1_btn.visible = true
	edit_skill2_btn.visible = (not is_spell and not is_parasite) or has_skill2
	edit_skill3_btn.visible = (not is_spell and not is_parasite) or has_skill3
	_refresh_card_preview()


func _format_skill_short(skill: Dictionary) -> String:
	if skill.is_empty():
		return Locale.t("editor.empty")

	var is_spell: bool = PlayerData.card_draft.get("card_type", "minion") == "spell"
	var result: String = ""
	if not is_spell:
		var sname: String = skill.get("skill_name", "")
		var name_prefix: String = ("[%s] " % sname) if sname != "" else ""
		var t: String = Locale.term("trigger", skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK))
		result = "%s%s " % [name_prefix, t]
	var sp: int = skill.get("probability", 100)
	if sp < 100:
		result += "%s " % Locale.t("skill.chance", [sp])

	# Effects (backward compat)
	var effects: Array = SkillEngine.legacy_skill_effects(skill)

	if effects.is_empty():
		result += Locale.t("editor.no_fx")
	else:
		var parts: Array = []
		for eff in effects:
			parts.append(_TextFormatter.format_effect_sentence(_TargetResolver.normalize_effect_target(eff)))
		result += "；".join(parts) if Locale.language == "zh" else "; ".join(parts)

	return result


# ============================================
# Templates
# ============================================

func _on_template_pressed() -> void:
	var popup := UITheme.make_popup_layer(self, 100)
	var popup_layer: CanvasLayer = popup["layer"]
	var bg: ColorRect = popup["bg"]
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			popup_layer.queue_free()
	)

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -190
	panel.offset_top = -170
	panel.offset_right = 190
	panel.offset_bottom = 170
	UITheme.apply_popup_frame(panel, "gold")
	popup_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("editor.template_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	vbox.add_child(title)

	for template_id in ["warrior", "healer", "guard", "gunner", "cursed"]:
		var btn := Button.new()
		btn.text = Locale.t("editor.template_%s" % template_id)
		btn.custom_minimum_size = Vector2(260, 38)
		UITheme.apply_button(btn, "primary" if template_id == "warrior" else "secondary")
		btn.pressed.connect(func(id: String = template_id):
			_apply_template(id)
			popup_layer.queue_free()
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = Locale.t("common.back")
	cancel.custom_minimum_size = Vector2(260, 34)
	UITheme.apply_button(cancel, "secondary")
	cancel.pressed.connect(popup_layer.queue_free)
	vbox.add_child(cancel)


func _apply_template(template_id: String) -> void:
	_save_form_to_draft()
	var art_path: String = PlayerData.card_draft.get("art_path", "")
	var draft := _template_draft(template_id)
	if art_path != "":
		draft["art_path"] = art_path
	PlayerData.card_draft = draft
	PlayerData.queue_card_draft_recovery()
	_restore_form_from_draft()
	_update_skill_labels()
	_update_balance_summary()
	_update_usability_summary()


func _template_draft(template_id: String) -> Dictionary:
	match template_id:
		"healer":
			return {
				"name": Locale.t("editor.template_healer"), "cost": 3, "hp": 5, "atk": 1, "gender": "female", "card_type": "minion", "art_path": "",
				"skill1": {"skill_name": Locale.t("editor.template_healer_skill"), "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100, "effects": [
					_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 2})
				]},
				"skill2": {}
			}
		"guard":
			return {
				"name": Locale.t("editor.template_guard"), "cost": 3, "hp": 7, "atk": 1, "gender": "male", "card_type": "minion", "art_path": "",
				"skill1": {"skill_name": Locale.t("editor.template_guard_skill"), "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100, "effects": [
					_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_ADD_BUFF, "buff_id": SkillEngine.BUFF_TAUNT, "value": 1, "duration": 2}),
					_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_SHIELD, "value": 2})
				]},
				"skill2": {}
			}
		"gunner":
			return {
				"name": Locale.t("editor.template_gunner"), "cost": 4, "hp": 4, "atk": 2, "gender": "nonhuman", "card_type": "minion", "art_path": "",
				"skill1": {"skill_name": Locale.t("editor.template_gunner_skill"), "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100, "effects": [
					_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value_min": 1, "value_max": 3, "random_count": 2})
				]},
				"skill2": {}
			}
		"cursed":
			return {
				"name": Locale.t("editor.template_cursed"), "cost": 2, "hp": 3, "atk": 1, "gender": "female", "card_type": "minion", "art_path": "",
				"skill1": {"skill_name": Locale.t("editor.template_cursed_skill"), "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100, "effects": [
					_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_ADD_BUFF, "buff_id": SkillEngine.BUFF_MISFORTUNE, "value": 30, "duration": 2})
				]},
				"skill2": {}
			}
		_:
			return {
				"name": Locale.t("editor.template_warrior"), "cost": 2, "hp": 4, "atk": 3, "gender": "male", "card_type": "minion", "art_path": "",
				"skill1": {}, "skill2": {}
			}


# ============================================
# Skill editing
# ============================================

func _on_edit_skill1_pressed():
	_save_form_to_draft()
	PlayerData.editing_skill_index = 0
	UIMotion.change_scene("res://SkillEditor.tscn")


func _on_edit_skill2_pressed():
	_save_form_to_draft()
	PlayerData.editing_skill_index = 1
	UIMotion.change_scene("res://SkillEditor.tscn")


func _on_edit_skill3_pressed():
	_save_form_to_draft()
	PlayerData.editing_skill_index = 2
	UIMotion.change_scene("res://SkillEditor.tscn")


# ============================================
# Save
# ============================================

func _on_save_button_pressed():
	_save_form_to_draft()
	var new_card: CardData = PlayerData.build_card_from_draft()
	if PlayerData.editing_deck_id != "" and PlayerData.editing_instance_id != "":
		_show_sync_edit_popup(new_card)
	else:
		_show_save_targets_popup(new_card)


func _show_sync_edit_popup(new_card: CardData) -> void:
	var original := PlayerData.find_deck_card(PlayerData.editing_deck_id, PlayerData.editing_instance_id)
	if original == null:
		_show_message(Locale.t("editor.need_target_deck"))
		return
	var target_deck_ids: Dictionary = {}
	for deck in PlayerData.deck_library:
		var deck_id: String = deck.get("id", "")
		for card in PlayerData.get_cards_for_deck(deck_id):
			if card.card_name == original.card_name:
				target_deck_ids[deck_id] = true
				break
	var popup := UITheme.make_popup_layer(self, 105)
	var popup_layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230
	panel.offset_top = -210
	panel.offset_right = 230
	panel.offset_bottom = 210
	UITheme.apply_popup_frame(panel, "gold")
	popup_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("editor.sync_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)
	var hint := Label.new()
	hint.text = Locale.t("editor.sync_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(hint)
	box.add_child(hint)
	var selected_ids: Dictionary = target_deck_ids.duplicate()
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(deck_scroll)
	var deck_box := VBoxContainer.new()
	deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_box.add_theme_constant_override("separation", 6)
	deck_scroll.add_child(deck_box)
	for deck in PlayerData.deck_library:
		var deck_id: String = deck.get("id", "")
		if not target_deck_ids.has(deck_id):
			continue
		var check := CheckBox.new()
		check.text = deck.get("name", Locale.t("deck.default_name"))
		check.button_pressed = true
		check.disabled = deck_id == PlayerData.editing_deck_id
		UITheme.apply_button(check, "secondary")
		check.toggled.connect(func(pressed: bool):
			if pressed:
				selected_ids[deck_id] = true
			else:
				selected_ids.erase(deck_id)
		)
		deck_box.add_child(check)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var save_btn := Button.new()
	save_btn.text = Locale.t("editor.save_card")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(save_btn, "primary")
	save_btn.pressed.connect(func():
		if not selected_ids.has(PlayerData.editing_deck_id):
			_show_message(Locale.t("editor.sync_keep_deck"))
			return
		_apply_synced_edit(new_card, original.card_name, selected_ids.keys())
		popup_layer.queue_free()
	)
	row.add_child(save_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("skill_editor.cancel")
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(popup_layer.queue_free)
	row.add_child(cancel_btn)


func _apply_synced_edit(new_card: CardData, original_name: String, target_deck_ids: Array) -> void:
	for deck_id_variant in target_deck_ids:
		var deck_id: String = deck_id_variant
		for card in PlayerData.get_cards_for_deck(deck_id):
			if card.card_name == new_card.card_name and card.card_name != original_name:
				_show_message(Locale.t("editor.sync_name_conflict"))
				return
	var saved_card: CardData = null
	for deck_id_variant in target_deck_ids:
		var deck_id: String = deck_id_variant
		var matching_instance_ids: Array = []
		for card in PlayerData.get_cards_for_deck(deck_id):
			if card.card_name == original_name:
				matching_instance_ids.append(card.instance_id)
		for instance_id in matching_instance_ids:
			PlayerData.update_deck_card(deck_id, instance_id, new_card.duplicate_card())
			if deck_id == PlayerData.editing_deck_id and instance_id == PlayerData.editing_instance_id:
				saved_card = PlayerData.find_deck_card(deck_id, instance_id)
	PlayerData.save_library()
	if saved_card == null:
		saved_card = new_card
	PlayerData.card_draft = PlayerData.card_to_draft(saved_card)
	_show_after_save_popup(saved_card)


func _show_save_targets_popup(new_card: CardData) -> void:
	var popup := UITheme.make_popup_layer(self, 105)
	var popup_layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230
	panel.offset_top = -210
	panel.offset_right = 230
	panel.offset_bottom = 210
	UITheme.apply_popup_frame(panel, "gold")
	popup_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("editor.save_targets")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)
	var target_ids: Dictionary = {}
	var default_deck_id := PlayerData.editing_deck_id if PlayerData.editing_deck_id != "" else PlayerData.current_deck_id
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(deck_scroll)
	var deck_box := VBoxContainer.new()
	deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_box.add_theme_constant_override("separation", 6)
	deck_scroll.add_child(deck_box)
	for deck in PlayerData.deck_library:
		var deck_id: String = deck.get("id", "")
		var check := CheckBox.new()
		check.text = deck.get("name", Locale.t("deck.default_name"))
		UITheme.apply_button(check, "secondary")
		check.button_pressed = deck_id == default_deck_id
		if check.button_pressed:
			target_ids[deck_id] = true
		check.toggled.connect(func(pressed: bool):
			if pressed:
				target_ids[deck_id] = true
			else:
				target_ids.erase(deck_id)
		)
		deck_box.add_child(check)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var save_btn := Button.new()
	save_btn.text = Locale.t("editor.save_card")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(save_btn, "primary")
	save_btn.pressed.connect(func():
		if target_ids.is_empty():
			_show_message(Locale.t("editor.need_target_deck"))
			return
		popup_layer.queue_free()
		_start_multi_deck_save(new_card, target_ids.keys())
	)
	row.add_child(save_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("skill_editor.cancel")
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(popup_layer.queue_free)
	row.add_child(cancel_btn)


func _start_multi_deck_save(new_card: CardData, target_deck_ids: Array) -> void:
	pending_save_card = new_card
	pending_save_target_ids = target_deck_ids
	pending_save_index = 0
	pending_saved_card = null
	_process_next_save_target()


func _process_next_save_target() -> void:
	if pending_save_index >= pending_save_target_ids.size():
		_finish_multi_deck_save()
		return
	var deck_id: String = pending_save_target_ids[pending_save_index]
	var ignore_instance := PlayerData.editing_instance_id if deck_id == PlayerData.editing_deck_id else ""
	var conflict := PlayerData.find_deck_conflict(deck_id, pending_save_card, ignore_instance)
	if conflict.get("kind", "") == "conflict":
		_show_save_conflict_popup(deck_id, conflict.get("card"), pending_save_card)
		return
	_save_to_target_deck(deck_id)
	pending_save_index += 1
	_process_next_save_target()


func _save_to_target_deck(deck_id: String) -> void:
	if deck_id == PlayerData.editing_deck_id and PlayerData.editing_instance_id != "":
		PlayerData.update_deck_card(deck_id, PlayerData.editing_instance_id, pending_save_card)
		pending_saved_card = PlayerData.find_deck_card(deck_id, PlayerData.editing_instance_id)
	else:
		var result := PlayerData.add_card_copy_to_deck(deck_id, pending_save_card, true)
		if result.get("kind", "") == "added":
			pending_saved_card = result.get("card")
	PlayerData.save_library()


func _finish_multi_deck_save() -> void:
	var saved_card := pending_saved_card if pending_saved_card != null else pending_save_card
	PlayerData.card_draft = PlayerData.card_to_draft(saved_card)
	_show_after_save_popup(saved_card)
	pending_save_card = null
	pending_save_target_ids.clear()
	pending_save_index = 0
	pending_saved_card = null


func _save_card_without_conflict(new_card: CardData) -> void:
	if PlayerData.editing_deck_id != "" and PlayerData.editing_instance_id != "":
		PlayerData.update_deck_card(PlayerData.editing_deck_id, PlayerData.editing_instance_id, new_card)
		var saved := PlayerData.find_deck_card(PlayerData.editing_deck_id, PlayerData.editing_instance_id)
		if saved != null:
			new_card = saved
	elif PlayerData.current_deck_id != "":
		var result := PlayerData.add_card_copy_to_deck(PlayerData.current_deck_id, new_card, true)
		if result.get("kind", "") == "added":
			new_card = result.get("card")
		PlayerData.save_library()
	PlayerData.card_draft = PlayerData.card_to_draft(new_card)
	_show_after_save_popup(new_card)


func _show_save_conflict_popup(deck_id: String, local_card: CardData, new_card: CardData) -> void:
	var popup := UITheme.make_popup_layer(self, 110)
	var popup_layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330
	panel.offset_top = -240
	panel.offset_right = 330
	panel.offset_bottom = 240
	UITheme.apply_popup_frame(panel, "gold")
	popup_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = Locale.t("share.name_conflict")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	vbox.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 16)
	vbox.add_child(cards_row)
	cards_row.add_child(_make_conflict_summary(Locale.t("share.local_card"), local_card))
	cards_row.add_child(_make_conflict_summary(Locale.t("share.incoming_card"), new_card))
	var input := LineEdit.new()
	input.text = new_card.card_name + " 2"
	UITheme.apply_input(input)
	vbox.add_child(input)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var rename_local := Button.new()
	rename_local.text = Locale.t("share.rename_local")
	rename_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(rename_local, "secondary")
	rename_local.pressed.connect(func():
		var new_name := input.text.strip_edges()
		local_card.card_name = new_name if new_name != "" else Locale.t("editor.unnamed")
		PlayerData.save_library()
		popup_layer.queue_free()
		if pending_save_card != null:
			_save_to_target_deck(pending_save_target_ids[pending_save_index])
			pending_save_index += 1
			_process_next_save_target()
		else:
			_save_card_without_conflict(new_card)
	)
	row.add_child(rename_local)
	var rename_new := Button.new()
	rename_new.text = Locale.t("share.rename_incoming")
	rename_new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(rename_new, "secondary")
	rename_new.pressed.connect(func():
		var new_name := input.text.strip_edges()
		new_card.card_name = new_name if new_name != "" else Locale.t("editor.unnamed")
		popup_layer.queue_free()
		if pending_save_card != null:
			pending_save_card.card_name = new_card.card_name
			_save_to_target_deck(pending_save_target_ids[pending_save_index])
			pending_save_index += 1
			_process_next_save_target()
		else:
			_save_card_without_conflict(new_card)
	)
	row.add_child(rename_new)
	var replace_btn := Button.new()
	replace_btn.text = Locale.t("share.replace_local")
	replace_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(replace_btn, "danger")
	replace_btn.pressed.connect(func():
		PlayerData.update_deck_card(deck_id, local_card.instance_id, new_card)
		pending_saved_card = PlayerData.find_deck_card(deck_id, local_card.instance_id)
		PlayerData.save_library()
		popup_layer.queue_free()
		pending_save_index += 1
		_process_next_save_target()
	)
	row.add_child(replace_btn)


func _show_message(text: String) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var popup_layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -190
	panel.offset_top = -90
	panel.offset_right = 190
	panel.offset_bottom = 90
	UITheme.apply_popup_frame(panel, "gold")
	popup_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	box.add_child(label)
	var ok := Button.new()
	ok.text = Locale.t("skill_editor.ok")
	ok.custom_minimum_size = Vector2(160, 36)
	UITheme.apply_button(ok, "primary")
	ok.pressed.connect(popup_layer.queue_free)
	box.add_child(ok)


func _make_conflict_summary(label_text: String, card: CardData) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(260, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	box.add_child(label)
	var preview_holder := CenterContainer.new()
	preview_holder.custom_minimum_size = Vector2(120, 150)
	box.add_child(preview_holder)
	var card_ui = card_ui_scene.instantiate()
	preview_holder.add_child(card_ui)
	card_ui.set_card(card)
	card_ui.apply_ui_scale(0.82)
	card_ui.set_actions_visible(false)
	card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _show_after_save_popup(saved_card: CardData) -> void:
	var popup := UITheme.make_popup_layer(self, 100)
	var popup_layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -190
	panel.offset_top = -140
	panel.offset_right = 190
	panel.offset_bottom = 140
	UITheme.apply_popup_frame(panel, "gold")
	popup_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = Locale.t("editor.saved_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	vbox.add_child(title)
	var return_btn := Button.new()
	return_btn.text = Locale.t("editor.after_save_return")
	UITheme.apply_button(return_btn, "primary")
	return_btn.pressed.connect(func():
		popup_layer.queue_free()
		_return_after_save()
	)
	vbox.add_child(return_btn)
	var continue_btn := Button.new()
	continue_btn.text = Locale.t("editor.after_save_continue")
	UITheme.apply_button(continue_btn, "secondary")
	continue_btn.pressed.connect(func():
		popup_layer.queue_free()
		PlayerData.editing_index = -1
		PlayerData.editing_deck_id = ""
		PlayerData.editing_instance_id = ""
		PlayerData.card_draft.clear()
		PlayerData.clear_card_draft_recovery()
		PlayerData.continue_editing_flag = true
		PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
		PlayerData.return_to_deck_id = ""
		UIMotion.change_scene("res://MainMenu.tscn")
	)
	vbox.add_child(continue_btn)
	var test_btn := Button.new()
	test_btn.text = Locale.t("editor.after_save_test")
	UITheme.apply_button(test_btn, "secondary")
	test_btn.pressed.connect(func():
		popup_layer.queue_free()
		_start_solo_test(saved_card)
	)
	vbox.add_child(test_btn)


func _return_after_save() -> void:
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_draft.clear()
	PlayerData.clear_card_draft_recovery()
	var return_scene := PlayerData.card_editor_return_scene
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	PlayerData.scene_history.clear()  # Reset navigation history when returning from editor
	UIMotion.change_scene(return_scene)


func _start_solo_test(saved_card: CardData) -> void:
	PlayerData.begin_card_playtest(saved_card)
	PlayerData.battle_mode = "practice"
	PlayerData.battle_deck.clear()
	PlayerData.battle_deck.append(saved_card.duplicate_card())
	PlayerData.opponent_battle_deck.clear()
	for card in CardDatabase.starter_library():
		PlayerData.opponent_battle_deck.append(card.duplicate_card())
	UIMotion.change_scene("res://Main.tscn")


# ============================================
# Back
# ============================================

func _on_back_button_pressed():
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_draft.clear()
	PlayerData.clear_card_draft_recovery()
	var return_scene := PlayerData.card_editor_return_scene
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	UIMotion.change_scene(return_scene)
