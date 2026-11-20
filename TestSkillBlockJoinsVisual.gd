extends "res://TestSkillWorkspaceVisual.gd"

func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.init_card_draft()
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	if OS.get_cmdline_user_args().has("--conditions-only"):
		var passed := await _check_condition_swap()
		if passed:
			print("TEST_SKILL_CONDITION_SWAP_VISUAL_OK")
		get_tree().quit(0 if passed else 1)
		return
	if not await _check_independent_widths():
		get_tree().quit(1)
		return
	if OS.get_cmdline_user_args().has("--width-only"):
		print("TEST_SKILL_BLOCK_WIDTHS_VISUAL_OK")
		get_tree().quit(0)
		return
	var heal := {"effect":SkillEngine.EFFECT_HEAL,"target":SkillEngine.TARGET_SELF,"value":1}
	editor._apply_skill_template({"trigger":SkillEngine.TRIGGER_ON_SUMMON,"effects":[
		heal.duplicate(true),heal.duplicate(true),
		{"effect":SkillEngine.EFFECT_REPEAT,"repeat_count":2,"then_effects":[heal.duplicate(true),heal.duplicate(true)]},
		{"effect":SkillEngine.EFFECT_IF_ELSE,"condition":{"op":">=","lhs":{"kind":"num","value":1},"rhs":{"kind":"num","value":1}},"then_effects":[heal.duplicate(true)],"else_effects":[heal.duplicate(true)]}]})
	await _settle()
	var hat: SkillBlock = editor.effects_list.get_child(0)
	for zoom in [1.0,0.75]:
		editor.workbench.workspace.set_zoom(zoom)
		editor.workbench.workspace.pan = Vector2(32,40)
		editor.workbench.workspace._sync_view()
		await _settle()
		await _capture("block-joins-%d" % roundi(zoom*100))
		var snapshot := get_viewport().get_texture().get_image()
		var canvas: Control = editor.workbench.workspace
		var background := _pixel(snapshot,canvas.global_position+Vector2(6,6))
		for block: SkillBlock in [hat.body_container.get_child(2),hat.body_container.get_child(3)]:
			for body in [block.then_container,block.else_container]:
				if body == null: continue
				var first: Control = body.get_child(0)
				var last: Control = body.get_child(body.get_child_count()-1)
				var left := first.get_global_rect().position+Vector2(-3*zoom,first.size.y*zoom/2)
				var bottom := last.get_global_rect().position+Vector2(65*zoom,last.size.y*zoom+2*zoom)
				if _pixel(snapshot,left).is_equal_approx(background) or _pixel(snapshot,bottom).is_equal_approx(background):
					push_error("TEST_BLOCK_JOINS_FAILED: background is visible between the C-shaped arm and its attached child at zoom %s" % zoom)
					get_tree().quit(1)
					return
	if not await _check_press_and_hint():
		get_tree().quit(1)
		return
	editor.queue_free()
	await _settle()
	PlayerData.card_draft.card_type = "spell"
	editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	editor._apply_skill_template({"effects":[heal.duplicate(true),heal.duplicate(true)]})
	await _settle()
	for zoom in [1.0,0.75]:
		editor.workbench.workspace.set_zoom(zoom)
		editor.workbench.workspace.pan = Vector2(32,40)
		editor.workbench.workspace._sync_view()
		await _settle()
		await _capture("spell-joins-%d" % roundi(zoom*100))
		var snapshot := get_viewport().get_texture().get_image()
		var background := _pixel(snapshot,editor.workbench.workspace.global_position+Vector2(6,6))
		for block: Control in editor.effects_list.get_children():
			var join := block.get_global_rect().position+Vector2(60*zoom,-2*zoom)
			if _pixel(snapshot,join).is_equal_approx(background):
				push_error("TEST_BLOCK_JOINS_FAILED: a spell's event or neighboring block is separated by background")
				get_tree().quit(1)
				return
	print("TEST_SKILL_BLOCK_JOINS_VISUAL_OK")
	get_tree().quit(0)

func _pixel(snapshot: Image, point: Vector2) -> Color:
	var ratio := Vector2(snapshot.get_size())/get_viewport().get_visible_rect().size
	return snapshot.get_pixelv(Vector2i((point*ratio).floor()))


func _check_condition_swap() -> bool:
	var first := {"op": ">=", "lhs": {"kind": "num", "value": 1}, "rhs": {"kind": "num", "value": 2}}
	var second := {"op": "<=", "lhs": {"kind": "num", "value": 3}, "rhs": {"kind": "num", "value": 4}}
	editor._apply_skill_template({"trigger": SkillEngine.TRIGGER_ON_SUMMON, "effects": [
		{"effect": SkillEngine.EFFECT_IF, "condition": {"logic": "and", "lhs": first, "rhs": second}, "then_effects": []},
		{"effect": SkillEngine.EFFECT_IF, "then_effects": []},
	]})
	editor.workbench.workspace.set_zoom(0.65)
	editor.workbench.workspace.pan = Vector2(20, 20)
	editor.workbench.workspace._sync_view()
	await _settle()
	var branches := _condition_branches()
	if branches.size() != 2:
		push_error("TEST_CONDITION_SWAP_FAILED: expected two visible boolean sockets")
		return false
	await _drag(_condition_grab(branches[0]), _condition_drop_point(branches[1]), MOUSE_BUTTON_LEFT)
	await _settle()
	var tree: Dictionary = editor.effect_data[0].get("condition", {})
	if tree.get("lhs") != second or tree.get("rhs") != first:
		push_error("TEST_CONDITION_SWAP_FAILED: swapping occupied sockets must retain both conditions")
		return false
	await _capture("condition-swap")
	editor._undo()
	await _settle()
	tree = editor.effect_data[0].condition
	if tree.lhs != first or tree.rhs != second:
		push_error("TEST_CONDITION_SWAP_FAILED: one undo must restore both conditions")
		return false
	editor._redo()
	await _settle()
	branches = _condition_branches()
	var hat: SkillBlock = editor.effects_list.get_child(0)
	var parent: SkillBlock = hat.body_container.get_child(0)
	await _drag(_condition_grab(branches[1]), _condition_drop_point(parent.cond_slot), MOUSE_BUTTON_LEFT)
	await _settle()
	tree = editor.effect_data[0].condition
	if tree.lhs != second or tree.rhs != first or not editor.loose_reporters.is_empty():
		push_error("TEST_CONDITION_SWAP_FAILED: a condition cannot replace its own parent")
		return false
	branches = _condition_branches()
	hat = editor.effects_list.get_child(0)
	var empty: SkillBlock = hat.body_container.get_child(1)
	await _drag(_condition_grab(branches[1]), _condition_drop_point(empty.cond_slot), MOUSE_BUTTON_LEFT)
	await _settle()
	if not editor.effect_data[0].condition.rhs.is_empty() or editor.effect_data[1].get("condition") != first or _condition_branches()[1].get_child_count() != 0:
		push_error("TEST_CONDITION_SWAP_FAILED: moving a reporter into an empty socket must leave its source empty")
		return false
	await _capture("condition-empty-after-move")
	branches = _condition_branches()
	hat = editor.effects_list.get_child(0)
	var other: SkillBlock = hat.body_container.get_child(1)
	await _drag(_condition_grab(other.cond_slot), _condition_drop_point(branches[0]), MOUSE_BUTTON_LEFT)
	await _settle()
	if editor.effect_data[0].condition.lhs != first or editor.effect_data[1].condition != second:
		push_error("TEST_CONDITION_SWAP_FAILED: swapping between separate blocks must retain both conditions")
		return false
	return true


func _condition_branches() -> Array[Control]:
	var hat: SkillBlock = editor.effects_list.get_child(0)
	var effect: SkillBlock = hat.body_container.get_child(0)
	var branches: Array[Control] = []
	for node in effect.cond_slot.get_child(0).get_children():
		if node.get_script() == preload("res://SkillConditionSocket.gd"):
			branches.append(node)
	return branches


func _condition_grab(socket: Control) -> Vector2:
	var reporter: Control = socket.get_child(0)
	var first_input: Control = reporter.get_child(0)
	var operator: Control = reporter.get_child(1)
	return Vector2((first_input.get_global_rect().end.x + operator.global_position.x) / 2.0, reporter.get_global_rect().get_center().y)


func _condition_drop_point(socket: Control) -> Vector2:
	return Vector2(socket.global_position.x + 6 * socket.get_global_transform().get_scale().x, socket.get_global_rect().get_center().y)

func _check_independent_widths() -> bool:
	var short_effect := {"effect":SkillEngine.EFFECT_CHARM,"target":SkillEngine.TARGET_SINGLE}
	var long_effect := {"effect":SkillEngine.EFFECT_ADD_BUFF,"target":SkillEngine.TARGET_SINGLE,"buff_id":SkillEngine.BUFF_ATK_BOOST,"value":2,"duration":2}
	editor._apply_skill_template({"trigger":SkillEngine.TRIGGER_ON_ATTACK,"effects":[short_effect.duplicate(true)]})
	editor.loose_groups = {"width":{"position":[32,220],"effects":[long_effect.duplicate(true)]}}
	editor._refresh_script()
	editor._maybe_snapshot()
	editor.workbench.workspace.set_zoom(0.85)
	editor.workbench.workspace.pan = Vector2(28,28)
	editor.workbench.workspace._sync_view()
	await _settle()
	var hat: SkillBlock = editor.effects_list.get_child(0)
	var first: SkillBlock = hat.body_container.get_child(0)
	var original_width := first.size.x
	var loose: Control = editor.workbench.workspace.loose_views[0].get_child(0)
	await _drag(loose.get_global_transform()*Vector2(8,14),first.get_global_transform()*Vector2(8,first.size.y-2),MOUSE_BUTTON_LEFT)
	await _settle()
	if editor.effect_data.size() != 2 or not editor.loose_groups.is_empty():
		push_error("TEST_BLOCK_WIDTH_FAILED: dragging the long block must attach it below the short block")
		return false
	hat = editor.effects_list.get_child(0)
	first = hat.body_container.get_child(0)
	var second: SkillBlock = hat.body_container.get_child(1)
	await _capture("block-independent-widths")
	if not is_equal_approx(first.size.x,original_width) or second.size.x <= first.size.x:
		push_error("TEST_BLOCK_WIDTH_FAILED: attachment must preserve the preceding block's own width (%s -> %s; following %s)" % [original_width,first.size.x,second.size.x])
		return false
	if not is_equal_approx(first.global_position.x,second.global_position.x):
		push_error("TEST_BLOCK_WIDTH_FAILED: unequal blocks must keep their connectors aligned")
		return false
	editor._undo()
	await _settle()
	if editor.effect_data.size() != 1 or not is_equal_approx(editor.effects_list.get_child(0).body_container.get_child(0).size.x,original_width):
		push_error("TEST_BLOCK_WIDTH_FAILED: undo must restore the short block and its width")
		return false
	editor._redo()
	await _settle()
	if editor.effect_data.size() != 2 or not is_equal_approx(editor.effects_list.get_child(0).body_container.get_child(0).size.x,original_width):
		push_error("TEST_BLOCK_WIDTH_FAILED: redo must preserve independent widths")
		return false
	editor.loose_groups.clear()
	return true

func _check_press_and_hint() -> bool:
	editor.workbench.workspace.set_zoom(1.0)
	editor.workbench.workspace.pan = Vector2(32,40)
	editor.workbench.workspace._sync_view()
	await _settle()
	var hat: SkillBlock = editor.effects_list.get_child(0)
	var leaf: SkillBlock = hat.body_container.get_child(0)
	var before := get_viewport().get_texture().get_image()
	var face := leaf.get_global_transform()*Vector2(6,leaf.size.y/2)
	var edge := leaf.get_global_transform()*Vector2(0.5,leaf.size.y/2)
	# The last two rows also contain the next block's notch outline.
	var tab := leaf.get_global_transform()*Vector2(28,leaf.size.y-3)
	var next_outline := leaf.get_global_transform()*Vector2(28,leaf.size.y-1)
	var point := leaf.get_global_transform()*Vector2(8,14)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion,true)
	await _mouse(point,MOUSE_BUTTON_LEFT,true)
	await _settle()
	assert(leaf._press_shadow_alpha > 0.9, "the actual mouse press must activate feedback")
	await _capture("block-pressed-contour")
	var after := get_viewport().get_texture().get_image()
	var face_ratio := _pixel(after,face).g/_pixel(before,face).g
	var tab_ratio := _pixel(after,tab).g/_pixel(before,tab).g
	var edge_ratio := _pixel(after,edge).g/_pixel(before,edge).g
	var passed := face_ratio < 0.9 and absf(face_ratio-tab_ratio) < 0.06 and absf(face_ratio-edge_ratio) < 0.06
	if not passed:
		push_error("TEST_PRESS_CONTOUR_FAILED: body, tab and outline must dim together (ratios %s, %s, %s)" % [face_ratio, tab_ratio, edge_ratio])
	if not _pixel(after,next_outline).is_equal_approx(_pixel(before,next_outline)):
		passed = false
		push_error("TEST_PRESS_CONTOUR_FAILED: the adjoining block's notch must keep its own shading")
	await _mouse(point,MOUSE_BUTTON_LEFT,false)
	await _settle()
	var control: SkillBlock = hat.body_container.get_child(2)
	var child: Control = control.then_container.get_child(0)
	var hole := child.get_global_rect().end+Vector2(3,-child.size.y/2)
	before = get_viewport().get_texture().get_image()
	point = control.get_global_transform()*Vector2(8,16)
	motion = InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion,true)
	await _mouse(point,MOUSE_BUTTON_LEFT,true)
	await _settle()
	assert(control._press_shadow_alpha > 0.9)
	await _capture("control-pressed-contour")
	after = get_viewport().get_texture().get_image()
	if not _pixel(after,hole).is_equal_approx(_pixel(before,hole)):
		passed = false
		push_error("TEST_PRESS_CONTOUR_FAILED: press shading must leave the C-shaped opening transparent")
	await _mouse(point,MOUSE_BUTTON_LEFT,false)
	editor.effect_data.clear()
	editor._refresh_script()
	await _settle()
	hat = editor.effects_list.get_child(0)
	var cap: Control = hat.get_child(0).get_child(0)
	await _capture("empty-script-hint")
	# Empty nesting regions now intentionally contain no placeholder block/text.
	if hat.body_container.get_child_count() != 0 or hat.body_container.size.y <= 0 or hat.body_container.get_global_rect().position.y < cap.get_global_rect().end.y-preload("res://SkillSocketStyle.gd").JOIN_OVERLAP:
		passed = false
		push_error("TEST_EMPTY_HINT_FAILED: the empty socket must remain open below the event cap")
	return passed
