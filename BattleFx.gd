extends Node
# ============================================
# BattleFx — autoload. Owns all low-level battlefield visual effects:
# procedural FX textures, an object pool for reusable effect nodes, and shared
# timing/easing constants. Main.gd only orchestrates where effects appear.
# ============================================

# --- Shared timing / easing constants (统一时长) ---
const RING_TIME := 0.22
const RING_SCALE := 2.2
const GLOW_DOT_SIZE := 22.0
const CARD_BACK_SIZE := Vector2(52, 72)
const COMBAT_TEXT_RISE_TIME := 0.82
const PROJECTILE_TIME := 0.35
const BANNER_HOLD := 0.9
const CARD_DRAW_STAGGER := 0.065
const CARD_DRAW_TRAVEL_TIME := 0.40

# --- Procedural FX textures (generated once) ---
var _glow_dot: Texture2D = null
var _ring_tex: Texture2D = null
var _card_back_tex: Texture2D = null
var _slash_tex: Texture2D = null

# --- Object pools: key -> Array[Control] ---
var _pool: Dictionary = {}

# --- Shared card-feedback state (per target instance) ---
# Hit flashes and skill pulses can interrupt each other. Keeping one baseline
# prevents an in-progress red/green/blue tint from becoming the next effect's
# permanent resting color.
var _hit_targets: Dictionary = {}

const _card_ui_scene = preload("res://CardUI.tscn")


func _ensure_textures() -> void:
	if _glow_dot != null:
		return
	_glow_dot = _make_glow_texture(64)
	_ring_tex = _make_ring_texture(96)
	_card_back_tex = _make_card_back_texture(120, 168)
	_slash_tex = _make_slash_texture(128)


func _ready() -> void:
	# Battle-field hit-flash bookkeeping must not leak across battles.
	if not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)


func _on_scene_changed() -> void:
	_hit_targets.clear()


func _exit_tree() -> void:
	# Pooled controls are detached from the tree, so normal scene teardown does
	# not own them. Explicitly release them when the effects service shuts down.
	for pool: Array in _pool.values():
		for node in pool:
			if is_instance_valid(node):
				node.free()
	_pool.clear()
	_hit_targets.clear()


func _make_glow_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := size * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var t := clampf(1.0 - d / radius, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)  # smoothstep
			img.set_pixel(x, y, Color(1, 1, 1, t))
	return ImageTexture.create_from_image(img)


func _make_ring_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := size * 0.42
	var band := size * 0.11
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var t := absf(d - radius) / band
			var a := clampf(1.0 - t, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _make_card_back_texture(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var corner := 10.0
	var border := 3.0
	for y in range(h):
		for x in range(w):
			var rx := clampf(x, corner, w - 1.0 - corner)
			var ry := clampf(y, corner, h - 1.0 - corner)
			var d := Vector2(x, y).distance_to(Vector2(rx, ry))
			if d > corner:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if d > corner - border:
				img.set_pixel(x, y, Color(0.95, 0.78, 0.32, 0.98))
				continue
			var shine := clampf(1.0 - float(y) / (h * 0.35), 0.0, 1.0) * 0.18
			img.set_pixel(x, y, Color(0.13 + shine, 0.19 + shine, 0.34 + shine, 0.96))
	return ImageTexture.create_from_image(img)


# Crescent "slash" arc, drawn pointing +X; rotated per use to follow the hit
# direction. Brightest near the leading edge, fading toward the handle.
func _make_slash_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var r_in := size * 0.16
	var r_out := size * 0.46
	var half_angle := deg_to_rad(40.0)
	for y in range(size):
		for x in range(size):
			var v := Vector2(x + 0.5, y + 0.5) - center
			var d := v.length()
			if d < r_in or d > r_out:
				continue
			var ang := absf(v.angle())
			if ang > half_angle:
				continue
			var radial := 1.0 - (d - r_in) / (r_out - r_in)
			var angular := 1.0 - ang / half_angle
			var a := radial * (0.35 + 0.65 * angular)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# ============ Object pool ============

func _acquire_control(key: String, factory: Callable) -> Control:
	var pool: Array = _pool.get(key, [])
	while not pool.is_empty():
		var node: Control = pool.pop_back()
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.visible = true
			node.scale = Vector2.ONE
			node.modulate = Color.WHITE
			node.position = Vector2.ZERO
			node.rotation = 0.0
			node.pivot_offset = Vector2.ZERO
			return node
	var node: Control = factory.call()
	if not _pool.has(key):
		_pool[key] = []
	return node


func _release(key: String, node) -> void:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	node.visible = false
	node.scale = Vector2.ONE
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	if not _pool.has(key):
		_pool[key] = []
	_pool[key].append(node)


# ============ Effects ============

func impact_ring(layer, center: Vector2, damage: bool = true, tint: Color = Color(), ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var base_color: Color
	if tint.a > 0.0:
		base_color = tint
	elif damage:
		base_color = Color(1.0, 0.22, 0.12, 0.85)
	else:
		base_color = Color(0.35, 1.0, 0.58, 0.70)
	var size := Vector2(46, 46) * ui_scale
	var ring := _acquire_control("ring", func() -> Control:
		var r := TextureRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.texture = _ring_tex
		return r) as TextureRect
	ring.texture = _ring_tex
	ring.size = size
	ring.pivot_offset = size / 2
	ring.position = center - size / 2
	ring.modulate = base_color
	layer.add_child(ring)
	layer.move_child(ring, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(ring, "scale", Vector2(RING_SCALE, RING_SCALE), RING_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(ring, "modulate:a", 0.0, RING_TIME)
	twn.chain().tween_callback(_release.bind("ring", ring))


func heal_particles(layer: CanvasLayer, center: Vector2, amount: int, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var particles := GPUParticles2D.new()
	particles.texture = _glow_dot
	particles.amount = clampi(6 + amount, 8, 16)
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.position = center
	particles.modulate = Color(0.38, 1.0, 0.58)
	particles.scale = Vector2(ui_scale, ui_scale)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 55.0
	mat.gravity = Vector3(0, -160, 0)
	mat.initial_velocity_min = 60.0
	mat.initial_velocity_max = 110.0
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	particles.process_material = mat
	layer.add_child(particles)
	layer.move_child(particles, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.tween_interval(particles.lifetime + 0.2)
	twn.tween_callback(particles.queue_free)


# Compact HUD feedback shared by hero HP and elixir bars. It overlays the
# existing bar rather than restyling the whole status panel, preserving the
# battle UI's restrained red/cyan/gold language.
func status_bar_feedback(layer: CanvasLayer, bar: ProgressBar, delta: int, kind: String, ui_scale: float = 1.0) -> void:
	if layer == null or bar == null or delta == 0:
		return
	_ensure_textures()
	var tint := Color(1.0, 0.31, 0.28) if kind == "damage" else (Color(0.36, 1.0, 0.64) if kind == "heal" else Color(0.30, 0.84, 1.0))
	var padding := 3.0 * ui_scale
	var overlay := Panel.new()
	overlay.name = "StatusFx_%s" % kind.capitalize()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.position = bar.global_position - Vector2(padding, padding)
	overlay.size = bar.size + Vector2(padding * 2.0, padding * 2.0)
	overlay.pivot_offset = overlay.size * 0.5
	overlay.scale = Vector2(0.985, 0.72)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.10)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.90)
	style.set_border_width_all(maxi(1, int(round(ui_scale))))
	style.set_corner_radius_all(maxi(5, int(round(7.0 * ui_scale))))
	style.shadow_color = Color(tint.r, tint.g, tint.b, 0.22)
	style.shadow_size = maxi(1, int(round(3.0 * ui_scale)))
	overlay.add_theme_stylebox_override("panel", style)
	layer.add_child(overlay)
	layer.move_child(overlay, layer.get_child_count() - 1)

	var value_label := Label.new()
	value_label.name = "StatusFxValue"
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.text = "%+d" % delta
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", maxi(10, int(round(12.0 * ui_scale))))
	value_label.add_theme_color_override("font_color", tint.lightened(0.18))
	value_label.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.045, 0.95))
	value_label.add_theme_constant_override("outline_size", maxi(2, int(round(3.0 * ui_scale))))
	value_label.size = Vector2(58, 22) * ui_scale
	value_label.position = bar.global_position + Vector2((bar.size.x - value_label.size.x) * 0.5, -4.0 * ui_scale)
	value_label.modulate.a = 0.0
	layer.add_child(value_label)
	layer.move_child(value_label, layer.get_child_count() - 1)

	var particles := GPUParticles2D.new()
	particles.name = "StatusFxParticles_%s" % kind.capitalize()
	particles.texture = _glow_dot
	particles.amount = 7 if kind != "damage" else 5
	particles.lifetime = 0.46
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.position = bar.global_position + Vector2(bar.size.x * (0.62 if delta > 0 else 0.42), bar.size.y * 0.5)
	particles.modulate = tint
	particles.scale = Vector2(ui_scale, ui_scale)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(minf(28.0 * ui_scale, bar.size.x * 0.22), 1.5 * ui_scale, 1.0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 48.0
	mat.gravity = Vector3(0, -38, 0)
	mat.initial_velocity_min = 18.0 * ui_scale
	mat.initial_velocity_max = 44.0 * ui_scale
	mat.scale_min = 0.08
	mat.scale_max = 0.18
	particles.process_material = mat
	layer.add_child(particles)
	layer.move_child(particles, layer.get_child_count() - 1)

	var twn := create_tween().set_parallel(true)
	twn.tween_property(overlay, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.tween_property(overlay, "modulate:a", 0.0, 0.26).set_delay(0.20)
	twn.tween_property(value_label, "modulate:a", 1.0, 0.07)
	twn.tween_property(value_label, "position:y", value_label.position.y - 13.0 * ui_scale, 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(value_label, "modulate:a", 0.0, 0.18).set_delay(0.32)
	twn.chain().tween_callback(overlay.queue_free)
	twn.chain().tween_callback(value_label.queue_free)
	var particle_cleanup := create_tween()
	particle_cleanup.tween_interval(particles.lifetime + 0.12)
	particle_cleanup.tween_callback(particles.queue_free)


func combat_text(layer: CanvasLayer, pos: Vector2, delta: int, strong: bool = false, ui_scale: float = 1.0) -> void:
	if layer == null or delta == 0:
		return
	var is_damage: bool = delta < 0
	var is_crit: bool = strong and is_damage
	var lbl := _acquire_control("text", func() -> Control:
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return l) as Label
	lbl.text = ("-%d" % -delta) if is_damage else ("+%d" % delta)
	# Big damage hits render in a hot orange to read as critical hits.
	var font_color: Color
	var outline_color: Color
	if is_crit:
		font_color = Color(1.0, 0.42, 0.08)
		outline_color = Color(0.18, 0.05, 0.0, 0.95)
	elif is_damage:
		font_color = Color(1.0, 0.22, 0.12)
		outline_color = Color(0.08, 0.02, 0.01, 0.95)
	else:
		font_color = Color(0.35, 1.0, 0.58)
		outline_color = Color(0.02, 0.08, 0.03, 0.95)
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_color_override("font_outline_color", outline_color)
	lbl.add_theme_constant_override("outline_size", 6 if is_crit else (5 if strong else 4))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.add_theme_font_size_override("font_size", 48 if is_crit else (42 if strong else 34))
	lbl.pivot_offset = Vector2(34, 20)
	lbl.rotation = randf_range(-0.045, 0.045)
	var side_offset: Vector2 = Vector2(16, -30) if is_damage else Vector2(-16, -26)
	var random_offset := Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 12.0))
	lbl.position = pos + side_offset + random_offset
	lbl.scale = Vector2(0.55, 0.55) if is_damage else Vector2(0.68, 0.68)
	lbl.modulate.a = 0.0
	layer.add_child(lbl)
	layer.move_child(lbl, layer.get_child_count() - 1)

	var rise: float = (56.0 if is_damage else 68.0) + randf_range(-6.0, 8.0)
	var drift: float = (12.0 if is_damage else -10.0) + randf_range(-18.0, 18.0)
	var peak_scale: Vector2 = Vector2(1.62, 1.62) if is_crit else (Vector2(1.55, 1.55) if strong and is_damage else (Vector2(1.34, 1.34) if is_damage else Vector2(1.18, 1.18)))
	var settle_scale: Vector2 = Vector2(1.14, 1.14) if is_damage else Vector2(1.0, 1.0)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(lbl, "modulate:a", 1.0, 0.07)
	twn.tween_property(lbl, "scale", peak_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.tween_property(lbl, "position", lbl.position + Vector2(drift, -rise), COMBAT_TEXT_RISE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	twn.tween_property(lbl, "scale", settle_scale, 0.18).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(lbl, "modulate:a", 0.0, 0.28).set_delay(0.50)
	twn.chain().tween_callback(_release.bind("text", lbl))


func spawn_draw_fly_card(layer: CanvasLayer, start: Vector2, target: Vector2, index: int, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var size := CARD_BACK_SIZE * ui_scale
	var card_back := _acquire_control("card_back", func() -> Control:
		var c := TextureRect.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.texture = _card_back_tex
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return c)
	card_back.texture = _card_back_tex
	card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_back.size = size
	card_back.pivot_offset = size / 2
	card_back.position = start - size / 2
	card_back.scale = Vector2(0.78, 0.78)
	card_back.rotation = deg_to_rad(-5.0)
	card_back.modulate = Color(0.84, 0.90, 1.0, 0.0)
	card_back.set_meta("battle_fx_kind", "draw_card")
	layer.add_child(card_back)
	layer.move_child(card_back, layer.get_child_count() - 1)
	var direction := signf(target.x - start.x) if absf(target.x - start.x) > 1.0 else 1.0
	var lift: float = -64.0 * ui_scale - minf(index, 4) * 5.0 * ui_scale
	var mid: Vector2 = (start + target) * 0.5 + Vector2(-18.0 * direction * ui_scale, lift)
	var end_position := target - size / 2
	var duration_scale := GamePreferences.battle_animation_duration_scale()
	var launch_time := CARD_DRAW_TRAVEL_TIME * 0.44 * duration_scale
	var settle_time := CARD_DRAW_TRAVEL_TIME * 0.56 * duration_scale
	var twn := layer.create_tween()
	twn.set_parallel(false)
	twn.tween_interval(index * card_draw_stagger())
	twn.tween_property(card_back, "modulate", Color.WHITE, 0.045 * duration_scale)
	twn.parallel().tween_property(card_back, "scale", Vector2(1.06, 1.06), launch_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.parallel().tween_property(card_back, "rotation", deg_to_rad(3.5) * direction, launch_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.parallel().tween_property(card_back, "position", mid - size / 2, launch_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_back, "position", end_position, settle_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	twn.parallel().tween_property(card_back, "rotation", 0.0, settle_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	twn.parallel().tween_property(card_back, "scale", Vector2(0.90, 0.90), settle_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var fade_time := 0.10 * duration_scale
	twn.parallel().tween_property(card_back, "modulate:a", 0.0, fade_time).set_delay(maxf(0.0, settle_time - fade_time))
	twn.chain().tween_callback(_release.bind("card_back", card_back))


func card_draw_stagger() -> float:
	return CARD_DRAW_STAGGER * GamePreferences.battle_animation_duration_scale()


func draw_card_arrival_delay(index: int) -> float:
	var duration_scale := GamePreferences.battle_animation_duration_scale()
	return (0.045 + CARD_DRAW_TRAVEL_TIME) * duration_scale + maxi(0, index) * card_draw_stagger()


func travel_card_arrival_delay(index: int) -> float:
	var duration_scale := GamePreferences.battle_animation_duration_scale()
	return 0.53 * duration_scale + maxi(0, index) * card_draw_stagger()


# Move a face-up card preview between two UI locations. The caller owns the
# visual construction so this stays reusable for pile selection, charm and
# generated-card effects without coupling BattleFx to CardUI.
func travel_card_control(layer: CanvasLayer, card_ghost: Control, start: Vector2, target: Vector2, index: int = 0, ui_scale: float = 1.0) -> void:
	if layer == null or card_ghost == null or not is_instance_valid(card_ghost):
		return
	layer.add_child(card_ghost)
	layer.move_child(card_ghost, layer.get_child_count() - 1)
	card_ghost.pivot_offset = card_ghost.size / 2
	card_ghost.position = start - card_ghost.size / 2
	card_ghost.modulate.a = 0.0
	card_ghost.set_meta("battle_fx_kind", "travel_card")
	var lift: float = -62.0 * ui_scale - index * 6.0
	var mid: Vector2 = (start + target) * 0.5 + Vector2(0, lift)
	var duration_scale := GamePreferences.battle_animation_duration_scale()
	var duration: float = 0.46 * duration_scale
	var twn := layer.create_tween()
	twn.tween_interval(index * card_draw_stagger())
	twn.tween_property(card_ghost, "modulate:a", 1.0, 0.07 * duration_scale)
	twn.parallel().tween_property(card_ghost, "scale", card_ghost.scale * 1.05, 0.10 * duration_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_ghost, "position", mid - card_ghost.size / 2, duration * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_ghost, "position", target - card_ghost.size / 2, duration * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.parallel().tween_property(card_ghost, "scale", card_ghost.scale * 0.78, duration * 0.55)
	twn.parallel().tween_property(card_ghost, "modulate:a", 0.0, 0.14 * duration_scale).set_delay(duration * 0.36)
	twn.tween_callback(card_ghost.queue_free)


func spell_cast_projectile(layer: CanvasLayer, start: Vector2, end: Vector2, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var dot := _acquire_control("projectile", func() -> Control:
		var d := TextureRect.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.texture = _glow_dot
		return d)
	dot.texture = _glow_dot
	dot.modulate = Color(0.55, 0.8, 1.0, 0.95)
	var dot_size := Vector2(GLOW_DOT_SIZE, GLOW_DOT_SIZE) * ui_scale
	dot.size = dot_size
	dot.pivot_offset = dot_size / 2
	dot.position = start - dot_size / 2
	layer.add_child(dot)
	layer.move_child(dot, layer.get_child_count() - 1)
	var mid: Vector2 = (start + end) / 2 + Vector2(0, -40) * ui_scale
	var twn := create_tween()
	twn.tween_method(func(t: float):
		if not is_instance_valid(dot):
			return
		var a := start.lerp(mid, t)
		var b := mid.lerp(end, t)
		dot.global_position = a.lerp(b, t) - dot.size / 2
	, 0.0, 1.0, PROJECTILE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	twn.tween_callback(func():
		if is_instance_valid(dot):
			impact_ring(layer, dot.global_position + dot.size / 2, false, Color(0.45, 0.7, 1.0, 0.5), ui_scale)
			_release("projectile", dot)
	)


func shake_layer(layer: CanvasLayer, strength: float = 2.5) -> void:
	if layer == null:
		return
	var twn := create_tween()
	twn.tween_property(layer, "offset", Vector2(strength, 0), 0.035)
	twn.tween_property(layer, "offset", Vector2(-strength, strength * 0.5), 0.05)
	twn.tween_property(layer, "offset", Vector2(strength * 0.5, -strength * 0.4), 0.045)
	twn.tween_property(layer, "offset", Vector2.ZERO, 0.05)


# Full-screen flash: a quick bright tint that decays, for heavy hits and
# results. Non-blocking and pooled.
func screen_flash(layer: CanvasLayer, tint: Color = Color(1.0, 0.95, 0.8), alpha: float = 0.18, duration: float = 0.16) -> void:
	if layer == null or alpha <= 0.0:
		return
	var rect := _acquire_control("flash", func() -> Control:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.anchor_right = 1.0
		r.anchor_bottom = 1.0
		return r)
	rect.color = Color(tint.r, tint.g, tint.b, alpha)
	layer.add_child(rect)
	layer.move_child(rect, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.tween_property(rect, "color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_callback(_release.bind("flash", rect))


# Crescent slash arc at the point of impact, oriented along the attack
# direction. Pairs with impact_ring for a crisp hit.
func attack_slash(layer: CanvasLayer, center: Vector2, direction: Vector2, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var slash := _acquire_control("slash", func() -> Control:
		var s := TextureRect.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.texture = _slash_tex
		return s)
	var size := Vector2(96, 96) * ui_scale
	slash.size = size
	slash.pivot_offset = size / 2
	slash.position = center - size / 2
	slash.rotation = direction.angle()
	slash.modulate = Color(1.0, 0.97, 0.88, 0.95)
	slash.scale = Vector2(0.35, 0.35)
	layer.add_child(slash)
	layer.move_child(slash, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(slash, "scale", Vector2(1.25, 1.25), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(slash, "modulate:a", 0.0, 0.20)
	twn.chain().tween_callback(_release.bind("slash", slash))


# Fading motion-trail dot behind a lunging attacker.
func _spawn_trail_dot(layer: CanvasLayer, pos: Vector2, ui_scale: float) -> void:
	if layer == null:
		return
	_ensure_textures()
	var dot := _acquire_control("trail", func() -> Control:
		var d := TextureRect.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.texture = _glow_dot
		return d)
	var size := Vector2(GLOW_DOT_SIZE, GLOW_DOT_SIZE) * ui_scale
	dot.size = size
	dot.pivot_offset = size / 2
	dot.position = pos - size / 2
	dot.modulate = Color(1.0, 0.9, 0.75, 0.8)
	dot.scale = Vector2(0.9, 0.9)
	layer.add_child(dot)
	layer.move_child(dot, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(dot, "scale", Vector2(0.25, 0.25), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(dot, "modulate:a", 0.0, 0.20)
	twn.chain().tween_callback(_release.bind("trail", dot))


# One-shot radial sparkle burst (summons, heals, deaths, victories).
func sparkle_burst(layer, center: Vector2, tint: Color, count: int = 10, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var particles := GPUParticles2D.new()
	particles.texture = _glow_dot
	particles.amount = count
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.position = center
	particles.modulate = tint
	particles.scale = Vector2(ui_scale, ui_scale)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 6.0 * ui_scale
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, -60, 0)
	mat.initial_velocity_min = 40.0 * ui_scale
	mat.initial_velocity_max = 130.0 * ui_scale
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	particles.process_material = mat
	layer.add_child(particles)
	layer.move_child(particles, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.tween_interval(particles.lifetime + 0.25)
	twn.tween_callback(particles.queue_free)


# Small, crisp white motes emitted outwards from all four socket edges. Four
# narrow emitters keep every particle outside the card face instead of making
# dots appear behind the card and travel through its text/buttons.
func card_drop_particles(layer: CanvasLayer, center: Vector2, count: int = 12, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var edge_specs := [
		{"offset": Vector2(0, -83), "extents": Vector3(52, 1.5, 1), "direction": Vector3(0, -1, 0)},
		{"offset": Vector2(0, 83), "extents": Vector3(52, 1.5, 1), "direction": Vector3(0, 1, 0)},
		{"offset": Vector2(-63, 0), "extents": Vector3(1.5, 70, 1), "direction": Vector3(-1, 0, 0)},
		{"offset": Vector2(63, 0), "extents": Vector3(1.5, 70, 1), "direction": Vector3(1, 0, 0)},
	]
	var base_amount := count / edge_specs.size()
	var remainder := count % edge_specs.size()
	for edge_index in range(edge_specs.size()):
		var amount := base_amount + (1 if edge_index < remainder else 0)
		if amount <= 0:
			continue
		_spawn_card_edge_particles(layer, center, edge_specs[edge_index], amount, ui_scale)


func _spawn_card_edge_particles(layer: CanvasLayer, center: Vector2, edge: Dictionary, amount: int, ui_scale: float) -> void:
	var particles := GPUParticles2D.new()
	particles.texture = _glow_dot
	particles.amount = amount
	particles.lifetime = 0.42
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.position = center + (edge.get("offset", Vector2.ZERO) as Vector2) * ui_scale
	particles.modulate = Color(1.0, 1.0, 1.0, 0.96)
	particles.scale = Vector2(ui_scale, ui_scale)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var extents: Vector3 = edge.get("extents", Vector3.ONE)
	mat.emission_box_extents = Vector3(extents.x * ui_scale, extents.y * ui_scale, extents.z)
	mat.direction = edge.get("direction", Vector3.UP)
	mat.spread = 34.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 34.0 * ui_scale
	mat.initial_velocity_max = 66.0 * ui_scale
	mat.scale_min = 0.06
	mat.scale_max = 0.15
	particles.process_material = mat
	layer.add_child(particles)
	layer.move_child(particles, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.tween_interval(particles.lifetime + 0.18)
	twn.tween_callback(particles.queue_free)


# Card death: dark arcane ring + shattering sparkle burst.
func death_burst(layer: CanvasLayer, center: Vector2, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	impact_ring(layer, center, true, Color(0.55, 0.30, 0.75, 0.8), ui_scale)
	sparkle_burst(layer, center, Color(0.62, 0.40, 0.85, 0.95), 12, ui_scale)


# Vertical arcane light pillar at a skill-casting slot.
func skill_cast_beam(layer: CanvasLayer, center: Vector2, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	_ensure_textures()
	var beam := _acquire_control("beam", func() -> Control:
		var b := TextureRect.new()
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.texture = _glow_dot
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		return b)
	var size := Vector2(16, 170) * ui_scale
	beam.size = size
	beam.pivot_offset = size / 2
	beam.position = center - size / 2
	beam.modulate = Color(0.55, 0.82, 1.0, 0.0)
	beam.scale = Vector2.ONE
	layer.add_child(beam)
	layer.move_child(beam, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(beam, "modulate:a", 0.9, 0.10)
	twn.tween_property(beam, "scale", Vector2(1.35, 1.0), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	twn.tween_property(beam, "modulate:a", 0.0, 0.32).set_delay(0.14)
	twn.chain().tween_callback(_release.bind("beam", beam))


# Golden/blue falling confetti raining from the top of the screen (victory).
func victory_confetti(layer: CanvasLayer, ui_scale: float = 1.0, viewport_size: Vector2 = Vector2.ZERO) -> void:
	if layer == null:
		return
	_ensure_textures()
	if viewport_size == Vector2.ZERO:
		viewport_size = Vector2(1152, 648)
	for data in [
		{"tint": Color(1.0, 0.84, 0.35), "amount": 56},
		{"tint": Color(0.55, 0.80, 1.0), "amount": 34},
		{"tint": Color(0.75, 0.95, 1.0), "amount": 26},
	]:
		var particles := GPUParticles2D.new()
		particles.texture = _glow_dot
		particles.amount = data["amount"]
		particles.lifetime = 2.4
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.position = Vector2(viewport_size.x / 2.0, -30.0)
		particles.modulate = data["tint"]
		particles.scale = Vector2(ui_scale, ui_scale)
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(viewport_size.x * 0.55, 8, 1)
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 24.0
		mat.gravity = Vector3(0, 210, 0)
		mat.initial_velocity_min = 50.0
		mat.initial_velocity_max = 140.0
		mat.scale_min = 0.5
		mat.scale_max = 1.1
		mat.damping_min = 20.0
		mat.damping_max = 60.0
		particles.process_material = mat
		layer.add_child(particles)
		layer.move_child(particles, layer.get_child_count() - 1)
		var twn := create_tween()
		twn.tween_interval(particles.lifetime + 0.5)
		twn.tween_callback(particles.queue_free)


func turn_banner(layer: CanvasLayer, text: String, ui_scale: float = 1.0, viewport_size: Vector2 = Vector2.ZERO) -> void:
	if layer == null or text.is_empty():
		return
	if viewport_size == Vector2.ZERO:
		viewport_size = Vector2(1152, 648)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	label.add_theme_font_size_override("font_size", max(22, int(30 * ui_scale)))
	label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", max(2, int(5 * ui_scale)))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.size = Vector2(viewport_size.x, 60 * ui_scale)
	label.position = Vector2(0, viewport_size.y * 0.3)
	label.pivot_offset = label.size / 2
	label.scale = Vector2(0.8, 0.8)
	label.modulate.a = 0.0
	layer.add_child(label)
	layer.move_child(label, layer.get_child_count() - 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(label, "modulate:a", 1.0, 0.16)
	twn.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.tween_property(label, "modulate:a", 0.0, 0.28).set_delay(BANNER_HOLD)
	twn.chain().tween_callback(label.queue_free)


# ============ Animation sequences ============

# Instantiates a fresh card into the layer as a visual ghost for flight/lunge
# animations. The ghost is fully independent, so field UI rebuilds never
# interrupt the effect.
func spawn_card_ghost(layer: CanvasLayer, card_ui, ui_scale: float = 1.0) -> Control:
	if layer == null or card_ui == null or not is_instance_valid(card_ui):
		return null
	var card_data = card_ui.get("current_card_data")
	var ghost: Control = _card_ui_scene.instantiate()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ghost)
	if card_data != null:
		ghost.set_card(card_data)
	if ghost.has_method("apply_ui_scale"):
		ghost.call("apply_ui_scale", ui_scale)
	# Apply the layout above first, then pin the ghost where the field card is.
	ghost.global_position = card_ui.global_position
	ghost.size = card_ui.size
	ghost.scale = card_ui.scale
	layer.move_child(ghost, layer.get_child_count() - 1)
	return ghost


# Three-beat attack animation: attacker lunge toward the target -> impact
# (ring + light screen shake) -> recoil return and fade.
func attack_lunge(layer: CanvasLayer, card_ui, to_center: Vector2, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	var ghost := spawn_card_ghost(layer, card_ui, ui_scale)
	if ghost == null:
		return
	var from_center: Vector2 = card_ui.global_position + card_ui.size / 2
	var base_position: Vector2 = ghost.position
	var delta: Vector2 = to_center - from_center
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(ghost, "position", base_position + delta, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(ghost, "scale", ghost.scale * 1.12, 0.16)
	# Motion trail: fading glow dots left along the lunge path. Positions are
	# computed analytically (no ghost capture) so freeing the ghost later never
	# invalidates this lambda.
	var trail_spawned := [false, false, false]
	twn.tween_method(func(t: float):
		for i in range(trail_spawned.size()):
			var thresh := (i + 1) / float(trail_spawned.size() + 1)
			if not trail_spawned[i] and t >= thresh:
				trail_spawned[i] = true
				_spawn_trail_dot(layer, from_center + delta * t, ui_scale)
	, 0.0, 1.0, 0.16)
	twn.chain().tween_callback(_attack_hit.bind(layer, ghost, base_position, delta, ui_scale))


func _attack_hit(layer, ghost, base_position: Vector2, delta: Vector2, ui_scale: float) -> void:
	if not is_instance_valid(ghost):
		return
	var hit_center: Vector2 = ghost.position + ghost.size / 2
	var direction := delta.normalized() if delta.length() > 1.0 else Vector2.RIGHT
	impact_ring(layer, hit_center, true, Color(), ui_scale)
	attack_slash(layer, hit_center, direction, ui_scale)
	screen_flash(layer, Color(1.0, 0.9, 0.75), 0.14, 0.13)
	shake_layer(layer, 2.5)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(ghost, "position", base_position, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.tween_property(ghost, "scale", ghost.scale * 0.9, 0.11)
	twn.tween_property(ghost, "modulate:a", 0.0, 0.12)
	twn.chain().tween_callback(ghost.queue_free)


# Short socket-lock effect for a freshly summoned card. SlotUI owns the tactile
# seating motion; this service adds effects that must live above the battlefield.
func summon_landing(layer: CanvasLayer, slot_ui, ui_scale: float = 1.0) -> void:
	if layer == null or slot_ui == null or not is_instance_valid(slot_ui):
		return
	var center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	if slot_ui.has_method("play_card_arrival"):
		slot_ui.call("play_card_arrival", "summon")
	var twn := create_tween()
	twn.tween_interval(0.15)
	twn.tween_callback(_summon_landing_finish.bind(layer, center, ui_scale))


func _summon_landing_finish(layer: CanvasLayer, center: Vector2, ui_scale: float) -> void:
	card_drop_particles(layer, center, 12, ui_scale)


# Swap transition for a move: each entry is [card_ui, position_delta] with an
# optional third element [start_pos] that overrides where the ghost begins
# flying from. This lets the non-authority client replay a move after the state
# has already swapped, starting each ghost from the slot the card left.
func move_swap(layer: CanvasLayer, entries: Array, ui_scale: float = 1.0) -> void:
	if layer == null:
		return
	for entry in entries:
		var card_ui = entry[0]
		if card_ui == null or not is_instance_valid(card_ui):
			continue
		var delta: Vector2 = entry[1]
		var start_pos: Vector2 = entry[2] if entry.size() > 2 else Vector2.INF
		var target_slot = entry[3] if entry.size() > 3 else null
		_single_move_ghost(layer, card_ui, delta, ui_scale, start_pos, target_slot)


func _single_move_ghost(layer: CanvasLayer, card_ui, delta: Vector2, ui_scale: float, start_pos: Vector2 = Vector2.INF, target_slot = null) -> void:
	var ghost := spawn_card_ghost(layer, card_ui, ui_scale)
	if ghost == null:
		return
	# Remove the stationary original immediately. After the deferred battlefield
	# refresh creates the destination card, hide that copy too until the flying
	# ghost reaches it; otherwise the player sees two copies of the same card.
	card_ui.modulate.a = 0.0
	_hide_move_destination_when_ready(target_slot)
	if start_pos != Vector2.INF:
		ghost.position = start_pos
	var base_position: Vector2 = ghost.position
	var end_position: Vector2 = base_position + delta
	var direction_sign := signf(delta.x) if absf(delta.x) > 0.5 else 1.0
	var mid: Vector2 = (base_position + end_position) / 2 + Vector2(0, -18) * ui_scale
	var base_scale: Vector2 = ghost.scale
	ghost.pivot_offset = ghost.size * 0.5
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		var a := base_position.lerp(mid, t)
		var b := mid.lerp(end_position, t)
		ghost.position = a.lerp(b, t)
	, 0.0, 1.0, 0.27).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(ghost, "rotation", deg_to_rad(2.2) * direction_sign, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(ghost, "rotation", 0.0, 0.14).set_delay(0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.tween_property(ghost, "scale", base_scale * 1.045, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(ghost, "scale", base_scale, 0.14).set_delay(0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.tween_property(ghost, "modulate:a", 0.82, 0.09).set_delay(0.18)
	twn.chain().tween_callback(_finish_move_ghost.bind(ghost, target_slot, layer, end_position, ui_scale))


func _hide_move_destination_when_ready(target_slot) -> void:
	if target_slot == null or not is_instance_valid(target_slot):
		return
	# update_entire_screen is deferred and may run on the next frame. Allow a
	# small bounded window for the replacement CardUI to appear.
	for _attempt in range(3):
		await get_tree().process_frame
		if target_slot == null or not is_instance_valid(target_slot):
			return
		var destination_card = target_slot.get("current_card_ui")
		if destination_card != null and is_instance_valid(destination_card):
			destination_card.visible = false
			return


func _finish_move_ghost(ghost, target_slot, layer: CanvasLayer, end_position: Vector2, ui_scale: float) -> void:
	if target_slot != null and is_instance_valid(target_slot) and target_slot.has_method("play_card_arrival"):
		target_slot.call("play_card_arrival", "swap")
		var center: Vector2 = target_slot.global_position + target_slot.size / 2
		card_drop_particles(layer, center, 7, ui_scale)
	if ghost != null and is_instance_valid(ghost):
		ghost.position = end_position
		ghost.queue_free()


# Card defeat: preserve the readable break beat, then send a face-up ghost to
# the discard pile. Rules already moved the CardData synchronously; this is a
# presentation-only echo and therefore never blocks chained death effects.
func death_fade(layer: CanvasLayer, card_ui, ui_scale: float = 1.0, discard_target: Vector2 = Vector2.INF, on_arrival: Callable = Callable()) -> void:
	if layer == null or card_ui == null or not is_instance_valid(card_ui):
		return
	death_burst(layer, card_ui.global_position + card_ui.size / 2, ui_scale)
	var ghost := spawn_card_ghost(layer, card_ui, ui_scale)
	if ghost == null:
		return
	ghost.set_meta("battle_fx_kind", "death_discard_card")
	var base_position: Vector2 = ghost.position
	var base_scale: Vector2 = ghost.scale
	var duration_scale := GamePreferences.battle_animation_duration_scale()
	ghost.pivot_offset = ghost.size * 0.5
	if discard_target == Vector2.INF:
		var fallback := layer.create_tween().set_parallel(true)
		fallback.tween_property(ghost, "modulate:a", 0.0, 0.24 * duration_scale)
		fallback.tween_property(ghost, "position", base_position + Vector2(0, 18), 0.24 * duration_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fallback.tween_property(ghost, "scale", base_scale * 0.82, 0.24 * duration_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		fallback.chain().tween_callback(ghost.queue_free)
		return
	var start_center: Vector2 = base_position + ghost.size * 0.5
	var direction := signf(discard_target.x - start_center.x) if absf(discard_target.x - start_center.x) > 1.0 else 1.0
	var control_center := (start_center + discard_target) * 0.5 + Vector2(28.0 * direction, -72.0) * ui_scale
	var twn := layer.create_tween()
	twn.set_parallel(false)
	# First beat: the card loses its footing but remains identifiable.
	twn.tween_property(ghost, "scale", Vector2(base_scale.x * 1.04, base_scale.y * 0.92), 0.085 * duration_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.parallel().tween_property(ghost, "rotation", deg_to_rad(-3.0) * direction, 0.085 * duration_scale)
	# Second beat: a compact curved flight makes the pile destination explicit.
	twn.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		var a := start_center.lerp(control_center, t)
		var b := control_center.lerp(discard_target, t)
		ghost.position = a.lerp(b, t) - ghost.size * 0.5
	, 0.0, 1.0, 0.36 * duration_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	twn.parallel().tween_property(ghost, "scale", base_scale * 0.46, 0.36 * duration_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.parallel().tween_property(ghost, "rotation", deg_to_rad(9.0) * direction, 0.36 * duration_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.parallel().tween_property(ghost, "modulate:a", 0.0, 0.12 * duration_scale).set_delay(0.24 * duration_scale)
	twn.tween_callback(_finish_death_discard.bind(ghost, layer, discard_target, ui_scale, on_arrival))


func _finish_death_discard(ghost: Control, layer: CanvasLayer, target: Vector2, ui_scale: float, on_arrival: Callable) -> void:
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	card_drop_particles(layer, target, 6, ui_scale)
	if on_arrival.is_valid():
		on_arrival.call()


# Hand card entry: fade in while springing to full size. Position is left to
# the container's layout (hand cards live in an HBoxContainer that re-sorts),
# so only modulate/scale are animated. Pivot is bottom-center, matching the
# hand-card hover effect.
func hand_card_enter(layer: CanvasLayer, card_ui: Control, ui_scale: float = 1.0) -> void:
	if layer == null or card_ui == null or not is_instance_valid(card_ui):
		return
	var base_scale: Vector2 = card_ui.scale
	card_ui.pivot_offset = Vector2(card_ui.size.x * 0.5, card_ui.size.y)
	card_ui.modulate.a = 0.0
	card_ui.scale = base_scale * 0.92
	var duration_scale := GamePreferences.battle_animation_duration_scale()
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(card_ui, "modulate:a", 1.0, 0.18 * duration_scale)
	twn.tween_property(card_ui, "scale", base_scale, 0.22 * duration_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Hit flash + jitter on a card when it takes damage (or heals). Multiple hits
# on the same card restart cleanly from its base transform.
func card_hit_flash(target: CanvasItem, delta: int) -> void:
	if target == null or not is_instance_valid(target) or delta == 0:
		return
	var key: int = target.get_instance_id()
	var data := _prepare_card_feedback(target)
	var base_modulate: Color = data["modulate"]
	var base_position: Vector2 = data["position"]
	var base_scale: Vector2 = data["scale"]
	var flash := Color(1.0, 0.44, 0.34) if delta < 0 else Color(0.54, 1.0, 0.64)
	var twn := create_tween()
	data["tween"] = twn
	_hit_targets[key] = data
	twn.set_parallel(false)
	twn.tween_property(target, "modulate", flash, 0.04)
	if target is Control:
		if delta < 0:
			twn.parallel().tween_property(target, "scale", Vector2(base_scale.x * 1.07, base_scale.y * 0.92), 0.04)
			twn.parallel().tween_property(target, "position", base_position + Vector2(8, -1), 0.035)
			twn.tween_property(target, "position", base_position + Vector2(-7, 1), 0.04)
			twn.parallel().tween_property(target, "scale", Vector2(base_scale.x * 0.96, base_scale.y * 1.05), 0.04)
			twn.tween_property(target, "position", base_position + Vector2(5, 0), 0.035)
			twn.tween_property(target, "position", base_position + Vector2(-3, 0), 0.035)
			twn.tween_property(target, "position", base_position, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			twn.parallel().tween_property(target, "scale", base_scale, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			twn.parallel().tween_property(target, "scale", base_scale * 1.07, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			twn.tween_property(target, "scale", base_scale, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(target, "modulate", base_modulate, 0.18)
	twn.finished.connect(_finish_hit_flash.bind(key, base_position, base_scale, base_modulate))


func _prepare_card_feedback(target: CanvasItem) -> Dictionary:
	var key := target.get_instance_id()
	if not _hit_targets.has(key):
		_hit_targets[key] = {
			"position": target.position if target is Control else Vector2.ZERO,
			"scale": target.scale if target is Control else Vector2.ONE,
			"modulate": target.modulate,
			"tween": null,
		}
	var data: Dictionary = _hit_targets[key]
	var old_tween: Tween = data.get("tween")
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	if target is Control:
		target.position = data["position"]
		target.scale = data["scale"]
	target.modulate = data["modulate"]
	return data


func _finish_hit_flash(key: int, base_position: Vector2, base_scale: Vector2, base_modulate: Color) -> void:
	var target := instance_from_id(key) as CanvasItem
	if target != null and is_instance_valid(target):
		if target is Control:
			target.position = base_position
			target.scale = base_scale
		target.modulate = base_modulate
	_hit_targets.erase(key)


# Field skill cast: card pulses + an arcane ring at the slot.
func skill_cast_pulse(layer: CanvasLayer, target: CanvasItem, center: Vector2, ui_scale: float = 1.0) -> void:
	if layer == null or target == null or not is_instance_valid(target):
		return
	var key := target.get_instance_id()
	var data := _prepare_card_feedback(target)
	var base_position: Vector2 = data["position"]
	var base_scale: Vector2 = data["scale"]
	var base_modulate: Color = data["modulate"]
	target.modulate = Color(0.72, 0.9, 1.35, 1.0)
	impact_ring(layer, center, false, Color(0.45, 0.7, 1.0, 0.5), ui_scale)
	skill_cast_beam(layer, center, ui_scale)
	var twn := create_tween()
	data["tween"] = twn
	_hit_targets[key] = data
	twn.set_parallel(true)
	if target is Control:
		twn.tween_property(target, "scale", base_scale * 1.08, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		twn.tween_property(target, "scale", base_scale, 0.18).set_delay(0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(target, "modulate", base_modulate, 0.26)
	twn.finished.connect(_finish_hit_flash.bind(key, base_position, base_scale, base_modulate))
