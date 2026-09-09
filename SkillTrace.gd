class_name SkillTrace
extends RefCounted

const LIMIT := 300
var entries: Array[Dictionary] = []
var dropped := 0


func record(entry: Dictionary) -> void:
	if entries.size() >= LIMIT:
		entries.pop_front()
		dropped += 1
	entries.append(entry.duplicate(true))


func clear() -> void:
	entries.clear()
	dropped = 0


static func describe(entry: Dictionary) -> String:
	var names := {
		"trigger": ["触发", "Trigger"], "silenced": ["被沉默阻止", "Blocked by silence"],
		"uses_exhausted": ["次数耗尽", "Uses exhausted"], "probability_failed": ["概率未命中", "Roll failed"],
		"condition_false": ["条件不成立", "Condition false"], "condition": ["条件判断", "Condition"],
		"repeat": ["重复执行", "Repeat"], "resolved": ["执行效果", "Effect"],
		"no_target": ["没有合法目标", "No target"], "first_turn_blocked": ["首回合限制", "First-turn restriction"],
		"budget_exhausted": ["执行预算耗尽", "Execution budget exhausted"],
	}
	var event := str(entry.get("event", ""))
	var label: String = names.get(event, [event, event])[0 if Locale.language == "zh" else 1]
	var detail := ""
	if entry.has("target"):
		detail = " → %s · %s = %s" % [entry.target, entry.get("effect", ""), entry.get("value", "")]
	elif entry.has("passed"):
		detail = " · " + str(entry.passed)
	elif entry.has("count"):
		detail = " × " + str(entry.count)
	return "%s · %s%s" % [entry.get("source", ""), label, detail]
