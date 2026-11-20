extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)

func _verify() -> void:
	GamePreferences.set_animation_acceleration(true)
	var wheel: CanvasLayer = battle.get_node("RandomWheelPresentation")
	await _check_cost_picker_follows_roll(wheel)
	print("TEST_COST_PICKER_ORDER_VISUAL_OK")
	get_tree().quit(0)


func _check_cost_picker_follows_roll(wheel: CanvasLayer) -> void:
	for amount in [0, 1]:
		battle.game.current_player = 2
		battle.game.player_field.slots.fill(null)
		battle.game.player2_field.slots.fill(null)
		var skill := {"skill_name": "随机减费", "trigger": "on_turn_start", "effects": [
			{"effect": "make_zero_cost", "target": "target_single", "value_min": 0, "value_max": 1},
		]}
		var caster := CardData.new("随机减费测试", 0, 4, 1, [skill])
		caster.instance_id = "discount-source"
		battle.game.player_field.slots[0] = caster
		var candidate := CardData.new("待减费", 2, 3, 1)
		battle.game.player_hand = [candidate]
		var rng := RandomNumberGenerator.new()
		for seed in range(30):
			rng.seed = seed
			if rng.randi_range(0, 1) == amount:
				battle.game.game_rng.seed = seed
				break
		var previous_rolls: int = wheel.history.size()
		battle.game.start_new_turn()
		assert(_discount_picker() == null, "no selection may appear during synchronous turn settlement")
		var deadline := Time.get_ticks_msec() + 10000
		while wheel.history.size() == previous_rolls:
			assert(Time.get_ticks_msec() < deadline)
			assert(_discount_picker() == null, "selection appeared over the random wheel")
			await get_tree().process_frame
		assert(int(wheel.history.back().result) == amount)
		await _idle(wheel)
		var picker := _discount_picker()
		if amount == 0:
			assert(picker == null and candidate.cost == 2, "a zero reduction must not prompt")
		else:
			assert(picker != null and picker.cards.has(candidate), "a positive roll must open the picker")
			picker._select(true, picker.cards.find(candidate))
			picker.confirm_button.pressed.emit()
			assert(candidate.cost == 1, "confirming a card must apply the rolled reduction")
			await get_tree().process_frame


func _discount_picker() -> CanvasLayer:
	for popup in get_tree().get_nodes_in_group("battle_modal"):
		if battle.is_ancestor_of(popup) and popup.get("pick_limit") == 1:
			return popup
	return null


func _idle(wheel: CanvasLayer) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while wheel.busy or battle._random_feedback_pending>0 or battle._hp_feedback_running or not battle._random_unbatched_events.is_empty():
		assert(Time.get_ticks_msec()<deadline,"trigger chain remained locked")
		await get_tree().process_frame
	await get_tree().create_timer(.45).timeout
