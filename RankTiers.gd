extends RefCounted

const TIERS := [
	{"minimum": 0, "id": "bronze", "badge": preload("res://res/ui/ranks/bronze.svg")},
	{"minimum": 900, "id": "silver", "badge": preload("res://res/ui/ranks/silver.svg")},
	{"minimum": 1100, "id": "gold", "badge": preload("res://res/ui/ranks/gold.svg")},
	{"minimum": 1300, "id": "platinum", "badge": preload("res://res/ui/ranks/platinum.svg")},
	{"minimum": 1500, "id": "diamond", "badge": preload("res://res/ui/ranks/diamond.svg")},
	{"minimum": 1750, "id": "master", "badge": preload("res://res/ui/ranks/master.svg")},
]


static func tier_index(rating: int) -> int:
	var index := 0
	while index + 1 < TIERS.size() and rating >= int(TIERS[index + 1].minimum):
		index += 1
	return index
