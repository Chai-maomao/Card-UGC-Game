extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")

@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel
@onready var language_label = $CenterContainer/VBoxContainer/LanguageLabel
@onready var language_option = $CenterContainer/VBoxContainer/LanguageOption
@onready var resolution_label = $CenterContainer/VBoxContainer/ResolutionLabel
@onready var resolution_option = $CenterContainer/VBoxContainer/ResolutionOption
@onready var playback_speed: HSlider = $CenterContainer/VBoxContainer/PlaybackSpeed
@onready var playback_speed_label: Label = $CenterContainer/VBoxContainer/PlaybackSpeedLabel
@onready var back_button = $CenterContainer/VBoxContainer/BackButton
@onready var version_label = $VersionLabel

var embedded_close: Callable
var _settings_panel: PanelContainer
var _settings_scroll: ScrollContainer
var _category_heading: Label
var _preference_controls: Dictionary = {}
var _preference_labels: Dictionary = {}
var _binding_buttons: Dictionary = {}
var _binding_labels: Dictionary = {}
var _binding_capture := ""
var _reset_keys_button: Button
var _support_button: Button
var _pages: Dictionary = {}
var _category_buttons: Dictionary = {}
var _active_category := "display"
var _quit_button: Button
var _quit_dialog: ConfirmationDialog
var _reset_button: Button
var _title_cards_button: Button
const CATEGORIES := ["display","audio","gameplay","controls"]

const LANGUAGE_CODES := ["zh", "en"]
const LANGUAGE_LABELS := ["简体中文", "English"]


func _ready() -> void:
	_apply_theme()
	_build_preferences()
	_setup_options()
	_apply_texts()
	_apply_responsive_layout()
	language_option.item_selected.connect(_on_language_selected)
	resolution_option.item_selected.connect(_on_resolution_selected)
	playback_speed.value_changed.connect(_on_playback_speed_changed)
	back_button.pressed.connect(_on_back_pressed)
	Locale.language_changed.connect(_apply_texts)
	AppPreferences.changed.connect(func(key):
		if key == "title_card_ids": _refresh_title_cards_button()
		if key in ["text_size","high_contrast","appearance"]:
			UITheme.theme_tree(self)
		var control := _preference_controls.get(key) as Control
		if control is Range:
			control.set_value_no_signal(float(AppPreferences.get_value(key)))
		elif key == "appearance" and control is OptionButton:
			control.select(int(AppPreferences.get_value(key))))
	get_viewport().size_changed.connect(_apply_responsive_layout)


func _setup_options() -> void:
	language_option.clear()
	for label in LANGUAGE_LABELS:
		language_option.add_item(label)
	language_option.selected = max(0, LANGUAGE_CODES.find(Locale.language))
	resolution_option.clear()
	for index in WindowSizeController.WINDOW_PRESETS.size():
		resolution_option.add_item(WindowSizeController.preset_label(index))
	resolution_option.selected = WindowSizeController.get_current_preset_index()
	playback_speed.set_value_no_signal(GamePreferences.battle_playback_speed())


func _apply_texts() -> void:
	title_label.text = Locale.t("settings.title")
	language_label.text = Locale.t("settings.language")
	resolution_label.text = Locale.t("settings.resolution")
	_update_playback_speed_label()
	back_button.text = Locale.t("common.back")
	version_label.text = Locale.t("settings.version", [AppVersion.VERSION])
	for category in _category_buttons: _category_buttons[category].text = Locale.t("settings.category_"+category)
	_category_heading.text = Locale.t("settings.category_" + _active_category)
	for action in _binding_buttons: _update_key_button(_binding_buttons[action],action)
	if _reset_keys_button != null: _reset_keys_button.text = Locale.t("settings.reset_keys")
	if _quit_button != null:
		if OS.has_feature("android"):
			_quit_button.text = "退出游戏" if Locale.language == "zh" else "Quit Game"
		else:
			_quit_button.text = "退出到桌面" if Locale.language == "zh" else "Quit to Desktop"
	if _support_button != null: _support_button.text = Locale.t("support.title")
	_refresh_title_cards_button()
	for key in _preference_labels: _preference_labels[key].text = Locale.t("preferences."+key)
	for key in ["appearance","quality","fps","text_size","window_mode"]:
		if not _preference_controls.has(key): continue
		var option: OptionButton = _preference_controls[key]
		if key == "appearance":
			option.set_item_text(0, Locale.t("preferences.appearance_dark"))
			option.set_item_text(1, Locale.t("preferences.appearance_light"))
		elif key == "window_mode":
			for i in range(3): option.set_item_text(i,Locale.t("settings.mode_"+["fullscreen","windowed","borderless"][i]))
		elif key in ["quality","text_size"]:
			for i in range(3): option.set_item_text(i,Locale.t("preferences."+(["low","medium","high"][i] if key == "quality" else ["normal","large","largest"][i])))
		else: option.set_item_text(0,Locale.t("preferences.unlimited"))


func _apply_theme() -> void:
	var background := Panel.new()
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(background)
	add_child(background)
	move_child(background, 0)
	_settings_panel = PanelContainer.new()
	UITheme.apply_app_background(_settings_panel)
	$CenterContainer.add_child(_settings_panel)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	_settings_panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",20)
	margin.add_child(layout)
	title_label.reparent(layout)
	UITheme.apply_title(title_label, 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",28)
	layout.add_child(body)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 152
	navigation.add_theme_constant_override("separation",8)
	body.add_child(navigation)
	var settings_surface := PanelContainer.new()
	settings_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_panel(settings_surface, "dark")
	body.add_child(settings_surface)
	var category_layout := VBoxContainer.new()
	category_layout.add_theme_constant_override("separation", 4)
	settings_surface.add_child(category_layout)
	var category_header := MarginContainer.new()
	category_header.add_theme_constant_override("margin_left", 16)
	category_header.add_theme_constant_override("margin_right", 16)
	category_header.add_theme_constant_override("margin_top", 8)
	category_layout.add_child(category_header)
	var category_title := VBoxContainer.new()
	category_title.add_theme_constant_override("separation", 8)
	category_header.add_child(category_title)
	_category_heading = Label.new()
	UITheme.apply_title(_category_heading, 20)
	category_title.add_child(_category_heading)
	category_title.add_child(UITheme.separator())
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.follow_focus = true
	UITheme.pad_scroll_content(_settings_scroll, 16)
	category_layout.add_child(_settings_scroll)
	var page_holder := VBoxContainer.new()
	page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.add_child(page_holder)
	for category in CATEGORIES:
		var tab := Button.new()
		tab.toggle_mode = true
		tab.custom_minimum_size.y = 46
		UITheme.apply_button(tab, "navigation")
		navigation.add_child(tab)
		_category_buttons[category] = tab
		tab.pressed.connect(func(): _show_category(category))
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation",12)
		page_holder.add_child(page)
		_pages[category] = page
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",12)
	layout.add_child(footer)
	back_button.reparent(footer)
	back_button.custom_minimum_size = Vector2(150,44)
	_quit_button = Button.new()
	_quit_button.name = "QuitToDesktop"
	UITheme.apply_button(_quit_button, "utility")
	_quit_button.pressed.connect(_confirm_quit)
	footer.add_child(_quit_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_support_button = Button.new()
	UITheme.apply_button(_support_button, "utility")
	footer.add_child(_support_button)
	_support_button.pressed.connect(func(): add_child(preload("res://presentation/SupportPanel.gd").new()))
	_reset_button = Button.new()
	UITheme.apply_button(_reset_button, "utility")
	footer.add_child(_reset_button)
	_preference_labels["reset"] = _reset_button
	version_label.hide()
	UITheme.apply_label(language_label)
	UITheme.apply_label(resolution_label)
	UITheme.apply_label(version_label, true)
	UITheme.apply_button(language_option, "secondary")
	UITheme.apply_button(resolution_option, "secondary")
	UITheme.apply_label(playback_speed_label)
	UITheme.place_page_back(self, back_button)


func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	$CenterContainer.offset_top = 64
	if _settings_panel: _settings_panel.custom_minimum_size = Vector2(minf(1040,viewport_size.x-32),viewport_size.y-96)
	if _settings_scroll: _settings_scroll.custom_minimum_size = Vector2(0,maxf(104,viewport_size.y-356))


func _on_language_selected(index: int) -> void:
	if index >= 0 and index < LANGUAGE_CODES.size():
		Locale.set_language(LANGUAGE_CODES[index])


func _on_resolution_selected(index: int) -> void:
	WindowSizeController.apply_preset(index)


func _on_playback_speed_changed(value: float) -> void:
	GamePreferences.set_battle_playback_speed(int(value))
	_update_playback_speed_label()


func _update_playback_speed_label() -> void:
	var keys := ["settings.playback_default", "settings.playback_medium", "settings.playback_fast"]
	playback_speed_label.text = Locale.t("settings.playback_speed", [Locale.t(keys[int(playback_speed.value)])])


func _show_category(category: String) -> void:
	var changed := category != _active_category
	if category != "controls" and not _binding_capture.is_empty():
		UIMotion.key_capture = Callable()
		_binding_capture = ""
		for action in _binding_buttons: _update_key_button(_binding_buttons[action],action)
	_active_category = category
	_category_heading.text = Locale.t("settings.category_" + category)
	for key in _pages:
		_pages[key].visible = key == category
		_category_buttons[key].set_pressed_no_signal(key == category)
	_settings_scroll.scroll_vertical = 0
	if changed:
		UITheme.fade_enter(_pages[category], 0.14)

func _setting_row(category: String,label: Label,control: Control) -> void:
	if _pages[category].get_child_count() > 0:
		_pages[category].add_child(UITheme.separator())
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation",20)
	_pages[category].add_child(row)
	if label.get_parent() != null: label.reparent(row)
	else: row.add_child(label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(label)
	if control.get_parent() != null: control.reparent(row)
	else: row.add_child(control)
	control.custom_minimum_size.x = 220


func _build_preferences() -> void:
	_setting_row("gameplay",language_label,language_option)
	_setting_row("display",resolution_label,resolution_option)
	if OS.has_feature("android"):
		resolution_option.get_parent().hide()
	_setting_row("gameplay",playback_speed_label,playback_speed)
	var title_cards_label := Label.new()
	_preference_labels["title_cards"] = title_cards_label
	_title_cards_button = Button.new()
	_title_cards_button.name = "TitleCardsButton"
	UITheme.apply_button(_title_cards_button,"secondary")
	_title_cards_button.pressed.connect(_choose_title_cards)
	_setting_row("gameplay",title_cards_label,_title_cards_button)
	for key in ["appearance","window_mode","high_contrast","vsync","fps","quality","master","bgm","sfx","mute","reduced_motion","camera_shake","text_size"]:
		if key == "window_mode" and OS.has_feature("android"): continue
		var label := Label.new()
		_preference_labels[key] = label
		var control: Control
		if key in ["master","bgm","sfx","ui"]:
			var slider := HSlider.new()
			slider.max_value = 1
			slider.step = 0.01
			slider.value = float(AppPreferences.get_value(key))
			slider.value_changed.connect(func(value): AppPreferences.set_value(key,value))
			control = slider
		elif key in ["appearance","fps","quality","text_size","window_mode"]:
			var option := OptionButton.new()
			var options: Array = [0,30,60,120,144] if key == "fps" else ([0,1] if key == "appearance" else [0,1,2])
			for value in options: option.add_item(str(value))
			option.selected = options.find(int(AppPreferences.get_value(key)))
			option.item_selected.connect(func(index): AppPreferences.set_value(key,options[index]))
			UITheme.apply_button(option,"secondary")
			UITheme.apply_popup_menu(option.get_popup())
			control = option
		else:
			var check := CheckButton.new()
			check.button_pressed = bool(AppPreferences.get_value(key))
			check.toggled.connect(func(value): AppPreferences.set_value(key,value))
			control = check
		control.custom_minimum_size = Vector2(150,36)
		var category := "audio" if key in ["master","bgm","sfx","ui","mute"] else ("gameplay" if key in ["reduced_motion","camera_shake","text_size"] else "display")
		_setting_row(category,label,control)
		_preference_controls[key] = control
	if OS.has_feature("android"):
		var touch_guide := Label.new()
		touch_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.apply_label(touch_guide)
		_pages["controls"].add_child(touch_guide)
		_preference_labels["touch_guide"] = touch_guide
	for action in AppPreferences.KEY_DEFAULTS:
		var label := Label.new()
		label.text = Locale.t("preferences."+action)
		_binding_labels[action] = label
		var binding := Button.new()
		UITheme.apply_button(binding,"secondary")
		binding.name = "Binding_%s" % action
		_setting_row("controls",label,binding)
		binding.custom_minimum_size = Vector2(160,44)
		_update_key_button(binding,action)
		_binding_buttons[action] = binding
		binding.pressed.connect(func():
			for other in _binding_buttons: _update_key_button(_binding_buttons[other],other)
			_binding_capture = action
			UITheme.apply_button(binding,"primary")
			binding.text = Locale.t("preferences.press_key")
			UIMotion.key_capture = func(code):
				_binding_capture = ""
				if code != KEY_ESCAPE and not AppPreferences.bind_key(action,code): UITheme.reject_button(binding)
				_update_key_button(binding,action))
	_reset_keys_button = Button.new()
	_reset_keys_button.text = Locale.t("settings.reset_keys")
	_reset_keys_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	UITheme.apply_button(_reset_keys_button,"secondary")
	_pages["controls"].add_child(_reset_keys_button)
	_reset_keys_button.pressed.connect(func():
		UIMotion.key_capture = Callable()
		_binding_capture = ""
		AppPreferences.reset_bindings()
		for action in _binding_buttons: _update_key_button(_binding_buttons[action],action))
	_reset_button.pressed.connect(func():
		AppPreferences.reset()
		GamePreferences.set_battle_playback_speed(GamePreferences.PlaybackSpeed.DEFAULT)
		Locale.set_language(Locale.DEFAULT_LANGUAGE)
		WindowSizeController.apply_preset(WindowSizeController.DEFAULT_PRESET_INDEX)
		_setup_options()
		_apply_texts()
		for key in _preference_controls:
			var control: Control = _preference_controls[key]
			if control is OptionButton: control.selected = [0,30,60,120,144].find(AppPreferences.get_value(key)) if key == "fps" else int(AppPreferences.get_value(key))
			elif control is BaseButton: control.set_pressed_no_signal(AppPreferences.get_value(key)))
	$CenterContainer/VBoxContainer.queue_free()
	_show_category(_active_category)


func _on_back_pressed() -> void:
	if embedded_close.is_valid(): embedded_close.call()
	else: UIMotion.go_back("res://MainMenu.tscn")


func _update_key_button(button: Button, action: String) -> void:
	button.text = OS.get_keycode_string(AppPreferences.bindings[action]).replace("Escape","Esc")
	UITheme.apply_button(button,"secondary")
	if _binding_labels.has(action): _binding_labels[action].text = Locale.t("preferences."+action)

func _exit_tree() -> void:
	UIMotion.key_capture = Callable()

func _confirm_quit() -> void:
	if not is_instance_valid(_quit_dialog):
		_quit_dialog = ConfirmationDialog.new()
		_quit_dialog.name = "QuitConfirmation"
		_quit_dialog.min_size.x = 360
		add_child(_quit_dialog)
		UITheme.apply_dialog(_quit_dialog,true)
		_quit_dialog.confirmed.connect(AppAudio.quit_to_desktop)
	_quit_dialog.title = _quit_button.text
	_quit_dialog.dialog_text = "确定退出游戏？" if Locale.language == "zh" else "Quit the game?"
	UITheme.apply_destructive_confirmation(_quit_dialog, "退出" if Locale.language == "zh" else "Quit")
	_quit_dialog.popup_centered()

func _refresh_title_cards_button() -> void:
	if _title_cards_button == null: return
	var count := (AppPreferences.get_value("title_card_ids") as Array).size()
	_title_cards_button.text = ("选择卡牌（%d/5）" if Locale.language == "zh" else "Choose Cards (%d/5)") % count


func _choose_title_cards() -> void:
	var dialog = preload("res://CardCollectionDialog.gd").new()
	# Deck copies share the same ID used by the title screen.
	var index_by_card_id := {}
	for card: CardData in PlayerData.card_library:
		if not card.card_id.is_empty():
			if index_by_card_id.has(card.card_id):
				continue
			index_by_card_id[card.card_id] = dialog.cards.size()
		dialog.cards.append(card)
	dialog.heading = "主界面展示卡牌（最多5张，留空使用默认）" if Locale.language == "zh" else "Main Menu Cards (up to 5; leave empty for defaults)"
	dialog.pick_limit = 5
	dialog.allow_empty_selection = true
	dialog.limit_feedback = true
	dialog.on_confirm = func(chosen: Array):
		var ids: Array[String] = []
		for card in chosen:
			PlayerData.ensure_card_id(card)
			ids.append(card.card_id)
		AppPreferences.set_value("title_card_ids",ids)
	add_child(dialog)
	for card_id in AppPreferences.get_value("title_card_ids"):
		if index_by_card_id.has(card_id):
			dialog._select(true, index_by_card_id[card_id])
