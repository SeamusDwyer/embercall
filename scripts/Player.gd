extends CharacterBody3D

@export var max_health: float = 100.0
var health: float = 100.0

@export_category("Movement")
@export var sprint_multiplier: float = 1.6
@export var sprint_fov_boost: float = 6.0

@export_category("Weapon")
@export var weapon_pivot_path: NodePath = ^"CameraPivot/WeaponPivot"
@export var swings: Array[NodePath] = [
	^"CameraPivot/Swings/Swing1",
	^"CameraPivot/Swings/Swing2",
	^"CameraPivot/Swings/Swing3",
]
@export var swing_cooldown: float = 0.35
@export var swing_amplitude: float = 1.0
@export var swing_frequency: float = 4.0
@export var swing_bounce: float = 0.6
@export var anticipation_time: float = 0.12
@export var strike_time: float = 0.10
@export var hold_time: float = 0.06
@export var show_ghosts: bool = false:
	set(value):
		show_ghosts = value
		_update_ghost_visibility()

@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var hud: CanvasLayer = null

var autopilot: bool = false
var scripted_move_dir: Vector3 = Vector3.ZERO
var scripted_attack_requested: bool = false
var scripted_sprint: bool = false

var _movement: PlayerMovement
var _camera: PlayerCamera
var _combat: PlayerCombat
var _health: PlayerHealth
var _swings: Array[Node3D] = []
var _sprinting: bool = false


func _ready() -> void:
	health = max_health

	_movement = PlayerMovement.new()
	add_child(_movement)
	_movement.setup(self, sprint_multiplier)

	_camera = PlayerCamera.new()
	add_child(_camera)
	_camera.setup(self, camera_pivot, camera, sprint_fov_boost)

	_resolve_swings()
	_update_ghost_visibility()

	_combat = PlayerCombat.new()
	add_child(_combat)
	var pivot_node := get_node_or_null(weapon_pivot_path) as Node3D
	_combat.setup(self, $CameraPivot/AttackArea, pivot_node, _swings)

	_health = PlayerHealth.new()
	add_child(_health)
	_health.setup(self)

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
		_movement.init_remote_sync()


func _set_mouse_captured() -> void:
	_camera.capture()


func _resolve_swings() -> void:
	_swings.clear()
	for path in swings:
		var node := get_node_or_null(path) as Node3D
		if node:
			_swings.append(node)


func _update_ghost_visibility() -> void:
	for swing in _swings:
		if is_instance_valid(swing):
			swing.visible = show_ghosts


func _notification(what: int) -> void:
	if _camera and is_instance_valid(_camera) and _camera.has_method("handle_notification"):
		_camera.handle_notification(what, autopilot)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not _camera.is_captured():
		return
	_camera.handle_input(event, hud)


func _physics_process(delta: float) -> void:
	var is_auth := is_multiplayer_authority()

	_sprinting = is_auth and (scripted_sprint if autopilot else Input.is_action_pressed("sprint"))
	_movement.apply_physics(delta, is_auth, autopilot, scripted_move_dir, _sprinting)
	_combat.process(delta)

	if not is_auth:
		return

	if autopilot:
		if scripted_attack_requested:
			_combat.attack_requested = true
			scripted_attack_requested = false
	else:
		_combat.attack_requested = Input.is_action_just_pressed("attack")

	if _combat.attack_requested and _combat.cooldown_left <= 0.0:
		_combat.trigger_attack()


func _process(delta: float) -> void:
	_combat.process_visual(delta)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	_camera.process(delta, _sprinting and moving)


# -- RPCs (must live on authority node) --

@rpc("any_peer", "call_local", "reliable")
func _request_attack() -> void:
	if not multiplayer.is_server():
		return
	_combat.resolve_hits()


@rpc("any_peer", "call_local", "reliable")
func _spawn_hit_impact(pos: Vector3) -> void:
	HitImpact.spawn(self, pos, Color(1.0, 0.8, 0.1, 0.8))


@rpc("any_peer", "call_local", "reliable")
func _request_ping(pos: Vector3, tag: String, strength: float) -> void:
	if multiplayer.is_server():
		Radar.emit_ping(pos, tag, strength)


func take_damage(amount: float, reason: String = DamageLog.REASON_UNKNOWN, source: Node = null) -> void:
	_health.take_damage(amount, reason, source)


@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: float, reason: String = "", source_name: String = "", amount: float = 0.0) -> void:
	_health.sync_hp(new_health, hud, reason, source_name, amount)


@rpc("any_peer", "call_local", "reliable")
func _on_death() -> void:
	_health.die(hud)
