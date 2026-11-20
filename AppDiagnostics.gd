extends Node

const DIRECTORY := "user://logs"
var previous_unclean_exit := false
var _marker := ""
var _notice_shown := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--diagnostics-test"): return
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	for name in DirAccess.get_files_at(DIRECTORY):
		if not name.begins_with("session-") or not name.ends_with(".json"): continue
		var path := DIRECTORY.path_join(name)
		var old = JSON.parse_string(FileAccess.get_file_as_string(path))
		var pid := int(name.trim_prefix("session-").trim_suffix(".json"))
		if old is Dictionary: pid = int(old.get("pid",pid))
		# The Android launcher runs one game process. Old sessions are not
		# child processes that the Unix process-status API can inspect.
		if OS.has_feature("android") or not OS.is_process_running(pid):
			previous_unclean_exit = true
			DirAccess.remove_absolute(path)
	_marker = DIRECTORY.path_join("session-%d.json" % OS.get_process_id())
	_write_marker()
	get_tree().scene_changed.connect(_notify_unclean_exit,CONNECT_ONE_SHOT)
	get_tree().create_timer(0.4).timeout.connect(_notify_unclean_exit)

func _write_marker() -> void:
	var file := FileAccess.open(_marker,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"pid":OS.get_process_id(),"version":AppVersion.VERSION,"started":Time.get_datetime_string_from_system(true)}))

func _notification(what: int) -> void:
	if _marker.is_empty() or not OS.has_feature("android"): return
	# Android can reclaim a background activity without sending an exit signal.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		DirAccess.remove_absolute(_marker)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_write_marker()

func _notify_unclean_exit() -> void:
	if not previous_unclean_exit or _notice_shown: return
	_notice_shown = true
	var dialog := AcceptDialog.new()
	dialog.title = Locale.t("support.previous_title")
	dialog.dialog_text = Locale.t("support.previous_body")
	get_tree().root.add_child(dialog)
	UITheme.apply_dialog(dialog,true)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(460, 0))

func summary() -> String:
	# Whitelist only. Never include active room files, card data, host/IP, or raw logs.
	return JSON.stringify({"version":AppVersion.VERSION,"protocol":AppVersion.PROTOCOL_VERSION,"engine":Engine.get_version_info().string,"os":OS.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"quality":AppPreferences.get_value("quality"),"window":str(get_window().size),"previous_unclean_exit":previous_unclean_exit},"  ")

func copy_summary() -> void:
	DisplayServer.clipboard_set(summary())

func open_logs() -> void:
	OS.shell_open(ProjectSettings.globalize_path(DIRECTORY))

func open_saves() -> void:
	OS.shell_open(OS.get_user_data_dir())

func _exit_tree() -> void:
	if not _marker.is_empty(): DirAccess.remove_absolute(_marker)
