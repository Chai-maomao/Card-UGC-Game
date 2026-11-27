class_name BattleArtResolver
extends RefCounted

static func restore(game: RefCounted) -> void:
	if not PlayerData.is_online_battle():
		return
	var paths := local_art_index([PlayerData.battle_deck, PlayerData.opponent_battle_deck, PlayerData.card_library])
	for cards in [game.player_hand, game.player2_hand, game.shared_deck, game.shared_discard,
			game.player_field.slots, game.player2_field.slots]:
		for card: CardData in cards:
			restore_card(card, paths)


static func local_art_index(decks: Array) -> Dictionary:
	var by_instance := {}
	var by_card := {}
	var available := {}
	# Keep the lobby's downloaded art and the selected deck ahead of other copies
	# in the library. Match snapshots may contain paths from the other machine.
	for deck in decks:
		for card: CardData in deck:
			var paths := [_local_path(card.art_path, available), _local_path(card.damaged_art_path, available)]
			if paths == ["", ""]:
				continue
			var key := _card_identity_key(card)
			var exact: Array = by_instance.get(key, ["", ""])
			for index in [0, 1]:
				if exact[index].is_empty():
					exact[index] = paths[index]
			by_instance[key] = exact
			if not card.card_id.is_empty():
				var alternatives: Array = by_card.get_or_add(card.card_id, [[], []])
				for index in [0, 1]:
					if not paths[index].is_empty() and not alternatives[index].has(paths[index]):
						alternatives[index].append(paths[index])
	return {"by_instance": by_instance, "by_card": by_card, "available": available}


static func restore_card(card: CardData, paths: Dictionary) -> void:
	_restore_art_path(card, paths.by_instance, paths.by_card, paths.available)


static func _restore_art_path(card: CardData, by_instance: Dictionary, by_card: Dictionary = {}, available: Dictionary = {}) -> void:
	if card == null:
		return
	var exact: Array = by_instance.get(_card_identity_key(card), ["", ""])
	var alternatives: Array = by_card.get(card.card_id, [[], []])
	for index in [0, 1]:
		var field := "art_path" if index == 0 else "damaged_art_path"
		var path: String = exact[index]
		if path.is_empty():
			path = _local_path(card.get(field), available)
		# Copies of the same card can have different instance IDs. Use their art
		# only when the available local copies agree on the illustration.
		if path.is_empty() and alternatives[index].size() == 1:
			path = alternatives[index][0]
		card.set(field, path)
	for attached in card.parasite_cards:
		_restore_art_path(attached, by_instance, by_card, available)


static func _local_path(path: String, available: Dictionary) -> String:
	if path.is_empty():
		return ""
	if not available.has(path):
		available[path] = ResourceLoader.exists(path, "Texture2D") if path.begins_with("res://") else FileAccess.file_exists(path)
	return path if available[path] else ""


static func _card_identity_key(card: CardData) -> String:
	if not card.instance_id.is_empty(): return "instance:"+card.instance_id
	if not card.card_id.is_empty(): return "card:"+card.card_id
	return "%s|%d|%d|%d|%s" % [card.card_name, card.base_cost, card.base_max_hp, card.base_atk, card.gender]
