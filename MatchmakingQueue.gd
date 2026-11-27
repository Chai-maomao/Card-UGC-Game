extends RefCounted

const RANKED := "ranked"
const RANDOM := "random"
const PACK_PROTOCOL := 3
const PREPARATION_LIMIT_MS := 90000
const SEARCH_LIMIT_MS := 120000
const BASE_RATING_RANGE := 100
const RATING_RANGE_STEP := 50
const RANGE_INTERVAL_MS := 10000

var _waiting: Dictionary = {}


static func valid_mode(mode: String) -> bool:
	return mode in [RANKED, RANDOM]


func add(peer: int, profile: String, mode: String, rating: int, now: int) -> bool:
	if not valid_mode(mode) or _waiting.has(peer):
		return false
	for entry: Dictionary in _waiting.values():
		if entry.profile == profile:
			return false
	_waiting[peer] = {"peer": peer, "profile": profile, "mode": mode, "rating": rating, "since": now}
	return true


func remove(peer: int) -> void:
	_waiting.erase(peer)


func expire(now: int) -> Array[int]:
	var peers: Array[int] = []
	for peer: int in _waiting.keys():
		if now - int(_waiting[peer].since) >= SEARCH_LIMIT_MS:
			peers.append(peer)
			remove(peer)
	return peers


func find_pair(now: int) -> Array[Dictionary]:
	var entries := _waiting.values()
	entries.sort_custom(func(left: Dictionary, right: Dictionary): return int(left.since) < int(right.since))
	for index in entries.size():
		var first: Dictionary = entries[index]
		for other in range(index + 1, entries.size()):
			var second: Dictionary = entries[other]
			if first.mode != second.mode:
				continue
			if first.mode == RANKED:
				var waited := now - mini(int(first.since), int(second.since))
				var rating_range := BASE_RATING_RANGE + floori(float(waited) / RANGE_INTERVAL_MS) * RATING_RANGE_STEP
				if absi(int(first.rating) - int(second.rating)) > rating_range:
					continue
			return [first, second]
	return []
