extends Node


func _ready() -> void:
	var options := {"input": "", "output": "res://artifacts/ai-decisions/trace.json"}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2 and options.has(pair[0]): options[pair[0]] = pair[1]
	if str(options.input).is_empty():
		_fail("--input must name an existing complete position/replay file")
		return
	if ProjectSettings.globalize_path(str(options.input)).simplify_path().to_lower() == ProjectSettings.globalize_path(str(options.output)).simplify_path().to_lower():
		_fail("output must not overwrite the input replay")
		return
	var file := FileAccess.open(str(options.input), FileAccess.READ)
	if file == null or file.get_length() > BattlePosition.MAX_FILE_BYTES:
		_fail("input is missing or too large")
		return
	var imported := BattleRepro.import_json(file.get_as_text())
	if not imported.ok:
		_fail(str(imported.reason))
		return
	var result := AiDecisionTrace.build(imported.record)
	if not result.ok:
		_fail(BattleRepro.export_json(result))
		return
	result.report["input_path"] = str(options.input)
	result.report["input_sha256"] = FileAccess.get_sha256(str(options.input))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(options.output).get_base_dir())) != OK:
		_fail("cannot create output directory")
		return
	var output := FileAccess.open(str(options.output), FileAccess.WRITE)
	if output == null:
		_fail("cannot write trace")
		return
	output.store_string(BattleRepro.export_json(result.report))
	if output.get_error() != OK:
		_fail("trace write failed")
		return
	print("AI_DECISION_TRACE_DONE decisions=%d steps=%d no_payload=%d hash=%s" % [result.report.summary.decisions, result.report.summary.recorded_steps, result.report.summary.activations_without_observed_payload, result.report.final_hash])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("AI_DECISION_TRACE_FAILED: " + reason)
	get_tree().quit(1)
