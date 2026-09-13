extends Node3D
## Physical 3D emblem mounted above an exit door.
## Shape + colour indicate the type of room the door leads to.
## Uses simple generated meshes so it renders under the headless dummy driver.

const SYMBOL_SIZE := 0.5

static func color_for_type(room_type: int) -> Color:
	match room_type:
		RoomManager.RoomType.COMBAT:
			return Color(0.8, 0.3, 0.2)
		RoomManager.RoomType.CHEST:
			return Color(0.8, 0.7, 0.2)
		RoomManager.RoomType.EVENT:
			return Color(0.5, 0.3, 0.8)
		RoomManager.RoomType.SHOP:
			return Color(0.2, 0.6, 0.8)
		RoomManager.RoomType.BOSS:
			return Color(0.9, 0.1, 0.1)
		_:
			return Color(0.8, 0.3, 0.2)


func setup(room_type: int) -> void:
	_clear()
	var color := color_for_type(room_type)

	var mesh := MeshInstance3D.new()
	mesh.name = "Emblem"
	mesh.mesh = _make_mesh(room_type)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.8
	mat.emission_energy_multiplier = 1.4
	mat.metallic = 0.3
	mat.roughness = 0.4
	mesh.material_override = mat
	add_child(mesh)

	# Soft backlight ring so the emblem reads at a distance.
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = color
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	add_child(glow)


func _clear() -> void:
	for c in get_children():
		c.queue_free()


func _make_mesh(room_type: int) -> Mesh:
	match room_type:
		RoomManager.RoomType.BOSS:
			return _diamond()
		RoomManager.RoomType.CHEST:
			var b := BoxMesh.new()
			b.size = Vector3(SYMBOL_SIZE, SYMBOL_SIZE * 0.8, SYMBOL_SIZE * 0.6)
			return b
		RoomManager.RoomType.SHOP:
			var b := BoxMesh.new()
			b.size = Vector3(SYMBOL_SIZE * 0.9, SYMBOL_SIZE * 0.9, SYMBOL_SIZE * 0.4)
			return b
		RoomManager.RoomType.EVENT:
			var p := PrismMesh.new()
			p.size = Vector3(SYMBOL_SIZE, SYMBOL_SIZE, SYMBOL_SIZE)
			return p
		_:
			var b := BoxMesh.new()
			b.size = Vector3(SYMBOL_SIZE, SYMBOL_SIZE, SYMBOL_SIZE)
			return b


func _diamond() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := SYMBOL_SIZE * 0.5
	var v := [Vector3(0, s, 0), Vector3(-s, 0, s), Vector3(s, 0, s),
		Vector3(s, 0, -s), Vector3(-s, 0, -s), Vector3(0, -s, 0)]
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
