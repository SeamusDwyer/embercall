extends Node
class_name HitImpact
## Shared hit impact visual. Called from Player and Enemy RPCs.

static func spawn(parent: Node, pos: Vector3, color: Color) -> void:
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
	mat.albedo_color = color
	marker.set_surface_override_material(0, mat)
	marker.global_position = pos

	parent.get_tree().get_root().add_child.call_deferred(marker)

	var tween := parent.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.parallel().tween_property(marker, "scale", Vector3(0.2, 0.2, 0.2), 0.4)
	tween.tween_callback(marker.queue_free)
