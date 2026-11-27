extends "res://TestSkillWorkspaceVisual.gd"

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	Input.use_accumulated_input = false
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.editing_skill_index = 0
	PlayerData.init_card_draft()
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	if "--offset-move-only" in OS.get_cmdline_user_args():
		var passed := await _verify_offset_move()
		if passed: print("TEST_SKILL_OFFSET_MOVE_VISUAL_OK")
		get_tree().quit(0 if passed else 1)
		return
	editor._add_if_block()
	editor._add_if_block()
	editor.workbench.workspace.set_zoom(0.62)
	await _settle()
	await _palette_drop("logic_kind", "and", _socket(0, []))
	assert(editor.effect_data[0].condition == {"logic":"and", "lhs":{}, "rhs":{}}, "new logic must expose two empty typed sockets")
	var issues: Array = []
	SkillErrorChecker.new().walk_issues(editor.effect_data, issues, [])
	assert(issues.filter(func(issue): return issue.get("condition_path", []) in [["lhs"], ["rhs"]]).size() == 2, "both empty inner sockets must block compilation")
	editor.validation_requested = true
	editor._mark_invalid_conditions()
	assert(_socket(0, ["lhs"]).has_node("ValidationOutline") and _socket(0, ["rhs"]).has_node("ValidationOutline"), "validation must identify the actual empty inner sockets")
	await _palette_drop("var_id", SkillEngine.VAR_HAND_COUNT, _socket(0, ["lhs"]))
	assert(editor.effect_data[0].condition.lhs.is_empty(), "a numeric reporter cannot fill a hexagonal condition socket")
	await _palette_drop("boolean_kind", "compare", _socket(0, ["lhs"]))
	await _palette_drop("logic_kind", "not", _socket(0, ["rhs"]))
	await _palette_drop("boolean_kind", "compare", _socket(0, ["rhs", "child"]))
	assert(editor.effect_data[0].condition.rhs.child.has("op"), "nested condition must go into the hovered inner socket")
	# This fixture evaluates complete comparisons; fresh palette sockets are
	# intentionally empty, so enter its literal operands explicitly.
	editor.effect_data[0].condition.lhs.rhs.merge({"kind":"num", "value":1})
	editor.effect_data[0].condition.rhs.child.lhs.merge({"kind":"num", "value":1})
	editor.effect_data[0].condition.rhs.child.rhs.merge({"kind":"num", "value":1})
	var lhs := _socket(0, ["lhs"])
	var values := lhs.find_children("*", "ValueSlot", true, false)
	assert(values.size() == 2)
	await _palette_drop("expr_kind", "+", values[0])
	assert(editor.effect_data[0].condition.lhs.lhs.kind == "expr")
	editor.effect_data[0].condition.lhs.lhs.a.merge({"kind":"num", "value":1})
	editor.effect_data[0].condition.lhs.lhs.b.merge({"kind":"num", "value":1})
	editor._refresh_script()
	await _settle()
	lhs = _socket(0, ["lhs"])
	values = lhs.find_children("*", "ValueSlot", true, false)
	await _palette_drop("var_id", SkillEngine.VAR_HAND_COUNT, values[1])
	assert(editor.effect_data[0].condition.lhs.lhs.a.kind == "var", "variable must nest inside arithmetic inside comparison")
	# Move a numeric reporter between sibling slots as a single undo step.
	values = _socket(0, ["lhs"]).find_children("*", "ValueSlot", true, false)
	var numeric_before: Dictionary = editor.effect_data[0].condition.duplicate(true)
	await _drag(values[1].get_global_transform() * Vector2(3, values[1].size.y / 2), values[2].get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data[0].condition.lhs.lhs.a.kind == "num" and editor.effect_data[0].condition.lhs.lhs.b.kind == "var", "numeric reporter must move to the matching sibling slot")
	editor._undo()
	await _settle()
	assert(editor.effect_data[0].condition == numeric_before, "one undo must restore both numeric sockets")
	var saved: Dictionary = editor.effect_data[0].condition.duplicate(true)
	# Dragging a filled nested condition must move just that subtree.
	var source := _socket(0, ["rhs", "child"])
	await _drag(source.get_global_transform() * Vector2(7, source.size.y / 2), _socket(1, []).get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data[0].condition.rhs.child.is_empty() and editor.effect_data[1].condition.has("op"), "moving a nested leaf must clear only its old socket")
	editor._undo()
	await _settle()
	assert(editor.effect_data[0].condition == saved and editor.effect_data[1].get("condition", {}).is_empty(), "one undo must restore both ends of a condition move")
	# Move the full logic reporter: retain every nested numeric expression.
	source = _socket(0, [])
	await _drag(source.get_global_transform() * Vector2(7, source.size.y / 2), _socket(1, []).get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data[0].get("condition", {}).is_empty() and editor.effect_data[1].condition == saved, "moving a logic tree must preserve all descendants")
	# Invalid shapes and self-descendant drops cannot advertise acceptance.
	var block: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(1)
	var root_reporter = _socket(1, []).get_child(0)
	assert(not block._can_drop_condition_at(["lhs"], root_reporter.payload), "cannot nest a condition inside itself")
	assert(not block._can_drop_condition_at([], {"type":"var_block", "var_id":SkillEngine.VAR_HAND_COUNT}))
	assert(not _socket(1, ["lhs"]).find_children("*", "ValueSlot", true, false)[0]._can_drop_var(Vector2.ZERO, {"type":"boolean_block", "boolean":saved}))
	editor.workbench.workspace.set_zoom(0.44)
	await _settle()
	var canvas: Control = editor.workbench.workspace
	var blank := canvas.global_position + Vector2(350, 420)
	await _drag(blank, blank + Vector2(-160, 0), MOUSE_BUTTON_MIDDLE)
	await _settle()
	await _capture("typed-nesting")
	# Saving and executing the edited tree must agree with the visible nesting.
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var unit := CardData.new("测试者", 0, 5, 1)
	var context := {"active_hand":[unit, unit, unit]}
	assert(SkillEngine._eval_operand(roundtrip.lhs.lhs, unit, unit, context) == 4, "nested hand-count plus one must evaluate to four")
	assert(not SkillEngine._eval_boolean(roundtrip, unit, unit, context))
	roundtrip.rhs.child.rhs.value = 2
	assert(SkillEngine._eval_boolean(roundtrip, unit, unit, context), "nested arithmetic and NOT must produce the expected result after roundtrip")
	var legacy := {"logic":"not", "child":{"condition_type":SkillEngine.CONDITION_HAND_COUNT, "condition_op":SkillEngine.CONDITION_OP_GTE, "condition_value":4}}
	assert(SkillEngine._eval_boolean(legacy, unit, unit, context), "nested legacy reporters must keep their actual comparison")
	await _verify_reporter_exchange()
	if not await _verify_offset_move():
		get_tree().quit(1)
		return
	await _verify_status_picker()
	editor.queue_free()
	await get_tree().process_frame
	print("TEST_SKILL_NESTING_VISUAL_OK")
	get_tree().quit(0)

func _verify_offset_move() -> bool:
	var effect := {"effect":SkillEngine.EFFECT_DAMAGE, "target":SkillEngine.TARGET_SELF,
			"value_var":SkillEngine.VAR_HAND_COUNT, "value_offset":-2}
	var expression := ValueSlot.make_expression("+")
	expression.b = {"kind":"num", "value":4}
	var destination := {"effect":SkillEngine.EFFECT_DAMAGE, "target":SkillEngine.TARGET_SELF, "value_expr":expression}
	editor.effect_data = [effect, destination]
	editor.loose_reporters.clear()
	editor.workbench.workspace.reset_view()
	editor._refresh_script()
	editor._maybe_snapshot()
	await _settle()
	var script_body: VBoxContainer = editor.effects_list.get_child(0).body_container
	var origin: ValueSlot = script_body.get_child(0).find_children("*", "ValueSlot", true, false)[0]
	var canvas: Control = editor.workbench.workspace
	var blank := canvas.global_position + canvas.size * Vector2(0.59, 0.66)
	await _drag(origin.get_global_transform() * Vector2(3, origin.size.y / 2), blank, MOUSE_BUTTON_LEFT)
	await _settle()
	if effect.has("value_var") or editor.loose_reporters.size() != 1:
		push_error("Dragging the variable onto the canvas must leave its source empty and create one reporter")
		return false
	var key: String = editor.loose_reporters.keys()[0]
	var record: Dictionary = editor.loose_reporters[key]
	if record.value.get("offset", 0) != -2:
		push_error("Dragging a variable onto the canvas lost its offset")
		return false
	var workspace: Dictionary = JSON.parse_string(JSON.stringify(editor._workspace_metadata()))
	editor._restore_workspace(workspace)
	editor._refresh_script()
	await _settle()
	var loose: ValueSlot = canvas.find_child("Reporter_%s" % key, true, false).get_child(0)
	script_body = editor.effects_list.get_child(0).body_container
	var operand: ValueSlot = script_body.get_child(1).find_children("*", "ValueSlot", true, false)[1]
	await _drag(loose.get_global_transform() * Vector2(3, loose.size.y / 2), operand.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await _settle()
	var card := CardData.new("测试者", 0, 5, 1)
	var context := {"active_hand":[card, card, card]}
	if not editor.loose_reporters.is_empty() or SkillEngine._eval_operand(expression, card, card, context) != 5:
		push_error("Moving the reporter into an arithmetic socket must retain its negative offset after reopening")
		return false
	await _capture("reporter-offset-move")
	return true

func _verify_reporter_exchange() -> void:
	var left := {"kind":"var", "var_id":SkillEngine.VAR_EMPTY_ENEMY}
	for right in [{"kind":"var", "var_id":SkillEngine.VAR_HAND_COUNT}, ValueSlot.make_expression("+")]:
		var expression := ValueSlot.make_expression("rand")
		expression.a = left.duplicate(true)
		expression.b = right.duplicate(true)
		editor.effect_data = [{"effect":SkillEngine.EFFECT_DAMAGE, "target":SkillEngine.TARGET_SELF, "value_expr":expression}]
		editor._refresh_script()
		editor._maybe_snapshot()
		editor.workbench.workspace.reset_view()
		await _settle()
		var block: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(0)
		var outer: ValueSlot = block.find_children("*", "ValueSlot", true, false)[0]
		var row := outer.get_child(0)
		var source: ValueSlot = row.get_child(0)
		var destination: ValueSlot = row.get_child(2)
		var before: Dictionary = editor._editor_state().duplicate(true)
		await _drag(source.get_global_transform() * Vector2(3, source.size.y / 2), destination.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		await _settle()
		assert(expression.a == right and expression.b == left, "dropping onto an occupied reporter must exchange complete values without losing either operand")
		await _capture("reporter-exchange-" + str(right.kind))
		var after: Dictionary = editor._editor_state().duplicate(true)
		editor._undo()
		await _settle()
		assert(editor._editor_state() == before, "one undo must restore both exchanged reporters")
		editor._redo()
		await _settle()
		assert(editor._editor_state() == after, "one redo must exchange both reporters together")

func _socket(index: int, path: Array) -> Control:
	var block: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(index)
	if path.is_empty(): return block.cond_slot
	for node in block.find_children("*", "PanelContainer", true, false):
		if node.get_script() == preload("res://SkillConditionSocket.gd") and node.condition_path == path: return node
	assert(false, "missing condition socket: %s" % [path])
	return null

func _palette_drop(field: String, value: String, target: Control) -> void:
	var button: SkillPaletteBlock
	for candidate in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if str(candidate.get(field)) == value:
			button = candidate
			break
	assert(button != null)
	# Search reveals collapsed drawers without relying on their scroll position.
	editor.palette_search.text = button.text
	editor._filter_palette(button.text)
	await _settle()
	var scroll: ScrollContainer = editor.palette_vbox.get_parent()
	scroll.ensure_control_visible(button)
	await _settle()
	await _drag(button.get_global_rect().get_center(), target.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await _settle()

func _verify_status_picker() -> void:
	editor.effect_data.clear()
	editor._add_effect_block(SkillEngine.EFFECT_ADD_BUFF)
	editor.effect_data[0].target = SkillEngine.TARGET_SELF
	editor._refresh_script()
	await _settle()
	editor.workbench.workspace.reset_view()
	await _settle()
	var block: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(0)
	var picker: OptionButton
	for candidate in block.find_children("*", "OptionButton", true, false):
		if candidate.item_count > SkillRegistry.BUFF_IDS.size(): picker = candidate
	assert(picker != null, "status picker must expose grouped sections")
	for buff in SkillRegistry.BUFF_IDS:
		preload("res://SkillStatusPicker.gd").select_value(picker, buff)
		picker.item_selected.emit(picker.selected)
		assert(editor.effect_data[0].buff_id == buff, "grouping must preserve each status's actual ID")
	await _settle()
	for candidate in block.find_children("*", "OptionButton", true, false):
		if candidate.item_count > SkillRegistry.BUFF_IDS.size(): picker = candidate
	await _click(picker.get_global_rect().get_center())
	assert(picker.get_popup().visible, "actual click must open the Chinese status menu")
	await _capture("grouped-status-picker")
	picker.get_popup().hide()
	Locale.language = "en"
	preload("res://SkillStatusPicker.gd").fill(picker, SkillRegistry.BUFF_STUN)
	await _settle()
	await _click(picker.get_global_rect().get_center())
	assert(picker.get_popup().visible, "actual click must open the English status menu")
	await _capture("grouped-status-picker-en")
	picker.get_popup().hide()
	Locale.language = "zh"
	editor._on_block_edit_path([0])
	await _settle()
	var form: SkillEffectForm
	for candidate in editor.get_children():
		if candidate is SkillEffectForm: form = candidate
	assert(form != null)
	for buff in SkillRegistry.BUFF_IDS:
		preload("res://SkillStatusPicker.gd").select_value(form._buff_sel, buff)
		form._buff_sel.item_selected.emit(form._buff_sel.selected)
		assert(form._preview_dict().buff_id == buff, "advanced form must preserve grouped status IDs too")
		assert(form._val_spin.editable == SkillRegistry.buff_uses_value(buff), "status value controls must follow the selected status")
	preload("res://SkillStatusPicker.gd").select_value(form._buff_sel, SkillRegistry.BUFF_LUCK)
	form._buff_sel.item_selected.emit(form._buff_sel.selected)
	form._on_ok()
	await _settle()
	assert(editor.effect_data[0].buff_id == SkillRegistry.BUFF_LUCK, "advanced form confirmation must save the actual selected status")
