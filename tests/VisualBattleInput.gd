extends RefCounted

# Exercise the visible renderer rather than clicking retained, invisible 2D controls.
static func click(viewport: Viewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event,true)
		await viewport.get_tree().process_frame

static func action(viewport: Viewport, battle: Node, card_ui: Control, skill_index: int = -1) -> void:
	if battle.get("tabletop") == null:
		var button: Button = card_ui.normal_atk_btn if skill_index < 0 else card_ui.get("skill%d_btn" % (skill_index+1))
		await click(viewport,button.get_global_rect().get_center())
		return
	var slot: Control = card_ui.get_parent()
	await click(viewport,slot.get_global_rect().get_center())
	await viewport.get_tree().process_frame
	assert(is_instance_valid(battle.card_inspector) and battle.card_inspector.visible,"visible 3D card must open its action panel")
	var button: Button = battle.card_inspector.find_child("TabletopAttack" if skill_index < 0 else "TabletopSkill%d" % skill_index,true,false)
	assert(button != null and not button.disabled and button.is_visible_in_tree(),"the requested 3D action must be available")
	await click(viewport,button.get_global_rect().get_center())
