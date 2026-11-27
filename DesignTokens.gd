extends RefCounted
# The one design vocabulary for application UI, printed cards, and table accents.
static var light_mode := false
static var BG: Color
static var PANEL: Color
static var PANEL_SOFT: Color
static var PANEL_DARK: Color
static var BORDER: Color
static var FIELD_BORDER: Color
static var TEXT: Color
static var MUTED: Color
static var BUTTON: Color
static var BUTTON_HOVER: Color
static var BUTTON_PRESSED: Color
static var PRIMARY: Color
static var PRIMARY_HOVER: Color
static var PRIMARY_PRESSED: Color
static var BRASS: Color
static var TOOLTIP_FILL: Color
static var TOOLTIP_BORDER: Color
static var HEADING_GOLD: Color
static var TEAL: Color
static var ENEMY: Color
static var SUCCESS: Color
static var WARNING: Color
static var DANGER: Color
static var DANGER_HOVER: Color
static var DANGER_PRESSED: Color
static var DISABLED: Color
static var DISABLED_TEXT: Color
static var DIVIDER: Color
static var TITLE: Color
static var CONTRAST_INK: Color
const PARASITE = Color("8b9c76")
const CARD_UNIT = Color("3a7471")
const CARD_SPELL = Color("62528c")
const CARD_PARASITE = Color("98603e")
const CARD_DISCOUNT = Color("285c4b")
const CARD_DANGER = Color("8f3b2e")
const PAPER = Color("e7daba")
const INK = Color("242d2c")
const SHADOW = Color(0,0,0,0.35)
const RADII = [4,8,16]
const SPACING = [4,8,12,16,24]
const FONT_SIZES = [12,13,16,18,22,28,32,42]
const BUTTON_TIME = 0.14
const PANEL_TIME = 0.22


static func _static_init() -> void:
	set_appearance(false)


static func set_appearance(light: bool) -> void:
	light_mode = light
	BG = Color("f4eee2" if light else "1b1915")
	PANEL = Color("ece2d0" if light else "27231d")
	PANEL_SOFT = Color("e5d8c2" if light else "302b22")
	PANEL_DARK = Color("fbf6eb" if light else "211e18")
	BORDER = Color("9a8059" if light else "74664e")
	FIELD_BORDER = Color("9b8160" if light else "8c7d61")
	TEXT = Color("33291e" if light else "efe5ce")
	MUTED = Color("685844" if light else "bcb4a3")
	BUTTON = Color("e8ddc8" if light else "302b23")
	BUTTON_HOVER = Color("f1e6cc" if light else "403729")
	BUTTON_PRESSED = Color("d8c7a8" if light else "372e22")
	PRIMARY = Color("d9be89" if light else "5b4930")
	PRIMARY_HOVER = Color("e6cda0" if light else "74603e")
	PRIMARY_PRESSED = Color("c8a771" if light else "514029")
	BRASS = Color("795720" if light else "b9a16e")
	TOOLTIP_FILL = Color("fff4de" if light else "382d1c")
	TOOLTIP_BORDER = Color("957044" if light else "907242")
	HEADING_GOLD = Color("76501e" if light else "dec28b")
	TEAL = Color("356762" if light else "72a09a")
	ENEMY = Color("984e43" if light else "b27769")
	SUCCESS = Color("36664b" if light else "87b296")
	WARNING = Color("89521e" if light else "e2ad6c")
	DANGER = Color("ecd0c7" if light else "4d1c1c")
	DANGER_HOVER = Color("f7ded6" if light else "6b2626")
	DANGER_PRESSED = Color("e3b6aa" if light else "331212")
	DISABLED = Color("e9e2d7" if light else "2b2822")
	DISABLED_TEXT = Color("766b5e" if light else "bbb5a7")
	DIVIDER = Color(BORDER, 0.48)
	TITLE = Color("493621") if light else PAPER
	CONTRAST_INK = Color("18130d") if light else Color.WHITE
