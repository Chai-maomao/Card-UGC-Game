extends RichTextLabel

func _init() -> void:
	hint_underlined = false

func _has_point(at: Vector2) -> bool:
	# Keyword icons and text accept hover. Other text leaves input to the host.
	return Rect2(Vector2.ZERO, size).has_point(at) and get_tooltip(at).begins_with(SkillHelp.KEYWORD_PREFIX)
