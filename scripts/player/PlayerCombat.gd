extends Node
class_name PlayerCombat
## Handles melee attacks, weapon animation, hit detection, knockback, and hit impacts.

var player: CharacterBody3D
var attack_area: Area3D
var weapon_pivot: Node3D

const DAMAGE := 8.0
const IGNITE_STACKS := 1
const KNOCKBACK := 8.0

var cooldown_left: float = 0.0
var swing_index: int = 0
var attack_requested: bool = false

enum Phase { IDLE, ANTICIPATION, STRIKE, HOLD }

var _swings: Array[Node3D] = []
var _pos_spring := DampedSpring3D.new()
var _rot_spring := DampedSpring3D.new()
var _rest_pos := Vector3.ZERO
var _rest_rot := Vector3.ZERO
var _anticipation_pos := Vector3.ZERO
var _anticipation_rot := Vector3.ZERO
var _final_pos := Vector3.ZERO
var _final_rot := Vector3.ZERO
var _phase: int = Phase.IDLE
var _phase_time: float = 0.0


func setup(p: CharacterBody3D, area: Area3D, wpivot: Node3D, swings: Array[Node3D] = []) -> void:
	player = p
	attack_area = area
	weapon_pivot = wpivot
	_swings = swings
	if wpivot:
		_rest_pos = wpivot.position
		_rest_rot = wpivot.rotation
		_pos_spring.reset(_rest_pos)
		_rot_spring.reset(_rest_rot)


func process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= delta


func trigger_attack() -> void:
	if _swings.is_empty():
		return
	swing_index = swing_index % _swings.size()
	var swing := _swings[swing_index]
	swing_index = (swing_index + 1) % _swings.size()
	var anticipation := swing.get_node_or_null("Anticipation") as Node3D
	var final := swing.get_node_or_null("Final") as Node3D
	if anticipation == null or final == null:
		return
	var a := _pose_in_pivot_space(anticipation)
	var f := _pose_in_pivot_space(final)
	_anticipation_pos = _rest_pos + (a.origin - _rest_pos) * player.swing_amplitude
	_anticipation_rot = _rest_rot + (a.basis.get_euler() - _rest_rot) * player.swing_amplitude
	_final_pos = _rest_pos + (f.origin - _rest_pos) * player.swing_amplitude
	_final_rot = _rest_rot + (f.basis.get_euler() - _rest_rot) * player.swing_amplitude
	cooldown_left = player.swing_cooldown
	_phase = Phase.ANTICIPATION
	_phase_time = 0.0
	player._request_attack.rpc_id(1)


func _pose_in_pivot_space(pose: Node3D) -> Transform3D:
	var parent := weapon_pivot.get_parent() as Node3D
	if parent:
		return parent.global_transform.affine_inverse() * pose.global_transform
	return pose.transform


func resolve_hits() -> void:
	Radar.emit_ping(player.global_position, "swing", 5.0)
	for body in attack_area.get_overlapping_bodies():
		if body == player:
			continue
		if body.has_method("take_damage"):
			body.take_damage(DAMAGE, DamageLog.REASON_PLAYER_MELEE, player)
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
			ignite_status.apply_stacks(IGNITE_STACKS, player)
		player._spawn_hit_impact.rpc(body.global_position)


func process_visual(delta: float) -> void:
	if not weapon_pivot:
		return
	var target_pos := _rest_pos
	var target_rot := _rest_rot
	match _phase:
		Phase.ANTICIPATION:
			target_pos = _anticipation_pos
			target_rot = _anticipation_rot
			_phase_time += delta
			if _phase_time >= player.anticipation_time:
				_phase = Phase.STRIKE
				_phase_time = 0.0
		Phase.STRIKE:
			target_pos = _final_pos
			target_rot = _final_rot
			_phase_time += delta
			if _phase_time >= player.strike_time:
				_phase = Phase.HOLD
				_phase_time = 0.0
		Phase.HOLD:
			target_pos = _final_pos
			target_rot = _final_rot
			_phase_time += delta
			if _phase_time >= player.hold_time:
				_phase = Phase.IDLE
				_phase_time = 0.0
	var damping_ratio: float = clampf(1.0 - player.swing_bounce, 0.05, 2.0)
	_pos_spring.step(target_pos, player.swing_frequency, damping_ratio, delta)
	_rot_spring.step(target_rot, player.swing_frequency, damping_ratio, delta)
	weapon_pivot.position = _pos_spring.value
	weapon_pivot.rotation = _rot_spring.value
