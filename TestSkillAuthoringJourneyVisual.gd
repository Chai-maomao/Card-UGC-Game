extends "res://TestSkillNestingVisual.gd"

func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	Input.use_accumulated_input = false
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.editing_skill_index = 0
	PlayerData.init_card_draft()
	var original_draft := PlayerData.card_draft.duplicate(true)
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	await _click(editor._template_btn.get_global_rect().get_center())
	await _settle()
	var strike: Button
	for button in editor.find_children("*","Button",true,false):
		if button.text == Locale.t("skill_template.strike"): strike = button
	assert(strike != null)
	await _click(strike.get_global_rect().get_center())
	await _settle()
	assert(editor.effect_data.size() == 1 and editor.effect_data[0].value == 3)
	assert(editor.current_trigger_key == SkillEngine.TRIGGER_ON_ACTIVATE)
	# Extend the template into a real conditional self-heal skill.
	await _palette_click("effect_id",SkillEngine.EFFECT_IF)
	assert(editor.effect_data.size() == 2)
	await _palette_drop("logic_kind","and",_socket(1,[]))
	await _palette_drop("boolean_kind","compare",_socket(1,["lhs"]))
	var values := _socket(1,["lhs"]).find_children("*","ValueSlot",true,false)
	await _palette_drop("var_id",SkillEngine.VAR_HAND_COUNT,values[0])
	values = _socket(1,["lhs"]).find_children("*","ValueSlot",true,false)
	await _type_number(values.back(),"3")
	var branch: SkillBlock = editor.effects_list.get_child(0).body_container.get_child(1)
	await _palette_drop("effect_id",SkillEngine.EFFECT_HEAL,branch.then_container)
	branch = editor.effects_list.get_child(0).body_container.get_child(1)
	var heal: SkillBlock = branch.then_container.get_child(0)
	for slot in heal.find_children("*","TargetSlot",true,false):
		if slot.kind == "target":
			await _palette_drop("target_kind",SkillEngine.TARGET_SELF,slot)
			break
	branch = editor.effects_list.get_child(0).body_container.get_child(1)
	heal = branch.then_container.get_child(0)
	await _type_number(heal.find_children("*","ValueSlot",true,false)[0],"2")
	# Compile with an off-screen inner hole, then navigate using the real popup.
	editor.workbench.workspace.pan += Vector2(-900,-700)
	editor.workbench.workspace._sync_view()
	await _click(editor.workbench.compile_button.get_global_rect().get_center())
	await _settle()
	assert(not editor.workbench.has_compiled)
	var locate: Button
	for button in editor.find_children("*","Button",true,false):
		if button.text == Locale.t("skill_editor.locate_issue"): locate = button
	assert(locate != null, "compile must offer a route to the actual error")
	await _click(locate.get_global_rect().get_center())
	await _settle()
	var hole := _socket(1,["rhs"])
	assert(editor.workbench.workspace.get_global_rect().has_point(hole.get_global_rect().get_center()))
	assert(hole.has_node("ValidationOutline"), "navigation must reveal the precise inner condition hole")
	await _capture("authoring-located-hole")
	await _palette_drop("boolean_kind","compare",hole)
	values = _socket(1,["rhs"]).find_children("*","ValueSlot",true,false)
	await _palette_drop("var_id",SkillEngine.VAR_MANA_CURRENT,values[0])
	values = _socket(1,["rhs"]).find_children("*","ValueSlot",true,false)
	await _type_number(values.back(),"2")
	await _click(editor.workbench.compile_button.get_global_rect().get_center())
	await _settle()
	assert(editor.workbench.has_compiled and editor._collect_errors().is_empty())
	assert(not _socket(1,["rhs"]).has_node("ValidationOutline"))
	assert(PlayerData.card_draft == original_draft, "compilation must not save the editing draft")
	await _click(editor.workbench.try_button.get_global_rect().get_center())
	await _settle()
	var trial: Control
	for child in editor.get_children():
		if child.get_script() == preload("res://SkillTryout.gd"): trial = child
	assert(trial != null)
	assert(trial.last_game.player_field.slots[2].hp == 12 and trial.last_game.player2_field.slots[2].hp == 7, "the assembled condition must execute using actual hand and elixir values")
	trial.stage.finish()
	await _capture("authoring-trial")
	var back: Button
	for button in trial.find_children("*","Button",true,false):
		if button.text == Locale.t("common.back"): back = button
	await _click(back.get_global_rect().get_center())
	await _settle()
	var expected: Dictionary = editor._build_skill().duplicate(true)
	get_tree().current_scene = null
	await _click(editor.save_button.get_global_rect().get_center())
	await get_tree().scene_changed
	await _settle()
	assert(SkillUndoManager.deep_equal(PlayerData.card_draft.skill1,expected))
	var card_editor: Control = get_tree().current_scene
	editor.queue_free()
	await _settle()
	card_editor.get_node("Panel/MarginContainer/ScrollContainer").ensure_control_visible(card_editor.edit_skill1_btn)
	await _settle()
	await _click(card_editor.edit_skill1_btn.get_global_rect().get_center())
	await get_tree().scene_changed
	await _settle()
	editor = get_tree().current_scene
	assert(SkillUndoManager.deep_equal(editor._build_skill(),expected), "the complete authored expression tree must survive save and reopen")
	assert(editor._collect_errors().is_empty())
	editor.workbench.workspace.reset_view()
	await _settle()
	await _capture("authoring-reopened")
	# Check the new error-navigation controls in the smaller English layout.
	editor.queue_free()
	await _settle()
	Locale.language = "en"
	get_window().size = Vector2i(960,540)
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	var filled := _socket(1,["rhs"])
	await _drag(filled.get_global_transform()*Vector2(3,filled.size.y/2),editor.palette_title.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
	await _settle()
	assert(editor.effect_data[1].condition.rhs.is_empty())
	await _click(editor.workbench.compile_button.get_global_rect().get_center())
	await _settle()
	locate = null
	for button in editor.find_children("*","Button",true,false):
		if button.text == Locale.t("skill_editor.locate_issue"): locate = button
	assert(locate != null and get_viewport().get_visible_rect().encloses(locate.get_global_rect()))
	await _capture("authoring-error-en-960")
	await _click(locate.get_global_rect().get_center())
	await _settle()
	assert(editor.workbench.workspace.get_global_rect().has_point(_socket(1,["rhs"]).get_global_rect().get_center()))
	print("TEST_SKILL_AUTHORING_JOURNEY_VISUAL_OK")
	get_tree().quit(0)

func _palette_click(field: String, value: String) -> void:
	var target: SkillPaletteBlock
	for button in editor.palette_vbox.find_children("*","SkillPaletteBlock",true,false):
		if str(button.get(field)) == value: target = button; break
	assert(target != null)
	editor.palette_search.text = target.text
	editor._filter_palette(target.text)
	await _settle()
	editor.palette_vbox.get_parent().ensure_control_visible(target)
	await _settle()
	await _click(target.get_global_rect().get_center())
	await _settle()

func _type_number(slot: Control, value: String) -> void:
	var input: LineEdit = slot.find_children("*","LineEdit",true,false)[0]
	await _click(input.get_global_rect().get_center())
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.ctrl_pressed = true
	key.pressed = true
	get_viewport().push_input(key,true)
	for digit in value:
		key = InputEventKey.new()
		key.keycode = digit.unicode_at(0)
		key.unicode = digit.unicode_at(0)
		key.pressed = true
		get_viewport().push_input(key,true)
	key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	get_viewport().push_input(key,true)
	await _settle()
