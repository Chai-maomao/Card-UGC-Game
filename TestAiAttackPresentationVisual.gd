extends "res://TestTabletop3DVisual.gd"

var launches: Array = []
var sampled := false
var expect_death_roll := false
var roll_count := 0
var aim_count := 0

func _verify() -> void:
	battle.get_node("CanvasLayer").child_entered_tree.connect(_observe_strike)
	await _exercise(false)
	await _exercise(true)
	await _exercise_damaged_heal()
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_AI_ATTACK_PRESENTATION_VISUAL_OK")
	get_tree().quit()

func _exercise(death_roll: bool) -> void:
	launches.clear()
	aim_count = 0
	expect_death_roll = death_roll
	roll_count = battle.get_node("RandomWheelPresentation").history.size()
	PlayerData.battle_mode = "practice"
	PlayerData.practice_ai_difficulty = "normal"
	battle.game.current_player = 2
	battle.game.is_player_turn = true
	battle.game.turn_number = 3
	battle.game.first_switch = false
	battle.game.game_rng.seed = 1
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player_hand.clear()
	battle.game.player2_hand.clear()
	battle.game.shared_deck.clear()
	battle.game.player_field.slots[2] = CardData.new("守卫", 0, 3, 0)
	if death_roll:
		var chance := SkillRegistry.make_chance_block(100)
		chance.then_effects = [{"effect":"damage", "target":"all_enemies", "value":1}]
		battle.game.player_field.slots[2].skills = [{"skill_name":"退场反击", "trigger":"on_death", "effects":[chance]}]
	for i in range(2):
		battle.game.player2_field.slots[i] = CardData.new("敌方射手%d" % i, 0, 8, 2)
	battle.game.player2_field.action_points = 10
	battle.game.player2_field.action_budget = 10
	battle.game.player2_field.actions_taken = 0
	battle.game.player2_field.current_mana = 5
	battle._suppress_status_feedback_once = true
	battle.update_entire_screen()
	await get_tree().create_timer(0.5).timeout
	await battle._run_practice_ai_turn()
	assert(launches.size() == 2, "actual AI turn must display both attacks, including the lethal hit: death_roll=%s launches=%s" % [death_roll, launches])
	assert(launches[0] == 3 and launches[1] == 1, "each projectile must start with the target's pre-hit HP still visible")
	assert(battle.game.player_field.slots[2] == null, "lethal target must leave only after its hit presentation")
	assert(battle.game.current_player == 1 and not battle.practice_ai_running, "AI must finish its turn and return control")
	assert(battle._hp_presentation_overrides.is_empty(), "AI presentation overrides must clear")
	assert(sampled, "projectile must remain visible between launch and impact")
	if death_roll:
		assert(battle.game.player2_field.slots[0].hp == 7 and battle.game.player2_field.slots[1].hp == 7, "death passive must still resolve its actual damage")
	assert(aim_count == launches.size(), "each attack must first draw a targeting arrow")

func _observe_strike(node: Node) -> void:
	if node.name == "AiAttackAim":
		aim_count += 1
	if node.name != "AiStrikeTrail": return
	assert(battle._hp_feedback_running, "AI attacks must run in the feedback queue")
	var shown: Dictionary = battle._hp_presentation_overrides.get("1:2", {})
	launches.append(int(shown.get("hp", -1)))
	if expect_death_roll and launches.size() == 2:
		var wheel: CanvasLayer = battle.get_node("RandomWheelPresentation")
		assert(wheel.history.size() == roll_count and not wheel.visible, "the lethal hit must land before the death-passive roulette")
	assert(battle._slot_ui_for_player(1, 2).current_card_ui != null, "target card must remain visible until impact")
	await get_tree().create_timer(0.14).timeout
	assert(is_instance_valid(node) and node.points.size() == 2, "AI projectile must travel before disappearing")
	assert(battle._hp_presentation_overrides["1:2"].hp == launches.back(), "HP must wait for projectile impact")
	assert(battle.tabletop.cards[2].face.shown_hp == launches.back(), "the visible 3D face must still show pre-impact HP")
	if not sampled:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/ai-attack-projectile.png")
		sampled = true


func _exercise_damaged_heal() -> void:
	launches.clear()
	aim_count = 0
	expect_death_roll = false
	battle.game.current_player = 2
	battle.game.is_player_turn = true
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	var chance := SkillRegistry.make_chance_block(100)
	chance.then_effects = [{"effect":"heal", "target":"self", "value":1}]
	var target := CardData.new("受伤回血", 0, 5, 0, [{"skill_name":"受伤回血", "trigger":"on_damaged", "effects":[chance]}])
	battle.game.player_field.slots[2] = target
	battle.game.player2_field.slots[0] = CardData.new("敌方射手", 0, 8, 2)
	battle.game.player2_field.action_points = 10
	battle.game.player2_field.action_budget = 10
	battle.game.player2_field.actions_taken = 0
	battle.update_entire_screen()
	await get_tree().create_timer(0.5).timeout
	var wheel: CanvasLayer = battle.get_node("RandomWheelPresentation")
	battle._run_practice_ai_turn()
	var deadline := Time.get_ticks_msec() + 5000
	while not wheel.visible and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(wheel.visible and aim_count == 1 and launches == [5], "the reaction wheel must follow targeting and projectile launch")
	await RenderingServer.frame_post_draw
	assert(battle.tabletop.cards[2].face.shown_hp == 3, "the rendered card must show the damage during the reaction wheel")
	get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/ai-damaged-heal-wheel.png")
	while battle.practice_ai_running:
		await get_tree().process_frame
	assert(target.hp == 4, "healing applies after the wheel reveals success")
