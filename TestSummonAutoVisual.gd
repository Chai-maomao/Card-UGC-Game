extends Node

const BattleScene = preload("res://Main.tscn")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer; run scripts/run_tests.ps1 -Suite visual")
		get_tree().quit(1)
		return
	var preparation_backup := PlayerData.battle_preparation_snapshot()
	NetworkManager.close_connection()
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	var battle = BattleScene.instantiate()
	add_child(battle)
	for _frame in range(4):
		await get_tree().process_frame
	battle.game.current_player = 1
	battle.game.turn_number = 2
	battle.game.is_player_turn = true
	battle.game.player_hand.clear()
	battle.game.player_field.slots = [null, null, null, null, null]
	battle.game.player2_field.slots = [null, null, CardData.new("训练目标", 1, 5, 1), null, null]
	var battlecry := CardData.new("战吼测试", 1, 4, 2, [{
		"skill_name": "精准打击", "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 2}],
	}])
	battle.game.player_hand.append(battlecry)
	battle.game.player_field.current_mana = 10
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	battle._on_card_drag_summoned(battlecry, null, 2)
	for _frame in range(4):
		await get_tree().process_frame
	if not battle.summon_targeting or battle.summon_source_slot != 2:
		push_error("SUMMON_AUTO_VISUAL_FAILED: target picker did not open")
		PlayerData._apply_battle_preparation(preparation_backup)
		get_tree().quit(1)
		return
	var output_dir := ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(output_dir.path_join("summon_auto_targeting.png"))
	PlayerData._apply_battle_preparation(preparation_backup)
	if err != OK:
		push_error("SUMMON_AUTO_VISUAL_FAILED: screenshot error %d" % err)
		get_tree().quit(1)
		return
	print("TEST_SUMMON_AUTO_VISUAL_OK")
	get_tree().quit(0)
