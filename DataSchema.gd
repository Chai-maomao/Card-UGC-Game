class_name DataSchema
extends RefCounted

const UgcSafetyPolicy = preload("res://UgcSafety.gd")

const KIND_CARD := "card"
const KIND_SKILL := "skill"
const KIND_DECK := "deck"
const KIND_LIBRARY := "library"
const KIND_SHARE_PACKAGE := "share_package"
const KIND_DRAFT_RECOVERY := "draft_recovery"
const KIND_SKILL_TEMPLATES := "skill_templates"
const KIND_MATCH_HISTORY := "match_history"
const KIND_MATCH_SNAPSHOT := "match_snapshot"

const CURRENT_VERSIONS := {
	KIND_LIBRARY: 3,
	KIND_SHARE_PACKAGE: 2,
	KIND_DRAFT_RECOVERY: 1,
	KIND_SKILL_TEMPLATES: 1,
	KIND_MATCH_HISTORY: 1,
	KIND_MATCH_SNAPSHOT: 1,
}

const MAX_DOCUMENT_BYTES := 16 * 1024 * 1024
const MAX_LIBRARY_DECKS := 100
const MAX_CARDS_PER_DECK := 200
const MAX_LIBRARY_CARDS := 5000
const MAX_TEMPLATES := 100
const MAX_HISTORY := 100
const MAX_PARASITES_PER_CARD := 6
const MAX_CARD_NAME_LENGTH := 80
const MAX_SKILL_NAME_LENGTH := 80
const MAX_DECK_NAME_LENGTH := 80
const MAX_ID_LENGTH := 160
const MAX_PATH_LENGTH := 1024


static func parse_and_migrate(kind: String, source: String) -> Dictionary:
	if source.to_utf8_buffer().size() > _max_bytes(kind):
		return _failure("document_too_large", [], {"limit": _max_bytes(kind)})
	var json := JSON.new()
	if json.parse(source) != OK:
		return _failure("invalid_json", [], {"message": json.get_error_message()})
	return migrate_and_validate(kind, json.get_data())


static func migrate_and_validate(kind: String, value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return _failure("root_type", [], {"expected": "Dictionary"})
	var encoded := JSON.stringify(value)
	if encoded.to_utf8_buffer().size() > _max_bytes(kind):
		return _failure("document_too_large", [], {"limit": _max_bytes(kind)})
	var data: Dictionary = value.duplicate(true)
	var from_version := int(data.get("schema" if kind == KIND_MATCH_SNAPSHOT else "version", 0))
	var migration := _migrate(kind, data, from_version)
	if not bool(migration.get("ok", false)):
		return migration
	data = migration.get("data", {})
	var errors := validate(kind, data)
	return {
		"ok": errors.is_empty(),
		"data": data,
		"errors": errors,
		"migrated_from": from_version,
		"version": CURRENT_VERSIONS.get(kind, 1),
	}


static func validate(kind: String, value: Variant) -> Array:
	var errors: Array = []
	match kind:
		KIND_CARD:
			_validate_card(value, [], errors)
		KIND_SKILL:
			_validate_skill(value, [], errors)
		KIND_DECK:
			_validate_deck(value, [], errors)
		KIND_LIBRARY:
			_validate_library(value, errors)
		KIND_SHARE_PACKAGE:
			_validate_share(value, errors)
		KIND_DRAFT_RECOVERY:
			_validate_draft_recovery(value, errors)
		KIND_SKILL_TEMPLATES:
			_validate_templates(value, errors)
		KIND_MATCH_HISTORY:
			_validate_history(value, errors)
		KIND_MATCH_SNAPSHOT:
			_validate_snapshot(value, errors)
		_:
			errors.append(_issue("unknown_schema", [], {"kind": kind}))
	return errors


static func _migrate(kind: String, data: Dictionary, from_version: int) -> Dictionary:
	var current := int(CURRENT_VERSIONS.get(kind, 1))
	if from_version > current:
		return _failure("future_version", [], {"actual": from_version, "supported": current})
	match kind:
		KIND_LIBRARY:
			if from_version < 0 or from_version > 3:
				return _failure("unsupported_version", [], {"actual": from_version})
			# V1/V2 used top-level cards plus deck card_ids; PlayerData's existing
			# deserializer performs that content migration after schema validation.
			data["version"] = 3
		KIND_SHARE_PACKAGE:
			if from_version not in [0, 1, 2]:
				return _failure("unsupported_version", [], {"actual": from_version})
			data["version"] = 2
		KIND_DRAFT_RECOVERY, KIND_SKILL_TEMPLATES, KIND_MATCH_HISTORY:
			if from_version not in [0, 1]:
				return _failure("unsupported_version", [], {"actual": from_version})
			data["version"] = 1
		KIND_MATCH_SNAPSHOT:
			if from_version != 1:
				return _failure("unsupported_version", [], {"actual": from_version})
		_:
			pass
	return {"ok": true, "data": data}


static func _validate_library(value: Variant, errors: Array) -> void:
	if not _expect_dictionary(value, [], errors):
		return
	var root: Dictionary = value
	if int(root.get("version", 0)) != 3:
		errors.append(_issue("version", ["version"], {"expected": 3}))
	var decks = root.get("decks", [])
	var cards = root.get("cards", [])
	if not (decks is Array) or not (cards is Array):
		errors.append(_issue("collection_type", [], {}))
		return
	if decks.size() > MAX_LIBRARY_DECKS or cards.size() > MAX_LIBRARY_CARDS:
		errors.append(_issue("collection_limit", [], {}))
	for i in range(mini(cards.size(), MAX_LIBRARY_CARDS + 1)):
		_validate_card(cards[i], ["cards", i], errors)
	for i in range(mini(decks.size(), MAX_LIBRARY_DECKS + 1)):
		_validate_deck(decks[i], ["decks", i], errors)


static func _validate_deck(value: Variant, path: Array, errors: Array) -> void:
	if not _expect_dictionary(value, path, errors):
		return
	var deck: Dictionary = value
	_validate_string(deck.get("id", ""), path + ["id"], 1, MAX_ID_LENGTH, errors)
	_validate_string(deck.get("name", ""), path + ["name"], 1, MAX_DECK_NAME_LENGTH, errors)
	if deck.has("cards"):
		var cards = deck.get("cards")
		if not (cards is Array):
			errors.append(_issue("cards_type", path + ["cards"], {}))
			return
		if cards.size() > MAX_CARDS_PER_DECK:
			errors.append(_issue("card_count", path + ["cards"], {"limit": MAX_CARDS_PER_DECK}))
		for i in range(mini(cards.size(), MAX_CARDS_PER_DECK + 1)):
			_validate_card(cards[i], path + ["cards", i], errors)
	elif deck.has("card_ids"):
		var ids = deck.get("card_ids")
		if not (ids is Array) or ids.size() > MAX_CARDS_PER_DECK:
			errors.append(_issue("card_ids", path + ["card_ids"], {}))
		elif ids is Array:
			for i in range(ids.size()):
				_validate_string(ids[i], path + ["card_ids", i], 1, MAX_ID_LENGTH, errors)
	else:
		errors.append(_issue("missing_cards", path, {}))


static func _validate_card(value: Variant, path: Array, errors: Array, parasite_depth: int = 0) -> void:
	if not _expect_dictionary(value, path, errors):
		return
	var card: Dictionary = value
	_validate_string(card.get("name", null), path + ["name"], 1, MAX_CARD_NAME_LENGTH, errors)
	for field in ["cost", "atk"]:
		_validate_integer(card.get(field, null), path + [field], errors)
	if not card.has("max_hp") and not card.has("hp"):
		errors.append(_issue("missing_field", path + ["max_hp"], {}))
	elif card.has("max_hp"):
		_validate_integer(card.get("max_hp"), path + ["max_hp"], errors)
	_validate_enum(card.get("card_type", "minion"), ["minion", "spell", "parasite"], path + ["card_type"], errors)
	_validate_enum(card.get("gender", "female"), ["female", "male", "nonhuman"], path + ["gender"], errors)
	if card.has("card_id"):
		_validate_string(card.get("card_id"), path + ["card_id"], 0, MAX_ID_LENGTH, errors)
	if card.has("instance_id"):
		_validate_string(card.get("instance_id"), path + ["instance_id"], 0, MAX_ID_LENGTH, errors)
	if card.has("art_path"):
		_validate_string(card.get("art_path"), path + ["art_path"], 0, MAX_PATH_LENGTH, errors)
	var skills = card.get("skills", [])
	if not (skills is Array):
		errors.append(_issue("skills_type", path + ["skills"], {}))
	else:
		for i in range(mini(skills.size(), UgcSafetyPolicy.MAX_SKILLS_PER_CARD + 1)):
			_validate_skill(skills[i], path + ["skills", i], errors)
	var safety := UgcSafetyPolicy.validate_serialized_card(card)
	for entry in safety:
		var copy: Dictionary = entry.duplicate(true)
		copy["path"] = path + copy.get("path", [])
		errors.append(copy)
	var parasites = card.get("parasite_cards", [])
	if not (parasites is Array):
		errors.append(_issue("parasites_type", path + ["parasite_cards"], {}))
	elif parasites.size() > MAX_PARASITES_PER_CARD or parasite_depth >= 4 and not parasites.is_empty():
		errors.append(_issue("parasite_limit", path + ["parasite_cards"], {}))
	else:
		for i in range(parasites.size()):
			_validate_card(parasites[i], path + ["parasite_cards", i], errors, parasite_depth + 1)


static func _validate_skill(value: Variant, path: Array, errors: Array) -> void:
	if not _expect_dictionary(value, path, errors):
		return
	var skill: Dictionary = value
	_validate_string(skill.get("skill_name", ""), path + ["skill_name"], 0, MAX_SKILL_NAME_LENGTH, errors)
	_validate_enum(skill.get("trigger", ""), SkillRegistry.TRIGGER_META.keys(), path + ["trigger"], errors)
	if skill.has("probability"):
		_validate_integer(skill.get("probability"), path + ["probability"], errors)
	var effects = skill.get("effects", null)
	if effects == null and skill.has("effect"):
		effects = [skill]
	if effects == null:
		effects = []
	if not (effects is Array):
		errors.append(_issue("effects_type", path + ["effects"], {}))
		return
	_validate_effects(effects, path + ["effects"], errors)
	var safety_skill := skill.duplicate(true)
	safety_skill["effects"] = effects
	for entry in UgcSafetyPolicy.validate_skill(safety_skill):
		var copy: Dictionary = entry.duplicate(true)
		copy["path"] = path + copy.get("path", [])
		errors.append(copy)


static func _validate_effects(effects: Array, path: Array, errors: Array) -> void:
	var stack: Array = [{"items": effects, "path": path}]
	while not stack.is_empty() and errors.size() < 100:
		var frame: Dictionary = stack.pop_back()
		var items: Array = frame["items"]
		for i in range(items.size()):
			var item_path: Array = frame["path"] + [i]
			var effect = items[i]
			if not (effect is Dictionary):
				errors.append(_issue("effect_type", item_path, {}))
				continue
			var effect_id = effect.get("effect", null)
			if not (effect_id is String) or not SkillRegistry.EFFECT_META.has(effect_id):
				errors.append(_issue("unknown_effect", item_path + ["effect"], {"actual": effect_id}))
			if effect.has("target"):
				var compatible_targets: Array = SkillRegistry.TARGET_IDS + ["all_allies", "all_enemies"]
				_validate_enum(effect.get("target"), compatible_targets, item_path + ["target"], errors)
			if effect.has("target_side"):
				_validate_enum(effect.get("target_side"), SkillRegistry.TARGET_SIDE_IDS, item_path + ["target_side"], errors)
			if effect.has("buff_id") and str(effect.get("buff_id", "")) != "":
				_validate_enum(effect.get("buff_id"), SkillRegistry.BUFF_IDS, item_path + ["buff_id"], errors)
			for branch in ["then_effects", "else_effects"]:
				var nested = effect.get(branch, [])
				if nested is Array and not nested.is_empty():
					stack.append({"items": nested, "path": item_path + [branch]})


static func _validate_share(value: Variant, errors: Array) -> void:
	if not _expect_dictionary(value, [], errors):
		return
	var root: Dictionary = value
	if int(root.get("version", 0)) != 2:
		errors.append(_issue("version", ["version"], {"expected": 2}))
	_validate_enum(root.get("type", ""), ["cards", "deck"], ["type"], errors)
	var cards = root.get("cards", null)
	if not (cards is Array) or cards.size() > MAX_CARDS_PER_DECK:
		errors.append(_issue("cards_type_or_limit", ["cards"], {}))
	else:
		for i in range(cards.size()):
			_validate_card(cards[i], ["cards", i], errors)
	if root.get("type", "") == "deck":
		_validate_deck(root.get("deck", null), ["deck"], errors)


static func _validate_draft_recovery(value: Variant, errors: Array) -> void:
	if not _expect_dictionary(value, [], errors):
		return
	var root: Dictionary = value
	var draft = root.get("draft", null)
	if not (draft is Dictionary):
		errors.append(_issue("draft_type", ["draft"], {}))
		return
	_validate_string(draft.get("name", ""), ["draft", "name"], 0, MAX_CARD_NAME_LENGTH, errors)
	for field in ["cost", "hp", "atk"]:
		_validate_integer(draft.get(field, null), ["draft", field], errors)
	_validate_enum(draft.get("card_type", "minion"), ["minion", "spell", "parasite"], ["draft", "card_type"], errors)
	for key in ["skill1", "skill2", "skill3"]:
		var skill = draft.get(key, {})
		if not (skill is Dictionary):
			errors.append(_issue("skill_type", ["draft", key], {}))
		elif not skill.is_empty():
			_validate_skill(skill, ["draft", key], errors)


static func _validate_templates(value: Variant, errors: Array) -> void:
	if not _expect_dictionary(value, [], errors):
		return
	var entries = value.get("templates", null)
	if not (entries is Array) or entries.size() > MAX_TEMPLATES:
		errors.append(_issue("templates_type_or_limit", ["templates"], {}))
		return
	for i in range(entries.size()):
		if not _expect_dictionary(entries[i], ["templates", i], errors):
			continue
		_validate_string(entries[i].get("name", ""), ["templates", i, "name"], 1, MAX_SKILL_NAME_LENGTH, errors)
		_validate_skill(entries[i].get("skill", null), ["templates", i, "skill"], errors)


static func _validate_history(value: Variant, errors: Array) -> void:
	if not _expect_dictionary(value, [], errors):
		return
	var matches = value.get("matches", null)
	if not (matches is Array) or matches.size() > MAX_HISTORY:
		errors.append(_issue("history_type_or_limit", ["matches"], {}))
		return
	for i in range(matches.size()):
		if not _expect_dictionary(matches[i], ["matches", i], errors):
			continue
		var entry: Dictionary = matches[i]
		for key in ["id", "mode", "outcome", "result", "deck_name", "app_version"]:
			if entry.has(key):
				_validate_string(entry[key], ["matches", i, key], 0, 160, errors)
		for key in ["timestamp", "turns", "player_hp", "opponent_hp", "duration"]:
			if entry.has(key):
				_validate_integer(entry[key], ["matches", i, key], errors)


static func _validate_snapshot(value: Variant, errors: Array) -> void:
	if not _expect_dictionary(value, [], errors):
		return
	var root: Dictionary = value
	if int(root.get("schema", 0)) != 1:
		errors.append(_issue("schema", ["schema"], {"expected": 1}))
	_validate_string(root.get("room_code", null), ["room_code"], 1, 32, errors)
	if int(root.get("player", 0)) not in [1, 2]:
		errors.append(_issue("player", ["player"], {}))
	var state = root.get("state", null)
	if not (state is Dictionary):
		errors.append(_issue("state_type", ["state"], {}))
		return
	for key in ["player_field", "player2_field", "player_hand", "player2_hand", "shared_deck", "state_revision"]:
		if not state.has(key):
			errors.append(_issue("missing_field", ["state", key], {}))
	for array_key in ["player_hand", "player2_hand", "shared_deck", "shared_discard"]:
		var cards = state.get(array_key, [])
		if not (cards is Array) or cards.size() > MAX_LIBRARY_CARDS:
			errors.append(_issue("cards_type_or_limit", ["state", array_key], {}))
		else:
			for i in range(cards.size()):
				_validate_card(cards[i], ["state", array_key, i], errors)
	for field_key in ["player_field", "player2_field"]:
		var field = state.get(field_key, {})
		if field is Dictionary and field.has("slots"):
			var slots = field.get("slots")
			if not (slots is Array) or slots.size() != 5:
				errors.append(_issue("slots", ["state", field_key, "slots"], {}))
			elif slots is Array:
				for i in range(slots.size()):
					if slots[i] is Dictionary and not slots[i].is_empty():
						_validate_card(slots[i], ["state", field_key, "slots", i], errors)


static func _expect_dictionary(value: Variant, path: Array, errors: Array) -> bool:
	if value is Dictionary:
		return true
	errors.append(_issue("dictionary_type", path, {}))
	return false


static func _validate_string(value: Variant, path: Array, minimum: int, maximum: int, errors: Array) -> void:
	if not (value is String):
		errors.append(_issue("string_type", path, {}))
		return
	var length: int = value.length()
	if length < minimum or length > maximum:
		errors.append(_issue("string_length", path, {"min": minimum, "max": maximum, "actual": length}))


static func _validate_integer(value: Variant, path: Array, errors: Array) -> void:
	if value is int:
		return
	if value is float and value == floor(value):
		return
	errors.append(_issue("integer_type", path, {}))


static func _validate_enum(value: Variant, allowed: Array, path: Array, errors: Array) -> void:
	if not (value is String) or not allowed.has(value):
		errors.append(_issue("enum", path, {"actual": value}))


static func _max_bytes(kind: String) -> int:
	if kind == KIND_SHARE_PACKAGE:
		return UgcSafetyPolicy.MAX_SHARE_PACKAGE_BYTES
	return MAX_DOCUMENT_BYTES


static func _failure(code: String, path: Array, details: Dictionary) -> Dictionary:
	return {"ok": false, "data": {}, "errors": [_issue(code, path, details)]}


static func _issue(code: String, path: Array, details: Dictionary) -> Dictionary:
	return {"code": code, "path": path.duplicate(), "details": details.duplicate(true)}
