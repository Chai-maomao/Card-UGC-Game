extends RefCounted

const META_KEY := &"skill_drag_preview"
const Z_INDEX := 120

static func show(source: Control, face: Control) -> void:
	var preview := Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.z_index = Z_INDEX
	preview.add_child(face)
	source.get_viewport().set_meta(META_KEY, weakref(face))
	source.set_drag_preview(preview)

static func face_in(viewport: Viewport) -> Control:
	if viewport.has_meta(META_KEY):
		var preview: WeakRef = viewport.get_meta(META_KEY)
		return preview.get_ref()
	return null

static func uses_socket_overlap(socket: Control) -> bool:
	var viewport := socket.get_viewport()
	if viewport == null or not viewport.gui_is_dragging() or face_in(viewport) == null:
		return false
	var ancestor := socket.get_parent()
	while ancestor != null:
		if ancestor.has_meta("skill_workspace_world"):
			return true
		ancestor = ancestor.get_parent()
	return false

static func bounds_at(face: Control, pointer: Vector2) -> Rect2:
	# The wrapper follows the mouse. Use the event position, including when
	# the release arrives before Godot updates the displayed drag preview.
	var bounds: Rect2 = face.get_transform() * Rect2(Vector2.ZERO, face.size)
	bounds.position += pointer
	return bounds
