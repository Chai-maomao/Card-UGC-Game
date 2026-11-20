extends Node3D

const CAPACITY := 48
var bodies: Array[RigidBody3D] = []
var remaining := PackedFloat32Array()
var cursor := 0
var active_count := 0

func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.055,0.035,0.09)
	var shape := SphereShape3D.new()
	shape.radius = 0.035
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b79b65")
	material.metallic = 0.65
	material.roughness = 0.37
	remaining.resize(CAPACITY)
	for i in range(CAPACITY):
		var body := RigidBody3D.new()
		body.mass = 0.03
		body.collision_layer = 0
		body.collision_mask = 1
		body.freeze = true
		body.visible = false
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material
		body.add_child(visual)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		bodies.append(body)

func burst(at: Vector3, rng: RandomNumberGenerator, count: int) -> void:
	for i in range(mini(count,CAPACITY)):
		var index := cursor
		cursor = (cursor+1)%CAPACITY
		var body := bodies[index]
		body.freeze = true
		body.position = at+Vector3(0,0.12,0)
		body.rotation = Vector3.ZERO
		body.visible = true
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = Vector3(rng.randf_range(-1.4,1.4),rng.randf_range(0.9,2.2),rng.randf_range(-1.4,1.4))
		body.angular_velocity = Vector3(rng.randf_range(-8,8),4,3)
		remaining[index] = 1.2

func clear() -> void:
	for i in range(CAPACITY):
		remaining[i] = 0
		bodies[i].visible = false
		bodies[i].freeze = true
	active_count = 0

func _physics_process(delta: float) -> void:
	active_count = 0
	for i in range(CAPACITY):
		if remaining[i] <= 0: continue
		remaining[i] -= delta
		if remaining[i] <= 0 or bodies[i].position.y < -1:
			remaining[i] = 0
			bodies[i].visible = false
			bodies[i].freeze = true
		else: active_count += 1
