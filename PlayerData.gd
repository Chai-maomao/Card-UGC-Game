extends Node

# ============================================
# Player data autoload — local save & draft management
# ============================================

const SAVE_FILE_NAME := "card_library.json"
const SAVE_TEMP_SUFFIX := ".tmp"
const SAVE_BACKUP_SUFFIX := ".bak"
const NET_ARTS_DIR := "user://net_arts"
const IMPORTED_ARTS_DIR := "user://arts"
const MAX_ART_BYTES := 2 * 1024 * 1024  # 2 MB cap per card art sent over the network
const SHARE_VERSION := 2
const SpellRules = preload("res://SpellRules.gd")
const ParasiteRules = preload("res://ParasiteRules.gd")
const UgcSafetyPolicy = preload("res://UgcSafety.gd")
const Schema = preload("res://DataSchema.gd")
const LibraryRepo = preload("res://CardLibraryRepository.gd")
const EditorRepo = preload("res://EditorDataRepository.gd")
const HistoryRepo = preload("res://MatchHistoryRepository.gd")
const BattlePrep = preload("res://BattlePreparationState.gd")
const SAFE_ART_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const DRAFT_RECOVERY_PATH := "user://card_draft_recovery.json"
const SKILL_TEMPLATES_PATH := "user://skill_templates.json"
const MATCH_HISTORY_PATH := "user://match_history.json"
const MAX_MATCH_HISTORY := 100
const DRAFT_RECOVERY_VERSION := 1

var card_library: Array = []
var deck_library: Array = []
var current_deck_id: String = ""
var save_path: String = ""
var editing_index: int = -1
var editing_deck_id: String = ""
var editing_instance_id: String = ""
var card_draft: Dictionary = {}
var editing_skill_index: int = 0
var card_editor_return_scene: String = "res://MainMenu.tscn"
var return_to_waiting_room: bool = false
var continue_editing_flag: bool = false  # "继续编辑"跳转标记
var return_to_deck_id: String = ""
var battle_deck: Array = []
var opponent_battle_deck: Array = []
var battle_mode: String = "hotseat"
var practice_ai_difficulty: String = "normal"
var battle_select_mode: String = "practice"
var battle_select_next_scene: String = "res://Main.tscn"
var battle_select_step: int = 1
var pending_hotseat_p1_deck: Array = []
var recovered_card_draft: Dictionary = {}
var custom_skill_templates: Array = []
var match_history: Array = []
var card_playtest_context: Dictionary = {}
var skill_tutorial_active: bool = false
var tutorial_editor_stage: String = ""
var tutorial_created_card: CardData = null
var _skill_tutorial_editor_backup: Dictionary = {}
var _draft_save_pending: bool = false
var _draft_save_at: float = 0.0

# ============================================
# Battle configuration (战斗前自定义参数)
# ============================================
const DEFAULT_BATTLE_CONFIG := {
	"mana_per_turn": 2,       # 每回合回费数量
	"draw_per_turn": 2,        # 每回合抽牌数量
	"starting_hp": 30,         # 玩家初始血量
	"second_extra_cards": 0,   # 后手第一回合补偿卡牌数
	"second_extra_mana": 2,    # 后手第一回合补偿圣水（2000局校准：先手胜率49.95%）
	"death_compensation": true,        # 战败补偿：卡牌被击杀时抽1张牌
	"face_damage_compensation": false,  # 本体伤害补偿：每张攻击牌给1点临时圣水
}
var battle_config: Dictionary = DEFAULT_BATTLE_CONFIG.duplicate(true)


func _apply_battle_preparation(state: Dictionary) -> void:
	battle_mode = str(state.get("mode", "hotseat"))
	practice_ai_difficulty = str(state.get("difficulty", "normal"))
	battle_deck = (state.get("player_deck", []) as Array).duplicate()
	opponent_battle_deck = (state.get("opponent_deck", []) as Array).duplicate()
	pending_hotseat_p1_deck = (state.get("pending_p1", []) as Array).duplicate()
	battle_select_mode = str(state.get("select_mode", "practice"))
	battle_select_next_scene = str(state.get("next_scene", "res://Main.tscn"))
	battle_select_step = int(state.get("select_step", 1))
	return_to_waiting_room = bool(state.get("return_to_waiting_room", false))


func configure_practice_battle(player_cards: Array, opponent_cards: Array, difficulty: String = "normal", preserve_playtest: bool = false) -> void:
	_apply_battle_preparation(BattlePrep.practice(player_cards, opponent_cards, difficulty))
	if not preserve_playtest:
		card_playtest_context = {}


func begin_hotseat_battle_selection(player_one_cards: Array = []) -> void:
	_apply_battle_preparation(BattlePrep.hotseat_pending(player_one_cards))
	card_playtest_context = {}


func prepare_hotseat_selection() -> void:
	begin_hotseat_battle_selection()
	battle_select_mode = "hotseat_p1"
	battle_select_step = 1


func configure_hotseat_battle(player_one_cards: Array, player_two_cards: Array) -> void:
	_apply_battle_preparation(BattlePrep.hotseat(player_one_cards, player_two_cards))
	card_playtest_context = {}


func configure_online_battle(player_cards: Array, next_scene: String = "res://Lobby.tscn") -> void:
	_apply_battle_preparation(BattlePrep.online(player_cards, next_scene))
	card_playtest_context = {}


func prepare_practice_selection(difficulty: String) -> void:
	_apply_battle_preparation(BattlePrep.practice([], [], difficulty))


func prepare_tutorial_battle(card: CardData = null) -> void:
	if card != null:
		tutorial_created_card = card.duplicate_card()
	var player_cards: Array = []
	for starter in CardDatabase.player_starters():
		player_cards.append(starter.duplicate_card())
	if tutorial_created_card != null:
		player_cards.append(tutorial_created_card.duplicate_card())
	var opponent_cards: Array = []
	for starter in CardDatabase.player_starters():
		opponent_cards.append(starter.duplicate_card())
	_apply_battle_preparation(BattlePrep.tutorial(player_cards, opponent_cards))
	card_playtest_context = {}


func begin_card_tutorial() -> void:
	# The full tutorial edits an in-memory card only. The player's current draft,
	# recovery debounce and return context are restored before battle begins.
	if skill_tutorial_active:
		cancel_skill_tutorial()
	_skill_tutorial_editor_backup = {
		"card_draft": card_draft.duplicate(true),
		"editing_index": editing_index,
		"editing_deck_id": editing_deck_id,
		"editing_instance_id": editing_instance_id,
		"editing_skill_index": editing_skill_index,
		"card_editor_return_scene": card_editor_return_scene,
		"return_to_deck_id": return_to_deck_id,
		"draft_save_pending": _draft_save_pending,
		"draft_save_at": _draft_save_at,
	}
	_draft_save_pending = false
	card_draft = {
		"card_type": "minion",
		"name": "",
		"cost": 1,
		"hp": 5,
		"atk": 2,
		"gender": "nonhuman",
		"art_path": "",
		"skill1": {},
		"skill2": {},
		"skill3": {},
	}
	editing_index = -1
	editing_deck_id = ""
	editing_instance_id = ""
	editing_skill_index = 0
	card_editor_return_scene = "res://MainMenu.tscn"
	return_to_deck_id = ""
	skill_tutorial_active = true
	tutorial_editor_stage = "card_basics"
	tutorial_created_card = null


func begin_skill_tutorial() -> void:
	# Compatibility entry used by focused editor tests and older callers.
	begin_card_tutorial()
	tutorial_editor_stage = "skill"


func finish_skill_tutorial_editor(skill: Dictionary = {}) -> void:
	if not skill.is_empty():
		card_draft["skill1"] = skill.duplicate(true)
	tutorial_editor_stage = "card_review"


func finish_card_tutorial(card: CardData) -> void:
	tutorial_created_card = card.duplicate_card()
	_restore_skill_tutorial_editor_state()
	prepare_tutorial_battle(tutorial_created_card)


func cancel_skill_tutorial() -> void:
	tutorial_created_card = null
	_restore_skill_tutorial_editor_state()


func _restore_skill_tutorial_editor_state() -> void:
	if not skill_tutorial_active:
		return
	card_draft = (_skill_tutorial_editor_backup.get("card_draft", {}) as Dictionary).duplicate(true)
	editing_index = int(_skill_tutorial_editor_backup.get("editing_index", -1))
	editing_deck_id = str(_skill_tutorial_editor_backup.get("editing_deck_id", ""))
	editing_instance_id = str(_skill_tutorial_editor_backup.get("editing_instance_id", ""))
	editing_skill_index = int(_skill_tutorial_editor_backup.get("editing_skill_index", 0))
	card_editor_return_scene = str(_skill_tutorial_editor_backup.get("card_editor_return_scene", "res://MainMenu.tscn"))
	return_to_deck_id = str(_skill_tutorial_editor_backup.get("return_to_deck_id", ""))
	_draft_save_pending = bool(_skill_tutorial_editor_backup.get("draft_save_pending", false))
	_draft_save_at = float(_skill_tutorial_editor_backup.get("draft_save_at", 0.0))
	_skill_tutorial_editor_backup = {}
	skill_tutorial_active = false
	tutorial_editor_stage = ""


func prepare_online_selection(next_scene: String) -> void:
	_apply_battle_preparation(BattlePrep.online([], next_scene))


func set_online_opponent_deck(cards: Array) -> void:
	opponent_battle_deck = cards.duplicate()


func clear_battle_preparation() -> void:
	_apply_battle_preparation(BattlePrep.empty())
	card_playtest_context = {}
	tutorial_created_card = null


func battle_preparation_snapshot() -> Dictionary:
	return {
		"mode": battle_mode, "difficulty": practice_ai_difficulty,
		"player_deck": battle_deck.duplicate(), "opponent_deck": opponent_battle_deck.duplicate(),
		"pending_p1": pending_hotseat_p1_deck.duplicate(), "select_mode": battle_select_mode,
		"next_scene": battle_select_next_scene, "select_step": battle_select_step,
		"return_to_waiting_room": return_to_waiting_room,
	}


func _ready():
	save_path = "user://" + SAVE_FILE_NAME
	print("Save path: %s" % ProjectSettings.globalize_path(save_path))
	load_library()
	_load_card_draft_recovery()
	_load_skill_templates()
	_load_match_history()
	clear_net_arts()


func _process(_delta: float) -> void:
	if _draft_save_pending and Time.get_ticks_msec() / 1000.0 >= _draft_save_at:
		_draft_save_pending = false
		save_card_draft_recovery()


# ============================================
# Serialization
# ============================================

static func make_id(prefix: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%s_%d_%08x" % [prefix, Time.get_unix_time_from_system(), rng.randi()]


static func ensure_card_id(card: CardData) -> void:
	if card.card_id == "":
		card.card_id = make_id("card")


static func ensure_instance_id(card: CardData) -> void:
	if card.instance_id == "":
		card.instance_id = make_id("inst")


static func prepare_deck_card(card: CardData, keep_instance: bool = false) -> CardData:
	var copy := card.duplicate_card()
	ensure_card_id(copy)
	if not keep_instance:
		copy.instance_id = ""
	ensure_instance_id(copy)
	return copy


static func serialize_card(card: CardData) -> Dictionary:
	ensure_card_id(card)
	ensure_instance_id(card)
	var skills_data: Array = []
	for skill in card.skills:
		skills_data.append(skill.duplicate(true))
	var parasites_data: Array = []
	for parasite in card.parasite_cards:
		if parasite is CardData:
			parasites_data.append(serialize_card(parasite))

	return {
		"card_id": card.card_id,
		"instance_id": card.instance_id,
		"name": card.card_name,
		"cost": card.cost,
		"max_hp": card.max_hp,
		"hp": card.hp,
		"atk": card.atk,
		"base_cost": card.base_cost,
		"base_max_hp": card.base_max_hp,
		"base_atk": card.base_atk,
		"gender": card.gender,
		"art_path": card.art_path,
		"card_type": card.card_type,
		"skills": skills_data,
		"has_acted": card.has_acted,
		"has_attacked": card.has_attacked,
		"summoned_this_turn": card.summoned_this_turn,
		"skills_used": card.skills_used.duplicate(),
		"skills_used_count": card.skills_used_count.duplicate(),
		"charmed_slot": card.charmed_slot,
		"original_cost": card.original_cost,
		"temp_hp": card.temp_hp,
		"parasite_cards": parasites_data,
		"status_effects": card.status_effects.duplicate(true),
		"attack_ignores_silence": card.attack_ignores_silence,
		"field_atk_bonus": card.field_atk_bonus,
		"immune_lethal": card.immune_lethal,
		"zero_cost_until_deploy": card.zero_cost_until_deploy,
	}


static func deserialize_card(data: Dictionary) -> CardData:
	var name: String = data.get("name", "Unknown")
	var cost: int = data.get("cost", 0)
	var max_hp: int = data.get("max_hp", 1)
	var atk: int = data.get("atk", 0)
	var skills: Array = data.get("skills", [])

	var card := CardData.new(name, cost, max_hp, atk, skills)
	card.card_id = data.get("card_id", data.get("share_id", ""))
	card.instance_id = data.get("instance_id", "")
	card.base_cost = int(data.get("base_cost", cost))
	card.base_max_hp = int(data.get("base_max_hp", max_hp))
	card.base_atk = int(data.get("base_atk", atk))
	card.hp = int(data.get("hp", max_hp))
	card.art_path = data.get("art_path", "")
	card.gender = data.get("gender", "female")
	card.card_type = data.get("card_type", "minion")
	card.has_acted = bool(data.get("has_acted", false))
	card.has_attacked = bool(data.get("has_attacked", false))
	card.summoned_this_turn = bool(data.get("summoned_this_turn", false))
	card.skills_used = data.get("skills_used", []).duplicate()
	card.skills_used_count = data.get("skills_used_count", {})
	card.charmed_slot = int(data.get("charmed_slot", -1))
	card.original_cost = int(data.get("original_cost", -1))
	card.temp_hp = int(data.get("temp_hp", 0))
	card.parasite_cards.clear()
	for parasite_data in data.get("parasite_cards", []):
		if typeof(parasite_data) == TYPE_DICTIONARY:
			card.parasite_cards.append(deserialize_card(parasite_data))
	card.status_effects = data.get("status_effects", []).duplicate(true)
	card.attack_ignores_silence = bool(data.get("attack_ignores_silence", false))
	card.field_atk_bonus = int(data.get("field_atk_bonus", 0))
	card.immune_lethal = bool(data.get("immune_lethal", false))
	card.zero_cost_until_deploy = bool(data.get("zero_cost_until_deploy", false))
	ensure_card_id(card)
	ensure_instance_id(card)
	return card


static func deserialize_battle_deck_payload(value: Variant) -> Dictionary:
	if not (value is Array):
		return {"ok": false, "cards": [], "errors": [{"code": "deck_type", "path": [], "details": {}}]}
	var deck_payload := {"id": "network", "name": "Network", "cards": value}
	var errors := Schema.validate(Schema.KIND_DECK, deck_payload)
	if not errors.is_empty():
		return {"ok": false, "cards": [], "errors": errors}
	var cards: Array = []
	for data in value:
		cards.append(deserialize_card(data))
	return {"ok": true, "cards": cards, "errors": []}


static func serialize_deck(deck: Dictionary) -> Dictionary:
	var cards_data: Array = []
	for card in deck.get("cards", []):
		if card is CardData:
			cards_data.append(serialize_card(card))
		elif typeof(card) == TYPE_DICTIONARY:
			cards_data.append(card.duplicate(true))
	return {
		"id": deck.get("id", make_id("deck")),
		"name": deck.get("name", "Deck"),
		"cards": cards_data,
	}


func serialize_library() -> String:
	_normalize_library()
	var decks_array: Array = []
	for deck in deck_library:
		decks_array.append(serialize_deck(deck))
	var root := {"decks": decks_array, "version": 3}
	return JSON.stringify(root, "\t")


func deserialize_library(json_string: String) -> Array:
	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		print("JSON parse error: %s" % json.get_error_message())
		deck_library = []
		card_library = []
		return []
	var root: Dictionary = json.get_data()
	if root.is_empty():
		deck_library = []
		card_library = []
		return []
	var old_cards_by_id := {}
	for card_data in root.get("cards", []):
		var old_card := deserialize_card(card_data)
		old_cards_by_id[old_card.card_id] = old_card
	deck_library = []
	var decks_array: Array = root.get("decks", [])
	for deck_data in decks_array:
		var deck_cards: Array = []
		if deck_data.has("cards"):
			for card_data in deck_data.get("cards", []):
				deck_cards.append(prepare_deck_card(deserialize_card(card_data), true))
		else:
			for card_id in deck_data.get("card_ids", []):
				if old_cards_by_id.has(card_id):
					deck_cards.append(prepare_deck_card(old_cards_by_id[card_id], false))
		deck_library.append({
			"id": deck_data.get("id", make_id("deck")),
			"name": deck_data.get("name", Locale.t("deck.default_name") if Engine.has_singleton("Locale") else "默认卡组"),
			"cards": deck_cards,
		})
	if deck_library.is_empty() and not old_cards_by_id.is_empty():
		var migrated_cards: Array = []
		for card in old_cards_by_id.values():
			migrated_cards.append(prepare_deck_card(card, false))
		deck_library.append({"id": make_id("deck"), "name": Locale.t("deck.default_name"), "cards": migrated_cards})
	_normalize_library()
	return card_library


func _normalize_library() -> void:
	var original_cards: Array = card_library.duplicate()
	var normalized_decks: Array = []
	card_library.clear()
	for deck in deck_library:
		var cards: Array = []
		if deck.has("cards"):
			for card_entry in deck.get("cards", []):
				var card: CardData = card_entry if card_entry is CardData else deserialize_card(card_entry)
				cards.append(prepare_deck_card(card, true))
		elif deck.has("card_ids"):
			for card_id in deck.get("card_ids", []):
				var old_card := _find_card_in_array(original_cards, card_id)
				if old_card != null:
					cards.append(prepare_deck_card(old_card, false))
		normalized_decks.append({
			"id": deck.get("id", make_id("deck")),
			"name": deck.get("name", Locale.t("deck.default_name") if Engine.has_singleton("Locale") else "默认卡组"),
			"cards": cards,
		})
		for card in cards:
			card_library.append(card)
	deck_library = normalized_decks
	if deck_library.is_empty() and not original_cards.is_empty():
		var cards: Array = []
		for card in original_cards:
			cards.append(prepare_deck_card(card, false))
		deck_library.append({"id": make_id("deck"), "name": Locale.t("deck.default_name"), "cards": cards})
		rebuild_card_library_cache()
	if current_deck_id == "" and not deck_library.is_empty():
		current_deck_id = deck_library[0].get("id", "")
	elif not get_deck(current_deck_id).is_empty():
		return
	elif not deck_library.is_empty():
		current_deck_id = deck_library[0].get("id", "")


func card_content_fingerprint(card: CardData) -> String:
	var data := serialize_card(card)
	data.erase("card_id")
	data.erase("instance_id")
	data.erase("art_path")
	data.erase("has_acted")
	data.erase("has_attacked")
	data.erase("summoned_this_turn")
	data.erase("skills_used")
	data.erase("charmed_slot")
	data.erase("original_cost")
	data.erase("temp_hp")
	data.erase("parasite_cards")
	data.erase("status_effects")
	return JSON.stringify(data)


func _find_card_in_array(cards: Array, card_id: String) -> CardData:
	for card in cards:
		if card.card_id == card_id:
			return card
	return null


func find_card_by_id(card_id: String) -> CardData:
	return LibraryRepo.find_card(deck_library, card_id)


func find_card_index_by_id(card_id: String) -> int:
	for i in range(card_library.size()):
		if card_library[i].card_id == card_id:
			return i
	return -1


func get_deck(deck_id: String) -> Dictionary:
	return LibraryRepo.find_deck(deck_library, deck_id)


func get_current_deck() -> Dictionary:
	var deck := get_deck(current_deck_id)
	if deck.is_empty() and not deck_library.is_empty():
		current_deck_id = deck_library[0].get("id", "")
		deck = deck_library[0]
	return deck


func get_cards_for_deck(deck_id: String) -> Array:
	var deck := get_deck(deck_id)
	return deck.get("cards", []) if not deck.is_empty() else []


func find_deck_card(deck_id: String, instance_id: String) -> CardData:
	for card in get_cards_for_deck(deck_id):
		if card.instance_id == instance_id:
			return card
	return null


func find_deck_card_index(deck_id: String, instance_id: String) -> int:
	return LibraryRepo.find_instance_index(get_deck(deck_id), instance_id)


func create_deck(deck_name: String, cards: Array = []) -> Dictionary:
	var deck_cards: Array = []
	for card in cards:
		deck_cards.append(prepare_deck_card(card, false))
	var deck := {"id": make_id("deck"), "name": deck_name, "cards": deck_cards}
	deck_library.append(deck)
	current_deck_id = deck["id"]
	save_library()
	return deck


func find_deck_conflict(deck_id: String, card: CardData, ignore_instance_id: String = "") -> Dictionary:
	for local in get_cards_for_deck(deck_id):
		if local.instance_id == ignore_instance_id:
			continue
		if local.card_name == card.card_name:
			if card_content_fingerprint(local) == card_content_fingerprint(card):
				return {"kind": "same", "card": local}
			return {"kind": "conflict", "card": local}
	return {"kind": "none"}


func add_card_copy_to_deck(deck_id: String, card: CardData, check_duplicate: bool = true) -> Dictionary:
	var conflict := find_deck_conflict(deck_id, card) if check_duplicate else {"kind": "none"}
	if conflict.get("kind", "") != "none":
		return conflict
	var deck := get_deck(deck_id)
	if deck.is_empty():
		return {"kind": "missing_deck"}
	var copy := prepare_deck_card(card, false)
	var cards: Array = deck.get("cards", [])
	cards.append(copy)
	deck["cards"] = cards
	card_library.append(copy)
	return {"kind": "added", "card": copy}


func update_deck_card(deck_id: String, instance_id: String, card: CardData) -> bool:
	var index := find_deck_card_index(deck_id, instance_id)
	if index < 0:
		return false
	var cards := get_cards_for_deck(deck_id)
	var old_card: CardData = cards[index]
	if card.card_id == "":
		card.card_id = old_card.card_id
	card.instance_id = old_card.instance_id
	cards[index] = prepare_deck_card(card, true)
	rebuild_card_library_cache()
	save_library()
	return true


func remove_deck_card(deck_id: String, instance_id: String) -> bool:
	var index := find_deck_card_index(deck_id, instance_id)
	if index < 0:
		return false
	var cards := get_cards_for_deck(deck_id)
	cards.remove_at(index)
	rebuild_card_library_cache()
	save_library()
	return true


func copy_cards_between_decks(source_deck_id: String, instance_ids: Array, target_deck_ids: Array) -> Dictionary:
	var added: int = 0
	var skipped: int = 0
	var conflicts: Array = []
	for target_deck_id in target_deck_ids:
		for instance_id in instance_ids:
			var card := find_deck_card(source_deck_id, instance_id)
			if card == null:
				continue
			var result := add_card_copy_to_deck(target_deck_id, card, true)
			match result.get("kind", ""):
				"added": added += 1
				"same": skipped += 1
				"conflict": conflicts.append({"target_deck_id": target_deck_id, "local": result.get("card"), "incoming": card.duplicate_card()})
	rebuild_card_library_cache()
	save_library()
	return {"added": added, "skipped": skipped, "conflicts": conflicts}


func rebuild_card_library_cache() -> void:
	card_library = LibraryRepo.flatten(deck_library)


func add_card_to_deck(deck_id: String, card_id: String) -> void:
	var card := find_card_by_id(card_id)
	if card != null:
		add_card_copy_to_deck(deck_id, card, true)


func serialize_cards_for_share(cards: Array) -> String:
	var cards_data: Array = []
	for card in cards:
		cards_data.append(_serialize_card_for_share(card))
	return JSON.stringify({"version": SHARE_VERSION, "type": "cards", "cards": cards_data}, "\t")


func serialize_deck_for_share(deck: Dictionary) -> String:
	var cards: Array = []
	for card in deck.get("cards", []):
		cards.append(_serialize_card_for_share(card))
	return JSON.stringify({"version": SHARE_VERSION, "type": "deck", "deck": serialize_deck(deck), "cards": cards}, "\t")


func _serialize_card_for_share(card: CardData) -> Dictionary:
	var data := serialize_card(card)
	data["share_id"] = card.card_id
	var art_bytes := read_art_bytes(card.art_path)
	if not art_bytes.is_empty():
		var ext := _extension_from_path(card.art_path)
		if SAFE_ART_EXTENSIONS.has(ext):
			data["art_ext"] = ext
			data["art_base64"] = Marshalls.raw_to_base64(art_bytes)
	return data


func parse_share_package(json_string: String) -> Dictionary:
	var result := Schema.parse_and_migrate(Schema.KIND_SHARE_PACKAGE, json_string)
	if not bool(result.get("ok", false)):
		var issues: Array = result.get("errors", [])
		return {"ok": false, "error": Locale.t("share.error_ugc_unsafe", [UgcSafetyPolicy.first_error_text(issues)])}
	return {"ok": true, "package": result.get("data", {})}


func _validate_share_package(package: Dictionary) -> Array:
	var result := Schema.migrate_and_validate(Schema.KIND_SHARE_PACKAGE, package)
	return result.get("errors", [])


func prepare_import_cards(package: Dictionary, target_deck_id: String = "") -> Dictionary:
	var package_issues := _validate_share_package(package)
	if not package_issues.is_empty():
		return {"incoming": [], "skipped": [], "conflicts": [], "id_map": {}, "invalid": true, "errors": package_issues}
	var incoming: Array = []
	var skipped: Array = []
	var conflicts: Array = []
	var id_map := {}
	var deck_id := target_deck_id if target_deck_id != "" else current_deck_id
	for card_data in package.get("cards", []):
		var share_id: String = card_data.get("share_id", card_data.get("card_id", ""))
		var card := deserialize_card(card_data)
		_restore_shared_art(card, card_data)
		var match := find_deck_conflict(deck_id, card)
		if match.get("kind", "") == "same":
			skipped.append(card)
			id_map[share_id] = match["card"].instance_id
		elif match.get("kind", "") == "conflict":
			conflicts.append({"local": match["card"], "incoming": card, "share_id": share_id})
		else:
			incoming.append({"card": card, "share_id": share_id})
	return {"incoming": incoming, "skipped": skipped, "conflicts": conflicts, "id_map": id_map}


func apply_prepared_import(prepared: Dictionary, package: Dictionary, replace_library: bool = false, append_to_current_deck: bool = false) -> Dictionary:
	var deck := get_current_deck()
	if deck.is_empty():
		deck = create_deck(Locale.t("deck.default_name"))
	var added_count: int = 0
	for item in prepared.get("incoming", []):
		var card: CardData = item["card"]
		var result := add_card_copy_to_deck(deck.get("id", ""), card, false)
		if result.get("kind", "") == "added":
			added_count += 1
			prepared["id_map"][item["share_id"]] = result["card"].instance_id
	save_library()
	return {"added": added_count, "skipped": prepared.get("skipped", []).size()}


func import_package_as_new_deck(package: Dictionary, deck_name: String) -> Dictionary:
	var package_issues := _validate_share_package(package)
	if not package_issues.is_empty():
		return {"added": 0, "deck_name": "", "invalid": true, "errors": package_issues}
	var deck_cards: Array = []
	var id_map := {}
	var added_count: int = 0
	for card_data in package.get("cards", []):
		var share_id: String = card_data.get("share_id", card_data.get("card_id", ""))
		var card := deserialize_card(card_data)
		_restore_shared_art(card, card_data)
		var copy := prepare_deck_card(card, false)
		deck_cards.append(copy)
		if share_id != "":
			id_map[share_id] = copy.instance_id
		added_count += 1
	var final_cards := deck_cards
	if package.get("type", "") == "deck":
		var deck_data: Dictionary = package.get("deck", {})
		var ordered_cards: Array = []
		for share_card_id in deck_data.get("card_ids", []):
			if id_map.has(share_card_id):
				for card in deck_cards:
					if card.instance_id == id_map[share_card_id]:
						ordered_cards.append(card)
						break
		if not ordered_cards.is_empty():
			final_cards = ordered_cards
	var final_name := deck_name.strip_edges()
	if final_name == "":
		final_name = Locale.t("share.import_deck_name")
	var deck := {"id": make_id("deck"), "name": final_name, "cards": final_cards}
	deck_library.append(deck)
	current_deck_id = deck.get("id", "")
	rebuild_card_library_cache()
	save_library()
	return {"added": added_count, "deck_name": final_name}


func _find_import_match(card: CardData) -> Dictionary:
	return find_deck_conflict(current_deck_id, card)


func _restore_shared_art(card: CardData, card_data: Dictionary) -> void:
	var encoded: String = card_data.get("art_base64", "")
	if encoded == "":
		return
	var ext: String = card_data.get("art_ext", "png").to_lower()
	if not SAFE_ART_EXTENSIONS.has(ext):
		return
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.is_empty() or bytes.size() > MAX_ART_BYTES:
		return
	card.art_path = save_imported_art(bytes, ext)


func save_imported_art(bytes: PackedByteArray, ext: String) -> String:
	if bytes.is_empty() or bytes.size() > MAX_ART_BYTES:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(IMPORTED_ARTS_DIR))
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_MD5)
	hash_ctx.update(bytes)
	var hash_str := hash_ctx.finish().hex_encode()
	var safe_ext := ext.to_lower()
	if not SAFE_ART_EXTENSIONS.has(safe_ext):
		safe_ext = "png"
	var rel_path := "%s/imported_%s.%s" % [IMPORTED_ARTS_DIR, hash_str, safe_ext]
	var abs_path := ProjectSettings.globalize_path(rel_path)
	if FileAccess.file_exists(abs_path):
		return rel_path
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return rel_path


func _extension_from_path(path: String) -> String:
	var ext := path.get_extension().to_lower()
	return ext if ext != "" else "png"


# ============================================
# File I/O
# ============================================

func _save_temp_path() -> String:
	return save_path + SAVE_TEMP_SUFFIX


func _save_backup_path() -> String:
	return save_path + SAVE_BACKUP_SUFFIX


func _is_valid_library_json(json_string: String) -> bool:
	return bool(Schema.parse_and_migrate(Schema.KIND_LIBRARY, json_string).get("ok", false))


func _read_library_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var contents := file.get_as_text()
	file.close()
	return contents


func _load_library_file(path: String) -> bool:
	var json_string := _read_library_file(path)
	if json_string == "":
		return false
	var result := Schema.parse_and_migrate(Schema.KIND_LIBRARY, json_string)
	if not bool(result.get("ok", false)):
		return false
	card_library = deserialize_library(JSON.stringify(result.get("data", {})))
	return true


func _remove_file_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _read_json_dictionary(path: String, schema_kind: String = "") -> Dictionary:
	var candidates := [path, path + ".bak"] if schema_kind != "" else [path]
	for index in range(candidates.size()):
		var candidate: String = candidates[index]
		var text := _read_library_file(candidate)
		if text.is_empty():
			continue
		if schema_kind == "":
			var parsed = JSON.parse_string(text)
			return parsed if parsed is Dictionary else {}
		var result := Schema.parse_and_migrate(schema_kind, text)
		if bool(result.get("ok", false)):
			if index == 1:
				_remove_file_if_present(path)
				DirAccess.copy_absolute(ProjectSettings.globalize_path(candidate), ProjectSettings.globalize_path(path))
			return result.get("data", {})
	return {}


func _write_json_atomic(path: String, payload: Dictionary, schema_kind: String = "") -> bool:
	if schema_kind != "" and not bool(Schema.migrate_and_validate(schema_kind, payload).get("ok", false)):
		return false
	var encoded := JSON.stringify(payload)
	if encoded.is_empty() or not (JSON.parse_string(encoded) is Dictionary):
		return false
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	_remove_file_if_present(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(encoded)
	file.flush()
	file.close()
	var disk_text := _read_library_file(temp_path)
	if schema_kind != "" and not bool(Schema.parse_and_migrate(schema_kind, disk_text).get("ok", false)):
		_remove_file_if_present(temp_path)
		return false
	if schema_kind == "" and not (JSON.parse_string(disk_text) is Dictionary):
		_remove_file_if_present(temp_path)
		return false
	_remove_file_if_present(backup_path)
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path)) != OK:
			_remove_file_if_present(temp_path)
			return false
		_remove_file_if_present(path)
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(path))
		_remove_file_if_present(temp_path)
		return false
	return true


func save_library() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var temp_path := _save_temp_path()
	var backup_path := _save_backup_path()
	_remove_file_if_present(temp_path)

	var json_string := serialize_library()
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		print("Cannot write temporary save: %s" % FileAccess.get_open_error())
		return false
	file.store_string(json_string)
	file.close()

	# Validate the bytes that actually reached disk before touching the current
	# library. This also catches interrupted or partial writes.
	var written := _read_library_file(temp_path)
	if written == "" or not _is_valid_library_json(written):
		print("Temporary library validation failed; current save kept intact")
		_remove_file_if_present(temp_path)
		return false

	var save_abs := ProjectSettings.globalize_path(save_path)
	var temp_abs := ProjectSettings.globalize_path(temp_path)
	var backup_abs := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(save_path):
		_remove_file_if_present(backup_path)
		var backup_err := DirAccess.copy_absolute(save_abs, backup_abs)
		if backup_err != OK:
			print("Cannot create library backup: %s" % backup_err)
			_remove_file_if_present(temp_path)
			return false
		_remove_file_if_present(save_path)

	var replace_err := DirAccess.rename_absolute(temp_abs, save_abs)
	if replace_err != OK:
		print("Cannot replace library save: %s" % replace_err)
		# Best-effort rollback. The backup remains available even if this copy
		# fails, so no valid save is silently discarded.
		if FileAccess.file_exists(backup_path):
			DirAccess.copy_absolute(backup_abs, save_abs)
		_remove_file_if_present(temp_path)
		return false

	print("Library saved (%d cards, %d decks)" % [card_library.size(), deck_library.size()])
	return true


func load_library() -> void:
	if _load_library_file(save_path):
		print("Library loaded (%d cards, %d decks)" % [card_library.size(), deck_library.size()])
		return

	var backup_path := _save_backup_path()
	if _load_library_file(backup_path):
		print("Primary library invalid; recovered backup (%d cards, %d decks)" % [card_library.size(), deck_library.size()])
		# Restore the known-good backup as the primary without routing it through
		# save_library(), which would otherwise back up the corrupt primary.
		_remove_file_if_present(save_path)
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(backup_path),
			ProjectSettings.globalize_path(save_path)
		)
		return

	if FileAccess.file_exists(save_path):
		var corrupt_path := "%s.corrupt.%d" % [save_path, Time.get_unix_time_from_system()]
		var quarantine_err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(corrupt_path)
		)
		print("Library was invalid; preserved as %s (result %s)" % [corrupt_path, quarantine_err])
	else:
		print("No save file found (first launch?)")
	_seed_starter_library()


# Populate a fresh collection with the default starter cards, then persist it.
func _seed_starter_library() -> void:
	card_library = CardDatabase.starter_library()
	_normalize_library()
	print("Seeded starter library (%d cards)" % card_library.size())
	save_library()


# ============================================
# Network card art (P2P only) — opponent arts stored by content hash
# ============================================

# Wipe opponent arts at launch; they only matter for the current session.
func clear_net_arts() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(NET_ARTS_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		var dir := DirAccess.open(abs_dir)
		if dir:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while fname != "":
				if not dir.current_is_dir():
					dir.remove(fname)
				fname = dir.get_next()
			dir.list_dir_end()
	DirAccess.make_dir_recursive_absolute(abs_dir)


# Read a local art file's bytes for sending. Returns empty if missing or over cap.
func read_art_bytes(art_path: String) -> PackedByteArray:
	if art_path == "":
		return PackedByteArray()
	var abs_path: String = art_path
	if abs_path.begins_with("user://") or abs_path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(abs_path)
	if not FileAccess.file_exists(abs_path):
		return PackedByteArray()
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var length := file.get_length()
	if length > MAX_ART_BYTES:
		file.close()
		print("Art over size cap, skipping transfer: %s (%d bytes)" % [art_path, length])
		return PackedByteArray()
	var bytes := file.get_buffer(length)
	file.close()
	return bytes


# Save received opponent art bytes named by content hash. Returns the user:// path,
# or "" on failure. Identical art (same bytes) maps to the same file — natural dedup.
func save_net_art(bytes: PackedByteArray, ext: String) -> String:
	if bytes.is_empty() or bytes.size() > MAX_ART_BYTES:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NET_ARTS_DIR))
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_MD5)
	hash_ctx.update(bytes)
	var digest := hash_ctx.finish()
	var hash_str := digest.hex_encode()
	var safe_ext: String = ext.strip_edges().to_lower()
	if not SAFE_ART_EXTENSIONS.has(safe_ext):
		return ""
	var rel_path: String = "%s/%s.%s" % [NET_ARTS_DIR, hash_str, safe_ext]
	var abs_path: String = ProjectSettings.globalize_path(rel_path)
	if FileAccess.file_exists(abs_path):
		return rel_path  # already have this exact art
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		print("Cannot write net art: %s" % FileAccess.get_open_error())
		return ""
	file.store_buffer(bytes)
	file.close()
	return rel_path


# ============================================
# Card library management
# ============================================

func add_card_to_library(card_data: CardData):
	if current_deck_id == "" and deck_library.is_empty():
		create_deck(Locale.t("deck.default_name") if Engine.has_singleton("Locale") else "默认卡组")
	add_card_copy_to_deck(current_deck_id, card_data, true)
	rebuild_card_library_cache()
	save_library()


func update_card_in_library(index: int, card_data: CardData) -> bool:
	if index < 0 or index >= card_library.size():
		return false
	var old_card: CardData = card_library[index]
	return update_deck_card(editing_deck_id, old_card.instance_id, card_data)


func remove_card_from_library(index: int) -> bool:
	if index < 0 or index >= card_library.size():
		return false
	var card: CardData = card_library[index]
	for deck in deck_library:
		if remove_deck_card(deck.get("id", ""), card.instance_id):
			return true
	return false


func find_save_conflict(card: CardData, editing_index_to_ignore: int = -1) -> Dictionary:
	var ignore_instance := editing_instance_id
	var deck_id := editing_deck_id if editing_deck_id != "" else current_deck_id
	var conflict := find_deck_conflict(deck_id, card, ignore_instance)
	if conflict.get("kind", "") == "none":
		return conflict
	return {"kind": conflict.get("kind", ""), "card": conflict.get("card"), "index": -1}


func get_library_count() -> int:
	return card_library.size()


func clear_library():
	card_library.clear()
	deck_library.clear()
	current_deck_id = ""
	save_library()


# ============================================
# Draft management (cross-scene)
# ============================================

func queue_card_draft_recovery() -> void:
	if skill_tutorial_active or card_draft.is_empty():
		return
	_draft_save_pending = true
	_draft_save_at = Time.get_ticks_msec() / 1000.0 + 0.45


func save_card_draft_recovery() -> bool:
	if skill_tutorial_active or card_draft.is_empty():
		return false
	var payload := {
		"version": DRAFT_RECOVERY_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"draft": card_draft.duplicate(true),
		"editing_index": editing_index,
		"editing_deck_id": editing_deck_id,
		"editing_instance_id": editing_instance_id,
		"return_scene": card_editor_return_scene,
	}
	var ok := _write_json_atomic(DRAFT_RECOVERY_PATH, payload, Schema.KIND_DRAFT_RECOVERY)
	if ok:
		recovered_card_draft = payload.duplicate(true)
	return ok


func _load_card_draft_recovery() -> void:
	var payload := _read_json_dictionary(DRAFT_RECOVERY_PATH, Schema.KIND_DRAFT_RECOVERY)
	if payload.is_empty():
		recovered_card_draft = {}
		return
	recovered_card_draft = EditorRepo.draft_from_payload(payload)


func restore_card_draft_recovery() -> bool:
	if recovered_card_draft.is_empty():
		return false
	var draft = recovered_card_draft.get("draft", {})
	if not (draft is Dictionary) or draft.is_empty():
		return false
	card_draft = (draft as Dictionary).duplicate(true)
	editing_index = int(recovered_card_draft.get("editing_index", -1))
	editing_deck_id = str(recovered_card_draft.get("editing_deck_id", ""))
	editing_instance_id = str(recovered_card_draft.get("editing_instance_id", ""))
	card_editor_return_scene = str(recovered_card_draft.get("return_scene", "res://MainMenu.tscn"))
	return true


func has_card_draft_recovery() -> bool:
	var draft = recovered_card_draft.get("draft", {})
	return draft is Dictionary and not (draft as Dictionary).is_empty()


func clear_card_draft_recovery() -> void:
	_draft_save_pending = false
	recovered_card_draft = {}
	_remove_file_if_present(DRAFT_RECOVERY_PATH)
	_remove_file_if_present(DRAFT_RECOVERY_PATH + ".tmp")
	_remove_file_if_present(DRAFT_RECOVERY_PATH + ".bak")


func save_custom_skill_template(name: String, skill: Dictionary) -> bool:
	var clean_name := name.strip_edges()
	if clean_name.is_empty() or skill.is_empty() or not UgcSafetyPolicy.validate_skill(skill).is_empty():
		return false
	custom_skill_templates = EditorRepo.upsert_template(custom_skill_templates, clean_name, skill)
	return _save_skill_templates()


func delete_custom_skill_template(index: int) -> bool:
	if index < 0 or index >= custom_skill_templates.size():
		return false
	custom_skill_templates = EditorRepo.remove_template(custom_skill_templates, index)
	return _save_skill_templates()


func _load_skill_templates() -> void:
	var payload := _read_json_dictionary(SKILL_TEMPLATES_PATH, Schema.KIND_SKILL_TEMPLATES)
	custom_skill_templates = EditorRepo.templates_from_payload(payload)


func _save_skill_templates() -> bool:
	return _write_json_atomic(SKILL_TEMPLATES_PATH, {"version": 1, "templates": custom_skill_templates}, Schema.KIND_SKILL_TEMPLATES)


func _load_match_history() -> void:
	var payload := _read_json_dictionary(MATCH_HISTORY_PATH, Schema.KIND_MATCH_HISTORY)
	match_history = HistoryRepo.from_payload(payload, MAX_MATCH_HISTORY)


func add_match_history(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	var stored := entry.duplicate(true)
	stored["id"] = str(stored.get("id", make_id("match")))
	stored["timestamp"] = int(stored.get("timestamp", Time.get_unix_time_from_system()))
	match_history = HistoryRepo.add(match_history, stored, MAX_MATCH_HISTORY)
	return _write_json_atomic(MATCH_HISTORY_PATH, HistoryRepo.payload(match_history), Schema.KIND_MATCH_HISTORY)


func clear_match_history() -> bool:
	match_history.clear()
	_remove_file_if_present(MATCH_HISTORY_PATH)
	_remove_file_if_present(MATCH_HISTORY_PATH + ".tmp")
	_remove_file_if_present(MATCH_HISTORY_PATH + ".bak")
	return true


func begin_card_playtest(saved_card: CardData) -> void:
	card_playtest_context = {
		"draft": card_draft.duplicate(true),
		"editing_index": editing_index,
		"editing_deck_id": editing_deck_id,
		"editing_instance_id": editing_instance_id,
		"return_scene": card_editor_return_scene,
		"battle_deck": battle_deck.duplicate(true),
		"opponent_deck": opponent_battle_deck.duplicate(true),
	}
	card_draft = card_to_draft(saved_card)
	save_card_draft_recovery()


func is_card_playtest_active() -> bool:
	return not card_playtest_context.is_empty()


func restore_after_card_playtest() -> bool:
	if card_playtest_context.is_empty():
		return false
	card_draft = (card_playtest_context.get("draft", {}) as Dictionary).duplicate(true)
	editing_index = int(card_playtest_context.get("editing_index", -1))
	editing_deck_id = str(card_playtest_context.get("editing_deck_id", ""))
	editing_instance_id = str(card_playtest_context.get("editing_instance_id", ""))
	card_editor_return_scene = str(card_playtest_context.get("return_scene", "res://MainMenu.tscn"))
	battle_deck = (card_playtest_context.get("battle_deck", []) as Array).duplicate()
	opponent_battle_deck = (card_playtest_context.get("opponent_deck", []) as Array).duplicate()
	card_playtest_context = {}
	queue_card_draft_recovery()
	return true

func init_card_draft():
	card_draft = {
		"name": "",
		"cost": 0,
		"hp": 1,
		"atk": 0,
		"gender": "female",
		"card_type": "minion",
		"art_path": "",
		"skill1": {},
		"skill2": {}
	}
	queue_card_draft_recovery()


# Initialise the card draft for a spell card: no body stats, and a pre-filled
# on_cast skill template so the creator sees an immediately useful starting point.
func init_spell_draft():
	card_draft = {
		"name": "",
		"cost": 2,
		"hp": 0,
		"atk": 0,
		"gender": "female",
		"art_path": "",
		"card_type": "spell",
		"skill1": {
			"skill_name": Locale.t("skill.spell_default"),
			"trigger": SkillEngine.TRIGGER_ON_CAST,
			"probability": 100,
			"effects": [{
				"target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ALL,
				"effect": SkillEngine.EFFECT_DAMAGE,
				"value": 3,
			}],
		},
		"skill2": {},
	}
	queue_card_draft_recovery()


func init_parasite_draft():
	card_draft = {
		"name": "",
		"cost": 2,
		"hp": 3,
		"atk": 0,
		"gender": "nonhuman",
		"art_path": "",
		"card_type": "parasite",
		"skill1": {
			"skill_name": Locale.t("skill.parasite_default"),
			"trigger": SkillEngine.TRIGGER_ON_ATTACK,
			"probability": 100,
			"effects": [{
				"target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ENEMY,
				"effect": SkillEngine.EFFECT_DAMAGE,
				"value": 1,
			}],
		},
		"skill2": {},
	}
	queue_card_draft_recovery()


func load_card_to_draft(card: CardData):
	card_draft = card_to_draft(card)
	if card.skills.size() >= 1:
		card_draft["skill1"] = card.skills[0].duplicate(true)
	if card.skills.size() >= 2:
		card_draft["skill2"] = card.skills[1].duplicate(true)
	if card.skills.size() >= 3:
		card_draft["skill3"] = card.skills[2].duplicate(true)
	queue_card_draft_recovery()


func card_to_draft(card: CardData) -> Dictionary:
	var draft := {
		"name": card.card_name,
		"cost": card.cost,
		"hp": card.max_hp,
		"atk": card.atk,
		"gender": card.gender,
		"card_type": card.card_type,
		"art_path": card.art_path,
		"skill1": {},
		"skill2": {},
		"skill3": {}
	}
	if card.skills.size() >= 1:
		draft["skill1"] = SpellRules.normalize_spell_skill(card, card.skills[0]) if card.is_spell() else card.skills[0].duplicate(true)
	if card.skills.size() >= 2 and not card.is_spell():
		draft["skill2"] = card.skills[1].duplicate(true)
	if card.skills.size() >= 3 and not card.is_spell():
		draft["skill3"] = card.skills[2].duplicate(true)
	return draft


func _draft_spell_shell(card_name: String) -> CardData:
	var card := CardData.new(card_name, int(card_draft.get("cost", 0)), 0, 0, [])
	card.card_type = "spell"
	return card


func build_card_from_draft() -> CardData:
	var card_name: String = card_draft.get("name", "Unnamed")
	var card_type: String = card_draft.get("card_type", "minion")
	var is_spell: bool = card_type == "spell"
	var is_parasite: bool = card_type == "parasite"
	var skills: Array = []
	if not card_draft.get("skill1", {}).is_empty():
		var skill1: Dictionary = card_draft["skill1"].duplicate(true)
		if is_spell:
			skill1 = SpellRules.normalize_spell_skill(_draft_spell_shell(card_name), skill1)
		skills.append(skill1)
	if not card_draft.get("skill2", {}).is_empty() and not is_spell and not is_parasite:
		skills.append(card_draft["skill2"].duplicate(true))
	if not card_draft.get("skill3", {}).is_empty() and not is_spell and not is_parasite:
		skills.append(card_draft["skill3"].duplicate(true))

	var card := CardData.new(
		card_name,
		card_draft.get("cost", 0),
		0 if is_spell else card_draft.get("hp", 1),
		0 if is_spell else card_draft.get("atk", 0),
		skills
	)
	card.art_path = card_draft.get("art_path", "")
	card.gender = card_draft.get("gender", "female")
	card.card_type = card_type
	SpellRules.normalize_spell_card(card)
	ParasiteRules.normalize_parasite_card(card)
	return card
