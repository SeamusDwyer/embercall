extends Node
## Scripted bot for headless CI. Clears the current room, then walks through an
## open exit door. Reports PASS once a room transition happens.

var player: CharacterBody3D
var world: Node3D

var _start_room: String = ""
var _timer: float = 0.0
var _result_reported: bool = false
var _last_attack_time: float = 0.0
var _wp_idx: int = 0


func setup(p: CharacterBody3D, w: Node3D) -> void:
	player = p
	world = w
	_start_room = RoomManager.current_room_id


func _physics_process(delta: float) -> void:
	if _result_reported or player == null or world == null:
		return

	_timer += delta
	if _timer > 45.0:
		_report("FAIL: timeout after 45s")
		return

	if RoomManager.current_room_id != _start_room:
		_report("PASS")
		return

	var room: Room = world.get_current_room()
	if room == null:
		return

	var enemy: Enemy = room.get_enemy()
	if enemy != null and is_instance_valid(enemy):
		_chase_and_attack(enemy.global_position)
		return

	if room.is_exit_unlocked():
		_walk_exit(room)


func _walk_exit(room: Room) -> void:
	var gate_pos: Vector3 = room.get_primary_exit_position()

	# Phase 1 — inside the room: line up laterally, then walk through the gate.
	if player.global_position.z > gate_pos.z - 0.5:
		_wp_idx = 0
		if absf(player.global_position.x - gate_pos.x) > 0.3:
			_move_to(Vector3(gate_pos.x, 0, player.global_position.z))
		else:
			_move_to(Vector3(gate_pos.x, 0, gate_pos.z - 2.0))
		return

	# Phase 2 — past the gate: follow the L-shaped corridor to the target.
	if room.children_ids.is_empty():
		return
	var child_center: Vector3 = world.get_room_center(room.children_ids[0])
	var entry_pos := child_center + Vector3(0, 0, 10.0)
	var mid_z := (gate_pos.z + entry_pos.z) / 2.0
	var waypoints := [
		Vector3(gate_pos.x, 0, mid_z),
		Vector3(entry_pos.x, 0, mid_z),
		entry_pos,
		child_center,
	]
	while _wp_idx < waypoints.size() and _flat_distance(player.global_position, waypoints[_wp_idx]) <= 1.0:
		_wp_idx += 1
	if _wp_idx >= waypoints.size():
		_move_to(child_center)
		return
	_move_to(waypoints[_wp_idx])


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _chase_and_attack(target: Vector3) -> void:
	var to_target := target - player.global_position
	to_target.y = 0
	var dist := to_target.length()
	if dist < 1.8:
		player.scripted_move_dir = Vector3.ZERO
		if _timer - _last_attack_time > 0.7:
			player.scripted_attack_requested = true
			_last_attack_time = _timer
	elif dist > 0.1:
		player.scripted_move_dir = to_target.normalized()
	_look_at(target)


func _move_to(target: Vector3) -> void:
	var to_target := target - player.global_position
	to_target.y = 0
	if to_target.length() > 0.2:
		player.scripted_move_dir = to_target.normalized()
	else:
		player.scripted_move_dir = Vector3.ZERO
	_look_at(target)


func _look_at(target: Vector3) -> void:
	var flat := Vector3(target.x, player.global_position.y, target.z)
	if player.global_position.distance_to(flat) > 0.1:
		player.look_at(flat, Vector3.UP)


func notify_exit_fired() -> void:
	pass


func _report(result: String) -> void:
	if _result_reported:
		return
	_result_reported = true
	print("TEST_RESULT: %s" % result)
	get_tree().quit(0 if result.begins_with("PASS") else 1)
