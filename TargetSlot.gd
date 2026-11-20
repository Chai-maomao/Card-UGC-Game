class_name TargetSlot
extends PanelContainer

# ============================================
# Scratch-style target selector slot.
# Sits at the "target" position of an effect sentence ("对 [友方/敌方]
# [目标] 造成 …"): two independent dimensions — side (enemy/ally/all) and
# target (single/sides/all/self/self_sides).
# Each slot renders as an oval chip showing the current value; clicking it
# opens a picker, and a matching palette reporter (target_block / side_block)
# can be dropped in to set it. Dragging the chip back onto the palette
# leaves an empty socket.
# Data contract (bound dictionary, shared reference):
#   side   : data["target_side"] = side_id
#   target : data["target"]      = target_id
# ============================================

const _TargetResolver = preload("res://SkillTargetResolver.gd")

signal changed
signal selection_updated

var data: Dictionary
var kind: String = "target"   # "target" | "side"
var _drop_highlight: bool = false
var _dragging: bool = false
var _motion_tween: Tween


func setup(p_data: Dictionary, p_kind: String) -> void:
	data = p_data
	kind = p_kind
	_apply_slot_style()
	_rebuild()


func _apply_slot_style() -> void:
	# The chip itself owns the material and drop outline. A second shaped
	# panel adds an empty ring around an already-filled reporter.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	custom_minimum_size = Vector2(64, 26)
	for child in get_children():
		if child is Button: _apply_button_style(child,_current_value() == "")
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_drag_forwarding(
		Callable(self, "_slot_get_drag_data"),
		Callable(self, "_can_drop_var"),
		Callable(self, "_drop_var"),
	)


func _tint_color() -> Color:
	return Color(0.12, 0.48, 0.72) if kind == "target" else Color(0.62, 0.40, 0.12)


func _field() -> String:
	return "target_side" if kind == "side" else "target"


func _default_value() -> String:
	if kind == "side":
		var forced := SkillRegistry.forced_target_side(str(data.get("effect", "")))
		if forced != "":
			return forced
		return _TargetResolver.default_target_side(str(data.get("target", SkillEngine.TARGET_SINGLE)))
	var allowed := SkillRegistry.allowed_targets(str(data.get("effect", "")))
	return str(allowed[0]) if not allowed.is_empty() else SkillEngine.TARGET_SINGLE


func _current_value() -> String:
	# Unset keys count as empty: the slot renders as an empty socket
	# ("+ 选择目标" / "+ 选择阵营") until the user picks a value, matching the
	# _sync_side visibility rule. Removing a chip erases its selection.
	return str(data.get(_field(), ""))


func _ids() -> Array:
	if has_meta("loose_reporter_key"):
		return SkillRegistry.TARGET_SIDE_IDS if kind == "side" else SkillRegistry.TARGET_IDS
	if kind == "side":
		var forced := SkillRegistry.forced_target_side(str(data.get("effect", "")))
		if forced != "":
			return [forced]
		return SkillRegistry.TARGET_SIDE_IDS
	var ids: Array = SkillRegistry.allowed_targets(str(data.get("effect", ""))).duplicate()
	# Keep irrelevant choices out of the common picker. A persisted invalid
	# combination is still caught by SkillErrorChecker.
	if not SkillRegistry.allows_player_target(str(data.get("effect", ""))):
		ids.erase(SkillEngine.TARGET_PLAYER)
	return ids


func _value_label(value: String) -> String:
	return Locale.term("target_side", value) if kind == "side" else Locale.term("target", value)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	var btn := Button.new()
	var value := _current_value()
	var empty := value == ""
	if empty:
		btn.text = ""
	else:
		btn.text = ValueSlot._clamp_chip(_value_label(value), 8)
	# No clip_text: it drops the text from the minimum-size calculation and
	# collapses the chip; _clamp_chip already keeps the label bounded.
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_apply_button_style(btn,empty)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if empty:
		btn.tooltip_text = Locale.t("skill_editor.target_pick_hint_tip") if kind == "target" else Locale.t("skill_editor.side_pick_hint_tip")
	else:
		btn.tooltip_text = SkillHelp.description("target_side" if kind == "side" else "target", value)
	btn.pressed.connect(func(): _open_menu(btn))
	_set_param_pass(btn)
	add_child(btn)


func _apply_button_style(btn: Button, empty: bool) -> void:
	var st := StyleBoxFlat.new()
	var tint := _tint_color()
	# Unset slots look like empty sockets: faint fill, dashed-feel bright edge.
	# (A directed target with 全体 is no longer grayed out — it is reported as
	# a compile error by SkillErrorChecker's red banner instead.)
	st.bg_color = Color(tint.r, tint.g, tint.b, 0.35 if empty else 0.78)
	st.border_color = Color(0.50,0.92,1.0) if _drop_highlight else Color(tint.r,tint.g,tint.b,0.55) if empty else tint
	st.set_border_width_all(2 if empty or _drop_highlight else 1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	btn.add_theme_stylebox_override("normal", preload("res://SkillSocketStyle.gd").from_flat(st, kind))
	var hover: StyleBoxFlat = st.duplicate()
	hover.bg_color = Color(tint.r, tint.g, tint.b, 0.55 if empty else 0.92)
	btn.add_theme_stylebox_override("hover", preload("res://SkillSocketStyle.gd").from_flat(hover, kind))
	btn.add_theme_stylebox_override("pressed", preload("res://SkillSocketStyle.gd").from_flat(hover, kind))


func _placeholder_text() -> String:
	return Locale.t("skill_editor.target_pick_hint") if kind == "target" else Locale.t("skill_editor.side_pick_hint")


func _open_menu(anchor: Control) -> void:
	var menu := PopupMenu.new()
	menu.popup_hide.connect(menu.queue_free)
	var ids: Array = _ids()
	for i in range(ids.size()):
		menu.add_item(_value_label(str(ids[i])), i)
		menu.set_item_tooltip(i, SkillHelp.description("target" if kind == "target" else "target_side", str(ids[i])))
	menu.id_pressed.connect(func(id: int):
		_set_selection(str(ids[id]))
		changed.emit()
	)
	add_child(menu)
	menu.position = Vector2i(anchor.get_global_rect().position + Vector2(0, anchor.size.y))
	menu.popup()


func _slot_get_drag_data(_pos: Vector2):
	var value := _current_value()
	if value == "":
		return null
	if get_viewport().gui_is_dragging():
		var preview := TargetSlot.new()
		preview.set_meta("drag_preview", true)
		preview.setup(data.duplicate(true), kind)
		preview.scale = get_global_transform().get_scale()
		preview.position = -_pos * preview.scale
		preview.size = preview.get_combined_minimum_size()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in preview.find_children("*","Control",true,false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrap := Control.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(preview)
		set_drag_preview(wrap)
		_dragging = true
		_animate_slot(Vector2.ONE, Color(0.72,0.76,0.84,0.48),0.07)
	return {
		"type": "target_block" if kind == "target" else "side_block",
		"value": value,
		"from_slot": self,
		"grab_offset": [_pos.x,_pos.y],
	}


func _can_drop_var(_pos: Vector2, payload) -> bool:
	if not (payload is Dictionary):
		_set_drop_highlight(false)
		return false
	var t: String = str(payload.get("type", ""))
	var ok := t == ("target_block" if kind == "target" else "side_block") \
		and str(payload.get("value", "")) in _ids()
	var source := payload.get("from_slot") as TargetSlot
	if is_instance_valid(source):
		var displaced := _current_value()
		ok = ok and source != self and source.kind == kind and (displaced.is_empty() or displaced in source._ids())
	_set_drop_highlight(ok)
	return ok


func _drop_var(_pos: Vector2, payload) -> void:
	if not _can_drop_var(_pos, payload): return
	_set_drop_highlight(false)
	var source := payload.get("from_slot") as TargetSlot
	if is_instance_valid(source):
		var displaced := _current_value()
		if displaced.is_empty():
			source.clear_to_number(false)
		else:
			source._set_selection(displaced)
	_set_selection(str(payload.get("value")))
	changed.emit()
	_play_drop_pulse()


# Restore the empty slot. Also used when the chip is dragged
# onto the palette (drop-to-discard for target / side reporters).
func clear_to_number(notify: bool = true) -> void:
	if has_meta("loose_reporter_key"):
		var editor = get_meta("loose_reporter_editor").get_ref()
		if editor != null: editor._remove_loose_reporter(str(get_meta("loose_reporter_key")), notify)
		return
	_set_selection("")
	if notify: changed.emit()


func _set_selection(value: String) -> void:
	if value.is_empty():
		data.erase(_field())
	else:
		data[_field()] = value
	_rebuild()
	selection_updated.emit()


func _set_drop_highlight(on: bool) -> void:
	if _drop_highlight == on:
		return
	_drop_highlight = on
	_apply_slot_style()


func _animate_slot(target_scale: Vector2, target_modulate: Color, duration: float) -> void:
	pivot_offset = size * 0.5
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "scale", target_scale, duration)
	_motion_tween.tween_property(self, "modulate", target_modulate, duration)


func _play_drop_pulse() -> void:
	modulate = Color(1.10,1.10,1.10)
	_animate_slot(Vector2.ONE, Color.WHITE, 0.16)


func _notification(what: int) -> void:
	if get_meta("drag_preview", false): return
	if what == NOTIFICATION_DRAG_END:
		_dragging = false
		_set_drop_highlight(false)
		_animate_slot(Vector2.ONE, Color.WHITE, 0.10)
	elif what == NOTIFICATION_MOUSE_EXIT and _drop_highlight:
		if not get_global_rect().has_point(get_global_mouse_position()):
			_set_drop_highlight(false)


# Inline parameter controls keep mouse_filter PASS so drag-drop resolution can
# walk through them to the enclosing block; STOP controls swallow the drop.
func _set_param_pass(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
