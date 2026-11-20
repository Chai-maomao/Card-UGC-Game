extends Node

const MenuScene = preload("res://MainMenu.tscn")
const BootstrapScript = preload("res://Bootstrap.gd")
var failures: Array[String] = []
var path := "res://artifacts/first-launch/logic-progress.cfg"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/first-launch"))
	var original_path := PlayerData.tutorial_progress_path
	var original_pending := PlayerData.startup_tutorial_pending
	var original_existing := PlayerData.had_saved_library_on_startup
	var library_hash := FileAccess.get_sha256(PlayerData.save_path)
	var progress := TutorialProgress.new(path)
	progress.clear()
	PlayerData.tutorial_progress_path = path
	PlayerData.had_saved_library_on_startup = false
	var bootstrap = BootstrapScript.new()
	_check(bootstrap._startup_target(PackedStringArray()) == "res://MainMenu.tscn", "first launch must show the original title scene")
	_check(FileAccess.file_exists(path) and progress.status() == "in_progress" and PlayerData.startup_tutorial_pending,
			"first launch must persist its pending introduction before displaying it")
	var menu = MenuScene.instantiate()
	add_child(menu)
	await _settle()
	var guide: TitleTutorialController = menu.title_tutorial_controller
	_check(guide != null and guide.phase == TitleTutorialController.Phase.WELCOME, "first menu must automatically enter title guidance")
	_check(not PlayerData.startup_tutorial_pending, "title introduction must consume the session flag")
	_check(menu.start_battle_btn.disabled and menu.card_editor_btn.disabled and menu.my_cards_btn.disabled,
			"unrelated menu actions must be gated until start or skip")
	guide._on_next()
	_check(guide.phase == TitleTutorialController.Phase.CONTRAST and guide.next_button.disabled,
			"contrast selection must follow welcome, before the menu tour")
	guide._on_next()
	_check(guide.phase == TitleTutorialController.Phase.CONTRAST, "Next must wait for a contrast choice")
	var original_contrast: bool = AppPreferences.get_value("high_contrast")
	guide.high_contrast_button.pressed.emit()
	var preferences := ConfigFile.new()
	_check(not guide.next_button.disabled and preferences.load(AppPreferences.PATH) == OK
			and bool(preferences.get_value("presentation", "high_contrast", false)),
			"choosing contrast must unlock Next and persist the setting")
	for expected in [TitleTutorialController.Phase.COLLECTION, TitleTutorialController.Phase.BATTLE, TitleTutorialController.Phase.CREATE]:
		guide._on_next()
		_check(guide.phase == expected, "title guide must introduce collection, battle and creation in order")
	var initial_style: Dictionary = guide._button_states[menu.start_battle_btn].duplicate()
	guide._on_skip()
	await _settle()
	_check(progress.status() == "skipped" and not progress.needs_startup_tutorial(), "explicit skip must persist")
	_check(menu.title_tutorial_controller == null and not menu.start_battle_btn.disabled and not menu.card_editor_btn.disabled,
			"skip must restore the original title menu")
	_check(menu.start_battle_btn.has_theme_stylebox_override("disabled") == initial_style.style_override
			and menu.start_battle_btn.get_theme_stylebox("disabled") == initial_style.style
			and menu.start_battle_btn.has_theme_color_override("font_disabled_color") == initial_style.color_override
			and menu.start_battle_btn.get_theme_color("font_disabled_color") == initial_style.color,
			"skip must restore original disabled theme overrides")
	menu.free()
	bootstrap._startup_target(PackedStringArray())
	_check(not PlayerData.startup_tutorial_pending, "a skipped first launch must not force guidance after restart")
	menu = MenuScene.instantiate()
	add_child(menu)
	await _settle()
	_check(menu.title_tutorial_controller == null, "returning players must see the normal menu")
	var busy := UIMotion._busy
	UIMotion._busy = true
	menu._on_tutorial_pressed()
	UIMotion._busy = busy
	_check(PlayerData.skill_tutorial_active and PlayerData.tutorial_editor_stage == "card_basics", "skipping must keep manual replay available")
	PlayerData.cancel_skill_tutorial()
	menu.free()

	# Closing an unfinished introduction must survive the newly-created library.
	progress.clear()
	PlayerData.had_saved_library_on_startup = false
	bootstrap._startup_target(PackedStringArray())
	menu = MenuScene.instantiate()
	add_child(menu)
	await _settle()
	menu.free()
	PlayerData.had_saved_library_on_startup = true
	bootstrap._startup_target(PackedStringArray())
	_check(PlayerData.startup_tutorial_pending, "pending marker must survive restart even though the default library now exists")
	progress.mark_editor_completed()
	progress.mark_completed()
	bootstrap._startup_target(PackedStringArray())
	_check(not PlayerData.startup_tutorial_pending and progress.editor_completed(), "full completion must suppress startup without losing chapter progress")

	for status in ["completed", "skipped"]:
		var cfg := ConfigFile.new()
		cfg.set_value("tutorial", "schema", 2)
		cfg.set_value("tutorial", "status", status)
		cfg.set_value("tutorial", "editor_completed", true)
		cfg.set_value("custom", "keep", "unchanged")
		cfg.save(path)
		_check(progress.initialize_startup(false) == OK and progress.status() == status and progress.editor_completed() and not progress.needs_startup_tutorial(),
				"legacy finished progress must be compatible: " + status)
		cfg.load(path)
		_check(cfg.get_value("custom", "keep") == "unchanged", "migration must preserve unrelated progress")
	progress.clear()
	_check(progress.initialize_startup(true) == OK and not progress.needs_startup_tutorial() and progress.status() == "never",
			"an existing library without a tutorial marker must migrate without forced guidance")
	progress.clear()
	PlayerData.startup_tutorial_pending = false
	for flag in ["--server", "--room-server"]:
		_check(bootstrap._startup_target(PackedStringArray([flag])) == "res://server.tscn" and not FileAccess.file_exists(path) and not PlayerData.startup_tutorial_pending,
				"server startup must bypass client onboarding: " + flag)
	_check(FileAccess.get_sha256(PlayerData.save_path) == library_hash, "first-launch checks and manual replay must not rewrite the collection")
	await _verify_exit_during_summon()
	bootstrap.free()
	PlayerData.tutorial_progress_path = original_path
	PlayerData.startup_tutorial_pending = original_pending
	PlayerData.had_saved_library_on_startup = original_existing
	AppPreferences.set_value("high_contrast", original_contrast)
	if failures.is_empty():
		print("TEST_FIRST_LAUNCH_TUTORIAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_FIRST_LAUNCH_TUTORIAL_FAILED: " + failure)
		get_tree().quit(1)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _verify_exit_during_summon() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var slot := Control.new()
	slot.size = Vector2(120, 160)
	layer.add_child(slot)
	var before := get_tree().get_processed_tweens()
	BattleFx.summon_landing(layer, slot)
	var landing: Tween
	for tween in get_tree().get_processed_tweens():
		if tween not in before:
			landing = tween
	_check(landing != null, "summoning must retain its landing feedback")
	layer.free()
	await _settle()
	_check(landing != null and not landing.is_valid(), "exiting during summon must cancel the delayed layer callback")
	await get_tree().create_timer(0.25).timeout


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
