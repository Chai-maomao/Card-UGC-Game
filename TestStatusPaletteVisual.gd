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
	var status_buttons: Array = []
	for candidate in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if candidate.buff_id != "": status_buttons.append(candidate)
	assert(status_buttons.size() == SkillRegistry.BUFF_IDS.size())
	for button in status_buttons:
		button.pressed.emit()
		assert(editor.effect_data.back().effect == SkillEngine.EFFECT_ADD_BUFF and editor.effect_data.back().buff_id == button.buff_id, "each status shortcut must create the selected status")
	editor.effect_data.clear()
	editor._refresh_script()
	editor.workbench.workspace.set_zoom(0.75)
	await _settle()
	var self_reporter: SkillPaletteBlock
	for candidate in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if candidate.target_kind == SkillEngine.TARGET_SELF:
			self_reporter = candidate
			break
	for buff in [SkillEngine.BUFF_DODGE, SkillEngine.BUFF_UNTARGETABLE, SkillEngine.BUFF_LUCK]:
		var button := _status_button(buff)
		await _reveal(button)
		await _click(button.get_global_rect().get_center())
		await _settle()
		var status_block: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(editor.effect_data.size() - 1)
		var values := status_block._sentence_row.find_children("*", "ValueSlot", true, false)
		assert(_picker(status_block).text == Locale.term("buff", buff), "the status dropdown must display the clicked preset")
		assert(editor.effect_data.back().duration == 1)
		if buff == SkillEngine.BUFF_DODGE:
			assert(values.size() == 1 and values[0].clamp_input and not status_block.tooltip_text.contains("明确"))
			await _enter_number(values[0], "50")
		elif buff == SkillEngine.BUFF_LUCK:
			assert(values.size() == 1 and values[0].clamp_input)
			await _enter_number(values[0], "25")
		else:
			assert(values.is_empty(), "Untargetable does not require a numeric value")
		var target: TargetSlot = status_block._sentence_row.find_children("*", "TargetSlot", true, false)[0]
		await _reveal(self_reporter)
		await _drag(self_reporter.get_global_rect().get_center(), target.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		await _settle()
		assert(editor.effect_data.back().target == SkillEngine.TARGET_SELF)
	await _capture("dodge-and-untargetable")
	await _click(editor.workbench.compile_button.get_global_rect().get_center())
	await _settle()
	assert(editor.workbench.has_compiled, "the statuses must compile after choosing their targets")
	var compiled: Array = editor.workbench.card_preview.current_card_data.skills[0].effects
	assert(compiled[0].buff_id == SkillEngine.BUFF_DODGE and compiled[0].value == 50)
	assert(compiled[1].buff_id == SkillEngine.BUFF_UNTARGETABLE)
	assert(compiled[2].buff_id == SkillEngine.BUFF_LUCK and compiled[2].value == 25)
	editor.effect_data.clear()
	editor._refresh_script()
	editor.workbench.workspace.reset_view()
	await _settle()
	await _reveal(_status_button(SkillEngine.BUFF_STUN))
	await _click(_status_button(SkillEngine.BUFF_STUN).get_global_rect().get_center())
	await _settle()
	var block := _first_block()
	assert(block._sentence_row.find_children("*", "ValueSlot", true, false).is_empty(), "stun must have no strength input")
	var duration_inputs := block._sentence_row.find_children("*", "SpinBox", true, false)
	assert(duration_inputs.size() == 1, "stun must have an editable duration")
	var duration_input: SpinBox = duration_inputs[0]
	duration_input.value = 2
	assert(editor._build_skill().effects[0].duration == 2, "the edited stun duration must survive skill compilation")
	assert(block.tooltip_text == SkillHelp.description("buff", SkillEngine.BUFF_STUN))
	assert(not block.tooltip_text.contains("留在") and block.tooltip_text.contains("不能普通攻击"))
	var motion := InputEventMouseMotion.new()
	motion.position = block.get_global_transform() * Vector2(35, 12)
	motion.global_position = motion.position
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(0.7).timeout
	await _capture("stun-specific-tooltip")
	# A status selection changes both the real sentence controls and its help.
	var picker := _picker(block)
	preload("res://SkillStatusPicker.gd").select_value(picker, SkillEngine.BUFF_REGEN)
	picker.item_selected.emit(picker.selected)
	await _settle()
	assert(block.tooltip_text == SkillHelp.description("buff", SkillEngine.BUFF_REGEN))
	var slot: ValueSlot = block._sentence_row.find_children("*", "ValueSlot", true, false)[0]
	slot._drop_var(Vector2.ZERO, {"type":"var_block", "var_id":SkillEngine.VAR_HAND_COUNT})
	assert(editor.effect_data[0].has("value_var"))
	picker = _picker(block)
	preload("res://SkillStatusPicker.gd").select_value(picker, SkillEngine.BUFF_SILENCE)
	picker.item_selected.emit(picker.selected)
	await _settle()
	assert(not editor.effect_data[0].has("value_var") and block._sentence_row.find_children("*", "ValueSlot", true, false).is_empty(), "switching to silence must remove obsolete reporters")
	picker = _picker(block)
	preload("res://SkillStatusPicker.gd").select_value(picker, SkillEngine.BUFF_DAMAGE_REDUCTION)
	picker.item_selected.emit(picker.selected)
	await _settle()
	slot = block._sentence_row.find_children("*", "ValueSlot", true, false)[0]
	var input: LineEdit = slot.get_child(0)
	await _enter_number(slot, "180")
	assert(editor.effect_data[0].value == 100 and input.text == "100", "fixed percentages cannot exceed 100")
	await _enter_number(slot, "-10")
	assert(editor.effect_data[0].value == 0, "fixed percentages cannot be negative")
	# Test both statement insertion and free-workspace drag payloads.
	var poison := _status_button(SkillEngine.BUFF_POISON)
	await _reveal(poison)
	var block_bounds := block.get_global_rect()
	var grab := Vector2(12, 12)
	await _drag(poison.get_global_rect().position + grab, Vector2(block_bounds.position.x, block_bounds.end.y) + grab, MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data.any(func(effect): return effect.get("buff_id") == SkillEngine.BUFF_POISON))
	var thorns := _status_button(SkillEngine.BUFF_THORNS)
	await _reveal(thorns)
	var canvas: Control = editor.workbench.workspace
	await _drag(thorns.get_global_rect().get_center(), canvas.global_position + Vector2(480, 470), MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.loose_groups.size() == 1 and editor.loose_groups.values()[0].effects[0].buff_id == SkillEngine.BUFF_THORNS, "free status block must preserve its preset")
	for button in editor.workbench.category_rail.get_children():
		if button.text == Locale.t("skill_editor.palette_status"):
			await _click(button.get_global_rect().get_center())
			break
	await _settle()
	await _capture("status-expanded")
	# The random reporter is discoverable in Operators and works in a value slot.
	var random_button: SkillPaletteBlock
	for candidate in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if candidate.expr_kind == "rand": random_button = candidate
	assert(random_button != null and random_button.get_parent().get_meta("unused", "") == "")
	var heading: Button = random_button.get_parent().get_parent().get_child(random_button.get_parent().get_index() - 1)
	assert(heading.get_meta("section_title") == Locale.t("skill_editor.palette_math"))
	await _reveal(random_button)
	var percentage_block: SkillBlock
	for candidate in editor.effects_list.get_child(0).body_container.get_children():
		if candidate is SkillBlock and candidate._effect.get("buff_id") == SkillEngine.BUFF_DAMAGE_REDUCTION: percentage_block = candidate
	slot = percentage_block._sentence_row.find_children("*", "ValueSlot", true, false)[0]
	var start := random_button.get_global_rect().get_center()
	var end := slot.get_global_rect().get_center()
	motion = InputEventMouseMotion.new()
	motion.position = start
	get_viewport().push_input(motion, true)
	await _mouse(start, MOUSE_BUTTON_LEFT, true)
	for step in range(1, 11):
		motion = InputEventMouseMotion.new()
		motion.position = start.lerp(end, float(step) / 10)
		motion.relative = (end - start) / 10
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion, true)
		await get_tree().process_frame
	await _settle()
	var preview: ValueSlot
	for candidate in get_tree().root.find_children("*", "ValueSlot", true, false):
		if candidate.get_meta("drag_preview", false): preview = candidate
	assert(preview != null and preview.find_children("*", "LineEdit", true, false).size() == 2, "palette random preview must show the actual editable range")
	var material: Color = preview.get_theme_stylebox("panel").bg_color
	var preview_size := preview.get_combined_minimum_size()
	await _capture("random-palette-preview")
	await _mouse(end, MOUSE_BUTTON_LEFT, false)
	await _settle()
	var expression: Dictionary = percentage_block._effect.value_expr
	assert(expression.op == "rand" and expression.a.is_empty() and expression.b.is_empty(), "random reporters must start with two empty inputs")
	var operands := slot.find_children("*", "ValueSlot", true, false)
	await _enter_number(operands[0], "1")
	var blank := canvas.get_global_rect().position + canvas.get_global_rect().size * Vector2(0.88, 0.75)
	await _enter_number(operands[1], "6", blank)
	assert(expression.b.value == 6 and not operands[1].get_child(0).has_focus(), "clicking blank canvas must commit the nested value")
	assert(slot.get_combined_minimum_size().distance_to(preview_size) < 1 and slot.get_theme_stylebox("panel").bg_color.is_equal_approx(material), "dropped expression must retain the preview's material and contour dimensions")
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var seen: Array = []
	for i in range(36):
		var result := SkillEngine._eval_operand(expression, null, null, {"rng":rng, "quiet":true})
		assert(result >= 1 and result <= 6)
		if not seen.has(result): seen.append(result)
	assert(seen.size() > 1, "random reporter must produce changing values")
	await _capture("random-variable-reporter")
	editor.queue_free()
	await get_tree().process_frame
	print("TEST_STATUS_PALETTE_VISUAL_OK")
	get_tree().quit(0)

func _status_button(buff: String) -> SkillPaletteBlock:
	for button in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if button.buff_id == buff: return button
	return null

func _first_block() -> SkillBlock:
	return editor.effects_list.get_child(0).body_container.get_child(0)

func _picker(block: SkillBlock) -> OptionButton:
	for node in block._sentence_row.find_children("*", "OptionButton", true, false):
		if node.item_count > SkillRegistry.BUFF_IDS.size(): return node
	return null

func _reveal(button: Button) -> void:
	editor.palette_search.text = button.text
	editor._filter_palette(button.text)
	await _settle()
	var scroll: ScrollContainer = editor.palette_vbox.get_parent()
	scroll.ensure_control_visible(button)
	await _settle()

func _enter_number(slot: ValueSlot, text: String, commit_at := Vector2.INF) -> void:
	var input: LineEdit = slot.find_children("*", "LineEdit", true, false)[0]
	await _click(input.get_global_rect().get_center())
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_A
	key.ctrl_pressed = true
	get_viewport().push_input(key, true)
	for digit in text:
		key = InputEventKey.new()
		key.pressed = true
		key.keycode = digit.unicode_at(0)
		key.unicode = digit.unicode_at(0)
		get_viewport().push_input(key, true)
	if commit_at != Vector2.INF:
		await _click(commit_at)
		await _settle()
		return
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ENTER
	get_viewport().push_input(key, true)
	await _settle()
