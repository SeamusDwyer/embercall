extends Node
## Manages Steam lobby lifecycle. Not an autoload — instantiated by Main.gd
## when Steam mode is active. Gracefully no-ops when Steam is unavailable.

signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int, owner_id: int)
signal lobby_error(message: String)

var _steam_available: bool = false
var _current_lobby_id: int = 0


func _init() -> void:
	if not ClassDB.class_exists(&"Steam"):
		return
	var steam: Object = Engine.get_singleton(&"Steam")
	_steam_available = steam.steamInit()
	if _steam_available:
		_connect_signals()


func _process(_delta: float) -> void:
	if _steam_available:
		var steam: Object = Engine.get_singleton(&"Steam")
		steam.run_callbacks()


func create_lobby(max_players: int) -> void:
	if not _steam_available:
		lobby_error.emit("Steam not available")
		return
	var steam: Object = Engine.get_singleton(&"Steam")
	steam.createLobby(steam.LOBBY_TYPE_FRIENDS_ONLY, max_players)


func join_lobby(lobby_id: int) -> void:
	if not _steam_available:
		lobby_error.emit("Steam not available")
		return
	var steam: Object = Engine.get_singleton(&"Steam")
	steam.joinLobby(lobby_id)


func leave_lobby() -> void:
	if _current_lobby_id > 0 and _steam_available:
		var steam: Object = Engine.get_singleton(&"Steam")
		steam.leaveLobby(_current_lobby_id)
		_current_lobby_id = 0


func open_invite_dialog() -> void:
	if _current_lobby_id > 0 and _steam_available:
		var steam: Object = Engine.get_singleton(&"Steam")
		steam.activateGameOverlayInviteDialog(_current_lobby_id)


func _connect_signals() -> void:
	var steam: Object = Engine.get_singleton(&"Steam")
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.join_requested.connect(_on_join_requested)


func _on_lobby_created(connect_result: int, lobby_id: int) -> void:
	if connect_result != 1:
		lobby_error.emit("Failed to create lobby: result=%d" % connect_result)
		return
	_current_lobby_id = lobby_id
	lobby_created.emit(lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, _response: int) -> void:
	_current_lobby_id = lobby_id
	var steam: Object = Engine.get_singleton(&"Steam")
	var owner_id: int = steam.getLobbyOwner(lobby_id)
	lobby_joined.emit(lobby_id, owner_id)


func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	print("Steam join requested for lobby %d" % lobby_id)
	var steam: Object = Engine.get_singleton(&"Steam")
	steam.joinLobby(lobby_id)
