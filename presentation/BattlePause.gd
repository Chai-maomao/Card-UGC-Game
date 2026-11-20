extends "res://SelectionMenu.gd"

var battle: Node
var paused_here := false
var settings_only := false
var _settings_layer: CanvasLayer

func _ready() -> void:
	add_to_group("battle_modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 180
	paused_here = not PlayerData.is_online_battle()
	if paused_here: get_tree().paused = true
	if settings_only:
		_show_settings_on(self)
		return
	heading = Locale.t("preferences.pause" if paused_here else "preferences.online_pause")
	backdrop = Color(Color.BLACK, 0.68)
	blur_backdrop = true
	super._ready()
	add_choice(Locale.t("preferences.resume"), dismiss)
	add_choice(Locale.t("preferences.settings"), _settings)
	add_choice(Locale.t("preferences.leave"), _confirm_leave)
	finish(false)
	UITheme.fade_enter(surface, 0.16)
	UIMotion.register_popup(self)


func viewport_changed() -> void:
	super.viewport_changed()
	var table := battle.get("tabletop") as Node3D
	if is_instance_valid(table):
		var screen := get_viewport().get_visible_rect().size
		var origin := surface.transform.origin
		var axis := tabletop_axis(table, origin)
		place(Transform2D(Vector2.RIGHT, axis, origin), minf(screen.x / 1152.0, screen.y / 648.0))


func _confirm_leave() -> void:
	battle._show_abandon_confirmation(layer + 2, func():
		if paused_here:
			get_tree().paused = false
		queue_free())

func _exit_tree() -> void:
	if paused_here: get_tree().paused = false

func _settings() -> void:
	if is_instance_valid(_settings_layer): return
	var layer_node := CanvasLayer.new()
	layer_node.layer = layer+1
	layer_node.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer_node)
	_show_settings_on(layer_node)

func _show_settings_on(layer_node: CanvasLayer) -> void:
	_settings_layer = layer_node
	var settings := preload("res://SettingsMenu.tscn").instantiate()
	settings.embedded_close = _close_settings.bind(layer_node, settings)
	layer_node.set_meta("popup_close", settings.embedded_close)
	layer_node.set_meta("popup_close_animated", true)
	layer_node.add_child(settings)
	UITheme.fade_enter(settings, 0.18)
	UIMotion.register_popup(layer_node)


func _close_settings(layer_node: CanvasLayer, settings: Control) -> void:
	if layer_node.get_meta("popup_close_locked", false):
		return
	if AppPreferences.get_value("reduced_motion"):
		layer_node.queue_free()
		return
	layer_node.set_meta("popup_close_locked", true)
	var fade_in: Tween = settings.get_meta("ui_fade") if settings.has_meta("ui_fade") else null
	if fade_in != null and fade_in.is_valid(): fade_in.kill()
	settings.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	var cover := ColorRect.new()
	cover.color = Color.TRANSPARENT
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.add_child(cover)
	var tween := layer_node.create_tween()
	tween.tween_property(settings, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(layer_node.queue_free)
