class_name SkillRegistry
extends RefCounted

# ============================================
# Skill domain catalog — single source of truth for every skill identifier
# and its metadata. SkillEngine re-exports the identifiers for compatibility;
# the editor, formatter and effect applier read metadata from here.
# ============================================

# --- Triggers ------------------------------------------------------------
const TRIGGER_ON_ATTACK   := "on_attack"
const TRIGGER_ON_ACTIVATE := "on_activate"
const TRIGGER_ON_SUMMON   := "on_summon"
const TRIGGER_ON_DEATH    := "on_death"
const TRIGGER_ON_DAMAGED  := "on_damaged"
const TRIGGER_ON_CAST     := "on_cast"
const TRIGGER_ON_TURN_START := "on_turn_start"
const TRIGGER_ON_TURN_END   := "on_turn_end"
const TRIGGER_ON_HEALED     := "on_healed"
const TRIGGER_ON_ATTACKED   := "on_attacked"

# --- Skill types -----------------------------------------------------------
const SKILL_TYPE_NORMAL  := "normal"
const SKILL_TYPE_TALENT  := "talent"

# --- Targets ---------------------------------------------------------------
const TARGET_SINGLE       := "target_single"
const TARGET_SIDES        := "target_sides"
const TARGET_SELF         := "self"
const TARGET_SELF_SIDES   := "self_sides"
const TARGET_ALL          := "all"
const TARGET_MALE         := "target_male"
const TARGET_FEMALE       := "target_female"
const TARGET_NONHUMAN     := "target_nonhuman"

const TARGET_SIDE_ENEMY   := "enemy"
const TARGET_SIDE_ALLY    := "ally"
const TARGET_SIDE_ALL     := "all"

# --- Effects ---------------------------------------------------------------
const EFFECT_DAMAGE             := "damage"
const EFFECT_HEAL               := "heal"
const EFFECT_ADD_BUFF           := "add_buff"
const EFFECT_DRAW_CARDS         := "draw_cards"
const EFFECT_SHIELD             := "shield"
const EFFECT_CHARM              := "charm"
const EFFECT_LIFESTEAL_DAMAGE   := "lifesteal_damage"
const EFFECT_EXECUTE            := "execute"
const EFFECT_CLEANSE            := "cleanse"
const EFFECT_DISPEL             := "dispel"
const EFFECT_GAIN_MANA          := "gain_mana"
const EFFECT_GAIN_ATTACK        := "gain_attack"
const EFFECT_GAIN_MAX_HP        := "gain_max_hp"
const EFFECT_VIEW_DISCARD       := "view_discard_select"
const EFFECT_VIEW_DECK          := "view_deck_select"
const EFFECT_ZERO_COST          := "make_zero_cost"
const EFFECT_MANA_DRAIN         := "mana_drain"
const EFFECT_SWAP_ATTACK        := "swap_attack"
const EFFECT_DISCARD_HAND       := "discard_hand"
const EFFECT_COPY_HAND          := "copy_hand"
const EFFECT_IF_ELSE            := "__if_else__"
const EFFECT_IF                 := "__if__"
const EFFECT_REPEAT             := "__repeat__"
const EFFECT_STOP               := "__stop__"

# --- Buffs -----------------------------------------------------------------
const BUFF_SILENCE          := "silence"
const BUFF_MISFORTUNE       := "misfortune"
const BUFF_ATK_BOOST        := "atk_boost"
const BUFF_REGEN            := "regen"
const BUFF_MANA_REFUND      := "mana_refund"
const BUFF_THORNS           := "thorns"
const BUFF_DAMAGE_REDUCTION := "damage_reduction"
const BUFF_TAUNT            := "taunt"
const BUFF_IMMUNE_LETHAL    := "immune_lethal"
const BUFF_POISON           := "poison"
const BUFF_STUN             := "stun"

# --- Dynamic value variables ------------------------------------------------
const VAR_FIELD_TOTAL   := "field_total"
const VAR_FIELD_ALLY    := "field_ally"
const VAR_FIELD_ENEMY   := "field_enemy"
const VAR_EMPTY_ALLY    := "empty_ally"
const VAR_EMPTY_ENEMY   := "empty_enemy"
const VAR_HAND_COUNT    := "hand_count"
const VAR_MANA_CURRENT  := "mana_current"
const VAR_ENEMY_HAND_COUNT := "enemy_hand_count"
const VAR_TURN_NUMBER   := "turn_number"
const VAR_DECK_COUNT    := "deck_count"
const VAR_ENEMY_MANA    := "enemy_mana"
# Target/source-stat reporters (Scratch-style oval blocks usable in
# comparisons; they read the current target/source card).
const VAR_SOURCE_HP_PCT := "source_hp_pct"
const VAR_TARGET_HP_PCT := "target_hp_pct"
const VAR_TARGET_ATK    := "target_atk"
const VAR_TARGET_COST   := "target_cost"

# --- Effect conditions --------------------------------------------------------
const CONDITION_NONE            := "none"
const CONDITION_SOURCE_HP_PCT   := "source_hp_pct"
const CONDITION_TARGET_HP_PCT   := "target_hp_pct"
const CONDITION_FIELD_ALLY      := "field_ally_count"
const CONDITION_FIELD_ENEMY     := "field_enemy_count"
const CONDITION_HAND_COUNT      := "hand_count"
const CONDITION_MANA_CURRENT    := "mana_current"
const CONDITION_TARGET_HAS_BUFF := "target_has_buff"
const CONDITION_TARGET_ATK      := "target_atk"
const CONDITION_TARGET_COST     := "target_cost"
const CONDITION_ENEMY_HAND_COUNT := "enemy_hand_count"
const CONDITION_TURN_NUMBER     := "turn_number"
const CONDITION_DECK_COUNT      := "deck_count"

const CONDITION_OP_GTE := ">="
const CONDITION_OP_LTE := "<="
const CONDITION_OP_EQ  := "=="


# ============================================
# Effect metadata
# ============================================
# requires_live_target: effect operates on battlefield units (needs live targets).
# allows_negative:      editor allows negative values (mana / attack / max-hp).
# force_self:           editor forces the target to self (hand / deck effects).
# uses_value:           effect consumes a numeric value (cleanse / dispel don't).
# handler:              static function name in SkillEffectApplier used to apply it.
# template:             Locale "effect_sentence" key for tooltip rendering.
# polarity:             "harmful" (score vs enemies) / "helpful" (score vs allies).
# score_kind:           balance formula: value_linear / value_diminishing /
#                       threshold / fixed / buff / none.
# score_weight:         balance coefficient for the matching score_kind.
# category:             "attack" / "defense" / "utility" (block-editor palette groups).
const EFFECT_META := {
	EFFECT_DAMAGE:            {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_damage", "template": "damage", "polarity": "harmful", "score_kind": "value_linear", "score_weight": 1.0, "category": "attack"},
	EFFECT_HEAL:              {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_heal", "template": "heal", "polarity": "helpful", "score_kind": "value_diminishing", "score_weight": 0.72, "category": "defense"},
	EFFECT_ADD_BUFF:          {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_buff", "template": "add_buff", "polarity": "helpful", "score_kind": "buff", "score_weight": 0.0, "category": "defense"},
	EFFECT_DRAW_CARDS:        {"requires_live_target": false, "allows_negative": false, "force_self": true,  "uses_value": true,
		"handler": "_apply_draw_cards", "template": "draw_cards", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 2.0, "category": "utility"},
	EFFECT_SHIELD:            {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_shield", "template": "shield", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 0.68, "category": "defense"},
	EFFECT_CHARM:             {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_charm", "template": "charm", "polarity": "harmful", "score_kind": "fixed", "score_weight": 3.0, "category": "attack"},
	EFFECT_LIFESTEAL_DAMAGE:  {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_lifesteal_damage", "template": "lifesteal_damage", "polarity": "harmful", "score_kind": "value_linear", "score_weight": 1.55, "category": "attack"},
	EFFECT_EXECUTE:           {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_execute", "template": "execute", "polarity": "harmful", "score_kind": "threshold", "score_weight": 0.9, "category": "attack"},
	EFFECT_CLEANSE:           {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": false,
		"handler": "_apply_cleanse", "template": "cleanse", "polarity": "helpful", "score_kind": "fixed", "score_weight": 1.2, "category": "defense"},
	EFFECT_DISPEL:            {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": false,
		"handler": "_apply_dispel", "template": "dispel", "polarity": "harmful", "score_kind": "fixed", "score_weight": 1.2, "category": "attack"},
	EFFECT_GAIN_MANA:         {"requires_live_target": false, "allows_negative": true,  "force_self": true,  "uses_value": true,
		"handler": "_apply_gain_mana", "template": "gain_mana", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 1.45, "category": "utility"},
	EFFECT_GAIN_ATTACK:       {"requires_live_target": true,  "allows_negative": true,  "force_self": false, "uses_value": true,
		"handler": "_apply_gain_attack", "template": "gain_attack", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 1.45, "category": "defense"},
	EFFECT_GAIN_MAX_HP:       {"requires_live_target": true,  "allows_negative": true,  "force_self": false, "uses_value": true,
		"handler": "_apply_gain_max_hp", "template": "gain_max_hp", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 1.05, "category": "defense"},
	EFFECT_VIEW_DISCARD:      {"requires_live_target": false, "allows_negative": false, "force_self": true,  "uses_value": true,
		"handler": "_apply_view_discard_select", "template": "view_discard_select", "polarity": "helpful", "score_kind": "none", "score_weight": 0.0, "category": "utility"},
	EFFECT_VIEW_DECK:         {"requires_live_target": false, "allows_negative": false, "force_self": true,  "uses_value": true,
		"handler": "_apply_view_deck_select", "template": "view_deck_select", "polarity": "helpful", "score_kind": "none", "score_weight": 0.0, "category": "utility"},
	EFFECT_ZERO_COST:         {"requires_live_target": false, "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "_apply_make_zero_cost", "template": "make_zero_cost", "polarity": "helpful", "score_kind": "none", "score_weight": 0.0, "category": "utility"},
	EFFECT_MANA_DRAIN:        {"requires_live_target": false, "allows_negative": false, "force_self": true,  "uses_value": true,
		"handler": "_apply_mana_drain", "template": "mana_drain", "polarity": "harmful", "score_kind": "value_linear", "score_weight": 1.2, "category": "attack"},
	EFFECT_SWAP_ATTACK:       {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": false,
		"handler": "_apply_swap_attack", "template": "swap_attack", "polarity": "harmful", "score_kind": "fixed", "score_weight": 2.0, "category": "attack"},
	EFFECT_DISCARD_HAND:      {"requires_live_target": false, "allows_negative": false, "force_self": true,  "uses_value": true,
		"handler": "_apply_discard_hand", "template": "discard_hand", "polarity": "harmful", "score_kind": "value_linear", "score_weight": 1.5, "category": "attack"},
	EFFECT_COPY_HAND:         {"requires_live_target": false, "allows_negative": false, "force_self": true,  "uses_value": true,
		"handler": "_apply_copy_hand", "template": "copy_hand", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 1.2, "category": "utility"},
	EFFECT_IF_ELSE:           {"requires_live_target": false, "allows_negative": false, "force_self": false, "uses_value": false,
		"handler": "", "template": "if_else", "polarity": "helpful", "score_kind": "none", "score_weight": 0.0, "category": "control"},
	EFFECT_IF:                {"requires_live_target": false, "allows_negative": false, "force_self": false, "uses_value": false,
		"handler": "", "template": "if", "polarity": "helpful", "score_kind": "none", "score_weight": 0.0, "category": "control"},
	EFFECT_REPEAT:            {"requires_live_target": false, "allows_negative": false, "force_self": false, "uses_value": true,
		"handler": "", "template": "repeat", "polarity": "helpful", "score_kind": "none", "score_weight": 0.0, "category": "control"},
	EFFECT_STOP:              {"requires_live_target": false, "allows_negative": false, "force_self": false, "uses_value": false,
		"handler": "", "template": "stop", "polarity": "helpful", "score_kind": "none", "score_weight": 0.0, "category": "control"},
}

# Editor dropdown order for effects (must match the previous hardcoded order).
const EFFECT_IDS := [
	EFFECT_DAMAGE, EFFECT_HEAL, EFFECT_DRAW_CARDS, EFFECT_SHIELD,
	EFFECT_CHARM, EFFECT_ADD_BUFF, EFFECT_LIFESTEAL_DAMAGE, EFFECT_EXECUTE,
	EFFECT_CLEANSE, EFFECT_DISPEL, EFFECT_GAIN_MANA, EFFECT_GAIN_ATTACK,
	EFFECT_GAIN_MAX_HP, EFFECT_VIEW_DISCARD, EFFECT_VIEW_DECK, EFFECT_ZERO_COST,
	EFFECT_MANA_DRAIN, EFFECT_SWAP_ATTACK, EFFECT_DISCARD_HAND, EFFECT_COPY_HAND,
]


# ============================================
# Buff metadata
# ============================================
# polarity: "negative" (removed by cleanse) / "positive" (removed by dispel).
# value_meaningful: whether the buff consumes a numeric value (taunt/silence don't).
const BUFF_META := {
	BUFF_ATK_BOOST:        {"polarity": "positive", "value_meaningful": true},
	BUFF_REGEN:            {"polarity": "positive", "value_meaningful": true},
	BUFF_MANA_REFUND:      {"polarity": "positive", "value_meaningful": true},
	BUFF_THORNS:           {"polarity": "positive", "value_meaningful": true},
	BUFF_DAMAGE_REDUCTION: {"polarity": "positive", "value_meaningful": true},
	BUFF_TAUNT:            {"polarity": "positive", "value_meaningful": false},
	BUFF_SILENCE:          {"polarity": "negative", "value_meaningful": false},
	BUFF_MISFORTUNE:       {"polarity": "negative", "value_meaningful": true},
	BUFF_IMMUNE_LETHAL:    {"polarity": "positive", "value_meaningful": true},
	BUFF_POISON:           {"polarity": "negative", "value_meaningful": true},
	BUFF_STUN:             {"polarity": "negative", "value_meaningful": false},
}

# Editor dropdown order for buffs.
const BUFF_IDS := [
	BUFF_ATK_BOOST, BUFF_REGEN, BUFF_MANA_REFUND, BUFF_THORNS,
	BUFF_DAMAGE_REDUCTION, BUFF_TAUNT, BUFF_SILENCE, BUFF_MISFORTUNE,
	BUFF_IMMUNE_LETHAL, BUFF_POISON, BUFF_STUN,
]


# ============================================
# Trigger metadata
# ============================================
# passive: whether the trigger is eligible for the "talent" (天赋) skill type.
const TRIGGER_META := {
	TRIGGER_ON_ATTACK:   {"passive": true},
	TRIGGER_ON_ACTIVATE: {"passive": false},
	TRIGGER_ON_SUMMON:   {"passive": true},
	TRIGGER_ON_DEATH:    {"passive": true},
	TRIGGER_ON_DAMAGED:  {"passive": true},
	TRIGGER_ON_CAST:     {"passive": false},
	TRIGGER_ON_TURN_START: {"passive": true},
	TRIGGER_ON_TURN_END:   {"passive": true},
	TRIGGER_ON_HEALED:     {"passive": true},
	TRIGGER_ON_ATTACKED:   {"passive": true},
}


# ============================================
# Editor dropdown lists (order-preserving)
# ============================================
const TARGET_IDS := [
	TARGET_SINGLE, TARGET_SIDES, TARGET_SELF, TARGET_SELF_SIDES,
	TARGET_ALL,
	TARGET_MALE, TARGET_FEMALE, TARGET_NONHUMAN,
]
const TARGET_SIDE_IDS := [TARGET_SIDE_ENEMY, TARGET_SIDE_ALLY, TARGET_SIDE_ALL]
const VALUE_VAR_IDS := [
	VAR_FIELD_TOTAL, VAR_FIELD_ALLY, VAR_FIELD_ENEMY,
	VAR_EMPTY_ALLY, VAR_EMPTY_ENEMY, VAR_HAND_COUNT, VAR_MANA_CURRENT,
	VAR_ENEMY_HAND_COUNT, VAR_TURN_NUMBER, VAR_DECK_COUNT, VAR_ENEMY_MANA,
	VAR_SOURCE_HP_PCT, VAR_TARGET_HP_PCT, VAR_TARGET_ATK, VAR_TARGET_COST,
]
const CONDITION_IDS := [
	CONDITION_NONE, CONDITION_SOURCE_HP_PCT, CONDITION_TARGET_HP_PCT,
	CONDITION_FIELD_ALLY, CONDITION_FIELD_ENEMY, CONDITION_HAND_COUNT,
	CONDITION_MANA_CURRENT, CONDITION_TARGET_HAS_BUFF,
	CONDITION_TARGET_ATK, CONDITION_TARGET_COST,
	CONDITION_ENEMY_HAND_COUNT, CONDITION_TURN_NUMBER, CONDITION_DECK_COUNT,
]
const CONDITION_OP_IDS := [CONDITION_OP_GTE, CONDITION_OP_LTE, CONDITION_OP_EQ]


# ============================================
# Queries
# ============================================

static func effect_meta(effect_id: String) -> Dictionary:
	return EFFECT_META.get(effect_id, {})


static func is_hand_effect(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return not bool(meta.get("requires_live_target", true))


static func allows_negative(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return bool(meta.get("allows_negative", false))


static func force_self(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return bool(meta.get("force_self", false))


static func uses_value(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return bool(meta.get("uses_value", true))


static func buff_polarity(buff_id: String) -> String:
	var meta: Dictionary = BUFF_META.get(buff_id, {})
	return str(meta.get("polarity", "neutral"))


static func buff_uses_value(buff_id: String) -> bool:
	var meta: Dictionary = BUFF_META.get(buff_id, {})
	return bool(meta.get("value_meaningful", true))


static func negative_buffs() -> Array:
	return _buffs_with_polarity("negative")


static func positive_buffs() -> Array:
	return _buffs_with_polarity("positive")


static func trigger_is_passive(trigger_id: String) -> bool:
	var meta: Dictionary = TRIGGER_META.get(trigger_id, {})
	return bool(meta.get("passive", true))


static func _buffs_with_polarity(polarity: String) -> Array:
	var result: Array = []
	for buff_id in BUFF_META:
		if buff_polarity(buff_id) == polarity:
			result.append(buff_id)
	return result
