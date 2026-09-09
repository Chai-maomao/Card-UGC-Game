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
		for draw_count in [0, 2, 5, 6]:
			PlayerData.battle_config["draw_per_turn"] = draw_count
			for seed_value in range(40):
				var game := Game.new()
				game.quiet = true
				game.init_game(Callable(), seed_value)
				opening_cases += 1
				_assert(game.player_hand[0].instance_id == specimen.instance_id,
					"tested card must always be first in player one's hand")
				_assert(game.player_hand[0].card_type == card_type, "all card types must be preserved")
				_assert(game.player_hand.size() == clampi(draw_count + 1, 3, 6), "opening must reserve helpers without exceeding six")
				_assert(game.player2_hand.size() == clampi(draw_count + 1, 3, 6), "both sides must receive the test instruments")
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
	await battle._on_end_turn_pressed()
	for _frame in range(4):
		await get_tree().process_frame
	_assert(battle.game.current_player == 2 and battle._view_player() == 2 and battle.is_my_turn(),
		"end turn must switch the controllable hand to player two")
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
	_assert(_starter_skill_matches(cards, "弓箭手", SkillEngine.TRIGGER_ON_ACTIVATE,
		SkillEngine.TARGET_SIDES, SkillEngine.EFFECT_DAMAGE, 1, "", 0, SkillEngine.TARGET_SIDE_ENEMY),
		"archer skill must be a meaningful adjacent-area alternative to its 2 damage attack")
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
