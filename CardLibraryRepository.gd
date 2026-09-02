class_name CardLibraryRepository
extends RefCounted


static func flatten(decks: Array) -> Array:
	var cards: Array = []
	for deck in decks:
		if deck is Dictionary:
			cards.append_array(deck.get("cards", []))
	return cards


static func find_deck(decks: Array, deck_id: String) -> Dictionary:
	for deck in decks:
		if deck is Dictionary and str(deck.get("id", "")) == deck_id:
			return deck
	return {}


static func find_card(decks: Array, card_id: String) -> CardData:
	for card in flatten(decks):
		if card is CardData and card.card_id == card_id:
			return card
	return null


static func find_instance_index(deck: Dictionary, instance_id: String) -> int:
	var cards: Array = deck.get("cards", [])
	for index in range(cards.size()):
		if cards[index] is CardData and cards[index].instance_id == instance_id:
			return index
	return -1
