extends Node
var role:=1
var sent:=false
var received:Dictionary={}
var acknowledged:Dictionary={}
var done:=false
var remote:CardData
func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):role=int(arg.get_slice("=",1))
	NetworkManager.use_isolated_session_storage("dual-art-wire")
	var card=CardData.new("Dual artwork",1,4,2)
	for field in ["art_path","damaged_art_path"]:
		var image=Image.create(320,303,false,Image.FORMAT_RGB8)
		image.fill(Color(0.2,0.6,0.4) if field=="art_path" else Color(0.7,0.3,0.2))
		var path="user://"+field+".png"
		assert(image.save_png(path)==OK)
		card.set(field,path)
	PlayerData.battle_deck=[card]
	remote=CardData.new("Dual artwork",1,4,2)
	NetworkManager.connected.connect(func():
		if not sent:
			sent=true
			NetworkManager.send_card_arts(PlayerData.card_art_transfers([card])))
	EventBus.rpc_card_art_received.connect(func(index,ext,bytes,total):
		assert(total==2 and index in [0,PlayerData.DAMAGED_ART_INDEX_OFFSET])
		var path=PlayerData.save_net_art(bytes,ext)
		assert(not path.is_empty())
		PlayerData.apply_received_art([remote],index,path)
		received[index]=true
		NetworkManager.send_card_art_ack(index,total))
	EventBus.rpc_card_art_ack_received.connect(func(index,total):
		assert(total==2)
		acknowledged[index]=true)
	var err=NetworkManager.host_game(55890) if role==1 else NetworkManager.join_game("127.0.0.1",55890)
	assert(err==OK)
	get_tree().create_timer(12).timeout.connect(func():
		if not done:
			push_error("TEST_DUAL_ART_WIRE_FAILED timeout")
			get_tree().quit(1))
func _process(_delta):
	if done or received.size()!=2 or acknowledged.size()!=2:return
	done=true
	assert(FileAccess.get_sha256(remote.art_path)==FileAccess.get_sha256(PlayerData.battle_deck[0].art_path))
	assert(FileAccess.get_sha256(remote.damaged_art_path)==FileAccess.get_sha256(PlayerData.battle_deck[0].damaged_art_path))
	remote.take_damage(1)
	assert(CardArtwork.selected_path(remote)==remote.damaged_art_path)
	remote.heal(1)
	assert(CardArtwork.selected_path(remote)==remote.art_path)
	print("TEST_DUAL_ART_WIRE_OK_P",role)
	await get_tree().create_timer(0.6).timeout
	NetworkManager.close_connection()
	get_tree().quit(0)
