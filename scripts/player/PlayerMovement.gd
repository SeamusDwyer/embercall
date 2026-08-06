extends Node
class_name PlayerMovement
## Movement for authority peers + interpolation for remote peers.

var player: CharacterBody3D

const SPEED := 5.0
const JUMP_HEIGHT := 1.2
const GRAVITY := 18.0
const FOOTSTEP_INTERVAL := 2.5
const INTERP_SPEED := 20.0
const SNAP_DISTANCE := 2.0

var _footstep_accum: float = 0.0
var _interp_from: Vector3 = Vector3.ZERO
var _interp_to: Vector3 = Vector3.ZERO
var _interp_progress: float = 0.0
var _has_received_sync: bool = false


func setup(p: CharacterBody3D) -> void:
	player = p


func init_remote_sync() -> void:
	var sync := player.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.synchronized.connect(_on_sync_received)


func apply_physics(delta: float, is_authority: bool, autopilot: bool, move_dir: Vector3) -> void:
	if not is_authority:
		_apply_remote(delta)
		return

	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		player.velocity.y = sqrt(2.0 * GRAVITY * JUMP_HEIGHT)

	var direction: Vector3
	if autopilot:
		direction = move_dir
	else:
		var input_dir := Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
		)
		direction = (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction.length() > 0.01:
		player.velocity.x = direction.x * SPEED
		player.velocity.z = direction.z * SPEED
		_footstep_accum += SPEED * delta
		if _footstep_accum > FOOTSTEP_INTERVAL:
			_footstep_accum = 0.0
			player.rpc_id(1, &"_request_ping", player.global_position, "footstep", 6.0)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, SPEED)
		player.velocity.z = move_toward(player.velocity.z, 0, SPEED)

	player.move_and_slide()


func _apply_remote(delta: float) -> void:
	if _interp_progress < 1.0 and _has_received_sync:
		_interp_progress = min(_interp_progress + delta * INTERP_SPEED, 1.0)
		player.global_position = _interp_from.lerp(_interp_to, _interp_progress)
	player.move_and_slide()


func _on_sync_received() -> void:
	if not _has_received_sync:
		_interp_from = player.global_position
		_interp_to = player.global_position
		_has_received_sync = true
		return
	var target: Vector3 = player.global_position
	var error: float = target.distance_to(_interp_to)
	if error > SNAP_DISTANCE:
		_interp_from = target
		_interp_to = target
		_interp_progress = 1.0
	else:
		_interp_from = _interp_from.lerp(_interp_to, _interp_progress)
		_interp_to = target
		_interp_progress = 0.0
