class_name CardEditorTutorialController
extends Node

const ProgressStore = preload("res://TutorialProgress.gd")

enum Phase {
	INTRO,
	ART,
	IDENTITY,
	STATS,
	PREVIEW,
	SKILL,
	REVIEW,
	CONFIRM,
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
var navigate_on_complete := true


func start(owner_editor: Control) -> void:
	editor = owner_editor
	_build_ui()
	editor.name_input.text_changed.connect(_on_form_changed)
	editor.gender_select.item_selected.connect(func(_index: int): _on_form_changed(""))
	for spin in [editor.cost_input, editor.hp_input, editor.atk_input]:
		spin.value_changed.connect(func(_value: float): _on_form_changed(""))
	set_phase(Phase.REVIEW if PlayerData.tutorial_editor_stage == "card_review" else Phase.INTRO)


func allows(action: String, context: Dictionary = {}) -> bool:
	var allowed := false
	match phase:
		Phase.SKILL:
			allowed = action == "edit_skill" and int(context.get("index", -1)) == 0
		Phase.CONFIRM:
			allowed = action == "confirm_card"
		Phase.ART:
			allowed = action in ["browse_art", "clear_art"]
		_:
			allowed = false
	if not allowed:
		_remind()
	return allowed


func notify_edit_skill(index: int) -> void:
	if index == 0 and phase == Phase.SKILL:
		PlayerData.tutorial_editor_stage = "skill"


func handle_confirm(card: CardData) -> bool:
	if not allows("confirm_card"):
		return true
	ProgressStore.new(progress_path).mark_editor_completed()
	PlayerData.finish_card_tutorial(card)
	if navigate_on_complete:
		UIMotion.replace_scene("res://Main.tscn", true)
	return true


func set_phase(next_phase: int) -> void:
	phase = next_phase
	_clear_focus()
	match phase:
		Phase.INTRO:
			_set_copy("tutorial.card_intro_title", "tutorial.card_intro_body", true)
			_focus_controls([_editor_scroll(), editor.card_preview_panel])
		Phase.ART:
			_set_copy("tutorial.card_art_title", "tutorial.card_art_body", true)
			_focus_controls([editor.art_path_label.get_parent()])
		Phase.IDENTITY:
			_set_copy("tutorial.card_identity_title", "tutorial.card_identity_body", _identity_valid())
			_focus_controls([editor.name_input, editor.gender_select])
			editor.name_input.grab_focus()
		Phase.STATS:
			_set_copy("tutorial.card_stats_title", "tutorial.card_stats_body", _stats_valid())
			_focus_controls([editor.cost_input, editor.hp_input, editor.atk_input])
		Phase.PREVIEW:
			_set_copy("tutorial.card_preview_title", "tutorial.card_preview_body", true)
			_focus_controls([editor.card_preview_panel, editor.balance_summary])
		Phase.SKILL:
			_set_copy("tutorial.card_skill_title", "tutorial.card_skill_body", false)
			_focus_controls([editor.edit_skill1_btn])
		Phase.REVIEW:
			_set_copy("tutorial.card_review_title", "tutorial.card_review_body", true)
			_focus_controls([editor.skill1_summary, editor.card_preview_panel])
		Phase.CONFIRM:
			_set_copy("tutorial.card_confirm_title", "tutorial.card_confirm_body", false)
			_focus_controls([editor.save_button])
	step_label.text = Locale.t("tutorial.card_step", [phase + 1, 8])
	_position_panel_for_phase()
	_configure_controls()
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
	instruction_panel.position = Vector2(18, 82)
	instruction_panel.custom_minimum_size = Vector2(350, 248)
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
	body_label.custom_minimum_size = Vector2(318, 88)
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
	UITheme.animate_popup_enter(instruction_panel)


func _configure_controls() -> void:
	editor.template_button.disabled = true
	editor.browse_button.disabled = phase != Phase.ART
	editor.clear_art_button.disabled = phase != Phase.ART
	editor.name_input.editable = phase == Phase.IDENTITY
	editor.gender_select.disabled = phase != Phase.IDENTITY
	editor.cost_input.editable = phase == Phase.STATS
	editor.hp_input.editable = phase == Phase.STATS
	editor.atk_input.editable = phase == Phase.STATS
	editor.edit_skill1_btn.disabled = phase != Phase.SKILL
	editor.edit_skill2_btn.disabled = true
	editor.edit_skill3_btn.disabled = true
	editor.save_button.disabled = phase != Phase.CONFIRM


func _identity_valid() -> bool:
	return not editor.name_input.text.strip_edges().is_empty()


func _stats_valid() -> bool:
	return editor.cost_input.value >= 0 and editor.cost_input.value <= 5 \
			and editor.hp_input.value >= 1 and editor.atk_input.value >= 1


func _on_form_changed(_value = null) -> void:
	if phase == Phase.IDENTITY:
		var ready := _identity_valid()
		next_button.disabled = not ready
		next_button.text = Locale.t("tutorial.next") if ready else Locale.t("tutorial.complete_action")
	elif phase == Phase.STATS:
		var ready := _stats_valid()
		next_button.disabled = not ready
		next_button.text = Locale.t("tutorial.next") if ready else Locale.t("tutorial.complete_action")


func _on_next() -> void:
	match phase:
		Phase.INTRO: set_phase(Phase.ART)
		Phase.ART: set_phase(Phase.IDENTITY)
		Phase.IDENTITY when _identity_valid(): set_phase(Phase.STATS)
		Phase.STATS when _stats_valid(): set_phase(Phase.PREVIEW)
		Phase.PREVIEW: set_phase(Phase.SKILL)
		Phase.REVIEW: set_phase(Phase.CONFIRM)


func _on_skip() -> void:
	ProgressStore.new(progress_path).mark_skipped()
	PlayerData.cancel_skill_tutorial()
	if navigate_on_complete:
		UIMotion.go_back("res://MainMenu.tscn")


func _on_exit() -> void:
	PlayerData.cancel_skill_tutorial()
	if navigate_on_complete:
		UIMotion.go_back("res://MainMenu.tscn")


func _editor_scroll() -> ScrollContainer:
	return editor.get_node_or_null("Panel/MarginContainer/ScrollContainer") as ScrollContainer


func _position_panel_for_phase() -> void:
	var viewport_size := editor.get_viewport_rect().size
	var use_left := phase in [Phase.INTRO, Phase.PREVIEW, Phase.REVIEW]
	instruction_panel.position = Vector2(18.0 if use_left else maxf(18.0, viewport_size.x - 370.0), 82.0)


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
	for index in range(mini(_focused_controls.size(), focus_frames.size())):
		var control := _focused_controls[index]
		if control == null or not is_instance_valid(control):
			focus_frames[index].visible = false
			continue
		var frame_rect := control.get_global_rect().grow(6.0)
		var scroll := _editor_scroll()
		if scroll != null and scroll.is_ancestor_of(control):
			var clip_rect := scroll.get_global_rect()
			if not frame_rect.intersects(clip_rect):
				focus_frames[index].visible = false
				continue
			frame_rect = frame_rect.intersection(clip_rect)
		focus_frames[index].visible = frame_rect.size.x > 1.0 and frame_rect.size.y > 1.0
		focus_frames[index].position = frame_rect.position
		focus_frames[index].size = frame_rect.size


func _refresh_focus_deferred() -> void:
	await get_tree().process_frame
	var scroll := _editor_scroll()
	if phase == Phase.INTRO and scroll != null:
		scroll.scroll_vertical = 0
		await get_tree().process_frame
	if scroll != null and not _focused_controls.is_empty() and scroll.is_ancestor_of(_focused_controls[0]):
		scroll.ensure_control_visible(_focused_controls[0])
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
