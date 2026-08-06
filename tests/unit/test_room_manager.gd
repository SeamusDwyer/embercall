extends "res://addons/gut/test.gd"

func before_each() -> void:
	RoomManager.start_run()


func test_act_generation_count() -> void:
	assert_eq(RoomManager.acts.size(), 3, "Should generate 3 acts")


func test_floors_per_act() -> void:
	for act in RoomManager.acts:
		var floors: Array = act.get("floors", [])
		assert_eq(floors.size(), RoomManager.FLOORS_PER_ACT, "Each act should have 8 floors")


func test_fixed_floor_room_types() -> void:
	var act: Dictionary = RoomManager.get_act_data()
	var floors: Array = act.get("floors", [])
	
	# Floor 0: COMBAT
	assert_eq(floors[0].size(), 1)
	assert_eq(floors[0][0]["type"], RoomManager.RoomType.COMBAT)
	
	# Floor 6: BOSS
	assert_eq(floors[6].size(), 1)
	assert_eq(floors[6][0]["type"], RoomManager.RoomType.BOSS)
	
	# Floor 7: CHEST
	assert_eq(floors[7].size(), 1)
	assert_eq(floors[7][0]["type"], RoomManager.RoomType.CHEST)


func test_choice_floors_room_count() -> void:
	var act: Dictionary = RoomManager.get_act_data()
	var floors: Array = act.get("floors", [])
	for f in range(1, 6):
		var count: int = floors[f].size()
		assert_true(count >= 2 and count <= RoomManager.MAX_ROOMS_PER_FLOOR, "Floor %d room count %d should be 2 or 3" % [f, count])


func test_begin_first_room() -> void:
	var first := RoomManager.begin_first_room()
	assert_eq(RoomManager.current_act, 1)
	assert_eq(RoomManager.current_floor, 0)
	assert_eq(RoomManager.current_room_id, first["id"])


func test_room_completion_and_choices() -> void:
	RoomManager.begin_first_room()
	assert_false(RoomManager.is_room_visited(RoomManager.current_room_id))
	RoomManager.complete_current_room()
	assert_true(RoomManager.is_room_visited(RoomManager.current_room_id))
	
	var choices := RoomManager.get_available_choices()
	assert_true(choices.size() >= 2, "Floor 1 should offer multiple choices")
	
	var chosen_id: String = choices[0]["id"]
	RoomManager.select_room(chosen_id)
	assert_eq(RoomManager.current_room_id, chosen_id)
	assert_eq(RoomManager.current_floor, 1)


func test_enemy_scaling_formulas() -> void:
	# Act 1 Floor 0
	assert_eq(RoomManager.get_enemy_count(1, 0), 1)
	assert_almost_eq(RoomManager.get_enemy_health_multiplier(1, 0), 1.0, 0.01)
	
	# Act 1 Floor 5
	assert_eq(RoomManager.get_enemy_count(1, 5), 3)
	assert_almost_eq(RoomManager.get_enemy_health_multiplier(1, 5), 1.75, 0.01)
	
	# Act 3 Floor 5
	assert_eq(RoomManager.get_enemy_count(3, 5), 6)
	assert_almost_eq(RoomManager.get_enemy_health_multiplier(3, 5), 2.35, 0.01)


func test_act_progression() -> void:
	RoomManager.start_run()
	assert_eq(RoomManager.current_act, 1)
	RoomManager.start_next_act()
	assert_eq(RoomManager.current_act, 2)
	RoomManager.start_next_act()
	assert_eq(RoomManager.current_act, 3)
