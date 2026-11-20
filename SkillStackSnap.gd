extends RefCounted

# Keep hit geometry independent of the space made by the insertion preview.
# Coordinates live in the canvas world so panning during a drag still works.
var editor: Control
var targets: Array[Dictionary] = []
var active: Dictionary = {}

func _init(owner_editor: Control) -> void:
	editor = owner_editor

func clear() -> void:
	targets.clear()
	active.clear()

func _capture(data: Dictionary) -> void:
	var world: Control = editor.workbench.workspace.world
	var inverse := world.get_global_transform().affine_inverse()
	var source: Array = data.get("from_path", [])
	for node in world.find_children("*", "VBoxContainer", true, false):
		if not node.has_meta("list_path") or not node.is_visible_in_tree(): continue
		var path: Array = node.get_meta("list_path")
		var blocked := false
		if not source.is_empty():
			var parent := source.slice(0, -1)
			var first: int = source.back()
			var count: int = editor._list_at(parent).size() if data.get("tail", false) else first + 1
			for index in range(first, count):
				if editor._is_path_prefix(parent + [index], path): blocked = true
		if blocked: continue
		var blocks: Array[Dictionary] = []
		var index := 0
		var has_hat := false
		for child in node.get_children():
			if not child is SkillBlock: continue
			if child.is_hat:
				has_hat = true
				break
			if child.visible:
				blocks.append({"index": index, "rect": inverse * child.get_global_rect(), "terminal": child._effect.get("effect") == SkillEngine.EFFECT_STOP})
			index += 1
		if has_hat: continue
		# A loose stack disappears as a target when all of it is in hand.
		if blocks.is_empty() and path.size() == 2 and path[0] is String and path[0] == "loose":
			continue
		var rect: Rect2 = inverse * node.get_global_rect()
		targets.append({"box": node, "path": path.duplicate(), "rect": rect, "blocks": blocks})

func preview(data: Variant) -> bool:
	if not data is Dictionary or data.get("type", "") != "effect_block":
		active.clear()
		editor._hide_insertion_line()
		return false
	var canvas: Control = editor.workbench.workspace
	if not Rect2(Vector2.ZERO, canvas.size).has_point(canvas.last_pointer):
		active.clear()
		editor._hide_insertion_line()
		return false
	if targets.is_empty(): _capture(data)
	var pointer: Vector2 = canvas.to_world(canvas.last_pointer)
	var grab: Array = data.get("grab_offset", [12, 12])
	var leading := pointer - Vector2(float(grab[0]), float(grab[1]))
	var scale_factor: float = canvas.world.get_global_transform().get_scale().x
	var source: Array = data.get("from_path", [])
	var source_parent := source.slice(0, -1)
	var chosen: Dictionary = {}
	var best := INF
	for target in targets:
		var box: Control = target.box
		if not is_instance_valid(box): continue
		var blocks: Array = target.blocks
		var rect: Rect2 = target.rect
		var inside_empty_socket := blocks.is_empty() and rect.has_point(pointer)
		var index := 0
		var anchor := rect.position
		var below_terminal := false
		if not blocks.is_empty():
			index = int(blocks.back().index) + 1
			anchor = blocks.back().rect.end
			anchor.x = blocks.back().rect.position.x
			anchor.y -= preload("res://SkillSocketStyle.gd").JOIN_OVERLAP
			below_terminal = blocks.back().terminal
			for block in blocks:
				var bounds: Rect2 = block.rect
				if absf(leading.y - bounds.position.y) < absf(leading.y - anchor.y):
					index = block.index
					anchor = bounds.position
					below_terminal = false
		var distance := (leading - anchor) * scale_factor
		if below_terminal: continue
		if not inside_empty_socket and (absf(distance.x) > 40 or absf(distance.y) > 24): continue
		var score := distance.length_squared()
		if inside_empty_socket:
			score = -10000.0 - float(target.path.size()) * 1000.0 + absf(distance.y)
		if score < best:
			best = score
			chosen = {"box": box, "path": target.path, "index": index}
			if not source.is_empty() and source_parent == target.path:
				chosen["unchanged"] = index == int(source.back())
	active = chosen
	if active.is_empty():
		editor._hide_insertion_line()
		return false
	if active.get("unchanged", false):
		editor._hide_insertion_line()
		return true
	editor._activate_slot_highlight(active.box)
	editor._show_insertion_line(active.box, active.index)
	return true

func commit(data: Dictionary) -> bool:
	# Resolve against the same frozen geometry, including on the release event.
	if not preview(data): return false
	if active.get("unchanged", false): return true
	var path: Array = active.path.duplicate()
	var index: int = active.index
	var final_index := index
	var source: Array = data.get("from_path", [])
	if not source.is_empty() and source.slice(0, -1) == path and int(source.back()) < index:
		final_index -= editor._list_at(path).size() - int(source.back()) if data.get("tail", false) else 1
	editor._hide_insertion_line()
	editor._apply_drop(data, path, index)
	editor._show_connection_feedback.call_deferred(path + [maxi(0, final_index)])
	return true
