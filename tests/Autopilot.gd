extends Node

var player: CharacterBody3D
var arena: Node3D

var _timer: float = 0.0
var _result_reported: bool = false
var _last_attack_time: float = 0.0
var _in_airlock: bool = false

func setup(p: CharacterBody3D, a: Node3D) -> void:
	player = p
	arena = a


func _physics_process(delta: float) -> void:
	if _result_reported or player == null or arena == null:
		return

	_timer += delta
	if _timer > 45.0:
		_report("FAIL: timeout after 45s")
		return

	var enemy_dead: bool = arena.is_enemy_dead()
	var exit_unlocked: bool = arena.is_exit_unlocked()

	var target_pos: Vector3

	if exit_unlocked:
		# Walk all the way into the airlock to trigger body_entered
		target_pos = arena.get_airlock_position()
		if player.global_position.distance_to(target_pos) < 0.5:
			player.scripted_move_dir = Vector3.ZERO
			if not _in_airlock:
				_in_airlock = true
				print("[Autopilot] Reached airlock — waiting for exit_triggered")
			if _check_exit_fired():
				_report("PASS")
			return
		else:
			_in_airlock = false
	elif arena.get_enemy() != null:
		var enemy: Node3D = arena.get_enemy()
		if is_instance_valid(enemy):
			target_pos = enemy.global_position
		else:
			return
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

	if target_pos != Vector3.ZERO:
		player.look_at(Vector3(target_pos.x, player_pos.y, target_pos.z), Vector3.UP)


var _exit_fired := false

func notify_exit_fired() -> void:
	_exit_fired = true

func _check_exit_fired() -> bool:
	return _exit_fired


func _report(result: String) -> void:
	if _result_reported:
		return
	_result_reported = true
	print("TEST_RESULT: %s" % result)
	get_tree().quit(0 if result.begins_with("PASS") else 1)
