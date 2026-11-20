extends Control

const SEND_PERIOD_MS := 100
const KEEPALIVE_MS := 650
const HIDE_AFTER_MS := 1500

var opposing_lane: Control
var own_lane: Control
var can_share: Callable
var _local_cursor := NetworkManager.CURSOR_HIDDEN
var _last_sent := NetworkManager.CURSOR_HIDDEN
var _remote_cursor := NetworkManager.CURSOR_HIDDEN
var _next_send_at := 0
var _last_sent_at := 0
var _expires_at := 0
var _drawn_at := Vector2.ZERO
var _caption: Label


func _ready() -> void:
	name = "OpponentCursor"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 75
	_caption = Label.new()
	_caption.text = Locale.t("chat.opponent_cursor")
	_caption.position = Vector2(16, 19)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.add_theme_color_override("font_color", UITheme.Tokens.MUTED)
	_caption.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.03, 0.85))
	_caption.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_caption)
	Locale.language_changed.connect(func(): _caption.text = Locale.t("chat.opponent_cursor"))
	NetworkManager.battle_cursor_received.connect(_receive)
	get_window().mouse_exited.connect(func(): _local_cursor = NetworkManager.CURSOR_HIDDEN)
	hide()


func _draw() -> void:
	draw_texture(UIMotion.GAME_CURSOR, -UIMotion.GAME_CURSOR_HOTSPOT, Color(0.68, 0.64, 0.57, 0.9))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_local_cursor = event.position


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var active := can_share.call() as bool and NetworkManager.battle_chat_supported and UIMotion.top_popup() == null
	if now >= _next_send_at:
		_next_send_at = now + SEND_PERIOD_MS
		var outgoing := _encode(_local_cursor) if active else NetworkManager.CURSOR_HIDDEN
		if outgoing != _last_sent or (outgoing != NetworkManager.CURSOR_HIDDEN and now - _last_sent_at >= KEEPALIVE_MS):
			NetworkManager.send_battle_cursor(outgoing)
			_last_sent_at = now
			_last_sent = outgoing
	if not active or _remote_cursor == NetworkManager.CURSOR_HIDDEN or now >= _expires_at:
		hide()
		return
	var target := _decode(Vector2(_remote_cursor.x, 1.0 - _remote_cursor.y))
	_drawn_at = _drawn_at.lerp(target, 1.0 - exp(-22.0 * delta)) if visible and not AppPreferences.get_value("reduced_motion") else target
	position = _drawn_at
	show()


func _receive(point: Vector2) -> void:
	_remote_cursor = point
	_expires_at = Time.get_ticks_msec() + HIDE_AFTER_MS


func _lane_rect(lane: Control) -> Rect2:
	var first := lane.get_child(0) as Control
	var last := lane.get_child(-1) as Control
	return first.get_global_rect().merge(last.get_global_rect())


func _encode(at: Vector2) -> Vector2:
	var far := _lane_rect(opposing_lane)
	var near := _lane_rect(own_lane)
	if at.y < far.position.y or at.y > near.end.y:
		return NetworkManager.CURSOR_HIDDEN
	var y: float
	if at.y < far.end.y:
		y = inverse_lerp(far.position.y, far.end.y, at.y) / 3.0
	elif at.y < near.position.y:
		y = (1.0 + inverse_lerp(far.end.y, near.position.y, at.y)) / 3.0
	else:
		y = (2.0 + inverse_lerp(near.position.y, near.end.y, at.y)) / 3.0
	var across := clampf(y * 3.0 - 1.0, 0.0, 1.0)
	var left := lerpf(far.position.x, near.position.x, across)
	var right := lerpf(far.end.x, near.end.x, across)
	if at.x < left or at.x > right:
		return NetworkManager.CURSOR_HIDDEN
	return Vector2(inverse_lerp(left, right, at.x), y)


func _decode(point: Vector2) -> Vector2:
	var far := _lane_rect(opposing_lane)
	var near := _lane_rect(own_lane)
	var band := point.y * 3.0
	var across := clampf(band - 1.0, 0.0, 1.0)
	var x := lerpf(lerpf(far.position.x, near.position.x, across), lerpf(far.end.x, near.end.x, across), point.x)
	var y: float
	if band < 1.0:
		y = lerpf(far.position.y, far.end.y, band)
	elif band < 2.0:
		y = lerpf(far.end.y, near.position.y, band - 1.0)
	else:
		y = lerpf(near.position.y, near.end.y, band - 2.0)
	return Vector2(x, y)
