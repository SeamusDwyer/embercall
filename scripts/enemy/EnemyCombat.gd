extends Node
class_name EnemyCombat
## Attack state machine (TELL → SWING → RECOVERY → IDLE) + spring-driven weapon
## swing using the same animation system as PlayerCombat: the current phase is
## replicated to every peer via Enemy.attack_phase, and each peer animates a
## WeaponPivot toward the swing ghost poses with a DampedSpring3D.
## Only the server advances the combat machine.

var enemy: Enemy

const DAMAGE := 10.0
const COOLDOWN := 1.2
const TELL_DURATION := 0.4
const SWING_DURATION := 0.2
## Max center-to-center distance a strike can land at, checked when the swing
## connects (the weapon visually reaches ~2.15 from the enemy's center).
const STRIKE_RANGE := 2.2

enum AttackPhase { IDLE, TELL, SWING, RECOVERY }
var phase: int = AttackPhase.IDLE
var cooldown_left: float = 0.0
var phase_timer: float = 0.0
var target: Node3D = null

var _pos_spring := DampedSpring3D.new()
var _rot_spring := DampedSpring3D.new()
var _rest_pos := Vector3.ZERO
var _rest_rot := Vector3.ZERO
var _anticipation_pos := Vector3.ZERO
var _anticipation_rot := Vector3.ZERO
var _final_pos := Vector3.ZERO
var _final_rot := Vector3.ZERO


func setup(e: Enemy) -> void:
	enemy = e
	_resolve_swing_poses()


func can_attack() -> bool:
	return phase == AttackPhase.IDLE and cooldown_left <= 0.0


## True if `tgt` is alive and within the enemy's melee range, checked before a
## wind-up starts. Enemies never begin an attack against a target that is out of
## range.
func _target_in_attack_range(tgt: Node3D) -> bool:
	if tgt == null or not is_instance_valid(tgt):
		return false
	return _horizontal_distance(tgt) <= enemy.attack_range


## True if `tgt` is a valid damageable node still within reach when the swing
## connects. Prevents locked-on attacks from hitting players who dodged away
## during the TELL wind-up.
func _target_in_range(tgt: Node3D) -> bool:
	if tgt == null or not is_instance_valid(tgt) or not tgt.has_method("take_damage"):
		return false
	return _horizontal_distance(tgt) <= STRIKE_RANGE


func _horizontal_distance(tgt: Node3D) -> float:
	var to := tgt.global_position - enemy.global_position
	to.y = 0.0
	return to.length()


func _resolve_swing_poses() -> void:
	if not enemy.weapon_pivot:
		return
	_rest_pos = enemy.weapon_pivot.position
	_rest_rot = enemy.weapon_pivot.rotation
	_pos_spring.reset(_rest_pos)
	_rot_spring.reset(_rest_rot)

	var anticipation := enemy.get_node_or_null("Swings/Swing1/Anticipation") as Node3D
	var final := enemy.get_node_or_null("Swings/Swing1/Final") as Node3D
	if anticipation == null or final == null:
		return
	var a := _pose_in_pivot_space(anticipation)
	var f := _pose_in_pivot_space(final)
	_anticipation_pos = _rest_pos + (a.origin - _rest_pos) * enemy.swing_amplitude
	_anticipation_rot = _rest_rot + (a.basis.get_euler() - _rest_rot) * enemy.swing_amplitude
	_final_pos = _rest_pos + (f.origin - _rest_pos) * enemy.swing_amplitude
	_final_rot = _rest_rot + (f.basis.get_euler() - _rest_rot) * enemy.swing_amplitude


func _pose_in_pivot_space(pose: Node3D) -> Transform3D:
	var parent := enemy.weapon_pivot.get_parent() as Node3D
	if parent:
		return parent.global_transform.affine_inverse() * pose.global_transform
	return pose.transform


func process_attack(delta: float, tgt: Node3D) -> void:
	cooldown_left = max(cooldown_left - delta, 0.0)

	match phase:
		AttackPhase.IDLE:
			if cooldown_left <= 0.0 and _target_in_attack_range(tgt):
				phase = AttackPhase.TELL
				phase_timer = TELL_DURATION
				target = tgt
				enemy.attack_phase = phase
				enemy._tell_attack.rpc()

		AttackPhase.TELL:
			phase_timer -= delta
			if phase_timer <= 0.0:
				phase = AttackPhase.SWING
				phase_timer = SWING_DURATION
				enemy.attack_phase = phase
				if _target_in_range(target):
					target.take_damage(DAMAGE, DamageLog.REASON_ENEMY_MELEE, enemy)
					Radar.emit_ping(enemy.global_position, "attack", 8.0)
					enemy._spawn_hit_impact.rpc(target.global_position)
				enemy._flash_attack.rpc()
				cooldown_left = COOLDOWN

		AttackPhase.SWING:
			phase_timer -= delta
			if phase_timer <= 0.0:
				phase = AttackPhase.RECOVERY
				enemy.attack_phase = phase

		AttackPhase.RECOVERY:
			if cooldown_left <= 0.0:
				phase = AttackPhase.IDLE
				enemy.attack_phase = phase


func process_animation(delta: float) -> void:
	if not enemy.weapon_pivot:
		return
	var target_pos := _rest_pos
	var target_rot := _rest_rot
	match enemy.attack_phase:
		AttackPhase.TELL:
			target_pos = _anticipation_pos
			target_rot = _anticipation_rot
		AttackPhase.SWING:
			target_pos = _final_pos
			target_rot = _final_rot
	var damping_ratio: float = clampf(1.0 - enemy.swing_bounce, 0.05, 2.0)
	_pos_spring.step(target_pos, enemy.swing_frequency, damping_ratio, delta)
	_rot_spring.step(target_rot, enemy.swing_frequency, damping_ratio, delta)
	enemy.weapon_pivot.position = _pos_spring.value
	enemy.weapon_pivot.rotation = _rot_spring.value
