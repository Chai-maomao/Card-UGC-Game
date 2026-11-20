extends RefCounted

const UITheme = preload("res://UITheme.gd")
const Workspace = preload("res://SkillWorkspace.gd")
var editor: Control
var workspace: Control
var toolbar: HBoxContainer
var inspector: PanelContainer
var inspector_body: VBoxContainer
var settings_section: VBoxContainer
var settings_tab: Button
var preview_tab: Button
var preview_section: VBoxContainer
var card_preview: Control
var compiled_summary: Label
var compile_button: Button
var try_button: Button
var zoom_label: Button
var category_rail: VBoxContainer
var _requested_category := ""
var _requested_scroll := -1
var _compiled_state: Dictionary = {}
var _compiled_name := ""
var has_compiled := false
var preview_feedback: Label

func install(owner_editor: Control) -> void:
	editor = owner_editor
	var main: VBoxContainer = editor.get_node("Panel/Margin/HBox/MainPanel/Margin")
	for child in main.get_children():
		child.hide()
	workspace = Workspace.new()
	workspace.editor_ref = weakref(editor)
	workspace.name = "Workspace"
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(workspace)
	editor.effects_list.reparent(workspace.stack)
	editor.effects_list.add_theme_constant_override("separation",-preload("res://SkillSocketStyle.gd").JOIN_OVERLAP)
	editor.effects_list.mouse_filter = Control.MOUSE_FILTER_PASS
	# The canvas is also a drop target, including when the script is empty.
	workspace.set_drag_forwarding(Callable(editor,"_get_drag_data_from_list"),
		func(_pos: Vector2, data):
			return editor._can_drop_on_workspace(data) and Rect2(Vector2.ZERO,workspace.size).has_point(workspace.last_pointer),
		func(_pos: Vector2, data): editor._drop_on_workspace(workspace.last_pointer,data))
	workspace.script_moved.connect(editor._finish_trigger_drag)
	if editor._is_spell():
		var handle := SkillBlock.new()
		handle.setup_hat(SkillEngine.TRIGGER_ON_CAST)
		handle.set_meta("skill_workspace",workspace)
		handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
		workspace.stack.add_child(handle)
		workspace.stack.move_child(handle,0)
	_build_toolbar()
	_build_inspector()
	_build_category_rail()
	_build_zoom_controls()
	editor._refresh_script()
	layout()
	workspace.reset_view.call_deferred()

func render_loose_groups() -> void:
	if workspace == null: return
	workspace.script_position = editor.workspace_script_position
	for view in workspace.loose_views:
		if is_instance_valid(view):
			view.get_parent().remove_child(view)
			view.queue_free()
	workspace.loose_views.clear()
	for key in editor.loose_groups:
		var group: Dictionary = editor.loose_groups[key]
		var box := VBoxContainer.new()
		box.name = "Loose_%s" % key
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_theme_constant_override("separation",-preload("res://SkillSocketStyle.gd").JOIN_OVERLAP)
		workspace.world.add_child(box)
		var point: Array = group["position"]
		box.position = Vector2(float(point[0]),float(point[1]))
		editor._render_effects(group["effects"],box,["loose",str(key)],false)
		editor._setup_slot_drop(box,["loose",str(key)])
		workspace.loose_views.append(box)
	for key in editor.loose_reporters:
		var record: Dictionary = editor.loose_reporters[key]
		var view := preload("res://SkillLooseReporter.gd").new()
		view.setup(editor, str(key), record)
		workspace.world.add_child(view)
		view.position = Vector2(record.position[0], record.position[1])
		workspace.loose_views.append(view)
	workspace._sync_view()

func _button(text: String, action: Callable, variant := "secondary") -> Button:
	var button := Button.new()
	button.text = text
	UITheme.apply_button(button, variant)
	button.pressed.connect(action)
	return button

func _build_toolbar() -> void:
	toolbar = HBoxContainer.new()
	toolbar.name = "WorkbenchToolbar"
	toolbar.add_theme_constant_override("separation", 8)
	editor.add_child(toolbar)
	editor.title_label.reparent(toolbar)
	editor.title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	editor.title_label.custom_minimum_size.x = 128
	editor.title_label.clip_text = true
	editor.title_label.show()
	for button in [editor._undo_btn, editor._redo_btn, editor._template_btn]:
		button.reparent(toolbar)
	toolbar.add_spacer(false)
	compile_button = _button(Locale.t("skill_editor.compile"), compile_preview)
	compile_button.name = "CompileButton"
	compile_button.tooltip_text = "检查技能是否合法，通过后可预览技能和卡牌。" if Locale.language == "zh" else "Check skill validity and unlock skill and card previews."
	toolbar.add_child(compile_button)
	try_button = _button(Locale.t("skill_editor.try"), _try_skill, "utility")
	toolbar.add_child(try_button)
	editor.save_button.reparent(toolbar)
	editor.save_button.show()
	UITheme.apply_button(editor.save_button, "primary")

func _try_skill() -> void:
	var errors: Array = editor._collect_errors()
	if not errors.is_empty():
		editor._show_save_blocked_popup(errors, "skill_editor.compile_failed")
		return
	var trial := preload("res://SkillTryout.gd").new()
	trial.skill = editor._build_skill().duplicate(true)
	trial.inspect_step.connect(func(path: Array):
		for candidate in editor.effects_list.find_children("*", "SkillBlock", true, false):
			if candidate.effect_path == path:
				workspace.reveal(candidate)
				candidate.modulate = Color(1.25,1.25,1.12)
				candidate.create_tween().tween_property(candidate,"modulate",Color.WHITE,0.45)
				break)
	editor.add_child(trial)

func _build_inspector() -> void:
	inspector = PanelContainer.new()
	inspector.name = "SkillInspector"
	var surface := StyleBoxFlat.new()
	surface.bg_color = UITheme.COLOR_PANEL
	surface.set_content_margin_all(16)
	surface.border_color = UITheme.Tokens.DIVIDER
	surface.border_width_left = 1
	inspector.add_theme_stylebox_override("panel", surface)
	editor.get_node("Panel/Margin/HBox").add_child(inspector)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(scroll)
	inspector_body = VBoxContainer.new()
	inspector_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_body.add_theme_constant_override("separation", 10)
	scroll.add_child(inspector_body)
	var tabs := HBoxContainer.new()
	inspector_body.add_child(tabs)
	settings_tab = _button(Locale.t("skill_editor.settings"), func(): _show_preview(false))
	preview_tab = _button(Locale.t("skill_editor.compiled_preview"), _request_preview)
	for tab in [settings_tab, preview_tab]:
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		UITheme.apply_button(tab, "navigation")
		tab.add_theme_font_size_override("font_size", 13)
		tabs.add_child(tab)
	settings_tab.button_pressed = true
	preview_feedback = Label.new()
	preview_feedback.text = Locale.t("skill_editor.compile_first")
	preview_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_feedback.add_theme_color_override("font_color",Color("ed7772"))
	preview_feedback.hide()
	inspector_body.add_child(preview_feedback)
	inspector_body.add_child(UITheme.separator())
	settings_section = VBoxContainer.new()
	settings_section.add_theme_constant_override("separation", 10)
	inspector_body.add_child(settings_section)
	for control in [editor.skill_name_label, editor.skill_name_input, editor.trigger_label,
			editor.trigger_preview_label, editor.trigger_side_row, editor.settings_label, editor.settings_row]:
		control.reparent(settings_section)
		control.custom_minimum_size.x = 0
	editor.settings_label.hide()
	# Settings form a narrow inspector instead of a long horizontal sentence.
	var fields: HBoxContainer = editor.skill_prob_spin.get_parent()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	fields.get_parent().add_child(column)
	for field in fields.get_children():
		field.reparent(column)
		if field is Label:
			field.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.hide()
	preview_section = VBoxContainer.new()
	preview_section.name = "CompiledPreview"
	preview_section.add_theme_constant_override("separation", 12)
	inspector_body.add_child(preview_section)
	var center := CenterContainer.new()
	preview_section.add_child(center)
	card_preview = preload("res://CardUI.tscn").instantiate()
	card_preview.set_meta("suppress_hover_hint",true)
	center.add_child(card_preview)
	card_preview.apply_ui_scale(1.25)
	card_preview.set_battle_layout_preview(true)
	compiled_summary = Label.new()
	compiled_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(compiled_summary)
	preview_section.add_child(compiled_summary)
	preview_section.hide()

func _build_category_rail() -> void:
	var palette_body: VBoxContainer = editor.palette_vbox.get_parent().get_parent()
	var palette_scroll: ScrollContainer = editor.palette_vbox.get_parent()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	palette_body.add_child(row)
	var rail_scroll := ScrollContainer.new()
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail_scroll.custom_minimum_size.x = 60
	row.add_child(rail_scroll)
	category_rail = VBoxContainer.new()
	category_rail.add_theme_constant_override("separation", 6)
	rail_scroll.add_child(category_rail)
	palette_scroll.reparent(row)
	palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_categories()
	palette_scroll.get_v_scroll_bar().value_changed.connect(func(_value): _sync_category())

func _sync_category() -> void:
	if category_rail == null: return
	var scroll: Control = editor.palette_vbox.get_parent()
	if scroll.scroll_vertical != _requested_scroll: _requested_category = ""
	var current := ""
	var requested_visible := false
	for header in editor.palette_vbox.get_children():
		if header is Button and header.visible and header.has_meta("section_title"):
			if header.get_meta("section_title") == _requested_category: requested_visible = true
			if current == "" or header.position.y <= scroll.scroll_vertical + 24:
				current = str(header.get_meta("section_title"))
	if requested_visible: current = _requested_category
	for button in category_rail.get_children():
		if button is Button: button.set_pressed_no_signal(button.text == current)

func refresh_categories() -> void:
	if category_rail == null:
		return
	for block in editor.palette_vbox.find_children("*","SkillPaletteBlock",true,false): block.set_meta("skill_workspace",workspace)
	for child in category_rail.get_children():
		child.queue_free()
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for header in editor.palette_vbox.get_children():
		if not header is Button or not header.has_meta("section_title"):
			continue
		var title := str(header.get_meta("section_title"))
		var button := _button(title, func():
			editor.palette_search.text = ""
			editor._filter_palette("")
			var scroll: ScrollContainer = editor.palette_vbox.get_parent()
			var box: Control = header.get_parent().get_child(header.get_index()+1)
			header.set_meta("user_open", true)
			box.show()
			await editor.get_tree().process_frame
			if not is_instance_valid(header): return
			scroll.scroll_vertical = maxi(0, roundi(header.position.y))
			_requested_scroll = scroll.scroll_vertical
			_requested_category = title
			_sync_category())
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(54, 42)
		button.add_theme_font_size_override("font_size", 12)
		category_rail.add_child(button)

func _build_zoom_controls() -> void:
	var dock := HBoxContainer.new()
	dock.name = "ZoomControls"
	workspace.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.offset_left = -190
	dock.offset_top = -54
	dock.offset_right = -16
	dock.offset_bottom = -14
	dock.add_child(_button("−", func(): workspace.set_zoom(workspace.zoom / 1.2)))
	zoom_label = _button("100%", func(): workspace.reset_view())
	zoom_label.tooltip_text = Locale.t("skill_editor.reset_view")
	dock.add_child(zoom_label)
	dock.add_child(_button("+", func(): workspace.set_zoom(workspace.zoom * 1.2)))
	workspace.view_changed.connect(func(): zoom_label.text = "%d%%" % roundi(workspace.zoom * 100))

func layout() -> void:
	var width := editor.get_viewport_rect().size.x
	var panel: Control = editor.get_node("Panel")
	panel.custom_minimum_size = Vector2.ZERO
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_top = 84
	panel.offset_bottom = -20
	UITheme.place_page_back(editor, editor.cancel_button)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_left = 140
	toolbar.offset_right = -24
	toolbar.offset_top = 20
	toolbar.offset_bottom = 64
	for side in ["left", "right", "top", "bottom"]:
		editor.get_node("Panel/Margin").add_theme_constant_override("margin_"+side, 0)
		editor.get_node("Panel/Margin/HBox/PalettePanel/Margin").add_theme_constant_override("margin_"+side, 12)
	editor.get_node("Panel/Margin/HBox").add_theme_constant_override("separation", 0)
	var palette: Control = editor.get_node("Panel/Margin/HBox/PalettePanel")
	var palette_width := 250.0 if width >= 1100 else 220.0
	if Locale.language == "en":
		palette_width = maxf(palette_width, minf(280.0, width * 0.30))
	palette.custom_minimum_size.x = palette_width
	inspector.custom_minimum_size.x = 252 if width >= 1100 else 214
	var main: Control = editor.get_node("Panel/Margin/HBox/MainPanel/Margin")
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.get_node("Panel/Margin/HBox/ColumnSeparator").hide()
	var palette_surface := StyleBoxFlat.new()
	palette_surface.bg_color = UITheme.COLOR_PANEL
	palette.add_theme_stylebox_override("panel", palette_surface)
	for button in [editor._undo_btn, editor._redo_btn, editor._template_btn, compile_button, try_button, editor.save_button]:
		button.add_theme_font_size_override("font_size", 14)
		button.custom_minimum_size.y = 40
	editor.title_label.add_theme_font_size_override("font_size", 18)
	card_preview.apply_ui_scale(1.25 if width >= 1100 else 1.05)

func invalidate_preview() -> void:
	if preview_section == null or not has_compiled:
		return
	if editor._editor_state() != _compiled_state or editor.skill_name_input.text != _compiled_name:
		has_compiled = false
		preview_feedback.hide()
		_show_preview(false)

func _request_preview() -> void:
	if has_compiled:
		_show_preview(true)
		return
	_show_preview(false)
	preview_feedback.show()
	UITheme.reject_button(preview_tab)

func _show_preview(show_preview: bool) -> void:
	settings_section.visible = not show_preview
	preview_section.visible = show_preview
	settings_tab.button_pressed = not show_preview
	preview_tab.button_pressed = show_preview

func compile_preview() -> bool:
	has_compiled = false
	preview_feedback.hide()
	_show_preview(false)
	var errors: Array = editor._collect_errors()
	if not errors.is_empty():
		editor._show_save_blocked_popup(errors, "skill_editor.compile_failed")
		return false
	var draft: Dictionary = PlayerData.card_draft.duplicate(true)
	var key: String = editor._skill_key_for_index(PlayerData.editing_skill_index)
	draft[key] = editor._build_skill()
	if key == "skill1": draft["talent"] = {}
	elif key == "talent": draft["skill1"] = {}
	card_preview.set_card(PlayerData.build_card_from_draft(draft))
	card_preview.set_battle_layout_preview(true)
	card_preview.tooltip_text = ""
	for child in card_preview.find_children("*","Control",true,false): child.tooltip_text = ""
	compiled_summary.text = editor._format_skill(editor._build_skill())
	_compiled_state = editor._editor_state().duplicate(true)
	_compiled_name = editor.skill_name_input.text
	has_compiled = true
	_show_preview(true)
	return true
