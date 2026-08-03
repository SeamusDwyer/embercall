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
const ATTACK_TELL_DURATION := 0.4
const ATTACK_SWING_DURATION := 0.2
const GROWL_INTERVAL := 4.0

@export var max_health: float = 40.0
@export var health: float = 40.0

@onready var ignite: IgniteStatus = $IgniteStatus
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh

var _attack_cooldown_left: float = 0.0
var _growl_timer: float = GROWL_INTERVAL
var _dead: bool = false
var _knockback_velocity: Vector3 = Vector3.ZERO

enum AttackPhase { IDLE, TELL, SWING, RECOVERY }
var _attack_phase: int = AttackPhase.IDLE
var _phase_timer: float = 0.0
var _attack_target: Node3D = null

signal died

func _ready() -> void:
	health = max_health
	ignite.ignited.connect(_on_ignited)
	ignite.extinguished.connect(_on_extinguished)
	set_process(true)


func _process(_delta: float) -> void:
	if not mesh:
		return
	var mat := mesh.get_surface_override_material(0)
	if ignite.is_burning and mat == null:
		_on_ignited()
	elif not ignite.is_burning and mat != null:
		_on_extinguished()

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
		_process_attack(delta, target)

	_process_attack_animation(delta)


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


func _process_attack(delta: float, target: Node3D) -> void:
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left -= delta

	match _attack_phase:
		AttackPhase.IDLE:
			if _attack_cooldown_left <= 0.0:
				_attack_phase = AttackPhase.TELL
				_phase_timer = ATTACK_TELL_DURATION
				_attack_target = target
				_tell_attack.rpc()

		AttackPhase.TELL:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_attack_phase = AttackPhase.SWING
				_phase_timer = ATTACK_SWING_DURATION
				if _attack_target and is_instance_valid(_attack_target) and _attack_target.has_method("take_damage"):
					_attack_target.take_damage(ATTACK_DAMAGE)
				Radar.emit_ping(global_position, "attack", 8.0)
				if _attack_target and is_instance_valid(_attack_target):
					_spawn_hit_impact.rpc(_attack_target.global_position)
				_flash_attack.rpc()
				_attack_cooldown_left = ATTACK_COOLDOWN

		AttackPhase.SWING:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_attack_phase = AttackPhase.RECOVERY

		AttackPhase.RECOVERY:
			if _attack_cooldown_left <= 0.0:
				_attack_phase = AttackPhase.IDLE


func _process_attack_animation(delta: float) -> void:
	match _attack_phase:
		AttackPhase.TELL:
			if weapon_mesh:
				var t: float = 1.0 - (_phase_timer / ATTACK_TELL_DURATION)
				weapon_mesh.position.z = -1.1 + t * 0.5
		AttackPhase.SWING:
			if weapon_mesh:
				var t: float = 1.0 - (_phase_timer / ATTACK_SWING_DURATION)
				var forward: float = -1.1 + 0.5 - (sin(t * PI) * 1.0)
				weapon_mesh.position.z = forward
		AttackPhase.RECOVERY:
			if weapon_mesh:
				weapon_mesh.position.z = lerpf(weapon_mesh.position.z, -1.1, delta * 8.0)
		_:
			if weapon_mesh:
				weapon_mesh.position.z = lerpf(weapon_mesh.position.z, -1.1, delta * 6.0)


@rpc("authority", "call_local", "reliable")
func _tell_attack() -> void:
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.0)
		mat.emission_energy_multiplier = 1.5
		mesh.set_surface_override_material(0, mat)


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


@rpc("authority", "call_local", "reliable")
func _flash_attack() -> void:
	if not mesh:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.05)
	mat.emission_energy_multiplier = 4.0
	mesh.set_surface_override_material(0, mat)
	await get_tree().create_timer(0.15).timeout
	if mesh and mesh.get_surface_override_material(0) == mat:
		mesh.set_surface_override_material(0, null)


@rpc("authority", "call_local", "reliable")
func _spawn_hit_impact(pos: Vector3) -> void:
	if not DebugShapes.show_hit_impacts:
		return
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.1, 0.8)
	marker.set_surface_override_material(0, mat)
	marker.global_position = pos
	marker.name = "HitImpact"
	get_tree().get_root().add_child.call_deferred(marker)
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.parallel().tween_property(marker, "scale", Vector3(0.2, 0.2, 0.2), 0.4)
	tween.tween_callback(marker.queue_free)
