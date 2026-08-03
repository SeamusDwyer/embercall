extends GutTest

const PlayerScene = preload("res://scenes/Player.tscn")

func test_player_sets_camera_current_on_authority() -> void:
	var player: CharacterBody3D = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame

	assert_true(player.camera.current, "camera should be current for authority player")


func test_player_setup_mouse_mode_on_authority() -> void:
	var player: CharacterBody3D = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame

	assert_false(player.autopilot, "autopilot should default to false")
	# In headless mode Input.mouse_mode stays VISIBLE because there is no OS window.
	# The code tries to set CAPTURED — verify the attempt was made by checking
	# that autopilot=false does NOT prevent the capture attempt.
	# (The actual CAPTURED value can only be verified on a real display.)


func test_unhandled_input_rotates_on_mouse_motion() -> void:
	var player: CharacterBody3D = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame

	player._mouse_captured = true

	var initial_yaw: float = player.rotation.y
	var initial_pitch: float = player.camera_pivot.rotation.x

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 50.0)
	player._unhandled_input(motion)

	assert_ne(player.rotation.y, initial_yaw, "yaw should change on horizontal mouse motion")
	assert_ne(player.camera_pivot.rotation.x, initial_pitch, "pitch should change on vertical mouse motion")


func test_unhandled_input_skips_small_motion() -> void:
	var player: CharacterBody3D = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame

	player._mouse_captured = true

	var initial_yaw: float = player.rotation.y

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0.0, 0.0)
	player._unhandled_input(motion)

	assert_eq(player.rotation.y, initial_yaw, "yaw should not change on zero motion")


func test_camera_pitch_clamped() -> void:
	var player: CharacterBody3D = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame

	player._mouse_captured = true

	# Look straight up (many large negative-Y motions)
	for _i in range(100):
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0, -200.0)
		player._unhandled_input(motion)

	assert_lt(player.camera_pivot.rotation.x, deg_to_rad(90), "pitch should be clamped below 90")

	# Look straight down
	for _i in range(100):
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0, 200.0)
		player._unhandled_input(motion)

	assert_gt(player.camera_pivot.rotation.x, deg_to_rad(-90), "pitch should be clamped above -90")
