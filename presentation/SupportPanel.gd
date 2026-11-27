extends CanvasLayer

const DOCUMENTS := {"privacy":"res://legal/PRIVACY.md","terms":"res://legal/TERMS.md","ugc":"res://legal/UGC.md","licenses":"res://legal/THIRD_PARTY_NOTICES.md"}

# Keep the detailed notices available without making them the default help text.
const SUMMARIES := {
	"zh": {
		"privacy": "存档、卡牌和设置都存在你的设备里。游戏不会自动上传日志，也没有广告或数据统计。\n\n联机时，对手会收到你的卡牌信息和卡图，也能看到连接 IP。目前对手的修改版客户端可能读取你的手牌和牌堆，请和信任的人玩。\n\n创意工坊需要注册后才能上传。用户名、卡包和举报会保存在工坊服务器；密码以加盐哈希保存。上传的卡包审核通过后会公开，其他玩家可以保存副本。\n\n反馈问题会打开公开的 GitHub 页面。发日志或截图前，记得去掉密码、联系方式等私人信息。",
		"terms": "游戏还在测试中，可能遇到错误或联机中断。重要的卡牌和存档请留一份备份。\n\n你创作的内容仍归你所有。分享别人的图片或作品前，请先确认可以使用；别人收到分享文件后，可以保存副本。\n\n请勿传播违法、侵权、骚扰、仇恨、性剥削内容或他人的隐私，也不要攻击玩家设备或滥用服务器。",
		"ugc": "可以自由设计卡牌和技能。用别人的图片时，请遵守作者的授权要求，不要冒充作者。\n\n自制卡牌不一定平衡。导入陌生人分享的内容前，先确认来源。\n\n如果收到不合适的内容，可以删除卡牌、退出房间，再通过“反馈问题”联系我们。公开反馈时不要转发他人的隐私。",
		"licenses": "CARDEX 使用 Godot 引擎和 Noto Sans SC 字体。音乐、音效和部分图片由项目作者提供，其余素材来源见完整清单。\n\n这些素材不一定允许单独转载或商用。需要使用时，请查看对应授权。",
	},
	"en": {
		"privacy": "Your saves, cards and settings stay on your device. The game has no ads or analytics and does not upload logs automatically.\n\nOnline opponents receive your card data and images and can see your connection IP. Modified clients may read your hand and deck, so play with people you trust.\n\nWorkshop uploads require an account. The server stores your username, salted password hash, packages and reports. Approved packages become public, and other players can keep copies.\n\nBug reports open a public GitHub page. Remove passwords and personal details before sharing logs or screenshots.",
		"terms": "The game is still in testing. Bugs and connection failures can happen, so keep a backup of important cards and saves.\n\nYour creations remain yours. Check permission before sharing someone else's art or work. Recipients can keep a copy of shared files.\n\nDo not share illegal, infringing, harassing, hateful, exploitative or private content. Do not attack players' devices or abuse servers.",
		"ugc": "You can create your own cards and skills. Follow the artist's permission requirements when using their images, and do not impersonate creators.\n\nCustom cards may be unbalanced. Check the source before importing files from someone you do not know.\n\nIf you receive inappropriate content, delete it, leave the room and use Report a Problem to contact us. Keep other people's private information out of public reports.",
		"licenses": "CARDEX uses Godot Engine and the Noto Sans SC font. Music, sound effects and some images were supplied by the project author. See the full notices for other asset sources.\n\nPermission to redistribute or commercially reuse these assets varies. Check each asset's license before using it.",
	},
}
var _document := "privacy"
var _show_full := false
var _body: RichTextLabel
var _full_button: Button

func _show_document(key: String) -> void:
	_document = key
	_show_full = false
	_refresh_document()

func _refresh_document() -> void:
	var language := "zh" if Locale.language == "zh" else "en"
	_body.text = FileAccess.get_file_as_string(DOCUMENTS[_document]) if _show_full else SUMMARIES[language][_document]
	_body.scroll_to_line(0)
	_full_button.text = ("收起全文" if _show_full else "查看全文") if language == "zh" else ("Show Summary" if _show_full else "Read Full Notice")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	set_meta("popup_close",queue_free)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.apply_overlay(shade)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_top = 24
	panel.offset_right = -24
	panel.offset_bottom = -24
	UITheme.apply_popup_frame(panel, "dark", false, true)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	panel.add_child(box)
	var title := Label.new()
	title.text = Locale.t("support.title")
	UITheme.apply_title(title,24)
	box.add_child(title)
	var tabs := HFlowContainer.new()
	box.add_child(tabs)
	var text := RichTextLabel.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", UITheme.regular_font())
	text.add_theme_color_override("default_color",UITheme.COLOR_TEXT)
	text.add_theme_font_size_override("normal_font_size", 16 + int(AppPreferences.get_value("text_size")) * 2)
	text.add_theme_constant_override("line_separation",6)
	box.add_child(text)
	var documents_group := ButtonGroup.new()
	for key in DOCUMENTS:
		var button := _button(Locale.t("support."+key),tabs)
		button.toggle_mode = true
		button.button_group = documents_group
		UITheme.apply_button(button, "outlined")
		button.set_pressed_no_signal(key == _document)
		button.pressed.connect(func(): _show_document(key))
	_body = text
	_full_button = _button("",tabs)
	_full_button.pressed.connect(func():
		_show_full = not _show_full
		_refresh_document())
	_refresh_document()
	var actions := HFlowContainer.new()
	box.add_child(actions)
	_button(Locale.t("support.copy"),actions).pressed.connect(func():
		AppDiagnostics.copy_summary()
		text.text = Locale.t("support.copied")+"\n\n"+AppDiagnostics.summary())
	if OS.has_feature("android"):
		_button(Locale.t("support.export_log"),actions).pressed.connect(_select_export_file.bind(AppDiagnostics.DIRECTORY))
		_button(Locale.t("support.export_save"),actions).pressed.connect(_select_export_file.bind("user://"))
	else:
		_button(Locale.t("support.logs"),actions).pressed.connect(AppDiagnostics.open_logs)
		_button(Locale.t("support.saves"),actions).pressed.connect(AppDiagnostics.open_saves)
	_button(Locale.t("support.issue"),actions).pressed.connect(func(): OS.shell_open("https://github.com/Chai-maomao/Card-UGC-Game/issues"))
	_button(Locale.t("common.close"),actions).pressed.connect(queue_free)
	UIMotion.register_popup(self)

func _select_export_file(directory: String) -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_USERDATA
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.current_dir = directory
	picker.file_selected.connect(func(path: String):
		picker.queue_free()
		_select_export_destination.call_deferred(path))
	picker.canceled.connect(picker.queue_free)
	add_child(picker)
	UITheme.apply_dialog(picker, true)
	# The Android document picker cannot browse the app's private data.
	picker.use_native_dialog = false
	picker.popup_centered_ratio(0.85)

func _select_export_destination(source: String) -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.current_file = source.get_file()
	picker.file_selected.connect(func(destination: String):
		_body.text = Locale.t("share.export_done" if _copy_file(source, destination) else "share.export_failed")
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	add_child(picker)
	UITheme.apply_dialog(picker, true)
	picker.popup_centered_ratio(0.85)

func _copy_file(source: String, destination: String) -> bool:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null: return false
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null: return false
	var remaining := input.get_length()
	while remaining > 0:
		var chunk := input.get_buffer(mini(remaining, 65536))
		if chunk.is_empty() or not output.store_buffer(chunk): return false
		remaining -= chunk.size()
	output.flush()
	return output.get_error() == OK

func _button(text: String, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	UITheme.apply_button(button,"secondary")
	parent.add_child(button)
	return button
