extends Node


func _ready() -> void:
	var report := BalanceCalibration.run(40)
	var failures := 0
	for row in report.pools:
		if row.simulation.stability_failures != 0 or row.simulation.games != 40:
			failures += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var file := FileAccess.open("res://artifacts/balance-calibration.json", FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t"))
	if failures:
		push_error("TEST_BALANCE_CALIBRATION_FAILED")
		get_tree().quit(1)
	else:
		print("TEST_BALANCE_CALIBRATION_OK games=120 pools=3")
		get_tree().quit(0)
