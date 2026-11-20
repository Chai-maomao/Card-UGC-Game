extends Node

const Game = preload("res://GameState.gd")
const Battle = preload("res://Main.tscn")

# Exercise the real setup/restore/first-launch methods without writing user saves.
class MemoryPlayerData:
	extends "res://PlayerData.gd"

	func save_card_draft_recovery() -> bool:
		return true

	func queue_card_draft_recovery() -> void:
		pass

	func save_library() -> bool:
		return true

var failures: Array[String] = []
var opening_cases := 0


func _ready() -> void:
	var original := PlayerData.battle_preparation_snapshot()
	var original_context := PlayerData.card_playtest_context.duplicate(true)
	var original_config := PlayerData.battle_config.duplicate(true)
	NetworkManager.close_connection()
	await _test_playtest_with_room_connection()
	_test_beginner_deck()
	var memory := MemoryPlayerData.new()
	memory.card_draft = {"name": "未丢失的草稿", "cost": 4}
	memory.editing_deck_id = "keep-deck"
	memory.editing_instance_id = "keep-instance"
	memory.configure_practice_battle([CardData.new("old", 1, 2, 1)], [], "hard")
	var old_setup := memory.battle_preparation_snapshot()
	var specimen := CardData.new("待测卡牌", 2, 4, 2, [])
	specimen.instance_id = "playtest-specimen"
	for card_type in ["minion", "spell", "parasite"]:
		specimen.card_type = card_type
		memory.configure_card_playtest(specimen)
		_assert(memory.battle_mode == "hotseat", "editor playtest must use hotseat")
		_assert(memory.battle_deck.size() == 16 and memory.opponent_battle_deck.size() == 16,
			"both players need complete support decks")
		PlayerData._apply_battle_preparation(memory.battle_preparation_snapshot())
		PlayerData.card_playtest_context = memory.card_playtest_context.duplicate(true)
		for draw_count in [0, 2, 5, 6, 8]:
			PlayerData.battle_config["draw_per_turn"] = draw_count
			for seed_value in range(40):
				var game := Game.new()
				game.quiet = true
				game.init_game(Callable(), seed_value)
				opening_cases += 1
				_assert(game.player_hand[0].instance_id == specimen.instance_id,
					"tested card must always be first in player one's hand")
				_assert(game.player_hand[0].card_type == card_type, "all card types must be preserved")
				_assert(game.player_hand.size() == clampi(draw_count + 1, 3, SkillEngine.MAX_HAND_SIZE), "opening must reserve helpers without exceeding the hand limit")
				_assert(game.player2_hand.size() == clampi(draw_count + 1, 3, SkillEngine.MAX_HAND_SIZE), "both sides must receive the test instruments")
				for support_id: String in CardDatabase.PLAYTEST_SUPPORT_IDS:
					_assert(game.player_hand.any(func(c): return c.card_id == support_id), "player one helper missing")
					_assert(game.player2_hand.any(func(c): return c.card_id == support_id), "player two helper missing")
				_assert(game.shared_deck.size() + game.player_hand.size() + game.player2_hand.size() == 33,
					"exactly two starter decks and one test specimen must exist")
				_assert(game.player_hand[0] != specimen, "battle must not mutate saved card")
		_assert(memory.restore_after_card_playtest(), "return to editor must restore context")
		_assert(memory.card_draft.get("name") == "未丢失的草稿", "editor draft must survive")
		_assert(memory.editing_deck_id == "keep-deck" and memory.editing_instance_id == "keep-instance",
			"editor destination must survive")
		_assert(memory.battle_preparation_snapshot() == old_setup, "entire old battle setup must be restored")
		_assert(not memory.restore_after_card_playtest(), "restoration must be idempotent")
	# A fresh real battle must allow both human sides, including actual deployment.
	specimen.card_type = "minion"
	specimen.skills = [{
		"skill_name": "入场鼓舞", "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100,
		"effects": [{"target": SkillEngine.TARGET_SELF, "effect": SkillEngine.EFFECT_GAIN_ATTACK, "value": 1}],
	}]
	memory.configure_card_playtest(specimen)
	PlayerData._apply_battle_preparation(memory.battle_preparation_snapshot())
	PlayerData.card_playtest_context = memory.card_playtest_context.duplicate(true)
	PlayerData.battle_config = original_config.duplicate(true)
	var battle = Battle.instantiate()
	add_child(battle)
	for _frame in range(4):
		await get_tree().process_frame
	_assert(battle._view_player() == 1 and battle.is_my_turn(), "player one must be controllable")
	_assert(battle._my_hand()[0].instance_id == specimen.instance_id, "real scene must display the test specimen")
	if OS.get_cmdline_user_args().has("--visual"):
		DisplayServer.window_set_title("CARDEX · 卡牌热座验收")
		print("PLAYTEST_VISUAL_READY: 玩家一首张为待测卡；结束回合可操控玩家二")
		memory.free()
		return
	battle._on_card_drag_summoned(battle.game.player_hand[0], null, 0)
	_assert(battle.game.player_field.slots[0] != null, "player one drag summon must work")
	_assert(battle.game.player_field.slots[0].field_atk_bonus == 1 and battle.game.player_field.slots[0].skills_used.has(0),
		"non-targeted summon skills must resolve automatically")
	var ready_deadline := Time.get_ticks_msec()+4000
	while battle.is_resolution_locked() and Time.get_ticks_msec()<ready_deadline:
		await get_tree().process_frame
	_assert(not battle.is_resolution_locked(), "deployment must finish before ending the turn")
	await battle._on_end_turn_pressed()
	ready_deadline = Time.get_ticks_msec()+4000
	while not battle.is_my_turn() and Time.get_ticks_msec()<ready_deadline:
		await get_tree().process_frame
	for _frame in range(4):
		await get_tree().process_frame
	_assert(battle.game.current_player == 2 and battle._view_player() == 2 and battle.is_my_turn(),
		"end turn must switch the controllable hand to player two")
	_assert(not battle.end_turn_button.disabled, "the next hotseat player must have an available End Turn button")
	_assert(not battle.practice_ai_running, "AI must not take over either side")
	_assert(battle._turn_owner_text() == Locale.t("battle.hotseat_turn", [2]), "hotseat HUD must identify the acting player")
	_assert(battle.player_status_hud.get_node("Margin/Content/SideLabel").text == Locale.t("battle.hotseat_player", [2]),
		"hand owner's HUD must identify player two")
	var wounded_ally := CardData.new("受伤友军", 1, 4, 1, [])
	wounded_ally.hp = 1
	battle.game.player2_field.slots[1] = wounded_ally
	var p2_card := CardData.new("从二号手牌召唤", 1, 2, 1, [{
		"skill_name": "入场治疗", "trigger": SkillEngine.TRIGGER_ON_SUMMON, "probability": 100,
		"effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "effect": SkillEngine.EFFECT_HEAL, "value": 2}],
	}])
	battle.game.player2_hand.clear()
	battle.game.player2_hand.append(p2_card)
	battle._refresh_hand_ui()
	battle._on_card_drag_summoned(p2_card, null, 0)
	_assert(battle.game.player2_field.slots[0] == p2_card, "player two drag summon must work")
	await get_tree().process_frame
	_assert(battle.summon_targeting and battle.summon_source_slot == 0,
		"a targeted summon skill must open targeting without a skill-button click")
	battle._on_player_slot_clicked(1)
	_assert(wounded_ally.hp == 3 and p2_card.skills_used.has(0),
		"the automatic summon target choice must resolve the queued skill")
	# Let detached transient battle FX finish before their owner is removed.
	await get_tree().create_timer(1.0).timeout
	battle.queue_free()
	await get_tree().process_frame
	PlayerData.configure_practice_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	_assert(PlayerData.card_playtest_opening_card() == null, "ordinary practice must not inherit the test card")
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	_assert(PlayerData.card_playtest_opening_card() == null, "ordinary hotseat must not inherit the test card")
	PlayerData._apply_battle_preparation(original)
	PlayerData.card_playtest_context = original_context
	PlayerData.battle_config = original_config
	memory.free()
	if failures.is_empty():
		print("TEST_CARD_PLAYTEST_OK: %d seeded openings, starter deck, restore, real hotseat actions" % opening_cases)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_CARD_PLAYTEST_FAILED: " + failure)
		get_tree().quit(1)
func _test_playtest_with_room_connection() -> void:
	_assert(NetworkManager.host_game(0) == OK,"room transport must start for the playtest regression")
	var room_peer := NetworkManager.peer
	var old_setup := PlayerData.battle_preparation_snapshot()
	var specimen := CardData.new("房间内测试卡",1,4,2,[])
	specimen.instance_id = "room-playtest-card"
	PlayerData.configure_card_playtest(specimen)
	var opening := PlayerData.card_playtest_opening_card()
	_assert(opening != null and opening.instance_id == specimen.instance_id,"connected room must not hide the local test card")
	var battle = Battle.instantiate()
	add_child(battle)
	for _frame in range(4): await get_tree().process_frame
	_assert(battle.my_player == 0,"local playtest must not take a network player seat")
	_assert(not EventBus.rpc_end_turn_received.is_connected(battle._on_rpc_end_turn),"local test must not subscribe to room battle commands")
	for expected_player in [2,1,2]:
		var deadline := Time.get_ticks_msec()+5000
		while (battle.is_resolution_locked() or battle.hand_container.get_children().any(func(c): return c.get_meta("tabletop_arriving",false))) and Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
		await battle._on_end_turn_pressed()
		deadline = Time.get_ticks_msec()+5000
		while not battle.is_my_turn() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		_assert(battle.game.current_player == expected_player and battle.is_my_turn() and battle._view_player() == expected_player,"room playtest must switch to a controllable P%d instead of waiting remotely" % expected_player)
		if not battle.is_my_turn(): break
	_assert(NetworkManager.is_online and NetworkManager.peer == room_peer,"local testing must preserve the existing room transport")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/room-card-playtest.png")
	battle.queue_free()
	await get_tree().process_frame
	PlayerData.restore_after_card_playtest()
	_assert(PlayerData.battle_preparation_snapshot() == old_setup,"return from local testing must restore the room's battle setup")
	NetworkManager.close_connection()
func _test_beginner_deck() -> void:
	var cards := CardDatabase.beginner_deck()
	var curve := {1: 0, 2: 0, 3: 0, 4: 0}
	var spell_count := 0
	for card: CardData in cards:
		curve[card.cost] += 1
		spell_count += int(card.is_spell())
		_assert(card.skills.size() <= 1, "starter cards must have at most one skill")
		for skill: Dictionary in card.skills:
			_assert(skill.effects.size() == 1, "starter skills must contain one readable effect")
			_assert(SkillErrorChecker.collect_semantic_issues(skill.effects, skill.trigger).is_empty(),
				"starter skills must use valid targets")
			_assert(UgcSafety.validate_skill(skill).is_empty(), "starter skills must satisfy engine limits")
	_assert(cards.size() == 16 and spell_count == 4, "starter deck must contain 12 minions and 4 spells")
	_assert(curve == {1: 4, 2: 6, 3: 4, 4: 2}, "starter cost curve changed unexpectedly")
	_assert(_starter_skill_matches(cards, "侦察兵", SkillEngine.TRIGGER_ON_SUMMON,
		SkillEngine.TARGET_SELF, SkillEngine.EFFECT_DRAW_CARDS, 1),
		"scout must teach summon-triggered card draw")
	_assert(_starter_skill_matches(cards, "盾卫", SkillEngine.TRIGGER_ON_SUMMON,
		SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 1, SkillEngine.BUFF_TAUNT, 2),
		"guard must teach a self-applied taunt status")
	var archer: Dictionary = cards[4].skills[0].effects[0]
	_assert(archer.target == SkillEngine.TARGET_SIDES and archer.target_side == SkillEngine.TARGET_SIDE_ENEMY
		and archer.effect == SkillEngine.EFFECT_DAMAGE and archer.get("value_min") == 1 and archer.get("value_max") == 2,
		"archer must teach both adjacency targeting and variable damage")
	var readiness: Dictionary = cards[3].skills[0].effects[0]
	_assert(readiness.effect == SkillEngine.EFFECT_IF_ELSE and readiness.condition.lhs.var_id == SkillEngine.VAR_HAND_COUNT
		and readiness.then_effects[0].effect == SkillEngine.EFFECT_SHIELD
		and readiness.else_effects[0].effect == SkillEngine.EFFECT_DRAW_CARDS,
		"the knight must teach a hand-size comparison with two branches")
	var sparks: Dictionary = cards[6].skills[0].effects[0]
	_assert(sparks.effect == SkillEngine.EFFECT_REPEAT and sparks.repeat_count == 2
		and sparks.then_effects[0].effect == SkillEngine.EFFECT_DAMAGE,
		"the beginner spell must teach a repeated effect")
	_test_beginner_effects(cards)
	_assert(_starter_skill_matches(cards, "医护兵", SkillEngine.TRIGGER_ON_ACTIVATE,
		SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_HEAL, 2, "", 0, SkillEngine.TARGET_SIDE_ALLY),
		"medic must teach targeted allied healing")
	var second := CardDatabase.beginner_deck()
	cards[0].hp = 0
	_assert(second[0].hp > 0, "starter factory must return independent card instances")
	var fresh := MemoryPlayerData.new()
	fresh._seed_starter_library()
	_assert(fresh.deck_library.size() == 1 and fresh.card_library.size() == 16,
		"first launch must seed one complete beginner deck")
	var existing := CardData.new("用户自定义卡", 9, 6, 7)
	fresh.deck_library = [{"id": "custom-deck", "name": "保留", "cards": [existing]}]
	fresh.current_deck_id = "custom-deck"
	fresh._normalize_library()
	_assert(fresh.deck_library.size() == 1 and fresh.card_library.size() == 1
		and fresh.card_library[0].card_name == "用户自定义卡", "existing decks must not be replaced during normalization")
	var sync_result := fresh.sync_beginner_default_deck()
	_assert(bool(sync_result.get("ok", false)) and bool(sync_result.get("created", false)),
		"beginner deck sync must create a missing named deck")
	_assert(fresh.deck_library.size() == 2 and fresh.get_cards_for_deck("custom-deck").size() == 1,
		"beginner deck sync must preserve every user deck")
	var synced_id := str(sync_result.get("deck_id", ""))
	_assert(fresh.get_cards_for_deck(synced_id).size() == 16 and fresh.current_deck_id == "custom-deck",
		"synced beginner deck must be complete without changing the selected deck")
	var second_sync := fresh.sync_beginner_default_deck()
	_assert(bool(second_sync.get("ok", false)) and not bool(second_sync.get("created", true))
		and str(second_sync.get("deck_id", "")) == synced_id and fresh.deck_library.size() == 2,
		"repeated beginner deck sync must replace in place instead of duplicating it")
	fresh.free()


func _test_beginner_effects(cards: Array) -> void:
	var game := Game.new()
	game.initialize_fields({})
	game.turn_number = 2
	var knight: CardData = cards[3].duplicate_card()
	game.player_hand = [knight, cards[0].duplicate_card(), cards[1].duplicate_card(), cards[2].duplicate_card()]
	_assert(game.summon_card(knight, 0), "the starter knight must be deployable")
	game.trigger_summon_skills(0, -1, 0)
	_assert(knight.temp_hp == 2 and game.player_hand.size() == 3,
		"deploying the starter knight with three cards left must grant two shield")

	game.player_field.current_mana = 4
	var reserve: CardData = cards[3].duplicate_card()
	game.player_hand = [reserve]
	game.shared_deck = [cards[0].duplicate_card()]
	_assert(game.summon_card(reserve, 1), "the second knight must be deployable")
	game.trigger_summon_skills(1, -1, 0)
	_assert(reserve.temp_hp == 0 and game.player_hand.size() == 1 and game.shared_deck.is_empty(),
		"deploying the starter knight with an empty hand must draw a card")

	game.player_field.current_mana = 4
	game.player_hand = [cards[6].duplicate_card()]
	var enemy := CardData.new("测试目标", 2, 5, 1)
	game.player2_field.slots[0] = enemy
	_assert(game.cast_spell(0, 0, 0, 2) and enemy.hp == 3,
		"the starter spell must hit its chosen enemy twice for one damage each")


func _starter_skill_matches(cards: Array, card_name: String, trigger: String, target: String,
		effect: String, value: int, buff_id: String = "", duration: int = 0,
		target_side: String = "") -> bool:
	for card: CardData in cards:
		if card.card_name != card_name or card.skills.size() != 1:
			continue
		var skill: Dictionary = card.skills[0]
		if str(skill.get("trigger", "")) != trigger or skill.get("effects", []).size() != 1:
			continue
		var item: Dictionary = skill.effects[0]
		return str(item.get("target", "")) == target \
			and str(item.get("effect", "")) == effect \
			and int(item.get("value", 0)) == value \
			and str(item.get("buff_id", "")) == buff_id \
			and int(item.get("duration", 0)) == duration \
			and (target_side == "" or str(item.get("target_side", "")) == target_side)
	return false


func _assert(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
