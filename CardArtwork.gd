class_name CardArtwork
extends RefCounted

const NORMAL := "res://res/tabletop/unillustrated_card.png"
const DAMAGED := "res://res/tabletop/unillustrated_card_damaged.png"

static func selected_path(card: CardData, displayed_hp: int = -1, displayed_max_hp: int = -1) -> String:
	var hp := card.hp if displayed_hp < 0 else displayed_hp
	var max_hp := card.max_hp if displayed_max_hp < 0 else displayed_max_hp
	var wounded := not card.is_spell() and max_hp > 0 and hp < max_hp
	if wounded and not card.damaged_art_path.is_empty(): return card.damaged_art_path
	if not card.art_path.is_empty(): return card.art_path
	return DAMAGED if wounded else NORMAL

static func texture_for(card: CardData, displayed_hp: int = -1, displayed_max_hp: int = -1) -> Texture2D:
	# Missing alternate files fall back to the user's primary image first.
	# A single custom image never borrows the default wounded illustration.
	for path in [selected_path(card, displayed_hp, displayed_max_hp),card.art_path,NORMAL]:
		if str(path).is_empty(): continue
		if str(path).begins_with("res://"):
			if ResourceLoader.exists(path,"Texture2D"): return load(path) as Texture2D
		elif FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty(): return ImageTexture.create_from_image(image)
	return null


static func deck_cover(deck: Dictionary) -> Texture2D:
	var cards: Array = deck.get("cards", [])
	var cover_id: String = deck.get("cover_instance_id", "")
	if not cover_id.is_empty():
		for card: CardData in cards:
			if card.instance_id == cover_id:
				return texture_for(card, card.max_hp, card.max_hp)
	for item in cards:
		var card := item as CardData
		if card != null and not card.art_path.is_empty():
			return texture_for(card, card.max_hp, card.max_hp)
	return load(NORMAL) as Texture2D if not cards.is_empty() else null
