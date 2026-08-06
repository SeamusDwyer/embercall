extends Node
class_name PlayerCombat
## Handles melee attacks, weapon animation, hit detection, knockback, and hit impacts.

var player: CharacterBody3D
var attack_area: Area3D
var weapon_pivot: Node3D

const COOLDOWN := 0.6
const DAMAGE := 8.0
const IGNITE_STACKS := 1
const KNOCKBACK := 8.0

const SWING_PATTERNS: Array[Dictionary] = [
	{"yaw": 55.0, "pitch": 25.0},
	{"yaw": -55.0, "pitch": 25.0},
	{"yaw": 0.0, "pitch": 60.0},
]

var cooldown_left: float = 0.0
var swing_index: int = 0
var attack_requested: bool = false


func setup(p: CharacterBody3D, area: Area3D, wpivot: Node3D) -> void:
	player = p
	attack_area = area
	weapon_pivot = wpivot


func process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= delta
		_animate_weapon()
	else:
		_reset_weapon()


func trigger_attack() -> void:
	swing_index = (swing_index + 1) % SWING_PATTERNS.size()
	cooldown_left = COOLDOWN
	player._request_attack.rpc_id(1)


func resolve_hits() -> void:
	Radar.emit_ping(player.global_position, "swing", 5.0)
	for body in attack_area.get_overlapping_bodies():
		if body == player:
			continue
		if body.has_method("take_damage"):
			body.take_damage(DAMAGE)
		if body.has_method("apply_knockback"):
			var kb_dir: Vector3 = body.global_position - player.global_position
			kb_dir.y = 0.0
			if kb_dir.length() > 0.01:
				kb_dir = kb_dir.normalized()
			else:
				kb_dir = -player.global_transform.basis.z
			body.apply_knockback(kb_dir, KNOCKBACK)
		var ignite_status = body.get_node_or_null("IgniteStatus")
		if ignite_status and ignite_status is IgniteStatus:
			ignite_status.apply_stacks(IGNITE_STACKS)
		player._spawn_hit_impact.rpc(body.global_position)


func _animate_weapon() -> void:
	if not weapon_pivot:
		return
	var progress: float = 1.0 - (cooldown_left / COOLDOWN)
	var phase: float = sin(progress * PI)
	var pattern: Dictionary = SWING_PATTERNS[swing_index]
	weapon_pivot.rotation_degrees = Vector3(-abs(phase) * pattern["pitch"], phase * pattern["yaw"], 0.0)


func _reset_weapon() -> void:
	if weapon_pivot:
		weapon_pivot.rotation_degrees = Vector3.ZERO
