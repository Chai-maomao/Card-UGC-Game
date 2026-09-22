class_name GamePreferences
extends RefCounted

const PATH := "user://settings.cfg"
const SECTION := "gameplay"
const KEY_ACCELERATE := "accelerate_battle_animations"
const STANDARD_ANIMATION_DURATION_SCALE := 1.55


static func animation_acceleration_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return false
	return bool(config.get_value(SECTION, KEY_ACCELERATE, false))


static func set_animation_acceleration(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION, KEY_ACCELERATE, enabled)
	config.save(PATH)


# Accelerated mode preserves the timing used before the card-flow polish.
# Standard mode deliberately gives card movement enough time to be read.
static func battle_animation_duration_scale() -> float:
	return 1.0 if animation_acceleration_enabled() else STANDARD_ANIMATION_DURATION_SCALE
