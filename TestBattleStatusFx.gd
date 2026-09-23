extends Node

var failures: Array[String] = []


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.battle_mode = "practice"
	var battle: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var game = battle.get("game")
	var layer := battle.get_node("CanvasLayer") as CanvasLayer
	var hud := battle.get("player_status_hud") as Panel
	var content := hud.get_node("Margin/Content") as HBoxContainer
	var hp_bar := content.get_node("HpBar") as ProgressBar
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	battle.call("_update_battle_status_huds")
	_assert(_count_named(layer, "StatusFx_") == 0, "initial status binding must not fabricate feedback")

	var hp_before: int = game.player_field.player_hp
	var mana_before: int = game.player_field.get_total_mana()
	game.player_field.damage_player(5)
	game.player_field.add_mana(2)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(_has_named(layer, "StatusFx_Damage"), "player damage must create red status feedback")
	_assert(_has_named(layer, "StatusFx_Mana"), "permanent mana gain must create cyan status feedback")
	_assert(hp_bar.value > game.player_field.player_hp and hp_bar.value <= hp_before, "HP bar must animate from its previous value")
	_assert(mana_bar.value < game.player_field.get_total_mana() and mana_bar.value >= mana_before, "mana bar must animate toward its gain")
	await get_tree().create_timer(0.72).timeout
	_assert(is_equal_approx(hp_bar.value, float(game.player_field.player_hp)), "HP animation must settle on authoritative health")
	_assert(is_equal_approx(mana_bar.value, float(game.player_field.get_total_mana())), "mana animation must settle on authoritative mana")

	game.player_field.heal_player(3)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(_has_named(layer, "StatusFx_Heal"), "player healing must create green status feedback")
	await get_tree().create_timer(0.72).timeout

	game.player_field.add_temp_mana(1)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(_has_named(layer, "StatusFx_Mana"), "temporary mana gain must use the same recovery feedback")
	await get_tree().create_timer(0.72).timeout

	game.player_field.spend_mana(1)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(not _has_named(layer, "StatusFx_Mana"), "mana spending must not look like mana recovery")

	game.player_field.damage_player(1)
	battle.set("_suppress_status_feedback_once", true)
	battle.call("_update_battle_status_huds")
	await get_tree().process_frame
	_assert(not _has_named(layer, "StatusFx_Damage"), "recovery-state application must not fabricate damage feedback")
	_assert(is_equal_approx(hp_bar.value, float(game.player_field.player_hp)), "suppressed state refresh must snap to the authoritative HP")

	await _verify_staged_card_hp(battle)
	await _verify_card_feedback_restoration(layer)

	if failures.is_empty():
		print("TEST_BATTLE_STATUS_FX_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_BATTLE_STATUS_FX_FAILED: %s" % failure)
		get_tree().quit(1)


func _verify_staged_card_hp(battle: Node) -> void:
	var target := CardData.new("分段生命目标", 1, 4, 0)
	battle.game.player2_field.slots[0] = target
	battle.update_entire_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var slot_ui = battle._slot_ui_for_player(2, 0)
	var card_ui = slot_ui.current_card_ui
	_assert(card_ui.hp_label.text == Locale.t("card.hp", [4, 4]), "staged HP fixture must begin at 4/4")

	# Gameplay has already reached its final 1/4 state, but presentation must
	# keep the card at 4/4 until the first stage, then show 2/4 for 0.2 seconds.
	target.hp = 1
	battle._queue_presentation_feedback([
		{"kind": "hp", "player": 2, "slot": 0, "delta": -2, "before_hp": 4, "new_hp": 2, "max_hp": 4, "feedback_group": 0},
		{"kind": "stage", "effect_id": SkillEngine.EFFECT_DAMAGE, "feedback_group": 1},
		{"kind": "hp", "player": 2, "slot": 0, "delta": -1, "before_hp": 2, "new_hp": 1, "max_hp": 4, "feedback_group": 1},
	])
	battle.update_entire_screen()
	_assert(card_ui.hp_label.text == Locale.t("card.hp", [4, 4]), "final gameplay HP must not leak ahead of the first presentation stage")
	await get_tree().process_frame
	_assert(card_ui.hp_label.text == Locale.t("card.hp", [2, 4]), "the attack stage must present 2/4 before the skill damage")
	await get_tree().create_timer(0.10).timeout
	_assert(card_ui.hp_label.text == Locale.t("card.hp", [2, 4]), "the skill stage must retain the full 0.2-second gap")
	await get_tree().create_timer(0.14).timeout
	_assert(card_ui.hp_label.text == Locale.t("card.hp", [1, 4]), "the skill stage must advance the card to its final 1/4 HP")


func _verify_card_feedback_restoration(layer: CanvasLayer) -> void:
	var target := Control.new()
	target.size = Vector2(120, 160)
	layer.add_child(target)
	var center := Vector2(320, 240)

	# The second pulse starts while the first card is still blue. It must reuse
	# the original white baseline instead of treating blue as the resting tint.
	BattleFx.skill_cast_pulse(layer, target, center)
	BattleFx.skill_cast_pulse(layer, target, center)
	await get_tree().create_timer(0.36).timeout
	_assert(target.modulate.is_equal_approx(Color.WHITE), "overlapping skill pulses must restore the card's stable color")
	_assert(target.scale.is_equal_approx(Vector2.ONE), "overlapping skill pulses must restore the card's stable scale")

	# Damage/heal flashes and skill pulses share the same transform and tint.
	# Either animation may interrupt the other without preserving an FX frame.
	BattleFx.skill_cast_pulse(layer, target, center)
	await get_tree().create_timer(0.03).timeout
	BattleFx.card_hit_flash(target, -1)
	await get_tree().create_timer(0.55).timeout
	_assert(target.modulate.is_equal_approx(Color.WHITE), "a hit interrupting a skill pulse must restore the stable color")
	_assert(target.scale.is_equal_approx(Vector2.ONE), "a hit interrupting a skill pulse must restore the stable scale")
	target.queue_free()


func _has_named(root: Node, node_name: String) -> bool:
	return root.find_child(node_name, true, false) != null


func _count_named(root: Node, prefix: String) -> int:
	var count := 0
	for node in root.find_children("%s*" % prefix, "", true, false):
		if not node.name.ends_with("Value"):
			count += 1
	return count


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
