extends CanvasLayer
## Local-only HUD. Listens to the Radar autoload for pings and draws them
## as fading blips around a center reticle, positioned by bearing relative
## to the bound player's forward vector. Also shows health and the bound
## player's own Ignite stacks (in case you set enemies up to ignite players too).

const BLIP_LIFETIME := 2.5
const RADAR_RADIUS := 90.0

@onready var health_bar: ProgressBar = $Root/HealthBar
@onready var health_label: Label = $Root/HealthLabel
@onready var radar_display: Control = $Root/RadarDisplay
@onready var death_label: Label = $Root/DeathLabel
@onready var ignite_label: Label = $Root/IgniteLabel
@onready var settings_panel: Panel = $Root/SettingsPanel
@onready var res_option: OptionButton = $Root/SettingsPanel/SettingsVBox/ResHBox/ResOption
@onready var vsync_check: CheckButton = $Root/SettingsPanel/SettingsVBox/VsyncHBox/VsyncCheck
@onready var hitbox_check: CheckButton = $Root/SettingsPanel/SettingsVBox/HitboxHBox/HitboxCheck
@onready var impact_check: CheckButton = $Root/SettingsPanel/SettingsVBox/ImpactHBox/ImpactCheck
@onready var resume_btn: Button = $Root/SettingsPanel/SettingsVBox/ResumeButton
@onready var quit_btn: Button = $Root/SettingsPanel/SettingsVBox/QuitButton

var _player: Node3D = null
var _blips: Array = []
var _settings_open: bool = false

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

func _ready() -> void:
	death_label.visible = false
	Radar.ping_received.connect(_on_ping_received)
	_populate_resolutions()
	vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	vsync_check.toggled.connect(_on_vsync_toggled)
	hitbox_check.toggled.connect(_on_hitbox_toggled)
	impact_check.toggled.connect(_on_impact_toggled)
	resume_btn.pressed.connect(_on_resume_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	set_process(true)


func toggle_settings() -> void:
	_settings_open = not _settings_open
	settings_panel.visible = _settings_open
	if _settings_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func are_settings_open() -> bool:
	return _settings_open


func _populate_resolutions() -> void:
	var current_size: Vector2i = DisplayServer.window_get_size()
	for i: int in range(RESOLUTIONS.size()):
		var res: Vector2i = RESOLUTIONS[i]
		res_option.add_item("%dx%d" % [res.x, res.y])
		if res == current_size:
			res_option.select(i)
	res_option.item_selected.connect(_on_resolution_changed)


func _on_resolution_changed(idx: int) -> void:
	if idx >= 0 and idx < RESOLUTIONS.size():
		var size: Vector2i = RESOLUTIONS[idx]
		DisplayServer.window_set_size(size)


func _on_resume_pressed() -> void:
	toggle_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_vsync_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _on_hitbox_toggled(enabled: bool) -> void:
	DebugShapes.set_visible(enabled)


func _on_impact_toggled(enabled: bool) -> void:
	DebugShapes.set_impacts_visible(enabled)

func bind_player(player: Node3D) -> void:
	_player = player
	update_health(player.health, player.max_health)


func update_health(current: float, max_h: float) -> void:
	health_bar.max_value = max_h
	health_bar.value = current
	health_label.text = "HP %d / %d" % [int(current), int(max_h)]


func show_death() -> void:
	death_label.visible = true


func _on_ping_received(world_pos: Vector3, tag: String, strength: float) -> void:
	if _player == null:
		return
	var to_ping := world_pos - _player.global_position
	var dist := to_ping.length()
	if dist > strength:
		return # out of hearing range for this ping's loudness
	var forward := -_player.global_transform.basis.z
	forward.y = 0
	to_ping.y = 0
	forward = forward.normalized()
	to_ping = to_ping.normalized() if to_ping.length() > 0.01 else forward
	var angle := forward.signed_angle_to(to_ping, Vector3.UP)
	_blips.append({"angle": angle, "dist": dist, "tag": tag, "life": BLIP_LIFETIME})
	radar_display.queue_redraw()


func _process(delta: float) -> void:
	var changed := false
	for b in _blips:
		b["life"] -= delta
	var before := _blips.size()
	_blips = _blips.filter(func(b): return b["life"] > 0.0)
	if _blips.size() != before:
		changed = true
	if changed:
		radar_display.queue_redraw()
	if is_instance_valid(_player) and _player.get("stacks") != null:
		pass # placeholder if you later expose player ignite stacks in the HUD


func get_blips() -> Array:
	return _blips
