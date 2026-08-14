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

# --- Procedural FX textures (generated once) ---
var _glow_dot: Texture2D = null
var _ring_tex: Texture2D = null
var _card_back_tex: Texture2D = null
var _slash_tex: Texture2D = null

# --- Object pools: key -> Array[Control] ---
var _pool: Dictionary = {}

# --- Card-hit flash state (per target instance) ---
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
		return c)
	card_back.texture = _card_back_tex
	card_back.size = size
	card_back.pivot_offset = size / 2
	card_back.position = start - size / 2 + Vector2(index * 7, -index * 5)
	card_back.modulate.a = 0.0
	layer.add_child(card_back)
	layer.move_child(card_back, layer.get_child_count() - 1)
	var lift: float = -78.0 * ui_scale - index * 8.0
	var mid: Vector2 = (start + target) * 0.5 + Vector2(0, lift)
	var duration: float = 0.58 + index * 0.07
	var twn := create_tween()
	twn.set_parallel(false)
	twn.tween_property(card_back, "modulate:a", 1.0, 0.08)
	twn.parallel().tween_property(card_back, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_back, "position", mid - card_back.size / 2, duration * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_back, "position", target - card_back.size / 2 + Vector2(index * 5, 0), duration * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.parallel().tween_property(card_back, "scale", Vector2(0.82, 0.82), duration * 0.55)
	twn.parallel().tween_property(card_back, "modulate:a", 0.0, 0.16).set_delay(duration * 0.35)
	twn.chain().tween_callback(_release.bind("card_back", card_back))


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


# Pop-in landing effect for a freshly summoned card in a slot: scale spring
# from small to full + a golden landing ring. Restores the card's original
# pivot when done so later hit-flash/drag effects keep their own pivot basis.
func summon_landing(layer: CanvasLayer, card_ui, center: Vector2, ui_scale: float = 1.0) -> void:
	if layer == null or card_ui == null or not is_instance_valid(card_ui):
		return
	var base_pivot: Vector2 = card_ui.pivot_offset
	var card_id: int = card_ui.get_instance_id()
	var base_scale: Vector2 = card_ui.scale
	card_ui.pivot_offset = card_ui.size / 2
	card_ui.scale = base_scale * 0.5
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(card_ui, "scale", base_scale, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.chain().tween_callback(_summon_landing_finish.bind(card_id, base_pivot, layer, center, ui_scale))


func _summon_landing_finish(card_id: int, base_pivot: Vector2, layer: CanvasLayer, center: Vector2, ui_scale: float) -> void:
	# Restore the card's original pivot only if it still exists (the field UI
	# may have been rebuilt while the landing animation was running).
	var card := instance_from_id(card_id)
	if card != null and is_instance_valid(card):
		card.pivot_offset = base_pivot
	impact_ring(layer, center, false, Color(0.95, 0.78, 0.32, 0.42), ui_scale)
	sparkle_burst(layer, center, Color(1.0, 0.85, 0.4, 0.95), 10, ui_scale)


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
		_single_move_ghost(layer, card_ui, delta, ui_scale, start_pos)


func _single_move_ghost(layer: CanvasLayer, card_ui, delta: Vector2, ui_scale: float, start_pos: Vector2 = Vector2.INF) -> void:
	var ghost := spawn_card_ghost(layer, card_ui, ui_scale)
	if ghost == null:
		return
	if start_pos != Vector2.INF:
		ghost.position = start_pos
	var base_position: Vector2 = ghost.position
	var end_position: Vector2 = base_position + delta
	var mid: Vector2 = (base_position + end_position) / 2 + Vector2(0, -12) * ui_scale
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		var a := base_position.lerp(mid, t)
		var b := mid.lerp(end_position, t)
		ghost.position = a.lerp(b, t)
	, 0.0, 1.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(ghost, "modulate:a", 0.0, 0.18).set_delay(0.14)
	twn.chain().tween_callback(ghost.queue_free)


# Card death: a ghost copy sinks and fades while the real card is removed,
# plus a dark arcane burst.
func death_fade(layer: CanvasLayer, card_ui, ui_scale: float = 1.0) -> void:
	if layer == null or card_ui == null or not is_instance_valid(card_ui):
		return
	death_burst(layer, card_ui.global_position + card_ui.size / 2, ui_scale)
	var ghost := spawn_card_ghost(layer, card_ui, ui_scale)
	if ghost == null:
		return
	var base_position: Vector2 = ghost.position
	var base_scale: Vector2 = ghost.scale
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(ghost, "modulate:a", 0.0, 0.24)
	twn.tween_property(ghost, "position", base_position + Vector2(0, 18), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.tween_property(ghost, "scale", base_scale * 0.82, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	twn.chain().tween_callback(ghost.queue_free)


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
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(card_ui, "modulate:a", 1.0, 0.18)
	twn.tween_property(card_ui, "scale", base_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Hit flash + jitter on a card when it takes damage (or heals). Multiple hits
# on the same card restart cleanly from its base transform.
func card_hit_flash(target: CanvasItem, delta: int) -> void:
	if target == null or not is_instance_valid(target) or delta == 0:
		return
	var key: int = target.get_instance_id()
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
	var base_scale: Vector2 = target.scale if target is Control else Vector2.ONE
	var base_modulate: Color = target.modulate
	target.modulate = Color(0.72, 0.9, 1.35, 1.0)
	impact_ring(layer, center, false, Color(0.45, 0.7, 1.0, 0.5), ui_scale)
	skill_cast_beam(layer, center, ui_scale)
	var twn := create_tween()
	twn.set_parallel(true)
	if target is Control:
		twn.tween_property(target, "scale", base_scale * 1.08, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		twn.tween_property(target, "scale", base_scale, 0.18).set_delay(0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(target, "modulate", base_modulate, 0.26)
