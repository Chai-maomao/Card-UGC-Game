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
const _TutorialController = preload("res://SkillEditorTutorialController.gd")
const _UgcSafety = preload("res://UgcSafety.gd")

@onready var title_label = $Panel/Margin/HBox/MainPanel/Margin/TitleLabel
@onready var help_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/HelpLabel
@onready var skill_name_input = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/SkillNameInput
@onready var skill_name_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/SkillNameLabel
@onready var trigger_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/TriggerLabel
@onready var trigger_preview_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/TriggerPreviewLabel
@onready var trigger_side_row = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/TriggerSideRow
@onready var trigger_side_label = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/TriggerSideRow/Label
@onready var trigger_side_select = $Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/TriggerSideRow/Option
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

var _opening_editor_state: Dictionary = {}
var _opening_skill_name := ""
var _discard_dialog: ConfirmationDialog
var effect_data: Array = []        # [{target, effect, value, buff_id, duration, ...}, ...]
var editing_effect_path: Array = [] # [] = none; last element -1 = append to the list at path
var current_trigger_key: String = SkillEngine.TRIGGER_ON_ATTACK
var current_trigger_side: String = SkillEngine.TARGET_SIDE_ALL
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
var skill_tutorial_controller: SkillEditorTutorialController
var _drag_in_progress: bool = false
var _pointer_down: bool = false
var _script_refresh_pending: bool = false
var _palette_drop_overlay: Control
var workbench: RefCounted
var loose_groups: Dictionary = {}
var loose_reporters: Dictionary = {}
var workspace_script_position := Vector2.ZERO
var validation_requested := false
var _drag_hidden: Array[WeakRef] = []


# ============================================
# Undo / redo (delegated to SkillUndoManager)
# ============================================

func _editor_state() -> Dictionary:
	# Full editing state (trigger + effects + skill metadata) so undo/redo
	# restore settings-level edits too, not just the block list.
	return {
		"trigger": current_trigger_key,
		"trigger_side": current_trigger_side,
		"effects": effect_data.duplicate(true),
		"loose_groups": loose_groups.duplicate(true),
		"loose_reporters": loose_reporters.duplicate(true),
		"workspace_position": [workspace_script_position.x, workspace_script_position.y],
		"probability": int(skill_prob_spin.value) if skill_prob_spin != null else 100,
		"max_uses": int(max_uses_spin.value) if max_uses_spin != null else 0,
		"skill_type": int(skill_type_select.selected) if skill_type_select != null else 0,
	}


func _apply_state(s: Dictionary) -> void:
	current_trigger_key = str(s.get("trigger", current_trigger_key))
	current_trigger_side = str(s.get("trigger_side", current_trigger_side))
	effect_data = (s.get("effects", []) as Array).duplicate(true)
	loose_groups = (s.get("loose_groups", {}) as Dictionary).duplicate(true)
	loose_reporters = (s.get("loose_reporters", {}) as Dictionary).duplicate(true)
	var point: Array = s.get("workspace_position", [0, 0])
	workspace_script_position = Vector2(float(point[0]), float(point[1]))
	if skill_prob_spin != null:
		skill_prob_spin.set_value_no_signal(float(s.get("probability", 100)))
	if max_uses_spin != null:
		max_uses_spin.set_value_no_signal(float(s.get("max_uses", 0)))
	if skill_type_select != null:
		skill_type_select.select(int(s.get("skill_type", 0)))
	_sync_trigger_side_select()
	_update_trigger_preview()
	_update_skill_type_visibility()
	if _is_talent_mode():
		_build_palette()
	_refresh_script()
	_update_summary()
	_refresh_undo_buttons()


func _maybe_snapshot() -> void:
	_undo_mgr.maybe_snapshot(_editor_state())
	_refresh_undo_buttons()
	if workbench != null:
		workbench.invalidate_preview()


func _undo() -> void:
	if not _undo_mgr.can_undo():
		UITheme.reject_button(_undo_btn)
		return
	var undid: Variant = _undo_mgr.undo(_editor_state())
	_apply_state(undid)


func _redo() -> void:
	if not _undo_mgr.can_redo():
		UITheme.reject_button(_redo_btn)
		return
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
	# Escape is also an emergency way out of an interrupted GUI drag. This is
	# intentionally handled before the Ctrl shortcut filter below.
	if key_ev.keycode == Key.KEY_ESCAPE and _is_editor_drag_active():
		_recover_pointer_after_drag()
		accept_event()
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


func _is_talent_mode() -> bool:
	return PlayerData.editing_skill_index == 3 and not _is_spell() and not _is_parasite()


func _apply_texts() -> void:
	var skill_index: int = PlayerData.editing_skill_index
	var is_spell := _is_spell()
	title_label.text = Locale.t("skill_editor.title_spell") if is_spell else (Locale.t("skill_editor.title_talent") if _is_talent_mode() else Locale.t("skill_editor.title", [skill_index + 1]))
	help_label.text = Locale.t("skill_editor.help_spell" if is_spell else ("skill_editor.help_talent" if _is_talent_mode() else "skill_editor.help"))
	help_label.hide()
	palette_title.text = Locale.t("skill_editor.palette_title")
	palette_search.placeholder_text = Locale.t("skill_editor.palette_search")
	effects_label.text = Locale.t("skill_editor.effects" if not is_spell else "skill_editor.spell_effects")
	effects_hint_label.text = Locale.t("skill_editor.effects_hint" if not is_spell else "skill_editor.effects_hint_spell")
	effects_hint_label.hide()
	settings_label.text = Locale.t("skill_editor.settings")
	preview_label.text = Locale.t("skill_editor.preview" if not is_spell else "skill_editor.spell_preview")
	save_button.text = Locale.t("skill_editor.save")
	cancel_button.text = Locale.t("common.back")

	# Spell skills have no name / trigger — hide those rows.
	skill_name_label.visible = not is_spell
	skill_name_input.visible = not is_spell
	trigger_label.visible = not is_spell
	trigger_preview_label.visible = not is_spell
	trigger_side_label.text = Locale.t("skill_editor.trigger_side")
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
	if workbench != null:
		workbench.layout()
		return
	var s := _ui_scale()
	var panel := $Panel
	panel.custom_minimum_size = Vector2.ZERO
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = -540.0 * s
	panel.anchor_top = 0
	panel.anchor_bottom = 1
	panel.offset_top = 80
	panel.offset_right = 540.0 * s
	panel.offset_bottom = -24
	UITheme.place_page_back(self, cancel_button)
	var inset := maxf(16.0,20.0*s)
	var main_content: Control = $Panel/Margin/HBox/MainPanel/Margin
	main_content.offset_left = inset
	main_content.offset_top = inset
	main_content.offset_right = -inset
	main_content.offset_bottom = -inset
	main_content.add_theme_constant_override("separation",maxi(10,roundi(8*s)))
	for side in ["left","right","top","bottom"]:
		$Panel/Margin.add_theme_constant_override("margin_"+side,maxi(12,roundi(14*s)))
		$Panel/Margin/HBox/PalettePanel/Margin.add_theme_constant_override("margin_"+side,maxi(12,roundi(12*s)))
	$Panel/Margin/HBox.add_theme_constant_override("separation",maxi(12,roundi(10*s)))
	$Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox.add_theme_constant_override("separation",maxi(10,roundi(8*s)))
	$Panel/Margin/HBox/PalettePanel.custom_minimum_size = Vector2(250 * s, 0)
	for label in [title_label, help_label, skill_name_label, trigger_label, trigger_preview_label, trigger_side_label,
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
	UITheme.apply_app_background($Panel)
	# Internal sections use spacing and rules; only the page has a frame.
	for inner_panel in [$Panel/Margin/HBox/PalettePanel,$Panel/Margin/HBox/MainPanel,preview_panel]:
		inner_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var scroll_inset := StyleBoxEmpty.new()
	scroll_inset.content_margin_right = 12
	$Panel/Margin/HBox/MainPanel/Margin/Scroll.add_theme_stylebox_override("panel",scroll_inset)
	for side in ["left","right"]:
		$Panel/Margin/HBox/MainPanel/Margin/PreviewPanel/Margin.add_theme_constant_override("margin_"+side,0)
	$Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/SeparatorMid.visible = not _is_spell()
	UITheme.apply_title(title_label, max(14, int(18 * _ui_scale())))
	UITheme.apply_title(palette_title, max(13, int(15 * _ui_scale())))
	UITheme.apply_input(palette_search)
	UITheme.apply_input(skill_name_input)
	UITheme.apply_button(save_button, "primary")
	UITheme.apply_button(cancel_button, "secondary")
	for soft_label in [help_label, trigger_preview_label, skill_summary]:
		UITheme.apply_label(soft_label, true)
	for label in [skill_name_label, trigger_label, trigger_side_label, settings_label, effects_label, effects_hint_label, preview_label]:
		UITheme.apply_label(label)
	UITheme.apply_button(trigger_side_select, "secondary")
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
	if workbench != null:
		workbench.refresh_categories()


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
	if workbench != null: workbench._sync_category.call_deferred()


func _select_trigger(trigger_key: String) -> void:
	if skill_tutorial_controller and not skill_tutorial_controller.allows("trigger", {"id": trigger_key}):
		return
	current_trigger_key = trigger_key
	_update_trigger_side_visibility()
	_update_trigger_preview()
	_update_skill_type_visibility()
	if _is_talent_mode():
		_build_palette()
	_refresh_script()
	_update_summary()
	_maybe_snapshot()
	if skill_tutorial_controller:
		skill_tutorial_controller.notify_action("trigger", {"id": trigger_key})


func _add_effect_block(effect_id: String, buff_id: String = "") -> void:
	if skill_tutorial_controller and not skill_tutorial_controller.allows("effect", {"id": effect_id}):
		return
	effect_data.append(_default_effect(effect_id, buff_id))
	_refresh_script()
	_update_summary()
	_maybe_snapshot()
	if skill_tutorial_controller:
		skill_tutorial_controller.notify_action("effect", {"id": effect_id})


# ============================================
# Script area (hat + effect blocks)
# ============================================

func _refresh_script() -> void:
	# Dropping a block mutates the data while Godot is still finishing the GUI
	# drag callback. Rebuilding here would queue the drag source and target for
	# deletion before the engine has released its Windows mouse capture. Defer
	# the rebuild until the input callback unwinds and DRAG_END can finish.
	if is_inside_tree() and get_viewport() != null and get_viewport().gui_is_dragging():
		_queue_script_refresh_after_drag()
		return
	_refresh_script_now()


func _queue_script_refresh_after_drag() -> void:
	if _script_refresh_pending or not is_inside_tree():
		return
	_script_refresh_pending = true
	_flush_script_refresh_after_drag.call_deferred()


func _flush_script_refresh_after_drag() -> void:
	_script_refresh_pending = false
	if not is_inside_tree():
		return
	# A lost release event must not keep the editor waiting forever. The data
	# mutation already completed, so cancelling a still-active drag is safe.
	if get_viewport() != null and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	_drag_in_progress = false
	_restore_pointer_visibility()
	_refresh_script_now()


func _refresh_script_now() -> void:
	_cleanup_loose_reporters()
	for child in effects_list.get_children():
		child.queue_free()
	if _is_spell():
		# Spells are locked to on_cast and have no visible event block.
		_render_effects(effect_data, effects_list, [], false)
		_maybe_add_slot_hint(effects_list)
	else:
		# The whole skill lives inside one event hat block (Scratch-style).
		var event_block := SkillBlock.new()
		event_block.setup_event_block(current_trigger_key, current_trigger_side)
		if workbench != null:
			event_block.set_meta("skill_workspace",workbench.workspace)
			event_block.mouse_default_cursor_shape = Control.CURSOR_DRAG
		effects_list.add_child(event_block)
		_render_effects(effect_data, event_block.body_container, [], true)
		_maybe_add_slot_hint(event_block.body_container)
		_setup_slot_drop(event_block.body_container, [])
	_refresh_error_banner()
	_mark_invalid_conditions()
	if workbench != null:
		workbench.render_loose_groups()


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
	_mark_invalid_conditions()

func _exit_tree() -> void:
	if is_instance_valid(_insertion_line) and _insertion_line.get_parent() == null:
		_insertion_line.free()


func _mark_invalid_conditions() -> void:
	_error_checker.editor = self
	_error_checker.mark_invalid_conditions()


func _focus_issue_path(path: Array, condition_path: Variant = null) -> void:
	if path.is_empty():
		return
	for candidate in effects_list.find_children("*", "SkillBlock", true, false):
		var block := candidate as SkillBlock
		if block != null and block.effect_path == path:
			var target: Control = block
			if condition_path is Array:
				for socket in block.find_children("*", "PanelContainer", true, false):
					if socket.get_script() == preload("res://SkillConditionSocket.gd") and socket.condition_path == condition_path:
						target = socket
						break
			if workbench != null:
				var canvas: Control = workbench.workspace
				if block.get_global_rect().size.x+64 <= canvas.size.x and block.get_global_rect().size.y+80 <= canvas.size.y:
					canvas.reveal(block)
				else:
					canvas.pan += canvas.get_global_rect().get_center()-target.get_global_rect().get_center()
					canvas._sync_view()
			else:
				var scroll := $Panel/Margin/HBox/MainPanel/Margin/Scroll as ScrollContainer
				scroll.ensure_control_visible(block)
			UITheme.reject_shake(target)
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
			if SkillRegistry.is_chance_block(eff):
				block.setup_chance_block(eff, path)
			else:
				block.setup_if_else(eff, path)
			block.draggable = true
			_connect_block_signals(block)
			container.add_child(block)
			if top_level:
				block.set_order(i + 1)
			var then_path: Array = path.duplicate()
			then_path.append("then")
			_render_effects(eff.get("then_effects", []), block.then_container, then_path, false)
			_setup_slot_drop(block.then_container, then_path)
			if block.has_else:
				var else_path: Array = path.duplicate()
				else_path.append("else")
				_render_effects(eff.get("else_effects", []), block.else_container, else_path, false)
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
	slot.custom_minimum_size.y = 36


func _connect_block_signals(block: SkillBlock) -> void:
	if workbench != null: block.set_meta("skill_workspace",workbench.workspace)
	block.edit_requested.connect(_on_block_edit_path)
	block.delete_requested.connect(_on_block_delete_path)
	block.move_requested.connect(_on_block_move_path)
	block.drop_requested.connect(_on_block_drop_path)
	block.changed.connect(_on_block_changed)
	block.context_requested.connect(_on_block_context_requested)
	block.condition_dropped.connect(_on_block_condition_dropped)
	block.condition_inserted.connect(_on_block_condition_inserted)
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
	# A temporary overlay is raised during a drag so headers, search controls,
	# scrollbars and palette buttons cannot punch holes in the discard zone.
	var palette_panel: Panel = $Panel/Margin/HBox/PalettePanel
	palette_panel.set_drag_forwarding(
		Callable(self, "_get_drag_data_from_list"),
		Callable(self, "_can_drop_on_palette"),
		Callable(self, "_drop_on_palette"),
	)
	_palette_drop_overlay = Control.new()
	_palette_drop_overlay.name = "PaletteDropOverlay"
	_palette_drop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_palette_drop_overlay.z_index = 100
	palette_panel.add_child(_palette_drop_overlay)
	_palette_drop_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_palette_drop_overlay.set_drag_forwarding(
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
var _stack_snap: RefCounted
var _trigger_snap_target: SkillBlock
var _highlighted_slot: VBoxContainer
var _slot_orig_style: StyleBox
var _palette_discard_highlight: bool = false
var _palette_orig_z_index := 0
var _palette_orig_style: StyleBox


func _can_drop_on_slot(vbox: VBoxContainer, _pos: Vector2, data) -> bool:
	if workbench != null:
		return _preview_stack_drop(data)
	_pos = _slot_pointer(vbox, _pos)
	var ok: bool = data is Dictionary and data.get("type", "") == "effect_block"
	if ok:
		_activate_slot_highlight(vbox)
		_show_insertion_line(vbox, _insertion_index_at(vbox, _pos))
	else:
		_hide_insertion_line()
	return ok


func _preview_stack_drop(data: Variant) -> bool:
	if _stack_snap == null: _stack_snap = preload("res://SkillStackSnap.gd").new(self)
	return _stack_snap.preview(data)

func _commit_stack_drop(data: Dictionary) -> bool:
	if _stack_snap == null: _stack_snap = preload("res://SkillStackSnap.gd").new(self)
	return _stack_snap.commit(data)

func _preview_trigger_attachment() -> SkillBlock:
	var canvas: Control = workbench.workspace
	var best: SkillBlock
	var best_distance := INF
	if effect_data.is_empty() and Rect2(Vector2.ZERO, canvas.size).has_point(canvas.last_pointer):
		var anchor := _trigger_body_anchor()
		for group in canvas.loose_views:
			if group.get_child_count() == 0: continue
			var first := group.get_child(0) as SkillBlock
			if first == null or not first.is_visible_in_tree(): continue
			var delta := first.get_global_rect().position - anchor
			if absf(delta.x) > 40.0 or absf(delta.y) > 24.0: continue
			var distance := delta.length_squared()
			if distance < best_distance:
				best = first
				best_distance = distance
	if _trigger_snap_target != best:
		_clear_trigger_attachment()
		_trigger_snap_target = best
		if best != null: best._set_drag_highlight(true)
	return best

func _trigger_body_anchor() -> Vector2:
	var body: Control = effects_list if _is_spell() else effects_list.get_child(0).body_container
	return body.get_global_rect().position

func _clear_trigger_attachment() -> void:
	if is_instance_valid(_trigger_snap_target):
		_trigger_snap_target._set_drag_highlight(false)
	_trigger_snap_target = null

func _finish_trigger_drag(at: Vector2, allow_attachment: bool) -> void:
	workspace_script_position = at
	var target := _preview_trigger_attachment() if allow_attachment else null
	_clear_trigger_attachment()
	if target != null:
		var world: Control = workbench.workspace.world
		var inverse := world.get_global_transform().affine_inverse()
		workspace_script_position += (inverse * target.global_position) - (inverse * _trigger_body_anchor())
		var path: Array = target.effect_path
		_move_effect(path, [], 0, true)
		_show_connection_feedback.call_deferred([0])
	else:
		_maybe_snapshot()

func _show_connection_feedback(path: Array, condition_socket: Variant = null) -> void:
	for candidate in workbench.workspace.world.find_children("*", "SkillBlock", true, false):
		var ancestor: Node = candidate
		var retiring := false
		while ancestor != workbench.workspace.world:
			if ancestor.is_queued_for_deletion(): retiring = true
			ancestor = ancestor.get_parent()
		if retiring: continue
		if not candidate.get_meta("drag_preview", false) and candidate.effect_path == path:
			if condition_socket is Array:
				if not is_instance_valid(candidate.cond_slot):
					return
				if condition_socket.is_empty():
					candidate.cond_slot.flash_attachment()
				else:
					for socket in candidate.cond_slot.find_children("*", "PanelContainer", true, false):
						if socket.get_script() == preload("res://SkillConditionSocket.gd") and socket.condition_path == condition_socket:
							socket.flash_attachment()
							break
				return
			candidate._set_drag_highlight(true)
			candidate._play_drop_pulse()
			var reference: WeakRef = weakref(candidate)
			get_tree().create_timer(0.38).timeout.connect(func():
				var block = reference.get_ref()
				if block != null: block._set_drag_highlight(false))
			break


func _activate_slot_highlight(vbox: VBoxContainer) -> void:
	if _highlighted_slot == vbox:
		return
	if _highlighted_slot != null:
		_highlight_slot(_highlighted_slot, false)
	_highlight_slot(vbox, true)
	_highlighted_slot = vbox


func _show_insertion_line(vbox: VBoxContainer, index: int) -> void:
	if _insertion_line != null and _insertion_line.get_parent() == vbox and _insertion_line.get_meta("index", -1) == index:
		return
	if _insertion_line == null:
		_insertion_line = PanelContainer.new()
		_insertion_line.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_insertion_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var data = get_viewport().gui_get_drag_data()
		var effect: Dictionary = {}
		if data is Dictionary:
			effect = data.get("effect", {})
			if effect.is_empty(): effect = _new_block_for(str(data.get("effect_id", SkillEngine.EFFECT_DAMAGE)), str(data.get("buff_id", "")))
		if effect.is_empty(): effect = _new_block_for(SkillEngine.EFFECT_DAMAGE)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", -preload("res://SkillSocketStyle.gd").JOIN_OVERLAP)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_insertion_line.add_child(column)
		var effects: Array = [effect]
		if data is Dictionary and data.get("tail", false) and not data.get("from_path", []).is_empty():
			var path: Array = data.from_path
			effects = _effect_list_at(path).slice(int(path.back()))
		for item in effects:
			var ghost := SkillBlock.make_preview(item)
			ghost.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			ghost.modulate = Color(1,1,1,0.62)
			ghost._set_drag_highlight(true)
			column.add_child(ghost)
	_insertion_line.set_meta("index", index)
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
	for child in vbox.get_children():
		if child is Label: child.visible = not on

func _hide_insertion_line() -> void:
	if _highlighted_slot != null:
		_highlight_slot(_highlighted_slot, false)
		_highlighted_slot = null
	if _insertion_line != null and _insertion_line.get_parent() != null:
		_insertion_line.get_parent().remove_child(_insertion_line)
	if _insertion_line != null:
		_insertion_line.queue_free()
		_insertion_line = null


func _process(_delta: float) -> void:
	if workbench != null and get_viewport().gui_is_dragging():
		_preview_stack_drop(get_viewport().gui_get_drag_data())
	# Track the editor viewport's press/release events. Forwarded editor input
	# does not necessarily update Input's OS-level mouse-button state.
	if _is_editor_drag_active() and not _pointer_down:
		_recover_pointer_after_drag()
	elif Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_restore_pointer_visibility()
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


func _input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		_pointer_down = mouse_button.pressed
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT \
			and not mouse_button.pressed and _drag_in_progress:
		# Run after the viewport has had a chance to perform the normal drop. If
		# it failed to end the drag, gui_cancel_drag() releases the capture.
		_recover_pointer_after_drag.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_drag_in_progress = true
		_set_palette_drop_overlay_active(true)
	elif what == NOTIFICATION_DRAG_END:
		if _stack_snap != null: _stack_snap.clear()
		_hide_insertion_line()
		_restore_drag_views()
		_drag_in_progress = false
		_set_palette_drop_overlay_active(false)
		_restore_pointer_visibility.call_deferred()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Cancelling a GUI drag removes its preview. The focus notification can
		# arrive while Godot is still changing the window's children.
		_recover_pointer_after_drag.call_deferred()


func _is_editor_drag_active() -> bool:
	return _drag_in_progress or (get_viewport() != null and get_viewport().gui_is_dragging())


func _recover_pointer_after_drag() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport != null and viewport.gui_is_dragging():
		viewport.gui_cancel_drag()
	_drag_in_progress = false
	_restore_drag_views()
	_pointer_down = false
	_set_palette_drop_overlay_active(false)
	_hide_insertion_line()
	_set_palette_discard_highlight(false)
	_restore_pointer_visibility()


func _set_palette_drop_overlay_active(active: bool) -> void:
	if _palette_drop_overlay != null and is_instance_valid(_palette_drop_overlay):
		_palette_drop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE


func _restore_pointer_visibility() -> void:
	# Re-applying VISIBLE also asks the Windows display backend to release any
	# stale capture/confine state left by an interrupted drag.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


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
		_palette_orig_z_index = panel.z_index
		panel.z_index = maxi(1,panel.z_index)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(UITheme.Tokens.DANGER_PRESSED,0.97)
		st.border_color = Color(UITheme.Tokens.ENEMY,0.98)
		st.set_border_width_all(2)
		st.set_corner_radius_all(8)
		st.shadow_color = Color(UITheme.Tokens.ENEMY,0.4)
		st.shadow_size = 8
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 10
		st.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", st)
	elif _palette_orig_style != null:
		panel.add_theme_stylebox_override("panel", _palette_orig_style)
		panel.z_index = _palette_orig_z_index


func _drop_on_palette(_pos: Vector2, data) -> void:
	_set_palette_discard_highlight(false)
	var t: String = str(data.get("type", ""))
	if t == "effect_block":
		var from_path: Array = data.get("from_path", [])
		if from_path.size() > 0:
			if data.get("tail",false):
				var list := _effect_list_at(from_path)
				list.resize(int(from_path.back()))
				_cleanup_loose_groups()
				_refresh_script()
				_update_summary()
				_maybe_snapshot()
			else: _on_block_delete_path(from_path)
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
			var root := SkillEngine._condition_dict(eff)
			_write_condition(eff, _replace_condition_at(root, data.get("from_condition_path", []), {}))
			_cleanup_loose_reporters()
			_refresh_script()
			_update_summary()
			_maybe_snapshot()


func _drop_on_slot(vbox: VBoxContainer, pos: Vector2, data) -> void:
	if workbench != null:
		_commit_stack_drop(data)
		return
	pos = _slot_pointer(vbox, pos)
	_hide_insertion_line()
	var list_path: Array = vbox.get_meta("list_path", [])
	var index := _insertion_index_at(vbox, pos)
	_apply_drop(data, list_path, index)

func _slot_pointer(control: Control, fallback: Vector2) -> Vector2:
	if workbench == null: return fallback
	# Forwarded input can leave a drop callback using the OS cursor location.
	# Convert the pointer observed by this viewport into the target's coordinates.
	var workspace: Control = workbench.workspace
	return control.get_global_transform().affine_inverse() * (workspace.get_global_transform() * workspace.last_pointer)


# Computes the insertion index under the mouse by comparing against each
# stacked block's vertical center (ignoring "+ 添加效果" buttons).
func _insertion_index_at(vbox: VBoxContainer, pos: Vector2) -> int:
	var block_idx := 0
	for child in vbox.get_children():
		if child is SkillBlock:
			if child.visible and pos.y < child.position.y + child.size.y * 0.5:
				return block_idx
			block_idx += 1
	return block_idx


# Unified drop handler: palette drop (insert new block) or script-internal
# move (remove from source, insert at target), with cycle protection.
func _apply_drop(data, list_path: Array, index: int) -> void:
	var from_path: Array = data.get("from_path", [])
	if from_path.size() > 0:
		_move_effect(from_path, list_path, index, bool(data.get("tail",false)))
	else:
		var effect_id: String = str(data.get("effect_id", ""))
		if effect_id == "":
			return
		var list := _list_at(list_path)
		var eff := _new_block_for(effect_id, str(data.get("buff_id", "")))
		list.insert(clamp(index, 0, list.size()), eff)
		_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _move_effect(from_path: Array, list_path: Array, index: int, move_tail: bool = false) -> void:
	# Reject moving a block into its own subtree (would create a cycle).
	if _is_path_prefix(from_path, list_path):
		return
	var from_parent: Array = from_path.slice(0, from_path.size() - 1)
	var from_idx: int = from_path[from_path.size() - 1]
	var src_list := _list_at(from_parent)
	if from_idx < 0 or from_idx >= src_list.size():
		return
	var count := src_list.size()-from_idx if move_tail else 1
	for i in range(from_idx,from_idx+count):
		if _is_path_prefix(from_parent+[i],list_path): return
	var dst_list := _list_at(list_path)
	var moved: Array = src_list.slice(from_idx,from_idx+count)
	for i in range(count): src_list.remove_at(from_idx)
	# When reordering within the same list, shifting left affects the index.
	if from_parent == list_path and from_idx < index:
		index -= count
	index = clampi(index,0,dst_list.size())
	for i in range(moved.size()): dst_list.insert(index+i,moved[i])
	_cleanup_loose_groups()
	_refresh_script()
	_update_summary()
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
	var root: Array = effect_data
	if not list_path.is_empty() and list_path[0] is String and list_path[0] == "loose":
		root = loose_groups[str(list_path[1])]["effects"]
		list_path = list_path.slice(2)
	if list_path.is_empty():
		return root
	var eff: Dictionary = root[list_path[0]]
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
	if path.size() == 2 and path[0] == "reporter": return loose_reporters[str(path[1])].value
	if path.size() == 1:
		return effect_data[path[0]]
	var list := _effect_list_at(path)
	return list[path[path.size() - 1]]


func _cleanup_loose_groups() -> void:
	for key in loose_groups.keys():
		if loose_groups[key]["effects"].is_empty(): loose_groups.erase(key)

func hide_drag_tail(block: SkillBlock) -> void:
	if _stack_snap != null: _stack_snap.clear()
	_restore_drag_views()
	var following := false
	for sibling in block.get_parent().get_children():
		if sibling == block: following = true
		if following and sibling is SkillBlock:
			_drag_hidden.append(weakref(sibling))
			sibling.hide()
	_hide_insertion_line()

func _restore_drag_views() -> void:
	for reference in _drag_hidden:
		var view = reference.get_ref()
		if view != null and not view.is_queued_for_deletion(): view.show()
	_drag_hidden.clear()


func _drop_on_workspace(local_point: Vector2, data: Dictionary) -> void:
	if data.get("type", "") != "effect_block":
		_drop_reporter_on_workspace(local_point, data)
		return
	if _commit_stack_drop(data): return
	_hide_insertion_line()
	var point: Vector2 = workbench.workspace.to_world(local_point)
	var grab: Array = data.get("grab_offset", [12, 12])
	point -= Vector2(float(grab[0]),float(grab[1]))
	var from: Array = data.get("from_path", [])
	# Move a free group without replacing its effect data or executable order.
	# A dragged child carries the remaining siblings below it.
	if from.size() == 3 and from[0] is String and from[0] == "loose" and int(from.back()) == 0 and (bool(data.get("tail",false)) or _effect_list_at(from).size() == 1):
		loose_groups[str(from[1])]["position"] = [point.x,point.y]
	else:
		var moved: Array = []
		if not from.is_empty():
			var source := _effect_list_at(from)
			var index: int = from.back()
			if index < 0 or index >= source.size(): return
			var count := source.size()-index if bool(data.get("tail",false)) else 1
			moved = source.slice(index,index+count)
			for i in range(count): source.remove_at(index)
		else:
			var id := str(data.get("effect_id", ""))
			if id.is_empty(): return
			moved = [_new_block_for(id, str(data.get("buff_id", "")))]
		var key := "g%d" % Time.get_ticks_usec()
		loose_groups[key] = {"position":[point.x,point.y], "effects":moved}
	_cleanup_loose_groups()
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _restore_workspace(raw: Variant) -> void:
	loose_groups.clear()
	loose_reporters.clear()
	workspace_script_position = Vector2.ZERO
	if not raw is Dictionary: return
	var units := 100.0 if raw.get("version",0) == 1 else 1.0
	var pos: Variant = raw.get("position", [0,0])
	if pos is Array and pos.size() == 2 and (pos[0] is float or pos[0] is int) and (pos[1] is float or pos[1] is int):
		if is_finite(float(pos[0])) and is_finite(float(pos[1])):
			workspace_script_position = Vector2(clampf(float(pos[0])/units,-100000,100000),clampf(float(pos[1])/units,-100000,100000))
	var groups: Variant = raw.get("groups", {})
	if not groups is Dictionary: return
	for key in groups:
		if loose_groups.size() >= 100: break
		var group: Variant = groups[key]
		if not group is Dictionary: continue
		var effects: Variant = group.get("effects", [])
		var point: Variant = group.get("position", [])
		if not effects is Array or effects.is_empty() or not point is Array or point.size() != 2: continue
		if not _UgcSafety.validate_skill({"effects":effects}).is_empty(): continue
		if not (point[0] is int or point[0] is float) or not (point[1] is int or point[1] is float): continue
		if not is_finite(float(point[0])) or not is_finite(float(point[1])): continue
		loose_groups[str(key)] = {"position":[clampf(float(point[0])/units,-100000,100000),clampf(float(point[1])/units,-100000,100000)],"effects":effects.duplicate(true)}

	var reporters: Variant = raw.get("reporters", {})
	if reporters is Dictionary:
		for key in reporters:
			if loose_reporters.size() >= 100: break
			var record: Variant = reporters[key]
			if not record is Dictionary or not record.get("value") is Dictionary: continue
			var point: Variant = record.get("position")
			if not point is Array or point.size() != 2: continue
			if not (point[0] is int or point[0] is float) or not (point[1] is int or point[1] is float): continue
			if not is_finite(float(point[0])) or not is_finite(float(point[1])): continue
			if not _valid_loose_reporter(record): continue
			loose_reporters[str(key)] = record.duplicate(true)
			loose_reporters[str(key)].position = [clampf(float(point[0])/units,-100000,100000),clampf(float(point[1])/units,-100000,100000)]

func _workspace_metadata() -> Dictionary:
	# Integer hundredths keep placement stable through JSON round trips without
	# giving editor coordinates any role in the executable skill definition.
	var groups: Dictionary = loose_groups.duplicate(true)
	for key in groups:
		var point: Array = groups[key]["position"]
		groups[key]["position"] = [roundi(float(point[0])*100),roundi(float(point[1])*100)]
	var reporters := loose_reporters.duplicate(true)
	for key in reporters:
		var point: Array = reporters[key].position
		reporters[key].position = [roundi(float(point[0])*100),roundi(float(point[1])*100)]
	return {"version":1,"position":[roundi(workspace_script_position.x*100),roundi(workspace_script_position.y*100)],"groups":groups,"reporters":reporters}


func _new_block_for(effect_id: String, buff_id: String = "") -> Dictionary:
	if effect_id == SkillRegistry.CHANCE_PALETTE_ID:
		return SkillRegistry.make_chance_block()
	if effect_id == SkillEngine.EFFECT_IF_ELSE:
		return _default_if_else()
	if effect_id == SkillEngine.EFFECT_IF:
		return _default_if()
	if effect_id == SkillEngine.EFFECT_REPEAT:
		return _default_repeat()
	if effect_id == SkillEngine.EFFECT_STOP:
		return {"effect": SkillEngine.EFFECT_STOP}
	return _default_effect(effect_id, buff_id)


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
	_cleanup_loose_groups()
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
	if skill_tutorial_controller:
		skill_tutorial_controller.notify_action("value")


func _on_block_context_requested(path: Array, at: Vector2) -> void:
	var menu := PopupMenu.new()
	menu.popup_hide.connect(menu.queue_free)
	menu.add_item(Locale.t("skill_editor.duplicate"), 0)
	menu.add_item(Locale.t("skill_editor.delete"), 1)
	if not SkillRegistry.is_control_effect(str(_effect_at(path).get("effect", ""))): menu.add_item(Locale.t("skill_editor.btn_edit"), 2)
	menu.add_separator()
	menu.add_item(Locale.t("skill_editor.btn_up"), 3)
	menu.add_item(Locale.t("skill_editor.btn_down"), 4)
	var siblings := _effect_list_at(path)
	var index: int = path.back()
	menu.set_item_disabled(menu.get_item_index(3), index <= 0)
	menu.set_item_disabled(menu.get_item_index(4), index >= siblings.size() - 1)
	menu.id_pressed.connect(func(id: int):
		if id == 0:
			_duplicate_effect(path)
		elif id == 1:
			_on_block_delete_path(path)
		elif id == 2: _on_block_edit_path(path)
		elif id == 3: _on_block_move_path(path, -1)
		elif id == 4: _on_block_move_path(path, 1)
	)
	add_child(menu)
	menu.position = Vector2i(at)
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


func _default_effect(effect_id: String, buff_id: String = "") -> Dictionary:
	# Target selection starts EMPTY: the block shows a "+ 选择目标" placeholder
	# so the user actively picks (rather than silently inheriting a default
	# like "敌方单体"). force_self effects never show a target slot.
	var eff := {
		"target": "",
		"target_side": "",
		"effect": effect_id,
		"buff_id": "",
		"duration": 0,
		"random_count": 0,
		"probability": 100,
	}
	if SkillRegistry.force_self(effect_id):
		eff["target"] = SkillEngine.TARGET_SELF
		eff["target_side"] = SkillEngine.TARGET_SIDE_ALL
	if effect_id == SkillEngine.EFFECT_ADD_BUFF:
		eff["buff_id"] = buff_id if buff_id in SkillRegistry.BUFF_IDS else SkillEngine.BUFF_ATK_BOOST
		eff["duration"] = 2
	if effect_id == SkillEngine.EFFECT_ZERO_COST:
		# The selector shape describes cards in the active hand, not a battlefield
		# target.  Unlike ordinary effects this block has no inline target socket,
		# so it must start with a usable single-card default.
		eff["target"] = SkillEngine.TARGET_SINGLE
		eff["target_side"] = SkillEngine.TARGET_SIDE_ALL
		eff["cost_reduction_mode"] = SkillRegistry.COST_REDUCTION_TURN
	# Passive talents never interrupt battle flow with a manual target picker.
	# Their effect target is the talent card itself; the board-side choice, when
	# relevant, belongs to the trigger rather than to the effect block.
	if _is_talent_mode():
		eff["target"] = SkillEngine.TARGET_SELF
		eff["target_side"] = SkillEngine.TARGET_SIDE_ALL
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
	if skill_tutorial_controller and not skill_tutorial_controller.allows("control"):
		return
	effect_data.append(_default_if_else())
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _add_if_block() -> void:
	if skill_tutorial_controller and not skill_tutorial_controller.allows("control"):
		return
	effect_data.append(_default_if())
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _add_stop_block() -> void:
	if skill_tutorial_controller and not skill_tutorial_controller.allows("control"):
		return
	effect_data.append({"effect": SkillEngine.EFFECT_STOP})
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


func _default_repeat() -> Dictionary:
	return {
		"effect": SkillEngine.EFFECT_REPEAT,
		"then_effects": [],
	}


func _add_repeat_block() -> void:
	if skill_tutorial_controller and not skill_tutorial_controller.allows("control"):
		return
	effect_data.append(_default_repeat())
	_refresh_script()
	_update_summary()
	_maybe_snapshot()


# Write condition changes through one nested dictionary, including older skills.
func _replace_condition_at(root: Dictionary, path: Array, value: Dictionary) -> Dictionary:
	if path.is_empty(): return value.duplicate(true)
	var result := root.duplicate(true)
	var cursor := result
	for key in path.slice(0, path.size() - 1):
		if not cursor.get(key) is Dictionary: return result
		cursor = cursor[key]
	cursor[path.back()] = value.duplicate(true)
	return result

func _write_condition(effect: Dictionary, root: Dictionary) -> void:
	for key in ["condition_type", "condition_op", "condition_value", "condition_buff_id"]: effect.erase(key)
	if root.is_empty(): effect.erase("condition")
	else: effect["condition"] = root.duplicate(true)

func _on_block_condition_inserted(path: Array, socket_path: Array, payload: Dictionary) -> void:
	var effect := _effect_at(path)
	var root: Dictionary = SkillEngine._condition_dict(effect).duplicate(true)
	var source: Object = payload.get("from_cond_slot")
	if source != null and is_instance_valid(source):
		var source_path: Array = payload.get("from_condition_path", [])
		var displaced := SkillBlock.condition_at_path(root, socket_path).duplicate(true)
		if source.effect_path == path:
			if SkillBlock.condition_path_prefix(source_path, socket_path) or SkillBlock.condition_path_prefix(socket_path, source_path):
				return
			root = _replace_condition_at(root, source_path, displaced)
		else:
			var source_effect := _effect_at(source.effect_path)
			_write_condition(source_effect, _replace_condition_at(SkillEngine._condition_dict(source_effect), source_path, displaced))
	_write_condition(effect, _replace_condition_at(root, socket_path, payload.get("boolean", {})))
	_cleanup_loose_reporters()
	_refresh_script()
	_update_summary()
	_maybe_snapshot()
	_show_connection_feedback.call_deferred(path, socket_path)

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
	_cleanup_loose_reporters()
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
	UITheme.apply_popup_frame(panel, "gold", false)
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
	preload("res://SkillStatusPicker.gd").fill(cond_buff_sel, SkillEngine.BUFF_ATK_BOOST)
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
	preload("res://SkillStatusPicker.gd").fill(cond_buff_sel, existing.get("condition_buff_id", SkillEngine.BUFF_ATK_BOOST))
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
				eff["condition"]["condition_buff_id"] = preload("res://SkillStatusPicker.gd").value(cond_buff_sel)
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

	# The section label already groups these fields; a second frame adds noise.
	var card := PanelContainer.new()
	var card_st := StyleBoxEmpty.new()
	card_st.content_margin_top = 4
	card_st.content_margin_bottom = 8
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
	var show_talent := false
	if skill_type_row != null:
		skill_type_row.visible = show_talent
	skill_type_select.visible = show_talent
	skill_type_select.selected = 1 if _is_talent_mode() else 0
	if _is_talent_mode():
		if skill_prob_spin:
			skill_prob_spin.value = 100
		if max_uses_spin:
			max_uses_spin.value = 0
	if settings_row:
		settings_row.visible = not _is_talent_mode()
	if settings_label:
		settings_label.visible = not _is_talent_mode()


# ============================================
# Trigger helpers
# ============================================

func _trigger_keys() -> Array:
	if _is_talent_mode():
		return [
			SkillEngine.TRIGGER_ALWAYS, SkillEngine.TRIGGER_ON_ADDED, SkillEngine.TRIGGER_ON_DISCARDED,
			SkillEngine.TRIGGER_ON_BOARD_CHANGED,
		]
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
		SkillEngine.TRIGGER_ON_BOARD_CHANGED,
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
	trigger_preview_label.text = SkillHelp.description("trigger",trigger_key)
	_update_trigger_side_visibility()


func _setup_trigger_side_select() -> void:
	trigger_side_select.clear()
	for side_id: String in SkillRegistry.TARGET_SIDE_IDS:
		trigger_side_select.add_item(Locale.term("board_side", side_id))
	trigger_side_select.item_selected.connect(func(index: int):
		if index >= 0 and index < SkillRegistry.TARGET_SIDE_IDS.size():
			current_trigger_side = SkillRegistry.TARGET_SIDE_IDS[index]
			_refresh_script()
			_update_summary()
			_maybe_snapshot()
	)
	_sync_trigger_side_select()
	_update_trigger_side_visibility()


func _sync_trigger_side_select() -> void:
	if trigger_side_select == null:
		return
	var index := SkillRegistry.TARGET_SIDE_IDS.find(current_trigger_side)
	trigger_side_select.select(maxi(0, index))


func _update_trigger_side_visibility() -> void:
	if trigger_side_row != null:
		trigger_side_row.visible = not _is_spell() and current_trigger_key == SkillEngine.TRIGGER_ON_BOARD_CHANGED


# ============================================
# Build / Load / Summary
# ============================================

func _load_skill(skill: Dictionary):
	_restore_workspace(skill.get("_workspace", {}))
	skill_name_input.text = skill.get("skill_name", "")
	if _is_spell():
		current_trigger_key = SkillEngine.TRIGGER_ON_CAST
	else:
		current_trigger_key = skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK)
	current_trigger_side = str(skill.get("trigger_side", SkillEngine.TARGET_SIDE_ALL))
	_sync_trigger_side_select()
	if skill_prob_spin:
		skill_prob_spin.value = float(skill.get("probability", 100))
	if max_uses_spin:
		max_uses_spin.value = float(skill.get("max_uses", 0))
	if skill_type_select:
		skill_type_select.selected = 0 if skill.get("skill_type", SkillEngine.SKILL_TYPE_NORMAL) != SkillEngine.SKILL_TYPE_TALENT else 1
	_update_trigger_preview()
	_update_skill_type_visibility()
	if _is_talent_mode():
		_build_palette()

	var effects: Array = SkillEngine.legacy_skill_effects(skill)
	var normalized_effects: Array = []
	for eff in effects:
		normalized_effects.append(_TargetResolver.normalize_effect_target(eff))
	effect_data = normalized_effects
	# Start a fresh undo history for this loaded skill.
	_reset_undo_history()
	_refresh_script()


func _build_skill(include_empty := false) -> Dictionary:
	if effect_data.is_empty() and not include_empty:
		return {}
	var is_spell := _is_spell()
	var trigger_key: String = _selected_trigger_key()
	var skill_type_val: String = SkillEngine.SKILL_TYPE_TALENT if _is_talent_mode() else SkillEngine.SKILL_TYPE_NORMAL
	var result := {
		"skill_name": PlayerData.card_draft.get("name", "") if is_spell else skill_name_input.text.strip_edges(),
		"trigger": trigger_key,
		"probability": 100 if _is_talent_mode() else (int(skill_prob_spin.value) if skill_prob_spin else 100),
		"max_uses": 0 if _is_talent_mode() else (int(max_uses_spin.value) if max_uses_spin else 0),
		"skill_type": skill_type_val,
		"effects": effect_data.duplicate(true),
	}
	if trigger_key == SkillEngine.TRIGGER_ON_BOARD_CHANGED:
		result["trigger_side"] = current_trigger_side
	if not loose_groups.is_empty() or not loose_reporters.is_empty() or not workspace_script_position.is_zero_approx():
		result["_workspace"] = _workspace_metadata()
	return result


func interrupted_skill_workspace() -> Dictionary:
	if not is_node_ready() or (_editor_state() == _opening_editor_state and skill_name_input.text == _opening_skill_name):
		return {}
	var skill := _build_skill(true)
	skill["skill_name"] = skill_name_input.text
	return {"index": PlayerData.editing_skill_index, "skill": skill}


func _update_summary():
	var skill: Dictionary = _build_skill()
	if skill.is_empty():
		# An unfinished script is still invalid to save, but its preview must
		# reflect the trigger/name already selected instead of defaulting to Attack.
		skill = {"skill_name": skill_name_input.text, "trigger": _selected_trigger_key(), "trigger_side": current_trigger_side, "effects": []}
	skill_summary.text = _format_skill(skill)
	_refresh_error_banner()
	if workbench != null:
		workbench.invalidate_preview()


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
		var trigger_id: String = str(skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK))
		var tname: String = Locale.term("trigger", trigger_id)
		if trigger_id == SkillEngine.TRIGGER_ON_BOARD_CHANGED:
			tname = Locale.t("skill_editor.board_change_trigger", [Locale.term("board_side", str(skill.get("trigger_side", SkillEngine.TARGET_SIDE_ALL)))])
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
	_focus_playtest_block.call_deferred()
	_restore_pointer_visibility()
	# Long reporters widen their block; the script area scrolls horizontally
	# (bottom bar, like the existing vertical scroll) so every part of a wide
	# block stays reachable without auto-wrapping the sentence.
	var script_scroll: ScrollContainer = $Panel/Margin/HBox/MainPanel/Margin/Scroll
	script_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_apply_theme()
	_setup_trigger_side_select()
	if _is_talent_mode():
		current_trigger_key = SkillEngine.TRIGGER_ALWAYS
	_apply_texts()
	_build_settings_row()
	_update_skill_type_visibility()
	_build_palette()
	_build_undo_buttons()
	_build_skill_template_button()
	if _is_talent_mode() and _template_btn:
		_template_btn.visible = false
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
	workbench = preload("res://SkillEditorWorkbench.gd").new()
	workbench.install(self)
	if PlayerData.skill_tutorial_active:
		skill_tutorial_controller = _TutorialController.new()
		add_child(skill_tutorial_controller)
		skill_tutorial_controller.start(self)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_opening_editor_state = _editor_state().duplicate(true)
	_opening_skill_name = skill_name_input.text
	if OS.has_feature("android") and UIMotion.consume_restore_state() == "recover_skill":
		var skill: Dictionary = PlayerData.recovered_card_draft.interrupted_skill.skill
		if _UgcSafety.validate_skill(skill).is_empty():
			_load_skill(skill)
			_update_summary()


func _connect_signals():
	skill_name_input.text_changed.connect(_on_skill_name_changed)
	palette_search.text_changed.connect(_filter_palette)
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _on_skill_name_changed(value: String) -> void:
	_update_summary()
	if skill_tutorial_controller:
		skill_tutorial_controller.on_name_changed(value)


func _build_skill_template_button() -> void:
	var row := save_button.get_parent() as HBoxContainer
	_template_btn = Button.new()
	_template_btn.text = Locale.t("skill_editor.templates")
	UITheme.apply_button(_template_btn, "utility")
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
	var page := preload("res://SelectionMenu.gd").new()
	page.layer = 105
	page.heading = Locale.t("skill_editor.templates")
	page.backdrop = UITheme.COLOR_BG
	page.scroll_choices = true
	add_child(page)
	var templates := _builtin_skill_templates()
	templates.append_array(PlayerData.custom_skill_templates)
	for entry in templates:
		var template_skill := (entry.get("skill", {}) as Dictionary).duplicate(true)
		var template_name := str(entry.get("name", Locale.t("skill.no_name")))
		page.add_choice(template_name, _on_skill_template_chosen.bind(template_skill, page), template_name)
	var name_input := LineEdit.new()
	name_input.placeholder_text = Locale.t("skill_editor.template_name")
	name_input.custom_minimum_size.y = 36
	UITheme.apply_input(name_input)
	page.entries.add_child(name_input)
	page.add_choice(Locale.t("skill_editor.favorite_current"), func():
		if PlayerData.save_custom_skill_template(name_input.text, _build_skill()):
			page.queue_free())
	page.finish()


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
	UITheme.apply_button(_undo_btn, "utility")
	_undo_btn.pressed.connect(_undo)
	row.add_child(_undo_btn)
	row.move_child(_undo_btn, 0)
	_redo_btn = Button.new()
	_redo_btn.text = Locale.t("skill_editor.redo")
	_redo_btn.add_theme_font_size_override("font_size", max(10, int(13 * _ui_scale())))
	UITheme.apply_button(_redo_btn, "utility")
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
		3:
			return "talent"
	return "skill3"


func _on_save_pressed():
	if effect_data.is_empty() and (not loose_groups.is_empty() or not loose_reporters.is_empty()):
		_show_save_blocked_popup([Locale.t("skill_editor.error_empty_skill")])
		return
	if loose_groups.size() > 100 or loose_reporters.size() > 100:
		_show_save_blocked_popup([Locale.t("skill_editor.loose_limit")])
		return
	for group in loose_groups.values():
		var workspace_issues := _UgcSafety.validate_skill({"effects":group["effects"]})
		if not workspace_issues.is_empty():
			_show_save_blocked_popup([_UgcSafety.first_error_text(workspace_issues)])
			return
	var errors: Array = _collect_errors()
	# An untouched/empty skill is a valid "no skill" state (saved as {}); only
	# real compile errors must block the save, otherwise the invalid skill
	# would be written into the card JSON.
	var empty_only: bool = errors.size() == 1 and str(errors[0]) == Locale.t("skill_editor.error_empty_skill")
	if not errors.is_empty() and not empty_only:
		_show_save_blocked_popup(errors)
		return
	var skill: Dictionary = _build_skill()
	if skill_tutorial_controller:
		skill_tutorial_controller.handle_save(skill)
		return
	var skill_key: String = _skill_key_for_index(PlayerData.editing_skill_index)
	if not skill.is_empty():
		if skill_key == "skill1":
			PlayerData.card_draft["talent"] = {}
		elif skill_key == "talent":
			PlayerData.card_draft["skill1"] = {}
	PlayerData.card_draft[skill_key] = skill
	PlayerData.save_card_draft_recovery()
	print("Skill saved: %s" % skill.get("skill_name", ""))
	UIMotion.go_back("res://CardEditor.tscn")


# A compile-error skill must not reach the card draft (which is later written
# to card_library.json): show what's wrong and refuse to leave the editor.
func _show_save_blocked_popup(errors: Array, title_key: String = "skill_editor.save_blocked_title") -> void:
	validation_requested = true
	_mark_invalid_conditions()
	var s := _ui_scale()
	var popup := UITheme.make_popup_layer(self, 100)
	var layer: CanvasLayer = popup.get("layer")
	var size := Vector2(420, 300) * s
	var panel := Panel.new()
	UITheme.apply_popup_frame(panel, "gold", false)
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
	title.text = Locale.t(title_key)
	title.add_theme_font_size_override("font_size", max(13, int(16 * s)))
	UITheme.apply_title(title, max(13, int(16 * s)))
	title.add_theme_color_override("font_color", UITheme.Tokens.PAPER)
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
	var issues: Array = _error_checker.collect_issues()
	for e in errors:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		err_box.add_child(row)
		var lbl := Label.new()
		lbl.text = "- " + str(e)
		lbl.add_theme_font_size_override("font_size", max(10, int(12 * s)))
		lbl.add_theme_color_override("font_color", UITheme.Tokens.TEXT)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		for issue in issues:
			if issue.get("message","") != str(e) or issue.get("path",[]).is_empty(): continue
			var locate := Button.new()
			locate.text = Locale.t("skill_editor.locate_issue")
			UITheme.apply_button(locate,"secondary")
			locate.pressed.connect(func():
				layer.queue_free()
				_focus_issue_path(issue.path,issue.get("condition_path")))
			row.add_child(locate)
			break

	var close_btn := Button.new()
	close_btn.text = Locale.t("common.confirm")
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
	)
	vb.add_child(close_btn)


func _focus_playtest_block() -> void:
	var path := PlayerData.skill_focus_path.duplicate()
	PlayerData.skill_focus_path.clear()
	if path.is_empty():
		return
	var effect := _effect_at(path)
	if effect.is_empty():
		return
	if str(effect.get("effect", "")) in [SkillEngine.EFFECT_IF, SkillEngine.EFFECT_IF_ELSE]:
		_open_if_condition_popup(path)
	else:
		_open_effect_popup(path)


func _on_cancel_pressed():
	if skill_tutorial_controller:
		skill_tutorial_controller._on_exit()
		return
	if _editor_state() == _opening_editor_state and skill_name_input.text == _opening_skill_name:
		_leave_skill_without_saving()
		return
	if not is_instance_valid(_discard_dialog):
		_discard_dialog = ConfirmationDialog.new()
		_discard_dialog.title = Locale.t("editor.discard_title")
		_discard_dialog.dialog_text = Locale.t("editor.discard_body")
		add_child(_discard_dialog)
		UITheme.apply_dialog(_discard_dialog,true)
		_discard_dialog.confirmed.connect(_leave_skill_without_saving)
	_discard_dialog.popup_centered()

func _leave_skill_without_saving() -> void:
	if PlayerData.recovered_card_draft.has("interrupted_skill"):
		PlayerData.save_card_draft_recovery()
	UIMotion.go_back("res://CardEditor.tscn")


func _add_chance_block() -> void:
	if skill_tutorial_controller and not skill_tutorial_controller.allows("control"): return
	effect_data.append(SkillRegistry.make_chance_block())
	_refresh_script()
	_update_summary()
	_maybe_snapshot()

func _reporter_from_payload(data: Dictionary) -> Dictionary:
	match str(data.get("type", "")):
		"target_block": return {"kind":"target", "value":{"target":str(data.get("value", ""))}}
		"side_block": return {"kind":"side", "value":{"target_side":str(data.get("value", ""))}}
		"var_block":
			var value := {"kind":"var", "var_id":str(data.get("var_id", ""))}
			var offset := int(data.get("offset", 0))
			if offset != 0: value["offset"] = offset
			return {"kind":"number", "value":value}
		"expr_block":
			return {"kind":"number","value":data.get("expression", ValueSlot.make_expression(str(data.get("expr_kind", "+")))).duplicate(true)}
		"boolean_block", "condition_block", "logic_block":
			var condition: Dictionary = data.get("boolean", data.get("condition", {})).duplicate(true)
			if data.get("type") == "logic_block":
				condition = {"logic":str(data.get("logic_kind", "and"))}
				if condition.logic == "not": condition.child = {}
				else: condition.merge({"lhs":{},"rhs":{}})
			return {"kind":"condition","value":{"effect":SkillEngine.EFFECT_IF,"condition":condition,"then_effects":[]}}
	return {}

func _valid_loose_reporter(record: Dictionary) -> bool:
	if record.get("kind") not in ["number","condition","target","side"] or not record.get("value") is Dictionary: return false
	if record.kind == "target": return record.value.get("target") in SkillRegistry.TARGET_IDS
	if record.kind == "side": return record.value.get("target_side") in SkillRegistry.TARGET_SIDE_IDS
	var renderer = preload("res://SkillLooseReporter.gd")
	if record.kind == "number" and not renderer.valid_number(record.value): return false
	if record.kind == "condition":
		var condition: Variant = record.value.get("condition")
		if not condition is Dictionary or condition.is_empty() or not renderer.valid_condition(condition): return false
	var effect: Dictionary = record.value if record.kind == "condition" else {"effect":SkillEngine.EFFECT_HEAL,"target":SkillEngine.TARGET_SELF,"value_expr":record.value}
	return _UgcSafety.validate_skill({"effects":[effect]}).is_empty()

func _can_drop_on_workspace(data: Variant) -> bool:
	if not data is Dictionary: return false
	# A rejected typed-socket drop must not fall through to a destructive
	# detach onto the canvas (especially a reporter into its own descendant).
	var hovered: Control = get_viewport().gui_get_hovered_control()
	while hovered != null and hovered != workbench.workspace:
		if hovered is ValueSlot or hovered is TargetSlot or hovered.get_script() == preload("res://SkillConditionSocket.gd"): return false
		hovered = hovered.get_parent() as Control
	if data.get("type") == "effect_block":
		_preview_stack_drop(data)
		return true
	var record := _reporter_from_payload(data)
	var source: Object = data.get("from_slot")
	var relocating := source != null and is_instance_valid(source) and source.has_meta("loose_reporter_key")
	var condition_source: Object = data.get("from_cond_slot")
	if condition_source != null and is_instance_valid(condition_source):
		relocating = condition_source.effect_path.size() == 2 and condition_source.effect_path[0] == "reporter" and data.get("from_condition_path", []).is_empty()
	return not record.is_empty() and (relocating or loose_reporters.size() < 100) and _valid_loose_reporter(record)

func _on_loose_reporter_changed() -> void:
	_update_summary()
	_maybe_snapshot()

func _remove_loose_reporter(key: String, notify := true) -> void:
	loose_reporters.erase(key)
	_refresh_script.call_deferred()
	if notify: _on_loose_reporter_changed()

func _drop_reporter_on_workspace(local_point: Vector2, data: Dictionary) -> void:
	if not _can_drop_on_workspace(data): return
	var record := _reporter_from_payload(data)
	var grab: Array = data.get("grab_offset", [12,12])
	var point: Vector2 = workbench.workspace.to_world(local_point) - Vector2(float(grab[0]),float(grab[1]))
	record.position = [point.x,point.y]
	var source: Object = data.get("from_slot")
	if source != null and is_instance_valid(source): source.clear_to_number(false)
	source = data.get("from_cond_slot")
	if source != null and is_instance_valid(source):
		var effect := _effect_at(source.effect_path)
		_write_condition(effect, _replace_condition_at(SkillEngine._condition_dict(effect), data.get("from_condition_path", []), {}))
	var key := "r%d" % Time.get_ticks_usec()
	loose_reporters[key] = record
	_cleanup_loose_reporters()
	_refresh_script()
	_on_loose_reporter_changed()

func _cleanup_loose_reporters() -> void:
	for key in loose_reporters.keys():
		if loose_reporters[key].kind == "condition" and loose_reporters[key].value.get("condition", {}).is_empty(): loose_reporters.erase(key)

func _on_loose_reporter_context(key: String, at: Vector2) -> void:
	if not loose_reporters.has(key): return
	var menu := PopupMenu.new()
	menu.popup_hide.connect(menu.queue_free)
	menu.add_item(Locale.t("skill_editor.duplicate"),0)
	menu.add_item(Locale.t("skill_editor.delete"),1)
	menu.set_item_disabled(0, loose_reporters.size() >= 100)
	menu.id_pressed.connect(func(id: int):
		if not loose_reporters.has(key): return
		if id == 1: _remove_loose_reporter(key)
		else:
			var copy: Dictionary = loose_reporters[key].duplicate(true)
			copy.position = [float(copy.position[0])+24,float(copy.position[1])+24]
			loose_reporters["r%d" % Time.get_ticks_usec()] = copy
			_refresh_script()
			_on_loose_reporter_changed())
	add_child(menu)
	menu.position = Vector2i(at)
	menu.popup()
