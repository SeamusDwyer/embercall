# Room / Map Progression System

## Goal

A Slay-the-Spire-style roguelike run of 3 acts, 8 floors each, laid out as a
**persistent, physically-connected dungeon**. The player progresses by
**walking through gated doors** — no menu or marker selection. Each exit path
is labeled by a **physical 3D symbol** showing the room type ahead. An
**airlock** seals every door behind the party so movement is always forward.

## Map topology generation

The map is a **layered DAG**: floors are depth ranks; edges connect only
adjacent floors and never cross (StS's "paths cannot cross" rule).

**Invariants**

- Rooms on the same floor are never connected (no lateral movement, e.g. A↔B).
- Edges are **non-crossing**: for edges `(s1→t1)`, `(s2→t2)` between floors
  `f`/`f+1`, `s1 < s2 ⟹ t1 ≤ t2`.
- Every room except floor 0 has ≥1 parent; every non-terminal room has ≥1
  child (all rooms reachable from start; no orphans).

**Generator** (per adjacent floor pair, in `RoomManager._generate_edges`):

```gdscript
var cursor := 0
for s in sources.size():
    var lo := cursor
    var hi := randi_range(lo, targets.size() - 1)
    if s == sources.size() - 1:
        hi = targets.size() - 1           # last source reaches last target
    for t in range(lo, hi + 1):
        if t == hi or randf() < density:  # allow skipping within the range
            edges[sources[s]] += targets[t]
    cursor = hi
```

Example (`A,B` on floor 1, `C,D` on floor 2): A fans over `[C,D]`, B starts at
`cursor=1` and can only reach D → `A→C, A→D, B→D`. `B→C` is structurally
impossible, preventing the crossing. The opening fan (floor 0 → 1) is always
full so the run starts with choices.

Floors chain into one continuous dungeon: floor 0 → middle floors → boss →
post-boss chest → chest's single edge chains into the next act's floor 0.
"Act" remains bookkeeping for scaling/state.

## Architecture

### Autoload: `RoomManager` (`scripts/RoomManager.gd`)

- Generates acts/floors/rooms, then `_generate_edges()` builds `children` and
  `parents` (room IDs) per room.
- `enter_room(room_id)` (alias of the old `select_room`) is triggered by
  physical door traversal; `room_selected` signal retained.
- `get_available_choices()` returns `current_room.children`.
- Enemy scaling (`get_enemy_count`, `get_enemy_health_multiplier`) unchanged.

### `World` (`scripts/World.gd`)

Owns the physical dungeon. At run start it:

- Instantiates one `Room` per room on a grid: `X = slot * 26`, `Z = -depth * 34`
  (global depth `= (act-1)*8 + floor`, continuous across acts).
- Creates corridors between adjacent floors from the `children` edges, plus a
  single large ground collider under everything.
- **Pre-places all room shells** (walls, floor, doors, symbols) so the world
  looks complete; **spawns contents lazily** on first player entry.
- Builds on both server (explicitly via `Main._start_run`) and clients (when
  `RoomManager.map_generated` fires).

### `Room` (`scripts/Room.gd`)

The 20×20 walled box, built procedurally. Forward is `-Z`: entry through the
south gate, exit through `N` north gates (one per child). Each room:

- Tracks clear state; emits `cleared`, `player_entered`, `enemy_spawned`.
- Seals its entry gate once all players are inside (airlock); combat rooms stay
  sealed until clear.
- Opens its exit gates when the clear condition is met.
- Keeps the Autopilot API (`get_enemy()`, `is_enemy_dead()`,
  `is_exit_unlocked()`, `get_primary_exit_position()`).

### `Door` (`scripts/Door.gd`)

A gate (`StaticBody3D`) + optional `RoomSymbol` emblem above it. States:
`LOCKED` (blocked), `SEALED` (combat), `OPEN` (collision disabled). Locked =
red, open = blue.

### `RoomSymbol` (`scripts/RoomSymbol.gd`)

Physical 3D emblem above each exit door, reusing Map3D colour/shape language:
Combat = red cube, Chest = yellow box, Event = purple prism, Shop = cyan box,
Boss = dark-red diamond.

## Room types & gate conditions

| Type   | Entry door            | Exit doors open when…     |
|--------|-----------------------|---------------------------|
| COMBAT | seals on activation   | all enemies die           |
| BOSS   | seals on activation   | boss dies                 |
| CHEST  | airlock-closes only   | chest opened              |
| SHOP   | always open           | always open               |
| EVENT  | airlock-closes only   | auto-clears (stub)        |

## Room flow per encounter

```
1. Player enters through a door → airlock seals it behind (once all passed).
   Combat/boss: entry door SEALS; contents spawn on first entry.
2. Gate condition met (enemies dead / chest opened / shop passthrough).
3. Exit doors unlock (blue) → symbols above them glow.
4. Player walks through a door → enters that child room.
5. Door seals behind the party (airlock) — no backtracking.
```

## Airlock / co-op semantics

- Trailing door closes once **all players have passed** (per `Net.players`).
- Combat entry door seals once **all players have entered**.
- Shop doors never lock.
- Convergence: when two parents share a child (A,B → D), their corridors meet
  at D's single entry gate.

## Map3D (`scripts/Map3D.gd`) — reference-only

Physical wall board in the current room. View-only: markers show
`CURRENT`/`VISITED`/`SELECTABLE`(= reachable through an open door)/`INACTIVE`.
Draws actual `children` edges (no crossings). No click-to-select.

## Main integration (`scripts/Main.gd`)

- `_start_run()` → `RoomManager.start_run()`, `begin_first_room()`,
  `world.build_run()`, connect `world.run_complete`.
- Room transitions are implicit (door traversal → `RoomManager.enter_room`).
- `_on_run_complete()` prints and unpauses.

## Enemy scaling table

Unchanged: `count = clampi(1 + floor/2 + (act-1)*2, 1, 6)`,
`hp_mult = 1.0 + floor*0.15 + (act-1)*0.3`, boss `hp_mult *= 2.5`.

## Out of scope

- No chest/shop/event content — chest open is a stub interaction; shop is a
  passthrough; event auto-clears.
- No gold/items/relics; no victory screen (console print).
- No late-join room-state replay (existing `sync_to_peer` covers RoomManager
  state only; enemy sync to a just-joined peer is not replayed).
- Corridors are simple box meshes; no bespoke room geometry variants.

## Files

| Path                                  | Status                            |
|---------------------------------------|-----------------------------------|
| `scripts/RoomManager.gd`              | Extended — edges + `enter_room()` |
| `scripts/World.gd`                    | New — layout + corridor wiring    |
| `scripts/Room.gd`                     | New — replaces `Arena.gd`         |
| `scripts/Door.gd`                     | New — gate + airlock              |
| `scripts/RoomSymbol.gd`               | New — emblem above door           |
| `scripts/Map3D.gd`                    | Modified — view-only              |
| `scripts/Main.gd`                     | Extended — world build + wiring   |
| `scenes/Main.tscn`                    | World node + persistent PlayerRoot|
| `scripts/GameState.gd`                | Updated — current-room ref        |
| `scripts/NetworkManager.gd`           | Updated — spawn into PlayerRoot   |
| `tests/Autopilot.gd`                  | Updated — walk through open door  |
| `scripts/Arena.gd`, `scenes/Arena.tscn` | Removed (replaced by Room)      |
