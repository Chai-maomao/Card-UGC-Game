class_name SkillPaletteBlock
extends Button

# ============================================
# Draggable palette block. Clicking adds the block to the script; dragging it
# onto the script area also appends it (Scratch-style grab-and-drop).
# Effect blocks carry an effect_id; condition reporter blocks (condition_id)
# can only be dropped into an if-block's condition gap.
# ============================================

signal palette_drop_requested(from_path: Array)

var effect_id: String = ""
var buff_id: String = ""
var condition_id: String = ""   # legacy condition reporter (kept for compat)
var var_id: String = ""         # variable reporter oval
var boolean_kind: String = ""   # "compare" / "has_buff" boolean block
var expr_kind: String = ""      # math reporter: "+" / "-" / "*" / "/" / "rand"
var logic_kind: String = ""     # logic reporter: "and" / "or" / "not"
var target_kind: String = ""    # target reporter: single / sides / all / self / self_sides
var side_kind: String = ""      # side reporter: enemy / ally / all
var _dragging: bool = false
var _discard_highlight: bool = false
var _motion_tween: Tween


func _init() -> void:
	set_meta("keyword_enabled",true)


func _ready() -> void:
	if get_meta("drag_preview",false):
		pivot_offset = Vector2.ZERO
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	var help := SkillHelp.palette(self)
	if not help.is_empty():
		tooltip_text = help
	resized.connect(_update_pivot)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	_update_pivot()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _animate_to(target_scale: Vector2, target_modulate: Color, duration: float) -> void:
	if target_scale.x > 1.0:
		var fit := UITheme._fit_button_hover(self, target_scale)
		target_scale = Vector2(fit.x, fit.y)
		pivot_offset = Vector2(fit.z, fit.w)
	else:
		_update_pivot()
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "scale", target_scale, duration)
	_motion_tween.tween_property(self, "modulate", target_modulate, duration)


func _on_mouse_entered() -> void:
	if not _dragging:
		_animate_to(Vector2(1.018, 1.018), Color(1.04, 1.04, 1.04, 1.0), 0.09)


func _on_mouse_exited() -> void:
	if not _dragging:
		_animate_to(Vector2.ONE, Color.WHITE, 0.09)


func _on_button_down() -> void:
	if not _dragging:
		_animate_to(Vector2(0.975, 0.975), Color(0.96, 0.96, 0.96, 1.0), 0.05)


func _on_button_up() -> void:
	if not _dragging:
		_on_mouse_entered()


func _get_drag_data(_at_position: Vector2):
	if has_meta("skill_workspace"):
		var workspace: Control = get_meta("skill_workspace")
		_at_position = get_global_transform().affine_inverse() * (workspace.get_global_transform() * workspace.press_pointer)
	if get_viewport().gui_is_dragging():
		var preview: Control = duplicate()
		if expr_kind != "":
			preview.free()
			var number := ValueSlot.new()
			number.set_meta("drag_preview", true)
			number.setup(ValueSlot.make_expression(expr_kind), "value", "var_id", "kind", true)
			preview = number
		if effect_id != "" and has_meta("skill_workspace"):
			var workspace: Control = get_meta("skill_workspace")
			var editor = workspace.editor_ref.get_ref()
			if editor != null:
				preview.free()
				preview = SkillBlock.make_preview(editor._new_block_for(effect_id, buff_id))
		preview.set_meta("drag_preview",true)
		# Drag previews leave the palette container; retain its full hit face so
		# grabbing the empty space beside the label keeps the same pointer anchor.
		preview.custom_minimum_size = preview.get_combined_minimum_size() if preview is SkillBlock or preview is ValueSlot else size
		preview.size = preview.custom_minimum_size
		preview.modulate = Color(1, 1, 1, 0.96)
		preview.scale = get_global_transform().get_scale()
		if (preview is SkillBlock or preview is ValueSlot) and has_meta("skill_workspace"):
			preview.scale = get_meta("skill_workspace").world.get_global_transform().get_scale()
		preview.position = -_at_position * preview.scale
		var lifted: StyleBox = get_theme_stylebox("normal").duplicate()
		if lifted is StyleBoxFlat:
			lifted.set_border_width_all(1)
			lifted.shadow_color = Color(0,0,0,0.28)
			lifted.shadow_size = 5
			lifted.shadow_offset = Vector2(0,3)
		if preview is Button:
			for state in ["normal","hover","pressed","hover_pressed"]: preview.add_theme_stylebox_override(state,lifted)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in preview.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var drag_control := Control.new()
		drag_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_control.add_child(preview)
		set_drag_preview(drag_control)
		_dragging = true
		_animate_to(Vector2.ONE, Color(0.90, 0.92, 0.94, 0.55), 0.08)
	if var_id != "":
		return {"type": "var_block", "var_id": var_id}
	if expr_kind != "":
		return {"type": "expr_block", "expr_kind": expr_kind, "expression":ValueSlot.make_expression(expr_kind), "grab_offset":[_at_position.x, _at_position.y]}
	if logic_kind != "":
		return {"type": "logic_block", "logic_kind": logic_kind}
	if boolean_kind != "":
		return {"type": "boolean_block", "boolean": _make_boolean(boolean_kind)}
	if condition_id != "":
		return {"type": "condition_block", "condition": _make_condition(condition_id)}
	if target_kind != "":
		return {"type": "target_block", "value": target_kind}
	if side_kind != "":
		return {"type": "side_block", "value": side_kind}
	return {"type": "effect_block", "effect_id": effect_id, "buff_id": buff_id, "from_index": -1, "grab_offset":[_at_position.x, _at_position.y]}


func _make_condition(id: String) -> Dictionary:
	return {
		"condition_type": id,
		"condition_op": SkillEngine.CONDITION_OP_GTE,
		"condition_value": 1,
		"condition_buff_id": SkillEngine.BUFF_ATK_BOOST,
	}


# Scratch-style boolean reporter: "[lhs] [op] [rhs]" comparison, or the
# special "target has buff" form.
func _make_boolean(kind: String) -> Dictionary:
	if kind == "has_buff":
		return {
			"op": "has",
			"lhs": {"kind": "target"},
			"rhs": {"kind": "buff", "buff_id": SkillEngine.BUFF_ATK_BOOST},
		}
	return {
		"op": SkillEngine.CONDITION_OP_GTE,
		"lhs": {},
		"rhs": {},
	}


# The palette is a drop-to-discard zone: dropping a script block onto any
# palette button deletes it. (The palette panel itself is also a target, but
# its buttons sit on top with mouse_filter STOP, so each button must forward
# the drop itself — otherwise the drag would be discarded over button areas.)
func _can_drop_data(_at_position: Vector2, data) -> bool:
	var ok: bool = data is Dictionary and data.get("type", "") == "effect_block" \
			and (data.get("from_path", []) as Array).size() > 0
	if ok and not _dragging:
		_discard_highlight = true
		_animate_to(Vector2(1.018, 1.018), Color(1.10, 0.66, 0.70, 1.0), 0.08)
	elif _discard_highlight:
		_clear_discard_highlight()
	return ok


func _drop_data(_at_position: Vector2, data) -> void:
	_clear_discard_highlight()
	var from_path: Array = data.get("from_path", [])
	if from_path.size() > 0:
		palette_drop_requested.emit(from_path)


func _notification(what: int) -> void:
	if get_meta("drag_preview",false): return
	if what == NOTIFICATION_DRAG_END:
		_dragging = false
		_clear_discard_highlight()
	elif what == NOTIFICATION_MOUSE_EXIT and _discard_highlight:
		_clear_discard_highlight()


func _process(_delta: float) -> void:
	if not _discard_highlight:
		return
	var viewport := get_viewport()
	if viewport == null or not viewport.gui_is_dragging() \
			or not get_global_rect().has_point(get_global_mouse_position()):
		_clear_discard_highlight()


func _clear_discard_highlight() -> void:
	if not _discard_highlight and modulate == Color.WHITE and scale == Vector2.ONE:
		return
	_discard_highlight = false
	_animate_to(Vector2.ONE, Color.WHITE, 0.10)
