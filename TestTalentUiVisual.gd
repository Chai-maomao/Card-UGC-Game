extends Node

const OUTPUT_DIR := "res://artifacts"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer; run scripts/run_tests.ps1 -Suite visual")
		get_tree().quit(1)
		return
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await _capture_card_editor()
	await _capture_talent_editor()
	await _capture_picker()
	await _verify_silent_resolution_lock()
	print("TEST_TALENT_UI_VISUAL_OK")
	get_tree().quit(0)


func _capture_card_editor() -> void:
	PlayerData.card_draft = {
		"name": "星辉守卫", "cost": 3, "hp": 5, "atk": 2, "gender": "nonhuman", "card_type": "minion", "art_path": "",
		"skill1": {"skill_name": "守护", "trigger": SkillEngine.TRIGGER_ON_SUMMON, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_SHIELD, "value": 2}]},
		"skill2": {}, "skill3": {},
		"talent": {"skill_name": "适应", "skill_type": SkillEngine.SKILL_TYPE_TALENT, "trigger": SkillEngine.TRIGGER_ON_BOARD_CHANGED, "trigger_side": SkillEngine.TARGET_SIDE_ALLY, "effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_CHANGE_COST, "value": -1}]},
	}
	PlayerData.editing_index = -1
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	var scroll := editor.get_node("Panel/MarginContainer/ScrollContainer") as ScrollContainer
	scroll.scroll_vertical = 10000
	await _settle()
	await _save_view("talent_card_editor.png")
	editor.queue_free()
	await _settle()


func _capture_talent_editor() -> void:
	PlayerData.editing_skill_index = 3
	var editor := preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	await _save_view("talent_skill_editor.png")
	editor.queue_free()
	await _settle()


func _capture_picker() -> void:
	var background := ColorRect.new()
	background.color = Color(0.01, 0.025, 0.05)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var cards: Array = []
	for i in range(5):
		cards.append(CardData.new("候选卡 %d" % (i + 1), i + 1, 3 + i, 1 + i))
	var dialog = preload("res://CardCollectionDialog.gd").show_cards(self, cards, "选择一张卡牌", 2)
	await _settle()
	dialog._select(true, 1)
	dialog._select(true, 3)
	await _settle()
	await _save_view("card_selection_overlay.png")
	dialog.queue_free()
	background.queue_free()
	await _settle()


func _verify_silent_resolution_lock() -> void:
	var prior := GamePreferences.animation_acceleration_enabled()
	GamePreferences.set_animation_acceleration(false)
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(), CardDatabase.playtest_deck())
	var battle := preload("res://Main.tscn").instantiate()
	add_child(battle)
	await _settle()
	battle._on_skill_effect_resolved(null, SkillEngine.EFFECT_DAMAGE, null, 1)
	battle._on_skill_effect_resolved(null, SkillEngine.EFFECT_HEAL, null, 1)
	await get_tree().process_frame
	var blocker := battle.get("_resolution_blocker") as Control
	if blocker == null or not blocker.visible or blocker.get_child_count() != 0:
		push_error("Resolution input lock must stay active without displaying a resolving panel")
		get_tree().quit(1)
		return
	GamePreferences.set_animation_acceleration(prior)
	battle.queue_free()
	await _settle()


func _save_view(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OUTPUT_DIR + "/" + file_name)
	if error != OK:
		push_error("Screenshot failed: " + file_name)
		get_tree().quit(1)


func _settle() -> void:
	for _i in range(8):
		await get_tree().process_frame
