class_name MatchSnapshotStore
extends RefCounted

const Schema = preload("res://DataSchema.gd")

var primary_path: String
var backup_path: String


func _init(path: String, backup: String = "") -> void:
	primary_path = path
	backup_path = backup if backup != "" else path + ".bak"


func save(payload: Dictionary) -> bool:
	if not is_valid(payload):
		return false
	var encoded := JSON.stringify(payload)
	var temp_path := primary_path + ".tmp"
	_remove(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(encoded)
	file.flush()
	file.close()
	if not is_valid(JSON.parse_string(_read(temp_path))):
		_remove(temp_path)
		return false
	_remove(backup_path)
	if FileAccess.file_exists(primary_path):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(primary_path), ProjectSettings.globalize_path(backup_path)) != OK:
			_remove(temp_path)
			return false
	_remove(primary_path)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(primary_path)) != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(primary_path))
		_remove(temp_path)
		return false
	return true


func load() -> Dictionary:
	var payload = JSON.parse_string(_read(primary_path))
	var recovered := false
	if not is_valid(payload):
		payload = JSON.parse_string(_read(backup_path))
		recovered = is_valid(payload)
	if not is_valid(payload):
		return {}
	if recovered:
		_remove(primary_path)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(primary_path))
	return payload


func clear() -> void:
	_remove(primary_path)
	_remove(primary_path + ".tmp")
	_remove(backup_path)


static func is_valid(value: Variant) -> bool:
	return Schema.validate(Schema.KIND_MATCH_SNAPSHOT, value).is_empty()


static func encode_state(state: Dictionary) -> Dictionary:
	var encoded := state.duplicate(true)
	for key in ["rng_seed", "rng_state"]:
		if encoded.has(key):
			encoded[key] = str(encoded[key])
	return encoded


static func decode_state(state: Dictionary) -> Dictionary:
	var decoded := state.duplicate(true)
	for key in ["rng_seed", "rng_state"]:
		if decoded.has(key):
			decoded[key] = int(str(decoded[key]))
	return decoded


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
