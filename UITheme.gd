extends RefCounted
class_name UITheme

const COLOR_BG := Color(0.055, 0.065, 0.085)
const COLOR_PANEL := Color(0.105, 0.12, 0.155, 0.96)
const COLOR_PANEL_SOFT := Color(0.13, 0.145, 0.18, 0.9)
const COLOR_PANEL_DARK := Color(0.075, 0.085, 0.11, 0.96)
const COLOR_GOLD := Color(0.90, 0.74, 0.40)
const COLOR_GOLD_SOFT := Color(0.62, 0.50, 0.28)
const COLOR_BLUE := Color(0.30, 0.43, 0.62)
const COLOR_ACCENT := Color(0.36, 0.52, 0.72)
const COLOR_TEXT := Color(0.95, 0.94, 0.89)
const COLOR_TEXT_MUTED := Color(0.68, 0.72, 0.78)
const COLOR_BUTTON := Color(0.17, 0.22, 0.31)
const COLOR_BUTTON_HOVER := Color(0.23, 0.30, 0.42)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.16, 0.24)
const COLOR_PRIMARY := Color(0.40, 0.31, 0.14)
const COLOR_PRIMARY_HOVER := Color(0.55, 0.42, 0.18)
const COLOR_PRIMARY_PRESSED := Color(0.25, 0.19, 0.09)
const COLOR_SHADOW := Color(0.0, 0.0, 0.0, 0.35)
const COLOR_ARCANE := Color(0.20, 0.72, 0.84)
const COLOR_ARCANE_SOFT := Color(0.12, 0.24, 0.32, 0.94)
const COLOR_ENEMY := Color(0.48, 0.20, 0.36)
const COLOR_PLAYER := Color(0.16, 0.46, 0.64)
const COLOR_SUCCESS := Color(0.42, 0.76, 0.58)
const COLOR_WARNING := Color(0.95, 0.58, 0.25)


static func apply_app_background(control: Control) -> void:
	if control == null:
		return
	control.add_theme_stylebox_override("panel", panel_style(COLOR_BG, Color(0.10, 0.12, 0.16), 0, 0))


static func apply_panel(panel: Control, variant: String = "normal") -> void:
	if panel == null:
		return
	var fill := COLOR_PANEL
	var border := COLOR_GOLD_SOFT
	var radius := 12
	var width := 1
	var shadow := COLOR_SHADOW
	var shadow_size := 4
	match variant:
		"dark":
			fill = COLOR_PANEL_DARK
			border = Color(0.20, 0.24, 0.32)
			shadow = Color(0.0, 0.0, 0.0, 0.25)
			shadow_size = 3
		"soft":
			fill = COLOR_PANEL_SOFT
			border = Color(0.26, 0.31, 0.40)
			shadow = Color(0.0, 0.0, 0.0, 0.30)
			shadow_size = 4
		"gold":
			fill = COLOR_PANEL
			border = COLOR_GOLD
			width = 2
			shadow = Color(0.0, 0.0, 0.0, 0.45)
			shadow_size = 6
		"slot":
			fill = Color(0.055, 0.09, 0.13, 0.94)
			border = Color(0.22, 0.42, 0.56)
			radius = 8
			shadow = Color(0.02, 0.28, 0.40, 0.22)
			shadow_size = 4
		"battle":
			fill = Color(0.035, 0.055, 0.085, 0.98)
			border = Color(0.16, 0.28, 0.38)
			radius = 0
			shadow = Color(0.0, 0.0, 0.0, 0.0)
			shadow_size = 0
		"hand":
			fill = Color(0.025, 0.052, 0.076, 0.96)
			border = Color(0.20, 0.58, 0.70, 0.72)
			radius = 14
			shadow = Color(0.0, 0.0, 0.0, 0.55)
			shadow_size = 7
		"enemy_slot":
			fill = Color(0.13, 0.055, 0.10, 0.92)
			border = COLOR_ENEMY
			radius = 8
			shadow = Color(0.35, 0.04, 0.18, 0.22)
			shadow_size = 4
		"player_slot":
			fill = Color(0.035, 0.11, 0.16, 0.94)
			border = COLOR_PLAYER
			radius = 8
			shadow = Color(0.02, 0.28, 0.40, 0.26)
			shadow_size = 4
	panel.add_theme_stylebox_override("panel", panel_style(fill, border, width, radius, shadow, shadow_size))


static func apply_button(button: BaseButton, variant: String = "secondary", animated: bool = true) -> void:
	if button == null:
		return
	var base := COLOR_BUTTON
	var hover := COLOR_BUTTON_HOVER
	var pressed := COLOR_BUTTON_PRESSED
	var border := COLOR_BLUE
	var shadow := COLOR_SHADOW
	var shadow_size := 2
	var hover_shadow_size := 4
	if variant == "primary":
		base = COLOR_PRIMARY
		hover = COLOR_PRIMARY_HOVER
		pressed = COLOR_PRIMARY_PRESSED
		border = COLOR_GOLD
		shadow = Color(0.0, 0.0, 0.0, 0.40)
		shadow_size = 3
		hover_shadow_size = 6
	elif variant == "danger":
		base = Color(0.30, 0.11, 0.11)
		hover = Color(0.42, 0.15, 0.15)
		pressed = Color(0.20, 0.07, 0.07)
		border = Color(0.78, 0.34, 0.30)
	button.add_theme_stylebox_override("normal", panel_style(base, border, 1, 8, shadow, shadow_size))
	button.add_theme_stylebox_override("hover", panel_style(hover, border.lightened(0.25), 1, 8, shadow, hover_shadow_size))
	button.add_theme_stylebox_override("pressed", panel_style(pressed, border.darkened(0.15), 1, 8, Color(0,0,0,0), 0))
	button.add_theme_stylebox_override("disabled", panel_style(Color(0.10, 0.11, 0.13), Color(0.20, 0.21, 0.24), 1, 8, Color(0,0,0,0), 0))
	button.add_theme_stylebox_override("focus", panel_style(base, border.lightened(0.35), 2, 8, Color(border.r, border.g, border.b, 0.5), 5))
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.72))
	button.add_theme_color_override("font_pressed_color", Color(0.94, 0.82, 0.50))
	button.add_theme_color_override("font_disabled_color", Color(0.44, 0.46, 0.50))
	if animated:
		hook_button_feedback(button)


static func apply_card_surface(panel: Panel, card_type: String, scale: float = 1.0) -> void:
	if panel == null:
		return
	var border := COLOR_GOLD_SOFT
	var fill := Color(0.02, 0.03, 0.05, 1.0)
	if card_type == "spell":
		border = COLOR_ARCANE
		fill = Color(0.045, 0.12, 0.17, 0.98)
	elif card_type == "parasite":
		border = Color(0.56, 0.30, 0.66)
		fill = Color(0.11, 0.055, 0.14, 0.98)
	# CardUI owns a dedicated shadow node below this surface. Keeping the frame
	# shadow-free guarantees that no dark pixels can be painted over its border.
	var style := panel_style(fill, border, max(1, int(scale)), max(3, int(6 * scale)))
	panel.add_theme_stylebox_override("panel", style)


static func apply_slot(button: Button, variant: String = "player", occupied: bool = false) -> void:
	if button == null:
		return
	var fill := Color(0.035, 0.11, 0.16, 0.94)
	var border := COLOR_PLAYER
	if variant == "enemy":
		fill = Color(0.13, 0.055, 0.10, 0.92)
		border = COLOR_ENEMY
	if occupied:
		fill = Color(0.035, 0.045, 0.065, 0.46)
		border = border.darkened(0.25)
	button.add_theme_stylebox_override("normal", panel_style(fill, border, 1 if occupied else 2, 8, Color(border.r, border.g, border.b, 0.18), 4 if not occupied else 2))
	button.add_theme_stylebox_override("hover", panel_style(fill.lightened(0.08), border.lightened(0.28), 2, 8, Color(border.r, border.g, border.b, 0.34), 7))
	button.add_theme_stylebox_override("pressed", panel_style(fill.darkened(0.12), border, 2, 8))
	button.add_theme_color_override("font_color", Color(0, 0, 0, 0))


static func apply_title(label: Label, size: int = 24) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.62))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	label.add_theme_constant_override("outline_size", 1)


static func apply_label(label: Label, muted: bool = false) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED if muted else COLOR_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


static func apply_input(control: Control) -> void:
	if control == null:
		return
	var normal_style := panel_style(Color(0.075, 0.085, 0.11), Color(0.30, 0.35, 0.45), 1, 6)
	var focus_style := panel_style(Color(0.075, 0.085, 0.11), COLOR_ACCENT, 1, 6, Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.35), 3)
	control.add_theme_stylebox_override("normal", normal_style)
	control.add_theme_stylebox_override("focus", focus_style)
	control.add_theme_stylebox_override("read_only", normal_style)
	control.add_theme_color_override("font_color", COLOR_TEXT)
	control.add_theme_color_override("font_placeholder_color", COLOR_TEXT_MUTED)


static func apply_overlay(rect: ColorRect) -> void:
	if rect == null:
		return
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.color = Color(0.0, 0.0, 0.0, 0.62)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP


static func apply_popup_frame(panel: Control, variant: String = "gold") -> void:
	apply_panel(panel, variant)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	animate_popup_enter(panel)


static func theme_tree(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Label:
			apply_label(child)
		elif child is Button:
			var variant := "danger" if child.text == "X" else "secondary"
			apply_button(child, variant)
		elif child is OptionButton or child is CheckBox:
			apply_button(child, "secondary")
		elif child is LineEdit or child is SpinBox or child is TextEdit:
			apply_input(child)
		elif child is Panel or child is PanelContainer:
			apply_panel(child, "soft")
		theme_tree(child)


static func make_popup_layer(parent: Node, layer_index: int = 100) -> Dictionary:
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = layer_index
	parent.add_child(popup_layer)
	var bg := ColorRect.new()
	apply_overlay(bg)
	popup_layer.add_child(bg)
	return {"layer": popup_layer, "bg": bg}


static func panel_style(fill: Color, border: Color, width: int = 1, radius: int = 10, shadow: Color = Color(0, 0, 0, 0), shadow_size: int = 0) -> StyleBoxFlat:
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
const BTN_PRESS_SCALE := Vector2(0.95, 0.95)
const MOTION_HOVER_TIME := 0.12
const MOTION_PRESS_TIME := 0.06


# Scales a button up on hover and squashes it on press with a springy release.
# Idempotent: repeated apply_button / re-theme calls never double-connect.
static func hook_button_feedback(button: BaseButton, hover_scale: Vector2 = BTN_HOVER_SCALE) -> void:
	if button == null or button.get_meta("uimotion_hooked", false):
		return
	button.set_meta("uimotion_hooked", true)
	var state := {"tween": null}

	button.mouse_entered.connect(func():
		if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
			return
		button.pivot_offset = button.size / 2
		var old: Tween = state["tween"] as Tween
		if old != null and old.is_valid():
			old.kill()
		var twn := button.create_tween()
		state["tween"] = twn
		twn.tween_property(button, "scale", hover_scale, MOTION_HOVER_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	button.mouse_exited.connect(func():
		if not is_instance_valid(button):
			return
		button.pivot_offset = button.size / 2
		var old: Tween = state["tween"] as Tween
		if old != null and old.is_valid():
			old.kill()
		var twn := button.create_tween()
		state["tween"] = twn
		twn.tween_property(button, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	button.button_down.connect(func():
		if not is_instance_valid(button) or button.disabled:
			return
		button.pivot_offset = button.size / 2
		var old: Tween = state["tween"] as Tween
		if old != null and old.is_valid():
			old.kill()
		var twn := button.create_tween()
		state["tween"] = twn
		twn.tween_property(button, "scale", BTN_PRESS_SCALE, MOTION_PRESS_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	button.button_up.connect(func():
		if not is_instance_valid(button):
			return
		button.pivot_offset = button.size / 2
		var old: Tween = state["tween"] as Tween
		if old != null and old.is_valid():
			old.kill()
		var twn := button.create_tween()
		state["tween"] = twn
		twn.tween_property(button, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)


# Spring pop-in + fade used by every themed popup (see apply_popup_frame).
# Runs deferred so anchors/containers settle before the pivot is computed.
static func animate_popup_enter(control: Control, from_scale: float = 0.92) -> void:
	if control == null:
		return
	control.modulate = Color(1, 1, 1, 0.0)
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
	twn.tween_property(control, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(control, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Plain alpha fade-in, for full-screen panels where scaling would reveal edges.
static func fade_enter(control: CanvasItem, duration: float = 0.3, delay: float = 0.0) -> void:
	if control == null:
		return
	control.modulate.a = 0.0
	var twn := control.create_tween()
	twn.tween_property(control, "modulate:a", 1.0, duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Staggered rise + fade for children of a freshly built list. Pass rise <= 0 to
# animate alpha only (safe inside GridContainer-like layouts that re-sort).
# Labels are skipped by default so they never fight a title_breathe loop.
#
# Containers sort their children lazily (queue_sort at frame end), so the rise
# animation must run after the first real layout — otherwise the tween captures
# position (0,0) and yanks every control into the top-left corner, overlapping
# the whole menu. We hide immediately and defer the actual animation one frame.
static func animate_list_enter(container: Node, stagger: float = 0.035, rise: float = 14.0, skip_labels: bool = true) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child is Control and not (skip_labels and child is Label):
			(child as Control).modulate.a = 0.0
	if container.is_inside_tree():
		_run_list_enter.call_deferred(container, stagger, rise, skip_labels)
	else:
		container.tree_entered.connect(_run_list_enter.bind(container, stagger, rise, skip_labels), CONNECT_ONE_SHOT)


static func _run_list_enter(container: Node, stagger: float, rise: float, skip_labels: bool) -> void:
	if container == null or not is_instance_valid(container) or not container.is_inside_tree():
		return
	await container.get_tree().process_frame
	if container == null or not is_instance_valid(container) or not container.is_inside_tree():
		return
	var index := 0
	for child in container.get_children():
		if child is Control:
			if skip_labels and child is Label:
				continue
			var c: Control = child
			if rise > 0.0:
				c.position.y += rise
			var twn := c.create_tween()
			twn.set_parallel(true)
			twn.tween_property(c, "modulate:a", 1.0, 0.20).set_delay(index * stagger).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if rise > 0.0:
				twn.tween_property(c, "position:y", c.position.y - rise, 0.24).set_delay(index * stagger).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			index += 1


# Gentle breathing shimmer for menu titles. Runs forever; guard keeps it single.
static func title_breathe(label: Label, min_alpha: float = 0.82, max_alpha: float = 1.0, period: float = 1.5) -> void:
	if label == null or label.get_meta("title_breathe_active", false):
		return
	label.set_meta("title_breathe_active", true)
	var twn := label.create_tween().set_loops()
	twn.tween_property(label, "modulate:a", min_alpha, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(label, "modulate:a", max_alpha, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# Looping attention pulse (scale) for a control. Returns the loop tween so the
# caller can kill it when the state it represents ends.
static func pulse_loop(control: Control, min_scale: float = 1.0, max_scale: float = 1.04, period: float = 1.2) -> Tween:
	if control == null:
		return null
	control.pivot_offset = control.size / 2
	var twn := control.create_tween().set_loops()
	twn.tween_property(control, "scale", Vector2(max_scale, max_scale), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(control, "scale", Vector2(min_scale, min_scale), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return twn


# Gentle "wrong input" shake for controls (insufficient mana toasts, blocked
# actions, ...) — translates and returns, so it is safe inside containers.
static func reject_shake(control: Control, strength: float = 6.0) -> void:
	if control == null:
		return
	var twn := control.create_tween()
	twn.tween_property(control, "position:x", control.position.x + strength, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(control, "position:x", control.position.x - strength, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(control, "position:x", control.position.x + strength * 0.5, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(control, "position:x", control.position.x, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
