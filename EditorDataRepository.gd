class_name EditorDataRepository
extends RefCounted


static func draft_from_payload(payload: Dictionary) -> Dictionary:
	var draft = payload.get("draft", {})
	return payload.duplicate(true) if draft is Dictionary and not draft.is_empty() else {}


static func templates_from_payload(payload: Dictionary) -> Array:
	var entries = payload.get("templates", [])
	return entries.duplicate(true) if entries is Array else []


static func upsert_template(entries: Array, name: String, skill: Dictionary) -> Array:
	var result := entries.duplicate(true)
	for entry in result:
		if str(entry.get("name", "")) == name:
			entry["skill"] = skill.duplicate(true)
			return result
	result.append({"name": name, "skill": skill.duplicate(true)})
	return result


static func remove_template(entries: Array, index: int) -> Array:
	var result := entries.duplicate(true)
	if index >= 0 and index < result.size():
		result.remove_at(index)
	return result
