extends Node3D
## A gated doorway between two rooms. Doubles as the airlock boundary:
## the gate is a solid collision body while locked and opens (collision
## disabled) when its room's clear condition is met.
##
## Exit doors carry a RoomSymbol above them indicating the destination type.

const LOCKED_COLOR := Color(0.6, 0.1, 0.05)
const LOCKED_EMIT := Color(0.8, 0.05, 0.0)
const OPEN_COLOR := Color(0.0, 0.4, 0.7)
const OPEN_EMIT := Color(0.0, 0.5, 1.0)

var destination_id: String = ""
var is_entry: bool = false
var locked: bool = true

var _gate: StaticBody3D
var _mesh: MeshInstance3D
var _col: CollisionShape3D
var _symbol: Node3D


func build(gap_width: float, height: float, thickness: float) -> void:
	_gate = StaticBody3D.new()
	_gate.name = "Gate"
	_gate.collision_layer = 1
	_gate.collision_mask = 1
	add_child(_gate)

	_mesh = MeshInstance3D.new()
	_mesh.name = "GateMesh"
	var box := BoxMesh.new()
	box.size = Vector3(gap_width, height, thickness)
	_mesh.mesh = box
	_gate.add_child(_mesh)

	_col = CollisionShape3D.new()
	_col.name = "GateCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(gap_width, height, thickness)
	_col.shape = shape
	_gate.add_child(_col)

	_apply_material()


func add_symbol(room_type: int, y: float) -> void:
	var symbol := Node3D.new()
	symbol.name = "RoomSymbol"
	symbol.set_script(load("res://scripts/RoomSymbol.gd"))
	symbol.position = Vector3(0, y, 0)
	add_child(symbol)
	symbol.setup(room_type)
	_symbol = symbol


func set_locked(value: bool) -> void:
	locked = value
	if is_instance_valid(_col):
		_col.set_deferred("disabled", not locked)
	_apply_material()


func _apply_material() -> void:
	if not is_instance_valid(_mesh):
		return
	var mat := StandardMaterial3D.new()
	if locked:
		mat.albedo_color = LOCKED_COLOR
		mat.emission_enabled = true
		mat.emission = LOCKED_EMIT
		mat.emission_energy_multiplier = 1.2
	else:
		mat.albedo_color = OPEN_COLOR
		mat.emission_enabled = true
		mat.emission = OPEN_EMIT
		mat.emission_energy_multiplier = 1.5
	_mesh.material_override = mat
