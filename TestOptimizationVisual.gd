extends Node

const Simulation = preload("res://CardBalanceSimulation.gd")


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
	var old_decks := PlayerData.deck_library
	var old_cards := PlayerData.card_library
	var old_editing_deck_id := PlayerData.editing_deck_id
	var old_editing_instance_id := PlayerData.editing_instance_id
	var old_editing_index := PlayerData.editing_index
	var old_revisions := PlayerData.card_revisions
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
	var simulation_popup: CanvasLayer = editor._open_balance_simulation(card, false)
	for index in range(Simulation.POOL_IDS.size()):
		editor._add_balance_simulation_result({
			"pool": Simulation.POOL_IDS[index],
			"games": 16,
			"average_rounds": 9.5 + index,
			"draw_rate": 0.125 if index != 1 else 0.3125,
			"first_player_win_rate": 0.54,
			"mana_utilization": 0.82,
			"stability_failures": 0,
			"candidate": {"plays_per_game": 0.75, "actions_per_game": 0.44, "damage_per_game": 1.8, "healing_per_game": 0.3},
			"warnings": [] if index != 1 else ["high_draw_rate"],
		})
	var simulation_panel: Panel = simulation_popup.get_node("CardSimulationPanel")
	(simulation_panel.find_child("SimulationStatus", true, false) as Label).text = Locale.t("simulation.complete", [48])
	(simulation_panel.find_child("SimulationProgress", true, false) as ProgressBar).value = 48
	(simulation_panel.find_child("SimulationCancelButton", true, false) as Button).text = Locale.t("common.close")
	await _capture("optimization-simulation.png")
	simulation_popup.queue_free()
	var current_version := CardData.new("连锁守卫", 4, 7, 3, card.skills.duplicate(true))
	current_version.card_id = "visual_revision_card"
	current_version.instance_id = "visual_revision_instance"
	var old_version := CardData.new("连锁守卫", 2, 5, 2, [])
	old_version.card_id = current_version.card_id
	old_version.instance_id = current_version.instance_id
	PlayerData.deck_library = [{"id": "visual_revision_deck", "name": "演示牌组", "cards": [current_version]}]
	PlayerData.rebuild_card_library_cache()
	PlayerData.editing_deck_id = "visual_revision_deck"
	PlayerData.editing_instance_id = current_version.instance_id
	PlayerData.editing_index = 0
	PlayerData.card_draft = PlayerData.card_to_draft(current_version)
	PlayerData.card_revisions = [
		{"card_id": current_version.card_id, "revision": 2, "saved_at": 1789981200, "card": PlayerData._card_revision_snapshot(current_version)},
		{"card_id": current_version.card_id, "revision": 1, "saved_at": 1789894800, "card": PlayerData._card_revision_snapshot(old_version)},
	]
	editor._restore_form_from_draft()
	editor._apply_texts()
	editor._update_skill_labels()
	editor._refresh_version_history_button()
	var revision_popup: CanvasLayer = editor._open_version_history()
	await _capture("optimization-version-history.png")
	revision_popup.queue_free()
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
	PlayerData.deck_library = old_decks
	PlayerData.card_library = old_cards
	PlayerData.editing_deck_id = old_editing_deck_id
	PlayerData.editing_instance_id = old_editing_instance_id
	PlayerData.editing_index = old_editing_index
	PlayerData.card_revisions = old_revisions
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
