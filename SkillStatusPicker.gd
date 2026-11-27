extends RefCounted

const GROUPS := {
	"protection": [SkillRegistry.BUFF_ATK_BOOST, SkillRegistry.BUFF_THORNS, SkillRegistry.BUFF_DAMAGE_REDUCTION,
		SkillRegistry.BUFF_DODGE, SkillRegistry.BUFF_UNTARGETABLE, SkillRegistry.BUFF_TAUNT, SkillRegistry.BUFF_IMMUNE_LETHAL],
	"recovery": [SkillRegistry.BUFF_REGEN, SkillRegistry.BUFF_MANA_REFUND],
	"control": [SkillRegistry.BUFF_SILENCE, SkillRegistry.BUFF_STUN, SkillRegistry.BUFF_MISFORTUNE, SkillRegistry.BUFF_LUCK, SkillRegistry.BUFF_POISON],
}

static func fill(picker: OptionButton, selected_buff: String) -> void:
	picker.clear()
	for group in GROUPS:
		picker.add_separator(Locale.t("skill_editor.status_group_" + group))
		for buff in GROUPS[group]:
			picker.add_item(Locale.term("buff", buff), SkillRegistry.BUFF_IDS.find(buff))
			picker.get_popup().set_item_tooltip(picker.item_count - 1, SkillHelp.description("buff", buff))
			if buff == selected_buff: picker.selected = picker.item_count - 1

static func value(picker: OptionButton) -> String:
	return SkillRegistry.BUFF_IDS[picker.get_selected_id()]

static func select_value(picker: OptionButton, buff: String) -> void:
	picker.select(picker.get_item_index(maxi(0, SkillRegistry.BUFF_IDS.find(buff))))
