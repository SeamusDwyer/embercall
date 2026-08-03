extends Node
## Autoload singleton: "Radar"
## The perception mechanic for the slice: any sound-worthy event (footstep,
## swing, ignite-whoosh, enemy growl) is emitted here. The SERVER decides a
## ping happened and RPCs it to all clients as a world position + tag.
## Each client's HUD converts that into a bearing/distance blip relative to
## its own local camera - never into "is this enemy currently visible", so
## it stays a clean, non per-player-vision system that's easy to keep in
## sync across the authoritative server.

signal ping_received(world_pos: Vector3, tag: String, strength: float)

## Call this from server-authoritative code (Enemy AI, Flammable spread,
## or a player's authority-checked attack) whenever something should be audible.
## strength roughly maps to "how far away can this be heard" in meters.
func emit_ping(world_pos: Vector3, tag: String, strength: float = 12.0) -> void:
	if not multiplayer.is_server():
		return
	_broadcast_ping.rpc(world_pos, tag, strength)


@rpc("authority", "call_local", "reliable")
func _broadcast_ping(world_pos: Vector3, tag: String, strength: float) -> void:
	ping_received.emit(world_pos, tag, strength)
