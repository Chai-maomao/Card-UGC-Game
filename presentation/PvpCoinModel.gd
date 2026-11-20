extends Node3D

const BRASS := Color("c6a164")
const GOLD := Color("f2cd85")
const PATINA := Color("20585a")


func _ready() -> void:
	var edge := _surface(Color("86633c"), 0.68, 0.32)
	var rim := _surface(BRASS, 0.73, 0.28)
	var engraving := _surface(GOLD, 0.59, 0.32)
	_disc(1.0, 0.20, 0.0, edge)
	_add_reeds(rim)
	for side: int in [-1, 1]:
		_disc(0.915, 0.038, side * 0.10, _surface(Color("79603d") if side == 1 else PATINA, 0.28, 0.44))
		_ring(0.897, 1.037, side * 0.099, rim)
		_ring(0.808, 0.828, side * 0.123, engraving)
		_ring(0.740, 0.750, side * 0.125, engraving)
		for index in range(24):
			var angle := TAU * index / 24.0
			var direction := Vector2.from_angle(angle)
			_line(direction * 0.766, direction * 0.788, side * 0.128, 0.012, engraving)
	_sun(engraving)
	_shield(engraving)


func _sun(ink: Material) -> void:
	var points := PackedVector2Array([Vector2(0, 0.24), Vector2(0.19, 0), Vector2(0, -0.24), Vector2(-0.19, 0)])
	_outline(points, 0.137, 0.054, ink)
	for index in range(8):
		var direction := Vector2.from_angle(TAU * index / 8.0)
		var tip := 0.60 if index % 2 == 0 else 0.47
		_line(direction * 0.34, direction * tip, 0.137, 0.049, ink)


func _shield(ink: Material) -> void:
	_outline(PackedVector2Array([
		Vector2(-0.40, 0.35), Vector2(0, 0.48), Vector2(0.40, 0.35),
		Vector2(0.34, -0.08), Vector2(0.22, -0.30), Vector2(0, -0.49),
		Vector2(-0.22, -0.30), Vector2(-0.34, -0.08),
	]), -0.137, 0.052, ink)
	_outline(PackedVector2Array([Vector2(0, 0.25), Vector2(0.15, 0.03), Vector2(0, -0.19), Vector2(-0.15, 0.03)]), -0.138, 0.044, ink)


func _outline(points: PackedVector2Array, z: float, width: float, ink: Material) -> void:
	for index in range(points.size()):
		_line(points[index], points[(index + 1) % points.size()], z, width, ink)


func _line(from: Vector2, to: Vector2, z: float, width: float, ink: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(from.distance_to(to) + width * 0.48, width, 0.018)
	var center := (from + to) * 0.5
	var instance := _add_mesh(mesh, ink)
	instance.position = Vector3(center.x, center.y, z)
	instance.rotation.z = (to - from).angle()


func _disc(radius: float, depth: float, z: float, surface: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 96
	var instance := _add_mesh(mesh, surface)
	instance.rotation.x = PI * 0.5
	instance.position.z = z


func _ring(inner: float, outer: float, z: float, surface: Material) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 96
	mesh.ring_segments = 12
	var instance := _add_mesh(mesh, surface)
	instance.rotation.x = PI * 0.5
	instance.position.z = z


func _add_reeds(surface: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.019, 0.153)
	mesh.material = surface
	var ridges := MultiMesh.new()
	ridges.transform_format = MultiMesh.TRANSFORM_3D
	ridges.mesh = mesh
	ridges.instance_count = 64
	for index in range(ridges.instance_count):
		var angle := TAU * index / ridges.instance_count
		var direction := Vector2.from_angle(angle) * 1.004
		ridges.set_instance_transform(index, Transform3D(Basis(Vector3.BACK, angle), Vector3(direction.x, direction.y, 0)))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = ridges
	add_child(instance)


func _add_mesh(mesh: Mesh, surface: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = surface
	add_child(instance)
	return instance


func _surface(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.metallic = metallic
	surface.roughness = roughness
	return surface
