extends CharacterBody3D
class_name Enemy
## Single enemy type for the vertical slice. All logic here runs
## server-side only; position is replicated to clients via a
## MultiplayerSynchronizer on Enemy.tscn. Deliberately simple AI so the
## slice can focus on proving out Ignite + Radar rather than pathfinding.

const SPEED := 3.0
const ATTACK_RANGE := 1.6
const ATTACK_DAMAGE := 10.0
const ATTACK_COOLDOWN := 1.2
const GROWL_INTERVAL := 4.0

@export var max_health: float = 40.0
@export var health: float = 40.0

@onready var ignite: IgniteStatus = $IgniteStatus
@onready var mesh: MeshInstance3D = $MeshInstance3D

var _attack_cooldown_left: float = 0.0
var _growl_timer: float = GROWL_INTERVAL
var _dead: bool = false
var _knockback_velocity: Vector3 = Vector3.ZERO

signal died

func _ready() -> void:
	health = max_health
	ignite.ignited.connect(_on_ignited)
	ignite.extinguished.connect(_on_extinguished)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead:
		return

	if _knockback_velocity.length() > 0.1:
		velocity.x = _knockback_velocity.x
		velocity.z = _knockback_velocity.z
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 15.0 * delta)
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		move_and_slide()
		return

	_growl_timer -= delta
	if _growl_timer <= 0.0:
		_growl_timer = GROWL_INTERVAL
		Radar.emit_ping(global_position, "growl", 14.0)

	var target := _find_nearest_player()
	if target == null:
		return

	var to_target := target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist > ATTACK_RANGE:
		var dir := to_target.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)
		move_and_slide()
	else:
		velocity.x = 0
		velocity.z = 0
		if _attack_cooldown_left <= 0.0:
			_attack_cooldown_left = ATTACK_COOLDOWN
			if target.has_method("take_damage"):
				target.take_damage(ATTACK_DAMAGE)
			Radar.emit_ping(global_position, "attack", 8.0)

	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left -= delta


func _find_nearest_player() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := INF
	for peer_id in Net.players:
		var p = Net.players[peer_id]
		if not is_instance_valid(p):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest


func take_damage(amount: float) -> void:
	if not multiplayer.is_server() or _dead:
		return
	health = max(0.0, health - amount)
	_sync_health.rpc(health)
	if health <= 0.0:
		_dead = true
		died.emit()
		_die.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	health = new_health


@rpc("authority", "call_local", "reliable")
func _die() -> void:
	_dead = true
	set_physics_process(false)
	visible = false
	var col := get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = true


func apply_knockback(direction: Vector3, strength: float) -> void:
	if not multiplayer.is_server():
		return
	_knockback_velocity = direction * strength


func _on_ignited() -> void:
	# Simple MVP feedback: swap to a hot emissive material so burning is
	# readable at a glance. Replace with real VFX/shader once art exists.
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.0)
		mat.emission_energy_multiplier = 2.0
		mesh.set_surface_override_material(0, mat)

func _on_extinguished() -> void:
	if mesh:
		mesh.set_surface_override_material(0, null)
