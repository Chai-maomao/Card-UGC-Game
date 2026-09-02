class_name SkillEditorTutorialController
extends Node

const ProgressStore = preload("res://TutorialProgress.gd")

enum Phase {
	INTRO,
	NAME,
	TRIGGER,
	EFFECT,
	REVIEW,
	SAVE,
}

var editor: Control
var phase: int = Phase.INTRO
var overlay_layer: CanvasLayer
var overlay_root: Control
var instruction_panel: PanelContainer
var step_label: Label
var title_label: Label
var body_label: Label
var next_button: Button
var skip_button: Button
var exit_button: Button
var focus_frames: Array[Panel] = []
var _focused_controls: Array[Control] = []
var _panel_tween: Tween
var progress_path: String = ProgressStore.DEFAULT_PATH
var navigate_on_complete: bool = true


func start(owner_editor: Control) -> void:
	editor = owner_editor
	_build_ui()
	set_phase(Phase.INTRO)


func allows(action: String, context: Dictionary = {}) -> bool:
	var allowed := false
	match phase:
		Phase.NAME:
			allowed = action == "name"
		Phase.TRIGGER:
			allowed = action == "trigger" and str(context.get("id", "")) == SkillEngine.TRIGGER_ON_SUMMON
		Phase.EFFECT:
			allowed = action == "effect" and str(context.get("id", "")) == SkillEngine.EFFECT_DRAW_CARDS
		Phase.SAVE:
			allowed = action == "save"
		_:
			allowed = false
	if not allowed:
		_remind()
	return allowed


func on_name_changed(value: String) -> void:
	if phase != Phase.NAME:
		return
	var ready := not value.strip_edges().is_empty()
	next_button.disabled = not ready
	next_button.text = Locale.t("tutorial.next") if ready else Locale.t("tutorial.complete_action")


func notify_action(action: String, _context: Dictionary = {}) -> void:
	match phase:
		Phase.TRIGGER when action == "trigger":
			set_phase(Phase.EFFECT)
		Phase.EFFECT when action == "effect":
			set_phase(Phase.REVIEW)


func handle_save(skill: Dictionary) -> bool:
	if not allows("save"):
		return true
	var effects: Array = skill.get("effects", [])
	var valid := not str(skill.get("skill_name", "")).strip_edges().is_empty() \
			and str(skill.get("trigger", "")) == SkillEngine.TRIGGER_ON_SUMMON \
			and effects.size() == 1 \
			and str((effects[0] as Dictionary).get("effect", "")) == SkillEngine.EFFECT_DRAW_CARDS
	if not valid:
		_remind()
		return true
	PlayerData.finish_skill_tutorial_editor(skill)
	if navigate_on_complete:
		UIMotion.go_back("res://CardEditor.tscn")
	return true


func set_phase(next_phase: int) -> void:
	phase = next_phase
	_clear_focus()
	match phase:
		Phase.INTRO:
			_set_copy("tutorial.editor_intro_title", "tutorial.editor_intro_body", true)
			_focus_controls([editor.palette_vbox.get_parent().get_parent().get_parent(), editor.effects_list])
		Phase.NAME:
			_set_copy("tutorial.editor_name_title", "tutorial.editor_name_body", false)
			_focus_controls([editor.skill_name_input])
			editor.skill_name_input.grab_focus()
			on_name_changed(editor.skill_name_input.text)
		Phase.TRIGGER:
			_set_copy("tutorial.editor_trigger_title", "tutorial.editor_trigger_body", false)
			_focus_controls([_trigger_button()])
		Phase.EFFECT:
			_set_copy("tutorial.editor_effect_title", "tutorial.editor_effect_body", false)
			_focus_controls([_effect_button()])
		Phase.REVIEW:
			_set_copy("tutorial.editor_review_title", "tutorial.editor_review_body", true)
			_focus_controls([editor.preview_panel])
		Phase.SAVE:
			_set_copy("tutorial.editor_save_title", "tutorial.editor_save_body", false)
			_focus_controls([editor.save_button])
	step_label.text = Locale.t("tutorial.editor_step", [phase + 1, 6])
	_configure_editor_controls()
	_refresh_focus_deferred.call_deferred()


func _set_copy(title_key: String, body_key: String, allow_next: bool) -> void:
	title_label.text = Locale.t(title_key)
	body_label.text = Locale.t(body_key)
	next_button.visible = true
	next_button.disabled = not allow_next
	next_button.text = Locale.t("tutorial.next") if allow_next else Locale.t("tutorial.complete_action")
	skip_button.visible = true
	skip_button.disabled = false
	skip_button.modulate.a = 1.0


func _build_ui() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 90
	editor.add_child(overlay_layer)
	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(overlay_root)
	instruction_panel = PanelContainer.new()
	instruction_panel.custom_minimum_size = Vector2(350, 238)
	instruction_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	instruction_panel.z_index = 10
	UITheme.apply_panel(instruction_panel, "gold")
	overlay_root.add_child(instruction_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	instruction_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	step_label = Label.new()
	step_label.add_theme_font_size_override("font_size", 12)
	UITheme.apply_label(step_label, true)
	box.add_child(step_label)
	title_label = Label.new()
	UITheme.apply_title(title_label, 20)
	box.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(318, 82)
	body_label.add_theme_font_size_override("font_size", 14)
	UITheme.apply_label(body_label)
	box.add_child(body_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	next_button = Button.new()
	next_button.custom_minimum_size = Vector2(112, 38)
	next_button.clip_text = true
	UITheme.apply_button(next_button, "primary")
	next_button.pressed.connect(_on_next)
	buttons.add_child(next_button)
	skip_button = Button.new()
	skip_button.text = Locale.t("tutorial.skip")
	skip_button.custom_minimum_size = Vector2(112, 38)
	skip_button.clip_text = true
	UITheme.apply_button(skip_button, "secondary")
	skip_button.pressed.connect(_on_skip)
	buttons.add_child(skip_button)
	exit_button = Button.new()
	exit_button.text = Locale.t("tutorial.exit")
	exit_button.custom_minimum_size = Vector2(72, 38)
	exit_button.clip_text = true
	UITheme.apply_button(exit_button, "secondary")
	exit_button.pressed.connect(_on_exit)
	buttons.add_child(exit_button)
	_position_panel()
	UITheme.animate_popup_enter(instruction_panel)


func _position_panel() -> void:
	var viewport_size := editor.get_viewport_rect().size
	instruction_panel.position = Vector2(maxf(18.0, viewport_size.x - 370.0), 18.0)


func _on_next() -> void:
	if phase == Phase.INTRO:
		set_phase(Phase.NAME)
	elif phase == Phase.NAME and not editor.skill_name_input.text.strip_edges().is_empty():
		set_phase(Phase.TRIGGER)
	elif phase == Phase.REVIEW:
		set_phase(Phase.SAVE)


func _on_skip() -> void:
	ProgressStore.new(progress_path).mark_skipped()
	PlayerData.cancel_skill_tutorial()
	if navigate_on_complete:
		UIMotion.go_back_levels(2, "res://MainMenu.tscn")


func _on_exit() -> void:
	PlayerData.cancel_skill_tutorial()
	if navigate_on_complete:
		UIMotion.go_back_levels(2, "res://MainMenu.tscn")


func _configure_editor_controls() -> void:
	editor.skill_name_input.editable = phase == Phase.NAME
	editor.save_button.disabled = phase != Phase.SAVE
	editor.cancel_button.disabled = true
	if editor._undo_btn:
		editor._undo_btn.disabled = true
	if editor._redo_btn:
		editor._redo_btn.disabled = true
	if editor._template_btn:
		editor._template_btn.disabled = true
	for button in editor.palette_vbox.find_children("*", "Button", true, false):
		var palette_button := button as Button
		palette_button.disabled = true
		_keep_disabled_button_colored(palette_button)
	var expected: Button = _trigger_button() if phase == Phase.TRIGGER else (_effect_button() if phase == Phase.EFFECT else null)
	if expected:
		expected.disabled = false
	_set_control_tree_enabled(editor.settings_row, false)
	_set_control_tree_enabled(editor.effects_list, false)


func _keep_disabled_button_colored(button: Button) -> void:
	# Tutorial gating remains functional through Button.disabled, but disabled
	# palette blocks retain their category colour and readable text.
	var normal_style := button.get_theme_stylebox("normal")
	if normal_style != null:
		button.add_theme_stylebox_override("disabled", normal_style.duplicate())
	button.add_theme_color_override("font_disabled_color", button.get_theme_color("font_color"))
	button.add_theme_color_override("icon_disabled_color", Color.WHITE)


func _set_control_tree_enabled(root: Node, enabled: bool) -> void:
	for node in root.find_children("*", "Control", true, false):
		if node is BaseButton:
			(node as BaseButton).disabled = not enabled
		elif node is LineEdit:
			(node as LineEdit).editable = enabled
		elif node is SpinBox:
			(node as SpinBox).editable = enabled


func _trigger_button() -> Button:
	var needle := Locale.term("trigger", SkillEngine.TRIGGER_ON_SUMMON)
	for node in editor.palette_vbox.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.contains(needle):
			return button
	return null


func _effect_button() -> Button:
	for node in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		var button := node as SkillPaletteBlock
		if button != null and button.effect_id == SkillEngine.EFFECT_DRAW_CARDS:
			return button
	return null


func _focus_controls(controls: Array) -> void:
	_focused_controls.clear()
	for control in controls:
		if control is Control and is_instance_valid(control):
			_focused_controls.append(control)
			var frame := Panel.new()
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = UITheme.COLOR_GOLD
			style.set_border_width_all(4)
			style.set_corner_radius_all(10)
			style.shadow_color = Color(UITheme.COLOR_GOLD.r, UITheme.COLOR_GOLD.g, UITheme.COLOR_GOLD.b, 0.38)
			style.shadow_size = 8
			frame.add_theme_stylebox_override("panel", style)
			overlay_root.add_child(frame)
			focus_frames.append(frame)
	_refresh_focus()
	for frame in focus_frames:
		var pulse := frame.create_tween().set_loops()
		pulse.tween_property(frame, "modulate:a", 0.48, 0.55).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(frame, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)


func _process(_delta: float) -> void:
	if not focus_frames.is_empty():
		_refresh_focus()


func _refresh_focus() -> void:
	for i in range(mini(_focused_controls.size(), focus_frames.size())):
		var control := _focused_controls[i]
		if control == null or not is_instance_valid(control):
			focus_frames[i].visible = false
			continue
		var frame_rect := control.get_global_rect().grow(6.0)
		var palette_scroll := _palette_scroll()
		if palette_scroll != null and palette_scroll.is_ancestor_of(control):
			var clip_rect := palette_scroll.get_global_rect()
			if not frame_rect.intersects(clip_rect):
				focus_frames[i].visible = false
				continue
			frame_rect = frame_rect.intersection(clip_rect)
		focus_frames[i].visible = frame_rect.size.x > 1.0 and frame_rect.size.y > 1.0
		focus_frames[i].position = frame_rect.position
		focus_frames[i].size = frame_rect.size


func _palette_scroll() -> ScrollContainer:
	return editor.get_node_or_null("Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteScroll") as ScrollContainer


func _refresh_focus_deferred() -> void:
	await get_tree().process_frame
	var palette_target: Control = null
	if phase == Phase.TRIGGER:
		palette_target = _trigger_button()
	elif phase == Phase.EFFECT:
		palette_target = _effect_button()
	if palette_target != null:
		var palette_scroll := _palette_scroll()
		if palette_scroll != null:
			palette_scroll.ensure_control_visible(palette_target)
			await get_tree().process_frame
	_refresh_focus()


func _clear_focus() -> void:
	for frame in focus_frames:
		if is_instance_valid(frame):
			frame.queue_free()
	focus_frames.clear()
	_focused_controls.clear()


func _remind() -> void:
	if instruction_panel == null:
		return
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	instruction_panel.pivot_offset = instruction_panel.size / 2.0
	_panel_tween = create_tween()
	_panel_tween.tween_property(instruction_panel, "scale", Vector2(1.025, 1.025), 0.08)
	_panel_tween.tween_property(instruction_panel, "scale", Vector2.ONE, 0.12)
