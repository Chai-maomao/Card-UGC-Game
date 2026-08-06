class_name SkillUndoManager
extends RefCounted

# ============================================
# Undo / redo history for the skill editor.
# Pure state: owns the undo/redo stacks and a deep-equality check. The editor
# forwards a snapshot of its FULL editing state (trigger + effect list +
# skill metadata) so every mutation — structural or settings-level — can be
# undone. maybe_snapshot() is called after a mutation; undo()/redo() return
# the restored state.
# ============================================

var undo_stack: Array = []
var redo_stack: Array = []
var last_state: Variant = null
var limit := 50


func init_from(state: Variant) -> void:
	undo_stack.clear()
	redo_stack.clear()
	last_state = _dup(state)


# Pushes the previous committed state when `state` differs from it (call AFTER
# a mutation). Repeated parameter changes each push one step, so a 3→5→7 edit
# undoes to 5 then to 3.
func maybe_snapshot(state: Variant) -> void:
	# Before any init_from() (e.g. settings controls setting their initial
	# value during _ready), just record the baseline — nothing to undo yet.
	if last_state == null:
		last_state = _dup(state)
		return
	if deep_equal(last_state, state):
		return
	undo_stack.append(_dup(last_state))
	if undo_stack.size() > limit:
		undo_stack.pop_front()
	redo_stack.clear()
	last_state = _dup(state)


func can_undo() -> bool:
	return not undo_stack.is_empty()


func can_redo() -> bool:
	return not redo_stack.is_empty()


func undo(state: Variant) -> Variant:
	if undo_stack.is_empty():
		return state
	redo_stack.append(_dup(state))
	var restored: Variant = undo_stack.pop_back()
	last_state = _dup(restored)
	return restored


func redo(state: Variant) -> Variant:
	if redo_stack.is_empty():
		return state
	undo_stack.append(_dup(state))
	var restored: Variant = redo_stack.pop_back()
	last_state = _dup(restored)
	return restored


static func _dup(v: Variant) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v


static func deep_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key in da:
			if not db.has(key) or not deep_equal(da[key], db[key]):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in range(aa.size()):
			if not deep_equal(aa[i], ab[i]):
				return false
		return true
	return a == b
