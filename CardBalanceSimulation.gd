class_name CardBalanceSimulation
extends RefCounted

const POOL_IDS := ["units", "spells", "support"]
const DEFAULT_GAMES_PER_POOL := 16
const CANDIDATE_METRIC_KEY := "__cardex_draft_candidate__"
const BASE_SEED := 31000


static func build_pool(kind: String, candidate: CardData) -> Array:
	var cards: Array = build_baseline_pool(kind)
	var specimen := candidate.duplicate_card()
	# Headless metrics are keyed by card name. Give the isolated simulation copy
	# a reserved name so a player card cannot collide with a calibration fixture.
	specimen.card_name = CANDIDATE_METRIC_KEY
	specimen.card_id = "simulation:candidate"
	specimen.instance_id = "simulation:candidate"
	cards.append(specimen)
	return cards


static func build_baseline_pool(kind: String) -> Array:
	return BalanceCalibration.pool(kind)


static func seed_for_pool(kind: String) -> int:
	return BASE_SEED + maxi(0, POOL_IDS.find(kind)) * 1000


static func new_accumulator(kind: String, requested_games: int) -> Dictionary:
	return {
		"pool": kind,
		"requested_games": maxi(1, requested_games),
		"games": 0,
		"wins": {"p1": 0, "p2": 0, "draw": 0},
		"rounds_total": 0,
		"mana_spent": 0,
		"unused_mana": 0,
		"stability_failures": 0,
		"candidate": _empty_candidate_metrics(),
	}


static func add_game(accumulator: Dictionary, result: Dictionary) -> void:
	accumulator["games"] = int(accumulator.get("games", 0)) + 1
	var wins: Dictionary = accumulator.get("wins", {})
	var winner := str(result.get("winner", "draw"))
	if winner not in ["p1", "p2"]:
		winner = "draw"
	wins[winner] = int(wins.get(winner, 0)) + 1
	accumulator["rounds_total"] = int(accumulator.get("rounds_total", 0)) + int(result.get("rounds", 0))
	accumulator["mana_spent"] = int(accumulator.get("mana_spent", 0)) + int(result.get("mana_spent", 0))
	accumulator["unused_mana"] = int(accumulator.get("unused_mana", 0)) + int(result.get("unused_mana", 0))
	if not bool(result.get("stable", false)):
		accumulator["stability_failures"] = int(accumulator.get("stability_failures", 0)) + 1
	var candidate: Dictionary = accumulator.get("candidate", {})
	var metrics: Dictionary = result.get("cards", {}).get(CANDIDATE_METRIC_KEY, {})
	for key in candidate.keys():
		candidate[key] = int(candidate.get(key, 0)) + int(metrics.get(key, 0))


static func finalize(accumulator: Dictionary) -> Dictionary:
	var games := maxi(1, int(accumulator.get("games", 0)))
	var wins: Dictionary = accumulator.get("wins", {})
	var decisive := int(wins.get("p1", 0)) + int(wins.get("p2", 0))
	var spent := int(accumulator.get("mana_spent", 0))
	var unused := int(accumulator.get("unused_mana", 0))
	var candidate: Dictionary = accumulator.get("candidate", {}).duplicate(true)
	var plays := int(candidate.get("summons", 0)) + int(candidate.get("casts", 0)) + int(candidate.get("attaches", 0))
	var actions := int(candidate.get("skills", 0)) + int(candidate.get("attacks", 0))
	candidate["plays"] = plays
	candidate["plays_per_game"] = float(plays) / games
	candidate["actions_per_game"] = float(actions) / games
	candidate["damage_per_game"] = float(candidate.get("damage", 0)) / games
	candidate["healing_per_game"] = float(candidate.get("healing", 0)) / games
	var result := {
		"pool": str(accumulator.get("pool", "units")),
		"games": int(accumulator.get("games", 0)),
		"wins": wins.duplicate(true),
		"draw_rate": float(wins.get("draw", 0)) / games,
		"first_player_win_rate": float(wins.get("p1", 0)) / maxf(1.0, float(decisive)),
		"average_rounds": float(accumulator.get("rounds_total", 0)) / games,
		"mana_utilization": float(spent) / maxf(1.0, float(spent + unused)),
		"stability_failures": int(accumulator.get("stability_failures", 0)),
		"candidate": candidate,
		"warnings": [],
	}
	var warnings: Array = result["warnings"]
	if int(result["stability_failures"]) > 0:
		warnings.append("unstable")
	if float(result["draw_rate"]) >= 0.25:
		warnings.append("high_draw_rate")
	if decisive >= maxi(8, int(ceil(float(games) * 0.5))) and (float(result["first_player_win_rate"]) < 0.35 or float(result["first_player_win_rate"]) > 0.65):
		warnings.append("first_player_skew")
	if plays == 0:
		warnings.append("candidate_unused")
	return result


static func _empty_candidate_metrics() -> Dictionary:
	return {
		"summons": 0,
		"casts": 0,
		"attaches": 0,
		"skills": 0,
		"attacks": 0,
		"damage": 0,
		"healing": 0,
	}
