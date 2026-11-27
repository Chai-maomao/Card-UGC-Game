class_name TitleTutorialController
extends Node

enum Phase { WELCOME, CONTRAST, COLLECTION, BATTLE, CREATE }

var menu: Control
var phase := Phase.WELCOME
var progress_path: String = PlayerData.tutorial_progress_path
var overlay_layer: CanvasLayer
var instruction_panel: PanelContainer
var step_label: Label
var title_label: Label
var body_label: Label
var next_button: Button
var skip_button: Button
var contrast_choices: HBoxContainer
var high_contrast_button: Button
var low_contrast_button: Button
var _contrast_chosen := false
var focus_frame: Panel
var _button_states: Dictionary = {}
var _dim_rects: Array[ColorRect] = []
var _leaving := false


func start(owner_menu: Control) -> void:
	menu = owner_menu
	# Also gate keyboard shortcuts/focus behind the modal introduction.
	for button in menu.find_children("*", "Button", true, false):
		_button_states[button] = {
			"disabled": button.disabled,
			"style_override": button.has_theme_stylebox_override("disabled"),
			"style": button.get_theme_stylebox("disabled"),
			"color_override": button.has_theme_color_override("font_disabled_color"),
			"color": button.get_theme_color("font_disabled_color"),
		}
		button.disabled = true
		# Modal gating must not erase the menu labels we are teaching.
		button.add_theme_stylebox_override("disabled", button.get_theme_stylebox("normal"))
		button.add_theme_color_override("font_disabled_color", button.get_theme_color("font_color"))
	_build_ui()
	Locale.language_changed.connect(_apply_texts)
	set_phase(Phase.WELCOME)
	next_button.grab_focus()


func _build_ui() -> void:
	var popup := UITheme.make_popup_layer(menu, 130)
	overlay_layer = popup.layer
	overlay_layer.set_meta("popup_close_locked", true)
	# The backdrop deliberately cannot dismiss the mandatory introduction.
	var backdrop := popup.bg as ColorRect
	backdrop.color = Color.TRANSPARENT
	for index in range(4):
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.62)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.add_child(dim)
		_dim_rects.append(dim)
	focus_frame = Panel.new()
	focus_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_frame.add_theme_stylebox_override("panel", UITheme.panel_style(Color.TRANSPARENT, UITheme.COLOR_GOLD, 3, 8))
	overlay_layer.add_child(focus_frame)
	instruction_panel = PanelContainer.new()
	UITheme.apply_popup_frame(instruction_panel, "gold", false, true)
	overlay_layer.add_child(instruction_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	instruction_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	box.add_child(header)
	step_label = Label.new()
	UITheme.apply_label(step_label, true)
	header.add_child(step_label)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_title(title_label, 22)
	header.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size.y = 48
	UITheme.apply_label(body_label)
	body_label.add_theme_font_size_override("font_size", 16)
	box.add_child(body_label)
	contrast_choices = HBoxContainer.new()
	contrast_choices.add_theme_constant_override("separation", 12)
	box.add_child(contrast_choices)
	var modes := ButtonGroup.new()
	high_contrast_button = _add_contrast_choice(true, modes)
	low_contrast_button = _add_contrast_choice(false, modes)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	next_button = Button.new()
	next_button.custom_minimum_size = Vector2(220, 44)
	UITheme.apply_button(next_button, "primary")
	next_button.pressed.connect(_on_next)
	buttons.add_child(next_button)
	skip_button = Button.new()
	skip_button.custom_minimum_size = Vector2(160, 44)
	UITheme.apply_button(skip_button, "secondary")
	skip_button.pressed.connect(_on_skip)
	buttons.add_child(skip_button)


func _add_contrast_choice(high_contrast: bool, modes: ButtonGroup) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = modes
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(button, "secondary", false, high_contrast)
	contrast_choices.add_child(button)
	button.pressed.connect(_choose_contrast.bind(high_contrast))
	return button


func _choose_contrast(high_contrast: bool) -> void:
	if phase != Phase.CONTRAST:
		return
	AppPreferences.set_value("high_contrast", high_contrast)
	_contrast_chosen = true
	UITheme.apply_label(step_label, true)
	UITheme.apply_button(next_button, "primary")
	UITheme.apply_button(skip_button, "secondary")
	for button in _button_states:
		UITheme._update_selection_color(button)
		button.add_theme_color_override("font_disabled_color", button.get_theme_color("font_color"))
	_apply_texts()


func set_phase(next_phase: int) -> void:
	phase = next_phase
	contrast_choices.visible = phase == Phase.CONTRAST
	focus_frame.visible = phase != Phase.CONTRAST
	_dim_rects[0].color.a = 0.38 if phase == Phase.CONTRAST else 0.62
	_apply_texts()
	_update_layout()
	if phase == Phase.CONTRAST:
		high_contrast_button.grab_focus()
	else:
		next_button.grab_focus()


func _apply_texts() -> void:
	var key: String = ["welcome", "contrast", "collection", "battle", "create"][phase]
	step_label.text = Locale.t("tutorial.title_step", [phase + 1, Phase.size()])
	title_label.text = Locale.t("tutorial.title_" + key + "_title")
	var args: Array = [[menu.start_battle_btn.text, menu.tutorial_btn.text], [], [menu.my_cards_btn.text], [menu.start_battle_btn.text], [menu.card_editor_btn.text]][phase]
	body_label.text = Locale.t("tutorial.title_" + key + "_body", args)
	next_button.text = Locale.t("tutorial.title_begin") if phase == Phase.CREATE else Locale.t("tutorial.next")
	next_button.disabled = phase == Phase.CONTRAST and not _contrast_chosen
	skip_button.text = Locale.t("tutorial.skip")
	high_contrast_button.text = ("✓  " if high_contrast_button.button_pressed else "") + Locale.t("preferences.high_contrast")
	low_contrast_button.text = ("✓  " if low_contrast_button.button_pressed else "") + Locale.t("tutorial.title_low_contrast")


func _process(_delta: float) -> void:
	if menu != null and not _leaving:
		_update_layout()


func _update_layout() -> void:
	var screen: Vector2 = menu.get_viewport_rect().size
	instruction_panel.custom_minimum_size.x = minf(740, screen.x - 36)
	instruction_panel.size.x = instruction_panel.custom_minimum_size.x
	instruction_panel.size.y = instruction_panel.get_combined_minimum_size().y
	instruction_panel.position = Vector2((screen.x - instruction_panel.size.x) / 2, screen.y - instruction_panel.size.y - 14)
	if phase == Phase.CONTRAST:
		for index in range(_dim_rects.size()):
			_dim_rects[index].position = Vector2.ZERO
			_dim_rects[index].size = screen if index == 0 else Vector2.ZERO
		return
	var targets := {
		Phase.WELCOME: menu.title_label,
		Phase.COLLECTION: menu.my_cards_btn,
		Phase.BATTLE: menu.start_battle_btn,
		Phase.CREATE: menu.card_editor_btn,
	}
	var target: Control = targets[phase]
	var bounds := (target.get_global_transform() * Rect2(Vector2.ZERO, target.size)).grow(6)
	focus_frame.position = bounds.position
	focus_frame.size = bounds.size
	var regions := [
		Rect2(0, 0, screen.x, bounds.position.y),
		Rect2(0, bounds.end.y, screen.x, maxf(0, screen.y - bounds.end.y)),
		Rect2(0, bounds.position.y, bounds.position.x, bounds.size.y),
		Rect2(bounds.end.x, bounds.position.y, maxf(0, screen.x - bounds.end.x), bounds.size.y),
	]
	for index in range(_dim_rects.size()):
		_dim_rects[index].position = regions[index].position
		_dim_rects[index].size = regions[index].size


func _on_next() -> void:
	if _leaving or next_button.disabled:
		return
	if phase < Phase.CREATE:
		set_phase(phase + 1)
		return
	_leaving = true
	next_button.disabled = true
	skip_button.disabled = true
	# Reuse the real full-card -> skill -> battlefield tutorial route.
	menu._on_tutorial_pressed()


func _on_skip() -> void:
	if _leaving:
		return
	_leaving = true
	var error := TutorialProgress.new(progress_path).mark_skipped()
	if error != OK:
		push_warning("Could not save tutorial skip (error %d)" % error)
	_restore_buttons()
	overlay_layer.queue_free()
	menu.title_tutorial_controller = null
	menu.start_battle_btn.grab_focus()
	queue_free()


func _exit_tree() -> void:
	_restore_buttons()


func _restore_buttons() -> void:
	for button in _button_states:
		if is_instance_valid(button):
			var saved: Dictionary = _button_states[button]
			button.disabled = saved.disabled
			if saved.style_override:
				button.add_theme_stylebox_override("disabled", saved.style)
			else:
				button.remove_theme_stylebox_override("disabled")
			if saved.color_override:
				button.add_theme_color_override("font_disabled_color", saved.color)
			else:
				button.remove_theme_color_override("font_disabled_color")
	_button_states.clear()
