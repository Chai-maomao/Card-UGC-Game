extends Node

const TEST_SAVE_PATH := "user://card_library_persistence_test.json"


func _ready() -> void:
	var original_save_path: String = PlayerData.save_path
	var original_decks: Array = PlayerData.deck_library
	var original_cards: Array = PlayerData.card_library
	_cleanup_test_files()

	PlayerData.save_path = TEST_SAVE_PATH
	var card := CardData.new("Persistence", 1, 2, 3, [])
	PlayerData.deck_library = [{"id": "deck_test", "name": "Test", "cards": [card]}]
	PlayerData.rebuild_card_library_cache()
	_assert(PlayerData.save_library(), "initial atomic save failed")
	_assert(FileAccess.file_exists(TEST_SAVE_PATH), "primary save missing")
	_assert(not FileAccess.file_exists(TEST_SAVE_PATH + PlayerData.SAVE_TEMP_SUFFIX), "temporary save was not cleaned")

	var second := CardData.new("Second", 2, 3, 4, [])
	PlayerData.deck_library[0]["cards"].append(second)
	PlayerData.rebuild_card_library_cache()
	_assert(PlayerData.save_library(), "second atomic save failed")
	_assert(FileAccess.file_exists(TEST_SAVE_PATH + PlayerData.SAVE_BACKUP_SUFFIX), "backup save missing")

	# Corrupt the primary. Loading must recover the one-card previous generation
	# from .bak and restore it as the primary file.
	var corrupt := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	corrupt.store_string("{not valid json")
	corrupt.close()
	PlayerData.deck_library = []
	PlayerData.card_library = []
	PlayerData.load_library()
	_assert(PlayerData.deck_library.size() == 1, "backup recovery lost deck")
	_assert(PlayerData.card_library.size() == 1, "backup recovery did not restore previous generation")
	_assert(PlayerData._is_valid_library_json(PlayerData._read_library_file(TEST_SAVE_PATH)), "recovered primary is invalid")

	var oversized := PackedByteArray()
	oversized.resize(PlayerData.MAX_ART_BYTES + 1)
	_assert(PlayerData.save_net_art(oversized, "png") == "", "oversized network art was accepted")
	_assert(PlayerData.save_net_art(PackedByteArray([1, 2, 3]), "../../exe") == "", "unsafe art extension was accepted")

	_cleanup_test_files()
	PlayerData.save_path = original_save_path
	PlayerData.deck_library = original_decks
	PlayerData.card_library = original_cards
	print("TEST_PERSISTENCE_SAFETY_OK")
	get_tree().quit(0)


func _cleanup_test_files() -> void:
	for suffix in ["", PlayerData.SAVE_TEMP_SUFFIX, PlayerData.SAVE_BACKUP_SUFFIX]:
		var path: String = TEST_SAVE_PATH + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_cleanup_test_files()
	get_tree().quit(1)
