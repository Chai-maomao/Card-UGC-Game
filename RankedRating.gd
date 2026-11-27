extends RefCounted

const INITIAL_RATING := 1000
const ELO_FACTOR := 32
const PackRating = preload("res://MatchPackRating.gd")

var _path: String
var _players: Dictionary = {}
var _settled: Dictionary = {}
var can_save := false


func _init(path: String) -> void:
	_path = path
	var journal := FileAccess.open(_path, FileAccess.READ)
	if journal == null:
		can_save = not FileAccess.file_exists(_path)
		return
	while journal.get_position() < journal.get_length():
		var line := journal.get_line()
		if line.is_empty():
			continue
		var parser := JSON.new()
		if parser.parse(line) != OK:
			continue
		var row: Variant = parser.data
		if row is Dictionary and row.has_all(["match_id", "first", "second", "winner"]):
			_apply(row)
	can_save = true


func profile(id: String) -> Dictionary:
	return _players.get(id, {"rating": INITIAL_RATING, "played": 0, "won": 0}).duplicate()


func settlement_for(match_id: String, profile_id: String) -> Dictionary:
	var match_settlement: Dictionary = _settled.get(match_id, {})
	return match_settlement.get(profile_id, {}).duplicate()


static func rating_after(first: int, second: int, winner: int, multipliers: Array = []) -> Array[int]:
	var expected := 1.0 / (1.0 + pow(10.0, (float(second) - float(first)) / 400.0))
	var score := 0.5 if winner == 3 else float(winner == 1)
	var change := ELO_FACTOR * (score - expected)
	return [maxi(0, first + _adjust_change(change, multipliers, 0)),
		maxi(0, second + _adjust_change(-change, multipliers, 1))]


static func _adjust_change(change: float, multipliers: Array, index: int) -> int:
	var base := roundi(change)
	if base <= 0 or index >= multipliers.size():
		return base
	return maxi(1, roundi(change * PackRating.validated_multiplier(multipliers[index])))


func settle(match_id: String, first: String, second: String, winner: int, multipliers: Array = []) -> bool:
	if not can_save or first == second or winner not in [1, 2, 3]:
		return false
	if _settled.has(match_id):
		return true
	var journal := FileAccess.open(_path, FileAccess.READ_WRITE if FileAccess.file_exists(_path) else FileAccess.WRITE)
	if journal == null:
		return false
	var row := {"match_id": match_id, "first": first, "second": second, "winner": winner,
		"multipliers": multipliers}
	journal.seek_end()
	# A torn last record must never corrupt the next complete settlement.
	if not journal.store_string("\n" + JSON.stringify(row) + "\n"):
		return false
	journal.flush()
	if journal.get_error() != OK:
		return false
	_apply(row)
	return true


func _apply(row: Dictionary) -> void:
	var match_id := str(row.match_id)
	var first_id := str(row.first)
	var second_id := str(row.second)
	var winner := int(row.winner)
	if _settled.has(match_id) or first_id == second_id or winner not in [1, 2, 3]:
		return
	var first := profile(first_id)
	var second := profile(second_id)
	var multipliers: Variant = row.get("multipliers", [])
	var scores := rating_after(first.rating, second.rating, winner, multipliers if multipliers is Array else [])
	_settled[match_id] = {
		first_id: _settlement(first.rating, scores[0], multipliers, 0),
		second_id: _settlement(second.rating, scores[1], multipliers, 1),
	}
	first.rating = scores[0]
	second.rating = scores[1]
	first.played += 1
	second.played += 1
	first.won += int(winner == 1)
	second.won += int(winner == 2)
	_players[first_id] = first
	_players[second_id] = second


static func _settlement(before: int, after: int, multipliers: Variant, index: int) -> Dictionary:
	var entry := {"before": before, "after": after}
	if multipliers is Array and index < multipliers.size():
		entry["multiplier"] = PackRating.validated_multiplier(multipliers[index])
	return entry
