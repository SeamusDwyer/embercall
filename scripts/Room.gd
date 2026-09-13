extends Node3D
class_name Room
## One physical room in the dungeon. Owns its geometry, its gated doorways and
## its encounter contents.
##
## Forward is -Z: the player enters through the south (+Z) entry gate and
## leaves through north (-Z) exit gates, one per child room. Same-floor rooms
## are never connected.
##
## Flow:
##   1. First player enters the activation area -> contents spawn.
##   2. Once every player is inside, the entry gate closes (airlock) and stays
##      closed (no backtracking). Combat rooms are sealed this way.
##   3. Clear condition met -> exit gates open (symbols glow).
##   4. Player walks through an exit gate into the next room.

const ROOM_W := 20.0
const ROOM_D := 20.0
const WALL_H := 4.0
const WALL_T := 0.5
const DOOR_GAP := 3.0
const FLOOR_THICK := 0.4

const WALL_COLOR := Color(0.28, 0.24, 0.24)
const FLOOR_COLOR := Color(0.18, 0.18, 0.2)
const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const DOOR_SCRIPT := preload("res://scripts/Door.gd")

signal activated(room_id: String)
signal player_entered(room_id: String)
signal cleared(room_id: String)
signal enemy_spawned(enemy: Enemy)
signal choice_locked(chosen_id: String, unchosen_ids: Array)

var room_id: String = ""
var room_type: int = RoomManager.RoomType.COMBAT
var room_data: Dictionary = {}
var children_ids: Array = []

var entry_gate: Node3D = null
var exit_gates: Array[Node3D] = []

var _activated := false
var _cleared := false
var _player_entered := false
var _entry_sealed := false
var _chosen_exit := -1
var _enemies: Array[Enemy] = []
var _enemies_dead := 0
var _players_inside: Dictionary = {}
var _activation_area: Area3D
var _enemies_root: Node3D
var _props_root: Node3D
var _light: DirectionalLight3D


func setup(data: Dictionary, child_datas: Array) -> void:
	room_data = data
	room_id = data.get("id", "")
	room_type = data.get("type", RoomManager.RoomType.COMBAT)
	children_ids = []
	for c in child_datas:
		children_ids.append(c.get("id", ""))

	_build_shell()
	_build_gates(child_datas)
	_build_activation_area()


func _build_shell() -> void:
	_light = DirectionalLight3D.new()
	_light.name = "RoomLight"
	_light.rotation_degrees = Vector3(-55, -35, 0)
	_light.light_energy = 0.7
	add_child(_light)

	_add_static_box(self, "Floor", Vector3(0, 0, 0),
		Vector3(ROOM_W, FLOOR_THICK, ROOM_D), FLOOR_COLOR, true)

	_add_static_box(self, "WallWest", Vector3(-ROOM_W / 2.0, WALL_H / 2.0, 0),
		Vector3(WALL_T, WALL_H, ROOM_D), WALL_COLOR)
	_add_static_box(self, "WallEast", Vector3(ROOM_W / 2.0, WALL_H / 2.0, 0),
		Vector3(WALL_T, WALL_H, ROOM_D), WALL_COLOR)

	# South wall: entry gap only when this room has a parent.
	var south_gaps: Array[float] = []
	if not room_data.get("parents", []).is_empty():
		south_gaps.append(0.0)
	_build_horizontal_wall(ROOM_D / 2.0, south_gaps)

	# North wall: one gap per child room.
	var north_gaps: Array[float] = []
	for i in range(children_ids.size()):
		north_gaps.append(_exit_gap_x(i, children_ids.size()))
	_build_horizontal_wall(-ROOM_D / 2.0, north_gaps)

	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	add_child(_enemies_root)

	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)


func _build_horizontal_wall(z: float, gap_centers: Array[float]) -> void:
	var sorted_gaps := gap_centers.duplicate()
	sorted_gaps.sort()
	var half := ROOM_W / 2.0
	var edges: Array[float] = [-half]
	for g in sorted_gaps:
		edges.append(g - DOOR_GAP / 2.0)
		edges.append(g + DOOR_GAP / 2.0)
	edges.append(half)

	var idx := 0
	while idx + 1 < edges.size():
		var a: float = edges[idx]
		var b: float = edges[idx + 1]
		idx += 2
		var seg_w := b - a
		if seg_w <= 0.05:
			continue
		_add_static_box(self, "WallSeg_%s_%d" % [str(z), idx], Vector3((a + b) / 2.0, WALL_H / 2.0, z),
			Vector3(seg_w, WALL_H, WALL_T), WALL_COLOR)


func _exit_gap_x(index: int, count: int) -> float:
	if count <= 1:
		return 0.0
	var span := ROOM_W / float(count)
	return (index - (count - 1) / 2.0) * span


func _build_gates(child_datas: Array) -> void:
	if not room_data.get("parents", []).is_empty():
		var entry := Node3D.new()
		entry.name = "EntryGate"
		entry.set_script(DOOR_SCRIPT)
		entry.position = Vector3(0, WALL_H / 2.0, ROOM_D / 2.0)
		add_child(entry)
		entry.build(DOOR_GAP, WALL_H, WALL_T)
		entry.set_locked(false)  # open for entry; closes once the party is inside
		entry_gate = entry

	for i in range(child_datas.size()):
		var child: Dictionary = child_datas[i]
		var gate := Node3D.new()
		gate.name = "ExitGate_%d" % i
		gate.set_script(DOOR_SCRIPT)
		gate.position = Vector3(_exit_gap_x(i, child_datas.size()), WALL_H / 2.0, -ROOM_D / 2.0)
		add_child(gate)
		gate.build(DOOR_GAP, WALL_H, WALL_T)
		gate.destination_id = child.get("id", "")
		gate.set_locked(true)
		gate.add_symbol(child.get("type", RoomManager.RoomType.COMBAT), WALL_H / 2.0 + 0.7)
		exit_gates.append(gate)

		# Airlock just outside the gate: detects traversal and locks the choice.
		var area := Area3D.new()
		area.name = "ExitAirlock_%d" % i
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		var acol := CollisionShape3D.new()
		var ashape := BoxShape3D.new()
		ashape.size = Vector3(DOOR_GAP, WALL_H, 2.0)
		acol.shape = ashape
		area.add_child(acol)
		area.position = Vector3(_exit_gap_x(i, child_datas.size()), WALL_H / 2.0, -ROOM_D / 2.0 - 1.0)
		add_child(area)
		area.body_entered.connect(_on_exit_airlock_entered.bind(i))


func _build_activation_area() -> void:
	_activation_area = Area3D.new()
	_activation_area.name = "ActivationArea"
	_activation_area.collision_layer = 0
	_activation_area.collision_mask = 1
	_activation_area.monitoring = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ROOM_W - 2.0, WALL_H, ROOM_D - 2.0)
	col.shape = shape
	_activation_area.add_child(col)
	_activation_area.position = Vector3(0, WALL_H / 2.0, 0)
	add_child(_activation_area)
	_activation_area.body_entered.connect(_on_area_entered)
	_activation_area.body_exited.connect(_on_area_exited)


# -- Activation & contents ---------------------------------------------------

func activate() -> void:
	if _activated:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_activated = true
	if multiplayer.has_multiplayer_peer():
		_sync_activate.rpc()
	else:
		_spawn_contents()
	activated.emit(room_id)


@rpc("authority", "call_local", "reliable")
func _sync_activate() -> void:
	_spawn_contents()


## Re-send this room's activation to a late-joining peer so its enemy nodes
## exist (matching paths) before their MultiplayerSynchronizer starts syncing.
func replay_activation_to_peer(peer_id: int) -> void:
	if not _activated:
		return
	_sync_activate.rpc_id(peer_id)


func _spawn_contents() -> void:
	match room_type:
		RoomManager.RoomType.COMBAT, RoomManager.RoomType.BOSS:
			_spawn_encounter()
		RoomManager.RoomType.SHOP:
			_do_clear()
		RoomManager.RoomType.CHEST:
			_spawn_chest()
		RoomManager.RoomType.EVENT:
			_do_clear()


func _spawn_encounter() -> void:
	var encounter: Dictionary = room_data.get("encounter", {})
	var enemy_list: Array = encounter.get("enemies", [])
	if enemy_list.is_empty():
		enemy_list = [{"name": "Grunt", "scale": Vector3.ONE, "hp": 40.0,
			"speed": 3.0, "color": Color(0.55, 0.1, 0.15), "pos": Vector3(0, 1.0, -5)}]

	var act: int = room_data.get("act", 1)
	var floor_num: int = room_data.get("floor", 0)
	var hp_mult := RoomManager.get_enemy_health_multiplier(act, floor_num)
	if room_type == RoomManager.RoomType.BOSS:
		hp_mult *= 2.5

	for i in range(enemy_list.size()):
		var edata: Dictionary = enemy_list[i].duplicate(true)
		edata["hp"] = edata.get("hp", 40.0) * hp_mult
		if room_type == RoomManager.RoomType.BOSS and edata.has("scale"):
			edata["scale"] = (edata["scale"] as Vector3) * 1.5
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		enemy.name = "Enemy_%d" % i
		enemy.set_multiplayer_authority(1)
		_enemies_root.add_child(enemy)
		enemy.configure_enemy(edata)
		enemy.position = edata.get("pos", Vector3(0, 1.0, -5))
		enemy.died.connect(_on_enemy_died)
		_enemies.append(enemy)
		enemy_spawned.emit(enemy)


func _spawn_chest() -> void:
	var chest := _add_static_box(_props_root, "Chest", Vector3(0, 0.6, -5),
		Vector3(1.4, 1.2, 1.0), Color(0.55, 0.4, 0.12))
	chest.name = "Chest"
	# Stub: opening the chest clears the room after a short beat.
	if multiplayer.is_server():
		get_tree().create_timer(0.75).timeout.connect(_do_clear)


# -- Clear conditions --------------------------------------------------------

func _on_enemy_died() -> void:
	if not multiplayer.is_server():
		return
	_enemies_dead += 1
	if _enemies_dead >= _enemies.size():
		_do_clear()


func _do_clear() -> void:
	if _cleared:
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_clear.rpc()
	else:
		_apply_clear()


@rpc("authority", "call_local", "reliable")
func _sync_clear() -> void:
	_apply_clear()


func _apply_clear() -> void:
	if _cleared:
		return
	_cleared = true
	for gate in exit_gates:
		gate.set_locked(false)
	cleared.emit(room_id)
	if multiplayer.is_server():
		RoomManager.complete_current_room()


# -- Airlock -----------------------------------------------------------------

func _on_area_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var pid := body.get_multiplayer_authority()
	_players_inside[pid] = true

	if not _activated:
		activate()

	if not _player_entered:
		_player_entered = true
		if multiplayer.is_server():
			player_entered.emit(room_id)

	_check_airlock()


func _on_area_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_players_inside.erase(body.get_multiplayer_authority())


func _check_airlock() -> void:
	if _entry_sealed or not is_instance_valid(entry_gate):
		return
	if not multiplayer.is_server():
		return
	for pid in Net.players:
		if pid not in _players_inside:
			return
	_entry_sealed = true
	_seal_entry.rpc()


@rpc("authority", "call_local", "reliable")
func _seal_entry() -> void:
	if is_instance_valid(entry_gate):
		entry_gate.set_locked(true)


## Seal this room's entry gate because another path was chosen (locks it out).
@rpc("authority", "call_local", "reliable")
func _seal_entry_forced() -> void:
	_entry_sealed = true
	if is_instance_valid(entry_gate):
		entry_gate.set_locked(true)


# -- Exit choice locking ------------------------------------------------------

func _on_exit_airlock_entered(body: Node3D, index: int) -> void:
	if not body.is_in_group("player"):
		return
	if not multiplayer.is_server():
		return
	# First player through locks in the choice: every other exit seals.
	if _chosen_exit == -1:
		_chosen_exit = index
		_sync_seal_exits.rpc(index)
		var unchosen: Array = []
		for i in range(children_ids.size()):
			if i != index:
				unchosen.append(children_ids[i])
		choice_locked.emit(children_ids[index] if index < children_ids.size() else "", unchosen)


@rpc("authority", "call_local", "reliable")
func _sync_seal_exits(chosen: int) -> void:
	_chosen_exit = chosen
	for i in range(exit_gates.size()):
		if i != chosen:
			exit_gates[i].set_locked(true)


# -- Queries (autopilot / GameState) -----------------------------------------

func is_activated() -> bool:
	return _activated


func is_cleared() -> bool:
	return _cleared


func get_enemy() -> Enemy:
	for e in _enemies:
		if is_instance_valid(e) and not e._dead:
			return e
	return null


func is_enemy_dead() -> bool:
	return _enemies.size() > 0 and _enemies_dead >= _enemies.size()


func is_exit_unlocked() -> bool:
	return _cleared and not exit_gates.is_empty()


func get_primary_exit_position() -> Vector3:
	if exit_gates.is_empty():
		return global_position
	return exit_gates[0].global_position


func get_enemy_count() -> int:
	return _enemies.size()


# -- Helpers -----------------------------------------------------------------

func _add_static_box(parent: Node3D, box_name: String, pos: Vector3, size: Vector3, color: Color, with_collision: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	if with_collision:
		body.collision_layer = 1
		body.collision_mask = 1
	else:
		body.collision_layer = 0
		body.collision_mask = 0

	if with_collision:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)

	parent.add_child(body)
	return body
