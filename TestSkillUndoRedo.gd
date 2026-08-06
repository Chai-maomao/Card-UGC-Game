extends Node

# ============================================
# Undo / redo regression tests for the skill editor.
# Every structural edit (add / delete / move / duplicate / drop / condition)
# and every inline parameter change must be undoable (Ctrl+Z) and redoable
# (Ctrl+Y); the undo stack is capped at 50 entries.
# ============================================

var failures: Array = []


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.card_draft = {
		"name": "撤销测试",
		"cost": 2,
		"hp": 4,
		"atk": 2,
		"gender": "male",
		"card_type": "minion",
		"art_path": "",
		"skill1": {},
		"skill2": {},
		"skill3": {},
	}
	PlayerData.editing_skill_index = 1
	var scene: PackedScene = load("res://SkillEditor.tscn")
	var sed: Node = scene.instantiate()
	add_child(sed)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Add -> undo -> redo ------------------------------------------------
	sed.call("_add_effect_block", SkillEngine.EFFECT_DAMAGE)
	_assert(_eff_count(sed) == 1, "add block failed")
	sed.call("_undo")
	_assert(_eff_count(sed) == 0, "undo add failed")
	sed.call("_redo")
	_assert(_eff_count(sed) == 1, "redo add failed")

	# --- Inline parameter change is undoable --------------------------------
	var ed: Array = sed.get("effect_data")
	ed[0]["value"] = 7
	sed.call("_on_block_changed", [0])
	sed.call("_undo")
	ed = sed.get("effect_data")
	_assert(int(ed[0].get("value", -1)) == 1, "undo param change failed (value=%s)" % str(ed[0].get("value", "?")))
	sed.call("_redo")
	ed = sed.get("effect_data")
	_assert(int(ed[0].get("value", -1)) == 7, "redo param change failed (value=%s)" % str(ed[0].get("value", "?")))

	# --- Delete -> undo restores the removed block --------------------------
	sed.call("_add_effect_block", SkillEngine.EFFECT_HEAL)
	_assert(_eff_count(sed) == 2, "second add failed")
	sed.call("_on_block_delete_path", [0])
	_assert(_eff_count(sed) == 1, "delete failed")
	sed.call("_undo")
	ed = sed.get("effect_data")
	_assert(ed.size() == 2, "undo delete failed (size=%d)" % ed.size())

	# --- Move (reorder) -> undo restores the original order -----------------
	sed.call("_on_block_move_path", [0], 1)
	ed = sed.get("effect_data")
	_assert(str(ed[0].get("effect", "")) == SkillEngine.EFFECT_HEAL, "move failed (first=%s)" % str(ed[0].get("effect", "")))
	sed.call("_undo")
	ed = sed.get("effect_data")
	_assert(str(ed[0].get("effect", "")) == SkillEngine.EFFECT_DAMAGE, "undo move failed (first=%s)" % str(ed[0].get("effect", "")))

	# --- Duplicate -> undo --------------------------------------------------
	sed.call("_duplicate_effect", [0])
	ed = sed.get("effect_data")
	_assert(ed.size() == 3, "duplicate failed (size=%d)" % ed.size())
	sed.call("_undo")
	_assert(_eff_count(sed) == 2, "undo duplicate failed")

	# --- Nested drop (if block + effect into then slot) -> undo -------------
	sed.call("_add_if_block")
	_assert(_eff_count(sed) == 3, "add if block failed")
	sed.call("_apply_drop", {"type": "effect_block", "effect_id": SkillEngine.EFFECT_DAMAGE}, [2, "then"], 0)
	ed = sed.get("effect_data")
	var then_list: Array = ed[2].get("then_effects", [])
	_assert(then_list.size() == 1, "nested drop failed (then=%d)" % then_list.size())
	sed.call("_undo")
	ed = sed.get("effect_data")
	then_list = ed[2].get("then_effects", [])
	_assert(then_list.is_empty(), "undo nested drop failed (then=%d)" % then_list.size())
	sed.call("_redo")
	ed = sed.get("effect_data")
	then_list = ed[2].get("then_effects", [])
	_assert(then_list.size() == 1, "redo nested drop failed (then=%d)" % then_list.size())

	# --- Condition drop -> undo ---------------------------------------------
	var bool_cond := {
		"op": SkillEngine.CONDITION_OP_GTE,
		"lhs": {"kind": "num", "value": 1},
		"rhs": {"kind": "num", "value": 1},
	}
	sed.call("_on_block_condition_dropped", [2], bool_cond)
	ed = sed.get("effect_data")
	_assert(ed[2].get("condition", {}).has("lhs"), "condition drop failed")
	sed.call("_undo")
	ed = sed.get("effect_data")
	_assert(ed[2].get("condition", {}).is_empty(), "undo condition drop failed: %s" % str(ed[2].get("condition", {})))

	# --- Keyboard shortcut on a fresh history --------------------------------
	var k_ed: Array = sed.get("effect_data")
	k_ed.clear()
	sed.call("_reset_undo_history")
	sed.call("_refresh_script")
	sed.call("_add_effect_block", SkillEngine.EFFECT_DAMAGE)
	_assert(_eff_count(sed) == 1, "keyboard prep add failed")
	var z_ev := InputEventKey.new()
	z_ev.keycode = Key.KEY_Z
	z_ev.ctrl_pressed = true
	z_ev.pressed = true
	sed.call("_unhandled_key_input", z_ev)
	_assert(_eff_count(sed) == 0, "Ctrl+Z did not undo add")
	var y_ev := InputEventKey.new()
	y_ev.keycode = Key.KEY_Y
	y_ev.ctrl_pressed = true
	y_ev.pressed = true
	sed.call("_unhandled_key_input", y_ev)
	_assert(_eff_count(sed) == 1, "Ctrl+Y did not redo add")

	# --- Undo stack capped at 50 --------------------------------------------
	sed.call("_reset_undo_history")
	for i in range(60):
		sed.call("_add_effect_block", SkillEngine.EFFECT_DAMAGE)
	var undo_mgr: SkillUndoManager = sed.get("_undo_mgr")
	_assert(undo_mgr.undo_stack.size() <= 50, "undo stack exceeded 50 (size=%d)" % undo_mgr.undo_stack.size())
	_assert(undo_mgr.redo_stack.is_empty(), "redo stack should clear after new edits (size=%d)" % undo_mgr.redo_stack.size())

	if failures.is_empty():
		print("TEST_SKILL_UNDO_REDO_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _eff_count(sed: Node) -> int:
	return (sed.get("effect_data") as Array).size()


func _assert(cond: bool, message: String) -> void:
	if not cond:
		failures.append(message)
