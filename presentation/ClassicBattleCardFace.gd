extends Control
const CardArtwork = preload("res://CardArtwork.gd")

const FALLBACK = preload("res://res/tabletop/unillustrated_card.png")
var card: CardData
var enemy := false
var art: Texture2D
var fingerprint := ""
var art_path_cache := ""
var shown_attack := 0
var shown_hp := 0
var prediction: Dictionary = {}
var _name_only := ""

func set_prediction(value: Dictionary) -> void:
	if value == prediction: return
	prediction = value.duplicate()
	queue_redraw()

func bind(value: CardData, opposing: bool, displayed_hp: int = -1, displayed_max_hp: int = -1) -> void:
	var hp := value.hp if displayed_hp < 0 else displayed_hp
	var selected := CardArtwork.selected_path(value, hp, displayed_max_hp)
	var next := "%s/%s/%s/%s/%s/%s" % [value.instance_id, value.card_name, value.effective_atk(), hp, value.cost, selected] + "/" + JSON.stringify(value.status_effects) + "/" + str(value.parasite_cards.size()) + "/" + str(value.has_attacked) + "/" + str(value.temp_hp)
	next += "/" + Locale.language
	next += "/" + value.card_type + "/" + str(value.max_hp)
	if next == fingerprint: return
	var changed_art := card == null or art_path_cache != selected
	card = value
	shown_attack = value.effective_atk()
	shown_hp = hp
	enemy = opposing
	fingerprint = next
	if changed_art:
		art_path_cache = selected
		art = CardArtwork.texture_for(value, hp, displayed_max_hp)
	queue_redraw()

func bind_name_only(value: String) -> void:
	card = null
	fingerprint = ""
	_name_only = value
	queue_redraw()

func _draw() -> void:
	if card == null and _name_only.is_empty(): return
	var font := ThemeDB.fallback_font
	var ink := Color("252c2b")
	var accent := UITheme.card_type_accent(card.card_type) if card != null else Color("887b5b")
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color("d7c9a7")
	edge.set_corner_radius_all(6)
	edge.anti_aliasing = true
	draw_style_box(edge,Rect2(0,0,384,528))
	draw_rect(Rect2(12,12,360,504), ink, false, 3)
	draw_rect(Rect2(21,21,342,486), Color("ede0bd"))
	draw_rect(Rect2(25,25,334,10), accent)
	var title_font := UITheme.display_font()
	var title := card.card_name if card != null else _name_only
	var title_width := 257 if card != null else 316
	while title.length() > 1 and title_font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,40).x > title_width:
		title = title.left(title.length()-2)+"…"
	draw_string(title_font, Vector2(34,74), title, HORIZONTAL_ALIGNMENT_LEFT, title_width + 8, 40, ink)
	if card == null:
		draw_rect(Rect2(32,93,320,397),Color("e1d3b0"))
		draw_string(font, Vector2(32,302), Locale.t("history.name_only"), HORIZONTAL_ALIGNMENT_CENTER, 320, 34, ink)
		return
	# Match the title's 34px left margin with the badge's outer right edge.
	var badge_x := 384.0-34.0-24.0
	draw_circle(Vector2(badge_x,61), 24, accent)
	draw_string(font, Vector2(badge_x-15,71), str(card.cost), HORIZONTAL_ALIGNMENT_CENTER, 30, 27, Color("fff0cd"))
	var art_rect := Rect2(32,93,320,303)
	draw_rect(art_rect, Color("293d3b"))
	if art != null:
		var source := Rect2(Vector2.ZERO, art.get_size())
		var ratio := art_rect.size.x/art_rect.size.y
		if source.size.x/source.size.y > ratio:
			source.position.x = (source.size.x-source.size.y*ratio)*0.5
			source.size.x = source.size.y*ratio
		else:
			source.position.y = (source.size.y-source.size.x/ratio)*0.5
			source.size.y = source.size.x/ratio
		draw_texture_rect_region(art, art_rect, source)
	else:
		# Printed geometric seal for UGC cards without an illustration.
		for radius in [96,83,54]:
			draw_arc(Vector2(192,239), radius, 0, TAU, 64, Color("a49268"), 2, true)
		var points := PackedVector2Array([Vector2(192,130),Vector2(271,269),Vector2(113,269),Vector2(192,130)])
		draw_polyline(points,Color("c1ab77"),4,true)
		draw_circle(Vector2(192,239),14,Color("c1ab77"))
	draw_rect(art_rect, Color("887b5b"), false, 2)
	var category := Locale.t("card.spell") if card.is_spell() else (Locale.t("card.parasite") if card.is_parasite() else ("单位" if Locale.language == "zh" else "Unit"))
	draw_string(font,Vector2(34,431),category,HORIZONTAL_ALIGNMENT_LEFT,120,22,accent)
	if int(prediction.get("shield",0)) != 0:
		draw_string(font,Vector2(160,431),("护盾 %+d" if Locale.language == "zh" else "Shield %+d") % int(prediction.shield),HORIZONTAL_ALIGNMENT_RIGHT,190,22,accent)
	elif int(prediction.get("effects",0)) != 0:
		draw_string(font,Vector2(160,431),("效果 %+d" if Locale.language == "zh" else "Effects %+d") % int(prediction.effects),HORIZONTAL_ALIGNMENT_RIGHT,190,22,accent)
	elif card.temp_hp > 0:
		draw_string(font,Vector2(160,431),("护盾 +%d" if Locale.language == "zh" else "+%d Shield") % card.temp_hp,HORIZONTAL_ALIGNMENT_RIGHT,190,22,accent)
	elif not card.status_effects.is_empty() or not card.parasite_cards.is_empty():
		var count := card.status_effects.size()+card.parasite_cards.size()
		draw_string(font,Vector2(160,431),("效果 %d" if Locale.language == "zh" else "%d effects") % count,HORIZONTAL_ALIGNMENT_RIGHT,190,22,Color("98644c"))
	draw_line(Vector2(32,446),Vector2(352,446),Color("a39574"),1)
	if card.is_spell():
		draw_string(font,Vector2(34,490),Locale.t("card.spell"),HORIZONTAL_ALIGNMENT_LEFT,300,26,ink)
	else:
		_draw_stat(font,"HP",_predicted_stat("hp",shown_hp),Rect2(32,455,144,55),ink,accent)
		_draw_stat(font,"ATK",_predicted_stat("atk",shown_attack),Rect2(208,455,144,55),ink,accent)

func _draw_stat(font: Font, label: String, value: String, area: Rect2, ink: Color, accent: Color) -> void:
	var label_width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,28).x
	var point_size := 44 if value.length() < 4 else 29
	var value_width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x
	var x := area.position.x+(area.size.x-label_width-10-value_width)*0.5
	draw_string(font,Vector2(x,490),label,HORIZONTAL_ALIGNMENT_LEFT,-1,28,accent)
	draw_string(font,Vector2(x+label_width+10,490),value,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size,ink)

func _predicted_stat(key: String, current: int) -> String:
	var change := int(prediction.get(key,0))
	return str(current) if change == 0 else "%d(%+d)" % [maxi(0,current+change),change]
