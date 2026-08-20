extends Control

# ============================================
# Skill Editor — Scratch-style block editor.
# Left palette (trigger hats + effect blocks grouped by category), right
# script area (trigger hat + stacked effect blocks). Click palette blocks to
# add them; ⚙ on a block opens the SkillEffectForm advanced popup.
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

@onready var title_label = $Panel/Margin/HBox/MainPanel/Margin/TitleLabel
@onready var help_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/HelpLabel
@onready var skill_name_input = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/SkillNameInput
@onready var skill_name_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/SkillNameLabel
@onready var trigger_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/TriggerLabel
@onready var trigger_preview_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/TriggerPreviewLabel
@onready var settings_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/SettingsLabel
@onready var settings_row = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/SettingsRow
@onready var effects_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsLabel
@onready var effects_hint_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsHintLabel
@onready var effects_list = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList
@onready var preview_panel = $Panel/Margin/HBox/MainPanel/Margin/PreviewPanel
@onready var preview_label = $Panel/Margin/HBox/MainPanel/Margin/PreviewPanel/Margin/VBox/PreviewLabel
@onready var skill_summary = $Panel/Margin/HBox/MainPanel/Margin/PreviewPanel/Margin/VBox/PreviewScroll/SkillSummary
@onready var save_button = $Panel/Margin/HBox/MainPanel/Margin/ButtonRow/SaveButton
@onready var cancel_button = $Panel/Margin/HBox/MainPanel/Margin/ButtonRow/CancelButton
@onready var palette_title = $Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteTitle
@onready var palette_search = $Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteSearch
@onready var palette_vbox = $Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteScroll/PaletteVBox

var effect_data: Array = []        # [{target, effect, value, buff_id, duration, ...}, ...]
var editing_effect_path: Array = [] # [] = none; last element -1 = append to the list at path
var current_trigger_key: String = SkillEngine.TRIGGER_ON_ATTACK
var skill_prob_spin: SpinBox       # skill-level probability
var max_uses_spin: SpinBox         # max uses per game (限定技)
var skill_type_select: OptionButton # normal or talent
var skill_type_row: HBoxContainer   # row containing skill_type_select (hidden for active skills)

# Undo / redo history (Scratch-style edit history) — delegated to a dedicated
# manager so the editor only forwards its effect_data.
var _undo_mgr := SkillUndoManager.new()
var _palette_builder := SkillPaletteBuilder.new()
var _undo_btn: Button
var _redo_btn: Button
var _template_btn: Button


# ============================================
# Undo / redo (delegated to SkillUndoManager)
# ============================================

func _editor_state() -> Dictionary:
	# Full editing state (trigger + effects + skill metadata) so undo/redo
	# restore settings-level edits too, not just the block list.
	return {
		"trigger": current_trigger_key,
		"effects": effect_data.duplicate(true),
		"probability": int(skill_prob_spin.value) if skill_prob_spin != null else 100,
		"max_uses": int(max_uses_spin.value) if max_uses_spin != null else 0,
		"skill_type": int(skill_type_select.selected) if skill_type_select != null else 0,
	}


func _apply_state(s: Dictionary) -> void:
	current_trigger_key = str(s.get("trigger", current_trigger_key))
	effect_data = (s.get("effects", []) as Array).duplicate(true)
	if skill_prob_spin != null:
		skill_prob_spin.set_value_no_signal(float(s.get("probability", 100)))
	if max_uses_spin != null:
		max_uses_spin.set_value_no_signal(float(s.get("max_uses", 0)))
	if skill_type_select != null:
		skill_type_select.select(int(s.get("skill_type", 0)))
	_update_trigger_preview()
	_update_skill_type_visibility()
	_refresh_script()
	_update_summary()
	_refresh_undo_buttons()


func _maybe_snapshot() -> void:
	_undo_mgr.maybe_snapshot(_editor_state())
	_refresh_undo_buttons()


func _undo() -> void:
	var undid: Variant = _undo_mgr.undo(_editor_state())
	_apply_state(undid)


func _redo() -> void:
	_apply_state(_undo_mgr.redo(_editor_state()))


func _reset_undo_history() -> void:
	_undo_mgr.init_from(_editor_state())
	_refresh_undo_buttons()


func _refresh_undo_buttons() -> void:
	if _undo_btn:
		_undo_btn.disabled = not _undo_mgr.can_undo()
	if _redo_btn:
		_redo_btn.disabled = not _undo_mgr.can_redo()


func _deep_equal(a: Variant, b: Variant) -> bool:
	return SkillUndoManager.deep_equal(a, b)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_ev := event as InputEventKey
	if key_ev == null or not key_ev.pressed or key_ev.echo:
		return
	if not key_ev.ctrl_pressed:
		return
	if key_ev.keycode == Key.KEY_Z:
		if key_ev.shift_pressed:
			_redo()
		else:
			_undo()
		accept_event()
	elif key_ev.keycode == Key.KEY_Y:
		_redo()
		accept_event()


func _is_spell() -> bool:
	return PlayerData.card_draft.get("card_type", "minion") == "spell"


func _is_parasite() -> bool:
	return PlayerData.card_draft.get("card_type", "minion") == "parasite"


func _apply_texts() -> void:
	var skill_index: int = PlayerData.editing_skill_index
	var is_spell := _is_spell()
	title_label.text = Locale.t("skill_editor.title_spell") if is_spell else Locale.t("skill_editor.title", [skill_index + 1])
	help_label.text = Locale.t("skill_editor.help_spell" if is_spell else "skill_editor.help")
	palette_title.text = Locale.t("skill_editor.palette_title")
	palette_search.placeholder_text = Locale.t("skill_editor.palette_search")
	effects_label.text = Locale.t("skill_editor.effects" if not is_spell else "skill_editor.spell_effects")
	effects_hint_label.text = Locale.t("skill_editor.effects_hint" if not is_spell else "skill_editor.effects_hint_spell")
	settings_label.text = Locale.t("skill_editor.settings")
	preview_label.text = Locale.t("skill_editor.preview" if not is_spell else "skill_editor.spell_preview")
	save_button.text = Locale.t("skill_editor.save")
	cancel_button.text = Locale.t("skill_editor.cancel")

	# Spell skills have no name / trigger — hide those rows.
	skill_name_label.visible = not is_spell
	skill_name_input.visible = not is_spell
	trigger_label.visible = not is_spell
	trigger_preview_label.visible = not is_spell
	if not is_spell:
		skill_name_label.text = Locale.t("skill_editor.name")
		skill_name_input.placeholder_text = Locale.t("skill_editor.name_placeholder")
		trigger_label.text = Locale.t("skill_editor.trigger")
	_update_trigger_preview()


# ============================================
# Layout / theme
# ============================================

func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var panel := $Panel
	panel.offset_left = -460.0 * s
	panel.offset_top = -320.0 * s
	panel.offset_right = 460.0 * s
	panel.offset_bottom = 320.0 * s
	$Panel/Margin/HBox/PalettePanel.custom_minimum_size = Vector2(250 * s, 0)
	for label in [title_label, help_label, skill_name_label, trigger_label, trigger_preview_label,
			settings_label, effects_label, effects_hint_label, preview_label, skill_summary, palette_title]:
		if label:
			var is_title: bool = label == title_label or label == palette_title
			label.add_theme_font_size_override("font_size", max(13, int(18 * s)) if is_title else max(10, int(14 * s)))
	if skill_prob_spin:
		skill_prob_spin.custom_minimum_size = Vector2(60 * s, 0)
	if max_uses_spin:
		max_uses_spin.custom_minimum_size = Vector2(60 * s, 0)


func _apply_theme() -> void:
	UITheme.apply_app_background(self)
	UITheme.apply_panel($Panel, "gold")
	UITheme.apply_panel($Panel/Margin/HBox/PalettePanel, "dark")
	UITheme.apply_panel($Panel/Margin/HBox/MainPanel, "dark")
	# Preview card: soft recessed panel so the pinned summary reads as a
	# distinct "live result" area rather than free-floating text.
	var pv_style := StyleBoxFlat.new()
	pv_style.bg_color = Color(0.06, 0.07, 0.095, 0.98)
	pv_style.border_color = Color(0.55, 0.44, 0.24, 0.55)
	pv_style.set_border_width_all(1)
	pv_style.set_corner_radius_all(8)
	pv_style.shadow_color = Color(0, 0, 0, 0.25)
	pv_style.shadow_size = 2
	preview_panel.add_theme_stylebox_override("panel", pv_style)
	UITheme.apply_title(title_label, max(14, int(18 * _ui_scale())))
	UITheme.apply_title(palette_title, max(13, int(15 * _ui_scale())))
	UITheme.apply_input(palette_search)
	UITheme.apply_input(skill_name_input)
	UITheme.apply_button(save_button, "primary")
	UITheme.apply_button(cancel_button, "secondary")
	for soft_label in [help_label, trigger_preview_label, skill_summary]:
		UITheme.apply_label(soft_label, true)
	for label in [skill_name_label, trigger_label, settings_label, effects_label, effects_hint_label, preview_label]:
		UITheme.apply_label(label)
	# Entrance: fade the whole editor panel in (full-rect, no scale).
	UITheme.fade_enter($Panel, 0.22)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


# ============================================
# Palette (built by SkillPaletteBuilder)
# ============================================

func _build_palette() -> void:
	_palette_builder.editor = self
	_palette_builder.build()
	_filter_palette(palette_search.text if palette_search != null else "")


func _filter_palette(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	var children := palette_vbox.get_children()
	var index := 0
	while index + 1 < children.size():
		var header := children[index] as Button
		var box := children[index + 1] as VBoxContainer
		index += 2
		if header == null or box == null:
			continue
		var title_matches := needle != "" and str(header.get_meta("section_title", "")).to_lower().contains(needle)
		var any_match := false
		for item in box.get_children():
			if not (item is Button):
				continue
			var matches := needle == "" or title_matches or (item as Button).text.to_lower().contains(needle)
			item.visible = matches
			any_match = any_match or matches
		header.visible = needle == "" or any_match
		box.visible = any_match if needle != "" else bool(header.get_meta("user_open", true))


func _select_trigger(trigger_key: String) -> void:
	current_trigger_key = trigger_key
	_update_trigger_preview()
	_update_skill_type_visibility()
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _add_effect_block(effect_id: String) -> void:
	effect_data.append(_default_effect(effect_id))
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


# ============================================
# Script area (hat + effect blocks)
# ============================================

func _refresh_script() -> void:
	for child in effects_list.get_children():
		child.queue_free()
	if _is_spell():
		# Spells are locked to on_cast and have no visible event block.
		_render_effects(effect_data, effects_list, [], false)
		_maybe_add_slot_hint(effects_list)
	else:
		# The whole skill lives inside one event hat block (Scratch-style).
		var event_block := SkillBlock.new()
		event_block.setup_event_block(current_trigger_key)
		effects_list.add_child(event_block)
		_render_effects(effect_data, event_block.body_container, [], true)
		_maybe_add_slot_hint(event_block.body_container)
		_setup_slot_drop(event_block.body_container, [])
	_refresh_error_banner()
	_mark_invalid_conditions()


# ============================================
# Compile-error hints (delegated to SkillErrorChecker)
# ============================================

var _error_checker := SkillErrorChecker.new()


func _collect_errors() -> Array:
	_error_checker.editor = self
	return _error_checker.collect_errors()


func _refresh_error_banner() -> void:
	_error_checker.editor = self
	_error_checker.refresh_banner()


func _mark_invalid_conditions() -> void:
	_error_checker.editor = self
	_error_checker.mark_invalid_conditions()


func _focus_issue_path(path: Array) -> void:
	if path.is_empty():
		return
	for candidate in effects_list.find_children("*", "SkillBlock", true, false):
		var block := candidate as SkillBlock
		if block != null and block.effect_path == path:
			var scroll := $Panel/Margin/HBox/MainPanel/Margin/Scroll as ScrollContainer
			scroll.ensure_control_visible(block)
			UITheme.reject_shake(block)
			return


# Recursively renders effect blocks; if/else blocks get their then/else
# slots filled with nested blocks (Scratch-style: add by dragging a palette
# block into the recessed slot — no "+ 添加效果" button).
func _render_effects(list: Array, container: VBoxContainer, base_path: Array, top_level: bool) -> void:
	for i in range(list.size()):
		var path: Array = base_path.duplicate()
		path.append(i)
		var eff: Dictionary = list[i]
		var effect_id: String = str(eff.get("effect", ""))
		if effect_id == SkillEngine.EFFECT_IF_ELSE or effect_id == SkillEngine.EFFECT_IF:
			var block := SkillBlock.new()
			block.setup_if_else(eff, path)
			block.draggable = true
			_connect_block_signals(block)
			container.add_child(block)
			if top_level:
				block.set_order(i + 1)
			var then_path: Array = path.duplicate()
			then_path.append("then")
			_render_effects(eff.get("then_effects", []), block.then_container, then_path, false)
			_maybe_add_slot_hint(block.then_container)
			_setup_slot_drop(block.then_container, then_path)
			if block.has_else:
				var else_path: Array = path.duplicate()
				else_path.append("else")
				_render_effects(eff.get("else_effects", []), block.else_container, else_path, false)
				_maybe_add_slot_hint(block.else_container)
				_setup_slot_drop(block.else_container, else_path)
		elif effect_id == SkillEngine.EFFECT_REPEAT:
			var block := SkillBlock.new()
			block.setup_repeat_block(eff, path)
			block.draggable = true
			_connect_block_signals(block)
			container.add_child(block)
			if top_level:
				block.set_order(i + 1)
			var loop_path: Array = path.duplicate()
			loop_path.append("then")
			_render_effects(eff.get("then_effects", []), block.then_container, loop_path, false)
			_maybe_add_slot_hint(block.then_container)
			_setup_slot_drop(block.then_container, loop_path)
		elif effect_id == SkillEngine.EFFECT_STOP:
			var block := SkillBlock.new()
			block.setup_stop_block(path)
			_connect_block_signals(block)
			container.add_child(block)
			if top_level:
				block.set_order(i + 1)
		else:
			var block := SkillBlock.new()
			block.setup_effect(eff, path)
			block.draggable = true
			_connect_block_signals(block)
			container.add_child(block)
			if top_level:
				block.set_order(i + 1)


# Empty then/else slots get a faint "拖入积木" placeholder (mouse_filter IGNORE
# so it never blocks drag-drops). It disappears once a block is dragged in.
# The empty slot also gets a bright border so it clearly reads as an
# insertable gap.
func _maybe_add_slot_hint(slot: VBoxContainer) -> void:
	if slot.get_child_count() > 0:
		return
	var hint := Label.new()
	hint.text = Locale.t("skill_editor.slot_hint")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(hint)
	var panel := slot.get_parent()
	if panel is PanelContainer:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0.16)
		st.border_color = Color(0.45, 0.70, 0.88, 0.65)
		st.set_border_width_all(1)
		st.set_corner_radius_all(5)
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		(panel as PanelContainer).add_theme_stylebox_override("panel", st)


func _connect_block_signals(block: SkillBlock) -> void:
	block.edit_requested.connect(_on_block_edit_path)
	block.delete_requested.connect(_on_block_delete_path)
	block.move_requested.connect(_on_block_move_path)
	block.drop_requested.connect(_on_block_drop_path)
	block.changed.connect(_on_block_changed)
	block.context_requested.connect(_on_block_context_requested)
	block.condition_dropped.connect(_on_block_condition_dropped)
	block.insertion_requested.connect(_on_block_insertion_requested)
	block.insertion_hidden.connect(_hide_insertion_line)


# A block is being hovered while dragging another block over it: move the
# insertion line to the exact gap the drop would land in.
func _on_block_insertion_requested(vbox: VBoxContainer, index: int) -> void:
	if vbox != null:
		_activate_slot_highlight(vbox)
		_show_insertion_line(vbox, index)


func _setup_drop_targets() -> void:
	# The script list accepts palette drops (append) and script-internal reorders.
	_setup_slot_drop(effects_list, [])
	# Dragging a script block back onto the palette deletes it (Scratch-like).
	var palette_panel: Panel = $Panel/Margin/HBox/PalettePanel
	palette_panel.set_drag_forwarding(
		Callable(self, "_get_drag_data_from_list"),
		Callable(self, "_can_drop_on_palette"),
		Callable(self, "_drop_on_palette"),
	)


# Registers a container as a drop target. list_path identifies which effect
# list the slot maps to ([] = top-level, [0, "then"] = first block's then slot).
func _setup_slot_drop(vbox: VBoxContainer, list_path: Array) -> void:
	vbox.set_meta("list_path", list_path)
	vbox.set_drag_forwarding(
		Callable(self, "_get_drag_data_from_list"),
		func(pos: Vector2, data): return _can_drop_on_slot(vbox, pos, data),
		func(pos: Vector2, data): _drop_on_slot(vbox, pos, data),
	)


func _get_drag_data_from_list(_pos: Vector2):
	return null


# Scratch-style drop feedback: while a drag hovers a slot, show a bright
# insertion line at the position the block would land, and glow the target
# slot. Cleaned up on drop and by _process once the GUI drag ends.
var _insertion_line: Control
var _highlighted_slot: VBoxContainer
var _slot_orig_style: StyleBox
var _palette_discard_highlight: bool = false
var _palette_orig_style: StyleBox


func _can_drop_on_slot(vbox: VBoxContainer, _pos: Vector2, data) -> bool:
	var ok: bool = data is Dictionary and data.get("type", "") == "effect_block"
	if ok:
		_activate_slot_highlight(vbox)
		_show_insertion_line(vbox, _insertion_index_at(vbox, _pos))
	else:
		_hide_insertion_line()
	return ok


func _activate_slot_highlight(vbox: VBoxContainer) -> void:
	if _highlighted_slot == vbox:
		return
	if _highlighted_slot != null:
		_highlight_slot(_highlighted_slot, false)
	_highlight_slot(vbox, true)
	_highlighted_slot = vbox


func _show_insertion_line(vbox: VBoxContainer, index: int) -> void:
	if _insertion_line == null:
		_insertion_line = PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.34, 0.92, 1.0)
		st.border_color = Color(0.82, 0.98, 1.0, 0.95)
		st.set_border_width_all(1)
		st.set_corner_radius_all(2)
		st.shadow_color = Color(0.15, 0.78, 1.0, 0.75)
		st.shadow_size = 6
		_insertion_line.add_theme_stylebox_override("panel", st)
		_insertion_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_insertion_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_insertion_line.custom_minimum_size = Vector2(40, 5)
	if _insertion_line.get_parent() != null:
		_insertion_line.get_parent().remove_child(_insertion_line)
	vbox.add_child(_insertion_line)
	# The VBox lays the line out naturally; place it before the block that
	# would land at `index` (skipping hint labels / the line itself).
	var child_index := 0
	var seen := 0
	for child in vbox.get_children():
		if child == _insertion_line:
			continue
		if seen == index:
			break
		if child is SkillBlock:
			seen += 1
		child_index += 1
	vbox.move_child(_insertion_line, child_index)


# Glows the recessed slot panel while a drag hovers it, so the drop target is
# unmistakable. Restores the original style (incl. the empty-slot border) on
# leave/drop.
func _highlight_slot(vbox: VBoxContainer, on: bool) -> void:
	var panel := vbox.get_parent()
	if not (panel is PanelContainer):
		return
	if on:
		_slot_orig_style = (panel as PanelContainer).get_theme_stylebox("panel")
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.10, 0.48, 0.66, 0.38)
		st.border_color = Color(0.42, 0.90, 1.0, 0.98)
		st.set_border_width_all(2)
		st.set_corner_radius_all(5)
		st.shadow_size = 0
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		(panel as PanelContainer).add_theme_stylebox_override("panel", st)
	else:
		if _slot_orig_style != null:
			(panel as PanelContainer).add_theme_stylebox_override("panel", _slot_orig_style)
		else:
			(panel as PanelContainer).remove_theme_stylebox_override("panel")


func _hide_insertion_line() -> void:
	if _highlighted_slot != null:
		_highlight_slot(_highlighted_slot, false)
		_highlighted_slot = null
	if _insertion_line != null and _insertion_line.get_parent() != null:
		_insertion_line.get_parent().remove_child(_insertion_line)


func _process(_delta: float) -> void:
	# A drag that ends over an invalid spot leaves the insertion line behind;
	# once the GUI drag is finished, drop it.
	if _insertion_line != null and _insertion_line.get_parent() != null \
			and not get_viewport().gui_is_dragging():
		_hide_insertion_line()
	if _palette_discard_highlight and not get_viewport().gui_is_dragging():
		_set_palette_discard_highlight(false)
	elif _palette_discard_highlight:
		var palette_panel: Panel = $Panel/Margin/HBox/PalettePanel
		if not palette_panel.get_global_rect().has_point(get_global_mouse_position()):
			_set_palette_discard_highlight(false)


func _can_drop_on_palette(_pos: Vector2, data) -> bool:
	if not (data is Dictionary):
		_set_palette_discard_highlight(false)
		return false
	var t: String = str(data.get("type", ""))
	var ok := false
	match t:
		"effect_block":
			ok = (data.get("from_path", []) as Array).size() > 0
		"var_block", "expr_block", "target_block", "side_block":
			# Only a slot-borne chip (not a fresh palette button) can be
			# discarded here.
			ok = data.has("from_slot")
		"boolean_block", "logic_block", "condition_block":
			ok = data.has("from_cond_slot")
	_set_palette_discard_highlight(ok)
	return ok


func _set_palette_discard_highlight(on: bool) -> void:
	if _palette_discard_highlight == on:
		return
	_palette_discard_highlight = on
	var panel: Panel = $Panel/Margin/HBox/PalettePanel
	if on:
		_palette_orig_style = panel.get_theme_stylebox("panel")
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.22, 0.055, 0.075, 0.97)
		st.border_color = Color(0.96, 0.34, 0.40, 0.98)
		st.set_border_width_all(2)
		st.set_corner_radius_all(8)
		st.shadow_color = Color(0.85, 0.12, 0.20, 0.40)
		st.shadow_size = 8
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 10
		st.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", st)
	elif _palette_orig_style != null:
		panel.add_theme_stylebox_override("panel", _palette_orig_style)


func _drop_on_palette(_pos: Vector2, data) -> void:
	_set_palette_discard_highlight(false)
	var t: String = str(data.get("type", ""))
	if t == "effect_block":
		var from_path: Array = data.get("from_path", [])
		if from_path.size() > 0:
			_on_block_delete_path(from_path)
		return
	if data.has("from_slot"):
		# Dragging a variable / math reporter back to the palette restores the
		# number slot to a plain fixed number (Scratch drop-to-discard).
		var slot: Object = data["from_slot"]
		if slot != null and is_instance_valid(slot) and slot.has_method("clear_to_number"):
			slot.call("clear_to_number")
		return
	if data.has("from_cond_slot"):
		var block: SkillBlock = data["from_cond_slot"]
		if block != null and is_instance_valid(block):
			var eff := _effect_at(block.effect_path)
			eff.erase("condition")
			eff.erase("condition_type")
			eff.erase("condition_op")
			eff.erase("condition_value")
			eff.erase("condition_buff_id")
			_refresh_script()
			_update_summary()
			_maybe_snapshot()


func _drop_on_slot(vbox: VBoxContainer, pos: Vector2, data) -> void:
	_hide_insertion_line()
	var list_path: Array = vbox.get_meta("list_path", [])
	var index := _insertion_index_at(vbox, pos)
	_apply_drop(data, list_path, index)


# Computes the insertion index under the mouse by comparing against each
# stacked block's vertical center (ignoring "+ 添加效果" buttons).
func _insertion_index_at(vbox: VBoxContainer, pos: Vector2) -> int:
	var block_idx := 0
	for child in vbox.get_children():
		if child is SkillBlock:
			if pos.y < child.position.y + child.size.y * 0.5:
				return block_idx
			block_idx += 1
	return block_idx


# Unified drop handler: palette drop (insert new block) or script-internal
# move (remove from source, insert at target), with cycle protection.
func _apply_drop(data, list_path: Array, index: int) -> void:
	var from_path: Array = data.get("from_path", [])
	if from_path.size() > 0:
		_move_effect(from_path, list_path, index)
	else:
		var effect_id: String = str(data.get("effect_id", ""))
		if effect_id == "":
			return
		var list := _list_at(list_path)
		var eff := _new_block_for(effect_id)
		list.insert(clamp(index, 0, list.size()), eff)
		_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _move_effect(from_path: Array, list_path: Array, index: int) -> void:
	# Reject moving a block into its own subtree (would create a cycle).
	if _is_path_prefix(from_path, list_path):
		return
	var from_parent: Array = from_path.slice(0, from_path.size() - 1)
	var from_idx: int = from_path[from_path.size() - 1]
	var src_list := _list_at(from_parent)
	if from_idx < 0 or from_idx >= src_list.size():
		return
	var dst_list := _list_at(list_path)
	var eff: Dictionary = src_list[from_idx]
	src_list.remove_at(from_idx)
	# When reordering within the same list, shifting left affects the index.
	if from_parent == list_path and from_idx < index:
		index -= 1
	dst_list.insert(clamp(index, 0, dst_list.size()), eff)
	_refresh_script()
	_maybe_snapshot()


# True when prefix is a strict ancestor path of path.
func _is_path_prefix(prefix: Array, path: Array) -> bool:
	if prefix.is_empty() or prefix.size() >= path.size():
		return false
	for i in range(prefix.size()):
		if prefix[i] != path[i]:
			return false
	return true


# ============================================
# Path-based tree operations
# ============================================

# Returns the effect list identified by a list path: [] = top-level,
# [0, "then"] = first block's then_effects, [0, "then", 1, "else"] = ...
func _list_at(list_path: Array) -> Array:
	if list_path.is_empty():
		return effect_data
	var eff: Dictionary = effect_data[list_path[0]]
	var i := 1
	while i + 1 < list_path.size():
		var sub: Array = eff.get(str(list_path[i]) + "_effects", [])
		eff = sub[list_path[i + 1]]
		i += 2
	return eff.get(str(list_path[list_path.size() - 1]) + "_effects", [])


# Effect path -> its parent list path (e.g. [0, "then", 2] -> [0, "then"]).
# Also accepts a list path directly ([0, "then"]) — the last element then
# already names the "_effects" slot, so nothing is stripped.
func _effect_list_at(path: Array) -> Array:
	var list_path: Array = path.duplicate()
	if list_path.is_empty():
		return effect_data
	if list_path[list_path.size() - 1] is int:
		list_path.pop_back()
	return _list_at(list_path)


func _effect_at(path: Array) -> Dictionary:
	if path.size() == 1:
		return effect_data[path[0]]
	var list := _effect_list_at(path)
	return list[path[path.size() - 1]]


func _new_block_for(effect_id: String) -> Dictionary:
	if effect_id == SkillEngine.EFFECT_IF_ELSE:
		return _default_if_else()
	if effect_id == SkillEngine.EFFECT_IF:
		return _default_if()
	if effect_id == SkillEngine.EFFECT_REPEAT:
		return _default_repeat()
	if effect_id == SkillEngine.EFFECT_STOP:
		return {"effect": SkillEngine.EFFECT_STOP}
	return _default_effect(effect_id)


func _on_block_edit_path(path: Array) -> void:
	var effect_id: String = str(_effect_at(path).get("effect", ""))
	if effect_id == SkillEngine.EFFECT_IF_ELSE or effect_id == SkillEngine.EFFECT_IF:
		_open_if_condition_popup(path)
	else:
		_open_effect_popup(path)


func _on_block_delete_path(path: Array) -> void:
	var list := _effect_list_at(path)
	var idx: int = path[path.size() - 1]
	if idx < 0 or idx >= list.size():
		return
	list.remove_at(idx)
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _on_block_move_path(path: Array, offset: int) -> void:
	var list := _effect_list_at(path)
	var idx: int = path[path.size() - 1]
	var target := idx + offset
	if idx < 0 or idx >= list.size() or target < 0 or target >= list.size():
		return
	var tmp = list[idx]
	list[idx] = list[target]
	list[target] = tmp
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _on_block_drop_path(from_path: Array, to_path: Array, insert_after: bool, data) -> void:
	var list_path: Array = to_path.slice(0, to_path.size() - 1)
	var index: int = to_path[to_path.size() - 1] + (1 if insert_after else 0)
	_apply_drop(data, list_path, index)


func _on_block_changed(_path: Array) -> void:
	# Inline parameter edits already mutated the effect data (dicts are shared
	# references); only the summary needs refreshing, not the whole script.
	_update_summary()
	_maybe_snapshot()


func _on_block_context_requested(path: Array, at: Vector2) -> void:
	var menu := PopupMenu.new()
	menu.add_item(Locale.t("skill_editor.duplicate"), 0)
	menu.add_item(Locale.t("skill_editor.delete"), 1)
	menu.id_pressed.connect(func(id: int):
		if id == 0:
			_duplicate_effect(path)
		elif id == 1:
			_on_block_delete_path(path)
	)
	add_child(menu)
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.popup()


func _duplicate_effect(path: Array) -> void:
	var list := _effect_list_at(path)
	var idx: int = path[path.size() - 1]
	if idx < 0 or idx >= list.size():
		return
	var copy: Dictionary = (list[idx] as Dictionary).duplicate(true)
	list.insert(idx + 1, copy)
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


# ============================================
# Effect popup (advanced settings via SkillEffectForm)
# ============================================

func _open_effect_popup(path: Array):
	editing_effect_path = path.duplicate()
	var form := SkillEffectForm.new()
	add_child(form)
	var existing: Dictionary = _effect_at(path)
	form.setup(_ui_scale(), existing, _selected_trigger_key())
	form.confirmed.connect(_on_effect_form_confirmed)
	form.cancelled.connect(func(): editing_effect_path = [])


func _on_effect_form_confirmed(eff: Dictionary):
	if editing_effect_path.is_empty():
		return
	var path: Array = editing_effect_path.duplicate()
	var last: int = path.pop_back()
	var list := _effect_list_at(path)
	if last < 0:
		list.append(eff)
	elif last < list.size():
		list[last] = eff
	editing_effect_path = []
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _default_effect(effect_id: String) -> Dictionary:
	# Target selection starts EMPTY: the block shows a "+ 选择目标" placeholder
	# so the user actively picks (rather than silently inheriting a default
	# like "敌方单体"). force_self effects never show a target slot.
	var eff := {
		"target": "",
		"target_side": "",
		"effect": effect_id,
		"value": 1,
		"buff_id": "",
		"duration": 0,
		"random_count": 0,
		"probability": 100,
	}
	if SkillRegistry.force_self(effect_id):
		eff["target"] = SkillEngine.TARGET_SELF
		eff["target_side"] = SkillEngine.TARGET_SIDE_ALL
	if effect_id == SkillEngine.EFFECT_ADD_BUFF:
		eff["buff_id"] = SkillEngine.BUFF_ATK_BOOST
		eff["duration"] = 2
	return _TargetResolver.normalize_effect_target(eff)


func _default_if_else() -> Dictionary:
	return {
		"effect": SkillEngine.EFFECT_IF_ELSE,
		# Empty condition: Scratch-style, the user must drop a condition
		# reporter into the gap before the block is valid.
		"condition": {},
		"then_effects": [],
		"else_effects": [],
	}


func _default_if() -> Dictionary:
	return {
		"effect": SkillEngine.EFFECT_IF,
		"condition": {},
		"then_effects": [],
	}


func _add_if_else_block() -> void:
	effect_data.append(_default_if_else())
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _add_if_block() -> void:
	effect_data.append(_default_if())
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _add_stop_block() -> void:
	effect_data.append({"effect": SkillEngine.EFFECT_STOP})
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _default_repeat() -> Dictionary:
	return {
		"effect": SkillEngine.EFFECT_REPEAT,
		"repeat_count": 2,
		"then_effects": [],
	}


func _add_repeat_block() -> void:
	effect_data.append(_default_repeat())
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


# A condition reporter was dropped into an if block's condition gap: write it
# back as the nested "condition" dict (clearing any legacy direct fields).
# When the reporter came from another if gap (from_path set), clear that gap
# too — Scratch-style dragging moves the reporter instead of copying it.
func _on_block_condition_dropped(path: Array, cond: Dictionary, from_path: Array = []) -> void:
	if not from_path.is_empty():
		var src_eff := _effect_at(from_path)
		src_eff.erase("condition")
		src_eff.erase("condition_type")
		src_eff.erase("condition_op")
		src_eff.erase("condition_value")
		src_eff.erase("condition_buff_id")
	var eff := _effect_at(path)
	eff.erase("condition_type")
	eff.erase("condition_op")
	eff.erase("condition_value")
	eff.erase("condition_buff_id")
	eff["condition"] = cond.duplicate(true)
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


# Lightweight popup that edits an if/else block's condition fields.
func _open_if_condition_popup(path: Array):
	var s := _ui_scale()
	var popup := UITheme.make_popup_layer(self, 100)
	var layer: CanvasLayer = popup.get("layer")
	var size := Vector2(380, 300) * s
	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.custom_minimum_size = size
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -size.x / 2.0
	panel.offset_top = -size.y / 2.0
	panel.offset_right = size.x / 2.0
	panel.offset_bottom = size.y / 2.0
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(14 * s))
	margin.add_theme_constant_override("margin_top", int(10 * s))
	margin.add_theme_constant_override("margin_right", int(14 * s))
	margin.add_theme_constant_override("margin_bottom", int(10 * s))
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(6 * s))
	margin.add_child(vb)

	var title := Label.new()
	title.text = Locale.t("skill_editor.if_condition_title")
	title.add_theme_font_size_override("font_size", max(13, int(16 * s)))
	UITheme.apply_title(title, max(13, int(16 * s)))
	vb.add_child(title)

	var cond_label := Label.new()
	cond_label.text = Locale.t("skill_editor.condition")
	cond_label.add_theme_font_size_override("font_size", max(10, int(13 * s)))
	UITheme.apply_label(cond_label)
	vb.add_child(cond_label)
	var cond_sel := OptionButton.new()
	cond_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(SkillRegistry.CONDITION_IDS.size()):
		var key: String = SkillRegistry.CONDITION_IDS[i]
		var label := Locale.t("skill_editor.condition_none") if key == SkillEngine.CONDITION_NONE else Locale.term("condition", key)
		cond_sel.add_item(label, i)
	UITheme.apply_button(cond_sel, "secondary")
	vb.add_child(cond_sel)

	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", int(6 * s))
	var op_label := Label.new()
	op_label.text = Locale.t("skill_editor.condition_op")
	op_label.add_theme_font_size_override("font_size", max(10, int(13 * s)))
	UITheme.apply_label(op_label)
	detail_row.add_child(op_label)
	var cond_op_sel := OptionButton.new()
	for i in range(SkillRegistry.CONDITION_OP_IDS.size()):
		cond_op_sel.add_item(Locale.term("condition_op", SkillRegistry.CONDITION_OP_IDS[i]), i)
	UITheme.apply_button(cond_op_sel, "secondary")
	detail_row.add_child(cond_op_sel)
	var cond_value_spin := SpinBox.new()
	cond_value_spin.custom_minimum_size = Vector2(60 * s, 0)
	cond_value_spin.min_value = 0.0
	cond_value_spin.max_value = 100.0
	cond_value_spin.value = 1.0
	UITheme.apply_input(cond_value_spin)
	detail_row.add_child(cond_value_spin)
	detail_row.visible = false
	vb.add_child(detail_row)

	var buff_row := HBoxContainer.new()
	buff_row.add_theme_constant_override("separation", int(6 * s))
	var buff_label := Label.new()
	buff_label.text = Locale.t("skill_editor.condition_buff")
	buff_label.add_theme_font_size_override("font_size", max(10, int(13 * s)))
	UITheme.apply_label(buff_label)
	buff_row.add_child(buff_label)
	var cond_buff_sel := OptionButton.new()
	cond_buff_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(SkillRegistry.BUFF_IDS.size()):
		cond_buff_sel.add_item(Locale.term("buff", SkillRegistry.BUFF_IDS[i]), i)
	UITheme.apply_button(cond_buff_sel, "secondary")
	buff_row.add_child(cond_buff_sel)
	buff_row.visible = false
	vb.add_child(buff_row)

	# Backfill current condition (supports the nested "condition" reporter dict).
	var existing: Dictionary = SkillEngine._condition_dict(_effect_at(path))
	var cur_type: String = existing.get("condition_type", SkillEngine.CONDITION_NONE)
	cond_sel.selected = _idx_of(cur_type, SkillRegistry.CONDITION_IDS)
	cond_op_sel.selected = _idx_of(existing.get("condition_op", SkillEngine.CONDITION_OP_GTE), SkillRegistry.CONDITION_OP_IDS)
	cond_value_spin.value = float(existing.get("condition_value", 1))
	cond_buff_sel.selected = _idx_of(existing.get("condition_buff_id", SkillEngine.BUFF_ATK_BOOST), SkillRegistry.BUFF_IDS)
	var _sync_condition = func():
		var ctype: String = SkillRegistry.CONDITION_IDS[cond_sel.selected]
		var uses_buff: bool = ctype == SkillEngine.CONDITION_TARGET_HAS_BUFF
		detail_row.visible = ctype != SkillEngine.CONDITION_NONE and not uses_buff
		buff_row.visible = uses_buff
	_sync_condition.call()
	cond_sel.item_selected.connect(func(_i: int): _sync_condition.call())

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", int(16 * s))
	var ok_btn := Button.new()
	ok_btn.text = Locale.t("skill_editor.ok")
	ok_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(ok_btn, "primary")
	ok_btn.pressed.connect(func():
		var eff := _effect_at(path)
		eff.erase("condition")
		eff.erase("condition_type")
		eff.erase("condition_op")
		eff.erase("condition_value")
		eff.erase("condition_buff_id")
		var ctype: String = SkillRegistry.CONDITION_IDS[cond_sel.selected]
		if ctype != SkillEngine.CONDITION_NONE:
			eff["condition"] = {
				"condition_type": ctype,
			}
			if ctype == SkillEngine.CONDITION_TARGET_HAS_BUFF:
				eff["condition"]["condition_buff_id"] = SkillRegistry.BUFF_IDS[cond_buff_sel.selected]
			else:
				eff["condition"]["condition_op"] = SkillRegistry.CONDITION_OP_IDS[cond_op_sel.selected]
				eff["condition"]["condition_value"] = int(cond_value_spin.value)
		layer.queue_free()
		_refresh_script()
		_update_summary()
		_maybe_snapshot()
	)
	btns.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("skill_editor.cancel")
	cancel_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(func(): layer.queue_free())
	btns.add_child(cancel_btn)
	vb.add_child(btns)


func _idx_of(key: String, keys: Array) -> int:
	var i := keys.find(key)
	return i if i >= 0 else 0


# ============================================
# Skill settings row (probability / max uses / talent)
# ============================================

func _build_settings_row() -> void:
	var s := _ui_scale()

	# Settings live in a subtle inset card so the tuning fields read as one
	# group, distinct from the effect blocks below.
	var card := PanelContainer.new()
	var card_st := StyleBoxFlat.new()
	card_st.bg_color = Color(0.05, 0.06, 0.09, 0.55)
	card_st.border_color = Color(0.30, 0.36, 0.48, 0.40)
	card_st.set_border_width_all(1)
	card_st.set_corner_radius_all(6)
	card_st.content_margin_left = 8
	card_st.content_margin_top = 4
	card_st.content_margin_right = 8
	card_st.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", card_st)
	settings_row.add_child(card)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", int(4 * s))
	card.add_child(inner)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", int(10 * s))
	inner.add_child(row1)

	var prob_lbl := Label.new()
	prob_lbl.text = Locale.t("skill_editor.probability")
	prob_lbl.add_theme_font_size_override("font_size", max(10, int(13 * s)))
	UITheme.apply_label(prob_lbl)
	row1.add_child(prob_lbl)
	skill_prob_spin = SpinBox.new()
	skill_prob_spin.custom_minimum_size = Vector2(60 * s, 0)
	skill_prob_spin.min_value = 1.0
	skill_prob_spin.max_value = 100.0
	skill_prob_spin.value = 100.0
	UITheme.apply_input(skill_prob_spin)
	skill_prob_spin.value_changed.connect(func(_f: float):
		_update_summary()
		_maybe_snapshot()
	)
	row1.add_child(skill_prob_spin)

	var uses_lbl := Label.new()
	uses_lbl.text = Locale.t("skill_editor.max_uses")
	uses_lbl.add_theme_font_size_override("font_size", max(10, int(13 * s)))
	UITheme.apply_label(uses_lbl)
	row1.add_child(uses_lbl)
	max_uses_spin = SpinBox.new()
	max_uses_spin.custom_minimum_size = Vector2(60 * s, 0)
	max_uses_spin.min_value = 0.0
	max_uses_spin.max_value = 99.0
	max_uses_spin.value = 0.0
	UITheme.apply_input(max_uses_spin)
	max_uses_spin.value_changed.connect(func(_f: float):
		_update_summary()
		_maybe_snapshot()
	)
	row1.add_child(max_uses_spin)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", int(10 * s))
	inner.add_child(row2)
	skill_type_row = row2

	var type_lbl := Label.new()
	type_lbl.text = Locale.t("skill_editor.skill_type")
	type_lbl.add_theme_font_size_override("font_size", max(10, int(13 * s)))
	UITheme.apply_label(type_lbl)
	row2.add_child(type_lbl)
	skill_type_select = OptionButton.new()
	skill_type_select.add_item(Locale.t("skill_editor.skill_type_normal"))
	skill_type_select.add_item(Locale.t("skill_editor.skill_type_talent"))
	skill_type_select.selected = 0
	UITheme.apply_button(skill_type_select, "secondary")
	skill_type_select.item_selected.connect(func(_i: int):
		_update_summary()
		_maybe_snapshot()
	)
	row2.add_child(skill_type_select)


func _update_skill_type_visibility() -> void:
	if skill_type_select == null:
		return
	var show_talent: bool = not _is_spell() and SkillRegistry.trigger_is_passive(_selected_trigger_key())
	if skill_type_row != null:
		skill_type_row.visible = show_talent
	skill_type_select.visible = show_talent
	if not show_talent and skill_type_select.selected != 0:
		skill_type_select.selected = 0


# ============================================
# Trigger helpers
# ============================================

func _trigger_keys() -> Array:
	if _is_parasite():
		return [
			SkillEngine.TRIGGER_ON_ATTACK,
			SkillEngine.TRIGGER_ON_DAMAGED,
			SkillEngine.TRIGGER_ON_DEATH,
		]
	return [
		SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_ACTIVATE,
		SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_DAMAGED,
		SkillEngine.TRIGGER_ON_TURN_START, SkillEngine.TRIGGER_ON_TURN_END,
		SkillEngine.TRIGGER_ON_HEALED, SkillEngine.TRIGGER_ON_ATTACKED,
	]


func _selected_trigger_key() -> String:
	# Spell cards are locked to on_cast.
	if _is_spell():
		return SkillEngine.TRIGGER_ON_CAST
	return current_trigger_key


func _update_trigger_preview() -> void:
	if trigger_preview_label == null:
		return
	var trigger_key: String = _selected_trigger_key()
	trigger_preview_label.text = Locale.t("skill_editor.trigger_help.%s" % trigger_key)


# ============================================
# Build / Load / Summary
# ============================================

func _load_skill(skill: Dictionary):
	skill_name_input.text = skill.get("skill_name", "")
	if _is_spell():
		current_trigger_key = SkillEngine.TRIGGER_ON_CAST
	else:
		current_trigger_key = skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK)
	if skill_prob_spin:
		skill_prob_spin.value = float(skill.get("probability", 100))
	if max_uses_spin:
		max_uses_spin.value = float(skill.get("max_uses", 0))
	if skill_type_select:
		skill_type_select.selected = 0 if skill.get("skill_type", SkillEngine.SKILL_TYPE_NORMAL) != SkillEngine.SKILL_TYPE_TALENT else 1
	_update_skill_type_visibility()

	var effects: Array = SkillEngine.legacy_skill_effects(skill)
	var normalized_effects: Array = []
	for eff in effects:
		normalized_effects.append(_TargetResolver.normalize_effect_target(eff))
	effect_data = normalized_effects
	# Start a fresh undo history for this loaded skill.
	_reset_undo_history()
	_refresh_script()


func _build_skill() -> Dictionary:
	if effect_data.is_empty():
		return {}
	var is_spell := _is_spell()
	var trigger_key: String = _selected_trigger_key()
	var skill_type_val: String = SkillEngine.SKILL_TYPE_NORMAL
	# Talent only applies to passive skills (not on_activate, not spell).
	if not is_spell and SkillRegistry.trigger_is_passive(trigger_key) and skill_type_select and skill_type_select.selected == 1:
		skill_type_val = SkillEngine.SKILL_TYPE_TALENT
	return {
		"skill_name": PlayerData.card_draft.get("name", "") if is_spell else skill_name_input.text.strip_edges(),
		"trigger": trigger_key,
		"probability": int(skill_prob_spin.value) if skill_prob_spin else 100,
		"max_uses": int(max_uses_spin.value) if max_uses_spin else 0,
		"skill_type": skill_type_val,
		"effects": effect_data.duplicate(true),
	}


func _update_summary():
	var skill: Dictionary = _build_skill()
	skill_summary.text = _format_skill(skill)
	_refresh_error_banner()


func _format_skill(skill: Dictionary) -> String:
	var is_spell := _is_spell()
	var sp: int = skill.get("probability", 100)
	var max_uses: int = skill.get("max_uses", 0)
	var skill_type: String = skill.get("skill_type", SkillEngine.SKILL_TYPE_NORMAL)
	var effects: Array = skill.get("effects", [])
	var lines := ""
	if not is_spell:
		var sname: String = skill.get("skill_name", "?")
		if sname == "":
			sname = Locale.t("skill.no_name")
		var tname: String = Locale.term("trigger", skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK))
		lines = "[%s] %s\n" % [sname, tname]
		if skill_type == SkillEngine.SKILL_TYPE_TALENT:
			lines += "  %s " % Locale.t("skill.talent_badge")
	if sp < 100:
		lines += "  %s\n" % Locale.t("skill.chance", [sp])
	if max_uses > 0:
		lines += "  %s\n" % Locale.t("skill_editor.limited_uses", [max_uses])
	if effects.is_empty():
		lines += "  %s" % Locale.t("skill.no_effects")
	for i in range(effects.size()):
		var eff: Dictionary = effects[i]
		lines += "  %d. %s" % [i + 1, _TextFormatter.format_effect_sentence(eff)]
		if i < effects.size() - 1:
			lines += "\n"
	return lines.strip_edges()


# ============================================
# Ready / Save / Cancel
# ============================================

func _ready():
	# Long reporters widen their block; the script area scrolls horizontally
	# (bottom bar, like the existing vertical scroll) so every part of a wide
	# block stays reachable without auto-wrapping the sentence.
	var script_scroll: ScrollContainer = $Panel/Margin/HBox/MainPanel/Margin/Scroll
	script_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_apply_theme()
	_apply_texts()
	_build_settings_row()
	_build_palette()
	_build_undo_buttons()
	_build_skill_template_button()
	_connect_signals()
	_setup_drop_targets()

	var skill_index: int = PlayerData.editing_skill_index
	var skill_key: String = _skill_key_for_index(skill_index)
	if PlayerData.card_draft.has(skill_key) and not PlayerData.card_draft[skill_key].is_empty():
		_load_skill(PlayerData.card_draft[skill_key])
	# Always seed the undo baseline (also for an empty/untouched skill), so the
	# first edit is undoable and Ctrl+Z never returns a nil state.
	_reset_undo_history()

	_refresh_script()
	_update_summary()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _connect_signals():
	skill_name_input.text_changed.connect(func(_t: String): _update_summary())
	palette_search.text_changed.connect(_filter_palette)
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _build_skill_template_button() -> void:
	var row := save_button.get_parent() as HBoxContainer
	_template_btn = Button.new()
	_template_btn.text = Locale.t("skill_editor.templates")
	UITheme.apply_button(_template_btn, "secondary")
	_template_btn.pressed.connect(_show_skill_templates_popup)
	row.add_child(_template_btn)
	row.move_child(_template_btn, mini(2, row.get_child_count() - 1))


func _builtin_skill_templates() -> Array:
	return [
		{"name": Locale.t("skill_template.strike"), "skill": {
			"skill_name": Locale.t("skill_template.strike"), "trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
			"probability": 100, "max_uses": 0, "skill_type": SkillEngine.SKILL_TYPE_NORMAL,
			"effects": [_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 3})],
		}},
		{"name": Locale.t("skill_template.heal"), "skill": {
			"skill_name": Locale.t("skill_template.heal"), "trigger": SkillEngine.TRIGGER_ON_SUMMON,
			"probability": 100, "max_uses": 0, "skill_type": SkillEngine.SKILL_TYPE_NORMAL,
			"effects": [_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_ALL, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 2})],
		}},
		{"name": Locale.t("skill_template.guard"), "skill": {
			"skill_name": Locale.t("skill_template.guard"), "trigger": SkillEngine.TRIGGER_ON_SUMMON,
			"probability": 100, "max_uses": 0, "skill_type": SkillEngine.SKILL_TYPE_NORMAL,
			"effects": [
				_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_SHIELD, "value": 2}),
				_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_ADD_BUFF, "buff_id": SkillEngine.BUFF_TAUNT, "value": 1, "duration": 2}),
			],
		}},
		{"name": Locale.t("skill_template.draw"), "skill": {
			"skill_name": Locale.t("skill_template.draw"), "trigger": SkillEngine.TRIGGER_ON_TURN_START,
			"probability": 100, "max_uses": 0, "skill_type": SkillEngine.SKILL_TYPE_NORMAL,
			"effects": [_TargetResolver.normalize_effect_target({"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_DRAW_CARDS, "value": 1})],
		}},
	]


func _show_skill_templates_popup() -> void:
	var popup := UITheme.make_popup_layer(self, 105)
	var layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -260
	panel.offset_right = 260
	panel.offset_bottom = 260
	UITheme.apply_popup_frame(panel, "gold")
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("skill_editor.templates")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 20)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var templates := _builtin_skill_templates()
	for custom in PlayerData.custom_skill_templates:
		templates.append(custom)
	for entry in templates:
		var btn := Button.new()
		btn.text = str(entry.get("name", Locale.t("skill.no_name")))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UITheme.apply_button(btn, "secondary")
		var template_skill := (entry.get("skill", {}) as Dictionary).duplicate(true)
		btn.pressed.connect(_on_skill_template_chosen.bind(template_skill, layer))
		list.add_child(btn)
	var name_input := LineEdit.new()
	name_input.placeholder_text = Locale.t("skill_editor.template_name")
	UITheme.apply_input(name_input)
	box.add_child(name_input)
	var save_current := Button.new()
	save_current.text = Locale.t("skill_editor.favorite_current")
	UITheme.apply_button(save_current, "primary")
	save_current.pressed.connect(func():
		var skill := _build_skill()
		if PlayerData.save_custom_skill_template(name_input.text, skill):
			layer.queue_free()
	)
	box.add_child(save_current)
	var close := Button.new()
	close.text = Locale.t("common.back")
	UITheme.apply_button(close, "secondary")
	close.pressed.connect(layer.queue_free)
	box.add_child(close)


func _on_skill_template_chosen(skill: Dictionary, layer: CanvasLayer) -> void:
	_apply_skill_template(skill)
	layer.queue_free()


func _apply_skill_template(skill: Dictionary) -> void:
	if skill.is_empty():
		return
	current_trigger_key = SkillEngine.TRIGGER_ON_CAST if _is_spell() else str(skill.get("trigger", SkillEngine.TRIGGER_ON_ACTIVATE))
	skill_name_input.text = str(skill.get("skill_name", ""))
	effect_data = (skill.get("effects", []) as Array).duplicate(true)
	if skill_prob_spin:
		skill_prob_spin.value = int(skill.get("probability", 100))
	if max_uses_spin:
		max_uses_spin.value = int(skill.get("max_uses", 0))
	_update_trigger_preview()
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


# Undo / redo buttons sit at the left of the save/cancel row (Ctrl+Z / Ctrl+Y
# work too); they are disabled when their stack is empty.
func _build_undo_buttons() -> void:
	var row: HBoxContainer = save_button.get_parent()
	_undo_btn = Button.new()
	_undo_btn.text = Locale.t("skill_editor.undo")
	_undo_btn.add_theme_font_size_override("font_size", max(10, int(13 * _ui_scale())))
	UITheme.apply_button(_undo_btn, "secondary")
	_undo_btn.pressed.connect(_undo)
	row.add_child(_undo_btn)
	row.move_child(_undo_btn, 0)
	_redo_btn = Button.new()
	_redo_btn.text = Locale.t("skill_editor.redo")
	_redo_btn.add_theme_font_size_override("font_size", max(10, int(13 * _ui_scale())))
	UITheme.apply_button(_redo_btn, "secondary")
	_redo_btn.pressed.connect(_redo)
	row.add_child(_redo_btn)
	row.move_child(_redo_btn, 1)
	_refresh_undo_buttons()


func _skill_key_for_index(index: int) -> String:
	match index:
		0:
			return "skill1"
		1:
			return "skill2"
	return "skill3"


func _on_save_pressed():
	var errors: Array = _collect_errors()
	# An untouched/empty skill is a valid "no skill" state (saved as {}); only
	# real compile errors must block the save, otherwise the invalid skill
	# would be written into the card JSON.
	var empty_only: bool = errors.size() == 1 and str(errors[0]) == Locale.t("skill_editor.error_empty_skill")
	if not errors.is_empty() and not empty_only:
		_show_save_blocked_popup(errors)
		return
	var skill: Dictionary = _build_skill()
	var skill_key: String = _skill_key_for_index(PlayerData.editing_skill_index)
	PlayerData.card_draft[skill_key] = skill
	PlayerData.save_card_draft_recovery()
	print("Skill saved: %s" % skill.get("skill_name", ""))
	UIMotion.change_scene("res://CardEditor.tscn")


# A compile-error skill must not reach the card draft (which is later written
# to card_library.json): show what's wrong and refuse to leave the editor.
func _show_save_blocked_popup(errors: Array) -> void:
	var s := _ui_scale()
	var popup := UITheme.make_popup_layer(self, 100)
	var layer: CanvasLayer = popup.get("layer")
	var size := Vector2(420, 300) * s
	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.custom_minimum_size = size
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -size.x / 2.0
	panel.offset_top = -size.y / 2.0
	panel.offset_right = size.x / 2.0
	panel.offset_bottom = size.y / 2.0
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(14 * s))
	margin.add_theme_constant_override("margin_top", int(10 * s))
	margin.add_theme_constant_override("margin_right", int(14 * s))
	margin.add_theme_constant_override("margin_bottom", int(10 * s))
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(6 * s))
	margin.add_child(vb)

	var title := Label.new()
	title.text = Locale.t("skill_editor.save_blocked_title")
	title.add_theme_font_size_override("font_size", max(13, int(16 * s)))
	UITheme.apply_title(title, max(13, int(16 * s)))
	title.add_theme_color_override("font_color", Color(1, 0.70, 0.70))
	vb.add_child(title)

	var body := Label.new()
	body.text = Locale.t("skill_editor.save_blocked_body")
	body.add_theme_font_size_override("font_size", max(10, int(13 * s)))
	UITheme.apply_label(body)
	vb.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var err_box := VBoxContainer.new()
	err_box.add_theme_constant_override("separation", int(4 * s))
	err_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(err_box)
	for e in errors:
		var lbl := Label.new()
		lbl.text = "- " + str(e)
		lbl.add_theme_font_size_override("font_size", max(10, int(12 * s)))
		lbl.add_theme_color_override("font_color", Color(1, 0.82, 0.82))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err_box.add_child(lbl)

	var close_btn := Button.new()
	close_btn.text = Locale.t("skill_editor.save_blocked_close")
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
	)
	vb.add_child(close_btn)


func _on_cancel_pressed():
	UIMotion.change_scene("res://CardEditor.tscn")
