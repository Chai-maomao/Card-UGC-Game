extends "res://TestSkillNestingVisual.gd"

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
	await _categories()
	editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
	await _settle()
	var effect: Dictionary = editor.effect_data[0]
	assert(not effect.has("value") and effect.get("target", "") == "")
	var block: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(0)
	var value: ValueSlot = block.find_children("*", "ValueSlot", true, false)[0]
	var input: LineEdit = value.find_children("*", "LineEdit", true, false)[0]
	assert(input.text == "" and input.get_global_rect().is_equal_approx(value.get_global_rect()), "the editable white field must occupy the full socket without a second shell")
	await _click(input.get_global_rect().get_center())
	await _settle()
	assert(input.text == "" and not effect.has("value"), "focusing an empty number must not insert zero")
	await _capture("empty-number-focused")
	await _click(editor.skill_name_input.get_global_rect().get_center())
	await _settle()
	assert(input.text == "" and not effect.has("value"), "leaving an untouched number must keep it empty")
	await _number(value, "0")
	assert(effect.has("value") and effect.value == 0, "explicit zero must remain distinct from an empty socket")
	await _number(value, "")
	assert(not effect.has("value") and input.text == "", "deleting a literal must restore an empty socket")
	var target: TargetSlot
	for slot in block.find_children("*", "TargetSlot", true, false):
		if slot.kind == "target": target = slot
	assert(target.get_child(0).text == "" and target._slot_get_drag_data(Vector2.ZERO) == null)
	await _palette_drop("target_kind", SkillEngine.TARGET_SINGLE, target)
	var side: TargetSlot
	for slot in block.find_children("*", "TargetSlot", true, false):
		if slot.kind == "side": side = slot
	await _palette_drop("side_kind", SkillEngine.TARGET_SIDE_ENEMY, side)
	await _palette_drop("expr_kind", "rand", value)
	assert(effect.value_expr.a.is_empty() and effect.value_expr.b.is_empty(), "fresh random reporters must have two unfilled operands")
	var operands := value.find_children("*", "ValueSlot", true, false)
	assert(operands.size() == 2)
	for operand in operands:
		assert(operand.find_children("*", "LineEdit", true, false)[0].text == "")
	var issues: Array = editor._error_checker.collect_issues()
	assert(issues.filter(func(issue): return issue.get("kind") == "value").size() == 2, "compilation must identify both missing operands")
	await _number(operands[0], "1")
	await _number(operands[1], "2")
	assert(editor._collect_errors().is_empty())
	assert(editor.workbench.compile_preview())
	var description: String = editor._format_skill(editor._build_skill())
	assert(description.contains("1~2") and not description.contains("随机"), "skill descriptions must use the compact a~b range")
	await _capture("random-blue-compiled")
	await _palette_drop("var_id", SkillEngine.VAR_HAND_COUNT, operands[0])
	var canvas: Control = editor.workbench.workspace
	var blank := canvas.global_position + canvas.size * Vector2(0.55, 0.75)
	await _drag(operands[0].get_global_transform() * Vector2(3, operands[0].size.y / 2), blank, MOUSE_BUTTON_LEFT)
	await _settle()
	assert(not effect.value_expr.a.has("value") and effect.value_expr.a.get("kind") == "num")
	block = editor.effects_list.get_child(0).body_container.get_child(0)
	value = block.find_children("*", "ValueSlot", true, false)[0]
	operands = value.find_children("*", "ValueSlot", true, false)
	for slot in block.find_children("*", "TargetSlot", true, false):
		if slot.kind == "target": target = slot
	assert(operands[0].find_children("*", "LineEdit", true, false)[0].text == "", "moving the last reporter out must leave a blank numeric field")
	await _drag(target.get_global_transform() * Vector2(3, target.size.y / 2), blank + Vector2(0, 50), MOUSE_BUTTON_LEFT)
	await _settle()
	block = editor.effects_list.get_child(0).body_container.get_child(0)
	for slot in block.find_children("*", "TargetSlot", true, false):
		if slot.kind == "target": target = slot
	assert(target._current_value() == "" and target.get_child(0).text == "" and target._slot_get_drag_data(Vector2.ZERO) == null, "moving a target out must leave an empty non-draggable socket")
	await _capture("reporters-removed-empty-sockets")
	await _undo_and_reopen_draft()
	await _verify_reporter_exchange()
	await _empty_controls()
	_descriptions()
	print("TEST_SKILL_EMPTY_SLOTS_VISUAL_OK")
	get_tree().quit(0)

func _number(slot: ValueSlot, text: String) -> void:
	var input: LineEdit = slot.find_children("*", "LineEdit", true, false)[0]
	await _click(input.get_global_rect().get_center())
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_A
	key.ctrl_pressed = true
	get_viewport().push_input(key, true)
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_BACKSPACE
	get_viewport().push_input(key, true)
	for digit in text:
		key = InputEventKey.new()
		key.pressed = true
		key.keycode = digit.unicode_at(0)
		key.unicode = digit.unicode_at(0)
		get_viewport().push_input(key, true)
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ENTER
	get_viewport().push_input(key, true)
	await _settle()

func _categories() -> void:
	for name_key in ["palette_target", "palette_math", "palette_target"]:
		var title := Locale.t("skill_editor." + name_key)
		for button in editor.workbench.category_rail.get_children():
			if button.text == title:
				editor.workbench.category_rail.get_parent().ensure_control_visible(button)
				await _settle()
				await _click(button.get_global_rect().get_center())
		await _settle()
		var selected: Array = []
		for button in editor.workbench.category_rail.get_children():
			if button.button_pressed: selected.append(button.text)
		assert(selected == [title], "clicked category must stay selected even at the scrollbar limit")
		for header in editor.palette_vbox.get_children():
			if header is Button and header.get_meta("section_title", "") == title:
				assert(header.text.begins_with("-"), "navigation must show the expanded minus sign")
	var random_button: SkillPaletteBlock
	for button in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if button.expr_kind == "rand": random_button = button
	var header: Button = random_button.get_parent().get_parent().get_child(random_button.get_parent().get_index() - 1)
	assert(header.get_meta("section_title") == Locale.t("skill_editor.palette_math"))
	await _capture("category-target-selected")

func _undo_and_reopen_draft() -> void:
	var after: Dictionary = editor._editor_state().duplicate(true)
	editor._undo()
	await _settle()
	assert(editor.effect_data[0].get("target") == SkillEngine.TARGET_SINGLE)
	editor._redo()
	await _settle()
	assert(editor._editor_state() == after)
	var workspace: Dictionary = editor._workspace_metadata()
	editor._restore_workspace(workspace)
	assert(editor.loose_reporters.size() == 2, "detached reporters must survive draft serialization")

func _empty_controls() -> void:
	editor.effect_data.clear()
	editor.loose_groups.clear()
	editor.loose_reporters.clear()
	editor._add_repeat_block()
	editor._add_if_block()
	editor._refresh_script()
	await _settle()
	var body: VBoxContainer = editor.effects_list.get_child(0).body_container
	assert(not editor.effect_data[0].has("repeat_count"))
	assert(body.get_child(0).then_container.get_child_count() == 0)
	assert(body.get_child(1).cond_slot.get_child_count() == 0)
	await _palette_drop("boolean_kind", "compare", body.get_child(1).cond_slot)
	assert(editor.effect_data[1].condition.lhs.is_empty() and editor.effect_data[1].condition.rhs.is_empty())
	editor._apply_drop({"type":"effect_block", "effect_id":SkillEngine.EFFECT_HEAL}, [0, "then"], 0)
	editor.effect_data[0].then_effects[0].merge({"target":SkillEngine.TARGET_SELF, "value":2})
	editor._refresh_script()
	editor.workbench.workspace.reset_view()
	await _settle()
	body = editor.effects_list.get_child(0).body_container
	var last: Control = body.get_child(0).then_container.get_child(0)
	var canvas: Control = editor.workbench.workspace
	var blank := canvas.global_position + canvas.size * Vector2(0.78, 0.7)
	await _drag(last.get_global_transform() * Vector2(10, 12), blank, MOUSE_BUTTON_LEFT)
	await _settle()
	body = editor.effects_list.get_child(0).body_container
	assert(editor.effect_data[0].then_effects.is_empty() and body.get_child(0).then_container.get_child_count() == 0, "removing the final nested statement must leave an empty cavity")
	var condition: Control = body.get_child(1).cond_slot.get_child(0)
	await _drag(condition.get_global_transform() * Vector2(4, condition.size.y / 2), blank - Vector2(0, 80), MOUSE_BUTTON_LEFT)
	await _settle()
	body = editor.effects_list.get_child(0).body_container
	assert(editor.effect_data[1].get("condition", {}).is_empty() and body.get_child(1).cond_slot.get_child_count() == 0, "removing the final condition must leave an empty hexagonal socket")
	await _capture("empty-nested-controls")

func _descriptions() -> void:
	for buff in SkillRegistry.BUFF_IDS:
		if SkillRegistry.buff_uses_value(buff): continue
		var effect := {"effect":SkillEngine.EFFECT_ADD_BUFF, "buff_id":buff, "target":SkillEngine.TARGET_SELF, "duration":2}
		var clean := SkillTextFormatter.format_effect_sentence(effect)
		effect.merge({"value":987, "value_expr":ValueSlot.make_expression("rand"), "value_var":SkillEngine.VAR_HAND_COUNT})
		assert(SkillTextFormatter.format_effect_sentence(effect) == clean, "unused strength must never appear in status descriptions")
