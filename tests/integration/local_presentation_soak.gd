extends Node
var battle: Node
var seconds := 7200.0
var started := 0
var actions := 0
var games := 0
var rng := RandomNumberGenerator.new()
var last_checkpoint := 0
var samples: Array[float] = []

func _ready() -> void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--seconds="): seconds=float(argument.trim_prefix("--seconds="))
 rng.seed=90317
 AppPreferences.set_value("fps",60)
 started=Time.get_ticks_msec()
 await _new_game()
 while float(Time.get_ticks_msec()-started)/1000.0 < seconds:
  await get_tree().create_timer(0.45).timeout
  if battle.battle_finished or not battle.game.check_game_over().is_empty():
   battle.queue_free()
   await get_tree().process_frame
   await _new_game()
   continue
  if battle.is_resolution_locked() or battle.match_paused: continue
  var choice=BattleAiPlanner.choose_action(battle.game,["easy","normal","hard"][games%3],rng)
  var player: int=battle.game.current_player
  match str(choice.get("type","end_turn")):
   "summon": battle._host_apply_summon(choice.hand_index,choice.slot,player)
   "attack": battle._host_apply_attack(choice.source_slot,choice.target_slot,player)
   "activate": battle._host_apply_skill(choice.slot,choice.skill_index,choice.get("target_slot",-1),player)
   "cast": battle._host_apply_cast(choice.hand_index,choice.get("skill_index",-1),choice.get("target_slot",-1),player,choice.get("target_player",0))
   "attach": battle._host_apply_parasite(choice.hand_index,choice.target_player,choice.target_slot,player)
   _: battle._host_apply_end_turn(player)
  actions+=1
  var elapsed=Time.get_ticks_msec()-started
  if elapsed-last_checkpoint >= 60000:
   last_checkpoint=elapsed
   var state: Dictionary=battle.game.export_initial_state()
   var store := MatchSnapshotStore.new("user://soak_checkpoint.json")
   assert(store.save({"schema":1,"room_code":"local-soak","player":1,"state":MatchSnapshotStore.encode_state(state)}),"soak snapshot must save")
   assert(BattleRepro.hash_state(MatchSnapshotStore.decode_state(store.load().state))==BattleRepro.hash_state(state),"soak checkpoint must roundtrip without progress loss")
   print("SOAK_LOCAL_CHECKPOINT ",JSON.stringify({"seconds":elapsed/1000.0,"actions":actions,"games":games,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"memory":OS.get_static_memory_usage(),"physics":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),"process":Performance.get_monitor(Performance.TIME_PROCESS),"hash":BattleRepro.hash_state(state)}))
 print("TEST_LOCAL_PRESENTATION_SOAK_OK ",JSON.stringify({"seconds":(Time.get_ticks_msec()-started)/1000.0,"actions":actions,"games":games}))
 battle.queue_free()
 await get_tree().process_frame
 AppAudio._exit_tree()
 await get_tree().create_timer(0.2).timeout
 get_tree().quit(0)

func _new_game() -> void:
 games+=1
 NetworkManager.close_connection()
 PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(),CardDatabase.beginner_deck())
 PlayerData.practice_challenge_id=""
 battle=preload("res://Main.tscn").instantiate()
 add_child(battle)
 await get_tree().create_timer(0.6).timeout
