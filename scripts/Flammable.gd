extends Node3D
class_name FlammableProp
## Environmental half of the Ignite synergy. Attach to any prop (crate,
## dry pillar, oil puddle) that should catch fire and become a standing
## hazard. Uses the same IgniteStatus component as characters, so a burning
## enemy that stumbles near a FlammableProp lights it via the same
## apply_stacks/spread path - one system, two contexts.

@onready var ignite: IgniteStatus = $IgniteStatus
@onready var fire_vfx: GPUParticles3D = $FireVFX
@onready var hazard_area: Area3D = $HazardArea

func _ready() -> void:
	ignite.ignited.connect(_on_ignited)
	ignite.extinguished.connect(_on_extinguished)
	hazard_area.body_entered.connect(_on_hazard_body_entered)
	fire_vfx.emitting = false

func _on_ignited() -> void:
	fire_vfx.emitting = true

func _on_extinguished() -> void:
	fire_vfx.emitting = false

func _on_hazard_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not ignite.is_burning:
		return
	var other_ignite = body.get_node_or_null("IgniteStatus")
	if other_ignite and other_ignite is IgniteStatus:
		other_ignite.apply_stacks(1)
