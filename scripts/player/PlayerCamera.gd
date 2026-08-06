extends Node
class_name PlayerCamera
## Handles mouse capture, camera rotation, focus notifications, and settings toggle.

var player: CharacterBody3D
var pivot: Node3D
var camera: Camera3D

const SENSITIVITY := 0.0025

var _captured: bool = false


func setup(p: CharacterBody3D, piv: Node3D, cam: Camera3D) -> void:
	player = p
	pivot = piv
	camera = cam


func capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func is_captured() -> bool:
	return _captured


func handle_input(event: InputEvent, hud: CanvasLayer) -> void:
	if event is InputEventMouseMotion:
		player.rotate_y(-event.relative.x * SENSITIVITY)
		pivot.rotate_x(-event.relative.y * SENSITIVITY)
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	if event.is_action_pressed("ui_cancel"):
		if hud and hud.has_method("toggle_settings"):
			hud.toggle_settings()
			_captured = hud.are_settings_open() == false


func handle_notification(what: int, autopilot: bool) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not autopilot:
			capture()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_captured = false
