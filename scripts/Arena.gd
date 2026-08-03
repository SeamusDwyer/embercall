extends Node3D
## Drives the one full loop for the vertical slice: players enter, an enemy
## is already present (or spawns after a short delay), killing it unlocks
## the ExitZone, walking into the ExitZone ends the run. Deliberately
## minimal - this is the seam where "next room" / meta-progression /
## choice-offer screens plug in later.

@onready var enemy: Enemy = $Enemies/Enemy
@onready var exit_zone: Area3D = $ExitZone
@onready var exit_vfx: GPUParticles3D = $ExitZone/ExitVFX

var _enemy_dead := false

func _ready() -> void:
	exit_zone.monitoring = false
	exit_vfx.emitting = false
	if enemy:
		enemy.died.connect(_on_enemy_died)
	exit_zone.body_entered.connect(_on_exit_entered)


func _on_enemy_died() -> void:
	_enemy_dead = true
	_unlock_exit.rpc()


@rpc("authority", "call_local", "reliable")
func _unlock_exit() -> void:
	exit_zone.monitoring = true
	exit_vfx.emitting = true


func _on_exit_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not _enemy_dead:
		return
	if body.is_in_group("player"):
		_run_complete.rpc()


@rpc("authority", "call_local", "reliable")
func _run_complete() -> void:
	print("Run complete! (MVP end state - wire up a restart/next-room screen here)")
	get_tree().paused = false
	# Simple MVP feedback: freeze the scene and let the player see the message.
	# Replace with your actual loop-exit UI once the core feel is validated.
