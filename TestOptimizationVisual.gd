extends Node


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual test requires a renderer")
		get_tree().quit(1)
		return
	get_tree().root.gui_embed_subwindows = true
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var backup := PlayerData.battle_preparation_snapshot()
	var old_draft := PlayerData.card_draft.duplicate(true)
	var old_context := PlayerData.card_playtest_context.duplicate(true)
	var card := CardData.new("连锁练习", 2, 5, 2, [{"trigger": "on_activate", "skill_name": "重复打击", "effects": [{"effect": "__repeat__", "repeat_count": 2, "then_effects": [{"effect": "damage", "target": "target_single", "target_side": "enemy", "value": 1}]}]}])
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(), CardDatabase.playtest_deck())
	PlayerData.card_playtest_context = {"test_card": PlayerData.serialize_card(card)}
	var battle := preload("res://Main.tscn").instantiate()
	add_child(battle)
	await _settle()
	battle.game.turn_number = 2
	battle.game.player_field.slots[0] = card
	battle.game.player2_field.slots[0] = CardData.new("目标守卫", 2, 8, 2)
	SkillEngine.trigger_single_skill(card, 0, battle.game.make_skill_context(0, 0, 2))
	var inspector: PlaytestInspector
	for child in battle.get_children():
		if child is PlaytestInspector: inspector = child
	if inspector == null:
		push_error("Inspector not installed")
		get_tree().quit(1)
		return
	inspector.show_trace()
	await _capture("optimization-inspector.png")
	inspector.dialog.hide()
	PracticeChallenges.show_picker(battle)
	await _capture("optimization-challenges.png")
	battle.queue_free()
	await _settle()
	PlayerData.card_playtest_context = {}
	PlayerData.card_draft = PlayerData.card_to_draft(card)
	PlayerData.card_draft.skill1.effects[0].repeat_expr = {"kind": "var", "var_id": "hand_count"}
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await _capture("optimization-balance.png")
	editor.queue_free()
	await _settle()
	SharePackage.edit_metadata(self, SharePackage.build([]), func(_data): pass)
	await _capture("optimization-share.png")
	PlayerData._apply_battle_preparation(backup)
	PlayerData.card_draft = old_draft
	PlayerData.card_playtest_context = old_context
	print("TEST_OPTIMIZATION_VISUAL_OK")
	get_tree().quit(0)


func _settle() -> void:
	for i in range(10): await get_tree().process_frame


func _capture(name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://artifacts/" + name)
	if result != OK:
		push_error("Screenshot failed: " + name)
		get_tree().quit(1)
