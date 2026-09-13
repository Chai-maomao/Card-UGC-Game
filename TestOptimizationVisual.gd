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
	PlayerData.practice_challenge_id = "parasite"
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	var challenge_battle := preload("res://Main.tscn").instantiate()
	add_child(challenge_battle)
	await _capture("optimization-challenge-gameplay.png")
	challenge_battle.queue_free()
	await _settle()
	PlayerData.practice_challenge_id = "resource"
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	var completed_battle := preload("res://Main.tscn").instantiate()
	add_child(completed_battle)
	await _settle()
	var challenge_controller: ChallengeController
	for child in completed_battle.get_children():
		if child is ChallengeController:
			challenge_controller = child
	completed_battle.game.player_field.slots[0] = CardData.new("巨人", 5, 8, 5)
	challenge_controller.finished = true
	challenge_controller._show()
	await _capture("optimization-challenge-complete.png")
	completed_battle.queue_free()
	PlayerData.practice_challenge_id = ""
	await _settle()
	PlayerData.card_draft = PlayerData.card_to_draft(card)
	PlayerData.card_draft.skill1.effects[0].repeat_expr = {"kind": "var", "var_id": "hand_count"}
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	var editor_scroll := editor.get_node("Panel/MarginContainer/ScrollContainer") as ScrollContainer
	editor_scroll.scroll_vertical = 10000
	await _capture("optimization-balance.png")
	editor.queue_free()
	await _settle()
	SharePackage.edit_metadata(self, SharePackage.build([]), func(_data): pass)
	await _capture("optimization-share.png")
	for child in get_children():
		if child is Window:
			child.queue_free()
	await _settle()
	var file_dialog := FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "选择卡图" if Locale.language == "zh" else "Select artwork"
	file_dialog.filters = PackedStringArray(["*.png, *.jpg ; 图片"] if Locale.language == "zh" else ["*.png, *.jpg ; Images"])
	add_child(file_dialog)
	UITheme.apply_dialog(file_dialog, true)
	file_dialog.popup_centered(Vector2i(820, 520))
	await _capture("optimization-file-dialog.png")
	file_dialog.queue_free()
	await _settle()
	PlayerData.battle_deck = [CardData.new("我方先锋", 2, 4, 2)]
	PlayerData.opponent_battle_deck = [CardData.new("对方守卫", 3, 6, 1)]
	var agreement := MatchAgreement.new()
	agreement.lobby = self
	agreement.offer = {
		"rules": PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true),
		"p1": MatchAgreement.deck_signature(PlayerData.battle_deck),
		"p2": MatchAgreement.deck_signature(PlayerData.opponent_battle_deck),
	}
	add_child(agreement)
	agreement._show_offer()
	await _capture("optimization-match-agreement.png")
	PlayerData._apply_battle_preparation(backup)
	PlayerData.card_draft = old_draft
	PlayerData.card_playtest_context = old_context
	print("TEST_OPTIMIZATION_VISUAL_OK")
	get_tree().quit(0)


func _on_back_pressed() -> void:
	pass


func _settle() -> void:
	for i in range(10): await get_tree().process_frame


func _capture(name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://artifacts/" + name)
	if result != OK:
		push_error("Screenshot failed: " + name)
		get_tree().quit(1)
