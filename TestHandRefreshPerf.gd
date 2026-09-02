extends Node

const SkillEngine = preload("res://SkillEngine.gd")

# Headless regression tests for the per-action UI responsiveness work:
#   1. Hand nodes are reused across refreshes (no full teardown/rebuild).
#   2. Entry feedback plays for genuinely new cards only.
#   3. Full-screen refreshes coalesce to one deferred run per frame.
#   4. Status badges are rebuilt only when their visible content changes.
#   5. apply_ui_scale is a no-op for unchanged scale + card type.
#   6. Hand skill activation resolves the live hand index of reused nodes.


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.battle_mode = "practice"
	var battle: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	add_child(battle)
	for _i in range(3):
		await get_tree().process_frame

	var failures := 0
	failures += await _test_hand_node_reuse(battle)
	failures += await _test_new_card_enter_feedback(battle)
	failures += await _test_screen_refresh_coalescing(battle)
	failures += await _test_status_badge_cache(battle)
	failures += await _test_apply_ui_scale_idempotent(battle)
	failures += await _test_dynamic_hand_index(battle)
	_bench_hand_refresh(battle)

	if failures > 0:
		push_error("TEST_HAND_REFRESH_PERF_FAILED: %d group(s)" % failures)
		get_tree().quit(1)
		return
	print("TEST_HAND_REFRESH_PERF_OK")
	get_tree().quit(0)


# --- 1. Summoning a card must not rebuild the remaining hand nodes. ---------
func _test_hand_node_reuse(battle: Node) -> int:
	var game = battle.game
	var field = game.player_field
	field.current_mana = 99
	field.max_mana = 99
	var hand: Array = game.player_hand
	var minion = null
	for card in hand:
		if card != null and not card.is_spell() and not card.is_parasite():
			minion = card
			break
	if minion == null:
		push_warning("PERF_TEST: no minion in opening hand; skipping reuse group")
		return 0
	var slot_idx := -1
	for i in range(field.slots.size()):
		if field.slots[i] == null:
			slot_idx = i
			break
	if slot_idx == -1:
		push_warning("PERF_TEST: no empty slot; skipping reuse group")
		return 0
	var size_before := hand.size()
	var ids_before := {}
	for child in battle.hand_container.get_children():
		ids_before[child.get("current_card_data")] = child.get_instance_id()

	if not game.summon_card(minion, slot_idx):
		_assert(false, "summon should succeed with ample mana and an empty slot")
		return 1
	battle._refresh_hand_ui()

	var after: Array = battle.hand_container.get_children()
	if after.size() != size_before - 1:
		_assert(false, "hand UI should shrink by exactly one after a summon")
		return 1
	for child in after:
		var data = child.get("current_card_data")
		if not ids_before.has(data) or ids_before[data] != child.get_instance_id():
			_assert(false, "remaining hand nodes must be reused, not rebuilt")
			return 1
	return 0


# --- 2. Entry fade plays for new cards only, reused cards stay opaque. ------
func _test_new_card_enter_feedback(battle: Node) -> int:
	var game = battle.game
	game.current_player = 1
	game.is_player_turn = true
	var hand: Array = game.player_hand
	if hand.is_empty():
		push_warning("PERF_TEST: empty hand; skipping enter-feedback group")
		return 0
	var extra: CardData = hand[0].duplicate_card()
	var reused_ids: Array = []
	for child in battle.hand_container.get_children():
		reused_ids.append(child.get_instance_id())

	hand.append(extra)
	battle._refresh_hand_ui()

	var after: Array = battle.hand_container.get_children()
	if after.size() != reused_ids.size() + 1:
		_assert(false, "appended card should add exactly one hand node")
		return 1
	var new_count := 0
	for child in after:
		if reused_ids.has(child.get_instance_id()):
			if not is_equal_approx(child.modulate.a, 1.0):
				_assert(false, "reused cards must not replay the entry fade")
				return 1
		else:
			new_count += 1
			if not is_equal_approx(child.modulate.a, 0.0):
				_assert(false, "new card should begin the entry fade at alpha 0")
				return 1
	if new_count != 1:
		_assert(false, "exactly one hand node should be new after a draw")
		return 1
	return 0


# --- 3. Duplicate update_entire_screen calls coalesce into one run. ---------
func _test_screen_refresh_coalescing(battle: Node) -> int:
	var turn_label: Label = battle.turn_label
	if turn_label == null:
		push_warning("PERF_TEST: no turn label; skipping coalescing group")
		return 0
	var marker := "__PERF_TEST_MARK__"
	turn_label.text = marker
	battle.update_entire_screen()
	battle.update_entire_screen()
	if turn_label.text != marker:
		_assert(false, "refresh must be deferred so duplicate calls coalesce in one frame")
		return 1
	if not battle._screen_refresh_queued:
		_assert(false, "queued flag should be raised while a refresh is pending")
		return 1
	await get_tree().process_frame
	await get_tree().process_frame
	if battle._screen_refresh_queued:
		_assert(false, "queued flag must reset after the deferred flush")
		return 1
	if turn_label.text == marker:
		_assert(false, "deferred refresh should have restored the real turn label")
		return 1
	return 0


# --- 4. Status badges rebuild only when visible content changes. ------------
func _badge_ids(card_ui) -> Array:
	var ids: Array = []
	if card_ui.status_icons == null:
		return ids
	for badge in card_ui.status_icons.get_children():
		ids.append(badge.get_instance_id())
	return ids


func _test_status_badge_cache(battle: Node) -> int:
	var children: Array = battle.hand_container.get_children()
	if children.is_empty():
		push_warning("PERF_TEST: empty hand; skipping badge group")
		return 0
	var card_ui = children[0]
	var card_data: CardData = card_ui.get("current_card_data")
	card_data.status_effects.append({"buff_id": "__perf_test_buff__", "value": 2, "duration": 2})
	card_ui.set_card(card_data)
	var badges_first := _badge_ids(card_ui)
	if badges_first.is_empty():
		push_warning("PERF_TEST: badge not created; skipping badge group")
		card_data.status_effects.clear()
		return 0

	card_ui.set_card(card_data)
	if _badge_ids(card_ui) != badges_first:
		_assert(false, "unchanged statuses must keep the existing badge nodes")
		card_data.status_effects.clear()
		return 1

	card_data.status_effects[0]["value"] = 3
	card_ui.set_card(card_data)
	if _badge_ids(card_ui) == badges_first:
		_assert(false, "changed status values must rebuild badges")
		card_data.status_effects.clear()
		return 1
	card_data.status_effects.clear()
	return 0


# --- 5. apply_ui_scale is a no-op for unchanged scale and card type. --------
func _test_apply_ui_scale_idempotent(battle: Node) -> int:
	var children: Array = battle.hand_container.get_children()
	if children.is_empty():
		push_warning("PERF_TEST: empty hand; skipping scale group")
		return 0
	var card_ui = children[0]
	var scale_before: float = card_ui.ui_scale
	card_ui.name_label.add_theme_font_size_override("font_size", 99)
	card_ui.apply_ui_scale(scale_before)
	if card_ui.name_label.get_theme_font_size("font_size") != 99:
		_assert(false, "apply_ui_scale must be a no-op for unchanged scale and card type")
		return 1
	card_ui.apply_ui_scale(scale_before + 0.5)
	if card_ui.name_label.get_theme_font_size("font_size") == 99:
		_assert(false, "apply_ui_scale must re-run when the scale changes")
		return 1
	card_ui.apply_ui_scale(scale_before)
	return 0


# --- 6. Skill activation resolves the live hand index of reused nodes. ------
func _test_dynamic_hand_index(battle: Node) -> int:
	var children: Array = battle.hand_container.get_children()
	if children.size() < 2:
		push_warning("PERF_TEST: hand too small; skipping index group")
		return 0
	if battle._hand_index_of(children[1]) != 1:
		_assert(false, "_hand_index_of should resolve the live index of a reused node")
		return 1
	if battle._hand_index_of(null) != -1:
		_assert(false, "_hand_index_of should reject invalid nodes")
		return 1

	# End-to-end: activating a spell through a reused node must target the
	# node's current position in the hand.
	var game = battle.game
	game.current_player = 1
	game.is_player_turn = true
	var spell_ui = null
	var spell_idx := -1
	for i in range(children.size()):
		var data = children[i].get("current_card_data")
		if data != null and data.is_spell():
			spell_ui = children[i]
			spell_idx = i
			break
	if spell_ui == null:
		# Deterministic fallback: append a crafted target-needed spell.
		var spell: CardData = CardData.new("PERF_TEST_SPELL", 1, 1, 1, [{
			"skill_name": "perf_test",
			"target": SkillEngine.TARGET_SINGLE,
			"effect": SkillEngine.EFFECT_DAMAGE,
			"value": 1,
			"effects": [{"target": SkillEngine.TARGET_SINGLE, "effect": SkillEngine.EFFECT_DAMAGE, "value": 1}],
		}])
		spell.card_type = "spell"
		game.player_hand.append(spell)
		battle._refresh_hand_ui()
		children = battle.hand_container.get_children()
		spell_idx = children.size() - 1
		spell_ui = children[spell_idx]
	var saved_turn: int = game.turn_number
	var saved_mana: int = game.player_field.current_mana
	game.turn_number = 2
	game.player_field.current_mana = 99
	battle.cast_targeting = false
	battle._on_hand_card_skill_activated(spell_ui)
	var ok: bool = not battle.cast_targeting or battle.cast_hand_index == spell_idx
	battle.cast_targeting = false
	game.turn_number = saved_turn
	game.player_field.current_mana = saved_mana
	if not ok:
		_assert(false, "spell activation via a reused node should use the live hand index")
		return 1
	return 0


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_HAND_REFRESH_PERF_FAILED: %s" % message)


# Reference numbers only (no threshold assertion): how long a no-op refresh
# takes with the incremental path, in microseconds per call.
func _bench_hand_refresh(battle: Node) -> void:
	var start := Time.get_ticks_usec()
	for _i in range(200):
		battle._refresh_hand_ui()
	var elapsed := Time.get_ticks_usec() - start
	print("PERF_BENCH no-op hand refresh: %.1f us/call" % (float(elapsed) / 200.0))
