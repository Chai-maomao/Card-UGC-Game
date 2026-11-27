extends Node

var editor: Control

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _ready() -> void:
	await get_tree().create_timer(0.2).timeout
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	# Keep the operator's physical pointer from competing with injected events.
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	Input.use_accumulated_input = false
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.editing_skill_index = 0
	PlayerData.init_card_draft()
	PlayerData.card_draft["name"] = "星铸守卫"
	var original := PlayerData.card_draft.duplicate(true)
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	var workbench: RefCounted = editor.workbench
	var canvas: Control = workbench.workspace
	assert(not workbench.preview_section.visible)
	await _capture("workspace-empty")
	await _click(editor._template_btn.get_global_rect().get_center())
	await _settle()
	var templates := editor.get_node_or_null("SkillTemplatesPopup")
	assert(templates != null and canvas.is_visible_in_tree(), "template selection must retain the workspace")
	await _capture("workspace-templates")
	templates.dismiss()
	await _settle()
	# View the discard decoration without the live drag cleanup clearing it.
	editor.set_process(false)
	editor._set_palette_discard_highlight(true)
	await _capture("palette-discard-glow")
	editor._set_palette_discard_highlight(false)
	editor.set_process(true)


	# Exercise viewport pointer routing and cursor-centred zoom.
	var point: Vector2 = canvas.global_position + canvas.size * Vector2(0.7, 0.7)
	var old_pan: Vector2 = canvas.pan
	await _drag(point, point + Vector2(-48, -36), MOUSE_BUTTON_LEFT)
	assert(canvas.pan.distance_to(old_pan + Vector2(-48, -36)) < 0.01)
	var local_point: Vector2 = point - canvas.global_position
	var before: Vector2 = (local_point - canvas.pan) / canvas.zoom
	await _mouse(point, MOUSE_BUTTON_WHEEL_UP, true)
	await _mouse(point, MOUSE_BUTTON_WHEEL_UP, false)
	var after: Vector2 = (local_point - canvas.pan) / canvas.zoom
	assert(before.distance_to(after) < 0.01, "zoom must keep cursor's world point fixed")
	await _click(workbench.zoom_label.get_global_rect().get_center())

	# Drag a palette block onto blank canvas at reduced zoom.
	# A trigger change can rebuild both the palette and category rail in one frame.
	editor._build_palette()
	editor.palette_search.text = Locale.term("effect", SkillEngine.EFFECT_DAMAGE)
	editor._filter_palette(editor.palette_search.text)
	await _settle()
	var defense: Button
	for button in workbench.category_rail.get_children():
		if button.text == Locale.t("skill_editor.palette_defense"):
			defense = button
			break
	assert(defense != null)
	await _click(defense.get_global_rect().get_center())
	await _settle()
	await _capture("workspace-category-click")
	assert(editor.palette_search.text.is_empty(), "category navigation must leave filtered search")
	assert(defense.button_pressed, "category navigation after rebuild must select the visible category")
	editor.palette_search.text = Locale.term("effect", SkillEngine.EFFECT_DAMAGE)
	editor.palette_search.text_changed.emit(editor.palette_search.text)
	await _settle()
	var damage: Button
	for button in editor.palette_vbox.find_children("*", "Button", true, false):
		if button.text == Locale.term("effect", SkillEngine.EFFECT_DAMAGE): damage = button
	assert(damage != null and damage.is_visible_in_tree())
	canvas.set_zoom(0.65)
	await _drag(damage.get_global_rect().get_center(), canvas.global_position + Vector2(320, 300), MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data.is_empty() and editor.loose_groups.size() == 1, "blank canvas must keep a free block without executing it")
	var key: String = editor.loose_groups.keys()[0]
	assert(canvas.loose_views.size() == 1)
	await _capture("workspace-free-block")
	var loose: SkillBlock
	for block in canvas.loose_views[0].get_children():
		if block is SkillBlock: loose = block
	assert(loose != null)
	# Grab the sentence text, not a narrow exposed border, and snap into the event.
	var source: Vector2 = loose.get_global_transform() * Vector2(14, 14)
	var hat: SkillBlock = editor.effects_list.get_child(0)
	canvas.set_zoom(1.21, hat.global_position - canvas.global_position)
	await _settle()
	source = loose.get_global_transform() * Vector2(14, 14)
	var marker := canvas.world.get_node("SnapMarker") as Line2D
	var body: Vector2 = hat.body_container.get_global_rect().position
	var grab: Vector2 = source - loose.global_position
	var outside := body + grab + Vector2(12, -38)
	var inside := body + grab + Vector2(12, -19)
	await _drag(source, outside, MOUSE_BUTTON_LEFT, false)
	assert(not marker.visible, "outside the capture range should not show a connector")
	var approach := InputEventMouseMotion.new()
	approach.position = inside
	approach.global_position = inside
	approach.relative = inside - outside
	approach.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(approach, true)
	await _settle()
	assert(marker.visible, "the connector must render at the edge of the snap range at 121 percent")
	await _capture("workspace-snap-range")
	await _mouse(inside, MOUSE_BUTTON_LEFT, false)
	await _settle()
	assert(editor.effect_data.size() == 1 and editor.loose_groups.is_empty(), "free block must reconnect from its title face")
	assert(not marker.visible, "the snap connector must clear after release")
	canvas.set_zoom(0.65)
	await _settle()
	editor.effect_data[0].merge({"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY},true)
	editor._on_block_changed([0])
	editor._refresh_script()
	await _settle()
	await _edit_block_amount(editor.effects_list,3)
	assert(editor.effect_data[0].value == 3, "advanced edit must update the real script")
	# Detach an existing executable block by its sentence, move it freely, undo
	# both movement and detachment, then reconnect it without losing parameters.
	hat = editor.effects_list.get_child(0)
	var connected: SkillBlock = hat.body_container.get_child(0)
	await _drag(connected.get_global_transform()*Vector2(14,14),canvas.global_position+Vector2(330,300),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data.is_empty() and editor.loose_groups.size()==1)
	key = editor.loose_groups.keys()[0]
	assert(editor.loose_groups[key].effects[0].value == 3)
	await _edit_block_amount(canvas.loose_views[0],5)
	assert(editor.loose_groups[key].effects[0].value==5,"a detached block must remain editable")
	editor._undo()
	await _settle()
	assert(editor.loose_groups[key].effects[0].value==3)
	var old_free: Array = editor.loose_groups[key].position.duplicate()
	loose = canvas.loose_views[0].get_child(0)
	var free_start: Vector2 = loose.get_global_transform()*Vector2(14,14)
	await _drag(free_start,free_start+Vector2(-30,45),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.loose_groups.size()==1, "moving a free block must not duplicate it")
	var moved_free: Array = editor.loose_groups[key].position
	assert(Vector2(moved_free[0]-old_free[0],moved_free[1]-old_free[1]).distance_to(Vector2(-30,45)/canvas.zoom)<1)
	editor._undo()
	await _settle()
	assert(editor.loose_groups[key].position == old_free)
	editor._undo()
	await _settle()
	assert(editor.effect_data.size()==1 and editor.loose_groups.is_empty())
	editor._redo()
	await _settle()
	loose = canvas.loose_views[0].get_child(0)
	hat = editor.effects_list.get_child(0)
	await _drag(loose.get_global_transform()*Vector2(14,14),hat.body_container.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.loose_groups.is_empty() and editor.effect_data[0].value==3)
	editor.skill_name_input.text = "星火"
	editor.skill_name_input.text_changed.emit("星火")
	await _click(workbench.compile_button.get_global_rect().get_center())
	await _settle()
	assert(workbench.preview_section.visible, "compile button must reveal preview")
	assert(workbench.card_preview.current_card_data.skills.size() == 1)
	assert(PlayerData.card_draft == original, "preview must not save or mutate the draft")
	await _capture("workspace-compiled")
	await _verify_preview_width(workbench)
	# The whole event stack can be moved by its header, even when the release
	# stays over the original stack, without panning the entire workspace.
	hat = editor.effects_list.get_child(0)
	var start: Vector2 = hat.get_global_transform() * Vector2(70,12)
	var old_script: Vector2 = editor.workspace_script_position
	var pan_before: Vector2 = canvas.pan
	await _drag(start,start+Vector2(44,24),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.workspace_script_position.distance_to(old_script+Vector2(44,24)/canvas.zoom) < 0.1)
	assert(canvas.pan.is_equal_approx(pan_before), "moving the script must not move the camera")
	editor._undo()
	await _settle()
	assert(editor.workspace_script_position.is_equal_approx(old_script))
	editor._redo()
	await _settle()

	# A new edit invalidates the compiled preview. Undo and redo still work.
	editor._add_effect_block(SkillEngine.EFFECT_HEAL)
	editor.effect_data[1].merge({"target":SkillEngine.TARGET_SELF,"target_side":SkillEngine.TARGET_SIDE_ALL,"value":2},true)
	editor._on_block_changed([1])
	assert(not workbench.preview_section.visible)
	editor._undo()
	assert(editor.effect_data[1].target == "")
	editor._undo()
	assert(editor.effect_data.size() == 1)
	editor._redo()
	editor._redo()
	assert(editor.effect_data.size() == 2)

	# Keep nested execution structure and reject incomplete conditions at compile time.
	editor._add_if_block()
	var last: int = editor.effect_data.size() - 1
	editor._apply_drop({"type":"effect_block", "effect_id":SkillEngine.EFFECT_DAMAGE}, [last, "then"], 0)
	assert(editor.effect_data[last].then_effects.size() == 1)
	assert(not workbench.compile_preview(), "an empty condition must not compile")
	assert(not workbench.preview_section.visible)
	# Close the validation popup before inspecting the workspace.
	for child in editor.get_children():
		if child is CanvasLayer: child.queue_free()
	editor.effect_data[last]["condition"] = {"op":">=", "lhs":{"kind":"num","value":1}, "rhs":{"kind":"num","value":1}}
	editor._refresh_script()
	editor._update_summary()
	await _settle()
	canvas.reset_view()
	await _capture("workspace-nested")

	# Reordering via structural edits also invalidates a compiled result.
	editor._on_block_delete_path([last])
	await _settle()
	assert(workbench.compile_preview())
	# Keep one unused block beside the script and verify save/reopen retains it.
	canvas.last_pointer = Vector2(330, 330)
	editor._drop_on_workspace(canvas.last_pointer, {"type":"effect_block", "effect_id":SkillEngine.EFFECT_HEAL})
	await _settle()
	assert(editor.loose_groups.size()==1)
	assert(workbench.compile_preview(),"unfinished disconnected blocks must not enter compilation")
	hat = editor.effects_list.get_child(0)
	connected = hat.body_container.get_child(1)
	loose = canvas.loose_views[0].get_child(0)
	await _drag(connected.get_global_transform() * Vector2(14, 14), loose.get_global_transform() * Vector2(14, 14), MOUSE_BUTTON_LEFT)
	await _settle()
	key = editor.loose_groups.keys()[0]
	assert(editor.effect_data.size() == 1 and editor.loose_groups.size() == 1 and editor.loose_groups[key].effects.size() == 2,
		"a connected block must snap into a loose stack")
	editor._undo()
	await _settle()
	assert(workbench.compile_preview())
	editor._move_effect([1], [], 0)
	assert(not workbench.preview_section.visible)
	assert(workbench.compile_preview())
	for dimensions in [Vector2i(960,540), Vector2i(1280,720)]:
		get_window().size = dimensions
		await _settle()
		assert(workbench.inspector.get_global_rect().end.x <= get_viewport().get_visible_rect().end.x)
		assert(workbench.compile_button.get_global_rect().end.x <= get_viewport().get_visible_rect().end.x)
		await _capture("workspace-compiled-%d" % dimensions.x)
	# Exercise the real Save -> CardEditor -> reopen route, keeping this observer
	# outside current_scene so scene transitions do not remove the assertions.
	var expected: Dictionary = editor._build_skill().duplicate(true)
	get_tree().current_scene = null
	await _click(editor.save_button.get_global_rect().get_center())
	await get_tree().scene_changed
	await _settle()
	assert(PlayerData.card_draft.skill1 == expected, "save must preserve compiled data")
	var card_editor: Control = get_tree().current_scene
	assert(card_editor.scene_file_path == "res://CardEditor.tscn")
	editor.queue_free()
	await get_tree().process_frame
	var form_scroll: ScrollContainer = card_editor.get_node("Panel/MarginContainer/ScrollContainer")
	form_scroll.ensure_control_visible(card_editor.edit_skill1_btn)
	await _settle()
	await _click(card_editor.edit_skill1_btn.get_global_rect().get_center())
	await get_tree().scene_changed
	await _settle()
	editor = get_tree().current_scene
	assert(editor.scene_file_path == "res://SkillEditor.tscn")
	assert(editor._build_skill() == expected, "reopening must restore the saved skill exactly")
	assert(editor.loose_groups.size() == 1, "save/reopen must keep the free block")
	assert(not editor.workbench.preview_section.visible)
	assert(editor.workbench.compile_preview())
	assert(editor.workbench.card_preview.current_card_data.skills[0] == expected)
	await _capture("workspace-reopened")
	# The CardData/JSON path used by card saving must keep the skill too.
	var packed: Dictionary = PlayerData.serialize_card(PlayerData.build_card_from_draft())
	var gameplay_only: Dictionary = packed.duplicate(true)
	gameplay_only.skills[0].erase("_workspace")
	assert(SharePackage.gameplay_signature(packed) == SharePackage.gameplay_signature(gameplay_only), "layout and unconnected blocks must not alter gameplay identity")
	var restored: CardData = PlayerData.deserialize_card(JSON.parse_string(JSON.stringify(packed)))
	# JSON stores numbers as floating point; compare all keys and numeric values
	# recursively, allowing only the int/float representation change.
	assert(SkillUndoManager.deep_equal(restored.skills[0], expected))
	get_tree().current_scene = null
	editor.queue_free()
	await get_tree().process_frame
	for kind in ["spell", "parasite", "talent"]:
		if kind == "spell": PlayerData.init_spell_draft()
		elif kind == "parasite": PlayerData.init_parasite_draft()
		else: PlayerData.init_card_draft()
		PlayerData.editing_skill_index = 3 if kind == "talent" else 0
		PlayerData.card_draft["name"] = "Arc Spark" if kind == "spell" else "守护印记"
		Locale.language = "en" if kind == "spell" else "zh"
		editor = preload("res://SkillEditor.tscn").instantiate()
		add_child(editor)
		await _settle()
		editor.skill_name_input.text = "Guard"
		if kind == "talent":
			editor._add_effect_block(SkillEngine.EFFECT_DAMAGE_CAP)
			editor.effect_data[0].value = 2
		else:
			editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
			var added: int = editor.effect_data.size() - 1
			editor.effect_data[added].merge({"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY,"value":3},true)
			editor._on_block_changed([added])
		editor._refresh_script()
		editor._update_summary()
		await _settle()
		assert(editor.workbench.compile_preview(), "%s must compile in the real editor" % kind)
		assert(editor.workbench.card_preview.current_card_data.card_type == ("minion" if kind == "talent" else kind))
		assert(editor.workbench.compile_button.get_global_rect().end.x <= get_viewport().get_visible_rect().end.x)
		for button in [editor._undo_btn,editor._redo_btn,editor._template_btn,editor.workbench.compile_button,editor.save_button]:
			if button.is_visible_in_tree():
				assert(get_viewport().get_visible_rect().encloses(button.get_global_rect()), "toolbar button must fit: %s %s" % [button.text,button.get_global_rect()])
		await _capture("workspace-%s" % kind)
		editor.queue_free()
		await get_tree().process_frame
	await get_tree().process_frame
	print("TEST_SKILL_WORKSPACE_VISUAL_OK")
	get_tree().quit(0)

func _settle() -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/%s.png" % name)

func _verify_preview_width(workbench: RefCounted) -> void:
	var summary: Label = workbench.compiled_summary
	var original := summary.text
	summary.text = "友方目标获得再生，每逢我方回合开始回复 1 点生命，持续 2 回合。为同一目标提高生命上限，持续到离场。"
	await _settle()
	var original_ratio: float = AppPreferences.get_value("skill_inspector_ratio")
	var narrow_width: float = workbench.inspector.size.x
	var narrow_lines := summary.get_line_count()
	var divider: Control = workbench.inspector_divider
	var center := divider.get_global_rect().get_center()
	await _drag(center, center - Vector2(170, 0), MOUSE_BUTTON_LEFT)
	await _settle()
	assert(workbench.inspector.size.x > narrow_width and summary.get_line_count() < narrow_lines,
		"widening the inspector must reduce the number of wrapped lines")
	await _capture("workspace-preview-expanded")
	center = divider.get_global_rect().get_center()
	await _drag(center, center + Vector2(170, 0), MOUSE_BUTTON_LEFT)
	await _settle()
	assert(is_equal_approx(workbench.inspector.size.x, narrow_width) and summary.get_line_count() == narrow_lines,
		"narrowing the inspector must wrap the same description back onto more lines")
	await _capture("workspace-preview-narrow")
	AppPreferences.set_value("skill_inspector_ratio", original_ratio)
	summary.text = original

func _mouse(point: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE) if pressed and button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE] else 0
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _drag(start: Vector2, end: Vector2, button: int, release := true) -> void:
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
	if release:
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
		if button.text == Locale.t("skill_editor.more"): advanced = button
	assert(advanced != null)
	await _click(advanced.get_global_rect().get_center())
	await _settle()
	var menu: PopupMenu
	for child in editor.get_children():
		if child is PopupMenu and child.visible: menu = child
	assert(menu != null and menu.get_item_text(menu.get_item_index(2)) == Locale.t("skill_editor.btn_edit"), "More must expose Advanced in the actual menu")
	menu.id_pressed.emit(2)
	menu.hide()
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
