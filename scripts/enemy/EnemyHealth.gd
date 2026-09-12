extends Node
class_name EnemyHealth
## Health, damage, death. Reads/writes enemy.health/max_health.

signal health_changed(new_health: float, old_health: float)

var enemy: Enemy

func setup(e: Enemy) -> void:
	enemy = e


func take_damage(amount: float) -> bool:
	if not multiplayer.is_server():
		return false
	if not is_instance_valid(enemy):
		return false
	var old_health := enemy.health
	enemy.health = max(0.0, enemy.health - amount)
	health_changed.emit(enemy.health, old_health)
	enemy._sync_health.rpc(enemy.health)
	if enemy.health <= 0.0:
		enemy._die.rpc()
		return true
	return false


func sync_hp(new_hp: float) -> void:
	enemy.health = new_hp


func apply_death_visuals() -> void:
	var col := enemy.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = true
	enemy.visible = false
