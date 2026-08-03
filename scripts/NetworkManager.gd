extends Node
## Autoload singleton: "Net"
## Transport-agnostic network layer. Supports ENet and (when available) Steam.
## Handles hosting, joining, and spawning a Player scene per connected peer.
## The server is authoritative: it owns enemy AI, Ignite ticks, and Radar pings.

signal player_list_changed

const PORT := 8910
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const CONNECT_TIMEOUT := 10.0

enum Transport { ENET, STEAM }

var players := {} # peer_id -> Node3D (player instance)
var _transport: int = Transport.ENET
var _suppress_reload: bool = false
var _connection_timer: SceneTreeTimer

var player_spawn_points: Array[Vector3] = [
	Vector3(-2, 1, 0),
	Vector3(2, 1, 0),
	Vector3(0, 1, -2),
	Vector3(0, 1, 2),
]


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(transport: int = Transport.ENET) -> void:
	_transport = transport
	match transport:
		Transport.STEAM:
			_start_steam_host()
		_:
			_start_enet_host()


func join_game(address_or_lobby: String, transport: int = Transport.ENET) -> void:
	_transport = transport
	match transport:
		Transport.STEAM:
			_start_steam_client(address_or_lobby)
		_:
			_start_enet_client(address_or_lobby)


func is_steam_available() -> bool:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return false
	if not ClassDB.class_exists(&"Steam"):
		return false
	var steam: Object = Engine.get_singleton(&"Steam")
	return steam.steamInit()


# ---------------------------------------------------------------------------
# ENet transport
# ---------------------------------------------------------------------------

func _start_enet_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to host on port %d: %s" % [PORT, error_string(err)])
		return
	_apply_peer(peer)
	_spawn_player(multiplayer.get_unique_id())


func _start_enet_client(address: String) -> void:
	var addr := address.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, PORT)
	if err != OK:
		push_error("Failed to connect to %s: %s" % [addr, error_string(err)])
		return
	_apply_peer(peer)


# ---------------------------------------------------------------------------
# Steam transport
# ---------------------------------------------------------------------------

func _start_steam_host() -> void:
	if not is_steam_available():
		push_error("Steam not available, falling back to ENet")
		_start_enet_host()
		return
	# Lobby created externally — caller passes lobby_id via _bind_steam_lobby
	push_error("Steam host: call _bind_steam_lobby(lobby_id) after lobby is created")


func _bind_steam_lobby(lobby_id: int) -> void:
	var peer: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	peer.set("server_relay", true)
	var mp_peer: MultiplayerPeer = peer as MultiplayerPeer
	var err: Error = mp_peer.host_with_lobby(lobby_id)
	if err != OK:
		push_error("Failed to host Steam lobby: %s" % error_string(err))
		_start_enet_host()
		return
	_apply_peer(mp_peer)
	_spawn_player(multiplayer.get_unique_id())


func _join_steam_lobby(lobby_id: int) -> void:
	var peer: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	var mp_peer: MultiplayerPeer = peer as MultiplayerPeer
	var err: Error = mp_peer.connect_to_lobby(lobby_id)
	if err != OK:
		push_error("Failed to join Steam lobby %d: %s" % [lobby_id, error_string(err)])
		return
	_apply_peer(mp_peer)


func _start_steam_client(lobby_id_str: String) -> void:
	if not is_steam_available():
		push_error("Steam not available, falling back to ENet")
		_start_enet_client("127.0.0.1")
		return
	var lobby_id: int = lobby_id_str.to_int()
	if lobby_id <= 0:
		push_error("Invalid lobby ID: %s" % lobby_id_str)
		return
	_join_steam_lobby(lobby_id)


# ---------------------------------------------------------------------------
# Shared peer management
# ---------------------------------------------------------------------------

func _apply_peer(peer: MultiplayerPeer) -> void:
	_cancel_connect_timer()
	if not multiplayer.is_server():
		multiplayer.connected_to_server.connect(_on_connected_ok)
		multiplayer.connection_failed.connect(_on_connection_failed)
		_connection_timer = get_tree().create_timer(CONNECT_TIMEOUT)
		_connection_timer.timeout.connect(_on_connect_timeout)
	multiplayer.multiplayer_peer = peer


func _cancel_connect_timer() -> void:
	if _connection_timer:
		_connection_timer.timeout.disconnect(_on_connect_timeout)
		_connection_timer = null


func _on_connect_timeout() -> void:
	push_error("Connection timed out")
	_cleanup_connection()


func _cleanup_connection() -> void:
	_cancel_connect_timer()
	if multiplayer.has_multiplayer_peer():
		if multiplayer.connected_to_server.is_connected(_on_connected_ok):
			multiplayer.connected_to_server.disconnect(_on_connected_ok)
		if multiplayer.connection_failed.is_connected(_on_connection_failed):
			multiplayer.connection_failed.disconnect(_on_connection_failed)
		if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
			multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	multiplayer.multiplayer_peer = null


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		replay_state_to_peer(id)
		_spawn_player(id)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var node = players[id]
		if is_instance_valid(node):
			node.queue_free()
		players.erase(id)
		player_list_changed.emit()


func _on_connected_ok() -> void:
	pass


func _on_connection_failed() -> void:
	push_error("Connection failed")
	_cleanup_connection()


func _on_server_disconnected() -> void:
	if _suppress_reload:
		_cleanup_connection()
		return
	push_error("Server disconnected")
	_cleanup_connection()
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Player spawning
# ---------------------------------------------------------------------------

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var idx := players.size() % player_spawn_points.size()
	var spawn_pos := player_spawn_points[idx]
	_do_spawn_player.rpc(peer_id, spawn_pos)


@rpc("authority", "call_local", "reliable")
func _do_spawn_player(peer_id: int, spawn_pos: Vector3) -> void:
	var arena := get_tree().get_root().get_node_or_null("Main/Arena")
	print("[SPAWN] peer_id=%d, arena=%s" % [peer_id, arena])
	if arena == null:
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	arena.get_node("PlayerRoot").add_child(player)
	player.global_position = spawn_pos
	players[peer_id] = player
	print("[SPAWN] player=%s added, players=%d" % [player, players.size()])
	player_list_changed.emit()


# Replay existing state to a late-joining peer.
func replay_state_to_peer(peer_id: int) -> void:
	for existing_id in players:
		if existing_id == peer_id:
			continue
		var p: Node3D = players[existing_id]
		if not is_instance_valid(p):
			continue
		var pos: Vector3 = p.global_position if p.global_position != Vector3.ZERO else player_spawn_points[existing_id % player_spawn_points.size()]
		_do_spawn_player.rpc_id(peer_id, existing_id, pos)

	var arena := get_tree().get_root().get_node_or_null("Main/Arena")
	if arena and arena.has_method("_sync_arena_state"):
		arena._sync_arena_state.rpc_id(peer_id)
