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
	"减伤": ["d5dde4", "reduction"],
	"damage reduction": ["d5dde4", "reduction"],
	"免疫致命伤害": ["d5dde4", "immune"],
	"lethal immunity": ["d5dde4", "immune"],
	"厄运": ["c0a0e2", "misfortune"],
	"misfortune": ["c0a0e2", "misfortune"],
	"圣水返还": ["67baff", "refund"],
	"elixir refund": ["67baff", "refund"],
	"攻击提升": ["f08078", "atk_boost"],
	"attack boost": ["f08078", "atk_boost"],
	"生命上限": ["8dcba5", "max_hp"],
	"max HP": ["8dcba5", "max_hp"],
	"抽牌": ["e1c16b", "draw"],
	"draw": ["e1c16b", "draw"],
	"弃牌": ["e1c16b", "discard"],
	"discard": ["e1c16b", "discard"],
	"牌库": ["8fb9d6", "draw_pile"],
	"draw pile": ["8fb9d6", "draw_pile"],
	"弃牌堆": ["b2a4c9", "discard_pile"],
	"discard pile": ["b2a4c9", "discard_pile"],
	"复制": ["e1c16b", "copy"],
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
	"费用": ["67baff", "cost"],
	"cost": ["67baff", "cost"],
	"伤害上限": ["f08078", "cap"],
	"damage cap": ["f08078", "cap"],
	"检索": ["e1c16b", "search"],
	"search": ["e1c16b", "search"],
	"寄生": ["c0a0e2", "parasite"],
	"parasite": ["c0a0e2", "parasite"],
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

static func build(text: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", UITheme.regular_font())
	var pixels := 16+int(AppPreferences.get_value("text_size"))*2
	label.add_theme_font_size_override("normal_font_size",pixels)
	label.add_theme_color_override("default_color",UITheme.COLOR_TEXT)
	label.text = colored(text,pixels)
	return label

static func colored(text: String, pixels: int = 16, preserve_heading: bool = true) -> String:
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
		result += "[img width=%d height=%d]res://res/ui/keywords/%s.svg[/img]\u2009[color=#%s]%s[/color]" % [pixels,pixels,style[1],style[0],_escape(word)]
		cursor = hit.get_end()
	return result+_escape(text.substr(cursor))

static func plain(text: String) -> String:
	# Godot 4.6 parsed text represents an image as a space; trim only
	# the image placeholder plus the thin separator inserted above.
	return text.replace(" \u2009", "").replace("\ufffc\u2009", "").replace("\ufffc", "")

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
