class_name SkillConditionReporter
extends HBoxContainer

# ============================================
# Draggable boolean/logic reporter that sits inside an if block's condition
# gap (comparisons, has-buff, and and/or/not logic trees).
#
# Bare Containers do not bind Control's drag methods to GDScript, so a
# set_drag_forwarding on a plain HBoxContainer is never invoked by the GUI
# pipeline (the press falls through to the enclosing if block instead). This
# scripted subclass implements the drag source directly:
#   - drag out of the gap -> drop on the palette removes the condition
#     (payload carries from_cond_slot), or drop into another if gap moves it
#   - drops from the palette (or another reporter) are forwarded to the
#     owning block's _drop_condition so the gap keeps working when filled.
# ============================================

var block: Node           # owning SkillBlock (for _drop_condition)
var _condition: Dictionary
var _condition_path: Array
var _drag_parent: WeakRef


func setup(p_block: Node, p_cond: Dictionary, p_path: Array) -> void:
	tooltip_text = SkillHelp.description("logic", str(p_cond.get("logic"))) if p_cond.has("logic") else SkillHelp.description("boolean", "has_buff" if p_cond.get("op", "") == "has" else "compare")
	block = p_block
	_condition = p_cond
	_condition_path = p_path
	# STOP so this reporter (not the if block) is the drag source. The GUI
	# pipeline calls Control.get_drag_data, which invokes the forwarding
	# callbacks below (a bare GDVIRTUAL _get_drag_data is not consulted), so
	# wire the script methods through set_drag_forwarding like ValueSlot does.
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_drag_forwarding(
		Callable(self, "_slot_get_drag_data"),
		Callable(self, "_can_drop_data"),
		Callable(self, "_drop_data"),
	)


func _slot_get_drag_data(_pos: Vector2):
	var condition := SkillBlock.condition_at_path(_condition, []).duplicate(true)
	if condition.is_empty():
		return null
	var socket: Control = get_parent()
	_drag_parent = weakref(socket)
	socket.modulate.a = 0.48
	var point := get_global_transform() * _pos
	var grab := socket.get_global_transform().affine_inverse() * point
	var preview := SkillBlock.make_condition_preview(condition)
	preview.scale = socket.get_global_transform().get_scale()
	preview.position = -grab * preview.scale
	preview.size = preview.get_combined_minimum_size()
	preload("res://SkillDragPreview.gd").show(self, preview)
	return {
		"type": "boolean_block",
		"boolean": condition,
		"from_cond_slot": block,
		"from_condition_path": _condition_path.duplicate(),
		"grab_offset": [grab.x, grab.y],
	}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_parent != null:
		var socket = _drag_parent.get_ref()
		if socket != null: socket.modulate.a = 1.0
		_drag_parent = null



# Filled reporter: accept palette drops (and other reporters) and forward them
# to the if gap so replacing the condition still works.
func _can_drop_data(_pos: Vector2, data) -> bool:
	var socket := get_parent()
	return socket != null and socket.has_method("_can_drop_data") and socket._can_drop_data(_pos, data)


func _drop_data(_pos: Vector2, data) -> void:
	var socket := get_parent()
	if socket != null and socket.has_method("_drop_data"):
		socket._drop_data(_pos, data)
