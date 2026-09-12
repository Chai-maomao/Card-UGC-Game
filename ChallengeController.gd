class_name ChallengeController
extends Node

var battle: Node
var challenge_id: String
var finished := false
var elapsed := 0.0
var dialog: AcceptDialog


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
	if is_instance_valid(dialog):
		dialog.queue_free()
	battle.cancel_attack()
	PracticeChallenges.configure(battle.game, challenge_id)
	battle.battle_finished = false
	finished = false
	elapsed = 0.0
	battle.update_entire_screen()
	_show()


func _show(include_hint := false) -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
	dialog = AcceptDialog.new()
	var number := PracticeChallenges.IDS.find(challenge_id) + 1
	dialog.title = "%d/%d · %s · %s" % [number, PracticeChallenges.IDS.size(), PracticeChallenges.title(challenge_id), PracticeChallenges.difficulty(challenge_id)]
	dialog.dialog_text = PracticeChallenges.objective(challenge_id) + "\n\n" + PracticeChallenges.progress(battle.game, challenge_id)
	if include_hint:
		dialog.dialog_text += "\n\n" + PracticeChallenges.hint(challenge_id)
	if finished:
		if PracticeChallenges.succeeded(battle.game, challenge_id):
			dialog.dialog_text += "\n\n" + ("挑战成功！" if Locale.language == "zh" else "Challenge complete!") + "\n" + PracticeChallenges.lesson(challenge_id)
		else:
			dialog.dialog_text += "\n\n" + PracticeChallenges.failure_reason(battle.game, challenge_id)
	dialog.get_ok_button().text = "关闭" if Locale.language == "zh" else "Close"
	var retry := dialog.add_button("重新挑战" if Locale.language == "zh" else "Retry", false, "retry")
	UITheme.apply_button(retry, "secondary")
	if not finished:
		var hint_button := dialog.add_button("查看提示" if Locale.language == "zh" else "Hint", false, "hint")
		UITheme.apply_button(hint_button, "secondary")
	dialog.custom_action.connect(func(action: String):
		if action == "retry":
			_reset()
		elif action == "hint":
			dialog.dialog_text = PracticeChallenges.objective(challenge_id) + "\n\n" + PracticeChallenges.progress(battle.game, challenge_id) + "\n\n" + PracticeChallenges.hint(challenge_id)
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	UITheme.apply_dialog(dialog)
	dialog.popup_centered(Vector2i(640, 240))


func _process(delta: float) -> void:
	if battle == null or finished: return
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0
	if PracticeChallenges.succeeded(battle.game, challenge_id) or PracticeChallenges.failed(battle.game, challenge_id):
		finished = true
		_show()


func _exit_tree() -> void:
	PlayerData.practice_challenge_id = ""
