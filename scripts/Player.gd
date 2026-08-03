extends CharacterBody3D
## First-person player controller for the vertical slice.
## Only the owning peer processes input (checked via is_multiplayer_authority()).
## Movement/rotation are replicated via a MultiplayerSynchronizer on Player.tscn.
## Melee attack is a short-lived Area3D hitbox; damage/ignite are applied
## through server-authoritative RPCs so the server stays the source of truth.

const SPEED := 5.0
const JUMP_HEIGHT := 1.2
const MOUSE_SENSITIVITY := 0.0025
const ATTACK_COOLDOWN := 0.6
const ATTACK_IGNITE_STACKS := 1
const ATTACK_DAMAGE := 8.0
const KNOCKBACK_STRENGTH := 8.0
const GRAVITY := 18.0

@export var max_health: float = 100.0
var health: float = 100.0

@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var attack_area: Area3D = $CameraPivot/AttackArea
@onready var attack_shape: CollisionShape3D = $CameraPivot/AttackArea/CollisionShape3D
@onready var weapon_mesh: MeshInstance3D = $CameraPivot/WeaponMesh
@onready var hud: CanvasLayer = null

var autopilot: bool = false
var scripted_move_dir: Vector3 = Vector3.ZERO
var scripted_attack_requested: bool = false

var _attack_cooldown_left: float = 0.0
var _footstep_dist_accum: float = 0.0
var _mouse_captured: bool = false

func _ready() -> void:
	health = max_health
	# The hitbox stays enabled at all times on every peer's copy of this node.
	# It's only ever *queried* (via get_overlapping_bodies) when the server
	# handles a _request_attack RPC, so there's no cost to leaving it live -
	# and critically, the SERVER's own copy needs it enabled to detect hits,
	# since only the server's overlap state is authoritative.
	if is_multiplayer_authority():
		camera.current = true
		if not autopilot:
			_set_mouse_captured.call_deferred()
		var hud_scene := preload("res://scenes/HUD.tscn")
		hud = hud_scene.instantiate()
		get_tree().get_root().add_child.call_deferred(hud)
		hud.bind_player.call_deferred(self)
	else:
		camera.current = false


func _set_mouse_captured() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_multiplayer_authority() and not autopilot:
			_set_mouse_captured()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_mouse_captured = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if not _mouse_captured:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	if event.is_action_pressed("ui_cancel"):
		if hud and hud.has_method("toggle_settings"):
			hud.toggle_settings()
			_mouse_captured = hud.are_settings_open() == false


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = sqrt(2.0 * GRAVITY * JUMP_HEIGHT)

	var direction: Vector3
	if autopilot:
		direction = scripted_move_dir
	else:
		var input_dir := Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
		)
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction.length() > 0.01:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		_footstep_dist_accum += SPEED * delta
		if _footstep_dist_accum > 2.5:
			_footstep_dist_accum = 0.0
			_request_ping.rpc_id(1, global_position, "footstep", 6.0)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left -= delta
		_animate_weapon_swing()
	else:
		_reset_weapon()

	var attack_triggered: bool
	if autopilot:
		attack_triggered = scripted_attack_requested
		scripted_attack_requested = false
	else:
		attack_triggered = Input.is_action_just_pressed("attack")

	if attack_triggered and _attack_cooldown_left <= 0.0:
		_attack_cooldown_left = ATTACK_COOLDOWN
		_do_attack()


func _do_attack() -> void:
	_request_attack.rpc_id(1)


func _animate_weapon_swing() -> void:
	if not weapon_mesh:
		return
	var progress: float = 1.0 - (_attack_cooldown_left / ATTACK_COOLDOWN)
	var angle: float = sin(progress * PI) * deg_to_rad(-45.0)
	weapon_mesh.rotation_degrees = Vector3(angle, 0.0, 0.0)


func _reset_weapon() -> void:
	if weapon_mesh:
		weapon_mesh.rotation_degrees = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func _request_attack() -> void:
	if not multiplayer.is_server():
		return
	Radar.emit_ping(global_position, "swing", 5.0)
	for body in attack_area.get_overlapping_bodies():
		if body == self:
			continue
		if body.has_method("take_damage"):
			body.take_damage(ATTACK_DAMAGE)
		if body.has_method("apply_knockback"):
			var kb_dir: Vector3 = body.global_position - global_position
			kb_dir.y = 0.0
			if kb_dir.length() > 0.01:
				kb_dir = kb_dir.normalized()
			else:
				kb_dir = -global_transform.basis.z
			body.apply_knockback(kb_dir, KNOCKBACK_STRENGTH)
		var ignite_status = body.get_node_or_null("IgniteStatus")
		if ignite_status and ignite_status is IgniteStatus:
			ignite_status.apply_stacks(ATTACK_IGNITE_STACKS)


@rpc("any_peer", "call_local", "reliable")
func _request_ping(pos: Vector3, tag: String, strength: float) -> void:
	if multiplayer.is_server():
		Radar.emit_ping(pos, tag, strength)


func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	health = max(0.0, health - amount)
	_sync_health.rpc(health)
	if health <= 0.0:
		_on_death.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	health = new_health
	if hud:
		hud.update_health(health, max_health)


@rpc("authority", "call_local", "reliable")
func _on_death() -> void:
	# MVP: just freeze the player and let others keep going. Respawn/retry
	# logic is an easy next step once the loop feels right.
	set_physics_process(false)
	if hud:
		hud.show_death()
