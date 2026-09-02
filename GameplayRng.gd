class_name GameplayRng
extends RefCounted

# Gameplay code must never fall back to Godot's process-global RNG. Battle
# contexts normally carry GameState.game_rng; isolated callers receive a
# deterministic, context-owned generator so tests and tools stay reproducible.
const FALLBACK_SEED := 0x43415244


static func from_context(context: Dictionary) -> RandomNumberGenerator:
	var existing = context.get("rng", null)
	if existing is RandomNumberGenerator:
		return existing
	var rng := RandomNumberGenerator.new()
	rng.seed = FALLBACK_SEED
	context["rng"] = rng
	if not bool(context.get("_rng_fallback_warned", false)):
		context["_rng_fallback_warned"] = true
		push_warning("Gameplay context had no RNG; installed deterministic fallback seed %d" % FALLBACK_SEED)
	return rng


static func shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temporary = values[i]
		values[i] = values[j]
		values[j] = temporary
