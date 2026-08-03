extends Node
## Autoload "DebugShapes" — toggleable hitbox visualization.

var show_hitboxes: bool = false
var show_hit_impacts: bool = false


func set_visible(v: bool) -> void:
	show_hitboxes = v
	if v:
		_ensure_parent()
	elif _overlay_parent:
		_overlay_parent.visible = false


func set_impacts_visible(v: bool) -> void:
	show_hit_impacts = v

const COLORS := {
	"player": Color(0.2, 0.6, 1.0, 0.3),
	"enemy": Color(1.0, 0.2, 0.2, 0.3),
	"flammable": Color(1.0, 0.6, 0.1, 0.3),
	"exit": Color(0.3, 1.0, 0.3, 0.3),
	"default": Color(1.0, 1.0, 1.0, 0.2),
}

var _overlay_parent: Node3D
var _overlays: Dictionary = {}


func _ensure_parent() -> void:
	if _overlay_parent and is_instance_valid(_overlay_parent):
		_overlay_parent.visible = true
		return
	_overlay_parent = Node3D.new()
	_overlay_parent.name = "HitboxOverlays"
	get_tree().get_root().add_child.call_deferred(_overlay_parent)


func _process(_delta: float) -> void:
	if not show_hitboxes:
		return
	if _overlay_parent == null or not is_instance_valid(_overlay_parent):
		return

	var to_process: Array[CollisionShape3D] = []
	_collect_shapes(get_tree().get_root(), to_process)

	for shape: CollisionShape3D in to_process:
		if _overlays.has(shape):
			var overlay: MeshInstance3D = _overlays[shape]
			if is_instance_valid(overlay):
				overlay.global_transform = shape.global_transform
		else:
			_create_overlay(shape)

	var dead: Array = []
	for shape in _overlays:
		if not is_instance_valid(shape):
			var overlay: MeshInstance3D = _overlays[shape]
			if is_instance_valid(overlay):
				overlay.queue_free()
			dead.append(shape)
	for shape in dead:
		_overlays.erase(shape)


func _collect_shapes(node: Node, out_shapes: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D and node.shape != null:
		out_shapes.append(node)
	for child in node.get_children():
		_collect_shapes(child, out_shapes)


func _create_overlay(shape: CollisionShape3D) -> void:
	if _overlay_parent == null:
		return

	var mesh: Mesh
	var s = shape.shape
	if s is BoxShape3D:
		var box := BoxMesh.new()
		box.size = s.size
		mesh = box
	elif s is CapsuleShape3D:
		var cap := CapsuleMesh.new()
		cap.radius = s.radius
		cap.height = s.height
		mesh = cap
	elif s is SphereShape3D:
		var sp := SphereMesh.new()
		sp.radius = s.radius
		sp.height = s.radius * 2.0
		mesh = sp
	else:
		return

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var tag := _tag_for_shape(shape)
	mat.albedo_color = COLORS.get(tag, COLORS["default"])

	var overlay := MeshInstance3D.new()
	overlay.mesh = mesh
	overlay.set_surface_override_material(0, mat)
	overlay.global_transform = shape.global_transform
	overlay.set_meta("source_shape", shape)

	_overlay_parent.add_child.call_deferred(overlay)
	_overlays[shape] = overlay


func _tag_for_shape(shape: CollisionShape3D) -> String:
	var owner := shape.get_parent()
	while owner:
		if owner.is_in_group("player"):
			return "player"
		if owner.is_in_group("enemy"):
			return "enemy"
		if owner.is_in_group("flammable"):
			return "flammable"
		if owner.name.to_lower().contains("exit"):
			return "exit"
		owner = owner.get_parent()
	return "default"
