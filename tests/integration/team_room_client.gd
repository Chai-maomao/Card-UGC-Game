extends Node

const VisualInput = preload("res://tests/VisualBattleInput.gd")

@onready var room: Node = NetworkManager.team_room
var _rejections := 0
var _observed_pause := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var host := args.has("--host")
	var invite := OS.get_environment("CARDEX_PARTY_INVITE")
	var room_code := OS.get_environment("CARDEX_PARTY_TEST_ROOM")
	if room_code.is_empty():
		room_code = "partytest"
	var server_address := OS.get_environment("CARDEX_PARTY_TEST_LOBBY")
	var managed := args.has("--managed-lobby")
	var verify_aim := args.has("--verify-aim")
	var creates_room := args.has("--create-room")
	var count := _argument(args, "--players=", 3)
	var port := _argument(args, "--port=", 8971)
	var capture_path := ""
	var size_override := Vector2i.ZERO
	for arg in args:
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--window-size="):
			var dimensions := arg.trim_prefix("--window-size=").split("x")
			if dimensions.size() == 2:
				size_override = Vector2i(dimensions[0].to_int(), dimensions[1].to_int())
	await get_tree().process_frame
	if size_override.x > 0 and size_override.y > 0:
		get_window().size = size_override
	var lobby_ui: Control
	if managed or verify_aim or not capture_path.is_empty():
		room.use_dedicated_lobby = managed
		lobby_ui = load("res://TeamLobby.tscn").instantiate()
		if verify_aim:
			# Older room servers omit the optional reveal deadline on the opening snapshot.
			room.battle_started.connect(func():
				if room.local_seat == 2:
					room._team_reveal_until = 0)
		get_tree().root.add_child(lobby_ui)
		get_tree().current_scene = lobby_ui
	room.action_rejected.connect(func(): _rejections += 1)
	room.view_changed.connect(func():
		_observed_pause = _observed_pause or not room.absent_seats.is_empty())
	if managed:
		lobby_ui._address.text = room_code
		lobby_ui._server_address.text = "127.0.0.1:%d" % port if server_address.is_empty() else server_address
		lobby_ui._count.select(count - 3)
		lobby_ui._refresh()
		var button: Button = lobby_ui._host if creates_room else lobby_ui._join
		button.pressed.emit()
	elif host:
		if room.host(count, port) != OK:
			_fail("Host bind failed")
			return
		print("TEAM_HOST_LISTENING")
	elif args.has("--wrong-invite"):
		var messages: Array[String] = []
		room.failed.connect(func(message: String): messages.append(message))
		if room.join("127.0.0.1", port, invite + "0") != OK or not await _until(func(): return not messages.is_empty()):
			_fail("Invalid invite did not receive a rejection")
		elif messages != ["team.bad_code"] or room.local_seat != 0 or room.is_open():
			_fail("Invalid invite acquired a seat")
		else:
			print("TEAM_INVALID_INVITE_REJECTED")
			get_tree().quit(0)
		return
	elif room.join("127.0.0.1", port, invite) != OK:
		_fail("Join could not start")
		return
	if not await _until(func(): return room.local_seat > 0 and room.occupied.has(room.local_seat)):
		_fail("No authenticated seat" + (": " + lobby_ui._status.text if is_instance_valid(lobby_ui) else ""))
		return
	if room.seat_count != count:
		_fail("Unexpected room capacity")
		return
	if managed and (room.lobby_room_code != room_code or room.is_host() != creates_room):
		_fail("Managed lobby must give the room code and reserve seat 1 for the creator")
		return
	print("TEAM_CLIENT_SEATED ", room.local_seat)
	if managed:
		if creates_room:
			lobby_ui._open_battle_settings()
			var settings := lobby_ui.get_node("AdvancedSettings")
			(settings.find_child("starting_hp", true, false) as SpinBox).value = 28
			(settings.find_child("action_time_seconds", true, false) as SpinBox).value = 11
			(settings.find_child("first_action_time_seconds", true, false) as SpinBox).value = 37
			for confirm in settings.find_children("*", "Button", true, false):
				if confirm.text == Locale.t("common.confirm"):
					confirm.pressed.emit()
					break
		if not await _until(func():
			return int(room.battle_rules.starting_hp) == 28 and int(room.battle_rules.action_time_seconds) == 11 \
				and int(room.battle_rules.first_action_time_seconds) == 37):
			_fail("Edited rules did not reach all room seats")
			return
	var deck: Array[CardData] = []
	for index in 10:
		var skill := {"skill_name": "Search", "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100,
			"effects": [{"effect": SkillRegistry.EFFECT_VIEW_DECK, "target": SkillEngine.TARGET_SELF,
				"value": 1, "random_count": 2}]}
		var active_skill := {"skill_name": "Rally", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100,
			"effects": [{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ALLY, "value": 1}]}
		deck.append(CardData.new("Seat %d unit %d" % [room.local_seat, index], 0, 3, 45, [skill, active_skill]))
	if not room.submit_deck(deck).is_empty():
		_fail("Deck submission refused")
		return
	if room.is_host():
		if count == 4 and not _check_eliminated_player_turn():
			_fail("A player eliminated by their own skill kept their turn")
			return
		if not await _until(room.can_start):
			_fail("All players could not ready up")
			return
		if not capture_path.is_empty():
			await _capture(capture_path.path_join("lobby.png"))
			await _click(lobby_ui._start)
		else:
			room.start()
	if not await _until(func(): return room.started):
		_fail("Did not enter battle")
		return
	var initial: Dictionary = room.view
	var battle_ui: Node
	var aim_view: Node
	if is_instance_valid(lobby_ui):
		var reveal := lobby_ui.get_node_or_null("TeamReveal")
		var confirm := reveal.find_child("TeamRevealConfirm", true, false) as Button if reveal != null else null
		if confirm == null:
			_fail("The lobby did not show its team reveal before entering battle")
			return
		if not capture_path.is_empty():
			await get_tree().create_timer(1.0).timeout
			await _capture(capture_path.path_join("team-reveal.png"))
		if verify_aim and room.local_seat == 2:
			await get_tree().create_timer((room.TEAM_REVEAL_MS + 250) / 1000.0).timeout
			if get_tree().current_scene != lobby_ui or not room.team_reveal_pending() or room.is_my_turn() \
					or room.action_clock.remaining_ms != room.action_clock.limit_ms:
				_fail("The unconfirmed player must stay in the lobby and keep the opening clock paused")
				return
		await _click(confirm)
		if not await _until(func():
			var scene := get_tree().current_scene
			return scene != null and scene.scene_file_path == "res://TeamBattle.tscn"):
			_fail("The reveal did not transition to battle")
			return
		var opened_battle := get_tree().current_scene
		room.returned_to_lobby.disconnect(opened_battle._return_to_lobby)
		print("TEAM_REVEAL_OK ", room.local_seat)
		if not capture_path.is_empty():
			battle_ui = opened_battle
		elif verify_aim:
			aim_view = opened_battle
	else:
		room.confirm_team_reveal()
	if not await _until(func(): return not room.team_reveal_pending()):
		_fail("The match did not unlock after all players confirmed")
		return
	if not capture_path.is_empty():
		if not await _check_board_view(battle_ui, count):
			_fail("The overview must switch inspected lanes and keep the local lane visible")
			return
		print("TEAM_BOARD_LAYOUT_OK ", count, " players at ", get_viewport().get_visible_rect().size)
		await _capture(capture_path.path_join("battle.png"))
	var team: int = initial.players[room.local_seat - 1].team
	var team_one: Array = initial.players.filter(func(player): return player.team == 1)
	if initial.players.size() != count or team_one.size() != floori(count / 2.0) or initial.hand.is_empty():
		_fail("Unexpected team assignment or opening hand")
		return
	if managed:
		var expected_hp := {3: [42, 23], 4: [28, 28], 5: [35, 24]}
		if initial.players.any(func(player): return player.max_hp != expected_hp[count][int(player.team) - 1]):
			_fail("The edited starting life was not used for the match")
			return
		if room.action_clock.limit_ms != 37000:
			_fail("The opening clock did not use the first-action limit set in the lobby")
			return
		print("TEAM_SETTINGS_OK ", room.local_seat)
	for player: Dictionary in initial.players:
		if player.has("hand") or (player.seat == room.local_seat and player.hand_count != initial.hand.size()):
			_fail("Hand ownership or privacy failed")
			return
	if not host and initial.active != room.local_seat:
		room.rpc_id(1, "_play", initial.revision, "end", -1, _opponent(initial, team), -1, -1)
		if not await _until(func(): return _rejections > 0):
			_fail("The host accepted an out-of-turn command")
			return
	if count == 3:
		await get_tree().create_timer(0.5).timeout
		if room.local_seat == 2:
			if verify_aim:
				room.view_changed.connect(func():
					if room.reconnecting:
						room._next_attempt = Time.get_ticks_msec() + 2200, CONNECT_ONE_SHOT)
			room._peer.disconnect_peer(1)
			if not await _until(func(): return room.reconnecting):
				_fail("The client did not start reconnecting after a transport loss")
				return
			if not await _until(func(): return not room.reconnecting and room.is_open() and not room.interrupted):
				_fail("The guest did not recover")
				return
			if room.local_seat != 2 or room.view != initial:
				_fail("The guest did not recover the exact seat and private hand")
				return
		else:
			if is_instance_valid(battle_ui):
				if not await _until(func(): return battle_ui.reconnect_leave_button.is_visible_in_tree()):
					_fail("The battle did not show the recovery controls")
					return
				if battle_ui.turn_wait_hint.get_node("Label").is_visible_in_tree():
					_fail("Party recovery text spills into the status strip")
					return
				await _click(battle_ui.reconnect_leave_button)
				var confirmation := battle_ui.get_node_or_null("AbandonBattleConfirmation") as CanvasLayer
				if confirmation == null or not confirmation.is_in_group("battle_modal"):
					_fail("The party recovery button did not open the standard battle dialog")
					return
				await _capture(capture_path.path_join("leave-confirmation.png"))
			if not await _until(func(): return _observed_pause and room.absent_seats.is_empty()):
				_fail("Connected peers did not observe pause and recovery")
				return
			if is_instance_valid(battle_ui) and not await _until(func(): return not battle_ui.has_node("AbandonBattleConfirmation")):
				_fail("The recovery confirmation remained open when the player returned")
				return
	await get_tree().create_timer(0.5).timeout
	var revisions: Array[int] = []
	var seen_eliminated := false
	var answered := false
	var hand_before_search := 0
	var retained := ""
	var verified_choice := false
	var clicked_end := false
	var dragged := false
	var moved := false
	var spare_deployed := false
	var field_discarded := false
	var saw_aim := false
	var saw_aim_clear := false
	var started_at := Time.get_ticks_msec()
	while int(room.view.winner) == 0 and not room.interrupted:
		if Time.get_ticks_msec() - started_at > 18000:
			_fail("Battle stalled (seat %d, active %s, chooser %s, round %s, revision %s)" % [
				room.local_seat, room.view.active, room.view.chooser, room.view.round, room.view.revision])
			return
		if int(room.view.chooser) != room.local_seat and not room.view.choice.is_empty():
			_fail("Other players received contents of a private picker")
			return
		if is_instance_valid(aim_view) and not saw_aim:
			var aim: Dictionary = room.visible_targeting_aim()
			if not aim.is_empty():
				aim_view._view_seat(aim.seat)
				await get_tree().process_frame
				var points: PackedVector2Array = aim_view._remote_targeting_points()
				if (points.size() != 2 or points[0] == points[1]
						or not points[0].is_equal_approx(aim_view._their_slots_ui()[aim.source].get_global_rect().get_center())
						or not points[1].is_equal_approx(aim_view._their_slots_ui()[aim.target].get_global_rect().get_center())):
					_fail("The replicated arrow did not connect the selected player's two units")
					return
				if not await _until(func(): return aim_view.attack_arrow.visible):
					_fail("The battlefield did not display the replicated aiming arrow")
					return
				for seat in aim_view._seat_buttons:
					if seat != aim.seat:
						aim_view._view_seat(seat)
						break
				if not aim_view._remote_targeting_points().is_empty():
					_fail("The replicated arrow remained visible on another player's field")
					return
				aim_view._view_seat(aim.seat)
				saw_aim = true
		elif saw_aim and room.targeting_aim.is_empty():
			saw_aim_clear = true
		if room.can_answer_choice():
			hand_before_search = room.view.hand.size()
			retained = room.view.choice.cards[0].instance_id
			if is_instance_valid(battle_ui) and is_instance_valid(battle_ui._picker):
				var picker: CanvasLayer = battle_ui._picker
				await _click(picker.selection_overlays[0])
				if is_instance_valid(battle_ui.card_inspector) and battle_ui.card_inspector.visible:
					for button in battle_ui.card_inspector.find_children("*", "Button", true, false):
						if button.text == Locale.t("common.close"):
							await _click(button)
							break
				await _click(picker.confirm_button)
			else:
				room.choose_cards([0])
			answered = true
		elif room.is_my_turn() and not revisions.has(room.view.revision):
			if answered and not verified_choice:
				verified_choice = room.view.hand.size() == hand_before_search + 1 \
					and room.view.hand.any(func(card): return card.instance_id == retained)
			revisions.append(room.view.revision)
			var rival := _opponent(room.view, team)
			var own: Dictionary = room.view.players[room.local_seat - 1]
			if own.slots[0].is_empty() and (team == 1 or (is_instance_valid(battle_ui) and not dragged)):
				if is_instance_valid(battle_ui) and not dragged:
					var hand_card: Control = battle_ui.hand_container.get_child(0)
					var target: Control = battle_ui.player_side_ui.get_child(0)
					await _click(hand_card)
					if not is_instance_valid(battle_ui.card_inspector) or not battle_ui.card_inspector.visible:
						_fail("Clicking a party hand card did not open the standard inspector")
						return
					battle_ui.card_inspector.hide()
					await _drag(hand_card.get_global_rect().get_center(), target.get_global_rect().get_center())
					if not await _until(func(): return not room.view.players[room.local_seat - 1].slots[0].is_empty() and int(room.view.chooser) == room.local_seat):
						_fail("Dragging a hand card onto the 3D board did not summon it")
						return
					dragged = true
					await _capture(capture_path.path_join("battle-playing.png"))
				else:
					room.play("summon", 0, room.local_seat, 0)
			elif is_instance_valid(battle_ui) and dragged and not moved and not own.slots[0].is_empty():
				var from: Control = battle_ui.player_side_ui.get_child(0)
				var to: Control = battle_ui.player_side_ui.get_child(1)
				var id := str(own.slots[0].instance_id)
				await _drag(from.get_global_rect().get_center(), to.get_global_rect().get_center())
				if not await _until(func(): return room.view.players[room.local_seat - 1].slots[1].get("instance_id") == id):
					_fail("Dragging an on-board unit did not move it through the room authority")
					return
				await _drag(to.get_global_rect().get_center(), from.get_global_rect().get_center())
				if not await _until(func(): return room.view.players[room.local_seat - 1].slots[0].get("instance_id") == id):
					_fail("Dragging the on-board unit back did not restore its slot")
					return
				moved = true
				if not await _check_skill_input(battle_ui, from):
					_fail("The standard skill inspector, aiming, cancellation, or skill submission failed")
					return
				await _capture(capture_path.path_join("battle-playing.png"))
			elif is_instance_valid(battle_ui) and moved and not field_discarded:
				var spare: Control = battle_ui.player_side_ui.get_child(1)
				if not spare_deployed:
					var hand_card: Control = battle_ui.hand_container.get_child(0)
					await _drag(hand_card.get_global_rect().get_center(), spare.get_global_rect().get_center())
					if not await _until(func(): return not room.view.players[room.local_seat - 1].slots[1].is_empty()):
						_fail("Could not deploy the card for the on-board discard check")
						return
					spare_deployed = true
				else:
					if not await _check_open_aim(battle_ui, spare, battle_ui.player_side_ui.get_child(0)):
						_fail("A player could not aim a skill at their other unit")
						return
					if verify_aim:
						await get_tree().create_timer(0.45).timeout
						if not battle_ui._aim_sent:
							_fail("No aim was sent from the pointed slot %d (mouse %s, target %s)" % [
								battle_ui.last_hovered_target, battle_ui.get_global_mouse_position(),
								battle_ui.player_side_ui.get_child(0).get_global_rect()])
							return
					var revision: int = room.view.revision
					await _click(battle_ui.player_side_ui.get_child(2))
					if battle_ui.activate_targeting or int(room.view.revision) != revision:
						_fail("Cancelling the aim changed the authoritative battle")
						return
					if verify_aim:
						await get_tree().create_timer(0.2).timeout
					if not await _check_open_aim(battle_ui, spare, battle_ui.player_side_ui.get_child(0)):
						_fail("The player could not aim again after cancellation")
						return
					await _click(battle_ui.player_side_ui.get_child(0))
					if not await _until(func(): return int(room.view.revision) > revision and room.view.players[room.local_seat - 1].slots[1].get("skills_used", []).has(1)):
						_fail("Selecting the other unit did not resolve the skill")
						return
					var pile: Control = battle_ui.discard_pile_btn
					var discard_before := int(room.view.discard_count)
					await _drag(spare.get_global_rect().get_center(), pile.get_global_rect().get_center())
					if not await _until(func(): return room.view.players[room.local_seat - 1].slots[1].is_empty() and int(room.view.discard_count) == discard_before + 1):
						_fail("Dragging a board card to the discard pile was not applied by the authority")
						return
					field_discarded = true
			elif team == 1 and int(room.view.round) > 1 and not own.slots[0].get("has_acted", true) \
					and not room.view.players[rival - 1].slots[0].is_empty():
				room.play("attack", 0, rival, 0)
			else:
				if is_instance_valid(battle_ui):
					await _click(battle_ui.end_turn_button)
					clicked_end = true
				else:
					room.play("end", -1, rival, -1)
		if room.view.players.any(func(player): return player.hp == 0):
			seen_eliminated = true
		await get_tree().process_frame
	# The final snapshot can arrive during the frame wait above and end the loop.
	seen_eliminated = seen_eliminated or room.view.players.any(func(player): return player.hp == 0)
	if int(room.view.winner) != 1 or not seen_eliminated or revisions.is_empty() or (team == 1 and not verified_choice):
		_fail("Unexpected result (seat %d, team %d, winner %s, elimination seen %s, submitted %s, choice verified %s)" % [
			room.local_seat, team, room.view.winner, seen_eliminated, revisions, verified_choice])
		return
	if is_instance_valid(aim_view) and not (saw_aim and saw_aim_clear):
		_fail("A spectator did not receive the aim and its explicit cancellation (aim %s, cancellation %s)" % [saw_aim, saw_aim_clear])
		return
	if not capture_path.is_empty():
		if not clicked_end or not dragged or not moved or not field_discarded:
			_fail("The native battle controls were not exercised")
			return
		if not await _until(func(): return is_instance_valid(battle_ui._online_result_back_btn)):
			_fail("The standard result view did not offer a party rematch")
			return
		await _capture(capture_path.path_join("result.png"))
	var hp_values: Array = room.view.players.map(func(player): return player.hp)
	var report := {"players": count, "seat": room.local_seat,
		"submitted_revisions": revisions, "opening_hand": initial.hand.map(func(card): return card.instance_id),
		"hp": hp_values, "winner": room.view.winner, "revision": room.view.revision}
	if is_instance_valid(battle_ui):
		await _click(battle_ui._online_result_back_btn)
	else:
		room.request_rematch()
	if not await _until(func(): return not room.started and room.occupied.size() == count and room.ready_seats.is_empty()):
		_fail("Players could not return to the same room for a new match")
		return
	print("TEST_TEAM_ROOM_OK ", JSON.stringify(report))
	# All peers must receive the result before the host shuts down the transport.
	await get_tree().create_timer(0.4).timeout
	room.close()
	get_tree().quit(0)


func _check_board_view(battle: Node, count: int) -> bool:
	if battle._seat_buttons.size() != count - 1:
		return false
	var seat_rect: Rect2 = battle._seat_bar.get_global_rect()
	if not get_viewport().get_visible_rect().encloses(seat_rect) \
			or seat_rect.intersects(battle.middle_info_bar.get_global_rect()) \
			or seat_rect.intersects(battle.end_turn_button.get_global_rect()) \
			or seat_rect.intersects(battle.discard_zone.get_global_rect()):
		push_error("Seat bounds %s must avoid turn bounds %s and discard bounds %s" % [
			seat_rect, battle.middle_info_bar.get_global_rect(), battle.discard_zone.get_global_rect()])
		return false
	var original: int = battle._viewed_seat
	for seat in battle._seat_buttons:
		var button: Button = battle._seat_buttons[seat]
		await _click(button)
		if (battle._viewed_seat != seat or battle._their_field().player_hp != room.view.players[seat - 1].hp
				or battle._my_field().player_hp != room.view.players[room.local_seat - 1].hp):
			return false
	await _click(battle._seat_buttons[original])
	return true


func _check_skill_input(battle: Node, source: Control) -> bool:
	var before := int(room.view.revision)
	if not await _check_open_aim(battle, source, source):
		return false
	await _click(source)
	if not battle.activate_targeting or int(room.view.revision) != before:
		return false
	await _click(battle.player_side_ui.get_child(2))
	return not battle.activate_targeting and int(room.view.revision) == before


func _check_open_aim(battle: Node, source: Control, target: Control) -> bool:
	await _click(source)
	if not is_instance_valid(battle.card_inspector) or not battle.card_inspector.visible:
		return false
	var skill := battle.card_inspector.find_child("TabletopSkill1", true, false) as Button
	if skill == null or skill.disabled:
		return false
	await _click(skill)
	var motion := InputEventMouseMotion.new()
	motion.position = target.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	return battle.activate_targeting and battle.attack_arrow.visible


func _check_eliminated_player_turn() -> bool:
	var state := preload("res://TeamBattleState.gd").new()
	var spell := CardData.new("Last Stand", 0, 1, 0, [{"skill_name": "Last Stand",
		"trigger": SkillEngine.TRIGGER_ON_CAST, "probability": 100, "effects": [{
			"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_PLAYER,
			"target_side": SkillEngine.TARGET_SIDE_ALLY, "value": 30}]}])
	spell.card_type = "spell"
	var decks := {}
	for seat in range(1, 5):
		decks[seat] = [PlayerData.serialize_card(CardData.new("Unit %d" % seat, 1, 1, 1))]
	state.start_match(decks, [1, 2, 3, 4], 17)
	state.hands[1].append(spell)
	var index: int = state.hands[1].size() - 1
	return (state.apply_action(1, 0, "cast", index, 1, -1, 0) and state.fields[1].player_hp == 0
		and state.winner == 0 and state.active_seat == 2 and not state.apply_action(1, 1, "end", -1, 3, -1, -1))


func _opponent(snapshot: Dictionary, team: int) -> int:
	for player: Dictionary in snapshot.players:
		if player.team != team and player.hp > 0:
			return player.seat
	return 0


func _argument(args: PackedStringArray, prefix: String, fallback: int) -> int:
	for arg in args:
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return fallback


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _capture(path: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _click(control: Control) -> void:
	await get_tree().process_frame
	await VisualInput.click(get_viewport(), control.get_global_rect().get_center())


func _drag(from: Vector2, to: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = from
	get_viewport().push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = from
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	for step in range(1, 9):
		motion = InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(step) / 8.0)
		motion.relative = (to - from) / 8.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion, true)
		await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.position = to
	release.button_index = MOUSE_BUTTON_LEFT
	get_viewport().push_input(release, true)


func _fail(message: String) -> void:
	push_error(message)
	room.close()
	get_tree().quit(1)
