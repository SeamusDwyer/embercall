extends Node
class_name IgniteStatus
## The synergy/status system for the slice: Ignite.
## Attach this as a child node to anything that can burn (Player, Enemy,
## Flammable prop). It is a world-state effect, not just a personal debuff:
## it ticks damage, pings the Radar (fire crackles are loud), and can spread
## to nearby Flammable nodes, which is what makes it bridge combat and
## environment rather than being a pure character stat.
##
## Server-authoritative: only runs its tick logic on the server; state is
## replicated to clients via the two exported vars below through a
## MultiplayerSynchronizer on the parent scene (see Enemy.tscn / Player.tscn).

@export var stacks: int = 0
@export var is_burning: bool = false

const MAX_STACKS := 5
const DAMAGE_PER_TICK := 2.0
const TICK_INTERVAL := 1.0
const STACK_DURATION := 4.0 # seconds added to burn timer per stack applied
const SPREAD_RADIUS := 3.0

var _burn_timer: float = 0.0
var _tick_timer: float = 0.0

signal ignited
signal extinguished
signal ticked(damage: float)

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if not multiplayer.multiplayer_peer:
		return
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_process(delta)

func _server_process(delta: float) -> void:
	if not is_burning:
		return
	_burn_timer -= delta
	_tick_timer -= delta

	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		var dmg := DAMAGE_PER_TICK * stacks
		ticked.emit(dmg)
		var owner_node := get_parent()
		if owner_node.has_method("take_damage"):
			owner_node.take_damage(dmg)
		Radar.emit_ping(owner_node.global_position, "burning", 8.0)
		_try_spread()

	if _burn_timer <= 0.0:
		_extinguish()

## Call from any authority-checked source (melee hit, fire prop, another
## burning entity in range) to apply or refresh Ignite stacks.
func apply_stacks(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var was_burning := is_burning
	stacks = clamp(stacks + amount, 0, MAX_STACKS)
	_burn_timer = max(_burn_timer, 0.0) + STACK_DURATION
	is_burning = true
	if not was_burning:
		ignited.emit()
		Radar.emit_ping(get_parent().global_position, "ignite_whoosh", 10.0)

func _extinguish() -> void:
	is_burning = false
	stacks = 0
	_burn_timer = 0.0
	extinguished.emit()

func _try_spread() -> void:
	var owner_node: Node3D = get_parent()
	var space: PhysicsDirectSpaceState3D = owner_node.get_world_3d().direct_space_state
	# Simple radius query using physics overlap on a temp shape.
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = SPREAD_RADIUS
	params.shape = shape
	params.transform = Transform3D(Basis(), owner_node.global_position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits: Array[Dictionary] = space.intersect_shape(params, 8)
	for hit in hits:
		var collider = hit.get("collider")
		if collider == null or collider == owner_node:
			continue
		var other_ignite = collider.get_node_or_null("IgniteStatus")
		if other_ignite and other_ignite is IgniteStatus and not other_ignite.is_burning:
			other_ignite.apply_stacks(1)
