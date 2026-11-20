extends "res://DirectLobby.gd"
var role := 1
var shared := ""
var seconds := 3600.0
var battle: Node
var elapsed := 0.0
var ready_sent := false
var next_action := 0.0
var moves_in_turn := 0
var actions := 0
var start_match := -1.0
var last_progress := 0.0
var port := 5228
var wall_started := 0

func _ready() -> void:
 wall_started=Time.get_ticks_msec()
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--role="): role=int(argument.trim_prefix("--role="))
  if argument.begins_with("--shared="): shared=argument.trim_prefix("--shared=")
  if argument.begins_with("--seconds="): seconds=float(argument.trim_prefix("--seconds="))
 NetworkManager.use_isolated_session_storage("release-soak-p%d" % role)
 NetworkManager.clear_room_session()
 PlayerData.prepare_online_selection("res://DirectLobby.tscn")
 PlayerData.battle_deck.clear()
 for i in range(12): PlayerData.battle_deck.append(CardData.new("Soak P%d %d" % [role,i],0,6,0))
 AppPreferences.set_value("fps",30)
 GamePreferences.set_battle_playback_speed(GamePreferences.PlaybackSpeed.FAST if role==2 else GamePreferences.PlaybackSpeed.DEFAULT)
 super._ready()
 set_process(true)
 if role==1:
  var error=NetworkManager.host_game(port)
  assert(error==OK,"soak host must bind its isolated port")
  _show_waiting_room()
 else:
  ip_input.text="127.0.0.1:%d" % port
  _on_join_pressed()

func _process(delta: float) -> void:
 super._process(delta)
 elapsed=float(Time.get_ticks_msec()-wall_started)/1000.0
 if battle==null:
  if elapsed>40: _fail("lobby timeout"); return
  if NetworkManager.is_game_rpc_ready():
   var marker=FileAccess.open(shared+".ready%d"%role,FileAccess.WRITE)
   marker.store_string("ready")
   marker.close()
   if FileAccess.file_exists(shared+".ready%d"%(3-role)) and elapsed>3 and waiting_ui!=null and not ready_sent:
    ready_sent=true
    _on_start_pressed()
  for child in match_agreement.get_children():
   if child is ConfirmationDialog and not child.is_queued_for_deletion(): child.confirmed.emit()
  return
 if start_match<0: start_match=elapsed
 if elapsed-start_match>=seconds:
  print("TEST_NETWORK_PRESENTATION_SOAK_OK_P%d " % role,JSON.stringify({"seconds":elapsed-start_match,"actions":actions,"revision":battle.game.state_revision,"pending":NetworkManager.pending_game_command_count()}))
  set_process(false)
  _finish_later()
  return
 if elapsed-last_progress>60:
  last_progress=elapsed
  print("SOAK_NETWORK_CHECKPOINT_P%d " % role,JSON.stringify({"seconds":elapsed-start_match,"actions":actions,"revision":battle.game.state_revision,"pending":NetworkManager.pending_game_command_count(),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"memory":OS.get_static_memory_usage()}))
 if battle.battle_finished: _fail("zero-attack stress match unexpectedly ended"); return
 if battle.match_paused:
  if elapsed-next_action>20: _fail("network stuck paused")
  return
 if not battle.is_my_turn() or battle.is_resolution_locked() or elapsed<next_action or NetworkManager.pending_game_command_count()>0: return
 next_action=elapsed+0.55
 var field: BattleField = battle.game.player_field if role==1 else battle.game.player2_field
 var source := -1
 for i in range(5):
  if field.slots[i]!=null: source=i; break
 if source<0:
  var hand: Array = battle.game.player_hand if role==1 else battle.game.player2_hand
  if hand.is_empty(): _fail("stress hand unexpectedly empty"); return
  battle._on_card_drag_summoned(hand[0],null,0)
 elif moves_in_turn<8:
  battle._on_card_drag_summoned(field.slots[source],null,(source+1)%5)
  moves_in_turn+=1
 else:
  battle._on_end_turn_pressed()
  moves_in_turn=0
 actions+=1

func _on_battle_start(match_id: String) -> void:
 if battle!=null: return
 NetworkManager.mark_match_started(match_id)
 lobby_panel.hide()
 if waiting_ui: waiting_ui.hide()
 battle=preload("res://Main.tscn").instantiate()
 add_child(battle)
 set_process(true)

func _on_opponent_disconnected(_player: int) -> void:
 if battle==null: super._on_opponent_disconnected(_player)

func _fail(reason: String) -> void:
 push_error("TEST_NETWORK_PRESENTATION_SOAK_FAILED_P%d: %s" % [role,reason])
 set_process(false)
 get_tree().quit(1)

func _finish_later() -> void:
 await get_tree().create_timer(1).timeout
 AppAudio._exit_tree()
 await get_tree().create_timer(0.2).timeout
 get_tree().quit(0)
