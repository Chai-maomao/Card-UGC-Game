class_name SkillConditionReporter
extends HBoxContainer

# ============================================
# Draggable boolean/logic reporter that sits inside an if block's condition
# gap (comparisons, has-buff, and and/or/not logic trees).
#
# Bare Containers do not bind Control's drag methods to GDScript, so a
# set_drag_forwarding on a plain HBoxContainer is never invoked by the GUI
# pipeline (the press falls through to the enclosing if block instead). This
# scripted subclass implements the drag source directly:
#   - drag out of the gap -> drop on the palette removes the condition
#     (payload carries from_cond_slot), or drop into another if gap moves it
#   - drops from the palette (or another reporter) are forwarded to the
#     owning block's _drop_condition so the gap keeps working when filled.
# ============================================

var block: Node           # owning SkillBlock (for _drop_condition)
var payload: Dictionary = {}   # boolean_block / logic_block payload
var preview_text: String = ""


func setup(p_block: Node, p_cond: Dictionary, p_payload: Dictionary) -> void:
	block = p_block
	payload = p_payload
	preview_text = Locale.t("skill_editor.logic_and") if p_cond.has("logic") else Locale.t("skill_editor.boolean_compare")
	# STOP so this reporter (not the if block) is the drag source. The GUI
	# pipeline calls Control.get_drag_data, which invokes the forwarding
	# callbacks below (a bare GDVIRTUAL _get_drag_data is not consulted), so
	# wire the script methods through set_drag_forwarding like ValueSlot does.
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_drag_forwarding(
		Callable(self, "_slot_get_drag_data"),
		Callable(self, "_can_drop_data"),
		Callable(self, "_drop_data"),
	)


func _slot_get_drag_data(_pos: Vector2):
	if payload.is_empty():
		return null
	var teal := Color(0.28, 0.60, 0.56)
	var lbl := Label.new()
	lbl.text = preview_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var st := StyleBoxFlat.new()
	st.bg_color = teal
	st.border_color = teal.darkened(0.3)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	lbl.add_theme_stylebox_override("normal", st)
	var wrap := Control.new()
	wrap.add_child(lbl)
	set_drag_preview(wrap)
	return payload


# Filled reporter: accept palette drops (and other reporters) and forward them
# to the if gap so replacing the condition still works.
func _can_drop_data(_pos: Vector2, data) -> bool:
	return data is Dictionary and data.get("type", "") in ["boolean_block", "logic_block", "condition_block"]


func _drop_data(_pos: Vector2, data) -> void:
	if block != null and block.has_method("_drop_condition"):
		block.call("_drop_condition", Vector2.ZERO, data)
