class_name BalanceCalibration
extends RefCounted


static func run(games_per_pool: int = 40) -> Dictionary:
	var pools := ["units", "spells", "support"]
	var rows: Array = []
	for index in range(pools.size()):
		var cards := _pool(pools[index])
		var result := HeadlessBattleSimulator.run_batch({"games": games_per_pool, "seed": 12000 + index * 1000, "deck_a": cards, "deck_b": cards, "swap_sides": true, "ai_a": "normal", "ai_b": "normal", "max_rounds": 30})
		var estimates: Array = []
		for card in cards:
			estimates.append({"name": card.card_name, "estimate": BalanceEvaluator.evaluate_card(card)})
		rows.append({"pool": pools[index], "simulation": result, "estimates": estimates})
	return {"version": 1, "games": games_per_pool * pools.size(), "note": "Shared draw-pool game: pool-level calibration, not independent constructed-deck matchup win rates. Estimates are heuristic; small samples are diagnostic only.", "pools": rows}


static func _pool(kind: String) -> Array:
	var cards: Array = []
	for i in range(8):
		var card := CardData.new("%s-%d" % [kind, i], 1 + i % 3, 3 + i % 4, 1 + i % 3)
		if kind == "spells" and i % 2 == 0:
			card = PracticeChallenges._spell("Flare-%d" % i, "damage", 2 + i % 3, "target_single", "enemy", 2)
		elif kind == "support" and i % 2 == 0:
			card.skills = [{"trigger": "on_summon", "skill_name": "Shield", "effects": [{"target": "self", "effect": "shield", "value": 2}]}]
		card.card_id = "calibration-%s-%d" % [kind, i]
		card.instance_id = card.card_id + "-instance"
		cards.append(card)
	return cards
