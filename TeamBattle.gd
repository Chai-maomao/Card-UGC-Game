extends "res://Main.gd"

const COLLECTION = preload("res://CardCollectionDialog.gd")
const RED_FLAG := [Vector2(-5, -7), Vector2(-5, 7), Vector2(-2, 7), Vector2(-2, 0),
	Vector2(6, 0), Vector2(3, -3), Vector2(6, -7)]
const BLUE_SHIELD := [Vector2(-6, -6), Vector2(6, -6), Vector2(6, 1),
	Vector2(4, 4), Vector2(0, 7), Vector2(-4, 4), Vector2(-6, 1)]

@onready var room: Node = NetworkManager.team_room
var _seat_bar: VBoxContainer
var _seat_buttons: Dictionary = {}
var _viewed_seat := 0
var _enemy_seat := 0
var _local_team := 0
var _revision := -1
var _projected_view: Dictionary = {}
var _picker: CanvasLayer
var _leaving := false
var _refresh_pending := false
var _aim_sent := false
var _aim_pointer := Vector2.INF


func _is_party_battle() -> bool:
	return true


func _ready() -> void:
	if not room.started or room.view.is_empty():
		set_process(false)
		_return_to_lobby()
		return
	super._ready()
	_seat_bar = VBoxContainer.new()
	_seat_bar.name = "PartySeats"
	$CanvasLayer.add_child(_seat_bar)
	var order: Array = room.view.players.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.team != b.team: return a.team == _player(room.local_seat).team
		return a.seat < b.seat)
	for player: Dictionary in order:
		var seat := int(player.seat)
		if seat == room.local_seat or not room.matchmaking_mode.is_empty():
			continue
		var button := Button.new()
		button.name = "PartySeat%d" % seat
		button.toggle_mode = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var team := int(player.team)
		_style_seat_button(button, team)
		button.draw.connect(_draw_seat_emblem.bind(button, team))
		_seat_bar.add_child(button)
		_seat_buttons[seat] = button
		button.pressed.connect(_view_seat.bind(seat))
	room.view_changed.connect(_queue_party_refresh)
	room.returned_to_lobby.connect(_return_to_lobby)
	room.action_rejected.connect(func(): _show_toast("team.invalid_action"))
	get_window().mouse_exited.connect(func(): _aim_pointer = Vector2.INF)
	middle_info_bar.item_rect_changed.connect(_position_seat_bar)
	end_turn_button.item_rect_changed.connect(_position_seat_bar)
	_apply_responsive_layout()
	_refresh_seat_bar()
	_sync_picker()
	if _opening_coin_active:
		_play_opening_coin.call_deferred(int(room.view.active), room.local_seat)


func _on_opening_coin_finished() -> void:
	room.confirm_team_reveal()
	super._on_opening_coin_finished()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_aim_pointer = get_canvas_transform().affine_inverse() * event.position


func _targeting_pointer_position() -> Vector2:
	return _aim_pointer if _aim_pointer.is_finite() else super._targeting_pointer_position()


func _initialize_battle_game() -> void:
	game.quiet = true
	game.battle_config = room.battle_rules.duplicate(true)
	game.player_field = BattleField.new("")
	game.player2_field = BattleField.new("")
	_local_team = int(_player(room.local_seat).team)
	_rebuild_enemy()
	_viewed_seat = int(room.view.active) if int(room.view.active) != room.local_seat else _enemy_seat
	_project_snapshot()
	_opening_coin_active = not room.matchmaking_mode.is_empty() and not room.reconnecting \
		and _revision == 0 and game.turn_number == 1 and int(room.view.winner) == 0 \
		and DisplayServer.get_name() != "headless"


func _view_player() -> int:
	return 1


func _owns_current_turn() -> bool:
	return not _leaving and not battle_finished and not _result_waiting_for_feedback and room.is_my_turn()


func _opponent_hand_count() -> int:
	return int(_player(_viewed_seat).get("hand_count", 0))


func _waiting_for_action_state() -> bool:
	return room.waiting_for_reply and not room.reconnecting


func _process_action_timer() -> void:
	if _action_timer == null:
		return
	if battle_finished or room.interrupted or int(room.view.get("winner", 0)) != 0:
		_action_timer.hide()
		return
	_action_timer.present(room.action_clock.remaining_ms, room.action_clock.limit_ms,
		match_paused or _opening_coin_active or room.team_reveal_pending())


func _player(seat: int) -> Dictionary:
	if seat <= 0 or room.view.is_empty():
		return {}
	return room.view.players[seat - 1]


func _seat_name(seat: int) -> String:
	var player := _player(seat)
	if player.is_empty():
		return ""
	if not room.matchmaking_mode.is_empty():
		return Locale.t("battle.you" if seat == room.local_seat else "battle.enemy")
	var side: int = player.team
	if side == 1 and room.seat_count == 3:
		return Locale.t("team.side_1")
	var team_position := 0
	for member: Dictionary in room.view.players:
		if int(member.team) == side:
			team_position += 1
		if int(member.seat) == seat:
			break
	return Locale.t("team.seat_short_%d" % side, [team_position])


func _is_enemy(seat: int) -> bool:
	var player := _player(seat)
	return not player.is_empty() and int(player.team) != _local_team


func _rebuild_enemy() -> void:
	if _is_enemy(_enemy_seat) and int(_player(_enemy_seat).hp) > 0:
		return
	_enemy_seat = 0
	for player: Dictionary in room.view.players:
		if _is_enemy(int(player.seat)) and int(player.hp) > 0:
			_enemy_seat = int(player.seat)
			return


func _view_seat(seat: int) -> void:
	if _viewed_seat == seat:
		_refresh_seat_bar()
		return
	if is_instance_valid(card_inspector):
		card_inspector.hide()
	if int(_player(seat).hp) <= 0:
		cancel_attack()
	_clear_targeting_aim()
	last_hovered_target = -1
	_viewed_seat = seat
	if _is_enemy(seat) and int(_player(seat).hp) > 0:
		_enemy_seat = seat
	_project_field(game.player2_field, _player(seat))
	_suppress_status_feedback_once = true
	_refresh_seat_bar()
	update_entire_screen()


func _apply_responsive_layout() -> void:
	super._apply_responsive_layout()
	if not is_instance_valid(_seat_bar):
		return
	var ui_scale := _ui_scale()
	var compact := _seat_buttons.size() >= 4
	_seat_bar.add_theme_constant_override("separation", maxi(2, roundi((3.0 if compact else 5.0) * ui_scale)))
	_position_seat_bar()
	for button: Button in _seat_buttons.values():
		button.custom_minimum_size = Vector2(148, 36 if compact else 46) * ui_scale
		button.add_theme_font_size_override("font_size", maxi(11, int((12.0 if compact else 14.0) * ui_scale)))
	for seat: int in _seat_buttons:
		_style_seat_button(_seat_buttons[seat], int(_player(seat).team))


func _position_seat_bar() -> void:
	var ui_scale := _ui_scale()
	var right_lane_x := get_viewport_rect().size.x - 160.0 * ui_scale
	var top := 158.0 * ui_scale
	var controls := middle_info_bar.get_global_rect().merge(end_turn_button.get_global_rect())
	if controls.end.x > right_lane_x:
		top = maxf(top, controls.end.y + 8.0 * ui_scale)
	_seat_bar.position = Vector2(right_lane_x, top)


func _on_appearance_preference_changed(key: String) -> void:
	super._on_appearance_preference_changed(key)
	if key in ["appearance", "high_contrast"]:
		for seat: int in _seat_buttons:
			_style_seat_button(_seat_buttons[seat], int(_player(seat).team))


func _style_seat_button(button: Button, team: int) -> void:
	UITheme.apply_button(button, "secondary", false)
	var accent := UITheme.party_team_accent(team)
	var active: bool = button.get_meta("party_turn_active", false)
	var ui_scale := _ui_scale()
	var vertical_padding := (2.0 if _seat_buttons.size() >= 4 else 4.0) * ui_scale
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		var selected: bool = state in ["pressed", "hover_pressed"]
		style.border_color = accent if selected or state == "hover" else accent.lerp(UITheme.Tokens.BORDER, 0.35)
		style.set_border_width_all(2 if selected else 1)
		style.content_margin_left = 24.0 * ui_scale
		style.content_margin_top = vertical_padding
		style.content_margin_bottom = vertical_padding
		if active:
			style.bg_color = style.bg_color.lerp(accent, 0.28)
			style.border_color = accent
	button.queue_redraw()


func _draw_seat_emblem(button: Button, team: int) -> void:
	var origin := Vector2(13 * _ui_scale(), button.size.y * 0.5)
	var points := PackedVector2Array()
	for point: Vector2 in (RED_FLAG if team == 1 else BLUE_SHIELD):
		points.append(origin + point * _ui_scale())
	button.draw_colored_polygon(points, UITheme.party_team_accent(team))


func _refresh_seat_bar() -> void:
	for seat: int in _seat_buttons:
		var button: Button = _seat_buttons[seat]
		var player := _player(seat)
		var hp := "%d/%d" % [player.hp, player.max_hp] if int(player.hp) > 0 else Locale.t("team.eliminated")
		var formation := ""
		for card: Dictionary in player.slots:
			formation += "· " if card.is_empty() else "◆ "
		var active := int(room.view.active) == seat and int(room.view.winner) == 0
		if active != button.get_meta("party_turn_active", false):
			button.set_meta("party_turn_active", active)
			_style_seat_button(button, int(player.team))
		button.text = "%s  %s\n%s" % [_seat_name(seat), hp, formation.strip_edges()]
		button.set_pressed_no_signal(seat == _viewed_seat)
		button.tooltip_text = Locale.t("team.resources", [player.hp, player.max_hp, player.mana, player.actions])
		button.modulate.a = 0.65 if int(player.hp) <= 0 else 1.0


func _project_snapshot() -> void:
	var view: Dictionary = room.view
	game.current_player = 1 if int(view.active) == room.local_seat else 2
	game.turn_number = int(view.round)
	game.state_revision = int(view.revision)
	game.is_player_turn = true
	_project_field(game.player_field, _player(room.local_seat))
	_project_field(game.player2_field, _player(_viewed_seat))
	game.player_hand = _decode_cards(view.hand, game.player_hand)
	game.shared_discard = _decode_cards(view.get("discard", []), [])
	game.shared_deck = _decode_cards(view.get("visible_deck", []), [])
	_projected_view = view
	_revision = int(view.revision)


func _project_field(field: BattleField, player: Dictionary) -> void:
	if player.is_empty():
		return
	field.player_hp = int(player.hp)
	field.max_player_hp = int(player.max_hp)
	field.current_mana = int(player.get("current_mana", player.mana))
	field.max_mana = int(player.get("max_mana", 10))
	field.temp_mana = int(player.get("temp_mana", 0))
	field.action_points = int(player.actions)
	field.action_budget = int(player.get("action_budget", player.actions))
	field.actions_taken = int(player.get("actions_taken", 0))
	field.slots = _decode_cards(player.slots, field.slots)


func _decode_cards(entries: Array, previous: Array) -> Array:
	var cards: Array = []
	var cached := {}
	for card: CardData in previous:
		if card != null:
			cached[card.instance_id] = card
	for entry: Dictionary in entries:
		if entry.is_empty():
			cards.append(null)
			continue
		var card := PlayerData.deserialize_card(entry)
		if not room.local_art.is_empty():
			BattleArtResolver.restore_card(card, room.local_art)
		var prior: CardData = cached.get(card.instance_id)
		cards.append(prior if prior != null and PlayerData.serialize_card(prior) == PlayerData.serialize_card(card) else card)
	return cards


func _visible_pile_counts() -> Vector2i:
	return Vector2i(int(room.view.get("deck_count", 0)), int(room.view.get("discard_count", 0)))


func _turn_owner_text() -> String:
	if room.view.is_empty():
		return ""
	if room.interrupted:
		return Locale.t("team.disconnected")
	if match_paused:
		return Locale.t("team.reconnecting" if room.reconnecting else "team.waiting_return")
	if room.team_reveal_pending():
		return Locale.t("team.waiting_confirmation")
	return Locale.t("battle.your_turn") if int(room.view.active) == room.local_seat \
		else Locale.t("team.seat_turn", [_seat_name(int(room.view.active))])


func _update_status_hud(hud: Panel, field: BattleField, hand_size: int, enemy: bool, active: bool, player_number: int, preview_mana: int = -1) -> void:
	var seat: int = _viewed_seat if enemy else room.local_seat
	super._update_status_hud(hud, field, hand_size, enemy, active and seat == int(room.view.get("active", 0)), player_number, preview_mana)
	hud.get_node("Margin/Content/SideLabel").text = _seat_name(seat)


func _end_turn_preview_text() -> String:
	if _viewed_seat != _enemy_seat:
		return Locale.t("team.end_target", [_seat_name(_enemy_seat)])
	return super._end_turn_preview_text()


func _refresh_end_turn_damage_preview() -> void:
	if _viewed_seat != _enemy_seat:
		var bar := enemy_status_hud.get_node("Margin/Content/HpBar") as ProgressBar
		preload("res://presentation/ResourceCostPreview.gd").update(bar, 0, _their_field().player_hp, false)
		return
	super._refresh_end_turn_damage_preview()


func _sync_targeting_state() -> void:
	var source := current_attacker_idx
	if summon_targeting:
		source = summon_source_slot
	elif activate_targeting:
		source = activate_source_slot
	var own_row := last_hovered_target >= _their_slots_ui().size()
	var target_row := _view_player() if own_row else _opponent_player()
	var slot := last_hovered_target - (_their_slots_ui().size() if own_row else 0)
	var target_seat: int = room.local_seat if own_row else _viewed_seat
	var eligible := false
	if is_my_turn() and source >= 0 and slot >= 0:
		if current_attacker_idx >= 0:
			var card: CardData = _their_field().slots[slot]
			eligible = not own_row and _their_field().player_hp > 0 and card != null and card.is_selectable() \
				and (not _is_enemy(_viewed_seat) or card.has_taunt() or not _their_field().has_any_taunt())
		else:
			eligible = _can_target_skill_slot(target_row, slot)
	if eligible:
		room.publish_targeting_aim(source, target_seat, slot)
		_aim_sent = true
	else:
		_clear_targeting_aim()


func cancel_attack():
	_clear_targeting_aim()
	super.cancel_attack()


func _clear_targeting_aim() -> void:
	if _aim_sent:
		_aim_sent = false
		room.publish_targeting_aim(-1, -1, -1)


func _remote_targeting_points() -> PackedVector2Array:
	if not _can_show_remote_targeting() or _leaving:
		return PackedVector2Array()
	var aim: Dictionary = room.visible_targeting_aim()
	if aim.is_empty() or int(aim.seat) != _viewed_seat:
		return PackedVector2Array()
	var target_seat: int = aim.target_seat
	if target_seat != room.local_seat and target_seat != _viewed_seat:
		return PackedVector2Array()
	var targets := _my_slots_ui() if target_seat == room.local_seat else _their_slots_ui()
	return _targeting_points(_their_slots_ui()[aim.source], targets[aim.target])


func _skill_target_is_hostile(player: int) -> bool:
	return player != _view_player() and _is_enemy(_viewed_seat)


func _summon_skill_has_live_manual_target(skill: Dictionary, _player: int, source: CardData) -> bool:
	if SpellRules.has_selectable_unit(skill, source, _my_field(), false, game.turn_number):
		return true
	for member: Dictionary in room.view.players:
		var seat: int = member.seat
		if seat == room.local_seat or int(member.hp) <= 0:
			continue
		var field := _their_field() if seat == _viewed_seat else BattleField.new("")
		if seat != _viewed_seat:
			_project_field(field, member)
		if SpellRules.has_selectable_unit(skill, source, field, _is_enemy(seat), game.turn_number):
			return true
	return false


func _on_opponent_slot_clicked(index: int):
	if _viewed_seat == _enemy_seat or summon_targeting or activate_targeting or cast_targeting \
			or ((current_attacker_idx >= 0 or parasite_targeting) and _their_field().player_hp > 0):
		super._on_opponent_slot_clicked(index)


func _dispatch_mode_action(command: String, source: int, target_player: int, target_slot: int, skill: int = -1) -> bool:
	if not room.is_my_turn():
		return true
	var targets_viewed_field := command in ["attack", "skill", "cast", "parasite"] and target_slot >= 0
	var target: int = room.local_seat if target_player == 1 else (_viewed_seat if targets_viewed_field else _enemy_seat)
	if command == "summon":
		skill = _enemy_seat
	if target_player == 2 and _viewed_seat != _enemy_seat and command != "end" and not targets_viewed_field:
		return true
	if command == "end" and _viewed_seat != _enemy_seat:
		_view_seat(_enemy_seat)
	room.play(command, source, target, target_slot, skill)
	return true


func _queue_party_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		_refresh_party_view.call_deferred()


func _refresh_party_view() -> void:
	_refresh_pending = false
	if not room.started or room.view.is_empty():
		return
	match_paused = room.reconnecting or not room.absent_seats.is_empty() or room.interrupted
	_close_recovery_forfeit_if_restored()
	var view: Dictionary = room.view
	if _history_recorded and view.has("ranked_settlement"):
		_sync_ranked_history_receipt(view)
	var previous := _projected_view
	var action: Dictionary = view.get("last_action", {})
	if int(view.revision) != _revision:
		var viewing_enemy := _viewed_seat == _enemy_seat
		_rebuild_enemy()
		if viewing_enemy and _enemy_seat > 0:
			_viewed_seat = _enemy_seat
		if is_instance_valid(card_inspector):
			card_inspector.hide()
		cancel_attack()
		_play_party_move(action)
		_project_snapshot()
		_refresh_hand_ui()
		_play_party_feedback.call_deferred(previous, action, _revision)
		_resume_auto_summon_targeting.call_deferred()
	_refresh_seat_bar()
	_sync_picker()
	update_entire_screen()
	if battle_finished:
		_refresh_online_result_destination()
	elif int(view.winner) != 0 or room.interrupted:
		_finish_party_result.call_deferred()


func _play_party_move(action: Dictionary) -> void:
	if action.get("command") == "move" and int(action.seat) in [room.local_seat, _viewed_seat]:
		_play_move_feedback(1 if int(action.seat) == room.local_seat else 2, int(action.source), int(action.target_slot))


func _play_party_feedback(before: Dictionary, action: Dictionary, revision: int) -> void:
	if _revision != revision or before.is_empty():
		return
	if not action.is_empty() and int(action.revision) == revision:
		var seat := int(action.seat)
		var actor := 1 if seat == room.local_seat else 2
		var old: Dictionary = before.players[seat - 1]
		var card_name := ""
		var source := int(action.source)
		var destination := int(action.target_slot)
		var command := str(action.command)
		if command in ["attack", "skill", "move", "discard_field"] and source in range(5):
			card_name = str(old.slots[source].get("name", ""))
		elif seat == room.local_seat and command in ["cast", "parasite", "discard"] and source in range(before.hand.size()):
			card_name = str(before.hand[source].get("name", ""))
		if command == "summon" and destination in range(5):
			card_name = str(_player(seat).slots[destination].get("name", ""))
		var action_name := Locale.t("battle.end_turn" if command == "end" else "team." + ("discard" if command == "discard_field" else command))
		if not card_name.is_empty():
			action_name += "  " + card_name
		_show_combat_broadcast("%s  %s" % [_seat_name(seat), action_name])
		if seat in [room.local_seat, _viewed_seat]:
			match command:
				"attack": _play_attack_feedback(actor, source, destination if int(action.target_seat) in [room.local_seat, _viewed_seat] else -1)
				"summon": _play_summon_feedback(_slot_ui_for_player(actor, destination))
				"skill": _play_skill_cast_feedback(actor, source, int(action.skill))
				"cast", "parasite": _play_skill_cast_feedback(actor, -1)
				"discard", "discard_field": _play_discard_feedback()
	for seat in [room.local_seat, _viewed_seat]:
		var actor := 1 if seat == room.local_seat else 2
		var old: Dictionary = before.players[seat - 1]
		var player := _player(seat)
		for index in range(5):
			var previous_card: Dictionary = old.slots[index]
			var next_card: Dictionary = player.slots[index]
			if previous_card.is_empty():
				continue
			if next_card.is_empty() and action.get("command") not in ["move", "discard_field"]:
				BattleFx.death_burst($CanvasLayer, _slot_ui_for_player(actor, index).get_global_rect().get_center(), _ui_scale())
			elif not next_card.is_empty() and previous_card.instance_id == next_card.instance_id:
				var delta := int(next_card.hp) + int(next_card.temp_hp) - int(previous_card.hp) - int(previous_card.temp_hp)
				if delta != 0:
					_show_combat_feedback_for(actor, index, delta)


func _enemy_swap_is_pending() -> bool:
	return room.can_answer_choice() and room.view.choice.get("kind") == "enemy_swap"


func enemy_swap_drag_payload(source: int) -> Dictionary:
	if not _enemy_swap_is_pending() or _viewed_seat != int(room.view.choice.target_seat):
		return {}
	var card: CardData = _their_field().slots[source]
	if card == null or not card.is_selectable():
		return {}
	return {"enemy_swap_source": source, "revision": _revision}


func can_drop_enemy_swap(data: Dictionary, destination: int) -> bool:
	if not _enemy_swap_is_pending() or _viewed_seat != int(room.view.choice.target_seat) \
			or int(data.get("revision", -1)) != _revision or int(data.get("enemy_swap_source", -1)) == destination:
		return false
	var card: CardData = _their_field().slots[destination]
	return card == null or card.is_selectable()


func drop_enemy_swap(data: Dictionary, destination: int) -> void:
	if can_drop_enemy_swap(data, destination):
		room.choose_cards([int(data.enemy_swap_source) * 5 + destination])


func _submit_online_cost_choice(_revision_value: int, _index: int) -> void:
	room.choose_cards([])


func _sync_picker() -> void:
	if is_instance_valid(_picker):
		if not room.can_answer_choice() or _picker.get_meta("revision") != _revision:
			_picker.set_meta("submitted", true)
			_picker.queue_free()
		return
	if not room.can_answer_choice():
		return
	var choice: Dictionary = room.view.choice
	if choice.kind == "enemy_swap":
		_view_seat(int(choice.target_seat))
		return
	var cards := _decode_cards(choice.cards, [])
	var title := _cost_picker_title(choice.value, choice.mode, choice.target) if choice.kind == "cost" else \
		Locale.t("battle.choose_keep") + " (" + Locale.t("battle.draw_pile" if choice.kind == "deck" else "battle.discard_pile") + ")"
	var revision := _revision
	var popup: CanvasLayer = COLLECTION.show_cards(self, cards, title, int(choice.count))
	_picker = popup
	popup.set_meta("revision", revision)
	popup.on_confirm = func(selected: Array):
		popup.set_meta("submitted", true)
		room.choose_cards(selected.map(func(card): return cards.find(card)))
	popup.tree_exited.connect(func():
		_picker = null
		if not is_inside_tree() or not room.started:
			return
		if not popup.get_meta("submitted", false) and room.can_answer_choice() and revision == _revision:
			room.choose_cards.call_deferred([])
		else:
			_sync_picker.call_deferred())


func _on_help_clicked():
	if not room.matchmaking_mode.is_empty():
		super._on_help_clicked()
		return
	var dialog := AcceptDialog.new()
	dialog.title = Locale.t("team.title")
	dialog.dialog_text = Locale.t("team.battle_rules")
	dialog.dialog_autowrap = true
	dialog.ok_button_text = Locale.t("common.close")
	add_child(dialog)
	UITheme.apply_dialog(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(500, 0))


func _finish_party_result() -> void:
	if not is_inside_tree() or battle_finished or _result_waiting_for_feedback:
		return
	_show_result(str(room.view.winner))


func _did_local_player_win(result: String) -> bool:
	return int(result) != 0 and int(result) == _local_team


func _result_title(result: String) -> String:
	if room.interrupted:
		return Locale.t("team.disconnected")
	if int(result) == 3:
		return Locale.t("team.draw")
	return Locale.t("result.online_win" if _did_local_player_win(result) else "result.online_loss")


func _result_mode_text() -> String:
	if not room.matchmaking_mode.is_empty():
		return Locale.t("matchmaking." + room.matchmaking_mode)
	return Locale.t("team.title")


func _result_summary_text() -> String:
	if not room.matchmaking_mode.is_empty():
		var result := Locale.t("matchmaking.result", [game.turn_number, game.player_field.player_hp, game.player2_field.player_hp])
		var rating: Dictionary = room.view.get("ranked_rating", {})
		if not rating.is_empty():
			result += "\n" + Locale.t("matchmaking.rating_change", [int(rating.rating), "%+d" % int(rating.change)])
			if int(rating.change) > 0 and rating.has("multiplier"):
				result += "\n" + Locale.t("matchmaking.result_multiplier", [rating.multiplier])
		return result
	var survivors := [0, 0]
	for player: Dictionary in _projected_view.players:
		if int(player.hp) > 0:
			survivors[int(int(player.team) != _local_team)] += 1
	return Locale.t("team.result_summary", [game.turn_number, survivors[0], survivors[1]])


func _record_match_history(_outcome: String, _result: String) -> void:
	if _history_recorded or room.matchmaking_mode.is_empty():
		return
	_history_recorded = true
	var outcome := "finished"
	if room.interrupted:
		outcome = "interrupted"
	elif int(_result) != 3:
		outcome = "victory" if _did_local_player_win(_result) else "defeat"
	var pool := match_info_cards()
	if not room.local_art.is_empty():
		for card: CardData in pool:
			BattleArtResolver.restore_card(card, room.local_art)
	var faces := PlayerData.snapshot_history_cards(pool)
	var entry := {
		"mode": room.matchmaking_mode,
		"outcome": outcome,
		"result": _result,
		"turns": game.turn_number,
		"player_hp": game.player_field.player_hp,
		"opponent_hp": game.player2_field.player_hp,
		"player_max_hp": game.player_field.max_player_hp,
		"opponent_max_hp": game.player2_field.max_player_hp,
		"deck_name": room.contribution_name,
		"deck_cards": faces.map(func(face: Dictionary): return face.name),
		"deck_card_faces": faces,
		"app_version": AppVersion.VERSION,
		"duration": maxi(0, roundi(Time.get_unix_time_from_system() - _battle_started_at)),
	}
	var match_id := str(room.view.get("ranked_match_id", ""))
	if not match_id.is_empty():
		entry["ranked_match_id"] = match_id
		var receipt: Variant = room.view.get("ranked_settlement")
		if PlayerData.valid_ranked_history_settlement(receipt):
			entry["ranked_settlement"] = receipt
	PlayerData.add_match_history(entry)


func _sync_ranked_history_receipt(view: Dictionary) -> void:
	var match_id := str(view.get("ranked_match_id", ""))
	if not match_id.is_empty():
		PlayerData.apply_ranked_history_settlements({match_id: view.ranked_settlement})


func match_info_cards() -> Array:
	return room.view.get("match_pool", []).map(PlayerData.deserialize_card)


func _refresh_online_result_destination() -> void:
	if is_instance_valid(_online_result_back_btn):
		if not room.matchmaking_mode.is_empty():
			_online_result_back_btn.text = Locale.t("matchmaking.back")
			_online_result_back_btn.disabled = false
			return
		_online_result_back_btn.text = Locale.t("team.rematch_waiting" if room.rematch_requested else "team.rematch")
		_online_result_back_btn.disabled = not room.can_rematch()


func _on_online_result_back_pressed() -> void:
	if not room.matchmaking_mode.is_empty():
		room.close()
		UIMotion.replace_scene("res://MatchmakingLobby.tscn")
		return
	room.request_rematch()


func _on_result_back_menu_pressed(_menu_button: Button = null) -> void:
	_abandon_battle_now()


func _abandon_battle_now() -> void:
	if _leaving:
		return
	_leaving = true
	var connection := "mp.dedicated" if room.use_dedicated_lobby else "mp.direct"
	var route := "online:%s:team.title" % connection
	if not room.matchmaking_mode.is_empty():
		route = "online:mp.dedicated:matchmaking." + room.matchmaking_mode
	await room.leave()
	if is_inside_tree():
		UIMotion.replace_scene("res://MainMenu.tscn", true, route)


func _return_to_lobby() -> void:
	UIMotion.replace_scene("res://TeamLobby.tscn" if room.matchmaking_mode.is_empty() else "res://MatchmakingLobby.tscn")
