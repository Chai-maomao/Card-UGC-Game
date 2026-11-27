extends "res://presentation/BattleTargetHighlights.gd"

# Plays recorded outcomes in order without executing gameplay or drawing RNG.
var _random_board_override: Dictionary = {}
var _random_resource_override: Dictionary = {}
var _plain_feedback_batches: Array = []
var _flushing_plain_feedback := false

func _queue_hp_feedback(events: Array) -> void:
	_queue_presentation_feedback(events)


func _queue_presentation_feedback(events: Array) -> void:
	if events.is_empty() or battle_finished:
		return
	var first_event: Dictionary = events[0]
	if not AppPreferences.get_value("reduced_motion") and not _hp_feedback_running \
			and _random_board_override.is_empty() and first_event.get("projectile", false):
		_set_random_board(first_event.get("board_before", {}))
	var rolls := events.filter(func(event): return str(event.get("kind",""))=="random")
	if not rolls.is_empty():
		var combined: Array = []
		for batch in _plain_feedback_batches: combined.append_array(batch)
		_plain_feedback_batches.clear()
		combined.append_array(events)
		events = combined
	# Collect this synchronous trigger chain before displaying its first effect.
	# Cleanup can still emit an on-death roll after an action's broadcast ends.
	if not _flushing_plain_feedback and not events.any(func(event): return str(event.get("kind",""))=="random"):
		var first := _plain_feedback_batches.is_empty()
		_plain_feedback_batches.append(events.duplicate(true))
		if first: _flush_plain_feedback_batches.call_deferred()
		return
	var stage_span := _feedback_stage_span(events)
	var needs_deferred_hand := false
	var needs_enemy_hand := false
	var needs_random := false
	var needs_projectile := false
	for value in events:
		if bool(value.get("projectile", false)): needs_projectile = true
		if str((value as Dictionary).get("kind",""))=="random":
			needs_random = true
			_random_feedback_pending += 1
			if _random_board_override.is_empty(): _set_random_board(value.get("board_before",value.get("board",{})))
		if str((value as Dictionary).get("kind","")) == "enemy_hand": needs_enemy_hand = true
		if str((value as Dictionary).get("kind", "")) in ["hand_entry","enemy_hand"]:
			needs_deferred_hand = true
	if not _hp_feedback_running and _hp_feedback_batches.is_empty() and not needs_deferred_hand and not needs_random \
			and not needs_projectile and _deployment_feedback_delay() <= 0.0 \
			and (GamePreferences.animation_acceleration_enabled() or stage_span <= 1):
		for value in events:
			_play_presentation_event(value)
		return
	if not _hp_feedback_running and _hp_feedback_batches.is_empty():
		_prime_hp_presentation(events)
	_hp_feedback_batches.append(events.duplicate(true))
	if needs_random or ((stage_span > 1 or needs_enemy_hand) and not _web_playback_allows_input()):
		_ensure_resolution_blocker()
	if not _hp_feedback_running:
		_drain_hp_feedback.call_deferred()

func _flush_plain_feedback_batches() -> void:
	var batches := _plain_feedback_batches.duplicate(true)
	_plain_feedback_batches.clear()
	if not _random_unbatched_events.is_empty():
		var prefix: Array = []
		for batch in batches: prefix.append_array(batch)
		prefix.append_array(_random_unbatched_events)
		_random_unbatched_events.assign(prefix)
		return
	_flushing_plain_feedback = true
	for batch in batches: _queue_presentation_feedback(batch)
	_flushing_plain_feedback = false


func _feedback_stage_span(events: Array) -> int:
	var stage_count := 0
	var previous_group := -1
	for value in events:
		var group := int((value as Dictionary).get("feedback_group", 0))
		if stage_count == 0 or group != previous_group:
			stage_count += 1
			previous_group = group
	return stage_count


func _drain_hp_feedback() -> void:
	if _hp_feedback_running:
		return
	_hp_feedback_running = true
	while not _hp_feedback_batches.is_empty() and is_inside_tree():
		var events: Array = _hp_feedback_batches.pop_front()
		_prime_hp_presentation(events)
		await _wait_for_deployment_feedback()
		var previous_group := -1
		var played_stage := false
		for value in events:
			var event: Dictionary = value
			var group := int(event.get("feedback_group", 0))
			if played_stage and group != previous_group and not GamePreferences.animation_acceleration_enabled():
				var gap_scale := GamePreferences.battle_animation_duration_scale() / GamePreferences.STANDARD_ANIMATION_DURATION_SCALE
				await get_tree().create_timer(EFFECT_PRESENTATION_GAP * gap_scale).timeout
			if str(event.get("kind","")) == "random":
				_set_random_board(event.get("board",{}))
				await _play_random_event(event)
			elif str(event.get("kind","")) == "enemy_hand":
				await _play_enemy_hand_event(event)
			elif str(event.get("kind",""))=="attack_motion":
				if bool(event.get("projectile", false)) and not AppPreferences.get_value("reduced_motion"):
					_set_random_board(event.get("board_before", {}))
					if bool(event.get("ai", false)):
						await _play_ai_attack_aim(event)
				_playing_random_action = true
				# Projectile attacks recoil at the source now; target hit feedback
				# belongs to the HP event after the projectile reaches it.
				var motion_target := -1 if bool(event.get("projectile", false)) else int(event.get("target_slot", -1))
				_play_attack_feedback(int(event.get("player",1)),int(event.get("source_slot",0)),motion_target)
				_playing_random_action = false
				if bool(event.get("projectile", false)):
					await _play_directed_projectile(event)
				else:
					await get_tree().create_timer(.12*GamePreferences.battle_animation_duration_scale()).timeout
			elif str(event.get("kind", "")) == "directed_motion":
				if not AppPreferences.get_value("reduced_motion"):
					_set_random_board(event.get("board_before", {}))
				await _play_directed_projectile(event)
			else:
				_play_presentation_event(event)
			previous_group = group
			played_stage = true
		_clear_hp_presentation(events)
		for event in events:
			if str(event.get("kind",""))=="random": _random_feedback_pending = maxi(0,_random_feedback_pending-1)
		if _random_feedback_pending==0 and not _random_board_override.is_empty():
			_random_board_override.clear()
			_random_resource_override.clear()
			update_entire_screen()
	_hp_feedback_running = false
	if not _resolution_running and _resolution_pending_steps <= 0 and _resolution_blocker != null and is_instance_valid(_resolution_blocker):
		_resolution_blocker.visible = false
	if is_inside_tree():
		update_entire_screen()


func _play_directed_projectile(event: Dictionary) -> void:
	var player := int(event.get("player", 2))
	var source := _slot_ui_for_player(player, int(event.get("source_slot", -1)))
	var target := _slot_ui_for_player(3 - player, int(event.get("target_slot", -1)))
	if target == null: return
	var start := get_viewport_rect().size * Vector2(0.5, 0.88 if player == _view_player() else 0.12)
	if source != null:
		start = source.get_global_rect().get_center()
	elif player == _view_player() and event.get("origin", []) is Array and event.get("origin", []).size() == 2:
		start = get_viewport_rect().size * Vector2(float(event.origin[0]), float(event.origin[1]))
	var finish := target.get_global_rect().get_center()
	var tint := UITheme.COLOR_GOLD if event.kind == "attack_motion" else Color("8fcbc8")
	await BattleFx.directed_trail($CanvasLayer, start, finish, tint, _ui_scale(), bool(event.get("ai", false)))


func _play_ai_attack_aim(event: Dictionary) -> void:
	var player := int(event.get("player", 2))
	var source := _slot_ui_for_player(player, int(event.get("source_slot", -1)))
	var target := _slot_ui_for_player(3 - player, int(event.get("target_slot", -1)))
	if source == null or target == null: return
	var arrow := preload("res://ArrowLine.gd").new()
	arrow.name = "AiAttackAim"
	arrow.z_index = 36
	arrow.default_color = Color("ec8679")
	arrow.width = 4.0 * _ui_scale()
	arrow.arrow_length = 18.0 * _ui_scale()
	arrow.arrow_width = 16.0 * _ui_scale()
	var start := source.get_global_rect().get_center()
	var finish := target.get_global_rect().get_center()
	arrow.points = PackedVector2Array([start, start])
	$CanvasLayer.add_child(arrow)
	var pace := GamePreferences.battle_animation_duration_scale()
	var tween := arrow.create_tween()
	if AppPreferences.get_value("reduced_motion"):
		arrow.points = PackedVector2Array([start, finish])
	else:
		tween.tween_method(func(amount: float):
			arrow.points = PackedVector2Array([start, start.lerp(finish, amount)])
		, 0.0, 1.0, 0.18 * pace).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.15 * pace)
	await tween.finished
	arrow.queue_free()


func _play_presentation_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", "hp" if event.has("delta") else "stage"))
	match kind:
		"ai_death":
			_playing_random_action = true
			_play_death_feedback(_slot_ui_for_player(int(event.get("player", 0)), int(event.get("slot", -1))))
			_playing_random_action = false
		"random_board":
			_set_random_board(event.get("board",{}))
		"hp":
			if int(event.get("delta",0)) < 0 and int(event.get("feedback_group",0)) > 0: AppAudio.play("skill")
			_update_hp_presentation(event)
			_show_floating_for(
				int(event.get("player", 0)),
				int(event.get("slot", -1)),
				int(event.get("delta", 0)),
				bool(event.get("zero_damage", false))
			)
		"hand_entry":
			_play_staged_hand_entry(event)
		"effect":
			AppAudio.play("dark_magic" if str(event.get("effect_id","")) == SkillEngine.EFFECT_ADD_BUFF else "skill")
			for value in event.get("targets", []):
				var loc: Dictionary = value
				var slot_ui := _slot_ui_for_player(int(loc.get("player", 0)), int(loc.get("slot", -1)))
				var target := _card_feedback_target(slot_ui)
				if target != null and is_instance_valid(target):
					BattleFx.skill_cast_pulse($CanvasLayer, target, slot_ui.global_position + slot_ui.size / 2, _ui_scale())

func _play_enemy_hand_event(_event: Dictionary) -> void:
	pass


func _set_random_board(snapshot: Dictionary) -> void:
	if snapshot.is_empty(): return
	_random_board_override.clear()
	_random_resource_override = snapshot.get("resources",{}).duplicate(true)
	for player in snapshot:
		if str(player)=="resources": continue
		var cards: Array = []
		for data in snapshot[player]: cards.append(PlayerData.deserialize_card(data) if not data.is_empty() else null)
		_random_board_override[str(player)] = cards
	update_entire_screen()


func _random_visible_slots(player: int,fallback: Array) -> Array:
	return _random_board_override.get(str(player),fallback)


func _random_wheel_origin(event: Dictionary) -> Vector2:
	var slot_ui := _slot_ui_for_player(int(event.get("player",1)),int(event.get("source_slot",-1)))
	return slot_ui.get_global_rect().get_center() if slot_ui != null else get_viewport_rect().size*Vector2(.5,.72)


func _play_random_event(event: Dictionary) -> void:
	var presenter := get_node_or_null("RandomWheelPresentation")
	if presenter != null: await presenter.play(event)


func _wait_for_random_feedback() -> void:
	while is_inside_tree() and (_random_feedback_pending>0 or not _random_unbatched_events.is_empty()):
		await get_tree().process_frame


func _defer_random_feedback(feedback: Callable) -> bool:
	if _random_feedback_pending<=0 and _random_unbatched_events.is_empty(): return false
	_run_after_random(feedback)
	return true


func _run_after_random(feedback: Callable) -> void:
	await _wait_for_random_feedback()
	if is_inside_tree() and not battle_finished and feedback.is_valid(): feedback.call()


func _hp_presentation_key(player: int, slot: int) -> String:
	return "%d:%d" % [player, slot]


func _prime_hp_presentation(events: Array) -> void:
	for value in events:
		var event: Dictionary = value
		if str(event.get("kind", "")) != "hp" or not event.has("before_hp"):
			continue
		var player := int(event.get("player", 0))
		var slot := int(event.get("slot", -1))
		var key := _hp_presentation_key(player, slot)
		if _hp_presentation_overrides.has(key):
			continue
		_hp_presentation_overrides[key] = {
			"player": player,
			"slot": slot,
			"hp": int(event.get("before_hp", 0)),
			"max_hp": int(event.get("max_hp", -1)),
		}
	_apply_hp_presentation_overrides()


func _update_hp_presentation(event: Dictionary) -> void:
	var player := int(event.get("player", 0))
	var slot := int(event.get("slot", -1))
	var cards: Array = _random_board_override.get(str(player),[])
	if slot in range(cards.size()) and cards[slot]!=null and event.has("new_hp"):
		cards[slot].hp = int(event.new_hp)
		update_entire_screen()
	var key := _hp_presentation_key(player, slot)
	if not _hp_presentation_overrides.has(key) or not event.has("new_hp"):
		return
	_hp_presentation_overrides[key] = {
		"player": player,
		"slot": slot,
		"hp": int(event.get("new_hp", 0)),
		"max_hp": int(event.get("max_hp", -1)),
	}
	_apply_hp_presentation_override(_hp_presentation_overrides[key])


func _apply_hp_presentation_overrides() -> void:
	for value in _hp_presentation_overrides.values():
		_apply_hp_presentation_override(value)


func _apply_hp_presentation_override(value: Dictionary) -> void:
	var slot_ui := _slot_ui_for_player(int(value.get("player", 0)), int(value.get("slot", -1)))
	if slot_ui == null:
		return
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui != null and is_instance_valid(card_ui) and card_ui.has_method("set_presentation_hp"):
		card_ui.set_presentation_hp(int(value.get("hp", 0)), int(value.get("max_hp", -1)))


func _clear_hp_presentation(events: Array) -> void:
	var cleared := {}
	for value in events:
		var event: Dictionary = value
		if str(event.get("kind", "")) != "hp":
			continue
		var player := int(event.get("player", 0))
		var slot := int(event.get("slot", -1))
		var key := _hp_presentation_key(player, slot)
		if cleared.has(key):
			continue
		cleared[key] = true
		_hp_presentation_overrides.erase(key)
		var slot_ui := _slot_ui_for_player(player, slot)
		if slot_ui == null:
			continue
		var card_ui = slot_ui.get("current_card_ui")
		if card_ui != null and is_instance_valid(card_ui) and card_ui.has_method("clear_presentation_hp"):
			card_ui.clear_presentation_hp()


