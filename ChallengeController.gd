class_name ChallengeController
extends Node

var battle: Node
var challenge_id: String
var finished := false
var elapsed := 0.0


func setup(owner_battle: Node, header: HBoxContainer) -> void:
	battle = owner_battle
	challenge_id = PlayerData.practice_challenge_id
	var button := Button.new()
	button.text = "挑战目标 / Challenge"
	UITheme.apply_button(button, "secondary")
	header.add_child(button)
	button.pressed.connect(_show)
	_reset.call_deferred()


func _reset() -> void:
	battle.cancel_attack()
	PracticeChallenges.configure(battle.game, challenge_id)
	battle.battle_finished = false
	finished = false
	battle.update_entire_screen()
	_show()


func _show() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = PracticeChallenges.title(challenge_id)
	dialog.dialog_text = PracticeChallenges.objective(challenge_id)
	if finished:
		dialog.dialog_text += "\n" + ("挑战成功 / Challenge complete" if PracticeChallenges.succeeded(battle.game, challenge_id) else "本回合已结束，请重试 / Turn ended. Try again.")
	dialog.add_button("重新挑战 / Retry", false, "retry")
	dialog.custom_action.connect(func(_action: String):
		dialog.queue_free()
		_reset()
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(580, 180))


func _process(delta: float) -> void:
	if battle == null or finished: return
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0
	if PracticeChallenges.succeeded(battle.game, challenge_id) or battle.game.turn_number > 2:
		finished = true
		_show()


func _exit_tree() -> void:
	PlayerData.practice_challenge_id = ""
