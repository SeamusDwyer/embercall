extends Node
class_name PlayerStamina
## Stamina for sprinting and melee swings. Lives on the authority peer only;
## reads/writes player.stamina/max_stamina and the exported drain/cost/regen
## tuning values on the Player.

var player: CharacterBody3D

var _exhausted: bool = false


func setup(p: CharacterBody3D) -> void:
	player = p


func can_sprint() -> bool:
	return not _exhausted and player.stamina > 0.0


func spend(amount: float) -> bool:
	if player.stamina < amount:
		return false
	player.stamina -= amount
	return true


func update(delta: float, sprinting: bool, moving: bool) -> void:
	if sprinting and moving:
		player.stamina = max(0.0, player.stamina - player.sprint_drain_per_second * delta)
		if player.stamina <= 0.0:
			_exhausted = true
	else:
		player.stamina = min(player.max_stamina, player.stamina + player.stamina_regen_per_second * delta)
		if _exhausted and player.stamina >= player.sprint_restart_threshold:
			_exhausted = false