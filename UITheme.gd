extends RefCounted
class_name UITheme

const Tokens = preload("res://DesignTokens.gd")
const FONT_FILE = preload("res://res/fonts/NotoSansSC.ttf")
const DISPLAY_FONT_FILE = preload("res://res/fonts/NotoSerifSC-SemiBold.ttf")
const POPUP_RADIUS := 4
const DIALOG_INSET := 26
static var _regular: FontVariation
static var _medium: FontVariation
static var _bold: FontVariation
static var _display: FontVariation
static var _selection_slanted: FontVariation
static var _bronze_surfaces: Dictionary = {}

static func regular_font() -> Font:
	if _regular == null:
		_regular = FontVariation.new()
		_regular.base_font = FONT_FILE
		_regular.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):400.0}
		_regular.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"):1}
	return _regular


static func medium_font() -> Font:
	if _medium == null:
		_medium = FontVariation.new()
		_medium.base_font = FONT_FILE
		_medium.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
		_medium.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"):1}
	return _medium

static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = FONT_FILE
		_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):700.0}
	return _bold


static func display_font() -> Font:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = DISPLAY_FONT_FILE
		_display.fallbacks = [regular_font()]
	return _display


static func selection_font() -> Font:
	if Locale.language != "en":
		return display_font()
	if _selection_slanted == null:
		_selection_slanted = display_font().duplicate() as FontVariation
		_selection_slanted.variation_transform = Transform2D(Vector2.RIGHT, Vector2(0.10, 1.0), Vector2.ZERO)
	return _selection_slanted


static func apply_selection_entry(button: Button) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", selection_font())
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 22.0
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_MUTED.darkened(0.2))
	_update_selection_color(button)
	button.focus_entered.connect(_update_selection_color.bind(button))
	button.focus_exited.connect(_update_selection_color.bind(button))
	add_selection_focus(button)


static func _update_selection_color(button: Button) -> void:
	var high_contrast := bool(AppPreferences.get_value("high_contrast"))
	var color := COLOR_TEXT if high_contrast else COLOR_TEXT_MUTED
	if button.has_focus():
		color = Color.WHITE if high_contrast else COLOR_TEXT
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_pressed_color", Color.WHITE if high_contrast else COLOR_GOLD)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE if high_contrast else COLOR_GOLD)
	button.add_theme_color_override("font_hover_color", Color.WHITE if high_contrast else COLOR_TEXT)
	button.add_theme_color_override("font_focus_color", Color.WHITE if high_contrast else COLOR_TEXT)


static func add_selection_focus(control: Control) -> void:
	_watch_selection_marker(control, 6.0)
	control.mouse_entered.connect(_focus_selection_entry.bind(control))


static func _focus_selection_entry(control: Control) -> void:
	var above := UIMotion.top_popup()
	var focused := control.get_viewport().gui_get_focus_owner()
	if (control is BaseButton and control.disabled) or focused is LineEdit or focused is TextEdit:
		return
	if above == null or above.is_ancestor_of(control):
		control.grab_focus()

const COLOR_BG := Tokens.BG
const COLOR_PANEL := Tokens.PANEL
const COLOR_PANEL_SOFT := Tokens.PANEL_SOFT
const COLOR_PANEL_DARK := Tokens.PANEL_DARK
const COLOR_GOLD := Tokens.BRASS
const COLOR_GOLD_SOFT := Tokens.PRIMARY_HOVER
const COLOR_BLUE := Tokens.TEAL
const COLOR_ACCENT := Tokens.TEAL
const COLOR_TEXT := Tokens.TEXT
const COLOR_TEXT_MUTED := Tokens.MUTED
const COLOR_BUTTON := Tokens.BUTTON
const COLOR_BUTTON_HOVER := Tokens.BUTTON_HOVER
const COLOR_BUTTON_PRESSED := Tokens.BUTTON_PRESSED
const COLOR_PRIMARY := Tokens.PRIMARY
const COLOR_PRIMARY_HOVER := Tokens.PRIMARY_HOVER
const COLOR_PRIMARY_PRESSED := Tokens.PRIMARY_PRESSED
const COLOR_SHADOW := Tokens.SHADOW
const COLOR_ARCANE := Tokens.TEAL
const COLOR_ARCANE_SOFT := Color(Tokens.INK,0.94)

static func card_type_accent(card_type: String) -> Color:
	match card_type:
		"spell": return Tokens.CARD_SPELL
		"parasite": return Tokens.CARD_PARASITE
	return Tokens.CARD_UNIT

static func strength_score_color(score: int) -> Color:
	var deviation := absi(score-100)
	if deviation<=15: return Tokens.SUCCESS
	if deviation<=40: return Tokens.WARNING
	return Color("df786b")
const COLOR_ENEMY := Tokens.ENEMY
const COLOR_PLAYER := Tokens.TEAL
const COLOR_SUCCESS := Tokens.SUCCESS
const COLOR_WARNING := Tokens.WARNING


static func apply_app_background(control: Control) -> void:
	if control == null:
		return
	if not (control is Panel or control is PanelContainer):
		if control.get_node_or_null("AppBackdrop") == null:
			var backdrop := Panel.new()
			backdrop.name = "AppBackdrop"
			backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
			backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.add_child(backdrop)
			control.move_child(backdrop, 0)
			apply_app_background(backdrop)
	control.add_theme_stylebox_override("panel", panel_style(COLOR_BG, Tokens.BORDER, 0, 0))


static func apply_panel(panel: Control, variant: String = "normal") -> void:
	if panel == null:
		return
	panel.set_meta("ui_panel_variant", variant)
	var fill := COLOR_PANEL
	var border := Tokens.BORDER
	var radius := 6
	var width := 0
	var shadow := Color.TRANSPARENT
	var shadow_size := 0
	match variant:
		"dark":
			fill = COLOR_PANEL_DARK
		"soft":
			fill = COLOR_PANEL_SOFT
		"gold":
			fill = COLOR_PANEL
			border = COLOR_GOLD
			width = 1
			radius = POPUP_RADIUS
		"tooltip":
			fill = Tokens.TOOLTIP_FILL
			border = Tokens.TOOLTIP_BORDER
			width = 1
			radius = POPUP_RADIUS
			shadow = Tokens.SHADOW
			shadow_size = 4
		"slot":
			fill = Tokens.PANEL
			border = Tokens.TEAL
			width = 1
			radius = 8
			shadow = Color(Tokens.INK,0.22)
			shadow_size = 4
		"battle":
			fill = Tokens.PANEL_DARK
			border = Tokens.INK
			radius = 0
			shadow = Color.TRANSPARENT
			shadow_size = 0
		"hand":
			fill = Tokens.PANEL_DARK
			border = Color(Tokens.TEAL,0.72)
			width = 1
			radius = 14
			shadow = Color(Color.BLACK,0.55)
			shadow_size = 7
		"enemy_slot":
			fill = Tokens.PANEL
			border = COLOR_ENEMY
			width = 1
			radius = 8
			shadow = Color(Tokens.DANGER_HOVER,0.22)
			shadow_size = 4
		"player_slot":
			fill = Color(Tokens.BG,0.94)
			border = COLOR_PLAYER
			width = 1
			radius = 8
			shadow = Color(Tokens.INK,0.26)
			shadow_size = 4
	var framed := panel.has_meta("ui_popup_frame") or variant == "tooltip"
	if framed:
		radius = POPUP_RADIUS
		width = 0
	panel.add_theme_stylebox_override("panel", panel_style(fill, border, width, radius, shadow, shadow_size))
	if framed:
		_add_bronze_surface(panel)


static func _add_bronze_surface(panel: Control) -> void:
	var painter := _draw_bronze_surface.bind(panel)
	if not panel.draw.is_connected(painter):
		panel.draw.connect(painter)
		panel.queue_redraw()


static func _draw_bronze_surface(panel: Control) -> void:
	var battle: bool = panel.get_meta("battle_frame", is_battle_context(panel))
	var filled: bool = panel.get_meta("ui_panel_variant", "") == "tooltip" or not panel.has_meta("ui_popup_frame")
	var key := Vector2i(int(battle), int(filled))
	if not _bronze_surfaces.has(key):
		var surface := StyleBoxTexture.new()
		surface.texture = preload("res://res/ui/bronze_battle_panel.png") if battle else preload("res://res/ui/bronze_panel.png")
		surface.draw_center = filled
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			surface.set_texture_margin(side, 7)
		_bronze_surfaces[key] = surface
	_bronze_surfaces[key].draw(panel.get_canvas_item(), Rect2(Vector2.ZERO, panel.size))


static func is_battle_context(node: Node) -> bool:
	while is_instance_valid(node):
		if node.is_in_group("battle_screen"):
			return true
		node = node.get_parent()
	return false


static func clear_popup_surfaces() -> void:
	_bronze_surfaces.clear()


static func apply_button(button: BaseButton, variant: String = "secondary", animated: bool = true, contrast_override: Variant = null) -> void:
	if button == null:
		return
	animated = animated and variant not in ["navigation", "utility"]
	var high_contrast := bool(AppPreferences.get_value("high_contrast") if contrast_override == null else contrast_override)
	button.add_theme_font_override("font", display_font() if variant == "navigation" else regular_font())
	button.set_meta("ui_button_variant", variant)
	button.set_meta("uimotion_enabled", animated)
	var base := COLOR_BUTTON
	var hover := COLOR_BUTTON_HOVER
	var pressed := COLOR_BUTTON_PRESSED
	var border := Tokens.BORDER
	var font_color := COLOR_TEXT
	if variant == "primary":
		base = COLOR_PRIMARY
		hover = COLOR_PRIMARY_HOVER
		pressed = COLOR_PRIMARY_PRESSED
		border = COLOR_GOLD
	elif variant == "danger":
		base = Tokens.DANGER
		hover = Tokens.DANGER_HOVER
		pressed = Tokens.DANGER_PRESSED
		border = Tokens.ENEMY
	elif variant == "utility":
		base = Color.TRANSPARENT
		hover = COLOR_BUTTON
		pressed = COLOR_BUTTON_PRESSED
		font_color = COLOR_TEXT_MUTED
	if variant == "navigation":
		base = Color.TRANSPARENT
		hover = Color.TRANSPARENT
		pressed = Color.TRANSPARENT
		font_color = COLOR_TEXT_MUTED
	var frame_width := 1 if variant in ["primary", "danger"] else 0
	var radius := 4
	button.add_theme_stylebox_override("normal", panel_style(base, border, frame_width, radius))
	button.add_theme_stylebox_override("hover", panel_style(hover, border.lightened(0.25), frame_width, radius))
	button.add_theme_stylebox_override("pressed", panel_style(pressed, border, frame_width, radius))
	button.add_theme_stylebox_override("hover_pressed", panel_style(pressed.lightened(0.04), border.lightened(0.25), frame_width, radius))
	var utility := variant == "utility"
	button.add_theme_stylebox_override("disabled", panel_style(Color.TRANSPARENT if utility else Tokens.DISABLED, Tokens.DISABLED, 0, radius))
	button.add_theme_stylebox_override("focus", panel_style(Color.TRANSPARENT, COLOR_GOLD, 0 if variant == "navigation" else 1, radius))
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_pressed_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Tokens.MUTED.darkened(0.25) if utility else Tokens.DISABLED_TEXT)
	if variant == "navigation" and button is Button:
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			button.get_theme_stylebox(state).set_content_margin(SIDE_LEFT, 22)
		var active_color := Color.WHITE if high_contrast else Tokens.HEADING_GOLD
		button.add_theme_color_override("font_pressed_color", active_color)
		button.add_theme_color_override("font_hover_pressed_color", active_color)
		_watch_selection_marker(button, 10.0, true)
	if high_contrast:
		button.add_theme_color_override("font_color",Color.WHITE)
		button.add_theme_color_override("font_disabled_color",Tokens.TEXT)
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.bg_color = Tokens.PANEL_SOFT if state in ["hover","pressed","hover_pressed"] else Tokens.PANEL_DARK
			style.border_color = Tokens.TEXT
			style.set_border_width_all(1)
			button.add_theme_stylebox_override(state,style)
	if animated:
		hook_button_feedback(button)
	elif button.get_meta("uimotion_hooked",false):
		_update_button_motion(button)


static func _watch_selection_marker(control: Control, x: float, navigation_only := false) -> void:
	var draw_marker := _draw_selection_marker.bind(control, x, navigation_only)
	if control.draw.is_connected(draw_marker):
		return
	control.draw.connect(draw_marker)
	control.mouse_entered.connect(control.queue_redraw)
	control.mouse_exited.connect(control.queue_redraw)
	control.focus_entered.connect(control.queue_redraw)
	control.focus_exited.connect(control.queue_redraw)
	if not UIMotion.navigation_input_changed.is_connected(control.queue_redraw):
		UIMotion.navigation_input_changed.connect(control.queue_redraw)


static func _draw_selection_marker(control: Control, x: float, navigation_only: bool) -> void:
	if navigation_only and control.get_meta("ui_button_variant", "") != "navigation":
		return
	if control is BaseButton and control.disabled:
		return
	if UIMotion.keyboard_navigation:
		if not control.has_focus(): return
	else:
		var hovered := control.get_viewport().gui_get_hovered_control()
		if hovered == null or (hovered != control and not control.is_ancestor_of(hovered)): return
	var center := Vector2(x, control.size.y * 0.5)
	var color := Color.WHITE if AppPreferences.get_value("high_contrast") else COLOR_GOLD
	control.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -4), center + Vector2(4, 0),
		center + Vector2(0, 4), center + Vector2(-4, 0),
	]), color)


# Independent pages share one navigation position in logical viewport coordinates.
static func place_page_back(page: Control, button: Button) -> void:
	if button.get_parent() != page:
		button.reparent(page, false)
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	# Reparenting out of an entering list must not retain its initial zero alpha.
	button.modulate.a = 1.0
	button.show()
	button.position = Vector2(24, 24)
	button.custom_minimum_size = Vector2(96, 40)
	button.size = button.custom_minimum_size
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.z_index = 30
	apply_button(button, "navigation")


static func apply_card_surface(panel: Panel, card_type: String, scale: float = 1.0) -> void:
	if panel == null:
		return
	var border := Tokens.BORDER
	var fill := Tokens.PAPER
	if card_type == "spell":
		border = COLOR_ARCANE
		fill = Tokens.PAPER
	elif card_type == "parasite":
		border = Tokens.PARASITE
		fill = Tokens.PAPER
	# CardUI owns a dedicated shadow node below this surface. Keeping the frame
	# shadow-free guarantees that no dark pixels can be painted over its border.
	var style := panel_style(fill, border, max(1, int(scale)), max(3, int(6 * scale)))
	panel.add_theme_stylebox_override("panel", style)


static func apply_slot(button: Button, variant: String = "player", occupied: bool = false) -> void:
	if button == null:
		return
	var fill := Color(Tokens.BG,0.94)
	var border := COLOR_PLAYER
	if variant == "enemy":
		fill = Tokens.PANEL
		border = COLOR_ENEMY
	if occupied:
		fill = Color(Tokens.PANEL_DARK,0.46)
		border = border.darkened(0.25)
	button.add_theme_stylebox_override("normal", panel_style(fill, border, 1 if occupied else 2, 8, Color(border.r, border.g, border.b, 0.18), 4 if not occupied else 2))
	button.add_theme_stylebox_override("hover", panel_style(fill.lightened(0.08), border.lightened(0.28), 2, 8, Color(border.r, border.g, border.b, 0.34), 7))
	button.add_theme_stylebox_override("pressed", panel_style(fill.darkened(0.12), border, 2, 8))
	button.add_theme_color_override("font_color", Color.TRANSPARENT)


static func apply_title(label: Label, size: int = 24) -> void:
	if label == null:
		return
	label.set_meta("keyword_literal",true)
	label.add_theme_font_override("font", display_font())
	label.add_theme_font_size_override("font_size", size+int(AppPreferences.get_value("text_size"))*2)
	label.add_theme_color_override("font_color", Tokens.PAPER)


static func apply_label(label: Label, muted: bool = false) -> void:
	if label == null:
		return
	if not label.has_meta("base_text_size"):
		label.set_meta("base_text_size",label.get_theme_font_size("font_size") if label.has_theme_font_size_override("font_size") else 16)
	if not label.has_theme_font_override("font"):
		label.add_theme_font_override("font", regular_font())
	label.add_theme_font_size_override("font_size",int(label.get_meta("base_text_size"))+int(AppPreferences.get_value("text_size"))*2)
	label.add_theme_color_override("font_color", COLOR_TEXT if AppPreferences.get_value("high_contrast") else (COLOR_TEXT_MUTED if muted else COLOR_TEXT))


static func apply_input(control: Control) -> void:
	if control == null:
		return
	var targets: Array[Control] = [control]
	if control is SpinBox:
		targets.append((control as SpinBox).get_line_edit())
	var high_contrast := bool(AppPreferences.get_value("high_contrast"))
	var normal_style := panel_style(Tokens.BG, Tokens.TEXT if high_contrast else Tokens.FIELD_BORDER, 1, POPUP_RADIUS)
	var focus_style := panel_style(Tokens.BG, Color.WHITE if high_contrast else COLOR_GOLD, 2, POPUP_RADIUS)
	for target in targets:
		target.add_theme_stylebox_override("normal", normal_style)
		target.add_theme_stylebox_override("focus", focus_style)
		target.add_theme_stylebox_override("read_only", normal_style)
		target.add_theme_color_override("font_color", COLOR_TEXT)
		target.add_theme_color_override("font_placeholder_color", COLOR_TEXT_MUTED)
		target.add_theme_color_override("caret_color", COLOR_TEXT)
		target.add_theme_color_override("selection_color", COLOR_PRIMARY_HOVER)
		target.add_theme_color_override("font_selected_color", Color.WHITE)


static func apply_item_list(list: ItemList) -> void:
	if list == null:
		return
	list.add_theme_stylebox_override("panel", panel_style(COLOR_PANEL_DARK, Tokens.INK, 1, 7))
	var selected := panel_style(COLOR_BUTTON_HOVER, COLOR_GOLD, 1, 4)
	list.add_theme_stylebox_override("selected", selected)
	list.add_theme_stylebox_override("selected_focus", selected)
	list.add_theme_stylebox_override("focus", panel_style(Color.TRANSPARENT, COLOR_GOLD, 1, 7))
	list.add_theme_color_override("font_color", COLOR_TEXT)
	list.add_theme_color_override("font_selected_color", Tokens.TEXT)
	list.add_theme_color_override("font_hovered_color", Tokens.TEXT)
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 6)


static func apply_scrollbar(bar: ScrollBar) -> void:
	if bar == null: return
	# Use Godot's built-in scrollbar styles, including their native minimum sizes.
	for name in ["scroll","scroll_focus","grabber","grabber_highlight","grabber_pressed"]:
		bar.remove_theme_stylebox_override(name)


static func pad_scroll_content(scroll: ScrollContainer, padding: int = 8) -> void:
	# Keep scaled hover/focus feedback inside the scroll area's clipping rect.
	var inset := StyleBoxEmpty.new()
	inset.set_content_margin_all(padding)
	scroll.add_theme_stylebox_override("panel", inset)


static func separator() -> HSeparator:
	var line := HSeparator.new()
	apply_separator(line)
	return line


static func apply_separator(line: HSeparator) -> void:
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_stylebox_override("separator", _separator_style())


static func _separator_style() -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = Tokens.DIVIDER
	style.thickness = 1
	return style


static func list_row_style() -> StyleBoxFlat:
	var style := panel_style(Color.TRANSPARENT, Tokens.DIVIDER, 0, 0)
	style.border_width_bottom = 1
	return style


static func apply_dialog(dialog: AcceptDialog, confirm_primary: bool = false) -> void:
	if dialog == null:
		return
	if dialog is FileDialog:
		var picker := dialog as FileDialog
		picker.use_native_dialog = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
		picker.mode_overrides_title = false
		_localize_file_dialog(dialog as FileDialog)
	# Also style the file picker's embedded fallback. It must not reintroduce
	# a second title frame, a draggable caption or an edge-hugging close X.
	dialog.borderless = true
	dialog.unresizable = true
	dialog.transparent_bg = true
	if not dialog.has_node("DialogCaption"):
		var caption := preload("res://DialogCaption.gd").new()
		caption.name = "DialogCaption"
		dialog.add_child(caption)
	var frame := panel_style(COLOR_PANEL_DARK, COLOR_GOLD, 0, POPUP_RADIUS)
	frame.bg_color.a = 1.0
	frame.expand_margin_top = 0
	dialog.add_theme_stylebox_override("embedded_border", frame)
	dialog.add_theme_stylebox_override("embedded_unfocused_border", frame)
	var body := panel_style(COLOR_PANEL_DARK, Tokens.BORDER, 0, POPUP_RADIUS)
	body.content_margin_left = DIALOG_INSET
	body.content_margin_right = DIALOG_INSET
	body.content_margin_top = 64
	body.content_margin_bottom = 20
	dialog.add_theme_color_override("title_color", Tokens.PAPER)
	dialog.add_theme_font_size_override("title_font_size", 18)
	# Captions are drawn inside the panel. A native title height leaves
	# an invisible title strip above an embedded borderless window.
	dialog.add_theme_constant_override("title_height", 0)
	dialog.add_theme_constant_override("title_outline_size", 1)
	dialog.add_theme_constant_override("buttons_separation", 16)
	dialog.add_theme_constant_override("buttons_min_width", 100)
	dialog.add_theme_constant_override("buttons_min_height", 38)
	var message := dialog.get_label()
	if message != null:
		apply_label(message)
		message.add_theme_font_size_override("font_size", 15)
		message.add_theme_constant_override("line_spacing", 5)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not dialog is FileDialog: dialog.get_ok_button().text = Locale.t("common.confirm")
	apply_button(dialog.get_ok_button(), "primary" if confirm_primary else "secondary")
	dialog.get_ok_button().custom_minimum_size = Vector2(104, 36)
	if dialog is ConfirmationDialog:
		var cancel := (dialog as ConfirmationDialog).get_cancel_button()
		if not dialog is FileDialog: cancel.text = Locale.t("common.back")
		apply_button(cancel, "secondary")
		cancel.custom_minimum_size = Vector2(104, 36)
	theme_tree(dialog, true)
	# AcceptDialog owns an internal background panel. Set its theme after the
	# content controls have been themed, then paint the recessed brass surface.
	dialog.add_theme_stylebox_override("panel", body)
	var content := dialog.get_children()
	for child in dialog.get_children(true):
		if child is Panel and child not in content:
			_add_bronze_surface(child)
			break


static func _localize_file_dialog(dialog: FileDialog) -> void:
	if Locale.language != "zh":
		return
	var default_titles := ["Open a File", "Open Files", "Open a Directory", "Open a File or Directory", "Save a File"]
	if dialog.title in default_titles or dialog.title.is_empty():
		match dialog.file_mode:
			FileDialog.FILE_MODE_SAVE_FILE:
				dialog.title = "保存文件"
			FileDialog.FILE_MODE_OPEN_FILES:
				dialog.title = "选择多个文件"
			FileDialog.FILE_MODE_OPEN_DIR:
				dialog.title = "选择文件夹"
			FileDialog.FILE_MODE_OPEN_ANY:
				dialog.title = "选择文件或文件夹"
			_:
				dialog.title = "选择文件"
	dialog.get_ok_button().text = "保存" if dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE else "选择"
	dialog.get_cancel_button().text = "取消"
	_translate_file_dialog_labels(dialog, {
		"Path:": "路径：",
		"Favorites:": "收藏：",
		"Directories & Files:": "文件夹与文件：",
		"Recent:": "最近：",
		"File:": "文件：",
	})


static func _translate_file_dialog_labels(root: Node, replacements: Dictionary) -> void:
	for child in root.get_children(true):
		if child is Label and replacements.has(child.text):
			child.text = replacements[child.text]
		_translate_file_dialog_labels(child, replacements)


static func apply_popup_menu(menu: PopupMenu) -> void:
	menu.add_theme_stylebox_override("panel", panel_style(COLOR_PANEL_DARK, Tokens.BORDER, 1, POPUP_RADIUS))
	menu.add_theme_stylebox_override("hover", panel_style(COLOR_BUTTON_HOVER, Tokens.BORDER, 0, POPUP_RADIUS))
	menu.add_theme_stylebox_override("separator", _separator_style())
	menu.add_theme_color_override("font_color", COLOR_TEXT)
	menu.add_theme_color_override("font_hover_color", Tokens.TEXT)
	menu.add_theme_color_override("font_disabled_color", COLOR_TEXT_MUTED.darkened(0.25))
	menu.add_theme_color_override("font_accelerator_color", COLOR_TEXT_MUTED)
	menu.add_theme_font_size_override("font_size", 14)
	menu.add_theme_constant_override("v_separation", 8)
	menu.add_theme_constant_override("h_separation", 12)


static func apply_overlay(rect: ColorRect) -> void:
	if rect == null:
		return
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.color = Color(Color.BLACK,0.62)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP


static func apply_popup_frame(panel: Control, variant: String = "gold", animate: bool = true) -> void:
	panel.set_meta("ui_popup_frame", true)
	apply_panel(panel, variant)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if animate:
		animate_popup_enter(panel, 1.0)


static func theme_tree(root: Node, include_internal: bool = false) -> void:
	if root == null:
		return
	for child in root.get_children(include_internal):
		if child is Label:
			apply_label(child)
		elif child is OptionButton:
			apply_button(child, str(child.get_meta("ui_button_variant", "secondary")))
			apply_popup_menu(child.get_popup())
		elif child is CheckButton:
			apply_button(child, str(child.get_meta("ui_button_variant", "secondary")), false)
		elif child is CheckBox:
			apply_button(child, str(child.get_meta("ui_button_variant", "secondary")))
		elif child is Button:
			var fallback := "danger" if child.text == "X" else "secondary"
			apply_button(child, str(child.get_meta("ui_button_variant", fallback)))
		elif child is LineEdit or child is SpinBox or child is TextEdit:
			apply_input(child)
		elif child is ItemList:
			apply_item_list(child)
		elif child is ScrollContainer:
			apply_scrollbar(child.get_h_scroll_bar())
			apply_scrollbar(child.get_v_scroll_bar())
		elif child is Panel or child is PanelContainer:
			apply_panel(child, str(child.get_meta("ui_panel_variant", "soft")))
		theme_tree(child, include_internal)


static func make_popup_layer(parent: Node, layer_index: int = 100) -> Dictionary:
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = layer_index
	parent.add_child(popup_layer)
	var bg := ColorRect.new()
	apply_overlay(bg)
	popup_layer.add_child(bg)
	return {"layer": popup_layer, "bg": bg}


static func panel_style(fill: Color, border: Color, width: int = 1, radius: int = 10, shadow: Color = Color.TRANSPARENT, shadow_size: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if shadow_size > 0:
		style.shadow_color = shadow
		style.shadow_size = shadow_size
	return style


# ============================================
# Unified interaction & entrance motion
# ============================================

const BTN_HOVER_SCALE := Vector2(1.035, 1.035)
const BTN_PRESS_SCALE := Vector2(0.98, 0.98)
const MOTION_HOVER_TIME := 0.12
const MOTION_PRESS_TIME := 0.06


# Compact hover/press motion without changing container layout or corner radii.
# Idempotent: repeated apply_button / re-theme calls never double-connect.
static func hook_button_feedback(button: BaseButton, _hover_scale: Vector2 = BTN_HOVER_SCALE) -> void:
	if button == null or button.get_meta("uimotion_hooked", false): return
	button.set_meta("uimotion_hooked", true)
	button.set_meta("uimotion_was_disabled",button.disabled)
	button.mouse_entered.connect(func(): _update_button_motion(button))
	button.mouse_entered.connect(func(): _reveal_button_feedback(button))
	button.mouse_exited.connect(func(): _update_button_motion(button))
	button.button_down.connect(func():
		button.set_meta("uimotion_down",true)
		_update_button_motion(button))
	button.button_up.connect(func():
		button.set_meta("uimotion_down",false)
		_update_button_motion(button))
	button.resized.connect(func():
		button.pivot_offset = button.size*0.5
		var pending_button: WeakRef = weakref(button)
		(func():
			var live_button := pending_button.get_ref() as BaseButton
			if live_button:
				_update_button_motion(live_button)
		).call_deferred())
	button.visibility_changed.connect(func():
		if not button.is_visible_in_tree():
			button.set_meta("uimotion_down",false)
			_update_button_motion(button))
	button.draw.connect(func():
		if button.disabled != bool(button.get_meta("uimotion_was_disabled",false)):
			button.set_meta("uimotion_was_disabled",button.disabled)
			button.set_meta("uimotion_down",false)
			_update_button_motion(button))
	_update_button_motion(button)

static func _reveal_button_feedback(button: BaseButton) -> void:
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			var scroll := ancestor as ScrollContainer
			var area := scroll.get_global_rect()
			var frame := scroll.get_theme_stylebox("panel")
			area.position.y += frame.get_content_margin(SIDE_TOP)
			area.size.y -= frame.get_content_margin(SIDE_TOP)+frame.get_content_margin(SIDE_BOTTOM)
			var rect := button.get_global_rect().grow_individual(3,2,3,2)
			if rect.size.y <= area.size.y:
				var shift := minf(0,rect.position.y-area.position.y)+maxf(0,rect.end.y-area.end.y)
				scroll.scroll_vertical += int(ceilf(absf(shift))*signf(shift))
			return
		ancestor = ancestor.get_parent()


static func _update_button_motion(button: BaseButton) -> void:
	if not is_instance_valid(button): return
	var target := Vector2.ONE
	var reduced := bool(AppPreferences.get_value("reduced_motion"))
	if button.get_meta("uimotion_enabled",true) and not reduced and not button.disabled and button.is_visible_in_tree():
		if button.get_meta("uimotion_down",false):
			target = BTN_PRESS_SCALE
		elif button.is_hovered():
			target = Vector2(1.0+minf(0.025,6.0/maxf(1,button.size.x)),1.0+minf(0.045,3.0/maxf(1,button.size.y)))
			var fit := _fit_button_hover(button,target)
			target = Vector2(fit.x,fit.y)
			button.pivot_offset = Vector2(fit.z,fit.w)
	var previous: Vector2 = button.get_meta("uimotion_target",Vector2(-1,-1))
	if previous.is_equal_approx(target) and button.scale.is_equal_approx(target): return
	var tween: Tween = button.get_meta("uimotion_tween") if button.has_meta("uimotion_tween") else null
	if previous.is_equal_approx(target) and tween != null and tween.is_running(): return
	if tween != null: tween.kill()
	button.set_meta("uimotion_target",target)
	if not button.is_hovered(): button.pivot_offset = button.size*0.5
	if reduced or button.disabled or not button.is_inside_tree() or not button.is_visible_in_tree():
		button.scale = target
		return
	tween = button.create_tween()
	button.set_meta("uimotion_tween",tween)
	tween.tween_property(button,"scale",target,MOTION_PRESS_TIME if button.get_meta("uimotion_down",false) else MOTION_HOVER_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _fit_button_hover(button: BaseButton, desired: Vector2) -> Vector4:
	var bounds := button.get_viewport().get_visible_rect()
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor.clip_contents or ancestor is ScrollContainer):
			var clip: Rect2 = ancestor.get_global_rect()
			if ancestor is ScrollContainer:
				var vertical: ScrollBar = ancestor.get_v_scroll_bar()
				var horizontal: ScrollBar = ancestor.get_h_scroll_bar()
				if vertical.visible: clip.end.x = minf(clip.end.x,vertical.get_global_rect().position.x)
				if horizontal.visible: clip.end.y = minf(clip.end.y,horizontal.get_global_rect().position.y)
			bounds = bounds.intersection(clip)
		ancestor = ancestor.get_parent()
	var parent_scale := button.get_global_transform().get_scale()/button.scale
	var rect := Rect2(button.global_position+(button.scale-Vector2.ONE)*button.pivot_offset*parent_scale,button.size*parent_scale)
	var pivot := button.size*0.5
	for axis in range(2):
		if rect.size[axis]<=0: continue
		desired[axis] = maxf(1.0,minf(desired[axis],bounds.size[axis]/rect.size[axis]))
		var growth := desired[axis]-1.0
		if growth<=0.00001: continue
		var low := maxf(0.0,(rect.position[axis]+rect.size[axis]*desired[axis]-bounds.end[axis])/growth)
		var high := minf(rect.size[axis],(rect.position[axis]-bounds.position[axis])/growth)
		if low<=high: pivot[axis] = clampf(rect.size[axis]*0.5,low,high)/parent_scale[axis]
		else: desired[axis]=1.0
	return Vector4(desired.x,desired.y,pivot.x,pivot.y)


# Spring pop-in + fade used by every themed popup (see apply_popup_frame).
# Runs deferred so anchors/containers settle before the pivot is computed.
static func animate_popup_enter(control: Control, from_scale: float = 0.92) -> void:
	if AppPreferences.get_value("reduced_motion"): return
	if control == null:
		return
	control.modulate = Color(Color.WHITE, 0.0)
	if control.is_inside_tree():
		_run_popup_enter.call_deferred(control, from_scale)
	else:
		control.tree_entered.connect(_run_popup_enter.bind(control, from_scale), CONNECT_ONE_SHOT)


static func _run_popup_enter(control: Control, from_scale: float) -> void:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return
	control.pivot_offset = control.size / 2
	control.scale = Vector2(from_scale, from_scale)
	var twn := control.create_tween()
	twn.set_parallel(true)
	twn.tween_property(control, "modulate:a", 1.0, Tokens.PANEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(control, "scale", Vector2.ONE, Tokens.PANEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Plain alpha fade-in, for full-screen panels where scaling would reveal edges.
static func fade_enter(control: CanvasItem, duration: float = 0.3, delay: float = 0.0) -> void:
	if control == null:
		return
	var previous: Tween = control.get_meta("ui_fade") if control.has_meta("ui_fade") else null
	if previous != null and previous.is_valid(): previous.kill()
	if AppPreferences.get_value("reduced_motion"):
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	var twn := control.create_tween()
	control.set_meta("ui_fade", twn)
	twn.tween_property(control, "modulate:a", 1.0, duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_callback(func(): control.remove_meta("ui_fade"))


# Let the container lay out its children first. The next sort can then take
# over from the animation when the list changes or the window is resized.
static func animate_list_enter(container: Container, rise: float, footer: Control = null) -> void:
	_finish_list_enter(container)
	if AppPreferences.get_value("reduced_motion") or not container.is_visible_in_tree():
		return
	var entries := container.get_children()
	if footer != null:
		entries.append(footer)
	var opacity: Dictionary[Control, float] = {}
	for child in entries:
		var item := child as Control
		if item == null or not (item is BaseButton or item is Container) or not item.is_visible_in_tree() or item.is_queued_for_deletion():
			continue
		opacity[item] = item.modulate.a
		item.modulate.a = 0.0
	if opacity.is_empty():
		return
	var tween := container.create_tween().set_parallel(true)
	tween.pause()
	var positions: Dictionary[Control, Vector2] = {}
	container.set_meta("list_entrance", {"tween": tween, "opacity": opacity, "positions": positions})
	var tree := container.get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(container) or not container.is_inside_tree() or not tween.is_valid():
		return
	if not container.is_visible_in_tree():
		_finish_list_enter(container)
		return
	var step := minf(0.032, 0.30 / maxf(1, opacity.size() - 1))
	for item: Control in opacity:
		if not is_instance_valid(item) or item.is_queued_for_deletion():
			continue
		var parent := item.get_parent() as CanvasItem
		var shift := parent.get_global_transform_with_canvas().affine_inverse().basis_xform(Vector2.DOWN * rise)
		var delay := positions.size() * step
		positions[item] = item.position
		item.position += shift
		tween.tween_property(item, "position", positions[item], Tokens.BUTTON_TIME).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(item, "modulate:a", opacity[item], Tokens.BUTTON_TIME * 0.75).set_delay(delay)
	if positions.is_empty():
		_finish_list_enter(container)
		return
	var finish := _finish_list_enter.bind(container)
	container.pre_sort_children.connect(finish, CONNECT_ONE_SHOT)
	tween.finished.connect(finish)
	tween.play()


static func _finish_list_enter(container: Container) -> void:
	if not container.has_meta("list_entrance"):
		return
	var state: Dictionary = container.get_meta("list_entrance")
	container.remove_meta("list_entrance")
	var finish := _finish_list_enter.bind(container)
	if container.pre_sort_children.is_connected(finish):
		container.pre_sort_children.disconnect(finish)
	var tween: Tween = state.tween
	if tween.is_valid():
		tween.kill()
	for item: Control in state.opacity:
		if not is_instance_valid(item):
			continue
		item.modulate.a = state.opacity[item]
		if state.positions.has(item):
			item.position = state.positions[item]


# Gentle breathing shimmer for menu titles. Runs forever; guard keeps it single.
static func title_breathe(label: Label, min_alpha: float = 0.82, max_alpha: float = 1.0, period: float = 1.5) -> void:
	if AppPreferences.get_value("reduced_motion"): return
	if label == null or label.get_meta("title_breathe_active", false):
		return
	label.set_meta("title_breathe_active", true)
	label.modulate.a = min_alpha
	label.create_tween().tween_property(label,"modulate:a",max_alpha,0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)



# Looping attention pulse (scale) for a control. Returns the loop tween so the
# caller can kill it when the state it represents ends.
static func pulse_loop(control: Control, min_scale: float = 1.0, max_scale: float = 1.04, period: float = 1.2) -> Tween:
	if AppPreferences.get_value("reduced_motion"): return null
	if control == null:
		return null
	control.pivot_offset = control.size / 2
	var twn := control.create_tween().set_loops()
	twn.tween_property(control, "scale", Vector2(max_scale, max_scale), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(control, "scale", Vector2(min_scale, min_scale), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return twn


# Gentle "wrong input" shake for controls (insufficient mana toasts, blocked
# actions, ...) — translates and returns, so it is safe inside containers.
static func reject_button(button: BaseButton) -> void:
	var feedback := button.get_node_or_null("/root/UIMotion/UnavailableFeedback")
	if feedback != null: feedback.reject(button)

static func reject_shake(control: Control, strength: float = 6.0) -> void:
	if control == null:
		return
	var twn := control.create_tween()
	twn.tween_property(control, "position:x", control.position.x + strength, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(control, "position:x", control.position.x - strength, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(control, "position:x", control.position.x + strength * 0.5, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(control, "position:x", control.position.x, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func apply_card_action(button: Button) -> void:
	button.add_theme_font_override("font",medium_font())
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for state in ["normal","hover","pressed","disabled"]:
		var fill := Tokens.PAPER.darkened(0.035)
		if state == "hover": fill = Tokens.PAPER.lightened(0.06)
		if state == "pressed": fill = Tokens.PAPER.darkened(0.12)
		var style := panel_style(fill,Tokens.BRASS,1,4,Color.TRANSPARENT,0)
		style.content_margin_left = 2
		style.content_margin_right = 2
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		button.add_theme_stylebox_override(state,style)
	button.add_theme_stylebox_override("focus",panel_style(Color.TRANSPARENT,Tokens.INK,2,4,Color.TRANSPARENT,0))
	for state in ["font_color","font_hover_color","font_pressed_color","font_disabled_color"]:
		button.add_theme_color_override(state,Tokens.INK)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
