class_name RoomPresenceStore
extends RefCounted

# Private IPC between the lobby and its room subprocess. Never sent to clients.
static func write(path: String, payload: Dictionary) -> bool:
	if path.is_empty(): return true # Standalone room used by local checks.
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	# Windows cannot replace an existing target with rename. A reader seeing the
	# short gap returns room_starting, never a stale vacant seat.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

static func read(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4096: return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary or not value.get("occupied") is Array or not value.get("tokens") is Dictionary:
		return {}
	return value
