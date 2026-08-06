extends Node
class_name EnemyCombat
## Attack state machine (TELL → SWING → RECOVERY → IDLE) + weapon animation.

var enemy: Enemy

const DAMAGE := 10.0
const COOLDOWN := 1.2
const TELL_DURATION := 0.4
const SWING_DURATION := 0.2

enum AttackPhase { IDLE, TELL, SWING, RECOVERY }
var phase: int = AttackPhase.IDLE
var cooldown_left: float = 0.0
var phase_timer: float = 0.0
var target: Node3D = null


func setup(e: Enemy) -> void:
	enemy = e


func can_attack() -> bool:
	return phase == AttackPhase.IDLE and cooldown_left <= 0.0


func process_attack(delta: float, tgt: Node3D) -> void:
	cooldown_left = max(cooldown_left - delta, 0.0)

	match phase:
		AttackPhase.IDLE:
			if cooldown_left <= 0.0 and tgt != null:
				phase = AttackPhase.TELL
				phase_timer = TELL_DURATION
				target = tgt
				enemy._tell_attack.rpc()

		AttackPhase.TELL:
			phase_timer -= delta
			if phase_timer <= 0.0:
				phase = AttackPhase.SWING
				phase_timer = SWING_DURATION
				if target and is_instance_valid(target) and target.has_method("take_damage"):
					target.take_damage(DAMAGE)
				Radar.emit_ping(enemy.global_position, "attack", 8.0)
				if target and is_instance_valid(target):
					enemy._spawn_hit_impact.rpc(target.global_position)
				enemy._flash_attack.rpc()
				cooldown_left = COOLDOWN

		AttackPhase.SWING:
			phase_timer -= delta
			if phase_timer <= 0.0:
				phase = AttackPhase.RECOVERY

		AttackPhase.RECOVERY:
			if cooldown_left <= 0.0:
				phase = AttackPhase.IDLE


func process_animation(delta: float, weapon_mesh: MeshInstance3D) -> void:
	if not weapon_mesh:
		return
	match phase:
		AttackPhase.TELL:
			var t: float = 1.0 - (phase_timer / TELL_DURATION)
			weapon_mesh.position.z = -1.1 + t * 0.5
		AttackPhase.SWING:
			var t: float = 1.0 - (phase_timer / SWING_DURATION)
			weapon_mesh.position.z = -1.1 + 0.5 - (sin(t * PI) * 1.0)
		AttackPhase.RECOVERY:
			weapon_mesh.position.z = lerpf(weapon_mesh.position.z, -1.1, delta * 8.0)
		_:
			weapon_mesh.position.z = lerpf(weapon_mesh.position.z, -1.1, delta * 6.0)
