class_name GamePreferences
extends RefCounted

const PATH := "user://settings.cfg"
const SECTION := "gameplay"
const KEY_ACCELERATE := "accelerate_battle_animations"
const KEY_PLAYBACK_SPEED := "battle_playback_speed"
enum PlaybackSpeed { DEFAULT, MEDIUM, FAST }
const STANDARD_ANIMATION_DURATION_SCALE := 1.55
const DEFAULT_ANIMATION_DURATION_SCALE := 2.05


static func animation_acceleration_enabled() -> bool:
	return battle_playback_speed() == PlaybackSpeed.FAST


static func battle_playback_speed() -> int:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return PlaybackSpeed.DEFAULT
	if config.has_section_key(SECTION, KEY_PLAYBACK_SPEED):
		return clampi(int(config.get_value(SECTION, KEY_PLAYBACK_SPEED)), PlaybackSpeed.DEFAULT, PlaybackSpeed.FAST)
	if config.has_section_key(SECTION, KEY_ACCELERATE):
		return PlaybackSpeed.FAST if config.get_value(SECTION, KEY_ACCELERATE) else PlaybackSpeed.MEDIUM
	return PlaybackSpeed.DEFAULT


static func set_animation_acceleration(enabled: bool) -> void:
	set_battle_playback_speed(PlaybackSpeed.FAST if enabled else PlaybackSpeed.MEDIUM)


static func set_battle_playback_speed(speed: int) -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION, KEY_PLAYBACK_SPEED, clampi(speed, PlaybackSpeed.DEFAULT, PlaybackSpeed.FAST))
	config.save(PATH)


# Accelerated mode preserves the timing used before the card-flow polish.
# Standard mode deliberately gives card movement enough time to be read.
static func battle_animation_duration_scale() -> float:
	match battle_playback_speed():
		PlaybackSpeed.FAST: return 1.0
		PlaybackSpeed.MEDIUM: return STANDARD_ANIMATION_DURATION_SCALE
	return DEFAULT_ANIMATION_DURATION_SCALE


# These effects shared one timing in the original medium and fast settings.
static func battle_effect_speed() -> float:
	return STANDARD_ANIMATION_DURATION_SCALE / DEFAULT_ANIMATION_DURATION_SCALE if battle_playback_speed() == PlaybackSpeed.DEFAULT else 1.0
