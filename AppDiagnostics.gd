extends Node

const DIRECTORY := "user://logs"
var previous_unclean_exit := false
var _marker := ""
var _notice_shown := false
var _frame_trace: FileAccess
var _last_draw_usec := 0
var _sample_begin_usec := 0
var _sample_begin_process_frame := 0
var _draw_intervals := PackedFloat32Array()
var _gpu_render_times := PackedFloat32Array()
var _cpu_render_times := PackedFloat32Array()
var _trace_viewport: RID
var _drag_frames := 0

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
	if OS.has_feature("windows") and DisplayServer.get_name() != "headless" \
			and OS.get_cmdline_user_args().has("--trace-battle-frames"):
		_start_frame_trace()

func _start_frame_trace() -> void:
	var path := DIRECTORY.path_join("battle-frames-%d-%d.jsonl" % [OS.get_process_id(), Time.get_ticks_msec()])
	_frame_trace = FileAccess.open(path, FileAccess.WRITE)
	if _frame_trace == null:
		push_warning("Could not open frame diagnostics log: " + ProjectSettings.globalize_path(path))
		return
	_frame_trace.store_line(JSON.stringify({
		"version": AppVersion.VERSION, "engine": Engine.get_version_info().string,
		"started_utc": Time.get_datetime_string_from_system(true),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
	}))
	_frame_trace.flush()
	_trace_viewport = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_trace_viewport, true)
	RenderingServer.frame_post_draw.connect(_sample_draw)

func _sample_draw() -> void:
	var now := Time.get_ticks_usec()
	var process_frame := Engine.get_process_frames()
	if _sample_begin_usec == 0:
		_sample_begin_usec = now
		_sample_begin_process_frame = process_frame
	if _last_draw_usec > 0:
		_draw_intervals.append(float(now - _last_draw_usec) / 1000.0)
		_cpu_render_times.append(RenderingServer.viewport_get_measured_render_time_cpu(_trace_viewport))
		_gpu_render_times.append(RenderingServer.viewport_get_measured_render_time_gpu(_trace_viewport))
		_drag_frames += int(get_viewport().gui_is_dragging())
	_last_draw_usec = now
	if now - _sample_begin_usec < 1_000_000:
		return
	_draw_intervals.sort()
	_cpu_render_times.sort()
	_gpu_render_times.sort()
	var count := _draw_intervals.size()
	var p95 := int((count - 1) * 0.95)
	var scene := get_tree().current_scene
	var elapsed := float(now - _sample_begin_usec) / 1_000_000.0
	_frame_trace.store_line(JSON.stringify({
		"elapsed_ms": Time.get_ticks_msec(), "render_fps": count / elapsed,
		"process_fps": (process_frame - _sample_begin_process_frame) / elapsed,
		"scene": scene.scene_file_path if scene != null else "", "battle_mode": PlayerData.battle_mode,
		"p95_ms": _draw_intervals[p95], "max_ms": _draw_intervals[count - 1],
		"render_cpu_p95_ms": _cpu_render_times[p95], "render_gpu_p95_ms": _gpu_render_times[p95],
		"drag_frames": _drag_frames, "focused": get_window().has_focus(),
		"resolution": str(get_window().size), "window_mode": int(get_window().mode),
		"vsync": int(DisplayServer.window_get_vsync_mode()), "fps_limit": Engine.max_fps,
	}))
	_frame_trace.flush()
	_sample_begin_usec = now
	_sample_begin_process_frame = process_frame
	_draw_intervals.clear()
	_cpu_render_times.clear()
	_gpu_render_times.clear()
	_drag_frames = 0

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
