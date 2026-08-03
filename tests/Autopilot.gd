extends Node

var player: CharacterBody3D
var arena: Node3D

var _timer: float = 0.0
var _result_reported: bool = false
var _last_attack_time: float = 0.0

func setup(p: CharacterBody3D, a: Node3D) -> void:
	player = p
	arena = a


func _physics_process(delta: float) -> void:
	if _result_reported or player == null or arena == null:
		return

	_timer += delta
	if _timer > 30.0:
		_report("FAIL: timeout after 30s")
		return

	var enemy: Node3D = arena.get_enemy()
	var enemy_dead: bool = arena.is_enemy_dead()
	var exit_unlocked: bool = arena.is_exit_unlocked()

	var target_pos: Vector3
	if enemy_dead and exit_unlocked:
		target_pos = arena.exit_zone.global_position
		if player.global_position.distance_to(target_pos) < 2.0:
			_report("PASS")
			return
	elif enemy and is_instance_valid(enemy):
		target_pos = enemy.global_position
	else:
		return

	var player_pos := player.global_position
	var to_target := target_pos - player_pos
	to_target.y = 0
	var dist := to_target.length()

	if dist < 1.8 and not enemy_dead:
		player.scripted_move_dir = Vector3.ZERO
		if _timer - _last_attack_time > 0.7:
			player.scripted_attack_requested = true
			_last_attack_time = _timer
	elif dist > 0.1:
		player.scripted_move_dir = to_target.normalized()

	player.look_at(Vector3(target_pos.x, player_pos.y, target_pos.z), Vector3.UP)


func _report(result: String) -> void:
	if _result_reported:
		return
	_result_reported = true
	print("TEST_RESULT: %s" % result)
	get_tree().quit(0 if result.begins_with("PASS") else 1)
