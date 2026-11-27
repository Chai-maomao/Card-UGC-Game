extends Control

# ============================================
# Card Editor
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")
const _BalanceEvaluator = preload("res://BalanceEvaluator.gd")
const _BalanceSimulation = preload("res://CardBalanceSimulation.gd")
const _BattleSimulator = preload("res://HeadlessBattleSimulator.gd")
const _UsabilityAnalyzer = preload("res://CardUsabilityAnalyzer.gd")
const _UgcSafety = preload("res://UgcSafety.gd")
const _CardTutorialController = preload("res://CardEditorTutorialController.gd")
const _CardArtDropZone = preload("res://presentation/CardArtDropZone.gd")

var pending_save_card: CardData = null
var pending_save_target_ids: Array = []
var pending_save_index: int = 0
var _pending_save_decks: Dictionary = {}
var _pending_prior_cards: Array[CardData] = []
var _retry_save_target_ids: Array = []
var _retry_sync_cards: Dictionary = {}
var _pending_sync_cards: Dictionary = {}
var pending_saved_card: CardData = null
var pending_save_popup_layer: CanvasLayer = null
var card_tutorial_controller
var _diagnostics_panel: PanelContainer
var _editor_save_dock: CenterContainer
var _simulation_generation := 0
var _simulation_popup_layer: CanvasLayer = null
var _simulation_ui := {}
var _version_history_popup_layer: CanvasLayer = null
var _suspend_form_updates := false
var _art_edit_field := "art_path"
var _damaged_art_label: Label
var _damaged_art_path: Label
var _damaged_art_browse: _CardArtDropZone
var _art_crop: CanvasLayer
var _damaged_art_clear: Button
var _preview_damaged: CheckButton
var _room_connection_notice: Label
var _form_header: VBoxContainer

@onready var title_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TitleLabel
@onready var template_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TemplateButton
@onready var art_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtLabel
@onready var browse_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/BrowseButton
@onready var clear_art_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/ClearArtButton
@onready var name_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/NameLabel
@onready var name_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/NameInput
@onready var cost_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/StatsGrid/CostField/CostLabel
@onready var cost_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/StatsGrid/CostField/CostInput
@onready var hp_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/StatsGrid/HpField/HpLabel
@onready var hp_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/StatsGrid/HpField/HpInput
@onready var atk_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/StatsGrid/AtkField/AtkLabel
@onready var atk_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/StatsGrid/AtkField/AtkInput
@onready var gender_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/GenderLabel
@onready var gender_select = $Panel/MarginContainer/ScrollContainer/VBoxContainer/GenderSelect
@onready var parasite_damage_mode_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ParasiteDamageModeLabel
@onready var parasite_damage_mode_select = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ParasiteDamageModeSelect
@onready var balance_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/BalanceLabel
@onready var balance_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/BalanceSummary
@onready var usability_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/UsabilitySummary
@onready var analysis_actions_row = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AnalysisActionsRow
@onready var simulation_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AnalysisActionsRow/SimulationButton
@onready var version_history_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AnalysisActionsRow/VersionHistoryButton
@onready var art_path_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtPathLabel
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
@onready var edit_skill1_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill1TalentRow/EditSkill1Button
@onready var edit_talent_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill1TalentRow/EditTalentButton
@onready var talent_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TalentSummary
@onready var edit_skill2_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EditSkill2Button
@onready var edit_skill3_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EditSkill3Button
@onready var save_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/SaveButton
@onready var back_button = $BackButton

signal card_created(new_card_data: CardData)


func _apply_texts() -> void:
	title_label.text = Locale.t("editor.title")
	template_button.text = Locale.t("editor.use_template")
	art_label.text = Locale.t("editor.art_label")
	var upload_prompt := Locale.t("editor.art_upload_touch" if _CardArtDropZone.uses_touch_picker() else "editor.art_upload")
	var upload_shortcut := _art_paste_hint()
	browse_button.set_copy(upload_prompt, upload_shortcut)
	if _damaged_art_label != null:
		_damaged_art_label.text = Locale.t("editor.damaged_art")
		_damaged_art_browse.set_copy(upload_prompt, upload_shortcut)
		_damaged_art_clear.text = Locale.t("editor.clear_art")
		_preview_damaged.text = Locale.t("editor.preview_damaged")
	clear_art_button.text = Locale.t("editor.clear_art")
	name_label.text = Locale.t("editor.name")
	cost_label.text = Locale.t("editor.cost")
	hp_label.text = Locale.t("editor.hp")
	atk_label.text = Locale.t("editor.atk")

	var is_spell: bool = PlayerData.card_draft.get("card_type", "minion") == "spell"
	var is_parasite: bool = PlayerData.card_draft.get("card_type", "minion") == "parasite"

	gender_label.text = Locale.t("editor.gender")
	gender_label.visible = not is_spell
	gender_select.visible = not is_spell
	parasite_damage_mode_label.text = Locale.t("editor.parasite_damage_mode")
	parasite_damage_mode_label.visible = is_parasite
	parasite_damage_mode_select.visible = is_parasite
	parasite_damage_mode_select.tooltip_text = Locale.t("editor.parasite_damage_mode_help")
	hp_label.visible = not is_spell
	hp_input.visible = not is_spell
	atk_label.visible = not is_spell
	atk_input.visible = not is_spell
	# For minions/parasites, restore visibility in case they were hidden by a previous spell edit.
	if not is_spell:
		hp_input.editable = true
		atk_input.editable = true
	balance_label.text = Locale.t("balance.title")
	simulation_button.text = Locale.t("simulation.button")
	simulation_button.tooltip_text = Locale.t("simulation.button_help")
	version_history_button.text = Locale.t("revision.button")
	version_history_button.tooltip_text = Locale.t("revision.button_help")

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
	edit_talent_btn.text = Locale.t("editor.edit_talent")
	save_button.text = Locale.t("editor.update_card") if PlayerData.editing_index >= 0 else Locale.t("editor.save_card")
	back_button.text = Locale.t("common.back")
	art_dialog.title = Locale.t("editor.select_art")
	art_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.bmp,*.webp ; 图片" if Locale.language == "zh" else "*.png,*.jpg,*.jpeg,*.bmp,*.webp ; Images"])
	preview_title.text = Locale.t("editor.preview_title")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var bottom_inset := roundi(22 * s)

	# MarginContainer
	var margin := $Panel/MarginContainer
	var form_top := maxi(80, int(64 * s))
	var sidebar_right := -28 * s
	if preview_card:
		preview_card.apply_ui_scale(max(0.9, 1.35 * s))
	var sidebar_width := maxf(266 * s, card_preview_panel.get_combined_minimum_size().x)
	var sidebar_left := sidebar_right - sidebar_width
	var form_right := ceili(-sidebar_left + 58 * s)
	margin.add_theme_constant_override("margin_left", int(48 * s))
	margin.add_theme_constant_override("margin_right", form_right)
	margin.add_theme_constant_override("margin_bottom", bottom_inset)

	# Back button
	var back_btn := $BackButton
	UITheme.place_page_back(self, back_btn)
	back_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	if is_instance_valid(_room_connection_notice):
		_room_connection_notice.offset_left = back_btn.position.x + back_btn.size.x + 16.0
		_room_connection_notice.offset_top = back_btn.position.y
		_room_connection_notice.offset_right = -24.0
		_room_connection_notice.offset_bottom = back_btn.position.y + back_btn.size.y
		_room_connection_notice.add_theme_font_size_override("font_size", max(14, int(14 * s)))
	if card_preview_panel:
		# This panel is right-anchored. Assigning `position` moved it relative to
		# the wrong origin on resized windows and could place the entire preview
		# off-screen; offsets preserve the right anchor at every scale.
		card_preview_panel.offset_left = sidebar_left
		card_preview_panel.offset_top = 72 * s
		card_preview_panel.offset_right = sidebar_right
		card_preview_panel.offset_bottom = card_preview_panel.offset_top + maxf(270 * s, card_preview_panel.get_combined_minimum_size().y)
		preview_title.add_theme_font_size_override("font_size", max(10, int(14 * s)))

	# VBox container
	UITheme.pad_scroll_content($Panel/MarginContainer/ScrollContainer, 16)
	var vbox := $Panel/MarginContainer/ScrollContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", int(10 * s))

	for control in [cost_input, hp_input, atk_input]:
		control.custom_minimum_size = Vector2(0, 40 * s)
		control.add_theme_font_size_override("font_size", maxi(14, int(17 * s)))
	for label in [cost_label, hp_label, atk_label]:
		label.add_theme_font_size_override("font_size", maxi(13, int(15 * s)))
	if _diagnostics_panel:
		_diagnostics_panel.offset_left = sidebar_left
		_diagnostics_panel.offset_right = sidebar_right
		_diagnostics_panel.offset_top = card_preview_panel.offset_bottom + 12 * s
		_diagnostics_panel.offset_bottom = -80 * s
	if _editor_save_dock:
		_editor_save_dock.offset_left = sidebar_left
		_editor_save_dock.offset_right = sidebar_right
		_editor_save_dock.offset_top = -68 * s
		_editor_save_dock.offset_bottom = -bottom_inset
		save_button.custom_minimum_size = Vector2(sidebar_width, 44 * s)
	# Scale all labels and inputs in the VBox
	title_label.add_theme_font_size_override("font_size", maxi(18, int(22 * s)))
	template_button.add_theme_font_size_override("font_size", maxi(13, int(14 * s)))
	_form_header.offset_left = int(48 * s)
	_form_header.offset_right = -form_right - 16
	_form_header.offset_top = form_top
	var header_height := ceili(_form_header.get_combined_minimum_size().y)
	_form_header.offset_bottom = form_top + header_height
	margin.add_theme_constant_override("margin_top", form_top + header_height + maxi(8, roundi(12 * s)))
	for child in vbox.get_children():
		if child is Label:
			var section: bool = child.has_meta("card_form_heading")
			child.add_theme_font_size_override("font_size", maxi(16, int(18 * s)) if section else maxi(12, int(14 * s)))
		elif child is LineEdit or child is SpinBox or child is OptionButton:
			child.custom_minimum_size = Vector2(200 * s, 0)
		elif child is Button:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _apply_theme() -> void:
	UITheme.apply_app_background($Panel)
	UITheme.apply_title(title_label, max(18, int(22 * _ui_scale())))
	for label in [art_label, name_label, cost_label, hp_label, atk_label, gender_label, parasite_damage_mode_label, balance_label, balance_summary, usability_summary, skill1_label, skill1_summary, skill2_label, skill2_summary, skill3_label, skill3_summary, talent_summary]:
		UITheme.apply_label(label, label in [balance_summary, usability_summary, skill1_summary, skill2_summary, skill3_summary, talent_summary])
	for input in [name_input, cost_input, hp_input, atk_input, gender_select, parasite_damage_mode_select]:
		UITheme.apply_input(input)
	for btn in [template_button, clear_art_button, simulation_button, version_history_button]:
		UITheme.apply_button(btn, "utility")
	_setup_template_menu()
	for btn in [edit_skill1_btn, edit_talent_btn, edit_skill2_btn, edit_skill3_btn]:
		UITheme.apply_button(btn, "secondary")
	UITheme.apply_button(save_button, "primary")
	template_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UITheme.apply_dialog(art_dialog, true)
	UITheme.apply_label(art_path_label, true)
	UITheme.apply_panel(card_preview_panel, "dark")
	UITheme.apply_title(preview_title, 14)
	# Entrance: fade the whole editor panel in (full-rect, no scale).
	UITheme.fade_enter($Panel, 0.22)


func _ready():
	browse_button.paste_requested.connect(_paste_art.bind("art_path"))
	art_label.set_meta("keyword_literal",true)
	get_window().files_dropped.connect(_on_art_files_dropped)
	_arrange_editor_form()
	_build_damaged_art_controls()
	_apply_theme()
	_configure_skill_summaries()
	_setup_gender_dropdown()
	_setup_parasite_damage_mode_dropdown()
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
	_build_editor_sidebar()
	_setup_room_connection_notice()
	get_viewport().size_changed.connect(_resize_current_balance_popup)
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# Re-apply card-type restrictions AFTER form is restored so locked fields reflect the final values.
	_apply_card_type_restrictions()
	_capture_opening_revision()
	_refresh_version_history_button()
	if PlayerData.skill_tutorial_active:
		analysis_actions_row.visible = false
		card_tutorial_controller = _CardTutorialController.new()
		add_child(card_tutorial_controller)
		card_tutorial_controller.start(self)


func _arrange_editor_form() -> void:
	var form := name_label.get_parent() as VBoxContainer
	_form_header = VBoxContainer.new()
	_form_header.name = "EditorHeader"
	_form_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_form_header.add_theme_constant_override("separation", 8)
	$Panel.add_child(_form_header)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_form_header.add_child(header)
	_form_header.add_child(UITheme.separator())
	title_label.reparent(header, false)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	template_button.reparent(header, false)
	for field in [name_label, name_input, form.get_node("StatsGrid"),
			gender_label, gender_select, parasite_damage_mode_label, parasite_damage_mode_select,
			form.get_node("SeparatorA")]:
		form.move_child(field, art_label.get_index())
	_add_form_heading(form, name_label, "editor.section_attributes")
	art_label.set_meta("card_form_heading", true)
	UITheme.apply_title(art_label, 18)
	_add_form_heading(form, skill1_label, "editor.section_skills")
	for child in form.get_children():
		if child is HSeparator:
			UITheme.apply_separator(child)
	form.get_node("Separator0").hide()


func _add_form_heading(form: VBoxContainer, before: Control, key: String) -> void:
	var heading := Label.new()
	heading.text = Locale.t(key)
	heading.set_meta("card_form_heading", true)
	UITheme.apply_title(heading, 18)
	form.add_child(heading)
	form.move_child(heading, before.get_index())


func _setup_room_connection_notice() -> void:
	if not PlayerData.return_to_waiting_room or PlayerData.card_editor_return_scene != "res://DedicatedLobby.tscn":
		return
	_room_connection_notice = Label.new()
	_room_connection_notice.name = "RoomConnectionNotice"
	_room_connection_notice.anchor_right = 1.0
	_room_connection_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_connection_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_connection_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_label(_room_connection_notice)
	_room_connection_notice.add_theme_color_override("font_color", UITheme.COLOR_WARNING)
	add_child(_room_connection_notice)
	NetworkManager.room_link_wait_changed.connect(_refresh_room_connection_notice)
	NetworkManager.opponent_disconnected.connect(func(_player: int): _refresh_room_connection_notice())
	_refresh_room_connection_notice()


func _refresh_room_connection_notice() -> void:
	var room_available := NetworkManager.has_live_server_room()
	_room_connection_notice.visible = not room_available or NetworkManager.room_link_waiting()
	_room_connection_notice.text = Locale.t("editor.room_link_recovering" if room_available else "editor.room_link_lost")


func _setup_gender_dropdown():
	gender_select.clear()
	gender_select.add_item(Locale.t("editor.gender_male"), 0)
	gender_select.add_item(Locale.t("editor.gender_female"), 1)
	gender_select.add_item(Locale.t("editor.gender_nonhuman"), 2)


func _setup_parasite_damage_mode_dropdown() -> void:
	parasite_damage_mode_select.clear()
	parasite_damage_mode_select.add_item(Locale.t("editor.parasite_mode_absorb"), 0)
	parasite_damage_mode_select.add_item(Locale.t("editor.parasite_mode_linked"), 1)


# Apply read-only card-type restrictions from the draft.
# For spell cards, ensure HP/ATK values are 0 (controls are hidden by _apply_texts).
func _apply_card_type_restrictions() -> void:
	var card_type: String = PlayerData.card_draft.get("card_type", "minion")
	var is_spell: bool = card_type == "spell"
	var is_linked_parasite: bool = card_type == "parasite" and str(PlayerData.card_draft.get("parasite_damage_mode", CardData.PARASITE_DAMAGE_ABSORB)) == CardData.PARASITE_DAMAGE_LINKED
	if is_spell:
		hp_input.value = 0
		atk_input.value = 0
		PlayerData.card_draft["hp"] = 0
		PlayerData.card_draft["atk"] = 0
	hp_input.editable = not is_spell and not is_linked_parasite
	var hp_tint := Color(UITheme.Tokens.TEAL,0.78) if is_linked_parasite else Color.WHITE
	hp_input.modulate = hp_tint
	hp_label.modulate = hp_tint
	hp_input.tooltip_text = Locale.t("editor.parasite_linked_hp_help") if is_linked_parasite else ""
	hp_label.tooltip_text = hp_input.tooltip_text


func _restore_form_from_draft():
	_suspend_form_updates = true
	name_input.text = PlayerData.card_draft.get("name", "")
	cost_input.value = PlayerData.card_draft.get("cost", 0)
	hp_input.value = PlayerData.card_draft.get("hp", 1)
	atk_input.value = PlayerData.card_draft.get("atk", 0)
	var gmap: Dictionary = {"male": 0, "female": 1, "nonhuman": 2}
	gender_select.selected = gmap.get(PlayerData.card_draft.get("gender", "female"), 1)
	parasite_damage_mode_select.selected = 1 if PlayerData.card_draft.get("parasite_damage_mode", CardData.PARASITE_DAMAGE_ABSORB) == CardData.PARASITE_DAMAGE_LINKED else 0

	_show_art_status("art_path", "")
	if is_instance_valid(_damaged_art_path):
		_show_art_status("damaged_art_path", "")
	_suspend_form_updates = false


func _save_form_to_draft():
	PlayerData.card_draft["name"] = name_input.text if name_input.text != "" else Locale.t("editor.unnamed")
	PlayerData.card_draft["cost"] = int(cost_input.value)
	PlayerData.card_draft["hp"] = int(hp_input.value)
	PlayerData.card_draft["atk"] = int(atk_input.value)
	var genders: Array = ["male", "female", "nonhuman"]
	PlayerData.card_draft["gender"] = genders[gender_select.selected]
	if PlayerData.card_draft.get("card_type", "minion") == "parasite":
		PlayerData.card_draft["parasite_damage_mode"] = CardData.PARASITE_DAMAGE_LINKED if parasite_damage_mode_select.selected == 1 else CardData.PARASITE_DAMAGE_ABSORB
	PlayerData.queue_card_draft_recovery()


func _refresh_card_preview() -> void:
	var art := str(PlayerData.card_draft.get("art_path", ""))
	clear_art_button.disabled = art.is_empty()
	browse_button.set_art(art)
	if _damaged_art_clear != null:
		var damaged: String = PlayerData.card_draft.get("damaged_art_path", "")
		_damaged_art_clear.disabled = damaged.is_empty()
		_damaged_art_browse.set_art(damaged)
	if preview_card == null:
		return
	var preview_data: CardData = PlayerData.build_card_from_draft()
	if _preview_damaged != null and _preview_damaged.button_pressed and preview_data.max_hp>0:
		preview_data.hp = maxi(0,preview_data.max_hp-1)
	preview_card.set_card(preview_data)
	preview_card.set_battle_layout_preview(true)


func _connect_live_balance_updates() -> void:
	name_input.text_changed.connect(func(_text: String): _update_balance_from_form())
	cost_input.value_changed.connect(func(_value: float): _update_balance_from_form())
	hp_input.value_changed.connect(func(_value: float): _update_balance_from_form())
	atk_input.value_changed.connect(func(_value: float): _update_balance_from_form())
	gender_select.item_selected.connect(func(_idx: int): _update_balance_from_form())
	parasite_damage_mode_select.item_selected.connect(func(_idx: int): _update_balance_from_form())


func _update_balance_from_form() -> void:
	if _suspend_form_updates:
		return
	_save_form_to_draft()
	_apply_card_type_restrictions()
	_update_balance_summary()
	_update_usability_summary()
	_refresh_card_preview()
	if card_tutorial_controller:
		card_tutorial_controller._on_form_changed()


func _update_usability_summary() -> void:
	var result := _UsabilityAnalyzer.analyze(PlayerData.card_draft)
	var issues: Array = result.get("issues", [])
	if issues.is_empty():
		usability_summary.text = Locale.t("usability.ready")
		usability_summary.add_theme_color_override("font_color", UITheme.Tokens.SUCCESS)
		return
	var lines: Array = []
	var has_error := false
	for issue in issues:
		var severity := str(issue.get("severity", "info"))
		has_error = has_error or severity == "error"
		var marker := "!" if severity == "error" else ("△" if severity == "warning" else "•")
		lines.append("%s %s" % [marker, Locale.t(str(issue.get("key", "")), issue.get("args", []))])
	usability_summary.text = "\n".join(lines)
	usability_summary.add_theme_color_override("font_color", UITheme.Tokens.WARNING if has_error else UITheme.Tokens.WARNING)


func _update_balance_summary() -> void:
	if balance_summary == null:
		return
	var skills: Array = []
	var first_key := "talent" if not PlayerData.card_draft.get("talent", {}).is_empty() else "skill1"
	for key in [first_key, "skill2", "skill3"]:
		var skill: Dictionary = PlayerData.card_draft.get(key, {})
		if not skill.is_empty():
			skills.append(skill)
	var result: Dictionary = _BalanceEvaluator.evaluate_values(
		int(PlayerData.card_draft.get("cost", 0)),
		int(PlayerData.card_draft.get("atk", 0)),
		int(PlayerData.card_draft.get("hp", 1)),
		skills,
		str(PlayerData.card_draft.get("card_type", "minion")),
		1,
		str(PlayerData.card_draft.get("parasite_damage_mode", CardData.PARASITE_DAMAGE_ABSORB))
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
	if bool(result.get("uncertain", false)):
		balance_summary.text += ("\n情景估值 %.1f–%.1f" if Locale.language == "zh" else "\nScenario estimate %.1f–%.1f") % [result.get("scenario_min", 0.0), result.get("scenario_max", 0.0)]
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
			return UITheme.Tokens.ENEMY
		"strong":
			return UITheme.Tokens.WARNING
		"weak":
			return UITheme.Tokens.MUTED
	return UITheme.Tokens.TITLE


# ============================================
# Draft simulation report
# ============================================

func _on_balance_simulation_pressed() -> void:
	_save_form_to_draft()
	var safety_issues := _UgcSafety.validate_draft_card(PlayerData.card_draft)
	if not safety_issues.is_empty():
		_show_message(Locale.t("editor.ugc_safety_blocked", [_UgcSafety.first_error_text(safety_issues)]))
		return
	var usability := _UsabilityAnalyzer.analyze(PlayerData.card_draft)
	for issue in usability.get("issues", []):
		if str(issue.get("severity", "")) == "error":
			_show_message(Locale.t("simulation.invalid_card"))
			return
	_open_balance_simulation(PlayerData.build_card_from_draft(), true)


func _open_balance_simulation(candidate: CardData, auto_start: bool = true, games_per_pool: int = _BalanceSimulation.DEFAULT_GAMES_PER_POOL) -> CanvasLayer:
	games_per_pool = maxi(1, games_per_pool)
	_simulation_generation += 1
	var generation := _simulation_generation
	if _simulation_popup_layer != null and is_instance_valid(_simulation_popup_layer):
		_simulation_popup_layer.queue_free()
	var popup := UITheme.make_popup_layer(self, 125)
	var popup_layer: CanvasLayer = popup["layer"]
	popup_layer.name = "CardSimulationPopup"
	popup_layer.set_meta("popup_close", _close_balance_simulation.bind(generation))
	_simulation_popup_layer = popup_layer
	var bg: ColorRect = popup["bg"]
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_close_balance_simulation(generation)
	)

	var panel := Panel.new()
	panel.name = "CardSimulationPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.clip_contents = true
	UITheme.apply_popup_frame(panel, "gold", false)
	popup_layer.add_child(panel)
	_resize_balance_popup(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.name = "SimulationTitle"
	title.text = Locale.t("simulation.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = title.text
	UITheme.apply_title(title, 22)
	box.add_child(title)
	var note := Label.new()
	note.name = "SimulationNote"
	note.text = Locale.t("simulation.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(note, true)
	box.add_child(note)

	var progress := ProgressBar.new()
	progress.name = "SimulationProgress"
	progress.min_value = 0
	progress.max_value = _BalanceSimulation.POOL_IDS.size() * games_per_pool
	progress.value = 0
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 14)
	progress.add_theme_stylebox_override("background", UITheme.panel_style(Color(UITheme.Tokens.PANEL_DARK,0.9), UITheme.Tokens.INK, 1, 6))
	progress.add_theme_stylebox_override("fill", UITheme.panel_style(Color(UITheme.Tokens.TEAL,0.92), UITheme.COLOR_GOLD, 1, 6))
	box.add_child(progress)
	var status := Label.new()
	status.name = "SimulationStatus"
	status.text = Locale.t("simulation.ready")
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(status, true)
	box.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.name = "SimulationScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.apply_scrollbar(scroll.get_h_scroll_bar())
	UITheme.apply_scrollbar(scroll.get_v_scroll_bar())
	box.add_child(scroll)
	var results := VBoxContainer.new()
	results.name = "SimulationResults"
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_theme_constant_override("separation", 8)
	scroll.add_child(results)
	var placeholder := Label.new()
	placeholder.name = "SimulationPlaceholder"
	placeholder.text = Locale.t("simulation.waiting")
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(placeholder, true)
	results.add_child(placeholder)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	var close_button := Button.new()
	close_button.name = "SimulationCancelButton"
	close_button.text = Locale.t("common.cancel") if auto_start else Locale.t("common.close")
	close_button.custom_minimum_size = Vector2(124, 40)
	UITheme.apply_button(close_button, "secondary")
	close_button.pressed.connect(_close_balance_simulation.bind(generation))
	actions.add_child(close_button)

	_simulation_ui = {
		"generation": generation,
		"progress": progress,
		"status": status,
		"results": results,
		"close": close_button,
	}
	UITheme.animate_popup_enter(panel)
	if auto_start:
		_run_balance_simulation.call_deferred(generation, candidate.duplicate_card(), games_per_pool)
	return popup_layer


func _resize_balance_popup(panel: Control) -> void:
	var dimensions := Vector2(580, 440).min(get_viewport_rect().size - Vector2(32, 32))
	panel.offset_left = -dimensions.x / 2
	panel.offset_right = dimensions.x / 2
	panel.offset_top = -dimensions.y / 2
	panel.offset_bottom = dimensions.y / 2


func _resize_current_balance_popup() -> void:
	if not is_instance_valid(_simulation_popup_layer) or _simulation_popup_layer.is_queued_for_deletion(): return
	var panel := _simulation_popup_layer.get_node_or_null("CardSimulationPanel") as Control
	if panel != null: _resize_balance_popup(panel)


func _run_balance_simulation(generation: int, candidate: CardData, games_per_pool: int) -> void:
	var completed := 0
	for kind in _BalanceSimulation.POOL_IDS:
		if not _simulation_is_current(generation):
			return
		var accumulator := _BalanceSimulation.new_accumulator(kind, games_per_pool)
		var pool := _BalanceSimulation.build_pool(kind, candidate)
		var baseline_pool := _BalanceSimulation.build_baseline_pool(kind)
		for game_index in range(games_per_pool):
			if not _simulation_is_current(generation):
				return
			var result := _BattleSimulator.run_game(
				baseline_pool,
				pool,
				_BalanceSimulation.seed_for_pool(kind) + game_index,
				"normal",
				"normal",
				30
			)
			_BalanceSimulation.add_game(accumulator, result)
			completed += 1
			(_simulation_ui["progress"] as ProgressBar).value = completed
			(_simulation_ui["status"] as Label).text = Locale.t("simulation.progress", [
				Locale.t("simulation.pool.%s" % kind), game_index + 1, games_per_pool,
			])
			# One deterministic game per frame keeps the editor responsive and gives
			# the cancel action a chance to take effect between simulations.
			await get_tree().process_frame
		if not _simulation_is_current(generation):
			return
		_add_balance_simulation_result(_BalanceSimulation.finalize(accumulator))
	if not _simulation_is_current(generation):
		return
	(_simulation_ui["status"] as Label).text = Locale.t("simulation.complete", [completed])
	(_simulation_ui["status"] as Label).hide()
	(_simulation_ui["progress"] as ProgressBar).hide()
	(_simulation_ui["close"] as Button).text = Locale.t("common.close")


func _add_balance_simulation_result(result: Dictionary) -> void:
	var results: VBoxContainer = _simulation_ui.get("results")
	var placeholder := results.get_node_or_null("SimulationPlaceholder")
	if placeholder != null:
		placeholder.queue_free()
	if results.get_child_count()>0 and placeholder==null:
		results.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.name = "PoolResult_%s" % str(result.get("pool", ""))
	row.custom_minimum_size.y = 42
	row.add_theme_constant_override("separation",16)
	var name_label := Label.new()
	name_label.text = Locale.t("simulation.pool.%s" % str(result.get("pool","units")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(name_label)
	row.add_child(name_label)
	var score: Variant = result.get("strength_score")
	if score != null and bool(result.get("partial_score", false)):
		var qualifier := Label.new()
		qualifier.text = Locale.t("simulation.partial_score")
		qualifier.tooltip_text = Locale.t("simulation.partial_help")
		UITheme.apply_label(qualifier, true)
		row.add_child(qualifier)
	var score_label := Label.new()
	score_label.name = "StrengthScore"
	score_label.custom_minimum_size.x = 64
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.apply_title(score_label,24)
	var unused: bool = int(result.get("candidate", {}).get("plays", 0)) == 0
	score_label.text = str(int(score)) if score != null else Locale.t("simulation.no_plays" if unused else "simulation.insufficient")
	score_label.add_theme_color_override("font_color", UITheme.Tokens.MUTED if score == null else UITheme.strength_score_color(int(score)))
	row.add_child(score_label)
	results.add_child(row)


func _simulation_is_current(generation: int) -> bool:
	return generation == _simulation_generation \
		and _simulation_popup_layer != null \
		and is_instance_valid(_simulation_popup_layer) \
		and not _simulation_popup_layer.is_queued_for_deletion()


func _close_balance_simulation(generation: int) -> void:
	if generation != _simulation_generation:
		return
	_simulation_generation += 1
	if _simulation_popup_layer != null and is_instance_valid(_simulation_popup_layer):
		_simulation_popup_layer.queue_free()
	_simulation_popup_layer = null
	_simulation_ui.clear()


# ============================================
# Card version history
# ============================================

func _current_saved_card() -> CardData:
	if PlayerData.editing_deck_id.is_empty() or PlayerData.editing_instance_id.is_empty():
		return null
	return PlayerData.find_deck_card(PlayerData.editing_deck_id, PlayerData.editing_instance_id)


func _capture_opening_revision() -> void:
	var card := _current_saved_card()
	if card != null:
		PlayerData.record_card_revision(card)


func _record_saved_revision(card: CardData) -> void:
	if card != null:
		PlayerData.record_card_revision(card)
	_refresh_version_history_button()


func _revision_card_id() -> String:
	var card := _current_saved_card()
	if card != null:
		return card.card_id
	return ""


func _refresh_version_history_button() -> void:
	if version_history_button == null:
		return
	var card_id := _revision_card_id()
	var count := PlayerData.get_card_revisions(card_id).size()
	version_history_button.disabled = count == 0
	version_history_button.text = Locale.t("revision.button_count", [count]) if count > 0 else Locale.t("revision.button")
	version_history_button.tooltip_text = Locale.t("revision.button_help") if count > 0 else Locale.t("revision.save_first")


func _on_version_history_pressed() -> void:
	_save_form_to_draft()
	_open_version_history()


func _open_version_history() -> CanvasLayer:
	if _version_history_popup_layer != null and is_instance_valid(_version_history_popup_layer):
		_version_history_popup_layer.queue_free()
	var entries := PlayerData.get_card_revisions(_revision_card_id())
	if entries.is_empty():
		_show_message(Locale.t("revision.save_first"))
		return null
	var popup := UITheme.make_popup_layer(self, 106)
	var popup_layer: CanvasLayer = popup["layer"]
	_version_history_popup_layer = popup_layer
	var panel := Panel.new()
	panel.name = "CardRevisionPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_top = -255
	panel.offset_right = 340
	panel.offset_bottom = 255
	panel.clip_contents = true
	UITheme.apply_popup_frame(panel, "gold")
	popup_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("revision.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 22)
	box.add_child(title)
	var hint := Label.new()
	hint.name = "RevisionHint"
	hint.hide()
	hint.text = Locale.t("revision.hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(hint, true)
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.name = "RevisionScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.apply_scrollbar(scroll.get_h_scroll_bar())
	UITheme.apply_scrollbar(scroll.get_v_scroll_bar())
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "RevisionList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for entry in entries:
		list.add_child(_make_revision_row(entry))
	var close := Button.new()
	close.name = "RevisionCloseButton"
	close.text = Locale.t("common.close")
	close.custom_minimum_size = Vector2(124, 40)
	UITheme.apply_button(close, "secondary")
	close.pressed.connect(func():
		popup_layer.queue_free()
		_version_history_popup_layer = null
	)
	box.add_child(close)
	UITheme.animate_popup_enter(panel)
	return popup_layer


func _make_revision_row(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Revision_%d" % int(entry.get("revision", 0))
	UITheme.apply_panel(panel, "dark")
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 3)
	row.add_child(details)
	var heading := Label.new()
	heading.text = Locale.t("revision.entry", [int(entry.get("revision", 0)), _format_revision_time(int(entry.get("saved_at", 0)))])
	UITheme.apply_title(heading, 16)
	details.add_child(heading)
	var summary := Label.new()
	summary.text = _revision_change_summary(entry.get("card", {}))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(summary, true)
	details.add_child(summary)
	var restore := Button.new()
	restore.name = "RestoreRevisionButton"
	restore.text = Locale.t("revision.restore")
	restore.custom_minimum_size = Vector2(128, 38)
	UITheme.apply_button(restore, "secondary")
	restore.pressed.connect(_restore_revision_to_draft.bind(entry.get("card", {})))
	row.add_child(restore)
	return panel


func _format_revision_time(timestamp: int) -> String:
	var value := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d %02d:%02d" % [value.year, value.month, value.day, value.hour, value.minute]


func _revision_change_summary(snapshot: Dictionary) -> String:
	var current := PlayerData.build_card_from_draft()
	var parts: Array[String] = []
	if str(snapshot.get("name", "")) != current.card_name:
		parts.append(Locale.t("revision.change_name", [str(snapshot.get("name", "")), current.card_name]))
	for field in [["cost", current.cost, "revision.change_cost"], ["max_hp", current.max_hp, "revision.change_hp"], ["atk", current.atk, "revision.change_atk"]]:
		if int(snapshot.get(field[0], 0)) != int(field[1]):
			parts.append(Locale.t(field[2], [int(snapshot.get(field[0], 0)), int(field[1])]))
	if str(snapshot.get("card_type", "minion")) != current.card_type:
		parts.append(Locale.t("revision.change_type"))
	if snapshot.get("skills", []) != current.skills:
		parts.append(Locale.t("revision.change_skills"))
	return Locale.t("revision.current") if parts.is_empty() else ("；" if Locale.language=="zh" else "; ").join(parts)


func _restore_revision_to_draft(snapshot_value: Variant) -> void:
	if not snapshot_value is Dictionary:
		return
	var card := PlayerData.deserialize_card(snapshot_value)
	PlayerData.card_draft = PlayerData.card_to_draft(card)
	PlayerData.queue_card_draft_recovery()
	_restore_form_from_draft()
	_apply_texts()
	_update_skill_labels()
	_apply_card_type_restrictions()
	_update_balance_summary()
	_update_usability_summary()
	_refresh_card_preview()
	if _version_history_popup_layer != null and is_instance_valid(_version_history_popup_layer):
		_version_history_popup_layer.queue_free()
	_version_history_popup_layer = null
	_show_message(Locale.t("revision.restored"))


# ============================================
# Art picker
# ============================================

func _on_browse_art_pressed():
	_browse_art("art_path")


func _art_paste_hint() -> String:
	if _CardArtDropZone.uses_touch_picker() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return ""
	return Locale.t("editor.art_paste")


func _browse_art(field: String) -> void:
	if not _can_import_art():
		return
	_art_edit_field = field
	art_dialog.popup_centered()


func _can_import_art() -> bool:
	return is_visible_in_tree() and not is_instance_valid(_art_crop) and not art_dialog.visible \
		and (not card_tutorial_controller or card_tutorial_controller.allows("browse_art"))


func _art_field_at(point: Vector2) -> String:
	var scroll := $Panel/MarginContainer/ScrollContainer as ScrollContainer
	if not scroll.get_global_rect().has_point(point):
		return ""
	if browse_button.is_visible_in_tree() and browse_button.get_global_rect().has_point(point):
		return "art_path"
	if is_instance_valid(_damaged_art_browse) and _damaged_art_browse.is_visible_in_tree() \
			and _damaged_art_browse.get_global_rect().has_point(point):
		return "damaged_art_path"
	return ""


func _on_art_files_dropped(paths: PackedStringArray) -> void:
	if paths.is_empty() or not _can_import_art():
		return
	var field := _art_field_at(get_global_mouse_position())
	if field.is_empty():
		return
	for path in paths:
		if path.get_extension().to_lower() in ["png", "jpg", "jpeg", "bmp", "webp"]:
			_open_art_crop(Image.load_from_file(path), field)
			return
	_open_art_crop(null, field)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_paste") or not _can_import_art():
		return
	var focus := get_viewport().gui_get_focus_owner()
	var field := _art_field_at(get_global_mouse_position())
	if focus == browse_button:
		field = "art_path"
	elif is_instance_valid(_damaged_art_browse) and focus == _damaged_art_browse:
		field = "damaged_art_path"
	if field.is_empty() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return
	get_viewport().set_input_as_handled()
	_paste_art(field)


func _paste_art(field: String) -> void:
	if not _can_import_art() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return
	if not DisplayServer.clipboard_has_image():
		_show_art_status(field, Locale.t("editor.art_clipboard_empty"))
		return
	_open_art_crop(DisplayServer.clipboard_get_image(), field)


func _on_art_file_selected(path: String) -> void:
	var image := _load_document_image(path) if path.begins_with("content://") else Image.load_from_file(path)
	_open_art_crop(image, _art_edit_field)


func _load_document_image(path: String) -> Image:
	# A gallery or cloud provider can return a numeric ID with no extension.
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12: return null
	var header := bytes.slice(0, 12).hex_encode()
	var image := Image.new()
	var result := ERR_FILE_UNRECOGNIZED
	if header.begins_with("89504e470d0a1a0a"):
		result = image.load_png_from_buffer(bytes)
	elif header.begins_with("ffd8ff"):
		result = image.load_jpg_from_buffer(bytes)
	elif header.begins_with("424d"):
		result = image.load_bmp_from_buffer(bytes)
	elif header.begins_with("52494646") and header.ends_with("57454250"):
		result = image.load_webp_from_buffer(bytes)
	return image if result == OK else null


func _open_art_crop(image: Image, field: String) -> void:
	if is_instance_valid(_art_crop):
		return
	if image == null or image.is_empty():
		_show_art_status(field, Locale.t("editor.art_import_failed"))
		return
	_save_form_to_draft()
	var dialog := preload("res://presentation/CardArtCropDialog.gd").new()
	dialog.source_image = image
	dialog.preview_card = PlayerData.build_card_from_draft()
	dialog.on_saved = func(saved_path):
		PlayerData.card_draft[field] = saved_path
		PlayerData.queue_card_draft_recovery()
		_show_art_status(field, "")
		_refresh_card_preview()
	_art_crop = dialog
	add_child(dialog)
	UIMotion.register_popup(dialog)

func _show_art_status(field: String, message: String) -> void:
	var status: Label = _damaged_art_path if field == "damaged_art_path" else art_path_label
	status.text = message
	status.visible = not message.is_empty()


func _on_clear_art_pressed():
	if card_tutorial_controller and not card_tutorial_controller.allows("clear_art"):
		return
	PlayerData.card_draft["art_path"] = ""
	PlayerData.queue_card_draft_recovery()
	_show_art_status("art_path", "")
	_refresh_card_preview()


# ============================================
# Skill preview
# ============================================

func _configure_skill_summaries() -> void:
	for summary in [skill1_summary, skill2_summary, skill3_summary, talent_summary]:
		if summary == null:
			continue
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.custom_minimum_size.x = 0.0
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _update_skill_labels():
	var card_type: String = PlayerData.card_draft.get("card_type", "minion")
	var is_spell: bool = card_type == "spell"
	var is_parasite: bool = card_type == "parasite"
	skill1_summary.text = _format_skill_short(PlayerData.card_draft.get("skill1", {}))
	skill2_summary.text = _format_skill_short(PlayerData.card_draft.get("skill2", {}))
	skill3_summary.text = _format_skill_short(PlayerData.card_draft.get("skill3", {}))
	var talent: Dictionary = PlayerData.card_draft.get("talent", {})
	var has_talent := not talent.is_empty()
	if not is_spell and not is_parasite:
		skill1_label.text = Locale.t("editor.talent") if has_talent else Locale.t("editor.skill_1")
	talent_summary.text = "%s：%s" % [Locale.t("editor.talent"), _format_skill_short(talent)]
	var has_skill2: bool = not PlayerData.card_draft.get("skill2", {}).is_empty()
	var has_skill3: bool = not PlayerData.card_draft.get("skill3", {}).is_empty()
	# Spell cards only have one skill; parasite cards currently expose one passive skill slot.
	skill2_label.visible = not is_spell and not is_parasite
	skill2_summary.visible = not is_spell and not is_parasite
	skill3_label.visible = not is_spell and not is_parasite
	skill3_summary.visible = not is_spell and not is_parasite
	edit_skill1_btn.visible = true
	edit_talent_btn.visible = not is_spell and not is_parasite
	# Skill 1 and Talent are two modes of the same first slot. Show only the
	# active mode's summary so the editor never presents four simultaneous slots.
	skill1_summary.visible = is_spell or is_parasite or not has_talent
	talent_summary.visible = not is_spell and not is_parasite and has_talent
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

func _setup_template_menu() -> void:
	template_button.icon = template_button.get_theme_icon("arrow", "OptionButton")
	template_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	template_button.focus_mode = Control.FOCUS_ALL
	var menu: PopupMenu = template_button.get_popup()
	UITheme.apply_popup_menu(menu)
	var templates := ["warrior", "healer", "guard", "gunner", "cursed"]
	for index in templates.size():
		menu.add_item(Locale.t("editor.template_%s" % templates[index]), index)
	menu.id_pressed.connect(func(index: int): _apply_template(templates[index]))


func _apply_template(template_id: String) -> void:
	_save_form_to_draft()
	var art_path: String = PlayerData.card_draft.get("art_path", "")
	var damaged_path: String = PlayerData.card_draft.get("damaged_art_path", "")
	var draft := _template_draft(template_id)
	if art_path != "":
		draft["art_path"] = art_path
	draft["damaged_art_path"] = damaged_path
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
	if card_tutorial_controller and not card_tutorial_controller.allows("edit_skill", {"index": 0}):
		return
	_save_form_to_draft()
	PlayerData.editing_skill_index = 0
	if card_tutorial_controller:
		card_tutorial_controller.notify_edit_skill(0)
	UIMotion.change_scene("res://SkillEditor.tscn")


func _on_edit_talent_pressed():
	if card_tutorial_controller:
		card_tutorial_controller.allows("edit_talent")
		return
	_save_form_to_draft()
	PlayerData.editing_skill_index = 3
	UIMotion.change_scene("res://SkillEditor.tscn")


func _on_edit_skill2_pressed():
	if card_tutorial_controller:
		card_tutorial_controller.allows("edit_skill", {"index": 1})
		return
	_save_form_to_draft()
	PlayerData.editing_skill_index = 1
	UIMotion.change_scene("res://SkillEditor.tscn")


func _on_edit_skill3_pressed():
	if card_tutorial_controller:
		card_tutorial_controller.allows("edit_skill", {"index": 2})
		return
	_save_form_to_draft()
	PlayerData.editing_skill_index = 2
	UIMotion.change_scene("res://SkillEditor.tscn")


# ============================================
# Save
# ============================================

func _on_save_button_pressed():
	_save_form_to_draft()
	var safety_issues := _UgcSafety.validate_draft_card(PlayerData.card_draft)
	if not safety_issues.is_empty():
		_show_message(Locale.t("editor.ugc_safety_blocked", [_UgcSafety.first_error_text(safety_issues)]))
		return
	var new_card: CardData = PlayerData.build_card_from_draft()
	if card_tutorial_controller:
		card_tutorial_controller.handle_confirm(new_card)
		return
	if PlayerData.editing_deck_id != "" and PlayerData.editing_instance_id != "":
		_show_sync_edit_popup(new_card)
	else:
		_show_save_targets_popup(new_card)


func _show_sync_edit_popup(new_card: CardData) -> void:
	var original := PlayerData.find_deck_card(PlayerData.editing_deck_id, PlayerData.editing_instance_id)
	if original == null:
		_show_message(Locale.t("editor.need_target_deck"))
		return
	var original_design := SharePackage.gameplay_signature(PlayerData.serialize_card(original))
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
	var selected_ids: Dictionary = {}
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(deck_scroll)
	var deck_box := VBoxContainer.new()
	deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_box.add_theme_constant_override("separation", 6)
	deck_scroll.add_child(deck_box)
	for deck in PlayerData.deck_library:
		var deck_id: String = deck.get("id", "")
		var copies := PlayerData.get_cards_for_deck(deck_id).filter(func(card: CardData): return card.card_name == original.card_name)
		for index in copies.size():
			var card: CardData = copies[index]
			var check := CheckBox.new()
			check.text = PlayerData.deck_display_name(deck)
			if copies.size() > 1:
				check.text += Locale.t("editor.sync_copy_number", [index + 1])
			check.disabled = deck_id == PlayerData.editing_deck_id and card.instance_id == original.instance_id
			var same_design := SharePackage.gameplay_signature(PlayerData.serialize_card(card)) == original_design \
				and PlayerData.same_card_art(card.art_path, original.art_path) \
				and (card.is_spell() or PlayerData.same_card_art(card.damaged_art_path, original.damaged_art_path))
			check.button_pressed = check.disabled or (same_design if _retry_sync_cards.is_empty() \
				else (_retry_sync_cards.get(deck_id, []) as Array).has(card.instance_id))
			var selected: Array = selected_ids.get_or_add(deck_id, [])
			if check.button_pressed:
				selected.append(card.instance_id)
			UITheme.apply_button(check, "secondary")
			check.toggled.connect(func(pressed: bool):
				if pressed:
					selected.append(card.instance_id)
				else:
					selected.erase(card.instance_id))
			deck_box.add_child(check)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var save_btn := Button.new()
	save_btn.text = Locale.t("editor.save_card")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(save_btn, "primary")
	save_btn.pressed.connect(func():
		if not (selected_ids.get(PlayerData.editing_deck_id, []) as Array).has(original.instance_id):
			_show_message(Locale.t("editor.sync_keep_deck"))
			return
		popup_layer.queue_free()
		_apply_synced_edit(new_card, original.card_name, selected_ids)
	)
	row.add_child(save_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("skill_editor.cancel")
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(popup_layer.queue_free)
	row.add_child(cancel_btn)
	UIMotion.register_popup(popup_layer)


func _apply_synced_edit(new_card: CardData, original_name: String, selected_ids: Dictionary) -> void:
	var target_deck_ids := selected_ids.keys().filter(func(id): return not selected_ids[id].is_empty())
	for deck_id_variant in target_deck_ids:
		var deck_id: String = deck_id_variant
		for card in PlayerData.get_cards_for_deck(deck_id):
			if card.card_name == new_card.card_name and card.card_name != original_name:
				_show_message(Locale.t("editor.sync_name_conflict"))
				return
	_clear_pending_save()
	pending_save_target_ids = target_deck_ids
	_pending_sync_cards = selected_ids.duplicate(true)
	for deck_id_variant in target_deck_ids:
		var deck_id: String = deck_id_variant
		for instance_id in selected_ids[deck_id]:
			var staged := _stage_deck_save(deck_id, new_card, instance_id)
			if staged == null:
				_fail_card_save()
				return
			if deck_id == PlayerData.editing_deck_id and instance_id == PlayerData.editing_instance_id:
				pending_saved_card = staged
	_finish_multi_deck_save()


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
		check.text = PlayerData.deck_display_name(deck)
		UITheme.apply_button(check, "secondary")
		check.button_pressed = deck_id == default_deck_id if _retry_save_target_ids.is_empty() else _retry_save_target_ids.has(deck_id)
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
	_clear_pending_save()
	pending_save_card = new_card
	pending_save_target_ids = target_deck_ids
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
	if conflict.get("kind", "") == "same" and ignore_instance.is_empty():
		if pending_saved_card == null:
			pending_saved_card = conflict["card"]
	elif not _save_to_target_deck(deck_id):
		return
	pending_save_index += 1
	_process_next_save_target()


func _save_to_target_deck(deck_id: String) -> bool:
	var instance_id := PlayerData.editing_instance_id if deck_id == PlayerData.editing_deck_id else ""
	pending_saved_card = _stage_deck_save(deck_id, pending_save_card, instance_id)
	if pending_saved_card == null:
		_fail_card_save()
		return false
	return true


func _stage_deck_save(deck_id: String, card: CardData, instance_id: String = "") -> CardData:
	var deck := PlayerData.get_deck(deck_id)
	if deck.is_empty():
		return null
	if not _pending_save_decks.has(deck_id):
		_pending_save_decks[deck_id] = deck["cards"].duplicate()
	var cards: Array = _pending_save_decks[deck_id]
	var saved := card.duplicate_card()
	saved.set_meta(&"modified_at", int(Time.get_unix_time_from_system()))
	if instance_id.is_empty():
		saved = PlayerData.prepare_deck_card(saved, false)
		cards.append(saved)
	else:
		var index := PlayerData.find_deck_card_index(deck_id, instance_id)
		if index < 0:
			return null
		var previous: CardData = cards[index]
		_pending_prior_cards.append(previous)
		saved.instance_id = previous.instance_id
		if saved.card_id.is_empty():
			saved.card_id = previous.card_id
		saved = PlayerData.prepare_deck_card(saved, true)
		cards[index] = saved
	return saved


func _finish_multi_deck_save() -> void:
	var saved_card := pending_saved_card
	if saved_card == null or not PlayerData.save_deck_card_lists(_pending_save_decks):
		_fail_card_save()
		return
	for previous in _pending_prior_cards:
		PlayerData.record_card_revision(previous)
	_record_saved_revision(saved_card)
	PlayerData.card_draft = PlayerData.card_to_draft(saved_card)
	_retry_save_target_ids.clear()
	_retry_sync_cards.clear()
	_show_after_save_popup(saved_card)
	_clear_pending_save()


func _fail_card_save() -> void:
	_retry_save_target_ids = pending_save_target_ids.duplicate()
	_retry_sync_cards = _pending_sync_cards.duplicate(true)
	_clear_pending_save()
	_show_message(Locale.t("editor.card_save_failed"))


func _clear_pending_save() -> void:
	pending_save_card = null
	pending_save_target_ids = []
	pending_save_index = 0
	pending_saved_card = null
	_pending_save_decks.clear()
	_pending_prior_cards.clear()
	_pending_sync_cards.clear()


func _save_card_without_conflict(new_card: CardData) -> void:
	var deck_id := PlayerData.editing_deck_id if not PlayerData.editing_deck_id.is_empty() else PlayerData.current_deck_id
	_start_multi_deck_save(new_card, [deck_id])


func _save_name_taken(deck_id: String, card_name: String) -> bool:
	for card in PlayerData.get_cards_for_deck(deck_id):
		if card.card_name == card_name:
			return true
	return false


func _available_save_name(deck_id: String, base_name: String) -> String:
	return PlayerData.available_card_copy_name(base_name, func(candidate: String): return _save_name_taken(deck_id, candidate))


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
	vbox.add_child(preload("res://CardCollectionDialog.gd").make_comparison(
		Locale.t("share.local_card"), local_card, Locale.t("share.incoming_card"), new_card))
	var input := LineEdit.new()
	input.text = _available_save_name(deck_id,new_card.card_name)
	UITheme.apply_input(input)
	vbox.add_child(input)
	var name_error := Label.new()
	name_error.text = Locale.t("editor.sync_name_conflict")
	name_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(name_error)
	name_error.add_theme_color_override("font_color",UITheme.COLOR_WARNING)
	vbox.add_child(name_error)
	name_error.hide()
	input.text_changed.connect(func(_text): name_error.hide())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var rename_new := Button.new()
	rename_new.text = Locale.t("share.rename_incoming")
	rename_new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(rename_new, "outlined")
	rename_new.pressed.connect(func():
		var new_name := input.text.strip_edges()
		if new_name.is_empty() or _save_name_taken(deck_id, new_name):
			name_error.text = Locale.t("share.rename_empty" if new_name.is_empty() else "editor.sync_name_conflict")
			name_error.show()
			input.grab_focus()
			return
		new_card.card_name = new_name
		popup_layer.queue_free()
		if not _save_to_target_deck(deck_id):
			return
		pending_save_index += 1
		_process_next_save_target()
	)
	row.add_child(rename_new)
	var replace_btn := Button.new()
	replace_btn.text = Locale.t("share.overwrite")
	replace_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(replace_btn, "danger")
	replace_btn.pressed.connect(func():
		pending_saved_card = _stage_deck_save(deck_id, new_card, local_card.instance_id)
		popup_layer.queue_free()
		if pending_saved_card == null:
			_fail_card_save()
			return
		pending_save_index += 1
		_process_next_save_target()
	)
	row.add_child(replace_btn)
	var cancel := func():
		popup_layer.queue_free()
		_clear_pending_save()
	popup_layer.set_meta("popup_close", cancel)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("common.cancel")
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	UITheme.apply_button(cancel_btn, "outlined")
	cancel_btn.pressed.connect(cancel)
	vbox.add_child(cancel_btn)
	input.grab_focus()


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


func _show_after_save_popup(saved_card: CardData) -> void:
	# Keep editing the saved instance when the dialog closes, including a newly
	# created card. Later saves must update it rather than add another copy.
	if _current_saved_card() == null and saved_card != null:
		for deck in PlayerData.deck_library:
			var stored := PlayerData.find_deck_card(str(deck.get("id", "")), saved_card.instance_id)
			if stored != null:
				PlayerData.editing_deck_id = str(deck.get("id", ""))
				PlayerData.editing_instance_id = stored.instance_id
				PlayerData.editing_index = PlayerData.find_deck_card_index(PlayerData.editing_deck_id, stored.instance_id)
				break
	_apply_texts()
	var page := preload("res://SelectionMenu.gd").new()
	page.name = "CardSavedPopup"
	page.layer = 100
	page.heading = Locale.t("editor.saved_title")
	page.backdrop = Color(Color.BLACK, 0.68)
	page.blur_backdrop = true
	add_child(page)
	var keep_editing := page.add_choice(Locale.t("editor.after_save_return"), page.dismiss)
	page.add_choice(Locale.t("editor.after_save_test"), func():
		page.dismiss()
		_start_solo_test(saved_card), Locale.t("editor.playtest_help"))
	UIMotion.register_popup(page, keep_editing)
	page.finish(false)
	UITheme.fade_enter(page.surface, 0.16)


func _return_after_save() -> void:
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_draft.clear()
	PlayerData.clear_card_draft_recovery()
	var return_scene := PlayerData.card_editor_return_scene
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	UIMotion.go_back(return_scene)


func _start_solo_test(saved_card: CardData) -> void:
	PlayerData.configure_card_playtest(saved_card)
	PlayerData.card_playtest_context["exit_scene"] = PlayerData.card_editor_return_scene
	UIMotion.change_scene("res://Main.tscn")


# ============================================
# Back
# ============================================

var _discard_dialog: ConfirmationDialog

func _has_unsaved_card_edits() -> bool:
	_save_form_to_draft()
	var built := PlayerData.build_card_from_draft()
	var saved := _current_saved_card()
	if saved == null and PlayerData.editing_index >= 0 and PlayerData.editing_index < PlayerData.card_library.size():
		saved = PlayerData.card_library[PlayerData.editing_index]
	if saved == null:
		var defaults := PlayerData.default_card_draft(built.card_type)
		defaults["name"] = Locale.t("editor.unnamed")
		saved = PlayerData.build_card_from_draft(defaults)
	return (
		SharePackage.gameplay_signature(PlayerData.serialize_card(built)) != SharePackage.gameplay_signature(PlayerData.serialize_card(saved))
		or built.art_path != saved.art_path
		or built.damaged_art_path != saved.damaged_art_path
		or not SkillUndoManager.deep_equal(built.skills, saved.skills)
	)


func _on_back_button_pressed():
	if card_tutorial_controller:
		card_tutorial_controller._on_exit()
		return
	if _has_unsaved_card_edits():
		if not is_instance_valid(_discard_dialog):
			_discard_dialog = ConfirmationDialog.new()
			_discard_dialog.title = Locale.t("editor.discard_title")
			_discard_dialog.dialog_text = Locale.t("editor.discard_body")
			add_child(_discard_dialog)
			UITheme.apply_dialog(_discard_dialog,true)
			UITheme.apply_destructive_confirmation(_discard_dialog, Locale.t("editor.discard_action"))
			_discard_dialog.confirmed.connect(_discard_card_and_leave)
		_discard_dialog.popup_centered()
		return
	_discard_card_and_leave()


func _discard_card_and_leave():
	if card_tutorial_controller:
		card_tutorial_controller._on_exit()
		return
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_draft.clear()
	PlayerData.clear_card_draft_recovery()
	var return_scene := PlayerData.card_editor_return_scene
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	UIMotion.go_back(return_scene)


func _build_editor_sidebar() -> void:
	_diagnostics_panel = PanelContainer.new()
	_diagnostics_panel.name = "CardDiagnostics"
	_diagnostics_panel.anchor_left = 1.0
	_diagnostics_panel.anchor_right = 1.0
	_diagnostics_panel.anchor_bottom = 1.0
	UITheme.apply_panel(_diagnostics_panel, "dark")
	var sidebar_style := _diagnostics_panel.get_theme_stylebox("panel") as StyleBoxFlat
	sidebar_style.content_margin_left = 16
	sidebar_style.content_margin_right = 16
	sidebar_style.content_margin_top = 16
	sidebar_style.content_margin_bottom = 16
	add_child(_diagnostics_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.pad_scroll_content(scroll, 8)
	_diagnostics_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	for control in [balance_label, balance_summary, usability_summary, analysis_actions_row]:
		control.reparent(box)
	analysis_actions_row.add_theme_constant_override("h_separation", 12)
	analysis_actions_row.add_theme_constant_override("v_separation", 12)
	for label in [balance_summary, usability_summary]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
	_editor_save_dock = CenterContainer.new()
	_editor_save_dock.name = "EditorSaveDock"
	_editor_save_dock.anchor_left = 1.0
	_editor_save_dock.anchor_right = 1.0
	_editor_save_dock.anchor_top = 1.0
	_editor_save_dock.anchor_bottom = 1.0
	add_child(_editor_save_dock)
	save_button.reparent(_editor_save_dock)

func _build_damaged_art_controls() -> void:
	if PlayerData.card_draft.get("card_type", "minion") == "spell":
		return
	var box := $Panel/MarginContainer/ScrollContainer/VBoxContainer
	var at := art_path_label.get_index() + 1
	_damaged_art_label = Label.new()
	box.add_child(_damaged_art_label)
	box.move_child(_damaged_art_label,at)
	UITheme.apply_label(_damaged_art_label)
	var row := HBoxContainer.new()
	row.name="DamagedArtRow"
	row.add_theme_constant_override("separation",8)
	box.add_child(row)
	box.move_child(row,at+1)
	_damaged_art_path = Label.new()
	_damaged_art_path.set_meta("keyword_literal",true)
	_damaged_art_path.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_damaged_art_path.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_damaged_art_path)
	box.move_child(_damaged_art_path, at + 2)
	UITheme.apply_label(_damaged_art_path,true)
	_damaged_art_browse = _CardArtDropZone.new()
	row.add_child(_damaged_art_browse)
	_damaged_art_browse.pressed.connect(_browse_art.bind("damaged_art_path"))
	_damaged_art_browse.paste_requested.connect(_paste_art.bind("damaged_art_path"))
	_damaged_art_clear=Button.new()
	_damaged_art_clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_damaged_art_clear)
	UITheme.apply_button(_damaged_art_clear, "utility")
	_damaged_art_clear.pressed.connect(func():
		PlayerData.card_draft["damaged_art_path"]=""
		PlayerData.queue_card_draft_recovery()
		_show_art_status("damaged_art_path", "")
		_refresh_card_preview())
	_preview_damaged=CheckButton.new()
	_preview_damaged.name="PreviewDamagedArt"
	var header := HBoxContainer.new()
	$CardPreviewPanel/PreviewBox.add_child(header)
	$CardPreviewPanel/PreviewBox.move_child(header,0)
	preview_title.reparent(header)
	preview_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(_preview_damaged)
	UITheme.apply_button(_preview_damaged, "utility", false)
	_preview_damaged.add_theme_font_size_override("font_size",12)
	_preview_damaged.toggled.connect(func(_on): _refresh_card_preview())
