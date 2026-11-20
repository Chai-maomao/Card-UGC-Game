extends Node

const Position = preload("res://BattlePosition.gd")
const Simulator = preload("res://HeadlessBattleSimulator.gd")
var samples: Array = []
var options := {"games": "64", "seed": "20261005", "pool": "beginner", "ai": "hard", "min_round": "4", "samples_per_game": "4", "max_rounds": "60", "continuation_turns": "100", "output": "res://artifacts/natural-20261005", "input": ""}


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2: options[parts[0]] = parts[1]
	if str(options.ai) not in BattleAiPlanner.DIFFICULTIES:
		_fail("Unknown AI difficulty")
		return
	var output := str(options.output)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		_fail("Cannot create output directory")
		return
	var started := Time.get_ticks_msec()
	var report := {"version": 1, "origin": "natural_simulation", "ai": options.ai, "seed": int(options.seed), "source_sha256": Position.source_manifest(), "sampling": {"minimum_round": int(options.min_round), "maximum_per_game": int(options.samples_per_game), "phase": "turn_start_after_draw", "selection": "first eligible positions, at least one living unit; balanced positions included"}, "source_games": [], "positions": [], "failures": 0}
	if not str(options.input).is_empty():
		var loaded := Position.read(FileAccess.get_file_as_string(str(options.input)))
		if not loaded.ok:
			_fail("Invalid input position: " + str(loaded.get("reason", "unknown")))
			return
		# Fold any verified history into the actual loaded position. The chosen AI
		# may differ from the source AI, so the old final result is not an oracle.
		var source_metadata: Variant = loaded.record.get("metadata", {})
		var metadata: Dictionary = source_metadata.duplicate(true) if source_metadata is Dictionary else {}
		metadata.erase("observed_final_hash")
		metadata.erase("observed_winner")
		metadata["origin"] = "imported_position"
		metadata["imported_final_hash"] = BattleRepro.state_hash(loaded.game)
		samples = [Position.capture(loaded.game, metadata)]
		report.origin = "imported_position"
		report.sampling = {"selection": "explicit input file", "path": options.input}
		_process_samples(output, report)
	else:
		var deck: Array
		match str(options.pool):
			"beginner": deck = CardDatabase.beginner_deck()
			"vanilla": deck = ComebackBenchmark.vanilla_pool()
			"ugc-v1":
				deck = UgcBenchmarkPool.deck()
				report["pool_manifest"] = UgcBenchmarkPool.manifest()
				report.source_sha256["UgcBenchmarkPool.gd"] = FileAccess.get_sha256("res://UgcBenchmarkPool.gd")
			"local": deck = PlayerData.get_cards_for_deck(PlayerData.current_deck_id)
			_:
				_fail("Unknown pool")
				return
		if deck.is_empty():
			_fail("Empty pool")
			return
		var game_count := clampi(int(options.games), 1, 256)
		for index in range(game_count):
			samples.clear()
			var seed_value := int(options.seed) + index
			var metadata := {"origin": "natural_simulation", "phase": "turn_start_after_draw", "seed": seed_value, "game_index": index, "pool": options.pool, "ai": options.ai}
			if report.has("pool_manifest"):
				metadata["pool_sha256"] = report.pool_manifest.sha256
			var observer := func(game):
				if game.turn_number >= int(options.min_round) and samples.size() < clampi(int(options.samples_per_game), 1, 16) and game.player_field.get_alive_count() + game.player2_field.get_alive_count() > 0:
					samples.append(Position.capture(game, metadata))
			var source := Simulator.run_game(deck, deck, seed_value, str(options.ai), str(options.ai), clampi(int(options.max_rounds), 4, 200), PlayerData.DEFAULT_BATTLE_CONFIG, observer)
			report.source_games.append({"seed": seed_value, "winner": source.winner, "stable": source.stable, "capped": source.winner == "draw", "rounds": source.rounds, "sample_count": samples.size(), "final_hash": source.final_hash, "metrics_version": source.metrics_version, "cards_by_identity": source.cards_by_identity, "identity_names": source.identity_names})
			if not source.stable: report.failures += 1
			for record in samples:
				record.metadata["observed_winner"] = source.winner
				record.metadata["observed_final_hash"] = source.final_hash
			_process_samples(output, report)
			_save_index(output, report, started)
			print("NATURAL_PROGRESS game=%d/%d positions=%d failures=%d" % [index + 1, game_count, report.positions.size(), report.failures])
	_save_index(output, report, started)
	print("NATURAL_POSITIONS_DONE positions=%d failures=%d elapsed_ms=%d output=%s" % [report.positions.size(), report.failures, Time.get_ticks_msec() - started, output])
	get_tree().quit(0 if report.failures == 0 else 1)


func _process_samples(output: String, report: Dictionary) -> void:
	for record: Dictionary in samples:
		var sample_id := "position-%04d" % report.positions.size()
		var row := {"id": sample_id, "file": sample_id + ".json", "metadata": record.metadata, "position": record.position, "initial_hash": record.state_hashes[0], "variants": {}}
		if Position.save(record, output.path_join(row.file)) != OK:
			report.failures += 1
			continue
		for variant in ["saved", "legacy"]:
			var branch: Dictionary = record.duplicate(true)
			if variant == "legacy":
				for key in ComebackBenchmark.AP_KEYS: branch.initial_state.battle_config.erase(key)
				branch.state_hashes = [BattleRepro.hash_state(branch.initial_state)]
			branch.actions = []
			branch.metadata["rule_variant"] = variant
			var continued := Position.continue_record(branch, str(options.ai), clampi(int(options.continuation_turns), 1, 200))
			if not continued.ok:
				report.failures += 1
				row.variants[variant] = {"stable": false, "failure": continued.get("reason", "unknown")}
				continue
			var filename: String = sample_id + "-" + variant + ".json"
			var saved := Position.save(continued.record, output.path_join(filename))
			var replay := Position.read(FileAccess.get_file_as_string(output.path_join(filename))) if saved == OK else {"ok": false}
			var verified: bool = replay.ok and BattleRepro.state_hash(replay.game) == continued.final_hash
			var matches_source: Variant = null
			if variant == "saved" and record.metadata.has("observed_final_hash") and not continued.capped:
				matches_source = continued.final_hash == record.metadata.observed_final_hash
			if not continued.stable or not verified or matches_source == false: report.failures += 1
			row.variants[variant] = {"file": filename, "winner": continued.winner, "turns": continued.turns, "capped": continued.capped, "stable": continued.stable, "verified": verified, "matches_source": matches_source, "final_hash": continued.final_hash}
		report.positions.append(row)


func _save_index(output: String, report: Dictionary, started: int) -> void:
	report["elapsed_ms"] = Time.get_ticks_msec() - started
	var file := FileAccess.open(output.path_join("index.json"), FileAccess.WRITE)
	if file == null:
		report.failures += 1
		return
	file.store_string(BattleRepro.export_json(report))


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
