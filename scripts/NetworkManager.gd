extends Node
## Autoload singleton: "Net"
## Thin wrapper around Godot 4's high-level ENet multiplayer API.
## Handles hosting, joining, and spawning a Player scene per connected peer.
## The server is authoritative: it owns enemy AI, Ignite ticks, and Radar pings.
## Each client only has input-authority over its own Player node.

signal player_list_changed

const PORT := 8910
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/Player.tscn")

var players := {} # peer_id -> Node3D (player instance)
var player_spawn_points: Array[Vector3] = [
	Vector3(-2, 1, 0),
	Vector3(2, 1, 0),
	Vector3(0, 1, -2),
	Vector3(0, 1, 2),
]

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to host: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	# Host is always peer id 1 and spawns itself immediately (no "peer_connected" fires for self).
	_spawn_player(multiplayer.get_unique_id())


func join_game(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("Failed to join: %s" % err)
		return
	multiplayer.multiplayer_peer = peer


func _on_peer_connected(id: int) -> void:
	# Only the server decides spawn placement; it tells everyone via RPC.
	if multiplayer.is_server():
		_spawn_player(id)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var node = players[id]
		if is_instance_valid(node):
			node.queue_free()
		players.erase(id)
		player_list_changed.emit()


func _on_connected_ok() -> void:
	pass # server will spawn us via _spawn_player -> rpc


func _on_connection_failed() -> void:
	push_error("Connection failed")


func _on_server_disconnected() -> void:
	push_error("Server disconnected")
	get_tree().reload_current_scene()


func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var idx := players.size() % player_spawn_points.size()
	var spawn_pos := player_spawn_points[idx]
	_do_spawn_player.rpc(peer_id, spawn_pos)


@rpc("authority", "call_local", "reliable")
func _do_spawn_player(peer_id: int, spawn_pos: Vector3) -> void:
	var arena := get_tree().get_root().get_node_or_null("Main/Arena")
	if arena == null:
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	arena.get_node("PlayerRoot").add_child(player)
	player.global_position = spawn_pos
	players[peer_id] = player
	player_list_changed.emit()
