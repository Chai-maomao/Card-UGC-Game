class_name CardRevisionRepository
extends RefCounted

const VERSION := 1
const MAX_REVISIONS_PER_CARD := 10
const MAX_TOTAL_REVISIONS := 2000


static func from_payload(payload: Dictionary) -> Array:
	var source = payload.get("revisions", [])
	if not source is Array:
		return []
	var result: Array = []
	for value in source:
		if value is Dictionary:
			result.append(value.duplicate(true))
		if result.size() >= MAX_TOTAL_REVISIONS:
			break
	return result


static func payload(entries: Array) -> Dictionary:
	return {"version": VERSION, "revisions": entries.duplicate(true)}


static func history(entries: Array, card_id: String) -> Array:
	var result: Array = []
	if card_id.is_empty():
		return result
	for value in entries:
		if value is Dictionary and str(value.get("card_id", "")) == card_id:
			result.append(value.duplicate(true))
	return result


static func add(entries: Array, card_snapshot: Dictionary, saved_at: int) -> Dictionary:
	var card_id := str(card_snapshot.get("card_id", ""))
	if card_id.is_empty():
		return {"changed": false, "entries": entries.duplicate(true)}
	var result := entries.duplicate(true)
	var existing := history(result, card_id)
	if not existing.is_empty() and _same_content(existing[0].get("card", {}), card_snapshot):
		return {"changed": false, "entries": result}
	var next_revision := 1
	for revision in existing:
		next_revision = maxi(next_revision, int(revision.get("revision", 0)) + 1)
	result.push_front({
		"card_id": card_id,
		"revision": next_revision,
		"saved_at": saved_at,
		"card": card_snapshot.duplicate(true),
	})
	var kept_for_card := 0
	var trimmed: Array = []
	for entry in result:
		if entry is Dictionary and str(entry.get("card_id", "")) == card_id:
			kept_for_card += 1
			if kept_for_card > MAX_REVISIONS_PER_CARD:
				continue
		trimmed.append(entry)
	result = trimmed
	if result.size() > MAX_TOTAL_REVISIONS:
		result.resize(MAX_TOTAL_REVISIONS)
	return {"changed": true, "entries": result}


static func _same_content(left_value: Variant, right_value: Variant) -> bool:
	if not left_value is Dictionary or not right_value is Dictionary:
		return false
	var left: Dictionary = left_value.duplicate(true)
	var right: Dictionary = right_value.duplicate(true)
	# Copies of one design have different instance IDs but share one history.
	left.erase("instance_id")
	right.erase("instance_id")
	return left == right
