extends Node

# Regression test for the battle card face layout:
#  1. With up to 3 skills the action column has 4 stacked chips (basic attack
#     + skill 1..3). Every visible button must stay fully inside the card and
#     inside the ActionButtons column — the 3rd button must NOT be half
#     clipped and nothing may spill past the card bottom edge.
#  2. The type accent must stay a thin line (<= 2px at scale 1).

var _card: Node


func _ready() -> void:
	Locale.language = "zh"
	var scene: PackedScene = load("res://CardUI.tscn")
	_card = scene.instantiate()
	add_child(_card)
	await get_tree().process_frame

	var skills: Array = []
	for i in range(3):
		skills.append({
			"skill_name": "技能%d" % (i + 1),
			"trigger": SkillEngine.TRIGGER_ON_ATTACK,
			"probability": 100,
			"effects": [{
				"target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ENEMY,
				"effect": SkillEngine.EFFECT_DAMAGE,
				"value": 1,
			}],
		})
	var card := CardData.new("三技卡", 3, 5, 2, skills)
	_card.call("set_card", card)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_buttons("3skills", 4)
	_card.call("apply_ui_scale", 0.75)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_buttons("3skills-compact", 4)
	_card.call("apply_ui_scale", 1.0)

	var card2 := CardData.new("单技卡", 1, 2, 1, [skills[0]])
	_card.call("set_card", card2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_buttons("1skill", 2)
	_card.call("set_battle_layout_preview", true)
	await get_tree().process_frame
	_check_buttons("static-preview", 2)
	if not _card.get_node("ActionButtons/NormalAtkButton").visible:
		push_error("CARD_STATIC_PREVIEW_FAIL display card did not retain the battle ATK layout")
		get_tree().quit(1)
		return
	await _check_spell_and_parasite_affordances()
	await _check_drag_preview(Vector2(16, 28))
	await _check_drag_preview(Vector2(94, 132))
	_check_card_shadow_contexts()
	await _check_slot_has_no_card_shadow(card2)
	await _check_limited_skill_disabled()
	await _check_slot_arrival_motion(card2)
	await _check_swap_motion(card2, card)
	if OS.get_cmdline_user_args().has("--visual-motion"):
		_show_motion_preview(card2, card)
		return
	if OS.get_cmdline_user_args().has("--visual"):
		_show_drag_previews()
		return

	print("TEST_CARD_UI_LAYOUT_OK")
	get_tree().quit(0)


func _check_buttons(tag: String, expected: int) -> void:
	var card_rect: Rect2 = _card.get_global_rect()
	var face_rect: Rect2 = _card.get_node("Background").get_global_rect()
	var box: Control = _card.get_node("ActionButtons")
	var box_rect: Rect2 = box.get_global_rect()
	var visible := 0
	for btn_path in ["ActionButtons/NormalAtkButton", "ActionButtons/Skill1Button", "ActionButtons/Skill2Button", "ActionButtons/Skill3Button"]:
		var btn: Control = _card.get_node(btn_path)
		if not btn.visible:
			continue
		visible += 1
		var r: Rect2 = btn.get_global_rect()
		print("CARD_LAYOUT %s btn=%s y=%.1f..%.1f h=%.1f box_bottom=%.1f card_bottom=%.1f" % [
			tag, btn_path.get_file(), r.position.y, r.end.y, r.size.y, box_rect.end.y, card_rect.end.y])
		if r.size.y <= 0.0:
			push_error("CARD_LAYOUT_FAIL %s %s zero height" % [tag, btn_path.get_file()])
			get_tree().quit(1)
			return
		if r.end.y > card_rect.end.y + 0.5:
			push_error("CARD_LAYOUT_FAIL %s %s spills past card bottom %.1f > %.1f" % [tag, btn_path.get_file(), r.end.y, card_rect.end.y])
			get_tree().quit(1)
			return
		if r.end.y > box_rect.end.y + 0.5:
			push_error("CARD_LAYOUT_FAIL %s %s spills past action column %.1f > %.1f" % [tag, btn_path.get_file(), r.end.y, box_rect.end.y])
			get_tree().quit(1)
			return
		# Keep enough room for the card-button hover shadow so its lower edge
		# remains inside the physical card face.
		if r.end.y > face_rect.end.y - 4.0 * float(_card.ui_scale) + 0.5:
			push_error("CARD_LAYOUT_FAIL %s %s lacks bottom shadow clearance %.1f > %.1f" % [tag, btn_path.get_file(), r.end.y, face_rect.end.y])
			get_tree().quit(1)
			return
	print("CARD_LAYOUT %s visible=%d expected=%d box_h=%.1f" % [tag, visible, expected, box_rect.size.y])
	if visible != expected:
		push_error("CARD_LAYOUT_FAIL %s expected %d visible buttons, got %d" % [tag, expected, visible])
		get_tree().quit(1)
		return
	var accent: ColorRect = _card.get_node("TypeAccent")
	print("CARD_LAYOUT %s accent_h=%.1f" % [tag, accent.size.y])
	if accent.size.y > 2.5:
		push_error("CARD_LAYOUT_FAIL %s type accent too thick: %.1f" % [tag, accent.size.y])
		get_tree().quit(1)
		return


func _check_spell_and_parasite_affordances() -> void:
	var spell_ui = preload("res://CardUI.tscn").instantiate()
	add_child(spell_ui)
	var spell := CardData.new("落雷", 1, 0, 0, [{"trigger": SkillEngine.TRIGGER_ON_CAST, "effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}]}])
	spell.card_type = "spell"
	spell_ui.set_card(spell)
	spell_ui.is_hand_card = true
	await get_tree().process_frame
	if spell_ui.get_node("ActionButtons").is_visible_in_tree() or spell_ui.get_node("ActionButtons/NormalAtkButton").is_visible_in_tree():
		push_error("CARD_SPELL_DRAG_FAIL hand spell exposed action buttons")
		get_tree().quit(1)
		return
	var holder: Control = spell_ui.call("_build_drag_preview", Vector2(30, 40))
	add_child(holder)
	await get_tree().process_frame
	await get_tree().process_frame
	var preview: Control = holder.get_node("PreviewCard")
	if preview.get_node("ActionButtons").is_visible_in_tree() or preview.get_node("ActionButtons/NormalAtkButton").is_visible_in_tree():
		push_error("CARD_SPELL_DRAG_FAIL spell preview exposed action buttons")
		get_tree().quit(1)
		return

	var host_ui = preload("res://CardUI.tscn").instantiate()
	add_child(host_ui)
	var host := CardData.new("宿主", 1, 5, 2)
	var shield := CardData.new("护巢虫", 1, 3, 1, [{"skill_name": "反击", "trigger": SkillEngine.TRIGGER_ON_DAMAGED, "effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}]}])
	shield.card_type = "parasite"
	ParasiteRules.attach(shield, host)
	host_ui.set_card(host)
	await get_tree().process_frame
	var hp: Label = host_ui.get_node("HpLabel")
	if not hp.text.contains("(3)") or not hp.tooltip_text.begins_with("寄生卡的生命值"):
		push_error("CARD_PARASITE_HP_FAIL host did not expose absorbing parasite HP")
		get_tree().quit(1)
		return
	var attachment_tip: String = host_ui.call("_format_parasite_attachment_tooltip", shield)
	if attachment_tip.find("承伤方式") < 0 or attachment_tip.find("寄生被动") < attachment_tip.find("承伤方式"):
		push_error("CARD_PARASITE_HP_FAIL damage mode was presented as part of the passive")
		get_tree().quit(1)
		return

	var linked_host := CardData.new("依附宿主", 1, 5, 2)
	var linked := CardData.new("依附虫", 1, 4, 1)
	linked.card_type = "parasite"
	linked.parasite_damage_mode = CardData.PARASITE_DAMAGE_LINKED
	ParasiteRules.attach(linked, linked_host)
	host_ui.set_card(linked_host)
	if (host_ui.get_node("HpLabel") as Label).text.contains("(") or (host_ui.get_node("HpLabel") as Label).tooltip_text != "":
		push_error("CARD_PARASITE_HP_FAIL linked parasite exposed an absorbing HP pool")
		get_tree().quit(1)
		return
	holder.queue_free()
	spell_ui.queue_free()
	host_ui.queue_free()


func _check_drag_preview(grab_position: Vector2) -> void:
	var holder: Control = _card.call("_build_drag_preview", grab_position)
	add_child(holder)
	await get_tree().process_frame
	await get_tree().process_frame
	var preview_card: Control = holder.get_node("PreviewCard")
	var shadow: Control = holder.get_node("PreviewShadow")
	var scale_factor: float = _card.DRAG_PREVIEW_SCALE
	var pointer_on_card := preview_card.position + grab_position * scale_factor
	if not pointer_on_card.is_equal_approx(Vector2.ZERO):
		push_error("CARD_DRAG_PREVIEW_FAIL grab point moved away from pointer: %s" % pointer_on_card)
		get_tree().quit(1)
		holder.queue_free()
		return
	var displayed_size := preview_card.size * scale_factor
	if shadow.size.x >= displayed_size.x or shadow.size.y >= displayed_size.y:
		push_error("CARD_DRAG_PREVIEW_FAIL shadow must be smaller than card: %s >= %s" % [shadow.size, displayed_size])
		get_tree().quit(1)
		holder.queue_free()
		return
	var relative_offset := shadow.position - preview_card.position
	if relative_offset.x >= 0 or relative_offset.y >= 0:
		push_error("CARD_DRAG_PREVIEW_FAIL shadow must offset upper-left: %s" % relative_offset)
		get_tree().quit(1)
		holder.queue_free()
		return
	var built_in_shadow: Control = preview_card.get_node("CardShadow")
	if built_in_shadow.visible:
		push_error("CARD_DRAG_PREVIEW_FAIL duplicated lower shadow must be hidden")
		get_tree().quit(1)
		holder.queue_free()
		return
	print("CARD_DRAG_PREVIEW grab=%s origin=%s shadow_offset=%s shadow=%s card=%s" % [
		grab_position, preview_card.position, relative_offset, shadow.size, displayed_size])
	holder.queue_free()


func _check_card_shadow_contexts() -> void:
	var shadow: Control = _card.get_node("CardShadow")
	if shadow.visible:
		push_error("CARD_STATIC_SHADOW_FAIL standalone/static card retained a shadow")
		get_tree().quit(1)
		return
	if _card.call("_get_drag_data", Vector2(20, 20)) != null:
		push_error("CARD_STATIC_DRAG_FAIL static card started a hand-card drag")
		get_tree().quit(1)
		return
	_card.is_hand_card = true
	if not shadow.visible:
		push_error("CARD_HAND_SHADOW_FAIL hand card did not enable its shadow")
		get_tree().quit(1)
		return
	_card.is_hand_card = false
	if shadow.visible:
		push_error("CARD_STATIC_SHADOW_FAIL leaving the hand retained a shadow")
		get_tree().quit(1)
		return
	print("CARD_SHADOW_CONTEXT static=false hand=true restored_static=false")


func _show_drag_previews() -> void:
	DisplayServer.window_set_title("CARDEX · 卡牌抓取点与阴影验收")
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.10, 0.12, 0.16)
	add_child(backdrop)
	var title := Label.new()
	title.text = "拖拽预览：十字中心就是鼠标位置"
	title.position = Vector2(360, 72)
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	var examples := [
		{"at": Vector2(310, 305), "grab": Vector2(16, 28), "label": "从卡面左上抓取"},
		{"at": Vector2(820, 305), "grab": Vector2(94, 132), "label": "从卡面右下抓取"},
	]
	for example in examples:
		var holder: Control = _card.call("_build_drag_preview", example.grab)
		holder.position = example.at
		add_child(holder)
		var caption := Label.new()
		caption.text = example.label
		caption.position = example.at + Vector2(-86, 125)
		caption.custom_minimum_size = Vector2(172, 28)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 16)
		add_child(caption)
		_add_crosshair(example.at)


func _check_slot_has_no_card_shadow(card_data: CardData) -> void:
	var slot = preload("res://SlotUI.tscn").instantiate()
	add_child(slot)
	await get_tree().process_frame
	slot.set_card(card_data)
	await get_tree().process_frame
	var slotted_card: Control = slot.current_card_ui
	if slotted_card.get_node("CardShadow").visible:
		push_error("CARD_SLOT_SHADOW_FAIL slotted card retained its standalone shadow")
		get_tree().quit(1)
		slot.queue_free()
		return
	if not bool(slotted_card.get("_battle_drag_enabled")):
		push_error("CARD_SLOT_DRAG_FAIL player field card cannot start a position swap")
		get_tree().quit(1)
		slot.queue_free()
		return
	slot.set_visual_variant("enemy")
	if bool(slotted_card.get("_battle_drag_enabled")):
		push_error("CARD_SLOT_DRAG_FAIL enemy field card remained draggable")
		get_tree().quit(1)
		slot.queue_free()
		return
	print("CARD_SLOT_SHADOW hidden=true")
	slot.queue_free()


func _check_limited_skill_disabled() -> void:
	var limited_ui = preload("res://CardUI.tscn").instantiate()
	add_child(limited_ui)
	limited_ui.set_embedded_in_slot(true)
	var limited := CardData.new("限定测试", 1, 3, 1, [{
		"skill_name": "一次技", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "max_uses": 1,
		"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_ATTACK, "value": 1}],
	}])
	limited.skills_used_count[0] = 1
	limited_ui.set_card(limited)
	await get_tree().process_frame
	var button: Button = limited_ui.get_node("ActionButtons/Skill1Button")
	if not button.disabled or not button.tooltip_text.contains(Locale.t("card.skill_limit_reached")):
		push_error("CARD_LIMITED_SKILL_FAIL exhausted limited skill did not grey out with a reason")
		get_tree().quit(1)
	limited_ui.queue_free()


func _check_slot_arrival_motion(card_data: CardData) -> void:
	var fx_layer := CanvasLayer.new()
	add_child(fx_layer)
	var slot = preload("res://SlotUI.tscn").instantiate()
	add_child(slot)
	await get_tree().process_frame
	slot.set_card(card_data)
	BattleFx.summon_landing(fx_layer, slot, 1.0)
	var card: Control = slot.current_card_ui
	var glow: Control = slot.get_node("ArrivalGlow")
	if not glow.visible or (card.position == Vector2.ZERO and card.scale == Vector2.ONE):
		push_error("CARD_ARRIVAL_FAIL summon did not start the slot-lock motion")
		get_tree().quit(1)
		slot.queue_free()
		fx_layer.queue_free()
		return
	await get_tree().create_timer(0.20).timeout
	var edge_particles: Array[GPUParticles2D] = []
	for child in fx_layer.get_children():
		if child is GPUParticles2D:
			edge_particles.append(child)
	var total_particles := 0
	var has_top := false
	var has_bottom := false
	var has_left := false
	var has_right := false
	var slot_center: Vector2 = slot.global_position + slot.size * 0.5
	for particles in edge_particles:
		total_particles += particles.amount
		has_top = has_top or particles.position.y < slot_center.y - slot.size.y * 0.5
		has_bottom = has_bottom or particles.position.y > slot_center.y + slot.size.y * 0.5
		has_left = has_left or particles.position.x < slot_center.x - slot.size.x * 0.5
		has_right = has_right or particles.position.x > slot_center.x + slot.size.x * 0.5
	if edge_particles.size() != 4 or total_particles != 12 or not (has_top and has_bottom and has_left and has_right):
		push_error("CARD_ARRIVAL_FAIL white particles were not emitted from all four slot edges")
		get_tree().quit(1)
		slot.queue_free()
		fx_layer.queue_free()
		return
	for particles in edge_particles:
		if not particles.modulate.is_equal_approx(Color(1.0, 1.0, 1.0, 0.96)):
			push_error("CARD_ARRIVAL_FAIL edge particle is not white")
			get_tree().quit(1)
			return
		var particle_material := particles.process_material as ParticleProcessMaterial
		if particle_material == null or particle_material.scale_max > 0.16 or particle_material.spread > 35.0:
			push_error("CARD_ARRIVAL_FAIL edge particles can spill back across the card face")
			get_tree().quit(1)
			return
	await get_tree().create_timer(0.20).timeout
	if glow.visible or not card.position.is_equal_approx(Vector2.ZERO) or not card.scale.is_equal_approx(Vector2.ONE) or not is_equal_approx(card.modulate.a, 1.0):
		push_error("CARD_ARRIVAL_FAIL summon did not settle cleanly")
		get_tree().quit(1)
		slot.queue_free()
		fx_layer.queue_free()
		return
	print("CARD_ARRIVAL summon_started=true white_particles=12 four_edges=true settled=true")
	slot.queue_free()
	fx_layer.queue_free()


func _check_swap_motion(card_a: CardData, card_b: CardData) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var source = preload("res://SlotUI.tscn").instantiate()
	var target = preload("res://SlotUI.tscn").instantiate()
	add_child(source)
	add_child(target)
	source.position = Vector2(80, 260)
	target.position = Vector2(260, 260)
	await get_tree().process_frame
	source.set_card(card_a)
	target.set_card(card_b)
	var delta: Vector2 = target.position - source.position
	BattleFx.move_swap(layer, [
		[source.current_card_ui, delta, Vector2.INF, target],
		[target.current_card_ui, -delta, Vector2.INF, source],
	])
	# Match the deferred battlefield rebuild that follows a real move.
	source.set_card(card_b)
	target.set_card(card_a)
	await get_tree().process_frame
	await get_tree().process_frame
	if source.current_card_ui.visible or target.current_card_ui.visible:
		push_error("CARD_SWAP_MOTION_FAIL destination cards were visible beneath their moving ghosts")
		get_tree().quit(1)
	else:
		await get_tree().create_timer(0.38).timeout
		if not source.current_card_ui.visible or not target.current_card_ui.visible:
			push_error("CARD_SWAP_MOTION_FAIL destination cards were not revealed on arrival")
			get_tree().quit(1)
		else:
			print("CARD_SWAP_MOTION ghosts=true duplicate_faces=false arrivals=true")
	source.queue_free()
	target.queue_free()
	layer.queue_free()


func _add_crosshair(at: Vector2) -> void:
	var horizontal := ColorRect.new()
	horizontal.color = Color(0.25, 0.95, 1.0)
	horizontal.position = at + Vector2(-10, -1)
	horizontal.size = Vector2(20, 2)
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(horizontal)
	var vertical := ColorRect.new()
	vertical.color = horizontal.color
	vertical.position = at + Vector2(-1, -10)
	vertical.size = Vector2(2, 20)
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vertical)


func _show_motion_preview(card_a: CardData, card_b: CardData) -> void:
	DisplayServer.window_set_title("CARDEX · 部署与换位动效验收")
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.055, 0.075, 0.105)
	add_child(backdrop)
	var title := Label.new()
	title.text = "落槽（白色粒子） / 位置交换"
	title.position = Vector2(405, 70)
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)
	var deploy_label := Label.new()
	deploy_label.text = "部署落槽"
	deploy_label.position = Vector2(185, 205)
	deploy_label.add_theme_font_size_override("font_size", 17)
	add_child(deploy_label)
	var swap_label := Label.new()
	swap_label.text = "交换位置"
	swap_label.position = Vector2(675, 205)
	swap_label.add_theme_font_size_override("font_size", 17)
	add_child(swap_label)
	var fx_layer := CanvasLayer.new()
	add_child(fx_layer)
	var deploy_slot = preload("res://SlotUI.tscn").instantiate()
	var swap_left = preload("res://SlotUI.tscn").instantiate()
	var swap_right = preload("res://SlotUI.tscn").instantiate()
	deploy_slot.position = Vector2(170, 250)
	swap_left.position = Vector2(580, 250)
	swap_right.position = Vector2(760, 250)
	add_child(deploy_slot)
	add_child(swap_left)
	add_child(swap_right)
	swap_left.set_card(card_a)
	swap_right.set_card(card_b)
	_run_motion_preview(deploy_slot, swap_left, swap_right, fx_layer, card_a, card_b)


func _run_motion_preview(deploy_slot, swap_left, swap_right, fx_layer: CanvasLayer, card_a: CardData, card_b: CardData) -> void:
	while is_instance_valid(deploy_slot):
		deploy_slot.set_card(card_a)
		BattleFx.summon_landing(fx_layer, deploy_slot, 1.0)
		await get_tree().create_timer(0.85).timeout
		if not is_instance_valid(swap_left):
			return
		var left_card: CardData = swap_left.current_card_data
		var right_card: CardData = swap_right.current_card_data
		var delta: Vector2 = swap_right.position - swap_left.position
		BattleFx.move_swap(fx_layer, [
			[swap_left.current_card_ui, delta, Vector2.INF, swap_right],
			[swap_right.current_card_ui, -delta, Vector2.INF, swap_left],
		], 1.0)
		swap_left.set_card(right_card)
		swap_right.set_card(left_card)
		await get_tree().create_timer(0.85).timeout
		deploy_slot.clear_card()
		await get_tree().create_timer(0.30).timeout
