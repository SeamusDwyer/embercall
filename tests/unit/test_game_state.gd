extends GutTest

func test_snapshot_has_expected_keys() -> void:
	var snap := GameState.get_snapshot()
	assert_true(snap.has("run"), "snapshot should have 'run' key")
	assert_true(snap.has("arena"), "snapshot should have 'arena' key")
	assert_true(snap.has("players"), "snapshot should have 'players' key")
	assert_true(snap.has("enemies"), "snapshot should have 'enemies' key")
	assert_true(snap.has("net"), "snapshot should have 'net' key")
	assert_true(snap.has("radar"), "snapshot should have 'radar' key")


func test_vec3_dict_roundtrip() -> void:
	var original := Vector3(1.5, -2.0, 3.25)
	var d := GameState._vec3_to_dict(original)
	assert_eq(d["x"], 1.5)
	assert_eq(d["y"], -2.0)
	assert_eq(d["z"], 3.25)
	var back := GameState.dict_to_vec3(d)
	assert_eq(back, original, "roundtrip should preserve vector")


func test_snapshot_net_has_host_id() -> void:
	var snap := GameState.get_snapshot()
	var net: Dictionary = snap["net"]
	assert_true(net.has("host_id"))
	assert_true(net.has("peer_count"))


func test_snapshot_run_has_expected_fields() -> void:
	var snap := GameState.get_snapshot()
	var run: Dictionary = snap["run"]
	assert_true(run.has("act"))
	assert_true(run.has("floor"))
	assert_true(run.has("room_id"))
	assert_true(run.has("room_type"))
	assert_true(run.has("run_complete"))


func test_enemy_dead_with_no_enemies() -> void:
	assert_false(GameState.are_all_enemies_dead(), "should be false when no enemies exist")


func test_get_available_choices_initially_empty() -> void:
	var choices := GameState.get_available_choices()
	assert_eq(choices.size(), 0, "no choices before run starts")


func test_is_run_started_initially_false() -> void:
	assert_false(GameState.is_run_started(), "run should not be started initially")


func test_signals_exist() -> void:
	assert_true(GameState.has_signal("player_spawned"))
	assert_true(GameState.has_signal("player_health_changed"))
	assert_true(GameState.has_signal("player_died"))
	assert_true(GameState.has_signal("enemy_spawned"))
	assert_true(GameState.has_signal("enemy_health_changed"))
	assert_true(GameState.has_signal("enemy_died"))
	assert_true(GameState.has_signal("room_cleared"))
	assert_true(GameState.has_signal("room_selected"))
	assert_true(GameState.has_signal("room_choices_available"))
	assert_true(GameState.has_signal("act_changed"))
	assert_true(GameState.has_signal("run_started"))
	assert_true(GameState.has_signal("run_complete"))
	assert_true(GameState.has_signal("ignite_applied"))
	assert_true(GameState.has_signal("ignite_extinguished"))
	assert_true(GameState.has_signal("ping_emitted"))
	assert_true(GameState.has_signal("exit_unlocked"))
	assert_true(GameState.has_signal("exit_triggered"))


func test_command_select_room_rejects_invalid() -> void:
	# Should not crash when called without a run started
	GameState.command_select_room("nonexistent")
	pass_test("command_select_room should not crash with invalid room id")


func test_get_all_players_returns_array() -> void:
	var players := GameState.get_all_players()
	assert_eq(players.size(), 0, "no players should exist in unit test context")


func test_get_all_enemies_returns_array() -> void:
	var enemies := GameState.get_all_enemies()
	assert_eq(enemies.size(), 0, "no enemies should exist in unit test context")


func test_get_player_returns_empty_for_missing() -> void:
	var p := GameState.get_player(999)
	assert_eq(p, {}, "missing player should return empty dict")


func test_get_enemy_returns_empty_for_missing() -> void:
	var e := GameState.get_enemy("nonexistent")
	assert_eq(e, {}, "missing enemy should return empty dict")
