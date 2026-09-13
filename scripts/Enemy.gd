extends CharacterBody3D
class_name Enemy
## Thin wrapper. Delegates to EnemyMovement, EnemyCombat, EnemyHealth.
## Supports static encounter configuration (hp, speed, scale, color, name).

@export var max_health: float = 40.0
@export var health: float = 40.0
@export var move_speed: float = 3.0
@export var encounter_name: String = "Enemy"
@export var base_color: Color = Color(0.55, 0.1, 0.15)

@export_category("Weapon")
@export var attack_range: float = 1.6
@export var attack_phase: int = 0
@export var swing_amplitude: float = 1.0
@export var swing_frequency: float = 5.0
@export var swing_bounce: float = 0.5
@export var show_ghosts: bool = false:
	set(value):
		show_ghosts = value
		_update_ghost_visibility()

@onready var ignite: IgniteStatus = $IgniteStatus
@onready var mesh: Node3D = $robot1
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var health_bar: HealthBar3D = $HealthBar

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
	_refresh_health_bar()
	_update_ghost_visibility()


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
	_refresh_health_bar()


func _apply_base_color() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	_apply_material_override(mat)


## Apply a material to the enemy's visible mesh. The model may be a single
## MeshInstance3D or a Node3D containing several, so tint every one.
func _apply_material_override(mat: StandardMaterial3D) -> void:
	if not is_instance_valid(mesh):
		return
	if mesh is MeshInstance3D:
		mesh.material_override = mat
		return
	for m in _find_meshes(mesh):
		m.material_override = mat


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for c in node.get_children():
		if c is MeshInstance3D:
			result.append(c)
		result.append_array(_find_meshes(c))
	return result


func _refresh_health_bar() -> void:
	if health_bar and is_instance_valid(health_bar):
		health_bar.set_health(health, max_health)


func _process(_delta: float) -> void:
	if not mesh or not is_instance_valid(mesh):
		return
	if ignite.is_burning:
		_on_ignited()
	else:
		_on_extinguished()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and not _dead:
		var target := _movement.apply_physics(delta)
		if target:
			_combat.process_attack(delta, target)
	_combat.process_animation(delta)


func _update_ghost_visibility() -> void:
	var swings := get_node_or_null("Swings") as Node3D
	if swings and is_instance_valid(swings):
		swings.visible = show_ghosts


func take_damage(amount: float, _reason: String = "", _source: Node = null) -> void:
	if _dead:
		return
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
	if not is_instance_valid(mesh):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 1.5
	_apply_material_override(mat)


@rpc("authority", "call_local", "reliable")
func _flash_attack() -> void:
	if not is_instance_valid(mesh):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.05)
	mat.emission_energy_multiplier = 4.0
	_apply_material_override(mat)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self) and is_instance_valid(mesh):
		_apply_base_color()


@rpc("authority", "call_local", "reliable")
func _spawn_hit_impact(pos: Vector3) -> void:
	HitImpact.spawn(self, pos, Color(1.0, 0.2, 0.1, 0.8))


func _on_ignited() -> void:
	if not is_instance_valid(mesh):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 2.0
	_apply_material_override(mat)


func _on_extinguished() -> void:
	_apply_base_color()
