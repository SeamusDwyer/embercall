extends MeshInstance3D
class_name HealthBar3D
## World-space, camera-facing health bar. Renders a single billboarded quad
## whose fill is driven by a shader uniform, so there is no per-frame transform
## math and no sub-node anchoring issues.
##
## Attach to a MeshInstance3D in an entity scene; call set_health() to update.

const SHADER := preload("res://scripts/vfx/health_bar.gdshader")

@export var bar_size: Vector2 = Vector2(0.9, 0.12)
@export var hide_at_full_health: bool = false
@export var fill_color: Color = Color(0.22, 0.85, 0.25)
@export var low_color: Color = Color(0.9, 0.15, 0.1)

var _material: ShaderMaterial


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = bar_size
	mesh = quad

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("fill_color", fill_color)
	_material.set_shader_parameter("low_color", low_color)
	material_override = _material

	set_health(1.0, 1.0)


func set_health(current: float, maximum: float) -> void:
	var ratio := 1.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	if _material:
		_material.set_shader_parameter("health", ratio)
	visible = not hide_at_full_health or ratio < 1.0
