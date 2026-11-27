extends Control

# ============================================
# 主菜单
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const MENU_ITEM_HEIGHT := 36.0
const UITheme = preload("res://UITheme.gd")
const SelectionMenu = preload("res://SelectionMenu.gd")
const TabletopMenu = preload("res://presentation/TabletopMenu.gd")

@onready var _menu_surface: Node2D = $MenuSurface
@onready var _menu_column: VBoxContainer = $MenuSurface/MenuColumn
@onready var _menu_items: VBoxContainer = _menu_column.get_node("MenuItems")
@onready var title_label: TextureRect = _menu_column.get_node("TitleArtwork")
@onready var start_battle_btn: Button = _menu_items.get_node("StartBattleButton")
@onready var resume_battle_btn: Button = _menu_items.get_node("ResumeBattleButton")
@onready var tutorial_btn: Button = _menu_items.get_node("TutorialButton")
@onready var card_editor_btn: Button = _menu_items.get_node("CardEditorButton")
@onready var my_cards_btn: Button = _menu_items.get_node("MyCardsButton")
@onready var _workshop_button: Button = _menu_items.get_node("WorkshopButton")
@onready var online_btn: Button = _menu_items.get_node("OnlineButton")
@onready var match_history_btn: Button = _menu_items.get_node("MatchHistoryButton")
@onready var settings_btn: Button = _menu_items.get_node("SettingsButton")

var _title_choices: Array[SelectionMenu] = []
var tabletop_menu: TabletopMenu
var battle_hub_layer: SelectionMenu
var battle_hub_resume_button: Button
var _active_resume_button: Button
var title_tutorial_controller: Node

func _apply_texts() -> void:
	resume_battle_btn.text = Locale.t("menu.resume")
	_update_battle_entry_text()
	tutorial_btn.text = Locale.t("menu.tutorial")
	card_editor_btn.text = Locale.t("menu.card_editor")
	my_cards_btn.text = Locale.t("menu.my_cards")
	_workshop_button.text = "创意工坊" if Locale.language == "zh" else "Workshop"
	online_btn.text = Locale.t("menu.online")
	match_history_btn.text = Locale.t("menu.match_history")
	settings_btn.text = Locale.t("menu.settings")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var screen_size := get_viewport_rect().size
	var s := _ui_scale()
	title_label.custom_minimum_size = Vector2(300, 60) * s
	_menu_column.add_theme_constant_override("separation", roundi((50 + MENU_ITEM_HEIGHT) * s))
	_menu_items.add_theme_constant_override("separation", roundi(4 * s))
	for button in _menu_items.get_children():
		button.custom_minimum_size = Vector2(218, MENU_ITEM_HEIGHT) * s
		button.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
	_align_menu_to_table(screen_size)
	for page in _title_choices:
		_place_title_choices(page)


func _align_menu_to_table(screen_size: Vector2) -> void:
	var s := _ui_scale()
	var list_start := (screen_size - BASE_VIEWPORT_SIZE * s) * 0.5 + Vector2(178, 254) * s
	var list_offset := title_label.custom_minimum_size.y + _menu_column.get_theme_constant("separation")
	var list_center := list_start + Vector2.DOWN * _menu_items.get_combined_minimum_size().y * 0.5
	var vertical_axis := SelectionMenu.tabletop_axis(tabletop_menu, list_center) if tabletop_menu != null else Vector2.DOWN
	_menu_surface.transform = Transform2D(Vector2.RIGHT, vertical_axis, list_start - vertical_axis * list_offset)


func _apply_theme() -> void:
	var bg := Panel.new()
	bg.name = "ThemeBackground"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.get_name() != "headless":
		tabletop_menu = TabletopMenu.new()
		tabletop_menu.name = "TabletopMenu"
		add_child(tabletop_menu)
		bg.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	else:
		UITheme.apply_app_background(bg)
	add_child(bg)
	move_child(bg, 0)

	for button in _menu_items.get_children():
		UITheme.apply_selection_entry(button, UITheme.display_font())


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	var restore_state := UIMotion.consume_restore_state()
	_refresh_resume_button()
	resume_battle_btn.pressed.connect(_on_resume_battle_pressed)
	_apply_theme()
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	tutorial_btn.pressed.connect(_on_tutorial_pressed)
	card_editor_btn.pressed.connect(_on_card_editor_pressed)
	my_cards_btn.pressed.connect(_on_my_cards_pressed)
	_workshop_button.pressed.connect(func(): UIMotion.change_scene("res://Workshop.tscn", "workshop"))
	online_btn.pressed.connect(_on_online_pressed)
	match_history_btn.pressed.connect(func(): UIMotion.change_scene("res://MatchHistory.tscn", "history"))
	settings_btn.pressed.connect(_on_settings_pressed)
	Locale.language_changed.connect(_apply_texts)
	NetworkManager.reconnect_transport_ready.connect(_on_reconnect_transport_ready)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	NetworkManager.reconnect_progress.connect(_on_reconnect_progress)
	_apply_texts()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	if not PlayerData.startup_tutorial_pending:
		var root_focus: Button = {"history": match_history_btn, "workshop": _workshop_button,
			"my_cards": my_cards_btn, "settings": settings_btn}.get(restore_state, start_battle_btn)
		root_focus.grab_focus()
	# "继续编辑"后自动显示卡牌类型选择弹窗
	if PlayerData.startup_tutorial_pending:
		# Consume once per process. Exiting the later chapters can return here
		# freely; an unfinished first launch is offered again after restarting.
		PlayerData.startup_tutorial_pending = false
		UIMotion.clear_history()
		title_tutorial_controller = preload("res://TitleTutorialController.gd").new()
		add_child(title_tutorial_controller)
		title_tutorial_controller.start(self)
	elif PlayerData.continue_editing_flag:
		PlayerData.continue_editing_flag = false
		_show_card_type_popup.call_deferred()
	elif restore_state.get_slice(":", 0) in ["battle_hub", "online", "local_battle", "practice", "challenge_picker", "card_type"]:
		_restore_title_route.call_deferred(restore_state)
	else:
		# MainMenu without a restore state is the navigation root.
		UIMotion.clear_history()


func _on_start_battle_pressed():
	_show_battle_hub_popup()


func _on_tutorial_pressed(return_state: String = "") -> void:
	NetworkManager.close_connection()
	# A tutorial is not a replacement match. Preserve any resumable online/LAN
	# session so the player can return and continue it afterwards.
	PlayerData.begin_card_tutorial()
	UIMotion.change_scene("res://CardEditor.tscn", return_state)


func _push_title_choices(node_name: String, heading: String, depth: int, opener: Button) -> SelectionMenu:
	var previous: CanvasItem = _menu_items if _title_choices.is_empty() else _title_choices.back().surface
	if is_instance_valid(opener) and opener.is_visible_in_tree():
		opener.grab_focus()
	var page := SelectionMenu.new()
	page.name = node_name
	page.heading = heading
	page.layer = depth
	page.placement = _place_title_choices.bind(page)
	if is_instance_valid(opener):
		page.title_entry = opener
	add_child(page)
	_title_choices.append(page)
	previous.hide()
	page.closing.connect(_title_choice_closed.bind(page))
	page.tree_exiting.connect(_title_choice_closed.bind(page))
	if is_instance_valid(page.title_entry):
		page.heading_label.add_theme_font_override("font", opener.get_theme_font("font"))
		page.promote_heading.call_deferred()
	else:
		page.fade_choices.call_deferred()
	return page


func _place_title_choices(page: SelectionMenu) -> void:
	var list_offset := title_label.custom_minimum_size.y + _menu_column.get_theme_constant("separation")
	var scale_value := _ui_scale()
	page.place(_menu_surface.transform.translated_local(Vector2(0, list_offset)), scale_value)


func _title_choice_closed(page: SelectionMenu) -> void:
	if not _title_choices.has(page):
		return
	var was_current: bool = _title_choices.back() == page
	_title_choices.erase(page)
	if page == battle_hub_layer:
		battle_hub_layer = null
		battle_hub_resume_button = null
	if not was_current or is_queued_for_deletion():
		return
	if not _title_choices.is_empty():
		var previous: SelectionMenu = _title_choices.back()
		previous.reveal_from_child(page.title_entry)
	elif is_instance_valid(_menu_items):
		_menu_items.show()
		for button in _menu_items.get_children():
			if button != page.title_entry and button.is_visible_in_tree():
				UITheme.fade_enter(button, 0.14)
		if is_instance_valid(page.title_entry) and page.title_entry.is_visible_in_tree():
			page.title_entry.grab_focus()


func _focus_title_choice(key: String) -> void:
	_title_choices.back().focus_choice(Locale.t(key))


func _restore_title_route(state: String) -> void:
	var branch := state.get_slice(":", 0)
	var entry := state.get_slice(":", 1)
	if branch == "card_type":
		card_editor_btn.grab_focus()
		_show_card_type_popup()
	else:
		_show_battle_hub_popup()
		match branch:
			"online":
				_focus_title_choice("menu.online")
				_show_battle_mode_popup(true)
				if entry in ["mp.dedicated", "mp.direct"]:
					_focus_title_choice(entry)
					_show_online_match_choices(entry == "mp.dedicated")
					var mode := state.get_slice(":", 2)
					_focus_title_choice(mode if not mode.is_empty() else "mp.classic")
					return
			"local_battle", "practice":
				_focus_title_choice("menu.battle_local")
				_show_battle_mode_popup()
				if branch == "practice":
					_focus_title_choice("menu.practice")
					_show_practice_difficulty_popup()
			"challenge_picker":
				var page := _push_title_choices("ChallengePickerLayer", PracticeChallenges.catalog_title(), 150,
					battle_hub_layer.find_choice(PracticeChallenges.catalog_title()))
				PracticeChallenges.add_choices(page)
				if not entry.is_empty():
					_title_choices.back().focus_choice("Challenge_" + entry)
				return
	if not entry.is_empty():
		_focus_title_choice(entry)


func _show_battle_hub_popup() -> void:
	if is_instance_valid(battle_hub_layer):
		return
	var page := _push_title_choices("BattleHub", Locale.t("menu.battle_hub_title"), 110, start_battle_btn)
	battle_hub_layer = page
	if NetworkManager.has_resumable_match_session():
		battle_hub_resume_button = page.add_choice(
			Locale.t("menu.resume"), _resume_from_hub, Locale.t("menu.resume_hint"))
	page.add_choice(Locale.t("menu.battle_local"), func():
		NetworkManager.close_connection()
		NetworkManager.clear_room_session()
		_show_battle_mode_popup())
	page.add_choice(Locale.t("menu.online"), _on_online_pressed)
	page.add_choice(Locale.t("menu.tutorial"), _on_tutorial_pressed.bind("battle_hub"))
	page.add_choice(Locale.t("menu.advanced_tutorial"), func(): UIMotion.change_scene("res://AdvancedTutorial.tscn", "battle_hub:menu.advanced_tutorial"))
	page.add_choice(PracticeChallenges.catalog_title(), _show_challenge_choices)
	page.finish()


func _resume_from_hub() -> void:
	_begin_saved_match_reconnect(battle_hub_resume_button)


func _show_battle_mode_popup(online: bool = false) -> void:
	var opener := start_battle_btn
	if is_instance_valid(battle_hub_layer):
		opener = battle_hub_layer.find_choice(Locale.t("menu.online" if online else "menu.battle_local"))
	var page := _push_title_choices(
		"OnlineModePopup" if online else "BattleModePopup",
		Locale.t("mp.title" if online else "menu.battle_mode"), 120, opener)
	if online:
		page.add_choice(Locale.t("mp.dedicated"), _show_online_match_choices.bind(true))
		page.add_choice(Locale.t("mp.direct"), _show_online_match_choices.bind(false))
	else:
		page.add_choice(Locale.t("menu.hotseat"), _start_hotseat_battle)
		page.add_choice(Locale.t("menu.practice"), _show_practice_difficulty_popup)
	page.finish()


func _show_online_match_choices(dedicated: bool) -> void:
	var connection := "mp.dedicated" if dedicated else "mp.direct"
	var opener := _title_choices.back().find_choice(Locale.t(connection)) as Button
	var page := _push_title_choices("OnlineMatchModePopup", Locale.t(connection), 140, opener)
	if dedicated:
		page.add_choice(Locale.t("matchmaking.ranked"), _enter_matchmaking.bind("ranked"))
		page.add_choice(Locale.t("matchmaking.random"), _enter_matchmaking.bind("random"))
	page.add_choice(Locale.t("mp.classic"), _enter_online_lobby.bind(dedicated, false))
	page.add_choice(Locale.t("team.title"), _enter_online_lobby.bind(dedicated, true))
	page.finish()


func _enter_matchmaking(mode: String) -> void:
	PlayerData.matchmaking_mode = mode
	UIMotion.change_scene("res://MatchmakingLobby.tscn", "online:mp.dedicated:matchmaking." + mode)


func _enter_online_lobby(dedicated: bool, party: bool) -> void:
	var connection := "mp.dedicated" if dedicated else "mp.direct"
	var mode := "team.title" if party else "mp.classic"
	var scene := "res://DedicatedLobby.tscn" if dedicated else "res://DirectLobby.tscn"
	if party:
		NetworkManager.team_room.use_dedicated_lobby = dedicated
		scene = "res://TeamLobby.tscn"
	else:
		PlayerData.prepare_online_selection(scene)
	UIMotion.change_scene(scene, "online:%s:%s" % [connection, mode])


func _show_practice_difficulty_popup() -> void:
	var parent := _title_choices.back() as SelectionMenu
	var page := _push_title_choices("PracticeDifficulty", Locale.t("menu.practice_difficulty"), 130,
		parent.find_choice(Locale.t("menu.practice")))
	for difficulty in ["easy", "normal", "hard"]:
		page.add_choice(Locale.t("menu.ai_%s" % difficulty), _start_practice_battle.bind(difficulty),
			Locale.t("menu.ai_%s_hint" % difficulty))
	page.finish()


func _show_challenge_choices() -> void:
	UIMotion.change_scene("res://presentation/ChallengeLaunch.tscn", "battle_hub:launch.challenges")


func _start_hotseat_battle() -> void:
	PlayerData.prepare_hotseat_selection()
	UIMotion.change_scene("res://BattleDeckSelect.tscn", "local_battle")


func _start_practice_battle(difficulty: String = "normal") -> void:
	PlayerData.prepare_practice_selection(difficulty)
	UIMotion.change_scene("res://BattleDeckSelect.tscn", "practice:menu.ai_" + difficulty)


func _on_card_editor_pressed():
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	PlayerData.return_to_deck_id = ""
	_show_card_type_popup()


func _show_card_type_popup() -> void:
	var page := _push_title_choices("CardTypeChoices", Locale.t("editor.create_new_card"), 110, card_editor_btn)
	if OS.has_feature("android") and PlayerData.has_card_draft_recovery():
		page.add_choice("继续上次的草稿" if Locale.language == "zh" else "Resume last draft", _resume_card_draft)
	page.add_choice(Locale.t("editor.create_minion"), _start_new_card.bind(PlayerData.init_card_draft, "editor.create_minion"),
		SkillHelp.description("card_type", "minion"))
	page.add_choice(Locale.t("editor.create_spell"), _start_new_card.bind(PlayerData.init_spell_draft, "editor.create_spell"),
		SkillHelp.description("card_type", "spell"))
	page.add_choice(Locale.t("editor.create_parasite"), _start_new_card.bind(PlayerData.init_parasite_draft, "editor.create_parasite"),
		SkillHelp.description("card_type", "parasite"))
	page.finish()


func _start_new_card(initialize: Callable, entry: String) -> void:
	initialize.call()
	UIMotion.change_scene("res://CardEditor.tscn", "card_type:" + entry)


func _resume_card_draft() -> void:
	if not PlayerData.restore_card_draft_recovery():
		return
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	var workspace: Variant = PlayerData.recovered_card_draft.get("interrupted_skill", {})
	if workspace is Dictionary and workspace.get("skill") is Dictionary and int(workspace.get("index", -1)) in [0, 1, 2, 3]:
		PlayerData.editing_skill_index = int(workspace.index)
		UIMotion.replace_scene("res://SkillEditor.tscn", true, "recover_skill")
	else:
		UIMotion.change_scene("res://CardEditor.tscn", "card_type")


func _on_my_cards_pressed():
	UIMotion.change_scene("res://MyCards.tscn", "my_cards")


func _on_online_pressed() -> void:
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	_show_battle_mode_popup(true)


func _on_settings_pressed() -> void:
	UIMotion.change_scene("res://SettingsMenu.tscn", "settings")


func _on_resume_battle_pressed() -> void:
	_begin_saved_match_reconnect(resume_battle_btn)


func _begin_saved_match_reconnect(source_button: Button) -> void:
	if not NetworkManager.has_resumable_match_session():
		_refresh_resume_button()
		return
	_active_resume_button = source_button
	if _active_resume_button:
		_active_resume_button.disabled = true
		_active_resume_button.text = Locale.t("menu.reconnecting")
	if not NetworkManager.begin_saved_match_reconnect():
		_on_reconnect_failed("no_saved_session")


func _on_reconnect_transport_ready() -> void:
	UIMotion.change_scene("res://Main.tscn")


func _on_reconnect_progress(elapsed_seconds: int, attempt: int) -> void:
	if _active_resume_button and is_instance_valid(_active_resume_button):
		_active_resume_button.text = Locale.t("menu.reconnecting_progress", [attempt, elapsed_seconds])


func _on_reconnect_failed(_reason: String) -> void:
	var can_retry := NetworkManager.has_resumable_match_session()
	if _active_resume_button and is_instance_valid(_active_resume_button):
		_active_resume_button.disabled = not can_retry
		_active_resume_button.text = Locale.t("menu.reconnect_failed") if can_retry else Locale.t("menu.resume")
	_update_battle_entry_text()


func _refresh_resume_button() -> void:
	var can_resume := NetworkManager.has_resumable_match_session()
	# The legacy node stays as a compatibility hook for tests/callers; all
	# player-facing battle actions now live in the unified battle hub.
	resume_battle_btn.visible = false
	resume_battle_btn.disabled = false
	resume_battle_btn.text = Locale.t("menu.resume")
	resume_battle_btn.tooltip_text = Locale.t("menu.resume_hint")
	_update_battle_entry_text(can_resume)


func _update_battle_entry_text(can_resume: Variant = null) -> void:
	if not is_instance_valid(start_battle_btn):
		return
	var resumable: bool = NetworkManager.has_resumable_match_session() if can_resume == null else bool(can_resume)
	start_battle_btn.text = Locale.t("menu.battle_entry_resume" if resumable else "menu.battle_entry")
	start_battle_btn.tooltip_text = Locale.t("menu.resume_hint") if resumable else Locale.t("menu.battle_hub_hint")
