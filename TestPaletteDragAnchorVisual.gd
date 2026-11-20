extends Node
var editor: Control
func _enter_tree() -> void:
 get_window().set_flag(Window.FLAG_NO_FOCUS,true)
 get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _ready() -> void:
 get_window().size=Vector2i(1280,720)
 Input.use_accumulated_input=false
 Locale.language="zh"
 PlayerData.skill_tutorial_active=false
 PlayerData.init_card_draft()
 PlayerData.editing_skill_index=0
 editor=load("res://SkillEditor.tscn").instantiate()
 add_child(editor)
 await get_tree().create_timer(0.4).timeout
 editor.palette_search.text="比较"
 editor.palette_search.text_changed.emit("比较")
 await get_tree().create_timer(0.3).timeout
 var source: Button
 for node in editor.palette_vbox.find_children("*","Button",true,false):
  if node.text=="比较": source=node
 assert(source!=null)
 for zoom in [0.85,0.65,1.0]:
  editor.workbench.workspace.set_zoom(zoom)
  for fraction in [0.18,0.88]:
   var start: Vector2=source.get_global_transform()*(source.size*Vector2(fraction,0.5))
   await motion(start,false)
   await mouse(start,true)
   var destination: Vector2=editor.workbench.workspace.global_position+Vector2(250,310)
   for step in range(1,9):
    await motion(start.lerp(destination,step/8.0),true)
   await RenderingServer.frame_post_draw
   var previews=get_tree().root.find_children("*","Button",true,false).filter(func(n):return n.get_meta("drag_preview",false))
   assert(get_viewport().gui_is_dragging() and previews.size()==1,"real palette drag must be active")
   var preview: Button=previews[0]
   var local: Vector2=preview.get_global_transform().affine_inverse()*destination
   print("ANCHOR ",zoom," ",fraction," pointer=",local," size=",preview.size)
   get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/palette-drag-anchor.png")
   assert(Rect2(Vector2.ZERO,preview.size).has_point(local),"grabbed point must remain inside the dragged button")
   assert(absf(local.x/preview.size.x-fraction)<0.04,"grab position must follow source face, including empty right side")
   await motion(destination+Vector2(80,-50),true)
   await RenderingServer.frame_post_draw
   var moved: Vector2=preview.get_global_transform().affine_inverse()*(destination+Vector2(80,-50))
   assert(moved.distance_to(local)<0.5,"grab anchor must remain stable during travel")
   await mouse(Vector2(5,5),false)
   await get_tree().create_timer(0.15).timeout
 print("TEST_PALETTE_DRAG_ANCHOR_OK")
 get_tree().quit()
func mouse(point:Vector2,pressed:bool)->void:
 var e=InputEventMouseButton.new()
 e.position=point
 e.global_position=point
 e.button_index=MOUSE_BUTTON_LEFT
 e.pressed=pressed
 e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 get_viewport().push_input(e,true)
 await get_tree().process_frame
func motion(point:Vector2,pressed:bool)->void:
 var e=InputEventMouseMotion.new()
 e.position=point
 e.global_position=point
 e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 e.relative=point-get_viewport().get_mouse_position()
 get_viewport().push_input(e,true)
 await get_tree().process_frame
