class_name BattleArtResolver
extends RefCounted

static func restore(game: RefCounted) -> void:
	if not PlayerData.is_online_battle():
		return
	var local_art_by_key := {}
	# Opponent arts were downloaded during the lobby and saved to local net_arts
	# paths in opponent_battle_deck. The authority state carries the authority's
	# own (remote) art paths for these cards, so we must remap them to our local
	# copies — otherwise the non-authority can't display the opponent's art.
	for card in PlayerData.opponent_battle_deck:
		if card is CardData and (card.art_path != "" or card.damaged_art_path != ""):
			local_art_by_key[_card_identity_key(card)] = [card.art_path, card.damaged_art_path]
	# Our own cards take precedence on identity collisions.
	for card in PlayerData.battle_deck:
		if card is CardData and (card.art_path != "" or card.damaged_art_path != ""):
			local_art_by_key[_card_identity_key(card)] = [card.art_path, card.damaged_art_path]
	for card in PlayerData.card_library:
		if card is CardData and (card.art_path != "" or card.damaged_art_path != ""):
			local_art_by_key[_card_identity_key(card)] = [card.art_path, card.damaged_art_path]
	_restore_art_paths_in_cards(game.player_hand, local_art_by_key)
	_restore_art_paths_in_cards(game.player2_hand, local_art_by_key)
	_restore_art_paths_in_cards(game.shared_deck, local_art_by_key)
	_restore_art_paths_in_cards(game.shared_discard, local_art_by_key)
	_restore_art_paths_in_slots(game.player_field.slots, local_art_by_key)
	_restore_art_paths_in_slots(game.player2_field.slots, local_art_by_key)


static func _restore_art_paths_in_cards(cards: Array, local_art_by_key: Dictionary) -> void:
	for card in cards:
		_restore_art_path(card, local_art_by_key)


static func _restore_art_paths_in_slots(slots: Array, local_art_by_key: Dictionary) -> void:
	for card in slots:
		_restore_art_path(card, local_art_by_key)


static func _restore_art_path(card, local_art_by_key: Dictionary) -> void:
	if not (card is CardData):
		return
	var key := _card_identity_key(card)
	if local_art_by_key.has(key):
		card.art_path = local_art_by_key[key][0]
		card.damaged_art_path = local_art_by_key[key][1]
	for attached in card.parasite_cards:
		_restore_art_path(attached,local_art_by_key)


static func _card_identity_key(card: CardData) -> String:
	if not card.instance_id.is_empty(): return "instance:"+card.instance_id
	if not card.card_id.is_empty(): return "card:"+card.card_id
	return "%s|%d|%d|%d|%s" % [card.card_name, card.base_cost, card.base_max_hp, card.base_atk, card.gender]
