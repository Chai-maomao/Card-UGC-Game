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
var condition_id: String = ""   # legacy condition reporter (kept for compat)
var var_id: String = ""         # variable reporter oval
var boolean_kind: String = ""   # "compare" / "has_buff" boolean block
var expr_kind: String = ""      # math reporter: "+" / "-" / "*" / "/" / "rand"
var logic_kind: String = ""     # logic reporter: "and" / "or" / "not"
var target_kind: String = ""    # target reporter: single / sides / all / self / self_sides
var side_kind: String = ""      # side reporter: enemy / ally / all


func _get_drag_data(_at_position: Vector2):
	var preview := duplicate()
	preview.modulate.a = 0.7
	var drag_control := Control.new()
	drag_control.add_child(preview)
	set_drag_preview(drag_control)
	if var_id != "":
		return {"type": "var_block", "var_id": var_id}
	if expr_kind != "":
		return {"type": "expr_block", "expr_kind": expr_kind}
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
	return {"type": "effect_block", "effect_id": effect_id, "from_index": -1}


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
		"lhs": {"kind": "num", "value": 1},
		"rhs": {"kind": "num", "value": 1},
	}


# The palette is a drop-to-discard zone: dropping a script block onto any
# palette button deletes it. (The palette panel itself is also a target, but
# its buttons sit on top with mouse_filter STOP, so each button must forward
# the drop itself — otherwise the drag would be discarded over button areas.)
func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.get("type", "") == "effect_block" \
			and (data.get("from_path", []) as Array).size() > 0


func _drop_data(_at_position: Vector2, data) -> void:
	var from_path: Array = data.get("from_path", [])
	if from_path.size() > 0:
		palette_drop_requested.emit(from_path)
