extends Node3D
## Dynamic arena that reconfigures per room type.
## Encounter-driven: spawns enemies from static RoomManager.ENCOUNTERS data.
## Flow:
##   Entry door locked on entry.
##   All enemies killed → exit door unlocks (turns blue), airlock activates.
##   All players step into the airlock → room cleared → transition fires.
##   Transition locks the entry door so players can't backtrack.

const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const MAP3D_SCENE := preload("res://scripts/Map3D.gd")

# Door materials — baked into constants so headless dummy renderer can handle them
const DOOR_MAT_LOCKED_COLOR  := Color(0.6, 0.1, 0.05)
const DOOR_MAT_LOCKED_EMIT   := Color(0.8, 0.05, 0.0)
const DOOR_MAT_UNLOCKED_COLOR := Color(0.0, 0.4, 0.7)
const DOOR_MAT_UNLOCKED_EMIT  := Color(0.0, 0.5, 1.0)

signal exit_triggered

# Dynamically created nodes (not in the .tscn — built in _ready)
var airlock: Area3D
var airlock_vfx: GPUParticles3D
var exit_door: StaticBody3D
var door_mesh: MeshInstance3D
var door_col: CollisionShape3D

var enemies_root: Node3D
var props_root: Node3D
var player_root: Node3D

var _enemies: Array[Enemy] = []
var _enemies_dead := 0
var _room_cleared := false
var _map_choice_made := false
var _map3d: Node3D
var _players_in_airlock: Dictionary = {}


func _ready() -> void:
	enemies_root = $Enemies
	props_root = $Props
	player_root = $PlayerRoot

	_setup_airlock_and_door()
	_setup_map()

	# Remove the hardcoded enemy from the restored .tscn
	for c in enemies_root.get_children():
		c.queue_free()
	for c in props_root.get_children():
		c.queue_free()

	_set_door_locked(true)
	airlock.monitoring = false
	airlock_vfx.emitting = false
	airlock.body_entered.connect(_on_airlock_entered)
	airlock.body_exited.connect(_on_airlock_exited)
	RoomManager.room_selected.connect(_on_map_choice_made)


func _setup_airlock_and_door() -> void:
	# Repurpose the old ExitZone as the airlock
	var old_exit := get_node_or_null("ExitZone")
	if old_exit:
		old_exit.name = "Airlock"
		airlock = old_exit
		airlock.monitoring = false
		# Ensure collision layer is set for area detection
		airlock.collision_layer = 1
		airlock.collision_mask = 1
	else:
		airlock = Area3D.new()
		airlock.name = "Airlock"
		airlock.position = Vector3(0, 1.5, 9.6)
		airlock.collision_layer = 1
		airlock.collision_mask = 1
		var a_col := CollisionShape3D.new()
		var a_shape := BoxShape3D.new()
		a_shape.size = Vector3(3, 3, 1.5)
		a_col.shape = a_shape
		airlock.add_child(a_col)
		add_child(airlock)

	# Repurpose old ExitVFX (if it still exists under the now-renamed airlock)
	airlock_vfx = airlock.get_node_or_null("ExitVFX") as GPUParticles3D
	if not airlock_vfx:
		airlock_vfx = GPUParticles3D.new()
		airlock_vfx.name = "ExitVFX"
		airlock_vfx.emitting = false
		airlock_vfx.amount = 20
		airlock_vfx.lifetime = 1.2
		var ppm := ParticleProcessMaterial.new()
		ppm.direction = Vector3(0, 1, 0)
		ppm.spread = 15.0
		ppm.gravity = Vector3(0, 0.2, 0)
		ppm.initial_velocity_min = 0.5
		ppm.initial_velocity_max = 1.2
		ppm.scale_min = 0.1
		ppm.scale_max = 0.25
		ppm.color = Color(0.3, 0.8, 1.0, 1)
		airlock_vfx.process_material = ppm
		airlock.add_child(airlock_vfx)

	# Create ExitDoor — a physical door that blocks the path
	exit_door = StaticBody3D.new()
	exit_door.name = "ExitDoor"
	exit_door.position = Vector3(0, 1.5, 9.0)
	exit_door.collision_layer = 1
	exit_door.collision_mask = 1
	add_child(exit_door)

	door_mesh = MeshInstance3D.new()
	door_mesh.name = "DoorMesh"
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 3.0, 0.3)
	door_mesh.mesh = box
	exit_door.add_child(door_mesh)

	door_col = CollisionShape3D.new()
	door_col.name = "DoorCollision"
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(2.5, 3.0, 0.3)
	door_col.shape = col_shape
	exit_door.add_child(door_col)


func _setup_map() -> void:
	var map_node := Node3D.new()
	map_node.name = "Map3D"
	map_node.set_script(MAP3D_SCENE)
	map_node.position = Vector3(0, 1.6, 9.4)
	map_node.rotation_degrees = Vector3(0, 180, 0)
	add_child(map_node)
	_map3d = map_node


func configure(room_data: Dictionary) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_do_configure.rpc(room_data)
	else:
		_apply_configure(room_data)


@rpc("authority", "call_local", "reliable")
func _do_configure(room_data: Dictionary) -> void:
	_apply_configure(room_data)


func _apply_configure(room_data: Dictionary) -> void:
	_clear_room()
	match room_data.get("type", RoomManager.RoomType.COMBAT):
		RoomManager.RoomType.COMBAT, RoomManager.RoomType.BOSS:
			_spawn_encounter(room_data)
		RoomManager.RoomType.CHEST:
			_auto_clear()
		RoomManager.RoomType.SHOP:
			_auto_clear()
		RoomManager.RoomType.EVENT:
			_auto_clear()

	if _map3d and _map3d.has_method("_refresh_markers"):
		_map3d._refresh_markers()


func _clear_room() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			if e.died.is_connected(_on_enemy_died):
				e.died.disconnect(_on_enemy_died)
			e.queue_free()
	_enemies.clear()
	_enemies_dead = 0

	for c in props_root.get_children():
		c.queue_free()

	_room_cleared = false
	_map_choice_made = false
	_players_in_airlock.clear()
	_set_door_locked(true)
	airlock.monitoring = false
	airlock_vfx.emitting = false


func _spawn_encounter(room_data: Dictionary) -> void:
	var encounter: Dictionary = room_data.get("encounter", {})
	var enemy_list: Array = encounter.get("enemies", [])

	if enemy_list.is_empty():
		enemy_list = [{"name": "Grunt", "scale": Vector3.ONE,
			"hp": 40.0, "speed": 3.0, "color": Color(0.55, 0.1, 0.15),
			"pos": Vector3(0, 1.0, -5)}]

	for i in enemy_list.size():
		var edata: Dictionary = enemy_list[i]
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		enemy.name = "Enemy_%d" % i
		enemy.set_multiplayer_authority(1)
		enemies_root.add_child(enemy)
		enemy.configure_enemy(edata)
		enemy.position = edata.get("pos", Vector3(0, 1.0, -5))
		enemy.died.connect(_on_enemy_died)
		_enemies.append(enemy)


func _auto_clear() -> void:
	_room_cleared = true
	_unlock_map_choices()


func _on_enemy_died() -> void:
	_enemies_dead += 1
	if _enemies_dead >= _enemies.size():
		_room_cleared = true
		_unlock_map_choices()


func _unlock_map_choices() -> void:
	if not multiplayer.is_server():
		return
	if RoomManager.current_room_id != "":
		RoomManager.complete_current_room()

	var choices := RoomManager.get_available_choices()
	if choices.is_empty():
		_on_map_choice_made()
	elif choices.size() == 1 or _is_autopilot_active():
		RoomManager.request_select_room(choices[0]["id"])


func _on_map_choice_made(_room_id: String = "") -> void:
	_map_choice_made = true
	_unlock_door.rpc()


@rpc("authority", "call_local", "reliable")
func _unlock_door() -> void:
	_set_door_locked(false)
	airlock.monitoring = true
	airlock_vfx.emitting = true
	print("[Arena] Exit door unlocked — all players enter airlock to advance")


func _set_door_locked(locked: bool) -> void:
	if not is_instance_valid(door_col):
		return
	door_col.disabled = not locked
	if not is_instance_valid(door_mesh):
		return
	var mat := StandardMaterial3D.new()
	if locked:
		mat.albedo_color = DOOR_MAT_LOCKED_COLOR
		mat.emission_enabled = true
		mat.emission = DOOR_MAT_LOCKED_EMIT
		mat.emission_energy_multiplier = 1.2
	else:
		mat.albedo_color = DOOR_MAT_UNLOCKED_COLOR
		mat.emission_enabled = true
		mat.emission = DOOR_MAT_UNLOCKED_EMIT
		mat.emission_energy_multiplier = 1.5
	door_mesh.material_override = mat


func _on_airlock_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("player"):
		var pid := body.get_multiplayer_authority()
		_players_in_airlock[pid] = true
		print("[Arena] Player %d in airlock (%d/%d)" % [pid, _players_in_airlock.size(), Net.players.size()])
		_check_all_players_ready()


func _on_airlock_exited(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("player"):
		var pid := body.get_multiplayer_authority()
		_players_in_airlock.erase(pid)


func _check_all_players_ready() -> void:
	if not multiplayer.is_server():
		return
	if not _room_cleared or not _map_choice_made:
		return
	for pid in Net.players:
		if pid not in _players_in_airlock:
			return
	_trigger_exit.rpc()


@rpc("authority", "call_local", "reliable")
func _trigger_exit() -> void:
	print("[Arena] All players in airlock — transitioning")
	_set_door_locked(true)
	airlock.monitoring = false
	airlock_vfx.emitting = false
	exit_triggered.emit()


func _is_autopilot_active() -> bool:
	for p in player_root.get_children():
		if "autopilot" in p and p.autopilot == true:
			return true
	return false


func get_airlock_position() -> Vector3:
	if is_instance_valid(airlock):
		return airlock.global_position
	return Vector3.ZERO


func is_exit_unlocked() -> bool:
	return _map_choice_made and _room_cleared


func get_enemy() -> Enemy:
	for e in _enemies:
		if is_instance_valid(e) and not e._dead:
			return e
	return null


func is_enemy_dead() -> bool:
	return _enemies_dead >= _enemies.size() and _enemies.size() > 0


@rpc("authority", "reliable")
func _sync_arena_state() -> void:
	if _room_cleared and _map_choice_made:
		_set_door_locked(false)
		airlock.monitoring = true
		airlock_vfx.emitting = true
