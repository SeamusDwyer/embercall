extends Node3D
## Physical 3D map placed on a wall in each room.
## Shows the full act map — room markers, connections, current position.
## Clickable markers on the next floor select the next room.

const MARKER_SIZE := 0.06
const FLOOR_SPACING := 0.28
const ROOM_SPACING := 0.18
const MAP_PADDING := Vector3(0.12, 0.12, 0.0)

var _markers: Array[Dictionary] = []
var _current_act: int = 0


func _ready() -> void:
	RoomManager.map_generated.connect(_on_map_generated)
	RoomManager.room_cleared.connect(_on_room_cleared)
	RoomManager.room_selected.connect(_on_room_selected)
	var ad := RoomManager.get_act_data()
	if not ad.is_empty():
		_on_map_generated(ad)


func _on_map_generated(act_data: Dictionary) -> void:
	_current_act = act_data.get("act_num", RoomManager.current_act)
	_clear_map()
	_build_map(act_data)


func _on_room_cleared(_room_id: String) -> void:
	_refresh_markers()


func _on_room_selected(_room_id: String) -> void:
	_refresh_markers()


func _clear_map() -> void:
	for child in get_children():
		child.queue_free()
	_markers.clear()


func _build_map(act_data: Dictionary) -> void:
	var floors: Array = act_data.get("floors", [])
	if floors.is_empty():
		return

	_current_act = act_data.get("act_num", RoomManager.current_act)

	var total_floors := floors.size()
	var max_rooms_in_floor := 1
	for f in floors:
		max_rooms_in_floor = max(max_rooms_in_floor, f.size())

	var bottom_left := Vector3(
		-(total_floors - 1) * FLOOR_SPACING / 2.0,
		(max_rooms_in_floor - 1) * ROOM_SPACING / 2.0 + 0.05,
		-0.005
	)

	for fi in range(total_floors):
		var floor_rooms: Array = floors[fi]
		var col_x := bottom_left.x + fi * FLOOR_SPACING
		for ri in range(floor_rooms.size()):
			var room_data: Dictionary = floor_rooms[ri]
			var row_y := bottom_left.y - ri * ROOM_SPACING
			var pos := Vector3(col_x, row_y, bottom_left.z - 0.01)
			_create_marker(room_data, pos)

		if fi < total_floors - 1:
			var next_rooms: Array = floors[fi + 1]
			_draw_connections(floor_rooms, next_rooms, fi, bottom_left)

	_add_board(total_floors, max_rooms_in_floor, bottom_left)
	_refresh_markers()


func _add_board(floors: int, max_rooms: int, origin: Vector3) -> void:
	var width := (floors - 1) * FLOOR_SPACING + MARKER_SIZE + MAP_PADDING.x * 2
	var height := (max_rooms - 1) * ROOM_SPACING + MARKER_SIZE + MAP_PADDING.y * 2

	var board := MeshInstance3D.new()
	board.name = "Board"
	board.mesh = BoxMesh.new()
	board.mesh.size = Vector3(width, height, 0.02)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.08, 0.08, 0.1, 0.95)
	board_mat.metallic = 0.2
	board_mat.roughness = 0.9
	board.material_override = board_mat

	var center_x := origin.x + (floors - 1) * FLOOR_SPACING / 2.0
	var center_y := origin.y - (max_rooms - 1) * ROOM_SPACING / 2.0
	board.position = Vector3(center_x, center_y, 0.0)
	add_child(board)


func _create_marker(room_data: Dictionary, pos: Vector3) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "Marker_" + room_data["id"]
	marker_root.position = pos
	add_child(marker_root)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var room_type: int = room_data["type"]
	match room_type:
		RoomManager.RoomType.BOSS:
			mesh.mesh = _make_diamond_mesh()
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(MARKER_SIZE, MARKER_SIZE, MARKER_SIZE)
			mesh.mesh = bm
	mesh.material_override = _room_material(room_data, RoomMarkerState.INACTIVE)
	marker_root.add_child(mesh)

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	body.input_ray_pickable = true
	body.input_event.connect(_on_marker_clicked.bind(room_data["id"]))
	marker_root.add_child(body)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(MARKER_SIZE * 2.5, MARKER_SIZE * 2.5, MARKER_SIZE * 2.5)
	col.shape = shape
	body.add_child(col)

	_markers.append({
		"id": room_data["id"],
		"type": room_data["type"],
		"floor": room_data["floor"],
		"node": marker_root,
		"mesh": mesh,
		"body": body,
		"state": RoomMarkerState.INACTIVE,
	})


func _draw_connections(from_rooms: Array, to_rooms: Array, floor_idx: int, origin: Vector3) -> void:
	for fi in range(from_rooms.size()):
		var fx := origin.x + floor_idx * FLOOR_SPACING
		var fy := origin.y - fi * ROOM_SPACING
		for ti in range(to_rooms.size()):
			var tx := origin.x + (floor_idx + 1) * FLOOR_SPACING
			var ty := origin.y - ti * ROOM_SPACING
			var mid := Vector3((fx + tx) / 2.0, (fy + ty) / 2.0, origin.z)
			var dx := tx - fx
			var dy := ty - fy
			var length := sqrt(dx * dx + dy * dy)
			var line_mesh := MeshInstance3D.new()
			line_mesh.name = "Line_%d_%d_to_%d" % [floor_idx, fi, ti]
			var box := BoxMesh.new()
			box.size = Vector3(length, 0.015, 0.01)
			line_mesh.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.3, 0.35, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.15, 0.15, 0.2)
			mat.emission_energy_multiplier = 0.5
			line_mesh.material_override = mat
			line_mesh.position = mid
			var angle := atan2(dy, dx)
			line_mesh.rotation_degrees = Vector3(0, 0, rad_to_deg(angle))
			add_child(line_mesh)


enum RoomMarkerState { INACTIVE, CURRENT, SELECTABLE, VISITED }

func _room_material(room_data: Dictionary, state: RoomMarkerState) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.3
	mat.roughness = 0.5

	var base_color: Color
	match room_data["type"]:
		RoomManager.RoomType.COMBAT:
			base_color = Color(0.8, 0.3, 0.2)
		RoomManager.RoomType.CHEST:
			base_color = Color(0.8, 0.7, 0.2)
		RoomManager.RoomType.EVENT:
			base_color = Color(0.5, 0.3, 0.8)
		RoomManager.RoomType.SHOP:
			base_color = Color(0.2, 0.6, 0.8)
		RoomManager.RoomType.BOSS:
			base_color = Color(0.9, 0.1, 0.1)
		_:
			base_color = Color(0.8, 0.3, 0.2)

	match state:
		RoomMarkerState.CURRENT:
			mat.albedo_color = base_color.lightened(0.4)
			mat.emission_enabled = true
			mat.emission = base_color * 0.8
			mat.emission_energy_multiplier = 1.5
		RoomMarkerState.SELECTABLE:
			mat.albedo_color = base_color.lightened(0.2)
			mat.emission_enabled = true
			mat.emission = base_color * 0.5
			mat.emission_energy_multiplier = 0.8
		RoomMarkerState.VISITED:
			mat.albedo_color = base_color.darkened(0.5)
			mat.emission_enabled = true
			mat.emission = base_color * 0.2
			mat.emission_energy_multiplier = 0.3
		_:
			mat.albedo_color = base_color.darkened(0.3)

	return mat


func _refresh_markers() -> void:
	var act := RoomManager.current_act
	if act != _current_act:
		_current_act = act
		var ad := RoomManager.get_act_data()
		if not ad.is_empty():
			_clear_map()
			_build_map(ad)
			return

	var current_id := RoomManager.current_room_id
	var current_floor := RoomManager.current_floor

	for marker in _markers:
		var mfloor: int = marker["floor"]
		var mid: String = marker["id"]
		var state: RoomMarkerState

		if mid == current_id:
			state = RoomMarkerState.CURRENT
		elif RoomManager.is_room_visited(mid):
			state = RoomMarkerState.VISITED
		elif mfloor == current_floor + 1 and current_id != "" and RoomManager.is_room_visited(current_id):
			state = RoomMarkerState.SELECTABLE
		else:
			state = RoomMarkerState.INACTIVE

		if state != marker["state"]:
			marker["state"] = state
			var mesh: MeshInstance3D = marker["mesh"]
			var body: StaticBody3D = marker["body"]
			var room_data := {"type": marker["type"]}
			mesh.material_override = _room_material(room_data, state)
			body.input_ray_pickable = (state == RoomMarkerState.SELECTABLE)


func _on_marker_clicked(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int, room_id: String) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return

	for marker in _markers:
		if marker["id"] == room_id and marker["state"] == RoomMarkerState.SELECTABLE:
			_select_room(room_id)
			return


func _select_room(room_id: String) -> void:
	RoomManager.request_select_room(room_id)


func _make_diamond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v := [Vector3(0, 0.05, 0), Vector3(-0.04, 0, 0.04), Vector3(0.04, 0, 0.04),
		Vector3(0.04, 0, -0.04), Vector3(-0.04, 0, -0.04), Vector3(0, -0.05, 0)]

	st.add_vertex(v[0]); st.add_vertex(v[1]); st.add_vertex(v[2])
	st.add_vertex(v[0]); st.add_vertex(v[2]); st.add_vertex(v[3])
	st.add_vertex(v[0]); st.add_vertex(v[3]); st.add_vertex(v[4])
	st.add_vertex(v[0]); st.add_vertex(v[4]); st.add_vertex(v[1])
	st.add_vertex(v[5]); st.add_vertex(v[2]); st.add_vertex(v[1])
	st.add_vertex(v[5]); st.add_vertex(v[3]); st.add_vertex(v[2])
	st.add_vertex(v[5]); st.add_vertex(v[4]); st.add_vertex(v[3])
	st.add_vertex(v[5]); st.add_vertex(v[1]); st.add_vertex(v[4])

	st.generate_normals()
	return st.commit()
