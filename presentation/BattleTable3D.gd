extends Node3D

const Face = preload("res://presentation/TabletopCardFace.gd")
const ClassicFace = preload("res://presentation/ClassicBattleCardFace.gd")
var classic_battle_ui := false
var camera: Camera3D
var cards: Dictionary = {}
var sockets: Array[MeshInstance3D] = []
var lamps: Array[OmniLight3D] = []
var elapsed := 0.0
var trauma := 0.0
var rng := RandomNumberGenerator.new()
var menu_mode := false
var duration_scale := 1.0
var shard_pool: Node3D
var environment: Environment
var main_light: DirectionalLight3D
var quality := 1
var grain_normal: NoiseTexture2D
var dust: GPUParticles3D
var _pending_face_bakes: Dictionary = {}
var _drawing_faces: Dictionary = {}

func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	duration_scale = 1.0 if menu_mode else maxf(1.0,GamePreferences.battle_animation_duration_scale())
	rng.seed = 673411
	grain_normal = NoiseTexture2D.new()
	grain_normal.width = 128
	grain_normal.height = 128
	grain_normal.as_normal_map = true
	grain_normal.bump_strength = 0.3
	var grain := FastNoiseLite.new()
	grain.seed = 8927
	grain.frequency = 0.12
	grain.fractal_octaves = 2
	grain_normal.noise = grain
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 40.0
	camera.position = Vector3(0,22,9)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	environment = settings
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("080e13")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("839aa1")
	settings.ambient_light_energy = 0.55
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	main_light = sun
	sun.rotation_degrees = Vector3(-53,-26,0)
	sun.light_color = Color("ffdfae")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 35
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-6,5,-4)
	fill.light_color = Color("67a1be")
	fill.light_energy = 1.2
	fill.omni_range = 19
	add_child(fill)
	var stone := ShaderMaterial.new()
	stone.shader = preload("res://presentation/stone.gdshader")
	_box(self,Vector3(30,0.6,24),Vector3(0,-0.4,0),stone)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30,0.6,24)
	collision.shape = shape
	floor_body.position.y = -0.4
	floor_body.add_child(collision)
	add_child(floor_body)
	_box(self,Vector3(31,0.35,25),Vector3(0,-0.85,0),material(Color("101719"),0.3,0.6))
	var brass := material(Color("85714c"),0.72,0.36)
	var seal := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.5
	ring.outer_radius = 1.53
	seal.visible = not menu_mode
	seal.mesh = ring
	seal.material_override = brass
	seal.position.y = -0.065
	add_child(seal)
	var charcoal := material(Color("121c20"),0.15,0.7)
	for z in [-11.5,11.5]:
		_box(self,Vector3(29.4,0.12,0.12),Vector3(0,0.01,z),brass)
	for x in [-14.5,14.5]:
		_box(self,Vector3(0.12,0.12,23),Vector3(x,0.01,0),brass)
	for z in [-10.5,10.5]:
		for x in [-12.8,12.8]: _make_lamp(Vector3(x,0,z),brass)
	# The inset seam and machined corners make the board feel constructed.
	for x in [-10.5,10.5]:
		for z in [-8.8,8.8]:
			_box(self,Vector3(1.2,0.14,0.12),Vector3(x,0.04,z),brass)
	for i in range(10):
		var socket := _box(self,Vector3(1.5,0.05,2),Vector3.ZERO,charcoal.duplicate() as Material)
		sockets.append(socket)
		var edge := material(Color("746b53"),0.6,0.6)
		for x in [-0.69,0.69]:
			for z in [-0.94,0.94]:
				_box(socket,Vector3(0.16,0.03,0.018),Vector3(x-signf(x)*0.07,0.04,z),edge)
				_box(socket,Vector3(0.018,0.03,0.20),Vector3(x,0.04,z-signf(z)*0.09),edge)

	shard_pool = preload("res://presentation/TabletopShardPool.gd").new()
	add_child(shard_pool)
	AppPreferences.changed.connect(_preferences_changed)
	_make_dust()
	_apply_quality()

func _preferences_changed(key: String) -> void:
	if key in ["quality","reduced_motion"]: _apply_quality()

func _apply_quality() -> void:
	quality = int(AppPreferences.get_value("quality"))
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X][quality]
	main_light.shadow_enabled = quality > 0
	# Compatibility has no SSAO/glow; geometry and text remain identical.
	var modern := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	environment.ssao_enabled = modern and quality == 2
	environment.ssao_radius = 0.4
	environment.ssao_intensity = 0.65
	environment.glow_enabled = modern and quality == 2
	environment.glow_intensity = 0.18
	environment.glow_hdr_threshold = 1.7
	if quality == 0 or AppPreferences.get_value("reduced_motion"): shard_pool.clear()
	if dust != null:
		dust.emitting = quality > 0 and not AppPreferences.get_value("reduced_motion")
		dust.visible = dust.emitting
		dust.amount = 96 if quality == 2 else 48

func material(color: Color, metal: float = 0.0, rough: float = 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	if grain_normal != null and metal > 0.5:
		mat.normal_enabled = true
		mat.normal_texture = grain_normal
		mat.normal_scale = 0.12
	return mat

func _box(parent: Node, dimensions: Vector3, location: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = mat
	node.position = location
	parent.add_child(node)
	return node

func _make_lamp(at: Vector3, brass: Material) -> void:
	_box(self,Vector3(0.45,0.18,0.45),at+Vector3(0,0.08,0),brass)
	_box(self,Vector3(0.25,0.6,0.25),at+Vector3(0,0.44,0),material(Color("cfc09a")))
	var flame := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.25
	flame.mesh = mesh
	var emissive := material(Color("ffd897"))
	emissive.emission_enabled = true
	emissive.emission = Color("ffbc57")
	emissive.emission_energy_multiplier = 3
	flame.material_override = emissive
	flame.position = at+Vector3(0,0.86,0)
	add_child(flame)
	var lamp := OmniLight3D.new()
	lamp.position = at+Vector3(0,1.1,0)
	lamp.light_color = Color("ffc17b")
	lamp.light_energy = 4
	lamp.omni_range = 5
	add_child(lamp)
	lamps.append(lamp)

func plane_point(screen: Vector2, height: float = 0.08) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	return origin + ray * ((height-origin.y)/ray.y)

func _slot_dimensions(rect: Rect2, height: float = 0.08) -> Vector3:
	var midpoint := rect.get_center()
	var left := plane_point(midpoint-Vector2(rect.size.x*0.5,0),height)
	var right := plane_point(midpoint+Vector2(rect.size.x*0.5,0),height)
	var near := plane_point(midpoint+Vector2(0,rect.size.y*0.5),height)
	var far := plane_point(midpoint-Vector2(0,rect.size.y*0.5),height)
	return Vector3(absf(right.x-left.x)*0.91,0.11,absf(near.z-far.z)*0.92)

func fit_opponent_lane(near_row: Control, far_row: Control) -> void:
	if near_row.get_child_count()<3 or far_row.get_child_count()<3: return
	# Keep the native Control hit areas and the meshes in the same projection.
	# Both rows now describe cards of equal world size, rather than enlarging
	# distant cards to fill the old, equally sized screen rectangles.
	far_row.scale = Vector2.ONE
	var reference := _slot_dimensions(near_row.get_child(2).get_global_rect())
	var far_rect: Rect2 = far_row.get_child(2).get_global_rect()
	var unscaled := _slot_dimensions(far_rect)
	var low := 0.1
	var high := 1.5
	for step in range(20):
		var mid := (low+high)*0.5
		var probe := Rect2(far_rect.get_center()-Vector2(far_rect.size.x,far_rect.size.y*mid)*0.5,Vector2(far_rect.size.x,far_rect.size.y*mid))
		if _slot_dimensions(probe).z < reference.z: low = mid
		else: high = mid
	far_row.pivot_offset = far_row.size*0.5
	far_row.scale = Vector2(reference.x/unscaled.x,(low+high)*0.5)

func reindex_hand(values: Array) -> void:
	var old := {}
	var unchanged := true
	for key in cards:
		if key < 10: continue
		old[key] = cards[key]
		if key-10 >= values.size() or int(cards[key].get("card_object_id",0)) != values[key-10].get_instance_id(): unchanged = false
	if unchanged and old.size()==values.size(): return
	for key in old: cards.erase(key)
	for index in range(values.size()):
		for key in old.keys():
			if int(old[key].get("card_object_id",0)) == values[index].get_instance_id() or (values[index].instance_id != "" and old[key].id == values[index].instance_id):
				old[key]["card_object_id"] = values[index].get_instance_id()
				cards[10+index] = old[key]
				old.erase(key)
				break
	for entry in old.values():
		entry.root.queue_free()
		entry.viewport.queue_free()

func sync_slot(slot: Control, key: int, value: CardData, enemy: bool, update_face: bool = true, displayed_hp: Dictionary = {}) -> void:
	if not is_instance_valid(camera) or slot.size.x <= 0: return
	if key >= 10 and cards.has(key):
		cards[key]["fan_angle"] = float(slot.get_meta("hand_fan_angle",0.0))
	var rect := slot.get_global_rect()
	var hand_card := key >= 10
	var surface_height := (0.36 if slot.get_meta("hand_focused",false) else 0.08+0.02*(key-10)) if hand_card else 0.08
	if value != null and cards.has(key) and cards[key].id == value.instance_id and cards[key].get("rect",Rect2()) == rect and is_equal_approx(float(cards[key].get("surface_height",0.08)),surface_height):
		if update_face: _sync_face(cards[key], value, enemy, displayed_hp)
		return
	var center := plane_point(rect.get_center(),surface_height)
	var dimensions := _slot_dimensions(rect,surface_height)
	if hand_card:
		dimensions.y = 0.008
		center.y -= dimensions.y*0.5+0.002
	if key < sockets.size():
		sockets[key].position = center-Vector3(0,0.16,0)
		sockets[key].scale = Vector3(dimensions.x/1.5,1,dimensions.z/2)
	if value == null:
		if cards.has(key):
			var old: Dictionary = cards[key]
			old.root.queue_free()
			old.viewport.queue_free()
			cards.erase(key)
		return
	if cards.has(key) and cards[key].id != value.instance_id:
		cards[key].root.queue_free()
		cards[key].viewport.queue_free()
		cards.erase(key)
	if not cards.has(key):
		var root := Node3D.new()
		root.position = center+Vector3(0,0.18 if key >= 10 else 0.28,0.3)
		add_child(root)
		var body := _box(root,dimensions,Vector3.ZERO,material(Color("29251f"),0.2,0.5))
		body.visible = not classic_battle_ui
		var viewport := SubViewport.new()
		viewport.size = Vector2i(384,528) if classic_battle_ui else Vector2i(384,512)
		viewport.transparent_bg = classic_battle_ui
		viewport.disable_3d = true
		viewport.gui_disable_input = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(viewport)
		var face = ClassicFace.new() if classic_battle_ui else Face.new()
		face.size = Vector2(viewport.size)
		viewport.add_child(face)
		var top := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(dimensions.x,dimensions.z)
		top.mesh = quad
		top.rotation.x = -PI/2
		top.position.y = dimensions.y*0.5+0.002
		var ink := StandardMaterial3D.new()
		ink.albedo_texture = viewport.get_texture()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if classic_battle_ui else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		ink.albedo_color = Color.WHITE if classic_battle_ui else Color(0.64,0.70,0.76)
		if menu_mode:
			ink.albedo_color = ink.albedo_color.darkened(0.08)
		if classic_battle_ui:
			ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			ink.alpha_scissor_threshold = 0.5
		ink.roughness = 0.94
		ink.metallic_specular = 0.05
		ink.normal_enabled = true
		ink.normal_texture = grain_normal
		ink.normal_scale = 0.05
		ink.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		top.material_override = ink
		root.add_child(top)
		cards[key] = {"id":value.instance_id,"root":root,"body":body,"top":top,"viewport":viewport,"face":face,"target":center,"velocity":Vector3.ZERO,"dimensions":dimensions}
	var entry: Dictionary = cards[key]
	entry["card_object_id"] = value.get_instance_id()
	if hand_card:
		if entry.has("surface_height") and not is_equal_approx(float(entry.surface_height),surface_height):
			# Lift changes depth immediately for paper ordering. Transport the old
			# screen position to that depth before damping, avoiding a sideways kick.
			var previous_top: Vector3 = entry.top.global_position
			var transported := plane_point(camera.unproject_position(previous_top),surface_height)
			var ratio := (camera.global_position.y-surface_height)/maxf(.001,camera.global_position.y-previous_top.y)
			entry.root.position = Vector3(transported.x,center.y,transported.z)
			entry.velocity.x *= ratio
			entry.velocity.z *= ratio
		entry["fan_angle"] = float(slot.get_meta("hand_fan_angle",0.0))
	entry.target = center
	entry["rect"] = rect
	entry["surface_height"] = surface_height
	entry.body.scale = dimensions/entry.dimensions
	entry.top.scale = Vector3(dimensions.x/entry.dimensions.x,dimensions.z/entry.dimensions.z,1)
	if update_face or entry.face.fingerprint.is_empty(): _sync_face(entry, value, enemy, displayed_hp)

func _sync_face(entry: Dictionary, value: CardData, enemy: bool, displayed_hp: Dictionary = {}) -> void:
	var previous: String = entry.face.fingerprint
	if classic_battle_ui:
		entry.face.bind(value, enemy, int(displayed_hp.get("hp", -1)), int(displayed_hp.get("max_hp", -1)))
	else:
		entry.face.bind(value, enemy)
	if previous != entry.face.fingerprint:
		queue_face_bake(entry)

func present_hp(key: int, hp: int, max_hp: int) -> void:
	if not classic_battle_ui or not cards.has(key):
		return
	var entry: Dictionary = cards[key]
	_sync_face(entry, entry.face.card, entry.face.enemy, {"hp": hp, "max_hp": max_hp})

func set_card_outline(key: int, color: Color) -> void:
	if not cards.has(key): return
	var entry: Dictionary = cards[key]
	if not entry.has("outline"):
		if color.a <= 0.0: return
		entry["outline"] = preload("res://presentation/CardTargetOutline.gd").new()
		entry.root.add_child(entry.outline)
	entry.outline.update_outline(entry.dimensions * entry.body.scale, color)


func hover(key: int, enabled: bool) -> void:
	if cards.has(key): cards[key]["hover"] = enabled
	if key < sockets.size():
		var mat: StandardMaterial3D = sockets[key].material_override
		mat.albedo_color = Color("364b49") if enabled else Color("121c20")
		for corner in sockets[key].get_children():
			corner.material_override.albedo_color = Color("c6af76") if enabled else Color("746b53")

func impact(key: int, direction: Vector3 = Vector3.ZERO, strong: bool = false) -> void:
	if not cards.has(key): return
	cards[key].velocity += Vector3(0,7.0 if strong else 1.5,0)+direction*(6.0 if strong else 1.8)
	trauma = maxf(trauma,0.12 if strong else 0.025)
	if strong: _debris(cards[key].target)

func strike(key: int, target_key: int, forward: Vector3) -> void:
	if not cards.has(key) or AppPreferences.get_value("reduced_motion"):
		return
	var entry: Dictionary = cards[key]
	var direction := forward
	if cards.has(target_key):
		var span: Vector3 = cards[target_key].target - entry.target
		span.y = 0.0
		if span.length_squared() > 0.001:
			direction = span.normalized()
	# A small positional kick reads on the first rendered frame. The spring
	# returns the physical card to the slot without moving its input proxy.
	entry.root.position = entry.target + direction * 0.08
	entry.velocity = direction * 6.4 + Vector3.UP * 1.4

func receive_hit(key: int, damage: int) -> void:
	if not cards.has(key) or damage <= 0 or AppPreferences.get_value("reduced_motion"):
		return
	var entry: Dictionary = cards[key]
	var away := Vector3.BACK if key < 5 else Vector3.FORWARD
	var weight := clampf(float(damage - 1) / 5.0, 0.0, 1.0)
	entry.velocity = away * lerpf(3.5, 8.8, weight) + Vector3.UP * lerpf(0.6, 2.6, weight)
	if damage >= 4:
		trauma = maxf(trauma, lerpf(0.05, 0.13, weight))
		_debris(entry.target)

func _debris(at: Vector3) -> void:
	if quality == 0 or AppPreferences.get_value("reduced_motion"): return
	shard_pool.burst(at,rng,9 if quality == 2 else 5)

func _physics_process(delta: float) -> void:
	elapsed += delta
	var reduced := bool(AppPreferences.get_value("reduced_motion"))
	# Exact critical damping is independent of render/physics frame rate.
	var omega := 28.0 / minf(duration_scale,1.2)
	var decay := exp(-omega*delta)
	for key in cards:
		var entry: Dictionary = cards[key]
		var target: Vector3 = entry.target+Vector3(0,0.035 if key < 10 and entry.get("hover",false) else 0,0)
		if reduced:
			entry.root.position = target
			entry.velocity = Vector3.ZERO
			entry.erase("travel")
		elif entry.has("travel"):
			var travel: Dictionary = entry.travel
			travel.age += delta
			var phase := clampf(float(travel.age)/0.30,0,1)
			var horizontal := clampf((phase-0.2)/0.55,0,1)
			horizontal = horizontal*horizontal*(3.0-2.0*horizontal)
			var lift := smoothstep(0,0.2,phase)*(1.0-smoothstep(0.75,1.0,phase))*float(travel.lift)
			var previous: Vector3 = entry.root.position
			entry.root.position = (travel.from as Vector3).lerp(target,horizontal)+Vector3(0,lift,0)
			entry.velocity = (entry.root.position-previous)/maxf(delta,0.001)
			if phase >= 1:
				entry.erase("travel")
				entry.velocity = Vector3.ZERO
		else:
			var offset: Vector3 = entry.root.position-target
			var step: Vector3 = (entry.velocity+omega*offset)*delta
			entry.root.position = target+(offset+step)*decay
			entry.velocity = (entry.velocity-omega*step)*decay
		entry.root.rotation.x = clampf(entry.velocity.z*0.02,-0.06,0.06)
		entry.root.rotation.z = clampf(-entry.velocity.x*0.02,-0.05,0.05)
		if key >= 10:
			# Preserve paper ordering even while adjacent cards animate past each other.
			entry.root.position.y = target.y
			entry.root.rotation = Vector3(0,-float(entry.get("fan_angle",0.0)),0)
			entry.velocity.y = 0
		# Keep the lowest tilted corner above the board; no physics touches rules.
		var clearance: float = entry.dimensions.y*0.5+absf(sin(entry.root.rotation.x))*entry.dimensions.z*0.5+absf(sin(entry.root.rotation.z))*entry.dimensions.x*0.5
		entry.root.position.y = maxf(entry.root.position.y,-0.08+clearance)

	trauma = move_toward(trauma,0,delta*0.6)
	if reduced or quality == 0 or not AppPreferences.get_value("camera_shake"): trauma = 0
	camera.h_offset = sin(elapsed*71)*trauma*0.12
	camera.v_offset = cos(elapsed*57)*trauma*0.07
	for i in range(lamps.size()): lamps[i].light_energy = 3.8+sin(elapsed*3.4+i)*0.16

func remove_hand_after(count: int) -> void:
	for key in cards.keys():
		if key >= 10+count:
			cards[key].root.queue_free()
			cards[key].viewport.queue_free()
			cards.erase(key)

func queue_face_bake(entry: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_pending_face_bakes[entry.viewport.get_instance_id()] = entry
	if not get_tree().process_frame.is_connected(_request_face_draws):
		get_tree().process_frame.connect(_request_face_draws, CONNECT_ONE_SHOT)


func _request_face_draws() -> void:
	for viewport_id in _pending_face_bakes:
		var entry: Dictionary = _pending_face_bakes[viewport_id]
		if is_instance_valid(entry.viewport) and not entry.viewport.is_queued_for_deletion():
			entry.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_drawing_faces[viewport_id] = entry
	_pending_face_bakes.clear()
	if not _drawing_faces.is_empty() and not RenderingServer.frame_post_draw.is_connected(_finish_face_bakes):
		RenderingServer.frame_post_draw.connect(_finish_face_bakes, CONNECT_ONE_SHOT)


func _finish_face_bakes() -> void:
	for entry: Dictionary in _drawing_faces.values():
		_bake_face(entry)
	_drawing_faces.clear()


func _exit_tree() -> void:
	if get_tree().process_frame.is_connected(_request_face_draws):
		get_tree().process_frame.disconnect(_request_face_draws)
	if RenderingServer.frame_post_draw.is_connected(_finish_face_bakes):
		RenderingServer.frame_post_draw.disconnect(_finish_face_bakes)
	_pending_face_bakes.clear()
	_drawing_faces.clear()


func _bake_face(entry: Dictionary) -> void:
	if not is_instance_valid(entry.viewport) or not is_instance_valid(entry.top): return
	var image: Image = entry.viewport.get_texture().get_image()
	if image == null or image.is_empty(): return
	image.generate_mipmaps()
	entry.top.material_override.albedo_texture = ImageTexture.create_from_image(image)


func _make_dust() -> void:
	dust = GPUParticles3D.new()
	dust.amount = 48
	dust.lifetime = 12
	dust.preprocess = 4
	dust.visibility_aabb = AABB(Vector3(-12,0,-10),Vector3(24,6,20))
	dust.position.y = 1.8
	dust.fixed_fps = 30
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(11,0.4,9)
	motion.direction = Vector3(0.3,1,0)
	motion.spread = 20
	motion.initial_velocity_min = 0.02
	motion.initial_velocity_max = 0.06
	motion.gravity = Vector3.ZERO
	motion.scale_min = 0.3
	motion.scale_max = 0.7
	dust.process_material = motion
	var speck := QuadMesh.new()
	speck.size = Vector2(0.045,0.045)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.75,0.66,0.45,0.13)
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	ink.no_depth_test = false
	speck.material = ink
	dust.draw_pass_1 = speck
	add_child(dust)

func projected_slot_corners(key: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var transform: Transform3D
	var dimensions: Vector3
	if cards.has(key):
		var entry: Dictionary = cards[key]
		transform = entry.root.global_transform
		dimensions = entry.dimensions * entry.body.scale
	elif key >= 0 and key < sockets.size():
		transform = sockets[key].global_transform
		dimensions = (sockets[key].mesh as BoxMesh).size
	else: return points
	for corner in [Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(1,1,1),Vector3(-1,1,1)]:
		points.append(camera.unproject_position(transform * (corner * dimensions * 0.5)))
	return points
