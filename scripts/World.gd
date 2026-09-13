extends Node3D
class_name World
## Owns the physical dungeon: instantiates one Room per generated room, lays
## them out on a depth-major grid, links adjacent floors with corridors, and
## wires up door traversal.
##
## Layout: X = slot, Z = -global_depth. Global depth is continuous across acts
## so the whole run is one dungeon (act = bookkeeping for scaling/state).

const PITCH_X := 26.0
const PITCH_Z := 34.0
const ROOM_W := 20.0
const ROOM_D := 20.0
const CORRIDOR_WIDTH := 5.0

const ROOM_SCRIPT := preload("res://scripts/Room.gd")
const MAP3D_SCRIPT := preload("res://scripts/Map3D.gd")

signal room_entered(room_id: String)
signal room_cleared(room_id: String)
signal run_complete()

var rooms: Dictionary = {}          # room_id -> Room
var _map: Node3D
var _built := false


func _ready() -> void:
	# Clients build the world when the server's map arrives (server builds
	# explicitly via Main._start_run -> build_run).
	RoomManager.map_generated.connect(_on_map_generated)


func _on_map_generated(_act_data: Dictionary) -> void:
	if not _built:
		build_run()


func build_run() -> void:
	if _built:
		return
	_built = true
	_clear_world()
	_create_rooms()
	_create_corridors()
	_create_map()

	# Activate the starting room immediately; players spawn inside it.
	var first := RoomManager.get_current_room()
	if not first.is_empty():
		var room: Room = rooms.get(first["id"])
		if room:
			room.activate()


func _clear_world() -> void:
	for c in get_children():
		c.queue_free()
	rooms.clear()


func _create_rooms() -> void:
	for act_data in RoomManager.acts:
		var act_num: int = act_data.get("act_num", 1)
		var floors: Array = act_data.get("floors", [])
		for floor_idx in range(floors.size()):
			var floor_rooms: Array = floors[floor_idx]
			for room_data in floor_rooms:
				var room: Room = ROOM_SCRIPT.new()
				room.name = "Room_" + room_data["id"]
				room.position = _room_position(act_num, floor_idx, room_data.get("slot", 0))
				add_child(room)

				var child_datas: Array = []
				for cid in room_data.get("children", []):
					var cd := RoomManager.get_room_by_id(cid)
					if not cd.is_empty():
						child_datas.append(cd)
				room.setup(room_data, child_datas)
				room.player_entered.connect(_on_room_player_entered)
				room.cleared.connect(_on_room_cleared)
				room.choice_locked.connect(_on_choice_locked)
				rooms[room_data["id"]] = room


func _room_position(act_num: int, floor_idx: int, slot: int) -> Vector3:
	var depth := (act_num - 1) * RoomManager.FLOORS_PER_ACT + floor_idx
	return Vector3(slot * PITCH_X, 0, -depth * PITCH_Z)


func _create_corridors() -> void:
	for act_data in RoomManager.acts:
		var floors: Array = act_data.get("floors", [])
		for floor_rooms in floors:
			for room_data in floor_rooms:
				var source: Room = rooms.get(room_data["id"])
				if source == null:
					continue
				var children: Array = room_data.get("children", [])
				for i in range(children.size()):
					var target: Room = rooms.get(children[i])
					if target == null:
						continue
					var from := source.global_position + Vector3(source._exit_gap_x(i, children.size()), 0, -ROOM_D / 2.0)
					var to := target.global_position + Vector3(0, 0, ROOM_D / 2.0)
					_add_corridor(from, to)


func _add_corridor(from: Vector3, to: Vector3) -> void:
	# Axis-aligned L/Z: forward out of the source, lateral, then forward into
	# the target. Floors only — the void between floors prevents wandering.
	var mid_z := (from.z + to.z) / 2.0
	_add_segment(Vector3(from.x, 0, from.z), Vector3(from.x, 0, mid_z))
	_add_segment(Vector3(from.x, 0, mid_z), Vector3(to.x, 0, mid_z))
	_add_segment(Vector3(to.x, 0, mid_z), Vector3(to.x, 0, to.z))


func _add_segment(a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var length := Vector2(delta.x, delta.z).length()
	if length < 0.1:
		return
	var dir := Vector3(delta.x, 0.0, delta.z).normalized()
	var mid := (a + b) / 2.0
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	_add_box(mid, Vector3(CORRIDOR_WIDTH, 0.4, length), yaw, _floor_mat(), "CorridorFloor")


func _add_box(pos: Vector3, size: Vector3, yaw: float, mat: StandardMaterial3D, box_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	body.rotation_degrees = Vector3(0, yaw, 0)
	body.collision_layer = 1
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)


func _floor_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	return mat


func _create_map() -> void:
	_map = Node3D.new()
	_map.name = "Map3D"
	_map.set_script(MAP3D_SCRIPT)
	add_child(_map)
	_reposition_map()


func _reposition_map() -> void:
	if not is_instance_valid(_map):
		return
	var room := get_current_room()
	if room == null:
		return
	_map.global_position = room.global_position + Vector3(7, 1.6, 9.4)
	_map.rotation_degrees = Vector3(0, 180, 0)


# -- Signal handlers ---------------------------------------------------------

func _on_room_player_entered(room_id: String) -> void:
	if RoomManager.current_room_id == room_id:
		return
	RoomManager.enter_room(room_id)
	room_entered.emit(room_id)
	_reposition_map()


func _on_room_cleared(room_id: String) -> void:
	room_cleared.emit(room_id)
	var data := RoomManager.get_room_by_id(room_id)
	if data.get("children", []).is_empty():
		run_complete.emit()


func _on_choice_locked(_chosen_id: String, unchosen_ids: Array) -> void:
	# Seal the entry gates of the rooms the player did NOT choose, so the
	# choice is final even if corridors physically converge.
	for cid in unchosen_ids:
		var room: Room = rooms.get(cid)
		if room:
			room._seal_entry_forced.rpc()


# -- Queries -----------------------------------------------------------------

func get_room_node(room_id: String) -> Room:
	return rooms.get(room_id)


func get_current_room() -> Room:
	return rooms.get(RoomManager.current_room_id)


func get_room_center(room_id: String) -> Vector3:
	var room: Room = rooms.get(room_id)
	if room:
		return room.global_position
	return Vector3.ZERO


func is_exit_unlocked() -> bool:
	var room := get_current_room()
	return room != null and room.is_exit_unlocked()


func get_enemy() -> Enemy:
	var room := get_current_room()
	return room.get_enemy() if room else null


func is_enemy_dead() -> bool:
	var room := get_current_room()
	return room.is_enemy_dead() if room else false


@rpc("authority", "reliable")
func _sync_arena_state() -> void:
	# Late-join: re-apply the current room's gate state.
	var room := get_current_room()
	if room == null:
		return
	if room.is_exit_unlocked():
		for gate in room.exit_gates:
			gate.set_locked(false)


## Replay the current room's activation + gate state to a late-joining peer.
func replay_to_peer(peer_id: int) -> void:
	var room := get_current_room()
	if room != null:
		room.replay_activation_to_peer(peer_id)
	_sync_arena_state.rpc_id(peer_id)
