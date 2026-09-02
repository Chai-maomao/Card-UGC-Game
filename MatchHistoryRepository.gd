class_name MatchHistoryRepository
extends RefCounted


static func from_payload(payload: Dictionary, maximum: int) -> Array:
	var entries = payload.get("matches", [])
	if not (entries is Array):
		return []
	var result: Array = entries.duplicate(true)
	if result.size() > maximum:
		result.resize(maximum)
	return result


static func add(entries: Array, entry: Dictionary, maximum: int) -> Array:
	var result := entries.duplicate(true)
	result.push_front(entry.duplicate(true))
	if result.size() > maximum:
		result.resize(maximum)
	return result


static func payload(entries: Array) -> Dictionary:
	return {"version": 1, "matches": entries.duplicate(true)}
