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

var _player: Node3D = null
var _blips: Array = [] # each: {angle: float, dist: float, tag: String, life: float}

func _ready() -> void:
	death_label.visible = false
	Radar.ping_received.connect(_on_ping_received)
	set_process(true)

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
	if _player and _player.get("stacks") != null:
		pass # placeholder if you later expose player ignite stacks in the HUD


func get_blips() -> Array:
	return _blips
