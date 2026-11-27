extends RefCounted

const DEFAULT_SECONDS := 20
const DEFAULT_FIRST_SECONDS := 30
const MIN_SECONDS := 1
const MAX_SECONDS := 300
const KEYS := ["action_time_enabled", "action_time_seconds", "first_action_time_seconds"]

var remaining_ms := 0
var limit_ms := 0
var _turn := Vector2i(-1, -1)
var _actions := -1
var _last_tick := -1
var _was_paused := true


static func enabled(config: Dictionary) -> bool:
	return config.get(KEYS[0], true) == true


static func seconds(config: Dictionary, first: bool) -> int:
	var regular := _valid_seconds(config.get(KEYS[1]), DEFAULT_SECONDS)
	return _valid_seconds(config.get(KEYS[2]), DEFAULT_FIRST_SECONDS) if first else regular


static func _valid_seconds(value: Variant, fallback: int) -> int:
	if (value is int or value is float) and is_finite(float(value)):
		return int(clampf(float(value), MIN_SECONDS, MAX_SECONDS))
	return fallback


func tick(config: Dictionary, turn: Vector2i, actions: int, paused: bool, now: int) -> bool:
	var limit := seconds(config, actions == 0) * 1000 if enabled(config) else 0
	if turn != _turn or actions != _actions or limit != limit_ms:
		_turn = turn
		_actions = actions
		limit_ms = limit
		remaining_ms = limit
	elif not paused and not _was_paused:
		remaining_ms = maxi(0, remaining_ms - maxi(0, now - _last_tick))
	_last_tick = now
	_was_paused = paused
	return limit_ms > 0 and remaining_ms == 0 and not paused
