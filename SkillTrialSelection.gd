extends RefCounted

# The editor can reconstruct its isolated sample from the same seed and the
# player's choices. This keeps the synchronous battle engine unchanged while
# later expressions still see the chosen cards before they execute.
var choices: Array = []
var pending: Dictionary = {}
var _cursor := 0

func run(skill: Dictionary, source: CardData, game: RefCounted, context: Dictionary, frames: Array) -> void:
	_cursor = 0
	pending = {}
	var deck_choice := func(count, draw_count, _player, _hand):
		var take: int = draw_count if draw_count > 0 else count*2
		_request({"kind":"deck","cards":game.shared_deck.slice(0,take),"limit":count},game,context,frames)
	var discard_choice := func(count, draw_count, _player, _hand):
		var cards: Array = game.shared_discard.slice(0,draw_count) if draw_count > 0 else game.shared_discard.duplicate()
		_request({"kind":"discard","cards":cards,"limit":count},game,context,frames)
	var hand_choice := func(value, mode, _player, hand, target, _count):
		var cards: Array = []
		for card: CardData in hand:
			if card.cost > 0: cards.append(card)
		_request({"kind":"hand","cards":cards,"limit":1,"reduction":value,"mode":mode,"target":target,"hand":hand},game,context,frames)
	var shuffle := func():
		if game.shared_deck.is_empty() and not game.shared_discard.is_empty():
			game.shared_deck = game.shared_discard.duplicate()
			game.shared_discard.clear()
			game._shuffle_shared_deck()
	EventBus.view_deck_select.connect(deck_choice)
	EventBus.view_discard_select.connect(discard_choice)
	EventBus.make_zero_cost_select.connect(hand_choice)
	EventBus.shuffle_discard_into_deck.connect(shuffle)
	SkillEngine.trigger_external_skill(skill,source,context)
	EventBus.view_deck_select.disconnect(deck_choice)
	EventBus.view_discard_select.disconnect(discard_choice)
	EventBus.make_zero_cost_select.disconnect(hand_choice)
	EventBus.shuffle_discard_into_deck.disconnect(shuffle)

func _request(request: Dictionary, game: RefCounted, context: Dictionary, frames: Array) -> void:
	if request.cards.is_empty(): return
	if _cursor < choices.size():
		var selected: Array = []
		for index: int in choices[_cursor]: selected.append(request.cards[index])
		_cursor += 1
		_apply(request,selected,game)
		if not frames.is_empty():
			var names: PackedStringArray = []
			for card: CardData in selected: names.append(card.card_name)
			frames.back().entry["chosen"] = names
			frames.back().entry["selection_neighbors"] = request.get("target","") in [SkillEngine.TARGET_SIDES,SkillEngine.TARGET_SELF_SIDES]
		return
	pending = request
	if not frames.is_empty(): frames.back().entry.event = "selection"
	# Abort only this disposable sample invocation, without a safety-limit
	# notification. Confirming the picker reconstructs it with the next choice.
	context._ugc_budget.aborted = true

func confirm(selected: Array) -> void:
	var indices: Array[int] = []
	for card in selected: indices.append(pending.cards.find(card))
	choices.append(indices)
	pending = {}

func _apply(request: Dictionary, selected: Array, game: RefCounted) -> void:
	if request.kind != "hand":
		var pile: Array = game.shared_deck if request.kind == "deck" else game.shared_discard
		for card: CardData in selected:
			pile.erase(card)
			game.resolve_hand_entry_for_player(card,request.kind,{},1)
		return
	var applied: Array = selected.duplicate()
	if request.target in [SkillEngine.TARGET_SIDES,SkillEngine.TARGET_SELF_SIDES]:
		for chosen: CardData in selected:
			var index: int = request.hand.find(chosen)
			for offset in [-1,1]:
				var adjacent: int = index+offset
				if adjacent >= 0 and adjacent < request.hand.size() and request.hand[adjacent] not in applied:
					applied.append(request.hand[adjacent])
	for card: CardData in applied:
		card.apply_cost_reduction(request.reduction,request.mode == SkillRegistry.COST_REDUCTION_PERMANENT)
