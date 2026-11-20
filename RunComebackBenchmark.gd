extends Node

const Benchmark = preload("res://ComebackBenchmark.gd")
const Repro = preload("res://BattleRepro.gd")


func _ready() -> void:
	var options := {"samples": "128", "seed": "20261005", "pool": "all", "ai": "hard", "variants": "legacy,action", "scenarios": "all", "output": "res://artifacts/comeback-20261005.json"}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2: options[parts[0]] = parts[1]
	var count := maxi(2, int(options["samples"]))
	var base_seed := int(options["seed"])
	var pools := {"vanilla": Benchmark.vanilla_pool(), "beginner": CardDatabase.beginner_deck()}
	var requested_pool := str(options["pool"])
	if requested_pool == "local":
		pools = {"local": PlayerData.get_cards_for_deck(PlayerData.current_deck_id)}
	elif requested_pool != "all":
		if not pools.has(requested_pool):
			push_error("Unknown benchmark pool")
			get_tree().quit(1)
			return
		pools = {requested_pool: pools[requested_pool]}
	var variants := str(options["variants"]).split(",")
	for variant in variants:
		if not variant in ["legacy", "action", "board_x2", "elixir_x2", "no_hand", "base_1"]:
			push_error("Unknown benchmark rules: " + variant)
			get_tree().quit(1)
			return
	var report := {"version": 1, "seed": base_seed, "samples_per_cell": count, "ai": options["ai"], "max_player_turns": 100, "hand_limit": SkillEngine.MAX_HAND_SIZE, "scenarios": Benchmark.scenarios(), "base_config": PlayerData.DEFAULT_BATTLE_CONFIG, "rows": [], "trials": [], "elapsed_ms": 0}
	report["pool_manifest"] = {}
	for pool_id in pools:
		var manifest: Array = []
		var index := 0
		for card: CardData in pools[pool_id]:
			var specimen := card.duplicate_card()
			specimen.card_id = card.card_id if not card.card_id.is_empty() else "benchmark-pool-%d" % index
			specimen.instance_id = "benchmark-template-%s-%d" % [pool_id, index]
			manifest.append(PlayerData.serialize_card(specimen))
			index += 1
		report["pool_manifest"][pool_id] = manifest
	report["source_sha256"] = {}
	for path in ["ComebackBenchmark.gd", "GameState.gd", "BattleAiPlanner.gd", "BattleSearch.gd", "SkillEngine.gd", "CardData.gd"]:
		report["source_sha256"][path] = FileAccess.get_sha256("res://" + path)
	var started := Time.get_ticks_msec()
	var rejected := 0
	for pool_id in pools:
		var pool: Array = pools[pool_id]
		if pool.is_empty():
			push_error("Empty benchmark pool")
			get_tree().quit(1)
			return
		for scenario in Benchmark.scenarios():
			if str(options["scenarios"]) != "all" and not str(scenario["id"]) in str(options["scenarios"]).split(","): continue
			for trailer_next in [true, false]:
				var rows := {}
				for variant in variants:
					rows[variant] = {"pool": pool_id, "scenario": scenario["id"], "trailer_next": trailer_next, "variant": variant, "games": count, "comeback": 0, "held": 0, "draw": 0, "failures": 0, "turns": 0, "board_restored": 0, "trailer": {}, "leader": {}, "first_trailer": {}, "first_leader": {}}
				for index in range(count):
					var seed_value := base_seed + index
					var trailer := 1 + index % 2
					var state := Benchmark.make_state(pool, scenario, seed_value, trailer, trailer_next)
					for variant in variants:
						var result := Benchmark.run(state, trailer, variant, str(options["ai"]))
						var row: Dictionary = rows[variant]
						row[result["outcome"]] += 1
						row["failures"] += 0 if result["stable"] else 1
						rejected += 0 if result["stable"] else 1
						row["turns"] += result["turns"]
						row["board_restored"] += 1 if result["board_restored"] else 0
						for role in ["leader", "trailer", "first_leader", "first_trailer"]:
							for key in result[role]: row[role][key] = int(row[role].get(key, 0)) + int(result[role][key])
						var trial := {"pool": pool_id, "scenario": scenario["id"], "trailer_next": trailer_next, "seed": seed_value, "trailer_player": trailer, "variant": variant}
						trial.merge(result)
						report["trials"].append(trial)
				for variant in variants:
					var row: Dictionary = rows[variant]
					row["comeback_rate"] = float(row["comeback"]) / count
					row["mean_turns"] = float(row["turns"]) / count
					report["rows"].append(row)
					print("COMEBACK pool=%s scenario=%s trailer_next=%s rules=%s wins=%d/%d draws=%d failures=%d turns=%.1f" % [pool_id, scenario["id"], trailer_next, variant, row["comeback"], count, row["draw"], row["failures"], row["mean_turns"]])
				report["elapsed_ms"] = Time.get_ticks_msec() - started
				_save(report, str(options["output"]))
	print("COMEBACK_BENCHMARK_DONE games=%d failures=%d elapsed_ms=%d output=%s" % [report["trials"].size(), rejected, Time.get_ticks_msec() - started, options["output"]])
	get_tree().quit(0 if rejected == 0 else 1)


func _save(report: Dictionary, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save comeback report")
		get_tree().quit(1)
		return
	file.store_string(Repro.export_json(report))
