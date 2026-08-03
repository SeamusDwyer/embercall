extends Node
## Root scene script. Shows a minimal host/join panel; hides it once a
## multiplayer session starts. This is intentionally bare-bones for the
## vertical slice - swap for a real menu once the core loop is fun.

const AUTOPILOT_SCENE := preload("res://tests/Autopilot.gd")

@onready var menu: Control = $UI/MenuPanel
@onready var ip_field: LineEdit = $UI/MenuPanel/VBox/IPField
@onready var host_btn: Button = $UI/MenuPanel/VBox/HostButton
@onready var join_btn: Button = $UI/MenuPanel/VBox/JoinButton
@onready var status_label: Label = $UI/MenuPanel/VBox/StatusLabel

func _ready() -> void:
	var args := OS.get_cmdline_args()
	print("[MAIN] cmdline_args: ", args)
	if _has_arg(args, "--autopilot"):
		_start_autopilot()
		return
	if _has_arg(args, "--autojoin"):
		_start_autojoin(args)
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


func _start_autopilot() -> void:
	menu.visible = false
	Net.host_game()
	print("[AUTOPILOT] hosted game, connecting player_list_changed signal")
	Net.player_list_changed.connect(_on_autopilot_player_spawned)
	# In case the player was already spawned synchronously
	if Net.players.size() > 0:
		print("[AUTOPILOT] player already spawned")
		_on_autopilot_player_spawned()


func _on_autopilot_player_spawned() -> void:
	print("[AUTOPILOT] player_list_changed, players.size()=%d" % Net.players.size())
	if Net.players.size() == 0:
		return
	var pid: int = Net.players.keys()[0]
	var player = Net.players[pid]
	player.autopilot = true
	print("[AUTOPILOT] player=%s, arena=%s" % [player, $Arena])

	var autopilot: Node = AUTOPILOT_SCENE.new()
	autopilot.name = "Autopilot"
	add_child.call_deferred(autopilot)
	autopilot.setup(player, $Arena)
	print("[AUTOPILOT] autopilot setup complete")

	Net.player_list_changed.disconnect(_on_autopilot_player_spawned)


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
	print("[AUTOJOIN] connecting to %s" % addr)
	Net.join_game(addr)
	multiplayer.server_disconnected.connect(_on_autojoin_server_disconnected)
	multiplayer.connection_failed.connect(_on_autojoin_connection_failed)
	# Timeout: if no connection within 20s, fail
	get_tree().create_timer(20.0).timeout.connect(_on_autojoin_timeout)


func _on_autojoin_server_disconnected() -> void:
	print("TEST_RESULT: PASS (autojoin peer disconnected cleanly after host quit)")
	get_tree().quit(0)


func _on_autojoin_connection_failed() -> void:
	print("TEST_RESULT: FAIL: connection failed")
	get_tree().quit(1)


func _on_autojoin_timeout() -> void:
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
