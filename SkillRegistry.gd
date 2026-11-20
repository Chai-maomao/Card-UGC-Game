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
const TRIGGER_ON_ADDED      := "on_added"
const TRIGGER_ON_DISCARDED  := "on_discarded"
const TRIGGER_ON_BOARD_CHANGED := "on_board_changed"
const TRIGGER_ALWAYS        := "always"

# --- Skill types -----------------------------------------------------------
const SKILL_TYPE_NORMAL  := "normal"
const SKILL_TYPE_TALENT  := "talent"

# --- Targets ---------------------------------------------------------------
const TARGET_SINGLE       := "target_single"
const TARGET_SIDES        := "target_sides"
const TARGET_SELF         := "self"
const TARGET_SELF_SIDES   := "self_sides"
const TARGET_ALL          := "all"
const TARGET_PLAYER       := "player"
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
const EFFECT_CLONE_ENEMY        := "clone_enemy"
const EFFECT_MATCH_MAX_HP       := "match_max_hp"
const EFFECT_DAMAGE_CAP         := "damage_cap"
const EFFECT_CHANGE_COST        := "change_cost"
const EFFECT_IF_ELSE            := "__if_else__"
const EFFECT_IF                 := "__if__"
const EFFECT_REPEAT             := "__repeat__"
const EFFECT_STOP               := "__stop__"

const COST_REDUCTION_TURN := "turn"
const COST_REDUCTION_PERMANENT := "permanent"
const COST_REDUCTION_MODES := [COST_REDUCTION_TURN, COST_REDUCTION_PERMANENT]

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
	EFFECT_CHARM:             {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": false,
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
	EFFECT_CLONE_ENEMY:       {"requires_live_target": true,  "allows_negative": false, "force_self": false, "uses_value": false,
		"handler": "_apply_clone_enemy", "template": "clone_enemy", "polarity": "helpful", "score_kind": "fixed", "score_weight": 2.5, "category": "utility"},
	EFFECT_MATCH_MAX_HP:      {"requires_live_target": true, "allows_negative": false, "force_self": true, "uses_value": true,
		"handler": "_apply_match_max_hp", "template": "match_max_hp", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 1.25, "category": "defense", "talent_only": true},
	EFFECT_DAMAGE_CAP:        {"requires_live_target": true, "allows_negative": false, "force_self": true, "uses_value": true,
		"handler": "_apply_damage_cap", "template": "damage_cap", "polarity": "helpful", "score_kind": "fixed", "score_weight": 2.5, "category": "defense", "talent_only": true, "continuous": true},
	EFFECT_CHANGE_COST:       {"requires_live_target": true, "allows_negative": true, "force_self": false, "uses_value": true,
		"handler": "_apply_change_cost", "template": "change_cost", "polarity": "helpful", "score_kind": "value_linear", "score_weight": 0.8, "category": "utility"},
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
	EFFECT_CLONE_ENEMY, EFFECT_CHANGE_COST,
	EFFECT_MATCH_MAX_HP, EFFECT_DAMAGE_CAP,
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
	BUFF_IMMUNE_LETHAL:    {"polarity": "positive", "value_meaningful": false},
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
# passive: whether the trigger executes without a manual action. Talent editor
# availability is intentionally narrower and defined below.
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
	TRIGGER_ON_ADDED:      {"passive": true},
	TRIGGER_ON_DISCARDED:  {"passive": true},
	TRIGGER_ON_BOARD_CHANGED: {"passive": true},
	TRIGGER_ALWAYS:        {"passive": true, "talent_only": true},
}

# Talents are intentionally a small, lifecycle-oriented vocabulary rather
# than a fourth ordinary skill slot. Each trigger exposes only the effect that
# expresses its unique persistent/lifecycle purpose.
const TALENT_EFFECTS_BY_TRIGGER := {
	TRIGGER_ALWAYS: [EFFECT_DAMAGE_CAP],
	TRIGGER_ON_ADDED: [EFFECT_MATCH_MAX_HP, EFFECT_CHANGE_COST],
	TRIGGER_ON_DISCARDED: [EFFECT_GAIN_MANA, EFFECT_CHANGE_COST],
	TRIGGER_ON_BOARD_CHANGED: [EFFECT_CHANGE_COST],
}


# ============================================
# Editor dropdown lists (order-preserving)
# ============================================
const TARGET_IDS := [
	TARGET_SINGLE, TARGET_SIDES, TARGET_SELF, TARGET_SELF_SIDES,
	TARGET_ALL, TARGET_PLAYER,
	TARGET_MALE, TARGET_FEMALE, TARGET_NONHUMAN,
]
const TARGET_SIDE_IDS := [TARGET_SIDE_ENEMY, TARGET_SIDE_ALLY, TARGET_SIDE_ALL]
const VALUE_VAR_IDS := [
	VAR_FIELD_TOTAL, VAR_FIELD_ALLY, VAR_FIELD_ENEMY,
	VAR_EMPTY_ALLY, VAR_EMPTY_ENEMY, VAR_HAND_COUNT, VAR_MANA_CURRENT,
	VAR_ENEMY_HAND_COUNT, VAR_TURN_NUMBER, VAR_DECK_COUNT, VAR_ENEMY_MANA,
	VAR_SOURCE_HP_PCT, VAR_TARGET_HP_PCT, VAR_TARGET_ATK, VAR_TARGET_COST,
]
const TARGET_RELATIVE_VAR_IDS := [VAR_TARGET_HP_PCT, VAR_TARGET_ATK, VAR_TARGET_COST]
const TARGET_RELATIVE_CONDITION_IDS := [
	CONDITION_TARGET_HP_PCT, CONDITION_TARGET_HAS_BUFF,
	CONDITION_TARGET_ATK, CONDITION_TARGET_COST,
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

static func palette_category(effect_id: String) -> String:
	if effect_id in [EFFECT_ADD_BUFF, EFFECT_CLEANSE, EFFECT_DISPEL, EFFECT_CHARM]: return "status"
	return str(effect_meta(effect_id).get("category", "utility"))


static func is_hand_effect(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return not bool(meta.get("requires_live_target", true))


static func requires_live_target(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return bool(meta.get("requires_live_target", true))


# Player bodies deliberately support only the two effects that have a clear
# hero-level meaning. Other live-target effects remain unit-only.
static func allows_player_target(effect_id: String) -> bool:
	return effect_id in [EFFECT_DAMAGE, EFFECT_HEAL]


static func is_control_effect(effect_id: String) -> bool:
	return effect_id in [EFFECT_IF_ELSE, EFFECT_IF, EFFECT_REPEAT, EFFECT_STOP]


static func is_target_relative_var(var_id: String) -> bool:
	return var_id in TARGET_RELATIVE_VAR_IDS


static func is_target_relative_condition(condition_id: String) -> bool:
	return condition_id in TARGET_RELATIVE_CONDITION_IDS


static func allows_negative(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return bool(meta.get("allows_negative", false))


static func force_self(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return bool(meta.get("force_self", false))


static func uses_value(effect_id: String) -> bool:
	var meta: Dictionary = EFFECT_META.get(effect_id, {})
	return bool(meta.get("uses_value", true))


static func is_talent_only_effect(effect_id: String) -> bool:
	return bool(effect_meta(effect_id).get("talent_only", false))


static func is_continuous_effect(effect_id: String) -> bool:
	return bool(effect_meta(effect_id).get("continuous", false))


static func talent_effects_for_trigger(trigger_id: String) -> Array:
	return (TALENT_EFFECTS_BY_TRIGGER.get(trigger_id, []) as Array).duplicate()


static func is_effect_allowed_for_talent_trigger(effect_id: String, trigger_id: String) -> bool:
	return effect_id in TALENT_EFFECTS_BY_TRIGGER.get(trigger_id, [])


static func changes_enemy_hp_or_presence(effect_id: String, effect: Dictionary = {}) -> bool:
	if effect_id in [EFFECT_DAMAGE, EFFECT_HEAL, EFFECT_LIFESTEAL_DAMAGE, EFFECT_EXECUTE, EFFECT_CHARM, EFFECT_GAIN_MAX_HP, EFFECT_MATCH_MAX_HP]:
		return true
	if effect_id == EFFECT_ADD_BUFF:
		return str(effect.get("buff_id", "")) in [BUFF_POISON, BUFF_REGEN]
	return false


static func skill_changes_enemy_hp_or_presence(skill: Dictionary) -> bool:
	var effects = skill.get("effects", [])
	if not effects is Array or effects.is_empty() and skill.has("effect"):
		effects = [skill]
	return _effect_tree_changes_enemy(effects)


static func _effect_tree_changes_enemy(effects: Array) -> bool:
	for value in effects:
		if not value is Dictionary:
			continue
		var effect: Dictionary = value
		var effect_id := str(effect.get("effect", ""))
		if changes_enemy_hp_or_presence(effect_id, effect):
			var target := str(effect.get("target", ""))
			var side := str(effect.get("target_side", TARGET_SIDE_ALL))
			if target == "all_enemies" or (target not in [TARGET_SELF, TARGET_SELF_SIDES, "all_allies"] and side != TARGET_SIDE_ALLY):
				return true
		for branch in ["then_effects", "else_effects"]:
			var nested = effect.get(branch, [])
			if nested is Array and _effect_tree_changes_enemy(nested):
				return true
	return false


static func supports_random_count(effect_id: String) -> bool:
	return requires_live_target(effect_id) or effect_id in [EFFECT_VIEW_DISCARD, EFFECT_VIEW_DECK, EFFECT_ZERO_COST]


static func forced_target_side(effect_id: String) -> String:
	return TARGET_SIDE_ENEMY if effect_id == EFFECT_CLONE_ENEMY else ""


static func allowed_targets(effect_id: String) -> Array:
	if effect_id == EFFECT_CLONE_ENEMY:
		return [TARGET_SINGLE, TARGET_SIDES, TARGET_ALL, TARGET_MALE, TARGET_FEMALE, TARGET_NONHUMAN]
	return TARGET_IDS


static func buff_polarity(buff_id: String) -> String:
	var meta: Dictionary = BUFF_META.get(buff_id, {})
	return str(meta.get("polarity", "neutral"))


static func buff_uses_value(buff_id: String) -> bool:
	var meta: Dictionary = BUFF_META.get(buff_id, {})
	return bool(meta.get("value_meaningful", true))

static func effect_uses_value(effect: Dictionary) -> bool:
	var id := str(effect.get("effect", ""))
	return uses_value(id) and (id != EFFECT_ADD_BUFF or buff_uses_value(str(effect.get("buff_id", ""))))

static func buff_uses_duration(buff_id: String) -> bool:
	return buff_id != BUFF_STUN

static func percentage_value(effect: Dictionary) -> bool:
	return effect.get("effect") == EFFECT_ADD_BUFF and effect.get("buff_id") in [BUFF_DAMAGE_REDUCTION, BUFF_MISFORTUNE]

static func normalize_editor_value(effect: Dictionary) -> void:
	if is_control_effect(str(effect.get("effect", ""))): return
	if effect.get("effect") == EFFECT_ADD_BUFF and not buff_uses_duration(str(effect.get("buff_id", ""))): effect["duration"] = 1
	if not effect_uses_value(effect):
		effect.erase("value")
		for key in ["value_var", "value_expr", "value_offset", "value_min", "value_max"]: effect.erase(key)
	elif percentage_value(effect):
		for key in ["value", "value_min", "value_max"]:
			if effect.has(key): effect[key] = clampi(int(effect[key]), 0, 100)


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


# Editor shorthand compiled into the existing deterministic conditional form.
# The palette ID is never serialized as an effect ID.
const CHANCE_PALETTE_ID := "__chance_preset__"

static func make_chance_block(percent: int = 50) -> Dictionary:
	return {"effect": EFFECT_IF, "condition": {
		"op": CONDITION_OP_LTE,
		"lhs": {"kind": "expr", "op": "rand", "a": {"kind": "num", "value": 1}, "b": {"kind": "num", "value": 100}},
		"rhs": {"kind": "num", "value": clampi(percent, 0, 100)}}, "then_effects": []}

static func is_chance_block(effect: Dictionary) -> bool:
	if str(effect.get("effect", "")) != EFFECT_IF or not effect.get("else_effects", []).is_empty(): return false
	var condition = effect.get("condition", {})
	if not condition is Dictionary or str(condition.get("op", "")) != CONDITION_OP_LTE: return false
	var rhs = condition.get("rhs", {})
	if not rhs is Dictionary or str(rhs.get("kind", "")) != "num": return false
	var lhs = condition.get("lhs", {})
	if not lhs is Dictionary or str(lhs.get("kind", "")) != "expr" or str(lhs.get("op", "")) != "rand": return false
	var lower = lhs.get("a", {})
	var upper = lhs.get("b", {})
	if not lower is Dictionary or not upper is Dictionary: return false
	return str(lower.get("kind", "")) == "num" and str(upper.get("kind", "")) == "num" and float(lower.get("value", 0)) == 1.0 and float(upper.get("value", 0)) == 100.0
