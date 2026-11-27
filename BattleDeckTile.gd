class_name BattleDeckTile
extends Button

signal deck_selected(deck_id: String)
signal deck_inspected(deck_id: String)

var deck_id := ""
var chosen := false
var name_label: Label
var count_label: Label
var selected_label: Label
var content_margin: MarginContainer

func _ready() -> void:
	toggle_mode = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var resting := UITheme.panel_style(Color.TRANSPARENT, UITheme.Tokens.PANEL_SOFT, 0, 0)
	resting.border_width_bottom = 1
	var selected := resting.duplicate() as StyleBoxFlat
	selected.bg_color = UITheme.COLOR_PANEL_DARK
	selected.border_color = UITheme.Tokens.BORDER
	for state in ["normal", "hover"]:
		add_theme_stylebox_override(state, resting)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, selected)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UITheme.add_selection_focus(self)
	content_margin = MarginContainer.new()
	content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	content_margin.add_child(row)
	name_label = Label.new()
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", UITheme.selection_font())
	row.add_child(name_label)
	count_label = Label.new()
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_label(count_label, true)
	row.add_child(count_label)
	selected_label = Label.new()
	selected_label.text = "✓"
	selected_label.custom_minimum_size.x = 22
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_label(selected_label)
	selected_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	row.add_child(selected_label)
	focus_entered.connect(_update_title_color)
	focus_exited.connect(_update_title_color)
	pressed.connect(func(): deck_selected.emit(deck_id))
	gui_input.connect(_on_tile_input)

func configure(deck: Dictionary, ui_scale: float) -> void:
	deck_id = str(deck.get("id", ""))
	name_label.set_meta("keyword_literal",true)
	name_label.text = PlayerData.deck_display_name(deck)
	tooltip_text = ""
	set_meta("suppress_hover_hint",true)
	count_label.text = Locale.t("deck.card_count") % deck.get("cards", []).size()
	apply_ui_scale(ui_scale)

func apply_ui_scale(ui_scale: float) -> void:
	custom_minimum_size = Vector2(200, 48) * ui_scale
	content_margin.add_theme_constant_override("margin_left", maxi(22, int(24 * ui_scale)))
	content_margin.add_theme_constant_override("margin_right", maxi(10, int(18 * ui_scale)))
	name_label.add_theme_font_size_override("font_size", maxi(16, int(22 * ui_scale)))
	for label in [count_label, selected_label]:
		label.add_theme_font_size_override("font_size", maxi(12, int(14 * ui_scale)))

func set_selected(value: bool) -> void:
	chosen = value
	set_pressed_no_signal(value)
	selected_label.modulate.a = 1.0 if value else 0.0
	_update_title_color()


func set_locked(value: bool) -> void:
	if value:
		var style := get_theme_stylebox("pressed" if chosen else "normal")
		add_theme_stylebox_override("disabled", style)
	disabled = value
	_update_title_color()

func _update_title_color() -> void:
	var color := UITheme.COLOR_TEXT if has_focus() else (UITheme.COLOR_GOLD if chosen else UITheme.COLOR_TEXT_MUTED)
	if AppPreferences.get_value("high_contrast"):
		color = UITheme.Tokens.CONTRAST_INK if has_focus() else UITheme.COLOR_TEXT
	name_label.add_theme_color_override("font_color", color)

func _on_tile_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		deck_selected.emit(deck_id)
		deck_inspected.emit(deck_id)
		accept_event()
