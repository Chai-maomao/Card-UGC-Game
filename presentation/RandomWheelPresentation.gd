extends CanvasLayer

const Wheel = preload("res://presentation/RandomWheelFace.gd")
var battle: Node
var dim: ColorRect
var wheel: Control
var title: Label
var detail: Label
var busy := false
var history: Array[Dictionary] = []
var _screen_size := Vector2.ZERO

func _process(_delta: float) -> void:
	if not busy or _screen_size==get_viewport().get_visible_rect().size: return
	_layout_for_size()

func _layout_for_size() -> void:
	_screen_size = get_viewport().get_visible_rect().size
	var s := minf(_screen_size.x/1280,_screen_size.y/720)
	wheel.position = _screen_size*.5
	wheel.scale = Vector2.ONE*s
	dim.size = _screen_size
	title.position = Vector2(24,_screen_size.y*.5-250*s)
	title.size = Vector2(_screen_size.x-48,64*s)
	title.add_theme_font_size_override("font_size",maxi(14,int(20*s)))
	detail.position = Vector2(0,_screen_size.y*.5+192*s)
	detail.size = Vector2(_screen_size.x,60*s)
	detail.add_theme_font_size_override("font_size",maxi(16,int(23*s)))

func _ready() -> void:
	layer = 40
	dim = ColorRect.new()
	dim.name = "RandomWheelDimmer"
	dim.color = Color(.015,.022,.025,.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	wheel = Wheel.new()
	wheel.name = "RandomWheel"
	add_child(wheel)
	title = Label.new()
	title.set_meta("keyword_literal",true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_label(title)
	add_child(title)
	detail = Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_label(detail)
	add_child(detail)
	visible = false

func _duration(seconds: float) -> float:
	if AppPreferences.get_value("reduced_motion"): return minf(seconds,.1)
	return seconds*GamePreferences.battle_animation_duration_scale()

func landing_fraction(outcome: Dictionary) -> float:
	if str(outcome.get("type",""))=="chance":
		var roll := float(outcome.get("roll",0))
		return clampf((roll-.5 if outcome.get("integer_roll",false) else roll)/100,0.00001,.99999)
	var minimum := int(outcome.get("minimum",1))
	var count := maxi(1,int(outcome.get("maximum",6))-minimum+1)
	return (int(outcome.get("result",minimum))-minimum+.5)/count

func _subject_text(outcome: Dictionary) -> String:
	var zh := Locale.language=="zh"
	var owner := ""
	var player := int(outcome.get("player",0))
	if player in [1,2]:
		if not PlayerData.is_online_battle() and PlayerData.battle_mode=="hotseat":
			owner = ("玩家%d的" if zh else "Player %d's ")%player
		else:
			owner = ("我方" if player==battle._view_player() else "敌方") if zh else ("Your " if player==battle._view_player() else "Opponent's ")
	var source := str(outcome.get("source",""))
	var subject := owner+("【%s】"%source if zh else source)
	if outcome.has("parasite"):
		subject += ("身上的寄生卡【%s】" if zh else " with attached parasite %s")%str(outcome.parasite)
	var skill := str(outcome.get("skill",""))
	if not skill.is_empty(): subject += ("的技能【%s】" if zh else ", skill %s")%skill
	return subject if not source.is_empty() else ("技能的随机判定" if zh else "Random skill result")

func _chance_detail(outcome: Dictionary) -> String:
	var zh := Locale.language == "zh"
	var probability := int(outcome.get("probability", 0))
	match str(outcome.get("chance_scope", "")):
		"skill":
			return ("技能发动概率 %d%%" if zh else "Skill activation chance: %d%%") % probability
		"effect":
			var effect_id := str(outcome.get("effect_id", ""))
			var effect_name := Locale.term("effect", effect_id)
			var buff_id := str(outcome.get("buff_id", ""))
			if effect_id == "add_buff" and not buff_id.is_empty():
				effect_name = ("添加%s" if zh else "Apply %s") % Locale.term("buff", buff_id)
			return ("效果「%s」生效概率 %d%%" if zh else "%s (%d%% chance)") % [effect_name, probability]
		"block":
			return ("概率积木判定 %d%%" if zh else "Chance block: %d%%") % probability
		_:
			return ("有 %d%% 的概率触发" if zh else "%d%% chance to trigger") % probability

func play(outcome: Dictionary) -> void:
	busy = true
	visible = true
	wheel.outcome = outcome
	wheel.settled = false
	wheel.angle = 0
	var viewport := get_viewport().get_visible_rect().size
	_screen_size = viewport
	var s := minf(viewport.x/1280,viewport.y/720)
	var center := viewport*.5
	var origin: Vector2 = battle._random_wheel_origin(outcome)
	wheel.position = origin
	wheel.scale = Vector2.ONE*.22*s
	wheel.modulate.a = 0
	dim.size = viewport
	dim.modulate.a = 0
	title.text = _subject_text(outcome)
	title.position = Vector2(24,center.y-250*s)
	title.size = Vector2(viewport.x-48,64*s)
	title.add_theme_font_size_override("font_size",maxi(14,int(20*s)))
	detail.position = Vector2(0,center.y+192*s)
	detail.size = Vector2(viewport.x,60*s)
	detail.add_theme_font_size_override("font_size",maxi(16,int(23*s)))
	var chance := str(outcome.get("type",""))=="chance"
	if chance:
		detail.text = _chance_detail(outcome)
	else:
		detail.text = ("从 %d 到 %d 中抽取一个数" if Locale.language=="zh" else "Draw a number from %d to %d")%[int(outcome.get("minimum",1)),int(outcome.get("maximum",6))]
	title.modulate.a = 0
	detail.modulate.a = 0
	var intro := create_tween().set_parallel(true)
	intro.tween_property(wheel,"position",center,_duration(.24)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro.tween_property(wheel,"scale",Vector2.ONE*s,_duration(.24)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro.tween_property(wheel,"modulate:a",1.0,_duration(.16))
	intro.tween_property(dim,"modulate:a",1.0,_duration(.2))
	intro.tween_property(title,"modulate:a",1.0,_duration(.2))
	intro.tween_property(detail,"modulate:a",1.0,_duration(.2))
	await intro.finished
	_layout_for_size()
	var spin := create_tween()
	var turns := 0.0 if AppPreferences.get_value("reduced_motion") else 3.0
	spin.tween_property(wheel,"angle",-TAU*(turns+landing_fraction(outcome)),_duration(.95)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await spin.finished
	wheel.settled = true
	history.append(outcome.duplicate(true))
	if history.size()>32: history.pop_front()
	AppAudio.play("click" if chance else "draw_single")
	if not chance:
		detail.text = ("抽到了 %s" if Locale.language=="zh" else "Drew %s")%str(outcome.get("result",0))
	await get_tree().create_timer(_duration(.5)).timeout
	var outro := create_tween().set_parallel(true)
	outro.tween_property(wheel,"scale",Vector2.ONE*.94*s,_duration(.16))
	for control in [wheel,title,detail,dim]: outro.tween_property(control,"modulate:a",0.0,_duration(.16))
	await outro.finished
	visible = false
	busy = false
