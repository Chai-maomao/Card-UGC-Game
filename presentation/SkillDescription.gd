extends RefCounted

# One vocabulary for descriptions, labels, buttons and hover hints.
const KEYWORDS := {
	"圣水": ["67baff", "elixir"],
	"Elixir": ["67baff", "elixir"],
	"行动力": ["e1c16b", "ap"],
	"行动": ["e1c16b", "ap"],
	"AP": ["e1c16b", "ap"],
	"action points": ["e1c16b", "ap"],
	"生命": ["f08078", "hp"],
	"health": ["f08078", "hp"],
	"HP": ["f08078", "hp"],
	"攻击力": ["f08078", "attack"],
	"攻击": ["f08078", "attack"],
	"attack": ["f08078", "attack"],
	"伤害": ["f08078", "damage"],
	"damage": ["f08078", "damage"],
	"治疗": ["8dcba5", "heal"],
	"heal": ["8dcba5", "heal"],
	"healing": ["8dcba5", "heal"],
	"护盾": ["d5dde4", "shield"],
	"shield": ["d5dde4", "shield"],
	"中毒": ["b1d477", "poison"],
	"poison": ["b1d477", "poison"],
	"再生": ["8dcba5", "regen"],
	"regeneration": ["8dcba5", "regen"],
	"闪避": ["c0a0e2", "dodge"],
	"dodge": ["c0a0e2", "dodge"],
	"不可选中": ["c0a0e2", "untargetable"],
	"untargetable": ["c0a0e2", "untargetable"],
	"沉默": ["c0a0e2", "silence"],
	"silence": ["c0a0e2", "silence"],
	"眩晕": ["c0a0e2", "stun"],
	"stun": ["c0a0e2", "stun"],
	"嘲讽": ["c0a0e2", "taunt"],
	"taunt": ["c0a0e2", "taunt"],
	"魅惑": ["c0a0e2", "charm"],
	"charm": ["c0a0e2", "charm"],
	"反伤": ["f08078", "thorns"],
	"thorns": ["f08078", "thorns"],
	"吸血": ["f08078", "lifesteal"],
	"lifesteal": ["f08078", "lifesteal"],
	"吸血伤害": ["f08078", "lifesteal"],
	"lifesteal damage": ["f08078", "lifesteal"],
	"减伤": ["d5dde4", "reduction"],
	"damage reduction": ["d5dde4", "reduction"],
	"免疫致命伤害": ["d5dde4", "immune"],
	"免疫致命": ["d5dde4", "immune"],
	"lethal immunity": ["d5dde4", "immune"],
	"厄运": ["c0a0e2", "misfortune"],
	"霉运": ["c0a0e2", "misfortune"],
	"misfortune": ["c0a0e2", "misfortune"],
	"幸运": ["8dcba5", "luck"],
	"luck": ["8dcba5", "luck"],
	"圣水返还": ["67baff", "refund"],
	"elixir refund": ["67baff", "refund"],
	"攻击提升": ["f08078", "atk_boost"],
	"attack boost": ["f08078", "atk_boost"],
	"生命上限": ["8dcba5", "max_hp"],
	"max HP": ["8dcba5", "max_hp"],
	"本局生命成长": ["8dcba5", "max_hp"],
	"match max HP": ["8dcba5", "max_hp"],
	"抽牌": ["e1c16b", "draw"],
	"draw": ["e1c16b", "draw"],
	"draw cards": ["e1c16b", "draw"],
	"弃牌": ["e1c16b", "discard"],
	"discard": ["e1c16b", "discard"],
	"牌库": ["8fb9d6", "draw_pile"],
	"draw pile": ["8fb9d6", "draw_pile"],
	"弃牌堆": ["b2a4c9", "discard_pile"],
	"discard pile": ["b2a4c9", "discard_pile"],
	"手牌": ["e1c16b", "hand"],
	"hand card": ["e1c16b", "hand"],
	"hand cards": ["e1c16b", "hand"],
	"复制": ["e1c16b", "copy"],
	"复制手牌": ["e1c16b", "copy"],
	"copy hand": ["e1c16b", "copy"],
	"copy": ["e1c16b", "copy"],
	"克隆": ["c0a0e2", "clone"],
	"clone": ["c0a0e2", "clone"],
	"处决": ["f08078", "execute"],
	"execute": ["f08078", "execute"],
	"净化": ["8dcba5", "cleanse"],
	"cleanse": ["8dcba5", "cleanse"],
	"驱散": ["c0a0e2", "dispel"],
	"dispel": ["c0a0e2", "dispel"],
	"法力汲取": ["67baff", "drain"],
	"mana drain": ["67baff", "drain"],
	"交换攻击": ["f08078", "swap"],
	"swap attack": ["f08078", "swap"],
	"零费": ["67baff", "zero"],
	"zero cost": ["67baff", "zero"],
	"降低费用": ["67baff", "cost"],
	"reduce cost": ["67baff", "cost"],
	"费用变动": ["67baff", "cost"],
	"change cost": ["67baff", "cost"],
	"费用": ["67baff", "cost"],
	"cost": ["67baff", "cost"],
	"伤害上限": ["f08078", "cap"],
	"damage cap": ["f08078", "cap"],
	"单次伤害上限": ["f08078", "cap"],
	"single damage cap": ["f08078", "cap"],
	"检索": ["e1c16b", "search"],
	"search": ["e1c16b", "search"],
	"寄生": ["c0a0e2", "parasite"],
	"parasite": ["c0a0e2", "parasite"],
	"法术卡": ["8fb9d6", "spell"],
	"spell card": ["8fb9d6", "spell"],
	"单位卡": ["d5dde4", "unit"],
	"unit card": ["d5dde4", "unit"],
	"回合开始": ["e1c16b", "turn"],
	"回合结束": ["e1c16b", "turn"],
	"turn start": ["e1c16b", "turn"],
	"turn end": ["e1c16b", "turn"],
	"概率": ["c0a0e2", "chance"],
	"probability": ["c0a0e2", "chance"],
	"使用次数": ["e1c16b", "uses"],
	"uses remaining": ["e1c16b", "uses"],
	"max uses": ["e1c16b", "uses"],
}
const LIGHT_KEYWORD_COLORS := {
	"67baff": "205f95",
	"e1c16b": "72501a",
	"f08078": "a03731",
	"8dcba5": "2d6349",
	"d5dde4": "4d5f69",
	"b1d477": "4d6728",
	"c0a0e2": "684186",
	"8fb9d6": "315c73",
	"b2a4c9": "625071",
}
static var _pattern: RegEx

static func _regex() -> RegEx:
	if _pattern == null:
		_pattern = RegEx.new()
		var tokens := KEYWORDS.keys()
		tokens.sort_custom(func(a,b): return a.length()>b.length())
		var expressions: Array[String] = []
		for token: String in tokens:
			expressions.append("\\b"+token+"\\b" if token.unicode_at(0)<128 else token)
		_pattern.compile("(?i)(?:"+"|".join(expressions)+")")
	return _pattern

static func has_keywords(text: String) -> bool:
	for hit in _regex().search_all(text):
		if not _skip_match(text,hit): return true
	return false

static func make_abilities_frame() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "CardAbilitiesFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UITheme.panel_style(UITheme.COLOR_PANEL, UITheme.Tokens.BORDER, 1, 6)
	style.set_content_margin_all(12)
	frame.add_theme_stylebox_override("panel", style)
	return frame


static func make_skill_separator(index: int) -> HSeparator:
	var separator := HSeparator.new()
	separator.name = "SkillSeparator%d" % index
	separator.custom_minimum_size = Vector2(140, 12)
	separator.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_separator(separator)
	return separator


static func build_basic_attack(attack: int, party: bool = false) -> RichTextLabel:
	var text := Locale.t("tabletop.party_attack_description") if party \
		else ("[普通攻击]\n对敌方造成%d点伤害" if Locale.language == "zh" else "[Basic attack]\nDeal %d damage to an enemy")
	var description := build(text % attack)
	description.name = "BasicAttackDescription"
	return description


static func build_read_only_abilities(card: CardData) -> VBoxContainer:
	var abilities := VBoxContainer.new()
	abilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abilities.add_theme_constant_override("separation", 8)
	if not card.is_spell() and not card.is_parasite():
		abilities.add_child(build_basic_attack(card.effective_atk()))
	for index in range(card.skills.size()):
		var skill: Dictionary = card.skills[index]
		if skill.is_empty():
			continue
		if abilities.get_child_count() > 0:
			abilities.add_child(make_skill_separator(index))
		var remaining := SkillTextFormatter.remaining_skill_uses(card, skill, index)
		abilities.add_child(build(SkillTextFormatter.format_skill_tooltip(skill, index, remaining)))
	return abilities


static func build(text: String) -> RichTextLabel:
	var label := preload("res://presentation/KeywordInlineLabel.gd").new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_override("normal_font", UITheme.regular_font())
	var pixels := 16+int(AppPreferences.get_value("text_size"))*2
	label.add_theme_font_size_override("normal_font_size",pixels)
	label.add_theme_color_override("default_color",UITheme.COLOR_TEXT)
	label.text = colored(text,pixels)
	return label

static func build_battle_skill(card: CardData, index: int, refreshers: Array[Callable], attachment_index: int = -1) -> RichTextLabel:
	var skill: Dictionary = card.skills[index]
	var remaining := SkillTextFormatter.remaining_skill_uses(card, skill, index)
	var label := build(SkillTextFormatter.format_skill_tooltip(skill, index, remaining))
	if remaining >= 0:
		label.set_meta("remaining_uses", remaining)
		refreshers.append(_refresh_battle_skill.bind(label, index, attachment_index, card))
	return label

static func _refresh_battle_skill(current: CardData, label: RichTextLabel, index: int, attachment_index: int, original: CardData) -> void:
	var owner := current
	if attachment_index >= 0:
		owner = current.parasite_cards[attachment_index] if attachment_index < current.parasite_cards.size() else null
	if owner == null or index >= owner.skills.size():
		return
	if owner != original and (original.instance_id.is_empty() or owner.instance_id != original.instance_id):
		return
	var skill: Dictionary = owner.skills[index]
	var remaining := SkillTextFormatter.remaining_skill_uses(owner, skill, index)
	if remaining != label.get_meta("remaining_uses"):
		label.set_meta("remaining_uses", remaining)
		label.text = colored(SkillTextFormatter.format_skill_tooltip(skill, index, remaining), label.get_theme_font_size("normal_font_size"))

static func colored(text: String, pixels: int = 16, preserve_heading: bool = true, dark_surface: bool = false) -> String:
	# A generated [skill name] heading is authored content, not a keyword.
	var newline := text.find("\n")
	var begin := newline+1 if preserve_heading and text.begins_with("[") and newline>=0 else 0
	var result := _escape(text.left(begin))
	var cursor := begin
	for hit in _regex().search_all(text,begin):
		if _skip_match(text,hit): continue
		result += _escape(text.substr(cursor,hit.get_start()-cursor))
		var word: String = hit.get_string()
		var style: Array = []
		for token: String in KEYWORDS:
			if token.to_lower()==word.to_lower():
				style = KEYWORDS[token]
				break
		var icon: String = style[1]
		var hint := SkillHelp.KEYWORD_PREFIX + icon
		var color: String = style[0]
		var tint := ""
		if UITheme.Tokens.light_mode and not dark_surface and LIGHT_KEYWORD_COLORS.has(color):
			var original := Color(color)
			color = LIGHT_KEYWORD_COLORS[color]
			var dark := Color(color)
			tint = " color=#" + Color(dark.r / original.r, dark.g / original.g, dark.b / original.b).to_html(false)
		result += "[img width=%d height=%d tooltip=%s%s]res://res/ui/keywords/%s.svg[/img]\u202f[hint=\"%s\"][color=#%s]%s[/color][/hint]" % [
			pixels, pixels, hint, tint, icon, hint, color, _escape(word)]
		cursor = hit.get_end()
	return result+_escape(text.substr(cursor))

static func plain(text: String) -> String:
	# Godot 4.6 parsed text represents an image as a space; trim only
	# the image placeholder plus the thin separator inserted above.
	return text.replace(" \u202f", "").replace("\ufffc\u202f", "").replace("\ufffc", "")

static func _escape(text: String) -> String:
	return text.replace("[","[lb]")

static func _skip_match(text: String, hit: RegExMatch) -> bool:
	var prefix := text.left(hit.get_start())
	if prefix.rfind("【") > prefix.rfind("】"): return true
	if prefix.rfind("[") > prefix.rfind("]"): return true
	var word := hit.get_string().to_lower()
	var suffix := text.substr(hit.get_end())
	if word in ["弃牌","抽牌"] and suffix.begins_with("堆"): return true
	if word in ["discard","draw"] and suffix.to_lower().begins_with(" pile"): return true
	# Basic attack is an action name, not a resource/damage keyword.
	if word=="攻击" and (prefix.ends_with("普通") or prefix.ends_with("普")): return true
	if word=="attack" and (prefix.to_lower().ends_with("basic ") or prefix.to_lower().ends_with("normal ")): return true
	if word=="行动":
		# The short resource form in quotes/HUDs is numeric; prose such as
		# "本次行动" and "无法行动" keeps its ordinary meaning and appearance.
		var quantity := RegEx.new()
		quantity.compile("[0-9]+\\s*$")
		var ratio := RegEx.new()
		ratio.compile("^\\s*[0-9]+\\s*/\\s*[0-9]+")
		return quantity.search(prefix)==null and ratio.search(text.substr(hit.get_end()))==null
	return false
