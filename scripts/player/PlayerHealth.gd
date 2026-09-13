extends Node
class_name PlayerHealth
## Handles health, damage, and death. Reads/writes player.health/max_health.

signal health_changed(new_health: float, old_health: float)
signal died

var player: CharacterBody3D


func setup(p: CharacterBody3D) -> void:
	player = p


func take_damage(amount: float, reason: String = DamageLog.REASON_UNKNOWN, source: Node = null) -> void:
	if not multiplayer.is_server():
		return
	var old_health: float = player.health
	player.health = max(0.0, player.health - amount)
	health_changed.emit(player.health, old_health)
	player._sync_health.rpc(player.health, reason, _source_name(source), amount)
	if player.health <= 0.0:
		died.emit()
		player._on_death.rpc()


func sync_hp(new_hp: float, hud: CanvasLayer, reason: String = "", source_name: String = "", amount: float = 0.0) -> void:
	player.health = new_hp
	if hud:
		hud.update_health(player.health, player.max_health)
	if amount > 0.0 and reason != "":
		DamageLog.record(str(player.name), amount, reason, source_name, new_hp)


func _source_name(source: Node) -> String:
	if source == null or not is_instance_valid(source):
		return "-"
	return str(source.name)


func die(hud: CanvasLayer) -> void:
	player.set_physics_process(false)
	if hud:
		hud.show_death()
