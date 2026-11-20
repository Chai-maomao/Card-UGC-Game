extends "res://TestSkillNestingVisual.gd"

func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	Input.use_accumulated_input = false
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.editing_skill_index = 0
	PlayerData.init_card_draft()
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	editor.skill_name_input.text = "自由组合"
	editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
	editor.effect_data[0].merge({"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY,"value":3},true)
	editor._on_block_changed([0])
	editor._add_if_block()
	editor._apply_drop({"type":"effect_block","effect_id":SkillEngine.EFFECT_HEAL},[1,"then"],0)
	editor.effect_data[1].then_effects[0].target = SkillEngine.TARGET_SELF
	editor.effect_data[1].then_effects[0].value = 2
	editor._refresh_script()
	await _settle()
	var landing := Control.new()
	landing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landing.position = Vector2(200,300)
	landing.size = Vector2(40,40)
	editor.workbench.workspace.add_child(landing)
	await _palette_drop("expr_kind", "+", landing)
	assert(editor.loose_reporters.size() == 1, "math reporters must remain on blank canvas")
	var numeric_key: String = editor.loose_reporters.keys()[0]
	var view := _reporter_view(numeric_key)
	var values := view.find_children("*","ValueSlot",true,false)
	assert(values.size() == 3)
	await _palette_drop("var_id", SkillEngine.VAR_HAND_COUNT, values[1])
	assert(editor.loose_reporters[numeric_key].value.a.kind == "var", "free expressions must accept nested reporters")
	landing.position = Vector2(200,420)
	await _palette_drop("boolean_kind", "compare", landing)
	assert(editor.loose_reporters.size() == 2, "conditions must remain on blank canvas")
	var boolean_key := ""
	for key in editor.loose_reporters:
		if key != numeric_key: boolean_key = key
	await _capture("loose-reporters")
	# Move the entire free arithmetic expression into the damage value slot.
	var before: Dictionary = editor._editor_state().duplicate(true)
	var pan_before: Vector2 = editor.workbench.workspace.pan
	view = _reporter_view(numeric_key)
	await _drag(view.get_global_transform()*Vector2(2,view.size.y/2),_socket(1,[]).get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor._editor_state() == before, "a number dropped on a condition hole must preserve both the free reporter and the script")
	view = _reporter_view(numeric_key)
	values = view.find_children("*","ValueSlot",true,false)
	await _drag(view.get_global_transform()*Vector2(2,view.size.y/2),values[2].get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor._editor_state() == before, "a reporter cannot be inserted into its own descendant or detached as a fallback")
	var effect: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(0)
	var target: ValueSlot = effect.find_children("*","ValueSlot",true,false)[0]
	view = _reporter_view(numeric_key)
	await _move_with_preview(view.get_global_transform()*Vector2(2,view.size.y/2),target.get_global_rect().get_center(),"loose-number-preview")
	await _settle()
	assert(editor.workbench.workspace.pan.is_equal_approx(pan_before), "dragging a reporter must not also pan the canvas")
	assert(not editor.loose_reporters.has(numeric_key) and editor.effect_data[0].has("value_expr") and editor.effect_data[0].value_expr.a.kind == "var", "inserting a free expression must move, not duplicate, it")
	var inserted: Dictionary = editor._editor_state().duplicate(true)
	editor._undo()
	await _settle()
	assert(editor._editor_state() == before, "one undo must restore the free expression and the target value")
	editor._redo()
	await _settle()
	assert(editor._editor_state() == inserted, "redo must restore both ends of the expression move")
	editor._undo()
	await _settle()
	# Move the free condition into the real if socket, then undo both ends.
	view = _reporter_view(boolean_key)
	await _move_with_preview(view.get_global_transform()*Vector2(3,view.size.y/2),_socket(1,[]).get_global_rect().get_center(),"loose-condition-preview")
	await _settle()
	assert(not editor.loose_reporters.has(boolean_key) and editor.effect_data[1].condition.has("op"))
	inserted = editor._editor_state().duplicate(true)
	editor._undo()
	await _settle()
	assert(editor._editor_state() == before, "one undo must restore the free condition and the if socket")
	editor._redo()
	await _settle()
	assert(editor._editor_state() == inserted, "redo must restore both ends of the condition move")
	editor._undo()
	await _settle()
	# Discard a standalone condition through the real library drop zone.
	view = _reporter_view(boolean_key)
	await _drag(view.get_global_transform()*Vector2(3,view.size.y/2),editor.palette_title.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(not editor.loose_reporters.has(boolean_key) and editor.loose_reporters.size() == 1)
	editor._undo()
	await _settle()
	assert(editor._editor_state() == before, "undoing a discarded free condition must restore its complete content and position")
	landing.position = Vector2(500,200)
	await _palette_drop("target_kind", SkillEngine.TARGET_ALL, landing)
	landing.position = Vector2(500,330)
	await _palette_drop("side_kind", SkillEngine.TARGET_SIDE_ALLY, landing)
	assert(editor.loose_reporters.size() == 4, "target and side reporters must also remain on blank canvas")
	var target_key := ""
	var side_key := ""
	for key in editor.loose_reporters:
		if editor.loose_reporters[key].kind == "target": target_key = key
		if editor.loose_reporters[key].kind == "side": side_key = key
	before = editor._editor_state().duplicate(true)
	# Escape must return each kind to its original position and opacity.
	for key in [numeric_key,boolean_key,target_key,side_key]:
		view = _reporter_view(key)
		var start := view.get_global_transform()*Vector2(3,view.size.y/2)
		var end := start+Vector2(36,24)
		var motion := InputEventMouseMotion.new()
		motion.position = start
		get_viewport().push_input(motion,true)
		await _mouse(start,MOUSE_BUTTON_LEFT,true)
		for i in range(1,6):
			motion = InputEventMouseMotion.new()
			motion.position = start.lerp(end,float(i)/5)
			motion.relative = (end-start)/5
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			get_viewport().push_input(motion,true)
			await get_tree().process_frame
		assert(get_viewport().gui_is_dragging())
		if key == numeric_key:
			editor.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			assert(get_viewport().gui_is_dragging(), "focus notification must defer preview removal")
			await get_tree().process_frame
			assert(not get_viewport().gui_is_dragging(), "focus loss must release the drag on the next frame")
		else:
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			get_viewport().push_input(escape,true)
		await _mouse(end,MOUSE_BUTTON_LEFT,false)
		await _settle()
		assert(editor._editor_state() == before, "cancelling each reporter kind must preserve the workspace")
		for child in _reporter_view(key).find_children("*","Control",true,false):
			assert(is_equal_approx(child.modulate.a,1), "cancel must restore source opacity")
	effect = editor.effects_list.get_child(0).body_container.get_child(0)
	var target_socket: TargetSlot
	var side_socket: TargetSlot
	for candidate in effect.find_children("*","TargetSlot",true,false):
		if candidate.kind == "target": target_socket = candidate
		else: side_socket = candidate
	view = _reporter_view(target_key)
	await _target_hover_drop(view.get_global_transform()*Vector2(2,view.size.y/2),target_socket,"target-slot-hover")
	await _settle()
	assert(editor.effect_data[0].target == SkillEngine.TARGET_ALL
			and editor.loose_reporters[target_key].value.target == SkillEngine.TARGET_SINGLE,
			"dropping onto a filled target slot must keep the displaced reporter on the canvas")
	editor._undo()
	await _settle()
	assert(editor._editor_state() == before, "undo must restore both ends of a target move")
	effect = editor.effects_list.get_child(0).body_container.get_child(0)
	for candidate in effect.find_children("*","TargetSlot",true,false):
		if candidate.kind == "side": side_socket = candidate
	view = _reporter_view(side_key)
	await _target_hover_drop(view.get_global_transform()*Vector2(2,view.size.y/2),side_socket,"side-slot-hover")
	await _settle()
	assert(editor.effect_data[0].target_side == SkillEngine.TARGET_SIDE_ALLY
			and editor.loose_reporters[side_key].value.target_side == SkillEngine.TARGET_SIDE_ENEMY,
			"dropping onto a filled side slot must keep the displaced reporter on the canvas")
	editor._undo()
	await _settle()
	assert(editor._editor_state() == before, "undo must restore both ends of a side move")
	# Context commands apply consistently to all standalone reporter types.
	for key in [numeric_key,boolean_key,target_key,side_key]:
		view = _reporter_view(key)
		var start := view.get_global_transform()*Vector2(3,view.size.y/2)
		var motion := InputEventMouseMotion.new()
		motion.position = start
		motion.global_position = start
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
		await _mouse(start,MOUSE_BUTTON_RIGHT,true)
		await _mouse(start,MOUSE_BUTTON_RIGHT,false)
		await _settle()
		var menu: PopupMenu
		for child in editor.get_children():
			if child is PopupMenu and child.visible: menu = child
		assert(menu != null, "right-click must expose commands for each reporter type")
		menu.id_pressed.emit(0)
		menu.hide()
		await _settle()
		assert(editor.loose_reporters.size() == 5)
		editor._undo()
		await _settle()
		assert(editor._editor_state() == before, "duplicate and undo must preserve all original reporter contents")
		view = _reporter_view(key)
		start = view.get_global_transform()*Vector2(3,view.size.y/2)
		motion = InputEventMouseMotion.new()
		motion.position = start
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
		await _mouse(start,MOUSE_BUTTON_RIGHT,true)
		await _mouse(start,MOUSE_BUTTON_RIGHT,false)
		await _settle()
		menu = null
		for child in editor.get_children():
			if child is PopupMenu and child.visible: menu = child
		assert(menu != null)
		menu.id_pressed.emit(1)
		menu.hide()
		await _settle()
		assert(not editor.loose_reporters.has(key) and editor.loose_reporters.size() == 3)
		editor._undo()
		await _settle()
		assert(editor._editor_state() == before, "context deletion and undo must restore the complete reporter")
	await _capture("loose-all-types")
	# Finish the script without consuming the unconnected examples.
	await _palette_drop("boolean_kind", "compare", _socket(1,[]))
	editor.effect_data[1].condition.lhs = {"kind":"num", "value":1}
	editor.effect_data[1].condition.rhs = {"kind":"num", "value":1}
	editor._refresh_script()
	editor._update_summary()
	assert(editor.workbench.compile_preview(), "unconnected reporters must not enter compilation")
	var expected: Dictionary = editor._build_skill().duplicate(true)
	var json_skill: Dictionary = JSON.parse_string(JSON.stringify(expected))
	json_skill._workspace.reporters["invalid"] = {"kind":"number","position":[0,0],"value":{"kind":"expr","op":"+","a":[],"b":{"kind":"num","value":1}}}
	json_skill._workspace.reporters["invalid_condition"] = {"kind":"condition","position":[0,0],"value":{"condition":5}}
	editor._restore_workspace(json_skill._workspace)
	editor._refresh_script()
	await _settle()
	assert(SkillUndoManager.deep_equal(editor._build_skill(),expected), "reporter positions and contents must survive JSON")
	get_tree().current_scene = null
	await _click(editor.save_button.get_global_rect().get_center())
	await get_tree().scene_changed
	await _settle()
	assert(SkillUndoManager.deep_equal(PlayerData.card_draft.skill1,expected))
	var card_editor: Control = get_tree().current_scene
	editor.queue_free()
	await get_tree().process_frame
	card_editor.get_node("Panel/MarginContainer/ScrollContainer").ensure_control_visible(card_editor.edit_skill1_btn)
	await _settle()
	await _click(card_editor.edit_skill1_btn.get_global_rect().get_center())
	await get_tree().scene_changed
	await _settle()
	editor = get_tree().current_scene
	assert(editor.loose_reporters.size() == 4 and SkillUndoManager.deep_equal(editor._build_skill(),expected), "save and reopen must preserve standalone reporters")
	var packed: Dictionary = PlayerData.serialize_card(PlayerData.build_card_from_draft())
	var executable := packed.duplicate(true)
	executable.skills[0].erase("_workspace")
	assert(SharePackage.gameplay_signature(packed) == SharePackage.gameplay_signature(executable), "free reporters must not change the battle identity")
	await _capture("loose-reporters-reopened")
	print("TEST_LOOSE_REPORTERS_VISUAL_OK")
	get_tree().quit(0)

func _reporter_view(key: String) -> Control:
	for view in editor.workbench.workspace.loose_views:
		if view.name == "Reporter_%s" % key: return view
	assert(false,"missing reporter view")
	return null

func _target_hover_drop(start: Vector2, slot: TargetSlot, screenshot: String) -> void:
	var end := slot.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = start
	get_viewport().push_input(motion,true)
	await _mouse(start,MOUSE_BUTTON_LEFT,true)
	for i in range(1,10):
		motion = InputEventMouseMotion.new()
		motion.position = start.lerp(end,float(i)/9)
		motion.relative = (end-start)/9
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
	await _settle()
	assert(get_viewport().gui_is_dragging() and slot._drop_highlight)
	var chip: Button = slot.get_child(0)
	assert(chip.get_global_rect().is_equal_approx(slot.get_global_rect()), "the drop outline must share the filled chip's bounds without an empty outer ring")
	await _capture(screenshot)
	await _mouse(end,MOUSE_BUTTON_LEFT,false)

func _move_with_preview(start: Vector2, end: Vector2, screenshot: String) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = start
	get_viewport().push_input(motion,true)
	await _mouse(start,MOUSE_BUTTON_LEFT,true)
	for i in range(1,10):
		motion = InputEventMouseMotion.new()
		motion.position = start.lerp(end,float(i)/9)
		motion.relative = (end-start)/9
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
	await _settle()
	var preview: Control
	for node in get_tree().root.find_children("*","Control",true,false):
		if node.get_meta("drag_preview",false): preview = node
	assert(preview != null and preview.find_children("*","ValueSlot",true,false).size() >= 2, "reporter preview must keep its operands rather than collapse to a label")
	await _capture(screenshot)
	await _mouse(end,MOUSE_BUTTON_LEFT,false)
