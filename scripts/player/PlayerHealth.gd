extends Node
class_name PlayerHealth
## Handles health, damage, and death. Reads/writes player.health/max_health.

var player: CharacterBody3D


func setup(p: CharacterBody3D) -> void:
	player = p


func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	player.health = max(0.0, player.health - amount)
	player._sync_health.rpc(player.health)
	if player.health <= 0.0:
		player._on_death.rpc()


func sync_hp(new_hp: float, hud: CanvasLayer) -> void:
	player.health = new_hp
	if hud:
		hud.update_health(player.health, player.max_health)


func die(hud: CanvasLayer) -> void:
	player.set_physics_process(false)
	if hud:
		hud.show_death()
