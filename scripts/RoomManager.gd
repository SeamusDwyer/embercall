extends Node
## Autoload — manages act map generation, room state, run progression.
## Server-authoritative; clients receive state via RPC.
## Encounters are statically defined pools (similar to Slay the Spire).

enum RoomType { COMBAT, CHEST, EVENT, SHOP, BOSS }

const FLOORS_PER_ACT := 8
const MAX_ROOMS_PER_FLOOR := 3

## Chance an interior target inside a source room's contiguous range is kept.
## The first floor is always fully connected so the run starts with 2-3 choices.
const EDGE_DENSITY := 0.65

signal map_generated(act_data: Dictionary)
signal room_cleared(room_id: String)
signal room_selected(room_id: String)
signal run_complete()

var current_act := 0
var current_floor := 0
var current_room_id := ""
var acts: Array[Dictionary] = []
var _selections: Array[String] = []

const COMBAT_ENCOUNTERS: Array[String] = [
	"killer_toad",
	"haunted_rabbit",
	"ash_cultists",
	"ember_hounds",
	"shadow_duo"
]

const BOSS_ENCOUNTERS: Array[String] = [
	"pyroclastic_golem",
	"infernal_drake"
]

const ENCOUNTERS: Dictionary = {
	"killer_toad": {
		"id": "killer_toad",
		"name": "Killer Toad",
		"enemies": [
			{"name": "Killer Toad", "scale": Vector3(1.6, 1.2, 1.6), "hp": 80.0, "speed": 2.5, "color": Color(0.2, 0.7, 0.3), "pos": Vector3(0, 0.6, -5)}
		]
	},
	"haunted_rabbit": {
		"id": "haunted_rabbit",
		"name": "Haunted Rabbit",
		"enemies": [
			{"name": "Haunted Rabbit", "scale": Vector3(0.7, 0.7, 0.7), "hp": 45.0, "speed": 6.5, "color": Color(0.85, 0.75, 0.95), "pos": Vector3(0, 0.35, -5)}
		]
	},
	"ash_cultists": {
		"id": "ash_cultists",
		"name": "Ash Cultists",
		"enemies": [
			{"name": "Ash Cultist A", "scale": Vector3(1.0, 1.0, 1.0), "hp": 50.0, "speed": 3.5, "color": Color(0.9, 0.4, 0.1), "pos": Vector3(-2, 1.0, -5)},
			{"name": "Ash Cultist B", "scale": Vector3(1.0, 1.0, 1.0), "hp": 50.0, "speed": 3.5, "color": Color(0.9, 0.4, 0.1), "pos": Vector3(2, 1.0, -5)}
		]
	},
	"ember_hounds": {
		"id": "ember_hounds",
		"name": "Ember Hounds",
		"enemies": [
			{"name": "Ember Hound Alpha", "scale": Vector3(0.9, 0.8, 0.9), "hp": 35.0, "speed": 5.0, "color": Color(0.8, 0.1, 0.1), "pos": Vector3(0, 0.8, -6)},
			{"name": "Ember Hound Beta", "scale": Vector3(0.8, 0.7, 0.8), "hp": 30.0, "speed": 5.2, "color": Color(0.8, 0.15, 0.1), "pos": Vector3(-3, 0.7, -4)},
			{"name": "Ember Hound Gamma", "scale": Vector3(0.8, 0.7, 0.8), "hp": 30.0, "speed": 5.2, "color": Color(0.8, 0.15, 0.1), "pos": Vector3(3, 0.7, -4)}
		]
	},
	"shadow_duo": {
		"id": "shadow_duo",
		"name": "Shadow Duo",
		"enemies": [
			{"name": "Shadow Blade", "scale": Vector3(1.1, 1.1, 1.1), "hp": 60.0, "speed": 4.2, "color": Color(0.2, 0.2, 0.35), "pos": Vector3(-2.5, 1.1, -5)},
			{"name": "Shadow Guard", "scale": Vector3(1.2, 1.2, 1.2), "hp": 75.0, "speed": 3.0, "color": Color(0.15, 0.15, 0.25), "pos": Vector3(2.5, 1.2, -5)}
		]
	},
	"pyroclastic_golem": {
		"id": "pyroclastic_golem",
		"name": "Pyroclastic Golem",
		"enemies": [
			{"name": "Pyroclastic Golem", "scale": Vector3(2.2, 2.2, 2.2), "hp": 250.0, "speed": 2.2, "color": Color(1.0, 0.3, 0.0), "pos": Vector3(0, 2.2, -6)}
		]
	},
	"infernal_drake": {
		"id": "infernal_drake",
		"name": "Infernal Drake",
		"enemies": [
			{"name": "Infernal Drake", "scale": Vector3(2.0, 2.0, 2.0), "hp": 220.0, "speed": 3.5, "color": Color(0.8, 0.0, 0.2), "pos": Vector3(0, 2.0, -6)}
		]
	}
}


func start_run() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	acts.clear()
	_generate_all_acts()
	var first_room := _get_first_room_in_act(1)
	_sync_start_run.rpc(acts, first_room.get("id", ""))


func _generate_all_acts() -> void:
	acts.clear()
	for act in range(1, 4):
		var act_data := _generate_act(act)
		acts.append(act_data)
	_generate_all_edges()


## Builds the non-crossing layered DAG. Floors are connected to the next floor
## (and the last floor of each act to the next act's start). Same-floor rooms are
## never connected. Edges between two floors never cross: a source's targets form
## a contiguous, monotonically advancing range of slots.
func _generate_all_edges() -> void:
	for act_data in acts:
		for floor_rooms in act_data["floors"]:
			for room in floor_rooms:
				room["children"] = []
				room["parents"] = []

	for ai in range(acts.size()):
		var floors: Array = acts[ai]["floors"]
		for fi in range(floors.size() - 1):
			# The opening fan is always full so the run starts with choices.
			var density := 1.0 if fi == 0 else EDGE_DENSITY
			_generate_edges(floors[fi], floors[fi + 1], density)
		# Chain the post-boss chest into the next act's start room.
		if ai + 1 < acts.size():
			_generate_edges(floors[floors.size() - 1], acts[ai + 1]["floors"][0], 1.0)


func _generate_edges(sources: Array, targets: Array, density: float) -> void:
	if sources.is_empty() or targets.is_empty():
		return
	var cursor := 0
	for si in range(sources.size()):
		var source: Dictionary = sources[si]
		var lo := cursor
		var hi: int
		if si == sources.size() - 1:
			hi = targets.size() - 1
		else:
			hi = randi_range(lo, targets.size() - 1)

		var children: Array = []
		for t in range(lo, hi + 1):
			if t == hi or randf() < density:
				children.append(targets[t]["id"])
		if children.is_empty():
			children.append(targets[hi]["id"])
		source["children"] = children
		for cid in children:
			_add_parent(cid, source["id"])
		cursor = hi

	# Guarantee no orphan targets (every room is reachable).
	for target in targets:
		if target.get("parents", []).is_empty():
			var last_source: Dictionary = sources[sources.size() - 1]
			last_source["children"].append(target["id"])
			target["parents"].append(last_source["id"])


func _add_parent(room_id: String, parent_id: String) -> void:
	var room := get_room_by_id(room_id)
	if not room.is_empty() and not parent_id in room["parents"]:
		room["parents"].append(parent_id)


func get_room_by_id(room_id: String) -> Dictionary:
	for act_data in acts:
		for floor_rooms in act_data["floors"]:
			for room in floor_rooms:
				if room["id"] == room_id:
					return room
	return {}


func _generate_act(act_num: int) -> Dictionary:
	var floors: Array[Array] = []
	for floor_idx in range(FLOORS_PER_ACT):
		var rooms: Array[Dictionary] = []
		if floor_idx == 0:
			rooms.append(_make_room(act_num, floor_idx, 0, RoomType.COMBAT))
		elif floor_idx == FLOORS_PER_ACT - 2:
			rooms.append(_make_room(act_num, floor_idx, 0, RoomType.BOSS))
		elif floor_idx == FLOORS_PER_ACT - 1:
			rooms.append(_make_room(act_num, floor_idx, 0, RoomType.CHEST))
		else:
			var types: Array[RoomType] = [RoomType.COMBAT, RoomType.COMBAT, RoomType.COMBAT, RoomType.CHEST, RoomType.EVENT, RoomType.SHOP]
			types.shuffle()
			var room_count := randi() % (MAX_ROOMS_PER_FLOOR - 1) + 2  # 2 or 3
			for i in range(room_count):
				rooms.append(_make_room(act_num, floor_idx, i, types[i % types.size()]))
		floors.append(rooms)
	return {"act_num": act_num, "floors": floors}


func _make_room(act: int, floor: int, slot: int, type: RoomType) -> Dictionary:
	var rid := "r_%d_%d_%d" % [act, floor, slot]
	var encounter_id := ""
	var encounter_data: Dictionary = {}

	if type == RoomType.COMBAT:
		encounter_id = COMBAT_ENCOUNTERS[(act * 7 + floor * 3 + slot) % COMBAT_ENCOUNTERS.size()]
		encounter_data = ENCOUNTERS.get(encounter_id, {}).duplicate(true)
	elif type == RoomType.BOSS:
		encounter_id = BOSS_ENCOUNTERS[(act - 1) % BOSS_ENCOUNTERS.size()]
		encounter_data = ENCOUNTERS.get(encounter_id, {}).duplicate(true)

	return {
		"id": rid,
		"type": type,
		"act": act,
		"floor": floor,
		"slot": slot,
		"encounter_id": encounter_id,
		"encounter": encounter_data,
		"children": [],
		"parents": []
	}


func _get_first_room_in_act(act_num: int) -> Dictionary:
	if act_num < 1 or act_num > acts.size():
		return {}
	var floors: Array = acts[act_num - 1].get("floors", [])
	if floors.is_empty() or floors[0].is_empty():
		return {}
	return floors[0][0]


func get_act_data() -> Dictionary:
	if current_act < 1 or current_act > acts.size():
		return {}
	return acts[current_act - 1]


func get_current_room() -> Dictionary:
	var ad := get_act_data()
	if ad.is_empty():
		return {}
	var floors: Array = ad["floors"]
	if current_floor >= floors.size():
		return {}
	var floor_rooms: Array = floors[current_floor]
	for r in floor_rooms:
		if r["id"] == current_room_id:
			return r
	return {}


func get_available_choices() -> Array[Dictionary]:
	"""Returns the current room's children — the rooms reachable through its doors."""
	var choices: Array[Dictionary] = []
	var current := get_current_room()
	if current.is_empty():
		return choices
	for cid in current.get("children", []):
		var room := get_room_by_id(cid)
		if not room.is_empty():
			choices.append(room)
	return choices


## Player physically entered a room through a door.
func enter_room(room_id: String) -> void:
	request_select_room(room_id)


func request_select_room(room_id: String) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_server_request_select_room.rpc_id(1, room_id)
		return
	_process_room_selection(room_id)


@rpc("any_peer", "call_local", "reliable")
func _server_request_select_room(room_id: String) -> void:
	if not multiplayer.is_server():
		return
	_process_room_selection(room_id)


func _process_room_selection(room_id: String) -> void:
	select_room(room_id)


func select_room(room_id: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_select_room.rpc(room_id)
	else:
		_do_select_room(room_id)


@rpc("authority", "call_local", "reliable")
func _sync_select_room(room_id: String) -> void:
	_do_select_room(room_id)


func _do_select_room(room_id: String) -> void:
	current_room_id = room_id
	current_act = _room_act(room_id)
	current_floor = _room_floor(room_id)
	room_selected.emit(room_id)


func begin_first_room() -> Dictionary:
	var ad := get_act_data()
	if ad.is_empty():
		return {}
	var floors: Array = ad["floors"]
	if floors.is_empty():
		return {}
	var first: Dictionary = floors[0][0]
	current_room_id = first["id"]
	current_floor = first["floor"]
	return first


func is_room_visited(room_id: String) -> bool:
	return room_id in _selections


func start_next_act() -> Dictionary:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return get_current_room()
	if current_act >= 3:
		_sync_run_complete.rpc()
		return {}
	var next_act_num := current_act + 1
	var first_room := _get_first_room_in_act(next_act_num)
	_sync_start_next_act.rpc(next_act_num, first_room.get("id", ""))
	return get_current_room()


@rpc("authority", "call_local", "reliable")
func _sync_start_next_act(act_num: int, first_room_id: String) -> void:
	current_act = act_num
	current_floor = 0
	current_room_id = first_room_id
	_selections.clear()
	var ad := get_act_data()
	if not ad.is_empty():
		map_generated.emit(ad)


@rpc("authority", "call_local", "reliable")
func _sync_run_complete() -> void:
	run_complete.emit()


func complete_current_room() -> void:
	if current_room_id.is_empty():
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_complete_current_room.rpc(current_room_id)
	else:
		_do_complete_room(current_room_id)


@rpc("authority", "call_local", "reliable")
func _sync_complete_current_room(room_id: String) -> void:
	_do_complete_room(room_id)


func _do_complete_room(room_id: String) -> void:
	if not room_id in _selections:
		_selections.append(room_id)
	room_cleared.emit(room_id)


@rpc("authority", "call_local", "reliable")
func _sync_start_run(acts_data: Array, first_room_id: String) -> void:
	acts.assign(acts_data)
	current_act = 1
	current_floor = 0
	current_room_id = first_room_id
	_selections.clear()
	if not acts.is_empty():
		map_generated.emit(acts[0])


func sync_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_do_sync_full_state.rpc_id(peer_id, acts, current_act, current_floor, current_room_id, _selections)


@rpc("authority", "reliable")
func _do_sync_full_state(acts_data: Array, act_num: int, floor_num: int, room_id: String, selections: Array) -> void:
	acts.assign(acts_data)
	current_act = act_num
	current_floor = floor_num
	current_room_id = room_id
	_selections.assign(selections)
	var ad := get_act_data()
	if not ad.is_empty():
		map_generated.emit(ad)


func _room_floor(room_id: String) -> int:
	var parts := room_id.split("_")
	if parts.size() >= 3:
		return int(parts[2])
	return 0


func _room_act(room_id: String) -> int:
	var parts := room_id.split("_")
	if parts.size() >= 3:
		return int(parts[1])
	return current_act


func get_enemy_count(act: int, floor: int) -> int:
	return clampi(1 + floor / 2 + (act - 1) * 2, 1, 6)


func get_enemy_health_multiplier(act: int, floor: int) -> float:
	return 1.0 + floor * 0.15 + (act - 1) * 0.3
