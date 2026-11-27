extends Node

var stage: SubViewport

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)

func _click(point: Vector2, pressed: bool, double_click := false, mouse_button := MOUSE_BUTTON_LEFT) -> void:
	if pressed:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		stage.push_input(motion, true)
		await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.button_index = mouse_button
	event.pressed = pressed
	event.double_click = double_click
	event.button_mask = (1 << (mouse_button - 1)) if pressed else 0
	event.position = point
	event.global_position = point
	stage.push_input(event,true)
	await get_tree().process_frame

func _ready() -> void:
	Input.use_accumulated_input = false
	PlayerData.init_card_draft()
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.gui_embed_subwindows = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var image := Image.create(1200,600,false,Image.FORMAT_RGB8)
	image.fill_rect(Rect2i(0,0,400,600),Color.RED)
	image.fill_rect(Rect2i(400,0,400,600),Color.GREEN)
	image.fill_rect(Rect2i(800,0,400,600),Color.BLUE)
	var source := "user://crop-source.png"
	assert(image.save_png(source)==OK)
	var editor := preload("res://CardEditor.tscn").instantiate()
	stage.add_child(editor)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/ui-refinement-20261113")
	var upload_button: Button = editor.browse_button
	var upload_rect := upload_button.get_global_rect()
	var upload_point := upload_rect.get_center()
	var hover := InputEventMouseMotion.new()
	hover.position = upload_point
	stage.push_input(hover, true)
	await get_tree().create_timer(0.2).timeout
	assert(upload_button.is_hovered() and upload_button.get_global_rect() == upload_rect and upload_button.scale == Vector2.ONE,
		"hovering the upload area must leave its position and size unchanged")
	await RenderingServer.frame_post_draw
	stage.get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/card-art-upload.png")
	var paths := PackedStringArray([ProjectSettings.globalize_path(source)])
	hover = InputEventMouseMotion.new()
	hover.position = Vector2.ZERO
	stage.push_input(hover, true)
	get_window().files_dropped.emit(paths)
	assert(not is_instance_valid(editor._art_crop), "dropping outside an upload surface must leave the draft alone")
	hover = InputEventMouseMotion.new()
	hover.position = upload_point
	stage.push_input(hover, true)
	get_window().files_dropped.emit(paths)
	await get_tree().process_frame
	var dialog = editor.get_child(editor.get_child_count()-1)
	assert(dialog.get_script()==preload("res://presentation/CardArtCropDialog.gd"))
	await get_tree().create_timer(0.25).timeout
	var view: Control = dialog.crop_view
	var before: Rect2i = view.source_rect()
	var start := view.get_global_transform_with_canvas()*Vector2(192,245)
	hover = InputEventMouseMotion.new()
	hover.position = start
	stage.push_input(hover, true)
	await get_tree().process_frame
	await _click(start,true)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = view.get_global_transform_with_canvas()*Vector2(372,245)
	motion.global_position = motion.position
	stage.push_input(motion,true)
	await get_tree().process_frame
	await _click(motion.position,false)
	assert(view.source_rect().position.x<before.position.x,"dragging the image must change the selected crop")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/ui-refinement-20261113")
	stage.get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/crop-drag.png")
	var zoom: HSlider = dialog.find_children("*","HSlider",true,false)[0]
	var previous_width: int = view.source_rect().size.x
	await _click(zoom.get_global_rect().get_center(),true)
	await _click(zoom.get_global_rect().get_center(),false)
	assert(zoom.value>1 and view.source_rect().size.x<previous_width,"the real zoom slider must change the cropped area")
	var confirm: Button
	for button in dialog.find_children("*","Button",true,false):
		if button.text==Locale.t("battle.confirm"): confirm=button
	assert(confirm!=null)
	await _click(confirm.get_global_rect().get_center(),true)
	await _click(confirm.get_global_rect().get_center(),false)
	assert(await _wait_for_crop_close(editor), "The imported crop must finish saving")
	var saved_path: String=PlayerData.card_draft["art_path"]
	assert(saved_path.begins_with("user://arts/crop-") and FileAccess.file_exists(saved_path))
	var cropped := Image.load_from_file(saved_path)
	var pixel := cropped.get_pixel(cropped.get_width()/2,cropped.get_height()/2)
	assert(pixel.r>0.9 and pixel.g<0.1,"saved pixels must match the red region selected by the real drag")
	var checksum := FileAccess.get_sha256(saved_path)
	editor._on_art_file_selected(source)
	await get_tree().process_frame
	dialog=editor.get_child(editor.get_child_count()-1)
	var cancel: Button
	for button in dialog.find_children("*","Button",true,false):
		if button.text==Locale.t("common.cancel"): cancel=button
	assert(cancel!=null)
	await _click(cancel.get_global_rect().get_center(),true)
	await _click(cancel.get_global_rect().get_center(),false)
	await get_tree().process_frame
	assert(PlayerData.card_draft["art_path"]==saved_path and FileAccess.get_sha256(saved_path)==checksum,"cancel must retain the previous art and its pixels")
	assert(FileAccess.get_sha256(source)!=checksum,"the source image must remain separate from the cropped asset")
	var noise := Image.create_from_data(1536,1536,false,Image.FORMAT_RGB8,Crypto.new().generate_random_bytes(1536*1536*3))
	assert(noise.save_png("user://crop-noise.png")==OK)
	editor._on_art_file_selected("user://crop-noise.png")
	await get_tree().process_frame
	dialog=editor.get_child(editor.get_child_count()-1)
	for button in dialog.find_children("*","Button",true,false):
		if button.text==Locale.t("battle.confirm"): confirm=button
	await _click(confirm.get_global_rect().get_center(),true)
	await _click(confirm.get_global_rect().get_center(),false)
	assert(await _wait_for_crop_close(editor), "Large art must finish saving")
	assert(not PlayerData.read_art_bytes(PlayerData.card_draft["art_path"]).is_empty(),"a detailed uploaded crop must remain transferable under the existing art limit")
	editor.art_dialog.use_native_dialog = false
	upload_point = upload_button.get_global_rect().get_center()
	hover = InputEventMouseMotion.new()
	hover.position = upload_point
	stage.push_input(hover, true)
	await _click(upload_point, true)
	await _click(upload_point, false)
	assert(upload_button.has_focus() and not editor.art_dialog.visible, "one click must focus the normal art field for paste")
	await _click(upload_point, true, true)
	await _click(upload_point, false)
	assert(editor.art_dialog.visible and editor._art_edit_field == "art_path", "double-click opens the normal art picker")
	editor.art_dialog.hide()
	await get_tree().process_frame
	var damaged: Button = editor._damaged_art_browse
	var scroll := editor.get_node("Panel/MarginContainer/ScrollContainer") as ScrollContainer
	scroll.ensure_control_visible(damaged)
	await get_tree().process_frame
	var damaged_point := damaged.get_global_rect().get_center()
	hover.position = damaged_point
	stage.push_input(hover, true)
	await _click(damaged_point, true)
	await _click(damaged_point, false)
	assert(damaged.has_focus() and not editor.art_dialog.visible, "one click must focus the damaged art field for paste")
	await _click(damaged_point, true, true)
	await _click(damaged_point, false)
	assert(editor.art_dialog.visible and editor._art_edit_field == "damaged_art_path", "double-click opens the damaged art picker")
	editor.art_dialog.hide()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--clipboard-fixture"):
		assert(DisplayServer.clipboard_has_image(), "Clipboard fixture must contain an image")
		assert(await _check_right_click_paste(editor, scroll, upload_button, "art_path", "damaged_art_path"), "Normal art right-click must save and show the imported row")
		assert(await _check_right_click_paste(editor, scroll, damaged, "damaged_art_path", "art_path"), "Damaged art right-click must save and show the imported row")
		await RenderingServer.frame_post_draw
		stage.get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/card-art-imported.png")
		await _check_imported_actions(editor, scroll, upload_button, damaged)
		print("TEST_CARD_ART_RIGHT_CLICK_OK")
	print("TEST_CARD_ART_CROP_VISUAL_OK upload-area,crop-drag,zoom,saved-pixels,cancel-keeps-art,network-art-budget")
	editor.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _check_right_click_paste(editor: Control, scroll: ScrollContainer, target: Button, field: String, other: String) -> bool:
	var prior := str(PlayerData.card_draft.get(field, ""))
	var untouched := str(PlayerData.card_draft.get(other, ""))
	scroll.ensure_control_visible(target)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await get_tree().process_frame
	var point := target.get_global_rect().get_center()
	if not scroll.get_global_rect().has_point(point):
		return false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	stage.push_input(motion, true)
	await get_tree().process_frame
	var hovered := stage.gui_get_hovered_control()
	if hovered != target and not target.is_ancestor_of(hovered):
		push_error("Right-click fixture missed %s at %s and found %s" % [target.name, point, hovered])
		return false
	var paste_receivers: Array[String] = []
	var normal_record := func(): paste_receivers.append("art_path")
	var damage_record := func(): paste_receivers.append("damaged_art_path")
	editor.browse_button.paste_requested.connect(normal_record)
	editor._damaged_art_browse.paste_requested.connect(damage_record)
	await _click(point, true, false, MOUSE_BUTTON_RIGHT)
	await _click(point, false, false, MOUSE_BUTTON_RIGHT)
	editor.browse_button.paste_requested.disconnect(normal_record)
	editor._damaged_art_browse.paste_requested.disconnect(damage_record)
	if paste_receivers != [field]:
		push_error("Right-click for %s was received by %s" % [field, str(paste_receivers)])
		return false
	var crop: CanvasLayer = editor._art_crop
	if not is_instance_valid(crop) or editor.art_dialog.visible:
		return false
	await RenderingServer.frame_post_draw
	var confirmation: Button
	for button in crop.find_children("*", "Button", true, false):
		if button.text == Locale.t("battle.confirm"):
			confirmation = button
			break
	if not is_instance_valid(confirmation):
		return false
	await _click(confirmation.get_global_rect().get_center(), true)
	await _click(confirmation.get_global_rect().get_center(), false)
	if not await _wait_for_crop_close(editor):
		return false
	var saved := str(PlayerData.card_draft[field])
	if saved == prior or not FileAccess.file_exists(saved) or str(PlayerData.card_draft.get(other, "")) != untouched:
		push_error("Saved art did not replace exactly one field: %s, changed=%s, written=%s, other_unchanged=%s" % [field, saved != prior, FileAccess.file_exists(saved), str(PlayerData.card_draft.get(other, "")) == untouched])
		return false
	var row := target.get_node("ImportedArt") as Control
	var name_label := row.find_child("ImportedArtName", true, false) as Label
	var amount := row.find_child("ImportedArtSize", true, false) as Label
	var file := FileAccess.open(saved, FileAccess.READ)
	return row.is_visible_in_tree() and name_label.text == saved.get_file() and amount.text == String.humanize_size(file.get_length()) and target.tooltip_text.is_empty()


func _check_imported_actions(editor: Control, scroll: ScrollContainer, normal: Button, damaged: Button) -> void:
	var original := str(PlayerData.card_draft.art_path)
	var replace := normal.find_child("ReplaceArt", true, false) as Button
	scroll.ensure_control_visible(replace)
	await RenderingServer.frame_post_draw
	var point := replace.get_global_rect().get_center()
	await _click(point, true)
	await _click(point, false)
	assert(editor.art_dialog.visible and editor._art_edit_field == "art_path", "Replace must open the normal art picker")
	editor.art_dialog.hide()
	await get_tree().process_frame
	var clear: Button = editor._damaged_art_clear
	scroll.ensure_control_visible(clear)
	await RenderingServer.frame_post_draw
	point = clear.get_global_rect().get_center()
	await _click(point, true)
	await _click(point, false)
	assert(str(PlayerData.card_draft.art_path) == original and str(PlayerData.card_draft.damaged_art_path).is_empty())
	assert(not damaged.get_node("ImportedArt").visible, "Clear must return to the empty drop zone")


func _wait_for_crop_close(editor: Control) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while is_instance_valid(editor._art_crop) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not is_instance_valid(editor._art_crop)
