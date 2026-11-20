extends Node
var failures: Array[String] = []
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _ready() -> void:
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(),CardDatabase.beginner_deck())
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await get_tree().create_timer(1.0).timeout
	battle.game.current_player = 1
	battle.game.is_player_turn = true
	battle.game.turn_number = 2
	battle.game.player_field.slots.fill(null)
	battle.game.player2_field.slots.fill(null)
	battle.game.player_field.slots[0] = CardData.new("攻击者",0,5,5,[])
	battle.game.player_field.action_points = 10
	battle.game.player_field.action_budget = 10
	var fragile := CardData.new("可击杀",0,2,1,[])
	var taunt := CardData.new("嘲讽",0,8,1,[])
	taunt.apply_buff(SkillEngine.BUFF_TAUNT,1,3)
	var immune := CardData.new("免疫致命",0,1,1,[])
	immune.immune_lethal = true
	battle.game.player2_field.slots[0] = fragile
	battle.game.player2_field.slots[1] = taunt
	battle.game.player2_field.slots[2] = immune
	battle.update_entire_screen()
	await settle()
	_check(is_gold(outline_color(battle,6)),"taunt card has a persistent gold outline")
	battle._on_attack_requested(0)
	await settle()
	_check(outline_color(battle,5).a==0,"taunt prevents marking a blocked target as lethal")
	taunt.status_effects.clear()
	battle.update_entire_screen()
	await settle()
	_check(is_red(outline_color(battle,5)),"a legal guaranteed kill has a red outline")
	_check(not is_red(outline_color(battle,7)),"lethal immunity must not show a kill outline")
	await capture("lethal-outline.png")
	fragile.temp_hp = 8
	battle.update_entire_screen()
	await settle()
	_check(not is_red(outline_color(battle,5)),"temporary HP updates lethal eligibility immediately")
	battle.cancel_attack()
	taunt.apply_buff(SkillEngine.BUFF_TAUNT,1,3)
	battle.update_entire_screen()
	await settle()
	_check(outline_color(battle,5).a==0,"cancelling targeting removes the kill hint")
	_check(is_gold(outline_color(battle,6)),"taunt outline survives cancelling targeting")
	await capture("taunt-outline.png")
	battle.game.player2_field.slots[1] = null
	battle.update_entire_screen()
	await settle()
	_check(not battle.tabletop.cards.has(6),"removed cards leave no outline behind")
	battle.queue_free()
	await get_tree().process_frame
	if failures.is_empty(): print("TEST_TARGET_OUTLINES_VISUAL_OK"); get_tree().quit(0)
	else:
		for message in failures: push_error("TEST_TARGET_OUTLINES_VISUAL_FAILED: "+message)
		get_tree().quit(1)
func outline_color(battle: Node,key: int) -> Color:
	if not battle.tabletop.cards.has(key): return Color.TRANSPARENT
	var entry: Dictionary = battle.tabletop.cards[key]
	if not entry.has("outline") or not entry.outline.visible: return Color.TRANSPARENT
	return entry.outline.material_override.get_shader_parameter("edge_color")
func is_red(color: Color) -> bool: return color.a>0 and color.r>0.7 and color.g<0.5
func is_gold(color: Color) -> bool: return color.a>0 and color.r>0.7 and color.g>0.5 and color.b<0.5
func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/target-outlines-20261114/"+name)
func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
