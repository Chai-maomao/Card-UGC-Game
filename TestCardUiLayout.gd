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

	var card2 := CardData.new("单技卡", 1, 2, 1, [skills[0]])
	_card.call("set_card", card2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_buttons("1skill", 2)

	print("TEST_CARD_UI_LAYOUT_OK")
	get_tree().quit(0)


func _check_buttons(tag: String, expected: int) -> void:
	var card_rect: Rect2 = _card.get_global_rect()
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
