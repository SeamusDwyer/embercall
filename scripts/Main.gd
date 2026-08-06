extends Node
## Root scene script. Hosts/joins games, manages room progression,
## and wires the Arena to the RoomManager for the roguelike loop.

const AUTOPILOT_SCENE := preload("res://tests/Autopilot.gd")

@onready var menu: Control = $UI/MenuPanel
@onready var ip_field: LineEdit = $UI/MenuPanel/VBox/IPField
@onready var host_btn: Button = $UI/MenuPanel/VBox/HostButton
@onready var join_btn: Button = $UI/MenuPanel/VBox/JoinButton
@onready var status_label: Label = $UI/MenuPanel/VBox/StatusLabel
@onready var arena: Node3D = $Arena

var _run_started := false
var _autopilot: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_args()
	if _has_arg(args, "--autopilot"):
		_start_autopilot()
		return
	if _has_arg(args, "--autojoin"):
		_start_autojoin(args)
		return
	if _has_arg(args, "--steam-host"):
		_start_steam_host()
		return
	if _has_arg(args, "--steam-join"):
		_start_steam_join(args)
		return

	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	Net.player_list_changed.connect(_on_player_list_changed)


func _has_arg(args: Array, prefix: String) -> bool:
	for arg in args:
		var s: String = str(arg)
		if s == prefix or s.begins_with(prefix + "="):
			return true
	return false


func _get_arg_value(args: Array, prefix: String) -> String:
	for arg in args:
		var s: String = str(arg)
		if s.begins_with(prefix + "="):
			return s.trim_prefix(prefix + "=")
		elif s == prefix:
			var idx: int = args.find(s)
			if idx >= 0 and idx + 1 < args.size():
				return str(args[idx + 1])
	return ""


func _start_run() -> void:
	if _run_started:
		return
	_run_started = true

	RoomManager.start_run()
	if not arena.exit_triggered.is_connected(_on_arena_exit):
		arena.exit_triggered.connect(_on_arena_exit)
	RoomManager.run_complete.connect(_on_run_complete)

	var first_room := RoomManager.begin_first_room()
	if not first_room.is_empty():
		arena.configure(first_room)


func _on_arena_exit() -> void:
	if is_instance_valid(_autopilot):
		_autopilot.notify_exit_fired()

	if RoomManager.get_available_choices().is_empty():
		var act_room := RoomManager.start_next_act()
		if act_room.is_empty():
			_on_run_complete()
			return
		arena.configure(act_room)
	else:
		var next_room := RoomManager.get_current_room()
		if not next_room.is_empty():
			arena.configure(next_room)


func _on_run_complete() -> void:
	print("Run complete! All 3 acts cleared.")
	get_tree().paused = false


func _start_steam_host() -> void:
	menu.visible = false
	Net.host_game(Net.Transport.STEAM)
	status_label.text = "Hosting via Steam..."


func _start_steam_join(args: Array) -> void:
	menu.visible = false
	var lobby_id: String = _get_arg_value(args, "--steam-join")
	Net.join_game(lobby_id, Net.Transport.STEAM)
	status_label.text = "Joining Steam lobby %s..." % lobby_id


func _start_autopilot() -> void:
	menu.visible = false
	Net.host_game()
	Net.player_list_changed.connect(_on_autopilot_player_spawned)
	if Net.players.size() > 0:
		_on_autopilot_player_spawned()


func _on_autopilot_player_spawned() -> void:
	if Net.players.size() == 0:
		return
	var pid: int = Net.players.keys()[0]
	var player = Net.players[pid]
	player.autopilot = true

	_ensure_run_started()

	var autopilot: Node = AUTOPILOT_SCENE.new()
	autopilot.name = "Autopilot"
	_autopilot = autopilot
	add_child.call_deferred(autopilot)
	autopilot.setup(player, arena)

	Net.player_list_changed.disconnect(_on_autopilot_player_spawned)


func _ensure_run_started() -> void:
	if _run_started:
		return
	RoomManager.start_run()
	if not arena.exit_triggered.is_connected(_on_arena_exit):
		arena.exit_triggered.connect(_on_arena_exit)
	RoomManager.run_complete.connect(_on_run_complete)
	var first_room := RoomManager.begin_first_room()
	if not first_room.is_empty():
		arena.configure(first_room)
	_run_started = true


func _start_autojoin(args: Array) -> void:
	menu.visible = false
	Net._suppress_reload = true
	var addr := "127.0.0.1"
	for i in range(args.size()):
		var arg: String = str(args[i])
		var stripped: String = arg.lstrip("--autojoin=")
		if stripped != arg:
			addr = stripped
		elif arg == "--autojoin" and i + 1 < args.size():
			addr = str(args[i + 1])
	Net.join_game(addr)
	multiplayer.server_disconnected.connect(_on_autojoin_server_disconnected)
	multiplayer.connection_failed.connect(_on_autojoin_connection_failed)
	multiplayer.connected_to_server.connect(_on_autojoin_connected)
	var timeout_timer := get_tree().create_timer(20.0)
	timeout_timer.timeout.connect(_on_autojoin_timeout.bind(timeout_timer))


func _on_autojoin_connected() -> void:
	pass


func _on_autojoin_server_disconnected() -> void:
	print("TEST_RESULT: PASS (autojoin peer disconnected cleanly after host quit)")
	get_tree().quit(0)


func _on_autojoin_connection_failed() -> void:
	print("TEST_RESULT: FAIL: connection failed")
	get_tree().quit(1)


func _on_autojoin_timeout(timer: SceneTreeTimer) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	print("TEST_RESULT: FAIL: autojoin timeout waiting for host")
	get_tree().quit(1)


func _on_host_pressed() -> void:
	Net.host_game()
	status_label.text = "Hosting on port %d..." % Net.PORT
	menu.visible = false


func _on_join_pressed() -> void:
	var addr := ip_field.text.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	Net.join_game(addr)
	status_label.text = "Connecting to %s..." % addr
	menu.visible = false


func _on_player_list_changed() -> void:
	print("Players connected: ", Net.players.size())
	if multiplayer.is_server() and Net.players.size() > 0:
		_start_run()
