extends "res://TestSkillWorkspaceVisual.gd"

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
	editor._select_trigger(SkillEngine.TRIGGER_ON_DEATH)
	editor.palette_search.text = Locale.term("effect",SkillEngine.EFFECT_DAMAGE)
	editor._filter_palette(editor.palette_search.text)
	await _settle()
	var hat: SkillBlock = editor.effects_list.get_child(0)
	assert(hat.get_theme_stylebox("panel") is StyleBoxEmpty, "event must not enclose its script in a frame")
	var damage: Button
	for button in editor.palette_vbox.find_children("*","Button",true,false):
		if button.text == Locale.term("effect",SkillEngine.EFFECT_DAMAGE): damage = button
	var start := damage.get_global_rect().get_center()
	var end := hat.body_container.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = start
	get_viewport().push_input(motion,true)
	await _mouse(start,MOUSE_BUTTON_LEFT,true)
	for i in range(1,11):
		motion = InputEventMouseMotion.new()
		motion.position = start.lerp(end,float(i)/10)
		motion.relative = (end-start)/10
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
	await _settle()
	assert(get_viewport().gui_is_dragging())
	assert(editor._insertion_line != null and editor._insertion_line.size.y > 28, "insertion must reserve space for the actual block")
	assert(not editor._insertion_line.find_children("*","SkillBlock",true,false).is_empty(), "insertion preview must use the real block renderer")
	await _capture("scratch-insertion")
	await _mouse(end,MOUSE_BUTTON_LEFT,false)
	await _settle()
	assert(editor.effect_data.size() == 1 and editor._insertion_line == null)
	editor.effect_data[0].value = 1
	editor.effect_data[0].target = SkillEngine.TARGET_ALL
	editor.effect_data[0].target_side = SkillEngine.TARGET_SIDE_ENEMY
	editor._add_repeat_block()
	editor.effect_data[1].repeat_count = 2
	editor._apply_drop({"type":"effect_block","effect_id":SkillEngine.EFFECT_HEAL},[1,"then"],0)
	editor.effect_data[1].then_effects[0].target = SkillEngine.TARGET_SELF
	editor._refresh_script()
	await _settle()
	editor.workbench.workspace.reset_view()
	await _settle()
	await _capture("scratch-connected")
	for button in editor.workbench.category_rail.get_children():
		if button is Button and button.text == Locale.t("skill_editor.palette_control"):
			await _click(button.get_global_rect().get_center())
	await _settle()
	var selected: Array = []
	for button in editor.workbench.category_rail.get_children():
		if button is Button and button.button_pressed: selected.append(button.text)
	assert(selected == [Locale.t("skill_editor.palette_control")], "only the visible category should be selected: %s" % [selected])
	await _capture("scratch-controls")
	editor.palette_search.text = Locale.term("effect",SkillEngine.EFFECT_DAMAGE)
	editor._filter_palette(editor.palette_search.text)
	await _settle()
	var connected: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(0)
	var value: ValueSlot = connected.find_children("*","ValueSlot",true,false)[0]
	var input: LineEdit = value.find_children("*","LineEdit",true,false)[0]
	var spin: Control = input
	assert(absf(input.get_global_rect().end.x - spin.get_global_rect().end.x) < 0.1, "hidden steppers must return their entire hit region to the number field")
	for height in [0.25, 0.75]:
		await _click(spin.get_global_rect().position + Vector2(spin.get_global_rect().size.x - 4, spin.get_global_rect().size.y * height))
		assert(editor.effect_data[0].value == 1, "clicking the former arrow region must edit the number without stepping it")
	await _capture("number-without-stepper")
	await _click(input.get_global_rect().get_center())
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.ctrl_pressed = true
	key.pressed = true
	get_viewport().push_input(key,true)
	for digit in "24":
		key = InputEventKey.new()
		key.keycode = digit.unicode_at(0)
		key.unicode = digit.unicode_at(0)
		key.pressed = true
		get_viewport().push_input(key,true)
		await get_tree().process_frame
	key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	get_viewport().push_input(key,true)
	await _settle()
	assert(editor.effect_data[0].value == 24, "typing a multi-digit number must preserve focus and apply the complete number")
	editor._undo()
	await _settle()
	assert(editor.effect_data[0].value == 1, "one undo must restore the value before typing")
	# A newly dragged library block must keep the same visual position on release,
	# including when the canvas scale differs from the library scale.
	for zoom in [0.65, 1.0]:
		editor.workbench.workspace.set_zoom(zoom)
		await _settle()
		start = damage.get_global_rect().get_center()
		end = editor.workbench.workspace.global_position + editor.workbench.workspace.size * Vector2(0.83,0.82)
		motion = InputEventMouseMotion.new()
		motion.position = start
		get_viewport().push_input(motion,true)
		await _mouse(start,MOUSE_BUTTON_LEFT,true)
		for i in range(1,11):
			motion = InputEventMouseMotion.new()
			motion.position = start.lerp(end,float(i)/10)
			motion.relative = (end-start)/10
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			get_viewport().push_input(motion,true)
			await get_tree().process_frame
		await _settle()
		assert(get_viewport().gui_is_dragging(), "library drag must be active before measuring the preview")
		assert(editor._insertion_line == null, "anchor check must target blank canvas")
		var preview: SkillBlock
		for node in get_tree().root.find_children("*","SkillBlock",true,false):
			if node.get_meta("drag_preview",false): preview = node
		assert(preview != null)
		var before: Rect2 = preview.get_global_rect()
		await _capture("scratch-free-drag-%d" % roundi(zoom*100))
		await _mouse(end,MOUSE_BUTTON_LEFT,false)
		await _settle()
		var placed: SkillBlock = editor.workbench.workspace.loose_views.back().get_child(0)
		print("EFFECT_ANCHOR ", zoom, " preview=",before," placed=",placed.get_global_rect()," drop=",end)
		assert(before.position.distance_to(placed.get_global_rect().position) < 2, "release must not move the block away from its preview")
		assert(before.size.distance_to(placed.get_global_rect().size) < 2, "release must not resize the block")
		editor._undo()
		await _settle()
	await _check_stack_snap(damage)
	await _check_control_stack_drag()
	print("TEST_SCRATCH_SURFACE_VISUAL_OK")
	get_tree().quit(0)

func _check_control_stack_drag() -> void:
	var canvas: Control = editor.workbench.workspace
	editor._apply_skill_template({"trigger": SkillEngine.TRIGGER_ON_ATTACK, "effects": []})
	editor.loose_groups = {"controls": {"position": [84, 136], "effects": [
		{"effect": SkillEngine.EFFECT_IF, "then_effects": []},
		{"effect": SkillEngine.EFFECT_CHARM, "target": ""}
	]}}
	editor._refresh_script()
	editor._maybe_snapshot()
	canvas.set_zoom(0.85)
	canvas.pan = Vector2(32, 40)
	canvas._sync_view()
	await _settle()
	var control: SkillBlock = canvas.loose_views[0].get_child(0)
	var start := control.get_global_transform() * Vector2(13, 16)
	var destination := start + Vector2(85, 15)
	await _hold_drag(start, destination)
	assert(editor._insertion_line == null, "a detached stack must not snap into its own vacated position")
	var stack := get_tree().root.find_child("DraggedStack", true, false)
	assert(stack != null and stack.get_child_count() == 2)
	var preview: SkillBlock = stack.get_child(0)
	var socket := preview.then_container.get_global_rect()
	var cavity := Vector2(socket.position.x + socket.size.x * 0.7, socket.get_center().y)
	var snapshot := get_viewport().get_texture().get_image()
	var ratio := Vector2(snapshot.get_size()) / get_viewport().get_visible_rect().size
	var color := snapshot.get_pixelv(Vector2i(cavity * ratio))
	assert(color.b > color.r, "the canvas must show through the empty C-shaped drag preview")
	await _capture("control-stack-drag")
	await _mouse(destination, MOUSE_BUTTON_LEFT, false)
	await _settle()
	assert(editor.effect_data.is_empty() and canvas.loose_views.size() == 1)
	control = canvas.loose_views[0].get_child(0)
	var hat: SkillBlock = editor.effects_list.get_child(0)
	var hat_grab := hat.get_global_transform() * Vector2(45, 27)
	var block_position := control.global_position
	var hat_drop := hat_grab + block_position - hat.body_container.global_position
	await _drag(hat_grab, hat_drop, MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.loose_groups.is_empty() and editor.effect_data.size() == 2, "dragging a trigger onto a loose stack must connect it")
	hat = editor.effects_list.get_child(0)
	assert(hat.body_container.get_child(0).global_position.distance_to(block_position) < 2)
	var charm: SkillBlock = hat.body_container.get_child(1)
	assert(charm._sentence_row.get_child(0).text == "魅惑（" and charm.tooltip_text.contains("0费"))
	await _capture("trigger-attached-to-control-stack")
	var empty_opening: Vector2 = hat.body_container.get_child(0).then_container.size
	editor._undo()
	await _settle()
	assert(editor.effect_data.is_empty() and editor.loose_groups.size() == 1, "one undo must detach the trigger from the stack")
	var path: Array = canvas.loose_views[0].get_meta("list_path")
	editor._apply_drop({"type": "effect_block", "effect_id": SkillEngine.EFFECT_HEAL}, path + [0, "then"], 0)
	await _settle()
	control = canvas.loose_views[0].get_child(0)
	var child: SkillBlock = control.then_container.get_child(0)
	start = child.get_global_transform() * Vector2(12, 12)
	destination = canvas.get_global_rect().position + canvas.size * Vector2(0.77, 0.77)
	await _hold_drag(start, destination)
	assert(control.then_container.size.is_equal_approx(empty_opening), "a vacated cavity must match a normally empty cavity during the drag")
	await _capture("control-opening-during-detach")
	await _mouse(destination, MOUSE_BUTTON_LEFT, false)
	await _settle()
	control = canvas.loose_views[0].get_child(0)
	assert(control.then_container.get_child_count() == 0 and control.then_container.size.is_equal_approx(empty_opening), "releasing the last child must not resize the empty cavity again")
	await _capture("control-opening-after-detach")

func _check_stack_snap(palette: Button) -> void:
	var canvas: Control = editor.workbench.workspace
	for zoom in [1.0, 0.65]:
		editor.effect_data = [
			{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SELF, "value": 10},
			{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "value": 20},
			{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SELF, "value": 30}]
		editor._refresh_script()
		editor._maybe_snapshot()
		canvas.reset_view()
		canvas.set_zoom(zoom)
		await _settle()
		var body: VBoxContainer = editor.effects_list.get_child(0).body_container
		var second: Control = body.get_child(1)
		var destination: Vector2 = second.get_global_rect().position + Vector2(25, 8) * zoom
		var start := palette.get_global_rect().position + Vector2(12, 12)
		await _hold_drag(start, destination)
		assert(editor._insertion_line != null)
		var ghost: Control = editor._insertion_line
		var landing := ghost.get_global_rect().position
		for tick in range(16):
			var motion := InputEventMouseMotion.new()
			motion.position = destination + Vector2(1 if tick % 2 == 0 else -1, 0)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			get_viewport().push_input(motion, true)
			await get_tree().process_frame
			assert(editor._insertion_line == ghost and ghost.get_meta("index") == 1, "small pointer movements must not change the displayed connection")
		await _capture("stack-snap-preview-%d" % roundi(zoom * 100))
		await _mouse(destination, MOUSE_BUTTON_LEFT, false)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		body = editor.effects_list.get_child(0).body_container
		assert(editor.effect_data.size() == 4 and not editor.effect_data[1].has("value") and editor.effect_data[2].value == 20, "release must commit the insertion shown in the preview")
		assert(body.get_child(1).get_global_rect().position.distance_to(landing) < 2, "connected block must occupy the preview position")
		assert(body.get_child(1)._drag_highlight, "new connection must visibly confirm on the inserted block")
		await _capture("stack-snap-connected-%d" % roundi(zoom * 100))
		await _settle()
		# Approach the exposed bottom connector from the blank canvas.
		var last: Control = body.get_child(3)
		destination = last.get_global_rect().position + Vector2(12, last.size.y + 12) * zoom
		await _hold_drag(start, destination)
		assert(editor._insertion_line != null and editor._insertion_line.get_meta("index") == 4, "nearby connector must snap even when the pointer is outside the stack")
		await _mouse(destination, MOUSE_BUTTON_LEFT, false)
		await _settle()
		assert(editor.effect_data.size() == 5 and editor.loose_groups.is_empty(), "connector approach must attach rather than silently create a loose block")

func _hold_drag(start: Vector2, destination: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = start
	get_viewport().push_input(motion, true)
	await _mouse(start, MOUSE_BUTTON_LEFT, true)
	for step in range(1, 11):
		motion = InputEventMouseMotion.new()
		motion.position = start.lerp(destination, float(step) / 10)
		motion.relative = (destination - start) / 10
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion, true)
		await get_tree().process_frame
	await _settle()
	assert(get_viewport().gui_is_dragging())
