extends "res://TestSkillWorkspaceVisual.gd"

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	Input.use_accumulated_input = false
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.editing_skill_index = 0
	PlayerData.init_card_draft()
	var draft := PlayerData.card_draft.duplicate(true)
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
	editor.effect_data[0].merge({"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY,"value":3},true)
	editor._on_block_changed([0])
	editor._refresh_script()
	await _settle()
	var bench = editor.workbench
	var block = editor.effects_list.get_child(0).body_container.get_child(0)
	var rect: Rect2 = block.get_global_rect()
	var motion := InputEventMouseMotion.new()
	motion.position = rect.position + Vector2(14,14)
	get_viewport().push_input(motion,true)
	await _settle()
	assert(block.get_global_rect().is_equal_approx(rect), "hover must keep the block and its parameters still")
	# Open the actual block menu and use Duplicate; one undo restores the script.
	var more: Button
	for button in block.find_children("*","Button",true,false):
		if button.text == Locale.t("skill_editor.more"): more = button
	assert(more != null)
	await _click(more.get_global_rect().get_center())
	await _settle()
	var menu: PopupMenu
	for child in editor.get_children():
		if child is PopupMenu and child.visible: menu = child
	assert(menu != null)
	menu.id_pressed.emit(0)
	menu.hide()
	await _settle()
	assert(editor.effect_data.size() == 2 and editor.effect_data[1].value == 3)
	editor._undo()
	await _settle()
	assert(editor.effect_data.size() == 1)
	var script: Dictionary = editor._build_skill().duplicate(true)
	assert(editor._collect_errors().is_empty())
	await _click(bench.try_button.get_global_rect().get_center())
	await _settle()
	var trial
	for child in editor.get_children():
		if child.get_script() == preload("res://SkillTryout.gd"): trial = child
	assert(trial != null, "Try must open from the toolbar")
	assert(trial.last_game.player2_field.slots[2].hp == 7, "trial must execute the current skill through real rules")
	trial.stage.finish()
	assert(trial.report.get_parsed_text().contains("3"))
	await _capture("editor-try-skill")
	trial.skill.probability = 0
	trial.run_trial()
	assert(trial.last_game.player2_field.slots[2].hp == 10, "failed probability must skip the effects")
	trial.skill = script.duplicate(true)
	trial.skill.effects[0].erase("value")
	trial.skill.effects[0].value_expr = {"kind":"expr","op":"rand","a":{"kind":"num","value":2},"b":{"kind":"num","value":4}}
	for i in range(8):
		trial.run_trial()
		var hp: int = trial.last_game.player2_field.slots[2].hp
		assert(hp >= 6 and hp <= 8, "random reporter must run within its actual bounds")
	trial.skill = {"probability":100,"effects":[{"effect":SkillEngine.EFFECT_REPEAT,"repeat_count":2,"then_effects":script.effects.duplicate(true)}]}
	trial.run_trial()
	assert(trial.last_game.player2_field.slots[2].hp == 4, "nested trial must execute and describe both repetitions")
	trial.stage.finish()
	assert(trial.report.get_parsed_text().count("3") == 2)
	trial.skill = {"probability":100,"effects":[{"effect":SkillEngine.EFFECT_IF_ELSE,"condition":{"op":">=","lhs":{"kind":"num","value":1},"rhs":{"kind":"num","value":2}},"then_effects":script.effects.duplicate(true),"else_effects":[{"effect":SkillEngine.EFFECT_HEAL,"target":SkillEngine.TARGET_SELF,"value":2}]}]}
	trial.run_trial()
	assert(trial.last_game.player_field.slots[2].hp == 12 and trial.last_game.player2_field.slots[2].hp == 10, "false branch must heal self and skip enemy damage")
	var back: Button
	for button in trial.find_children("*","Button",true,false):
		if button.text == Locale.t("common.back"): back = button
	await _click(back.get_global_rect().get_center())
	await _settle()
	assert(editor._build_skill() == script and PlayerData.card_draft == draft, "trying a skill must preserve the editor and saved draft")
	# The step log is a route back to the corresponding editable block.
	await _click(bench.try_button.get_global_rect().get_center())
	await _settle()
	for child in editor.get_children():
		if child.get_script() == preload("res://SkillTryout.gd"): trial = child
	trial.stage.finish()
	await _click(trial.report.get_global_rect().position+Vector2(24,12))
	await _settle()
	assert(not is_instance_valid(trial) and editor._build_skill() == script)
	block = editor.effects_list.get_child(0).body_container.get_child(0)
	assert(bench.workspace.get_global_rect().has_point(block.get_global_rect().get_center()), "a clicked execution step must reveal its block in the editor")
	# Hold a dragged tail near the canvas edge; the view must move without dropping.
	block = editor.effects_list.get_child(0).body_container.get_child(0)
	var start: Vector2 = block.get_global_transform() * Vector2(14,14)
	var edge: Vector2 = bench.workspace.get_global_rect().end - Vector2(10,100)
	var old_pan: Vector2 = bench.workspace.pan
	motion = InputEventMouseMotion.new()
	motion.position = start
	get_viewport().push_input(motion,true)
	await _mouse(start,MOUSE_BUTTON_LEFT,true)
	for i in range(1,10):
		motion = InputEventMouseMotion.new()
		motion.position = start.lerp(edge,float(i)/9)
		motion.relative = (edge-start)/9
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		await get_tree().process_frame
	assert(get_viewport().gui_is_dragging())
	await get_tree().create_timer(0.25).timeout
	assert(bench.workspace.pan.x < old_pan.x - 30, "dragging near the edge must pan the canvas")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape,true)
	await _mouse(edge,MOUSE_BUTTON_LEFT,false)
	await _settle()
	assert(editor._build_skill() == script and editor.loose_groups.is_empty(), "cancelling an edge drag must preserve the script")
	editor._add_repeat_block()
	editor._apply_drop({"type":"effect_block","effect_id":SkillEngine.EFFECT_HEAL},[1,"then"],0)
	editor.effect_data[1].then_effects[0].target = SkillEngine.TARGET_SELF
	editor.effect_data[1].then_effects[0].value = 2
	editor.effect_data[1].repeat_count = 2
	editor._refresh_script()
	await _settle()
	bench.workspace.reset_view()
	await _settle()
	await _capture("editor-compact-stack")
	for language in ["zh","en"]:
		Locale.language = language
		if language == "en":
			editor.queue_free()
			await get_tree().process_frame
			editor = preload("res://SkillEditor.tscn").instantiate()
			add_child(editor)
			await _settle()
			bench = editor.workbench
			editor._add_effect_block(SkillEngine.EFFECT_DAMAGE)
			editor.effect_data[0].merge({"target":SkillEngine.TARGET_SINGLE,"target_side":SkillEngine.TARGET_SIDE_ENEMY,"value":3},true)
			editor._on_block_changed([0])
			editor._refresh_script()
		for dimensions in [Vector2i(960,540),Vector2i(1280,720)]:
			get_window().size = dimensions
			await _settle()
			for button in bench.toolbar.get_children():
				if button is Button: assert(get_viewport().get_visible_rect().encloses(button.get_global_rect()), "toolbar must fit at %s" % dimensions)
			var palette: Control = editor.get_node("Panel/Margin/HBox/PalettePanel")
			assert(palette.get_global_rect().encloses(editor.palette_search.get_global_rect()), "search must stay inside the palette: %s %s, minimum %s" % [palette.get_global_rect(),editor.palette_search.get_global_rect(),editor.palette_search.get_combined_minimum_size()])
			await _capture("editor-polish-%s-%d" % [language,dimensions.x])
			if dimensions.x == 960:
				await _click(bench.try_button.get_global_rect().get_center())
				await _settle()
				for child in editor.get_children():
					if child.get_script() == preload("res://SkillTryout.gd"): trial = child
				assert(is_instance_valid(trial))
				for panel in trial.find_children("*","PanelContainer",true,false):
					assert(get_viewport().get_visible_rect().encloses(panel.get_global_rect()), "tryout must fit the small window")
				await _capture("editor-try-%s-960" % language)
				trial.queue_free()
				await _settle()
	print("TEST_SKILL_EDITOR_POLISH_OK")
	get_tree().quit(0)
