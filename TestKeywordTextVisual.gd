extends Node
const Words=preload("res://presentation/SkillDescription.gd")
var presses := 0
func _enter_tree() -> void:
 get_window().set_flag(Window.FLAG_NO_FOCUS,true)
 get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _ready() -> void:
 get_window().size=Vector2i(1280,720)
 Locale.language="zh"
 var root=PanelContainer.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(root)
 UITheme.apply_app_background(root)
 var box=VBoxContainer.new()
 root.add_child(box)
 var grid=GridContainer.new()
 grid.columns=6
 grid.add_theme_constant_override("h_separation",20)
 grid.add_theme_constant_override("v_separation",12)
 box.add_child(grid)
 var manifest: Array=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/keyword-icons-20261115/manifest.json"))
 for item in manifest:
  var label=Label.new()
  label.text=item.name
  label.custom_minimum_size=Vector2(180,52)
  label.add_theme_font_size_override("font_size",20)
  grid.add_child(label)
 var sentence=Label.new()
 sentence.text="消耗 2 圣水，对敌方造成 3 点伤害。获得 4 点护盾，施加 2 回合中毒。"
 sentence.add_theme_font_size_override("font_size",22)
 box.add_child(sentence)
 var healing=Words.build(SkillTextFormatter.format_skill_tooltip({"skill_name":"治疗回响","trigger":"on_activate","effects":[{"effect":"heal","target":"self","value":3}]}))
 box.add_child(healing)
 assert(not Words.has_keywords("恢复旧版本") and not Words.has_keywords("回复"),"ordinary restore/recover verbs must not be treated as a healing effect name")
 assert(Words.plain(healing.get_parsed_text()).contains("回复") and not healing.text.contains("/heal.svg"),"generated healing uses a plain 回复 verb, without an extra healing icon")
 var button=Button.new()
 button.text="圣水补付"
 button.set_meta("keyword_enabled",true)
 UITheme.apply_button(button)
 button.pressed.connect(func():presses+=1)
 box.add_child(button)
 var literal=Label.new()
 literal.text="自定义名字：圣水伤害护盾"
 literal.set_meta("keyword_literal",true)
 box.add_child(literal)
 await get_tree().create_timer(0.6).timeout
 for label in grid.get_children():
  var rich=label.get_node_or_null("KeywordText")
  assert(rich!=null and rich.is_visible_in_tree(),"every approved keyword must render")
  assert(Words.plain(rich.get_parsed_text())==label.text,"icon decoration must preserve the displayed word")
  assert(rich.size.x>=rich.get_content_width(),"keyword icon and word must fit")
 assert(literal.get_node_or_null("KeywordText")==null and literal.self_modulate.a==1.0)
 var target=button.get_global_rect().get_center()
 var motion=InputEventMouseMotion.new()
 motion.position=target
 get_viewport().push_input(motion,true)
 for down in [true,false]:
  var event=InputEventMouseButton.new()
  event.position=target
  event.button_index=MOUSE_BUTTON_LEFT
  event.pressed=down
  get_viewport().push_input(event,true)
  await get_tree().process_frame
 assert(presses==1,"keyword overlay must let the actual button receive clicks")
 button.disabled=true
 await get_tree().process_frame
 await get_tree().process_frame
 assert(button.get_node("KeywordText").modulate.a<1.0,"disabled state must dim decorated text")
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://artifacts/keyword-icons-20261115/in-game-keywords.png")
 var first=grid.get_child(0)
 first.text="普通文字"
 await get_tree().process_frame
 await get_tree().process_frame
 assert(first.get_node_or_null("KeywordText")==null and first.self_modulate.a==1.0,"changing back to plain text must restore the label")
 sentence.add_theme_font_size_override("font_size",28)
 sentence.text="Elixir 2 / Damage 3 / Shield 4"
 await get_tree().process_frame
 await get_tree().process_frame
 var decorated=sentence.get_node("KeywordText")
 assert(Words.plain(decorated.get_parsed_text())==sentence.text,"English text and a live font-size change must refresh")
 assert(decorated.get_theme_font_size("normal_font_size")==28)
 for wording in ["弃牌堆选牌", "discard pile"]:
  var rich=Words.build(wording)
  box.add_child(rich)
  await get_tree().process_frame
  assert(rich.text.contains("/discard_pile.svg") and not rich.text.contains("/discard.svg"),"compound noun must use its own icon")
  assert(Words.plain(rich.get_parsed_text())==wording)
  rich.queue_free()
 # Literal action names, headings and non-resource uses of 行动 stay plain.
 for wording in ["普通攻击","本次行动","无法行动","Basic attack","普攻击杀","抽牌堆","恢复","回复"]:
  var unchanged=Label.new()
  unchanged.text=wording
  box.add_child(unchanged)
  await get_tree().process_frame
  await get_tree().process_frame
  assert(unchanged.get_node_or_null("KeywordText")==null and unchanged.self_modulate.a==1.0,"action names/prose must remain untouched: "+wording)
  unchanged.queue_free()
 var title=Label.new()
 title.text="圣水、伤害与护盾"
 UITheme.apply_title(title)
 box.add_child(title)
 await get_tree().process_frame
 await get_tree().process_frame
 assert(title.get_node_or_null("KeywordText")==null,"titles must retain their original colour and text")
 var quantity=Label.new()
 quantity.text="本次行动：3 行动 / 0 圣水"
 box.add_child(quantity)
 await get_tree().process_frame
 await get_tree().process_frame
 var quote: String=quantity.get_node("KeywordText").text
 assert(quote.begins_with("本次行动：") and quote.count("/ap.svg")==1,"only the numeric resource use of 行动 is decorated")
 var clone: Button=button.duplicate()
 box.add_child(clone)
 await get_tree().process_frame
 await get_tree().process_frame
 assert(clone.get_node_or_null("KeywordText")!=null and Words.plain(clone.get_node("KeywordText").get_parsed_text())==clone.text,"duplicated drag previews must retain visible keyword text")
 var entry=LineEdit.new()
 entry.text="圣水伤害护盾"
 box.add_child(entry)
 var selection=OptionButton.new()
 selection.add_item("攻击提升")
 box.add_child(selection)
 var slot=ValueSlot.new()
 box.add_child(slot)
 var field=Button.new()
 field.text="护盾"
 slot.add_child(field)
 await get_tree().process_frame
 await get_tree().process_frame
 assert(entry.text=="圣水伤害护盾" and entry.get_node_or_null("KeywordText")==null,"typed field values stay literal")
 assert(selection.get_node_or_null("KeywordText")==null and field.get_node_or_null("KeywordText")==null,"selected field values and variable slots stay literal")
 assert(not Words.colored("[圣水护盾] 攻击时：造成 2 点伤害",16,false).contains("/elixir.svg"),"user-authored names in inline summaries stay literal")
 for wording in ["复制到卡组","复制设备信息","恢复默认设置","恢复默认键位","创建一张新的寄生卡"]:
  var tool=Button.new()
  tool.text=wording
  box.add_child(tool)
  await get_tree().process_frame
  await get_tree().process_frame
  assert(tool.get_node_or_null("KeywordText")==null,"menu/tool buttons must remain plain: "+wording)
 var history=load("res://MatchHistory.tscn").instantiate()
 add_child(history)
 history.hide()
 var user_chip=history._make_card_chip("受伤魅惑 / 圣水伤害护盾",Color.WHITE)
 box.add_child(user_chip)
 await get_tree().process_frame
 await get_tree().process_frame
 for label in user_chip.find_children("*","Label",true,false):
  assert(label.get_node_or_null("KeywordText")==null,"history keeps user-authored names literal")
 history.queue_free()
 root.hide()
 var settings=load("res://SettingsMenu.tscn").instantiate()
 add_child(settings)
 await get_tree().create_timer(0.3).timeout
 for control in [settings._reset_button,settings._reset_keys_button]:
  assert(control.get_node_or_null("KeywordText")==null,"reset settings/bindings are ordinary UI words")
 settings._show_category("controls")
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/keyword-settings-plain.png")
 var support=load("res://presentation/SupportPanel.gd").new()
 settings.add_child(support)
 await get_tree().create_timer(0.2).timeout
 for control in support.find_children("*","Button",true,false):
  assert(control.get_node_or_null("KeywordText")==null,"support tools do not use combat icons")
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/keyword-support-plain.png")
 settings.queue_free()
 await get_tree().process_frame
 PlayerData.battle_select_mode="hotseat_p1"
 var decks=load("res://BattleDeckSelect.tscn").instantiate()
 add_child(decks)
 await get_tree().create_timer(0.3).timeout
 for spin in decks.basic_controls.values():
  var caption=spin.get_parent().get_child(0)
  assert(caption.get_node_or_null("KeywordText")==null,"basic battle settings remain plain")
 assert(not decks.deck_tiles.is_empty())
 assert(preload("res://UIHoverHints.gd").hint_for(decks.deck_tiles[0]).is_empty(),"deck hover must not repeat its name")
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/keyword-deck-basic-plain.png")
 decks._show_battle_config_popup()
 await get_tree().create_timer(0.25).timeout
 var decorated_fields := 0
 for label in decks.advanced_layer.find_children("*","Label",true,false):
  if label.get_node_or_null("KeywordText")!=null: decorated_fields+=1
 assert(decorated_fields>0,"advanced battle settings keep their keyword styling")
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/keyword-deck-advanced.png")
 print("TEST_KEYWORD_TEXT_VISUAL_OK")
 get_tree().quit()
