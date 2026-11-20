extends Node
const Artwork = preload("res://CardArtwork.gd")
var editor
func _ready():
	await get_tree().create_timer(0.2).timeout
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(1280,720)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	Locale.language="zh"
	PlayerData.skill_tutorial_active=false
	PlayerData.init_card_draft()
	var card=CardData.new("钟表守卫",2,4,3)
	assert(Artwork.selected_path(card)==Artwork.NORMAL)
	card.take_damage(1)
	assert(Artwork.selected_path(card)==Artwork.DAMAGED)
	card.heal(1)
	assert(Artwork.selected_path(card)==Artwork.NORMAL)
	var face=load("res://CardUI.tscn").instantiate()
	add_child(face)
	face.set_card(card)
	face.apply_ui_scale(2)
	card.take_damage(1)
	face.set_card(card)
	assert(face._printed_face.art==load(Artwork.DAMAGED))
	card.heal(1)
	face.set_card(card)
	assert(face._printed_face.art==load(Artwork.NORMAL))
	face.queue_free()
	editor=load("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await settle()
	editor.name_input.text="钟表守卫"
	editor.hp_input.value=4
	await capture("damaged-art-editor-default")
	await click(editor._preview_damaged.get_global_rect().get_center())
	assert(editor.preview_card.current_card_data.hp<editor.preview_card.current_card_data.max_hp)
	assert(editor.preview_card._printed_face.art==load(Artwork.DAMAGED))
	await capture("damaged-art-editor-wounded")
	for field in ["art_path","damaged_art_path"]:
		var image=Image.create(320,303,false,Image.FORMAT_RGB8)
		image.fill(Color("4b8c77") if field=="art_path" else Color("8b5448"))
		var path="user://fixture-"+field+".png"
		assert(image.save_png(path)==OK)
		var button=editor.browse_button if field=="art_path" else editor._damaged_art_browse
		var scroll=editor.get_node("Panel/MarginContainer/ScrollContainer")
		scroll.ensure_control_visible(button)
		await settle()
		await click(button.get_global_rect().get_center())
		assert(editor._art_edit_field==field)
		editor.art_dialog.hide()
		editor.art_dialog.file_selected.emit(path)
		await settle()
		var dialog=editor.get_child(editor.get_child_count()-1)
		assert(dialog.get_script()==load("res://presentation/CardArtCropDialog.gd"))
		var confirm
		for candidate in dialog.find_children("*","Button",true,false):
			if candidate.text==Locale.t("battle.confirm"):confirm=candidate
		assert(confirm!=null)
		await click(confirm.get_global_rect().get_center())
		await settle()
		assert(not str(PlayerData.card_draft.get(field,"")).is_empty())
	var built=PlayerData.build_card_from_draft()
	assert(built.art_path!=built.damaged_art_path)
	built.take_damage(1)
	assert(Artwork.selected_path(built)==built.damaged_art_path)
	built.heal(1)
	assert(Artwork.selected_path(built)==built.art_path)
	var alternate: String = built.damaged_art_path
	built.damaged_art_path="user://missing-wounded-art.png"
	built.take_damage(1)
	var fallback: Image = Artwork.texture_for(built).get_image()
	assert(fallback.get_pixel(100,100).is_equal_approx(Image.load_from_file(built.art_path).get_pixel(100,100)))
	built.damaged_art_path=alternate
	built.heal(1)
	var loaded=PlayerData.deserialize_card(JSON.parse_string(JSON.stringify(PlayerData.serialize_card(built))))
	assert(loaded.damaged_art_path==built.damaged_art_path)
	assert(built.duplicate_card().damaged_art_path==built.damaged_art_path)
	assert(PlayerData.card_to_draft(built).damaged_art_path==built.damaged_art_path)
	var package=SharePackage.build([PlayerData._serialize_card_for_share(built)])
	var parsed=PlayerData.parse_share_package(JSON.stringify(package))
	assert(parsed.ok)
	var result=PlayerData.import_package_as_new_deck(parsed.package,"差分测试")
	assert(result.added==1)
	var imported=PlayerData.deck_library.back().cards[0]
	assert(FileAccess.get_sha256(imported.art_path)==FileAccess.get_sha256(built.art_path))
	assert(FileAccess.get_sha256(imported.damaged_art_path)==FileAccess.get_sha256(built.damaged_art_path))
	var transfers=PlayerData.card_art_transfers([built])
	assert(transfers.size()==2)
	var remote=PlayerData.deserialize_card(PlayerData.serialize_card(built))
	remote.art_path=""
	remote.damaged_art_path=""
	for transfer in transfers:
		var received=PlayerData.save_net_art(transfer.bytes,transfer.ext)
		PlayerData.apply_received_art([remote],transfer.card_index,received)
	assert(FileAccess.get_sha256(remote.damaged_art_path)==FileAccess.get_sha256(built.damaged_art_path))
	# Stat changes in authority snapshots must not break local image remapping.
	remote.art_path="unavailable-on-this-client.png"
	remote.damaged_art_path="unavailable-wounded-on-this-client.png"
	remote.atk+=2
	remote.max_hp+=2
	remote.cost=0
	BattleArtResolver._restore_art_path(remote,{BattleArtResolver._card_identity_key(built):[built.art_path,built.damaged_art_path]})
	assert(remote.art_path==built.art_path and remote.damaged_art_path==built.damaged_art_path)
	await click(editor._damaged_art_clear.get_global_rect().get_center())
	assert(PlayerData.card_draft.damaged_art_path.is_empty())
	var single=PlayerData.build_card_from_draft()
	single.take_damage(1)
	assert(Artwork.selected_path(single)==single.art_path,"single custom artwork must not use the default damaged illustration")
	await capture("damaged-art-editor-custom")
	editor.queue_free()
	await settle()
	print("TEST_DAMAGED_CARD_ART_VISUAL_OK")
	get_tree().quit(0)
func settle():
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
func click(point):
	var motion=InputEventMouseMotion.new()
	motion.position=point
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		get_viewport().push_input(event,true)
		await get_tree().process_frame
func capture(name):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/%s.png"%name)
