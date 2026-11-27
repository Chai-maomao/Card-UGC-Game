extends RefCounted

const MIN_MULTIPLIER := 0.75
const MAX_MULTIPLIER := 1.15


static func prepare_card(card: CardData) -> CardData:
	var fresh := card.duplicate_card()
	fresh.permanent_cost_reduction = 0
	fresh.match_cost_delta = 0
	fresh.attack_ignores_silence = false
	fresh.reset_to_base()
	return fresh


static func min_cards() -> int:
	return preload("res://GameState.gd").opening_hand_size(PlayerData.DEFAULT_BATTLE_CONFIG)


static func evaluate(cards: Array, rating: int) -> Dictionary:
	var mean := 0.0
	var sum_squared_deviations := 0.0
	var count := 0
	for card: CardData in cards:
		var gap := float(BalanceEvaluator.evaluate_card(card).gap)
		count += 1
		var delta := gap - mean
		mean += delta / count
		sum_squared_deviations += delta * (gap - mean)
	var variance := maxf(0.0, sum_squared_deviations / maxi(count, 1))
	var mean_penalty := absf(mean) / (BalanceEvaluator.POINTS_PER_COST + absf(mean))
	var variance_scale := BalanceEvaluator.POINTS_PER_COST ** 2
	var variance_penalty := variance / (variance_scale + variance)
	var strictness := lerpf(0.80, 1.20, clampf((rating - 600.0) / 1200.0, 0.0, 1.0))
	var multiplier := clampf(MAX_MULTIPLIER - strictness * (0.34 * mean_penalty + 0.26 * variance_penalty),
		MIN_MULTIPLIER, MAX_MULTIPLIER)
	return {"mean": mean, "variance": variance, "multiplier": snappedf(multiplier, 0.01)}


static func validated_multiplier(value: Variant) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), MIN_MULTIPLIER, MAX_MULTIPLIER)
	return 1.0
