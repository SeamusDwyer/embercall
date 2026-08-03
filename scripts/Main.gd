extends Node
## Root scene script. Shows a minimal host/join panel; hides it once a
## multiplayer session starts. This is intentionally bare-bones for the
## vertical slice - swap for a real menu once the core loop is fun.

@onready var menu: Control = $UI/MenuPanel
@onready var ip_field: LineEdit = $UI/MenuPanel/VBox/IPField
@onready var host_btn: Button = $UI/MenuPanel/VBox/HostButton
@onready var join_btn: Button = $UI/MenuPanel/VBox/JoinButton
@onready var status_label: Label = $UI/MenuPanel/VBox/StatusLabel

func _ready() -> void:
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	Net.player_list_changed.connect(_on_player_list_changed)

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
