extends Control
## Draws the audio-radar blips owned by the parent HUD. Kept as a separate
## Control so _draw() has a clean local origin at the radar widget's center.

const RADIUS := 70.0
const TAG_COLORS := {
	"footstep": Color(0.8, 0.8, 0.8, 1.0),
	"growl": Color(1.0, 0.2, 0.2, 1.0),
	"attack": Color(1.0, 0.4, 0.1, 1.0),
	"swing": Color(0.6, 0.9, 1.0, 1.0),
	"burning": Color(1.0, 0.6, 0.0, 1.0),
	"ignite_whoosh": Color(1.0, 0.8, 0.0, 1.0),
}

func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, RADIUS, Color(0, 0, 0, 0.25))
	draw_arc(center, RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.4), 1.5)
	# forward marker
	draw_line(center, center + Vector2(0, -RADIUS - 8), Color(1, 1, 1, 0.6), 2.0)

	var hud = get_parent()
	if hud == null or not hud.has_method("get_blips"):
		return
	for b in hud.get_blips():
		var angle: float = b["angle"]
		var dist: float = b["dist"]
		var life: float = b["life"]
		var tag: String = b["tag"]
		var norm_dist: float = clamp(dist / 16.0, 0.15, 1.0)
		var point := center + Vector2(sin(angle), -cos(angle)) * RADIUS * norm_dist
		var color: Color = TAG_COLORS.get(tag, Color.WHITE)
		color.a = clamp(life / 2.5, 0.0, 1.0)
		draw_circle(point, 5.0, color)
