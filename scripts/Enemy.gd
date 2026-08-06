extends CharacterBody3D
class_name Enemy
## Thin wrapper. Delegates to EnemyMovement, EnemyCombat, EnemyHealth.
## Supports static encounter configuration (hp, speed, scale, color, name).

@export var max_health: float = 40.0
@export var health: float = 40.0
@export var move_speed: float = 3.0
@export var encounter_name: String = "Enemy"
@export var base_color: Color = Color(0.55, 0.1, 0.15)

@onready var ignite: IgniteStatus = $IgniteStatus
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh

var _movement: EnemyMovement
var _combat: EnemyCombat
var _health: EnemyHealth
var _dead: bool = false

signal died


func _ready() -> void:
	health = max_health

	_movement = EnemyMovement.new()
	add_child(_movement)
	_movement.setup(self)

	_combat = EnemyCombat.new()
	add_child(_combat)
	_combat.setup(self)

	_health = EnemyHealth.new()
	add_child(_health)
	_health.setup(self)

	ignite.ignited.connect(_on_ignited)
	ignite.extinguished.connect(_on_extinguished)
	set_process(true)
	_apply_base_color()


func configure_enemy(data: Dictionary) -> void:
	if multiplayer.is_server():
		_sync_configure_enemy.rpc(data)
	_apply_enemy_config(data)


@rpc("authority", "call_local", "reliable")
func _sync_configure_enemy(data: Dictionary) -> void:
	_apply_enemy_config(data)


func _apply_enemy_config(data: Dictionary) -> void:
	encounter_name = data.get("name", "Enemy")
	max_health = data.get("hp", 40.0)
	health = max_health
	move_speed = data.get("speed", 3.0)
	if data.has("scale") and data["scale"] is Vector3:
		scale = data["scale"]
	if data.has("color") and data["color"] is Color:
		base_color = data["color"]
	_apply_base_color()


func _apply_base_color() -> void:
	if mesh and is_instance_valid(mesh):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = base_color
		mesh.material_override = mat


func _process(_delta: float) -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	if ignite.is_burning:
		_on_ignited()
	else:
		_on_extinguished()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead:
		return

	var target := _movement.apply_physics(delta)
	if target:
		_combat.process_attack(delta, target)
	_combat.process_animation(delta, weapon_mesh)


func take_damage(amount: float) -> void:
	if _health.take_damage(amount):
		_dead = true
		died.emit()


func apply_knockback(direction: Vector3, strength: float) -> void:
	if not multiplayer.is_server():
		return
	_movement.apply_knockback(direction, strength)


# -- RPCs --

@rpc("authority", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	_health.sync_hp(new_health)


@rpc("authority", "call_local", "reliable")
func _die() -> void:
	_dead = true
	set_physics_process(false)
	_health.apply_death_visuals()


@rpc("authority", "call_local", "reliable")
func _tell_attack() -> void:
	if mesh and is_instance_valid(mesh):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.0)
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat


@rpc("authority", "call_local", "reliable")
func _flash_attack() -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.05)
	mat.emission_energy_multiplier = 4.0
	mesh.material_override = mat
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self) and is_instance_valid(mesh):
		_apply_base_color()


@rpc("authority", "call_local", "reliable")
func _spawn_hit_impact(pos: Vector3) -> void:
	HitImpact.spawn(self, pos, Color(1.0, 0.2, 0.1, 0.8))


func _on_ignited() -> void:
	if mesh and is_instance_valid(mesh):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.0)
		mat.emission_energy_multiplier = 2.0
		mesh.material_override = mat


func _on_extinguished() -> void:
	_apply_base_color()
