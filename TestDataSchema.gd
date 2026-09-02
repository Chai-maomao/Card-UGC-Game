extends Node

const Schema = preload("res://DataSchema.gd")
const TEST_HISTORY_PATH := "user://schema_history_test.json"

var failures: Array[String] = []


func _ready() -> void:
	_test_all_schema_entry_points()
	_test_invalid_boundaries()
	_test_legacy_migrations()
	_test_atomic_backup_recovery()
	_cleanup()
	if failures.is_empty():
		print("TEST_DATA_SCHEMA_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_DATA_SCHEMA_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_all_schema_entry_points() -> void:
	var card := _card()
	var skill: Dictionary = card["skills"][0]
	_assert(Schema.validate(Schema.KIND_CARD, card).is_empty(), "card schema rejected valid card")
	_assert(Schema.validate(Schema.KIND_SKILL, skill).is_empty(), "skill schema rejected valid skill")
	_assert(Schema.validate(Schema.KIND_DECK, {"id": "d", "name": "Deck", "cards": [card]}).is_empty(), "deck schema rejected valid deck")
	var library := {"version": 3, "decks": [{"id": "d", "name": "Deck", "cards": [card]}]}
	_assert(Schema.validate(Schema.KIND_LIBRARY, library).is_empty(), "library schema rejected valid library")
	var share := {"version": 2, "type": "cards", "cards": [card]}
	_assert(Schema.validate(Schema.KIND_SHARE_PACKAGE, share).is_empty(), "share schema rejected valid package")
	var draft := {"version": 1, "draft": {"name": "Draft", "cost": 1, "hp": 2, "atk": 1, "card_type": "minion", "skill1": skill, "skill2": {}, "skill3": {}}}
	_assert(Schema.validate(Schema.KIND_DRAFT_RECOVERY, draft).is_empty(), "draft schema rejected valid recovery")
	var templates := {"version": 1, "templates": [{"name": "Template", "skill": skill}]}
	_assert(Schema.validate(Schema.KIND_SKILL_TEMPLATES, templates).is_empty(), "template schema rejected valid templates")
	var history := {"version": 1, "matches": [{"id": "m", "timestamp": 1, "mode": "practice", "outcome": "win"}]}
	_assert(Schema.validate(Schema.KIND_MATCH_HISTORY, history).is_empty(), "history schema rejected valid history")
	var snapshot := {"schema": 1, "room_code": "ROOM", "player": 1, "state": {"player_field": {}, "player2_field": {}, "player_hand": [], "player2_hand": [], "shared_deck": [], "state_revision": 1}}
	_assert(Schema.validate(Schema.KIND_MATCH_SNAPSHOT, snapshot).is_empty(), "snapshot schema rejected valid snapshot")


func _test_invalid_boundaries() -> void:
	var missing := _card()
	missing.erase("name")
	_assert(not Schema.validate(Schema.KIND_CARD, missing).is_empty(), "missing required card name was accepted")
	var wrong_type := _card()
	wrong_type["cost"] = "free"
	_assert(not Schema.validate(Schema.KIND_CARD, wrong_type).is_empty(), "wrong numeric type was accepted")
	var unknown := _card()
	unknown["skills"][0]["effects"][0]["effect"] = "run_arbitrary_code"
	_assert(_has_code(Schema.validate(Schema.KIND_CARD, unknown), "unknown_effect"), "unknown effect was accepted")
	_assert(not bool(Schema.parse_and_migrate(Schema.KIND_LIBRARY, "{\"version\":3,\"decks\":[").get("ok", true)), "partial JSON was accepted")
	var oversized := "x".repeat(UgcSafety.MAX_SHARE_PACKAGE_BYTES + 1)
	_assert(_has_code(Schema.parse_and_migrate(Schema.KIND_SHARE_PACKAGE, oversized).get("errors", []), "document_too_large"), "oversized document was not rejected before parsing")


func _test_legacy_migrations() -> void:
	var card := _card()
	var legacy_library := {
		"version": 1,
		"cards": [card],
		"decks": [{"id": "old", "name": "Old", "card_ids": [card["card_id"]]}],
	}
	var migrated := Schema.migrate_and_validate(Schema.KIND_LIBRARY, legacy_library)
	_assert(bool(migrated.get("ok", false)), "v1 library migration failed: %s" % [migrated.get("errors", [])])
	_assert(int(migrated.get("data", {}).get("version", 0)) == 3, "library migration did not advance to v3")
	var legacy_share := {"version": 1, "type": "cards", "cards": [card]}
	var migrated_share := Schema.migrate_and_validate(Schema.KIND_SHARE_PACKAGE, legacy_share)
	_assert(bool(migrated_share.get("ok", false)) and int(migrated_share["data"]["version"]) == 2, "v1 share migration failed")
	var future := {"version": 999, "decks": []}
	_assert(_has_code(Schema.migrate_and_validate(Schema.KIND_LIBRARY, future).get("errors", []), "future_version"), "future schema version was accepted")


func _test_atomic_backup_recovery() -> void:
	_cleanup()
	var first := {"version": 1, "matches": [{"id": "first", "timestamp": 1}]}
	var second := {"version": 1, "matches": [{"id": "second", "timestamp": 2}]}
	_assert(PlayerData._write_json_atomic(TEST_HISTORY_PATH, first, Schema.KIND_MATCH_HISTORY), "first schema-aware atomic write failed")
	_assert(PlayerData._write_json_atomic(TEST_HISTORY_PATH, second, Schema.KIND_MATCH_HISTORY), "second schema-aware atomic write failed")
	var corrupt := FileAccess.open(TEST_HISTORY_PATH, FileAccess.WRITE)
	corrupt.store_string("{partial")
	corrupt.close()
	var recovered := PlayerData._read_json_dictionary(TEST_HISTORY_PATH, Schema.KIND_MATCH_HISTORY)
	_assert(str(recovered.get("matches", [{}])[0].get("id", "")) == "first", "schema-aware reader did not recover known-good backup")


func _card() -> Dictionary:
	return {
		"card_id": "card_test",
		"instance_id": "instance_test",
		"name": "Schema Card",
		"cost": 1,
		"max_hp": 2,
		"hp": 2,
		"atk": 1,
		"gender": "female",
		"card_type": "minion",
		"skills": [{
			"skill_name": "Hit",
			"trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
			"probability": 100,
			"effects": [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "value": 1}],
		}],
	}


func _has_code(errors: Array, code: String) -> bool:
	for error in errors:
		if str(error.get("code", "")) == code:
			return true
	return false


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_HISTORY_PATH + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
