extends Node
class_name EnemyMovement
## Chase nearest player, gravity, knockback decay, growl pings.

var enemy: Enemy

const SPEED := 3.0
const ATTACK_RANGE := 1.6
const GROWL_INTERVAL := 4.0

var knockback_velocity: Vector3 = Vector3.ZERO
var _growl_timer: float = GROWL_INTERVAL


func setup(e: Enemy) -> void:
	enemy = e


func apply_physics(delta: float) -> Node3D:
	if knockback_velocity.length() > 0.1:
		enemy.velocity.x = knockback_velocity.x
		enemy.velocity.z = knockback_velocity.z
		knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 15.0 * delta)
		if not enemy.is_on_floor():
			enemy.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		enemy.move_and_slide()
		return null

	_growl_timer -= delta
	if _growl_timer <= 0.0:
		_growl_timer = GROWL_INTERVAL
		Radar.emit_ping(enemy.global_position, "growl", 14.0)

	var target := _find_nearest_player()
	if target == null:
		return null

	var to_target := target.global_position - enemy.global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist > ATTACK_RANGE:
		var dir := to_target.normalized()
		enemy.velocity.x = dir.x * SPEED
		enemy.velocity.z = dir.z * SPEED
		if not enemy.is_on_floor():
			enemy.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		enemy.look_at(Vector3(target.global_position.x, enemy.global_position.y, target.global_position.z), Vector3.UP)
		enemy.move_and_slide()

	return target


func apply_knockback(direction: Vector3, strength: float) -> void:
	knockback_velocity = direction * strength


func _find_nearest_player() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := INF
	for peer_id in Net.players:
		var p = Net.players[peer_id]
		if not is_instance_valid(p):
			continue
		var d := enemy.global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest
