@tool
extends Node3D
## Visual-only "ghost" marker used to author weapon swing keyframes.
##
## Place one under the player's swing-pose container and move/rotate it to the
## desired final-frame pose of the weapon. Player hides these at runtime unless
## `show_ghosts` is enabled. Meshes are rendered translucent so they read as
## reference poses while editing.

@export_range(0.0, 1.0, 0.01) var transparency: float = 0.6:
	set(value):
		transparency = value
		_apply_style()


func _ready() -> void:
	_apply_style()


func _apply_style() -> void:
	for mesh in _meshes(self):
		mesh.transparency = transparency
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
