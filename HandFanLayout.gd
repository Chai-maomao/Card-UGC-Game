extends Container

var focused_card: Control
var _hover_tweens: Dictionary = {}
var _minimum_width := -1.0

# Card faces stay upright. Compression changes overlap, never text size.
func _get_minimum_size() -> Vector2:
	var height := 0.0
	var width := 0.0
	var count := 0
	for child in get_children():
		if child is Control:
			height = maxf(height, child.get_combined_minimum_size().y)
			width = maxf(width,child.get_combined_minimum_size().x)
			count += 1
	var fullness := minf(1.0,float(count-1)/maxi(1,SkillEngine.MAX_HAND_SIZE-1)) if count>1 else 0.0
	var span := maxf(0,size.x-width)*sqrt(fullness)
	var step := minf(width+10.0*width/120.0,span/maxi(1,count-1))
	var arc_height := (count-1)*step*.5*tan(deg_to_rad(4.0)) if count>1 else 0.0
	return Vector2(0, height + ceili(arc_height) + 12.0)


func _notification(what: int) -> void:
	if what==NOTIFICATION_RESIZED and not is_equal_approx(_minimum_width,size.x):
		_minimum_width=size.x
		update_minimum_size()
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var cards: Array[Control] = []
	for child in get_children():
		if child is Control and not child.is_queued_for_deletion():
			cards.append(child)
	if cards.is_empty():
		return
	var card_size := cards[0].get_combined_minimum_size()
	var count := cards.size()
	var gap := 10.0 * card_size.x / 120.0
	# Contract the fan at every hand size, including sizes that still overlap.
	var fullness := minf(1.0,float(count-1)/maxi(1,SkillEngine.MAX_HAND_SIZE-1))
	var span := maxf(0,size.x-card_size.x)*sqrt(fullness)
	var step := minf(card_size.x + gap, span/maxi(1,count-1))
	var width := card_size.x + (count - 1) * step
	var start := maxf(0, (size.x - width) * 0.5)
	for index in range(count):
		var spread := (float(index) / maxi(1, count - 1) - 0.5) * 2.0 if count > 1 else 0.0
		var fan_angle := deg_to_rad(8.0) * spread
		var radius := maxf(1.0, (count-1)*step*0.5) / sin(deg_to_rad(8.0))
		var rise := radius * (1.0-cos(fan_angle))
		cards[index].set_meta("hand_fan_angle",fan_angle)
		var hovered := cards[index] == focused_card
		var legacy_hover: bool = not cards[index].get_meta("tabletop_proxy",false) and bool(cards[index].get("_pointer_inside"))
		var legacy_scale := cards[index].scale
		var rest := Vector2(start + step * index,rise)
		if cards[index].get_meta("hand_rest_position",rest) != rest:
			# A return tween must not write its pre-discard position over the new fan.
			var id := cards[index].get_instance_id()
			var previous: Tween = _hover_tweens.get(id)
			if previous != null and previous.is_valid(): previous.kill()
			_hover_tweens.erase(id)
			cards[index].set_meta("hand_returning",false)
		fit_child_in_rect(cards[index], Rect2(rest, card_size))
		cards[index].set_meta("hand_rest_position", cards[index].position)
		if hovered:
			cards[index].scale = Vector2.ONE * 1.16
			cards[index].position.y -= 32.0 * card_size.x / 120.0
		elif legacy_hover:
			cards[index].scale = legacy_scale
			cards[index].position.y -= 14.0*card_size.x/120.0


# Hit areas follow the resting fan, so an enlarged card cannot steal its
# neighbors' exposed strips while the pointer moves across the hand.
func card_at_pointer(screen: Vector2) -> Control:
	var local := get_global_transform().affine_inverse() * screen
	var children := get_children()
	for index in range(children.size()-1,-1,-1):
		var card := children[index] as Control
		if card == null or card.is_queued_for_deletion() or card.get_meta("tabletop_arriving",false) or not card.has_meta("hand_rest_position"): continue
		if Rect2(card.get_meta("hand_rest_position"),card.size).has_point(local): return card
	if is_instance_valid(focused_card) and not focused_card.get_meta("tabletop_arriving",false) and focused_card.get_global_rect().has_point(screen): return focused_card
	return null


func focus_card(card: Control, enabled: bool) -> void:
	if enabled and card.get_meta("tabletop_arriving",false): return
	if enabled:
		if focused_card == card: return
		if is_instance_valid(focused_card): _animate_focus(focused_card,false)
		focused_card = card
		_animate_focus(card,true)
	elif focused_card == card:
		focused_card = null
		_animate_focus(card,false)


func _animate_focus(card: Control, enabled: bool) -> void:
	if not is_instance_valid(card) or card.is_queued_for_deletion(): return
	var previous: Tween = _hover_tweens.get(card.get_instance_id())
	if previous != null and previous.is_valid(): previous.kill()
	var rest: Vector2 = card.get_meta("hand_rest_position",card.position)
	card.set_meta("hand_focused",enabled)
	card.set_meta("hand_foreground",true)
	card.set_meta("hand_returning",not enabled)
	card.z_index = 20 if enabled else 0
	card.pivot_offset = Vector2(card.size.x*0.5,card.size.y)
	var tween := create_tween().set_parallel(true)
	_hover_tweens[card.get_instance_id()] = tween
	tween.tween_property(card,"position",rest-Vector2(0,32.0*card.size.x/120.0) if enabled else rest,0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card,"scale",Vector2.ONE*(1.16 if enabled else 1.0),0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var card_id := card.get_instance_id()
	var reference: WeakRef = weakref(card)
	tween.chain().tween_callback(func():
		_hover_tweens.erase(card_id)
		var returning_card = reference.get_ref()
		if returning_card != null: returning_card.set_meta("hand_returning",false))
