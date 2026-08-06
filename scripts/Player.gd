extends CharacterBody3D

@export var max_health: float = 100.0
var health: float = 100.0

@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var hud: CanvasLayer = null

var autopilot: bool = false
var scripted_move_dir: Vector3 = Vector3.ZERO
var scripted_attack_requested: bool = false

var _movement: PlayerMovement
var _camera: PlayerCamera
var _combat: PlayerCombat
var _health: PlayerHealth


func _ready() -> void:
	health = max_health

	_movement = PlayerMovement.new()
	add_child(_movement)
	_movement.setup(self)

	_camera = PlayerCamera.new()
	add_child(_camera)
	_camera.setup(self, camera_pivot, camera)

	_combat = PlayerCombat.new()
	add_child(_combat)
	_combat.setup(self, $CameraPivot/AttackArea, $CameraPivot/WeaponPivot)

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


func _notification(what: int) -> void:
	if _camera:
		_camera.handle_notification(what, autopilot)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not _camera.is_captured():
		return
	_camera.handle_input(event, hud)


func _physics_process(delta: float) -> void:
	var is_auth := is_multiplayer_authority()

	_movement.apply_physics(delta, is_auth, autopilot, scripted_move_dir)
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


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	_health.sync_hp(new_health, hud)


@rpc("any_peer", "call_local", "reliable")
func _on_death() -> void:
	_health.die(hud)
