extends CanvasLayer

signal picked(index: int)
const Back = preload("res://presentation/EnemyHandBack.gd")
const Face = preload("res://presentation/ClassicBattleCardFace.gd")
const HOVER_REVEAL_DISTANCE := 24.0
var battle: Node
var backs: Array[Button] = []
var dim: ColorRect
var prompt: Label
var expansion := 0.0
var busy := false
var accepting := false
var hovered := -1
var reserved: Array[int] = []
var reserved_tokens: Array = []
var selected_count := 0
var pending_own_faces: Dictionary = {}
var _pointer := Vector2(-1, -1)

# Preserve the visible face before a network snapshot removes/reflows the hand.
# The same node waits for its feedback turn and then flies; no second spawn.
func preserve_own_faces(cards: Array) -> void:
	if battle.tabletop == null: return
	for outcome in cards:
		var id := str(outcome.get("card",{}).get("instance_id",""))
		if pending_own_faces.has(id): continue
		for source in battle.hand_container.get_children():
			if source.current_card_data.instance_id != id: continue
			var key: int = 10+source.get_index()
			if not battle.tabletop.cards.has(key): continue
			var entry: Dictionary = battle.tabletop.cards[key]
			var texture: Texture2D = entry.top.material_override.albedo_texture
			var points: PackedVector2Array = battle._hand_face_points(entry)
			var center := (points[0]+points[1]+points[2]+points[3])*.25
			var face := Polygon2D.new()
			face.name = "PendingOwnDiscard"
			face.texture = ImageTexture.create_from_image(texture.get_image())
			face.position = center
			for index in range(points.size()): points[index] -= center
			face.polygon = points
			var size := texture.get_size()
			face.uv = PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])
			face.z_index = 65
			battle.get_node("CanvasLayer").add_child(face)
			pending_own_faces[id] = face
			break

func _ready() -> void:
	layer = 0
	get_window().mouse_exited.connect(func(): _pointer = Vector2(-1, -1))
	dim = ColorRect.new()
	dim.name = "EnemyHandDimmer"
	dim.color = Color(0.015,0.025,0.03,.63)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.hide()
	prompt = Label.new()
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(prompt)
	add_child(prompt)
	prompt.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer = event.position

func reserve_count(count: int,discard_count: int) -> void:
	reserved.append(count)
	var tokens: Array = []
	for index in range(discard_count): tokens.append(battle._hold_pile_addition(1))
	reserved_tokens.append(tokens)

func _process(delta: float) -> void:
	if not is_instance_valid(battle) or battle.game == null: return
	if not busy:
		var hand: Array = battle.game.player2_hand if battle._view_player()==1 else battle.game.player_hand
		_set_count(reserved[0] if not reserved.is_empty() and reserved[0]>=0 else hand.size())
	_layout(delta)

func _set_count(count: int) -> void:
	while backs.size()>count:
		backs.pop_back().queue_free()
	while backs.size()<count:
		var back := Back.new()
		back.name = "EnemyHandBack"
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.focus_mode = Control.FOCUS_NONE
		add_child(back)
		backs.append(back)
		back.pressed.connect(func():
			if accepting:
				accepting = false
				picked.emit(backs.find(back)))
		back.mouse_entered.connect(func():
			if accepting: hovered=backs.find(back); AppAudio.play_hover(back,true))
		back.mouse_exited.connect(func():
			if hovered==backs.find(back): hovered=-1)
		back.focus_entered.connect(func():
			if accepting: hovered=backs.find(back))
		back.set_meta("new_back",true)
	if prompt.get_index()!=get_child_count()-1: move_child(prompt,get_child_count()-1)

func _layout(delta: float) -> void:
	var viewport := get_viewport().get_visible_rect().size
	var s := minf(viewport.x/1280.0,viewport.y/720.0)
	var card_size := Vector2(116,116.0*908.0/680.0)*s
	var rest_bottom: float = battle.enemy_status_hud.get_global_rect().end.y+10*s
	var span := minf(viewport.x*lerpf(.43,.56,expansion),maxi(0,backs.size()-1)*card_size.x*.77)
	var step := span/maxi(1,backs.size()-1)
	var top := lerpf(rest_bottom-card_size.y,-card_size.y*.4,expansion)
	if _is_hovering_hand():
		top += HOVER_REVEAL_DISTANCE * s
	dim.size = viewport
	prompt.text = "选择一张敌方手牌" if Locale.language=="zh" else "Choose an opposing card"
	prompt.position = Vector2(0,card_size.y*.6+22*s)
	prompt.size = Vector2(viewport.x,30*s)
	prompt.add_theme_font_size_override("font_size",maxi(12,int(18*s)))
	for index in range(backs.size()):
		var card := backs[index]
		if card.get_meta("flying",false): continue
		var spread := (float(index)/maxi(1,backs.size()-1)-.5)*2 if backs.size()>1 else 0.0
		var highlight := accepting and index==hovered
		var target := Vector2((viewport.x-span-card_size.x)*.5+step*index,top-18*s*spread*spread+(10*s if highlight else 0))
		card.size = card_size
		card.pivot_offset = card_size*.5
		card.z_index = 20 if highlight else index
		card.rim.visible = highlight
		var weight := 1.0 if card.get_meta("new_back",false) or AppPreferences.get_value("reduced_motion") else 1.0-exp(-24*delta)
		card.position = card.position.lerp(target,weight)
		card.rotation = lerp_angle(card.rotation,deg_to_rad(-spread*lerpf(9,5,expansion)),weight)
		card.scale = card.scale.lerp(Vector2.ONE*(1.035 if highlight else 1.0),weight)
		card.set_meta("new_back",false)

func _is_hovering_hand() -> bool:
	if busy or backs.is_empty() or battle.battle_finished or UIMotion.top_popup() != null:
		return false
	var viewport := get_viewport()
	if not viewport.get_visible_rect().has_point(_pointer):
		return false
	for card in backs:
		var local := card.get_global_transform_with_canvas().affine_inverse() * _pointer
		if Rect2(Vector2.ZERO, card.size).has_point(local):
			return true
	return false

func _duration(value: float) -> float:
	return .01 if AppPreferences.get_value("reduced_motion") else value

func _enable_choices(enabled: bool) -> void:
	accepting = enabled
	for card in backs:
		card.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		card.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		card.disabled = not enabled
	if enabled and not backs.is_empty():
		for index in range(backs.size()):
			backs[index].focus_neighbor_left = backs[index].get_path_to(backs[(index+backs.size()-1)%backs.size()])
			backs[index].focus_neighbor_right = backs[index].get_path_to(backs[(index+1)%backs.size()])
		backs[0].grab_focus()


func cancel_pending_pick() -> void:
	if accepting:
		picked.emit(-1)


func play(event: Dictionary) -> void:
	busy = true
	selected_count = 0
	var cards: Array = event.get("cards",[])
	var actor := int(event.get("player",0))
	var tokens: Array = reserved_tokens.pop_front() if not reserved_tokens.is_empty() else []
	if not reserved.is_empty(): reserved.pop_front()
	if tokens.is_empty():
		for index in range(cards.size()): tokens.append(battle._hold_pile_addition(1))
	battle._update_pile_labels()
	if actor != battle._view_player():
		await _play_own_discard(cards,int(event.get("before_count",cards.size())),tokens)
		busy = false
		return
	_set_count(int(event.get("before_count",cards.size())))
	layer = 30
	dim.show()
	dim.modulate.a = 0
	var open := create_tween().set_parallel(true)
	open.tween_property(self,"expansion",1.0,_duration(.26)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	open.tween_property(dim,"modulate:a",1.0,_duration(.18))
	await open.finished
	open = null
	prompt.show()
	for _outcome in cards:
		if backs.is_empty(): break
		_enable_choices(true)
		var choice: int = await picked
		_enable_choices(false)
		if choice < 0:
			for token in tokens:
				battle._finish_pile_addition(int(token))
			prompt.hide()
			dim.hide()
			expansion = 0.0
			layer = 0
			hovered = -1
			busy = false
			return
		if choice >= backs.size(): choice = 0
		var chosen := backs[choice]
		chosen.set_meta("flying",true)
		chosen.z_index = 60
		chosen.rim.hide()
		AppAudio.play("draw")
		await _reveal_chosen(chosen,_outcome)
		await _fly(chosen,battle._discard_fly_target())
		backs.erase(chosen)
		chosen.queue_free()
		selected_count += 1
		battle._finish_pile_addition(int(tokens.pop_front()))
		hovered = -1
		battle._play_discard_pile_arrival(UITheme.Tokens.PAPER)
	prompt.hide()
	var close := create_tween().set_parallel(true)
	close.tween_property(self,"expansion",0.0,_duration(.24)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	close.tween_property(dim,"modulate:a",0.0,_duration(.18))
	await close.finished
	dim.hide()
	layer = 0
	busy = false

func _reveal_chosen(chosen: Control,outcome: Dictionary) -> void:
	# Pull the chosen back clear of the fan, turn edge-on, then reveal only
	# the already-resolved outcome. The visual choice never changes the RNG.
	var original := chosen.scale
	var pull := create_tween().set_parallel(true)
	pull.tween_property(chosen,"position:y",maxf(chosen.position.y,24*battle._ui_scale()),_duration(.16)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pull.tween_property(chosen,"rotation",0.0,_duration(.16))
	await pull.finished
	var turn := create_tween()
	turn.tween_property(chosen,"scale:x",.025,_duration(.14)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await turn.finished
	chosen.get_node("CardBackArtwork").hide()
	var face := Face.new()
	face.name = "RevealedDiscardFace"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size = Vector2(384,528)
	face.scale = chosen.size/face.size
	chosen.add_child(face)
	face.bind(PlayerData.deserialize_card(outcome.get("card",{})),false)
	var reveal := create_tween()
	reveal.tween_property(chosen,"scale:x",original.x,_duration(.18)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await reveal.finished
	await get_tree().create_timer(_duration(.16)).timeout

func _fly(card: Control,target: Vector2) -> void:
	var start := card.position+card.size*.5
	var original_scale := card.scale
	var bend := start.lerp(target,.48)-Vector2(0,70*battle._ui_scale())
	var tween := create_tween().set_parallel(true)
	tween.tween_method(func(t: float): card.position=start.lerp(bend,t).lerp(bend.lerp(target,t),t)-card.size*.5,0.0,1.0,_duration(.52)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(card,"scale",original_scale*.65,_duration(.52))
	tween.tween_property(card,"rotation",-.16,_duration(.52))
	tween.tween_property(card,"modulate:a",0.0,_duration(.12)).set_delay(_duration(.4))
	await tween.finished

func _play_own_discard(cards: Array,before_count: int,tokens: Array) -> void:
	for outcome in cards:
		var card := PlayerData.deserialize_card(outcome.get("card",{}))
		var preserved: Polygon2D = pending_own_faces.get(card.instance_id)
		if is_instance_valid(preserved):
			pending_own_faces.erase(card.instance_id)
			await _fly_preserved(preserved,battle._discard_fly_target())
			preserved.queue_free()
			battle._finish_pile_addition(int(tokens.pop_front()))
			battle._play_discard_pile_arrival(UITheme.Tokens.PAPER)
			continue
		var face := Face.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.size = Vector2(384,528)
		face.scale = Vector2.ONE*(116*battle._ui_scale()/384)
		face.pivot_offset = face.size*.5
		face.bind(card,false)
		battle.get_node("CanvasLayer").add_child(face)
		face.z_index = 65
		var bounds: Rect2 = battle.hand_container.get_global_rect()
		var fraction := (float(outcome.get("index",0))+.5)/maxi(1,before_count)
		var origin := Vector2(lerpf(bounds.position.x,bounds.end.x,fraction),bounds.get_center().y)
		if outcome.has("origin"): origin = Vector2(float(outcome.origin[0]),float(outcome.origin[1]))
		face.position = origin-face.size*.5
		await _fly(face,battle._discard_fly_target())
		face.queue_free()
		battle._finish_pile_addition(int(tokens.pop_front()))
		battle._play_discard_pile_arrival(UITheme.Tokens.PAPER)

func _fly_preserved(face: Polygon2D,target: Vector2) -> void:
	var start := face.position
	var bend := start.lerp(target,.48)-Vector2(0,70*battle._ui_scale())
	var tween := create_tween().set_parallel(true)
	tween.tween_method(func(t: float): face.position=start.lerp(bend,t).lerp(bend.lerp(target,t),t),0.0,1.0,_duration(.52)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(face,"scale",Vector2.ONE*.65,_duration(.52))
	tween.tween_property(face,"rotation",-.16,_duration(.52))
	tween.tween_property(face,"modulate:a",0.0,_duration(.12)).set_delay(_duration(.4))
	await tween.finished
