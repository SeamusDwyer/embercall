extends CharacterBody3D
## First-person player controller for the vertical slice.
## Only the owning peer processes input (checked via is_multiplayer_authority()).
## Movement/rotation are replicated via a MultiplayerSynchronizer on Player.tscn.
## Melee attack is a short-lived Area3D hitbox; damage/ignite are applied
## through server-authoritative RPCs so the server stays the source of truth.

const SPEED := 5.0
const JUMP_VELOCITY := 6.0
const MOUSE_SENSITIVITY := 0.0025
const ATTACK_COOLDOWN := 0.6
const ATTACK_IGNITE_STACKS := 1 # this weapon always applies Ignite; swap for archetype variety later

@export var max_health: float = 100.0
var health: float = 100.0

@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var attack_area: Area3D = $CameraPivot/AttackArea
@onready var attack_shape: CollisionShape3D = $CameraPivot/AttackArea/CollisionShape3D
@onready var hud: CanvasLayer = null # assigned at runtime for the local player only

var _attack_cooldown_left: float = 0.0
var _footstep_dist_accum: float = 0.0

func _ready() -> void:
	health = max_health
	# The hitbox stays enabled at all times on every peer's copy of this node.
	# It's only ever *queried* (via get_overlapping_bodies) when the server
	# handles a _request_attack RPC, so there's no cost to leaving it live -
	# and critically, the SERVER's own copy needs it enabled to detect hits,
	# since only the server's overlap state is authoritative.
	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var hud_scene := preload("res://scenes/HUD.tscn")
		hud = hud_scene.instantiate()
		get_tree().get_root().add_child(hud)
		hud.bind_player(self)
	else:
		camera.current = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
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

	if Input.is_action_just_pressed("attack") and _attack_cooldown_left <= 0.0:
		_attack_cooldown_left = ATTACK_COOLDOWN
		_do_attack()


func _do_attack() -> void:
	# Client-side: trigger swing animation/VFX here once you have art.
	# Server resolves who actually got hit via the RPC below.
	_request_attack.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _request_attack() -> void:
	if not multiplayer.is_server():
		return
	Radar.emit_ping(global_position, "swing", 5.0)
	for body in attack_area.get_overlapping_bodies():
		if body == self:
			continue
		if body.has_method("take_damage"):
			body.take_damage(8.0)
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
