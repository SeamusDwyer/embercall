extends Node
## GameState — agent harness singleton.
## Programmatic read/write access to game state for testing and automation.
## Mirrors state from other systems; does not own authoritative game data.

# -- Snapshot signals (emitted when polled state changes) --

signal player_spawned(pid: int)
signal player_health_changed(pid: int, new_health: float, old_health: float)
signal player_died(pid: int)
signal player_entered_airlock(pid: int)
signal player_exited_airlock(pid: int)

signal enemy_spawned(enemy_name: String, enemy_type: String)
signal enemy_health_changed(enemy_name: String, new_health: float, old_health: float)
signal enemy_died(enemy_name: String)

signal room_cleared(room_id: String)
signal room_selected(room_id: String)
signal room_choices_available(choices: Array)
signal act_changed(act_num: int)
signal run_started(acts: Array)
signal run_complete()

signal ignite_applied(target: String, target_id: String, stacks: int)
signal ignite_extinguished(target: String, target_id: String)
signal ping_emitted(world_pos: Vector3, tag: String, strength: float)

signal exit_unlocked()
signal exit_triggered()

# -- Internal bookkeeping --

var _previous_snapshot: Dictionary = {}
var _arena: Node3D = null
var _tracked_enemies: Dictionary = {}  # enemy_name -> WeakRef
var _hooked_players: Dictionary = {}  # pid -> true
var _hooked_enemies: Dictionary = {}  # ename -> true
var _run_started: bool = false


func _ready() -> void:
	Radar.ping_received.connect(_on_radar_ping)
	RoomManager.room_cleared.connect(_on_room_cleared)
	RoomManager.room_selected.connect(_on_room_selected)
	RoomManager.run_complete.connect(_on_run_complete)
	Net.player_list_changed.connect(_on_player_list_changed)

	_connect_arena.call_deferred()


# -- Snapshot --

func get_snapshot() -> Dictionary:
	_ensure_arena()

	var snapshot := {
		"run": _snapshot_run(),
		"arena": _snapshot_arena(),
		"players": _snapshot_players(),
		"enemies": _snapshot_enemies(),
		"net": _snapshot_net(),
		"radar": _snapshot_radar(),
	}
	_diff_and_emit(snapshot)
	_previous_snapshot = snapshot
	return snapshot


func _snapshot_run() -> Dictionary:
	return {
		"act": RoomManager.current_act,
		"floor": RoomManager.current_floor,
		"room_id": RoomManager.current_room_id,
		"room_type": _current_room_type(),
		"run_complete": false
	}


func _snapshot_arena() -> Dictionary:
	if _arena == null:
		return {}
	var alive := 0
	var total := 0
	for ename in _tracked_enemies:
		var ref: WeakRef = _tracked_enemies[ename]
		var enemy: Enemy = ref.get_ref() as Enemy if ref else null
		if enemy:
			total += 1
			if not enemy._dead:
				alive += 1
	return {
		"enemies_alive": alive,
		"enemies_total": total,
		"room_cleared": _arena.get("_room_cleared") if _arena else false,
		"exit_unlocked": _arena.is_exit_unlocked() if _arena.has_method("is_exit_unlocked") else false
	}


func _snapshot_players() -> Dictionary:
	var players := {}
	for pid in Net.players:
		var p: CharacterBody3D = Net.players[pid]
		if not is_instance_valid(p):
			continue
		var ignite := p.get_node_or_null("IgniteStatus") as IgniteStatus
		players[str(pid)] = {
			"id": pid,
			"pos": _vec3_to_dict(p.global_position),
			"health": p.health,
			"max_health": p.max_health,
			"is_burning": ignite.is_burning if ignite else false,
			"ignite_stacks": ignite.stacks if ignite else 0,
			"is_autopilot": p.autopilot,
			"is_dead": false
		}
	return players


func _snapshot_enemies() -> Dictionary:
	var enemies := {}
	for ename in _tracked_enemies:
		var ref: WeakRef = _tracked_enemies[ename]
		var enemy: Enemy = ref.get_ref() as Enemy if ref else null
		if not enemy:
			_tracked_enemies.erase(ename)
			continue
		var ignite := enemy.get_node_or_null("IgniteStatus") as IgniteStatus
		enemies[ename] = {
			"name": ename,
			"type": enemy.encounter_name,
			"pos": _vec3_to_dict(enemy.global_position),
			"health": enemy.health,
			"max_health": enemy.max_health,
			"is_burning": ignite.is_burning if ignite else false,
			"ignite_stacks": ignite.stacks if ignite else 0,
			"is_dead": enemy._dead
		}
	return enemies


func _snapshot_net() -> Dictionary:
	return {
		"peer_count": Net.players.size(),
		"host_id": 1
	}


func _snapshot_radar() -> Dictionary:
	return {}


# -- Diff engine (emits signals on state changes) --

func _diff_and_emit(current: Dictionary) -> void:
	if _previous_snapshot.is_empty():
		return

	var prev_run: Dictionary = _previous_snapshot.get("run", {})
	var curr_run: Dictionary = current.get("run", {})
	if curr_run.get("act", 0) != prev_run.get("act", 0):
		act_changed.emit(curr_run["act"])

	var prev_arena: Dictionary = _previous_snapshot.get("arena", {})
	var curr_arena: Dictionary = current.get("arena", {})
	if not prev_arena.get("exit_unlocked", false) and curr_arena.get("exit_unlocked", false):
		exit_unlocked.emit()

	var prev_players: Dictionary = _previous_snapshot.get("players", {})
	var curr_players: Dictionary = current.get("players", {})
	for pid_str in curr_players:
		var pid := int(pid_str)
		var cp: Dictionary = curr_players[pid_str]
		if not prev_players.has(pid_str):
			player_spawned.emit(pid)
			continue
		var pp: Dictionary = prev_players[pid_str]
		if cp.get("health", 0.0) < pp.get("health", 0.0):
			player_health_changed.emit(pid, cp["health"], pp["health"])
		if cp.get("is_dead", false) and not pp.get("is_dead", false):
			player_died.emit(pid)

	var prev_enemies: Dictionary = _previous_snapshot.get("enemies", {})
	var curr_enemies: Dictionary = current.get("enemies", {})
	for ename in curr_enemies:
		var ce: Dictionary = curr_enemies[ename]
		if not prev_enemies.has(ename):
			enemy_spawned.emit(ename, ce.get("type", ""))
			continue
		var pe: Dictionary = prev_enemies[ename]
		if ce.get("health", 0.0) < pe.get("health", 0.0):
			enemy_health_changed.emit(ename, ce["health"], pe["health"])
		if ce.get("is_dead", false) and not pe.get("is_dead", false):
			enemy_died.emit(ename)


# -- Signal relay (autoload events → GameState signals) --

func _on_radar_ping(world_pos: Vector3, tag: String, strength: float) -> void:
	ping_emitted.emit(world_pos, tag, strength)


func _on_room_cleared(room_id: String) -> void:
	var choices := RoomManager.get_available_choices()
	room_cleared.emit(room_id)
	if not choices.is_empty():
		room_choices_available.emit(choices)


func _on_room_selected(room_id: String) -> void:
	room_selected.emit(room_id)


func _on_run_complete() -> void:
	run_complete.emit()


func _on_player_list_changed() -> void:
	for pid in Net.players:
		if pid in _hooked_players:
			continue
		var p: CharacterBody3D = Net.players[pid]
		if not is_instance_valid(p):
			continue
		_hook_player(p, pid)


# -- Scene discovery --

func _connect_arena() -> void:
	var main := get_tree().get_root().get_node_or_null("Main")
	if not main:
		return
	_arena = main.get_node_or_null("Arena")
	if _arena == null:
		return
	if not _arena.exit_triggered.is_connected(_on_arena_exit):
		_arena.exit_triggered.connect(_on_arena_exit)
	if _arena.has_signal("enemy_spawned"):
		if not _arena.enemy_spawned.is_connected(_on_enemy_spawned):
			_arena.enemy_spawned.connect(_on_enemy_spawned)
		var enemies_root := _arena.get_node_or_null("Enemies")
		if enemies_root:
			for child in enemies_root.get_children():
				if child is Enemy:
					_hook_enemy(child)


func _ensure_arena() -> void:
	if _arena == null:
		_connect_arena()


func _get_arena() -> Node3D:
	_ensure_arena()
	return _arena


# -- Entity hook methods --

func _hook_player(player: Node, pid: int) -> void:
	if _hooked_players.has(pid):
		return
	_hooked_players[pid] = true

	var health_node := player.get_node_or_null("PlayerHealth")
	if health_node and health_node is PlayerHealth:
		if health_node.has_signal("health_changed"):
			health_node.health_changed.connect(_on_player_hp_changed.bind(pid))
		if health_node.has_signal("died"):
			health_node.died.connect(_on_player_died_signal.bind(pid))

	var ignite := player.get_node_or_null("IgniteStatus") as IgniteStatus
	if ignite:
		ignite.ignited.connect(_on_entity_ignited.bind("player", str(pid)))
		ignite.extinguished.connect(_on_entity_extinguished.bind("player", str(pid)))


func _hook_enemy(enemy: Enemy) -> void:
	var ename := enemy.name
	if _hooked_enemies.has(ename):
		return
	_hooked_enemies[ename] = true
	_tracked_enemies[ename] = weakref(enemy)

	var health_node := enemy.get_node_or_null("EnemyHealth")
	if health_node and health_node is EnemyHealth:
		if health_node.has_signal("health_changed"):
			health_node.health_changed.connect(_on_enemy_hp_changed.bind(ename))

	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died_signal.bind(ename))

	var ignite := enemy.get_node_or_null("IgniteStatus") as IgniteStatus
	if ignite:
		ignite.ignited.connect(_on_entity_ignited.bind("enemy", ename))
		ignite.extinguished.connect(_on_entity_extinguished.bind("enemy", ename))


# -- Signal handlers for hooked entities --

func _on_player_hp_changed(new_health: float, old_health: float, pid: int) -> void:
	player_health_changed.emit(pid, new_health, old_health)


func _on_player_died_signal(pid: int) -> void:
	player_died.emit(pid)


func _on_enemy_spawned(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	_hook_enemy(enemy)
	enemy_spawned.emit(enemy.name, enemy.encounter_name)


func _on_enemy_hp_changed(new_health: float, old_health: float, ename: String) -> void:
	enemy_health_changed.emit(ename, new_health, old_health)


func _on_enemy_died_signal(ename: String) -> void:
	enemy_died.emit(ename)


func _on_arena_exit() -> void:
	exit_triggered.emit()


func _on_entity_ignited(kind: String, target_id: String) -> void:
	var ignite_node: IgniteStatus = null
	if kind == "player":
		var pid := int(target_id)
		var player: CharacterBody3D = Net.players.get(pid)
		if player:
			ignite_node = player.get_node_or_null("IgniteStatus") as IgniteStatus
	elif kind == "enemy":
		var ref: WeakRef = _tracked_enemies.get(target_id)
		if ref:
			var enemy: Enemy = ref.get_ref() as Enemy
			if enemy:
				ignite_node = enemy.get_node_or_null("IgniteStatus") as IgniteStatus
	var stacks := ignite_node.stacks if ignite_node else 0
	ignite_applied.emit(kind, target_id, stacks)


func _on_entity_extinguished(kind: String, target_id: String) -> void:
	ignite_extinguished.emit(kind, target_id)


# -- Commands --

func command_move_to(pid: int, target: Vector3) -> void:
	var player: CharacterBody3D = Net.players.get(pid) as CharacterBody3D
	if not is_instance_valid(player) or not player.autopilot:
		return
	var to_target: Vector3 = target - player.global_position
	to_target.y = 0.0
	player.scripted_move_dir = to_target.normalized() if to_target.length() > 0.1 else Vector3.ZERO
	player.look_at(Vector3(target.x, player.global_position.y, target.z), Vector3.UP)


func command_stop(pid: int) -> void:
	var player: CharacterBody3D = Net.players.get(pid) as CharacterBody3D
	if not is_instance_valid(player):
		return
	player.scripted_move_dir = Vector3.ZERO


func command_attack(pid: int) -> void:
	var player: CharacterBody3D = Net.players.get(pid) as CharacterBody3D
	if not is_instance_valid(player):
		return
	player.scripted_attack_requested = true


func command_look_at(pid: int, target: Vector3) -> void:
	var player: CharacterBody3D = Net.players.get(pid) as CharacterBody3D
	if not is_instance_valid(player):
		return
	player.look_at(Vector3(target.x, player.global_position.y, target.z), Vector3.UP)


func command_select_room(room_id: String) -> void:
	RoomManager.request_select_room(room_id)


# -- Queries --

func get_player(pid: int) -> Dictionary:
	var snap := get_snapshot()
	var players: Dictionary = snap.get("players", {})
	return players.get(str(pid), {})


func get_enemy(ename: String) -> Dictionary:
	var snap := get_snapshot()
	var enemies: Dictionary = snap.get("enemies", {})
	return enemies.get(ename, {})


func get_nearest_enemy(pos: Vector3) -> Dictionary:
	var best_name := ""
	var best_dist := INF
	var snap := get_snapshot()
	var enemies: Dictionary = snap.get("enemies", {})
	for ename in enemies:
		var e: Dictionary = enemies[ename]
		if e.get("is_dead", true):
			continue
		var epos := Vector3(e["pos"]["x"], e["pos"]["y"], e["pos"]["z"])
		var d := pos.distance_to(epos)
		if d < best_dist:
			best_dist = d
			best_name = ename
	if best_name == "":
		return {}
	return enemies[best_name]


func get_all_players() -> Array[Dictionary]:
	var snap := get_snapshot()
	var result: Array[Dictionary] = []
	var players: Dictionary = snap.get("players", {})
	for pid_str in players:
		result.append(players[pid_str])
	return result


func get_all_enemies() -> Array[Dictionary]:
	var snap := get_snapshot()
	var result: Array[Dictionary] = []
	var enemies: Dictionary = snap.get("enemies", {})
	for ename in enemies:
		result.append(enemies[ename])
	return result


func are_all_enemies_dead() -> bool:
	var snap := get_snapshot()
	var enemies: Dictionary = snap.get("enemies", {})
	for ename in enemies:
		if not enemies[ename].get("is_dead", true):
			return false
	return enemies.size() > 0


func is_exit_unlocked() -> bool:
	var arena := _get_arena()
	if arena and arena.has_method("is_exit_unlocked"):
		return arena.is_exit_unlocked()
	return false


func get_available_choices() -> Array:
	return RoomManager.get_available_choices()


func get_current_room() -> Dictionary:
	return RoomManager.get_current_room()


func is_run_started() -> bool:
	return _run_started


# -- Helpers --

func _current_room_type() -> int:
	var room := RoomManager.get_current_room()
	return room.get("type", -1)


func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


static func dict_to_vec3(d: Dictionary) -> Vector3:
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))
