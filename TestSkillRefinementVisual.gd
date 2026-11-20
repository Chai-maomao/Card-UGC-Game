extends Node
var editor
func _ready():
	await get_tree().create_timer(0.2).timeout
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(1280,720)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	Input.use_accumulated_input=false
	Locale.language="zh"
	PlayerData.skill_tutorial_active=false
	PlayerData.editing_skill_index=0
	PlayerData.init_card_draft()
	editor=load("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	var bench=editor.workbench
	await _click(bench.preview_tab.get_global_rect().get_center())
	assert(bench.preview_feedback.visible and bench.preview_tab.has_node("UnavailableFeedback"))
	await _settle()
	editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
	await _settle()
	var hat=editor.effects_list.get_child(0)
	var block=hat.body_container.get_child(0)
	assert(block.find_children("ValidationOutline","",true,false).is_empty())
	assert(not bench.compile_preview())
	await _settle()
	var marked_slots: Array[Node] = []
	for marker in block.find_children("ValidationOutline", "", true, false):
		marked_slots.append(marker.get_parent())
	assert(marked_slots.size() == 2
			and marked_slots.any(func(slot: Node): return slot is TargetSlot and slot.kind == "target")
			and marked_slots.any(func(slot: Node): return slot is ValueSlot),
			"compilation must mark each required empty socket")
	for child in editor.get_children():
		if child is CanvasLayer: child.queue_free()
	await _settle()
	await _capture("validation-slot-only")
	for value in [1,2,3]:
		if value>1: editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
		editor.effect_data[value-1].merge({"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY,"value":value},true)
	editor._refresh_script()
	editor._update_summary()
	await _settle()
	assert(editor.effects_list.find_children("ValidationOutline","",true,false).is_empty())
	var canvas=bench.workspace
	canvas.set_zoom(0.7)
	await _settle()
	hat=editor.effects_list.get_child(0)
	var second=hat.body_container.get_child(1)
	var third=hat.body_container.get_child(2)
	var start=second.get_global_transform()*Vector2(14,14)
	var end=canvas.global_position+canvas.size*Vector2(0.6,0.8)
	var motion=InputEventMouseMotion.new()
	motion.position=start
	get_viewport().push_input(motion,true)
	await _mouse(start,MOUSE_BUTTON_LEFT,true)
	for i in range(1,10):
		motion=InputEventMouseMotion.new()
		motion.position=start.lerp(end,float(i)/9)
		motion.relative=(end-start)/9
		motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
	assert(get_viewport().gui_is_dragging())
	assert(not second.visible and not third.visible,"origin tail must vanish during drag")
	await _capture("scratch-tail-drag")
	var cancel := InputEventKey.new()
	cancel.keycode=KEY_ESCAPE
	cancel.pressed=true
	get_viewport().push_input(cancel,true)
	await get_tree().process_frame
	await _mouse(end,MOUSE_BUTTON_LEFT,false)
	await _settle()
	assert(not get_viewport().gui_is_dragging() and second.visible and third.visible)
	assert(editor.effect_data.size()==3 and editor.loose_groups.is_empty(),"cancel must restore the whole dragged tail")
	await _drag(second.get_global_transform()*Vector2(14,14),end,MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data.size()==1 and editor.effect_data[0].value==1)
	assert(editor.loose_groups.size()==1)
	var group=editor.loose_groups.values()[0]
	assert(group.effects.size()==2 and group.effects[0].value==2 and group.effects[1].value==3)
	await _capture("scratch-tail-detached")
	var loose=canvas.loose_views[0].get_child(0)
	hat=editor.effects_list.get_child(0)
	await _drag(loose.get_global_transform()*Vector2(14,14),hat.body_container.get_global_rect().end-Vector2(20,4),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.loose_groups.is_empty() and editor.effect_data.size()==3)
	assert(editor.effect_data[1].value==2 and editor.effect_data[2].value==3)
	assert(bench.compile_preview())
	await _settle()
	await _click(bench.card_preview.get_global_rect().get_center())
	assert(bench.card_preview.get_meta("suppress_hover_hint",false))
	print("TEST_SKILL_REFINEMENT_OK")
	get_tree().quit(0)

func _settle() -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/%s.png" % name)

func _mouse(point: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE) if pressed and button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE] else 0
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _drag(start: Vector2, end: Vector2, button: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = start
	get_viewport().push_input(motion,true)
	await _mouse(start, button, true)
	var previous := start
	for i in range(1, 10):
		var point := start.lerp(end, float(i)/9)
		motion = InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = motion.position
		motion.relative = motion.position - previous
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
		get_viewport().push_input(motion,true)
		previous = point
		await get_tree().process_frame
	await _mouse(end, button, false)

func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = motion.position
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	await _mouse(point, MOUSE_BUTTON_LEFT, true)
	await _mouse(point, MOUSE_BUTTON_LEFT, false)
	await RenderingServer.frame_post_draw

func _edit_block_amount(container: Control, value: int) -> void:
	var advanced: Button
	for button in container.find_children("*", "Button", true, false):
		if button.text == Locale.t("skill_editor.btn_edit"): advanced = button
	assert(advanced != null)
	await _click(advanced.get_global_rect().get_center())
	await _settle()
	var form: SkillEffectForm
	for child in editor.get_children():
		if child is SkillEffectForm: form = child
	assert(form != null, "Advanced must open from a scaled block")
	form._val_spin.value = value
	var confirm: Button
	for button in form.find_children("*", "Button", true, false):
		if button.text == Locale.t("skill_editor.ok"): confirm = button
	assert(confirm != null)
	await _click(confirm.get_global_rect().get_center())
	await _settle()
