# Room / Map Progression System

## Goal

Add a Slay-the-Spire-style roguelike map progression: 3 acts, each
containing a sequence of rooms the player must clear. A physical 3D map on
the wall of each room shows the full act layout and lets the player select
the next destination.

## Architecture

### Autoload: RoomManager (`scripts/RoomManager.gd`)

Server-authoritative singleton managing the run state:

- **Map generation**: 3 acts, 8 floors each. Procedural room types per floor.
- **Room state**: tracks current act, floor, room ID, visited rooms.
- **Signals**: `map_generated`, `room_cleared`, `room_selected`, `run_complete`.
- **Enemy scaling**: `get_enemy_count(act, floor)` and
  `get_enemy_health_multiplier(act, floor)` — count and HP scale per floor/act.

### Room types (`RoomType` enum)

| Type    | Description                                      |
|---------|--------------------------------------------------|
| COMBAT  | Spawn enemies; all must die to clear              |
| CHEST   | Free reward; auto-clears on entry (stub)          |
| EVENT   | Choice-based interaction (stub)                   |
| SHOP    | Spend gold on items (stub)                        |
| BOSS    | Single tough enemy (2.5x HP, 1.5x scale); ends act |

### Act structure (8 floors per act)

| Floor | Type(s)                               |
|-------|---------------------------------------|
| 0     | COMBAT (start)                        |
| 1–5   | 2–3 random rooms: COMBAT, CHEST, EVENT, SHOP |
| 6     | BOSS                                  |
| 7     | CHEST (post-boss reward)              |

Floor 0 is always the same. Floors 1–5 offer 2–3 randomly typed rooms
for player choice. Boss is mandatory and always a single room. The post-boss
chest auto-completes and advances to the next act (or ends the run after act 3).

## Room flow per encounter

```
1. Room loaded → enemies/props spawned from room_data
2. Room cleared → map markers on next floor become selectable
3. Player walks to map on wall, clicks a room marker
4. Exit door unlocks (particles on)
5. Player walks through exit → arena reconfigures for chosen room
```

When only one room exists on the next floor (e.g. boss, chest), the
selection is automatic and the exit unlocks immediately.

When the autopilot test is active, the first available choice is
auto-selected to keep the bot progressing.

## Map3D (`scripts/Map3D.gd`)

A physical 3D object placed on the south wall of the arena at
`(0, 1.6, 9.4)`, facing 180° so local +Z points into the room.

### Visual elements

- **Board**: dark backing panel sized to enclose all markers + padding.
- **Markers**: small colored cubes (boss = diamond) per room. Color-coded:
  - Red = Combat
  - Yellow = Chest
  - Purple = Event
  - Cyan = Shop
  - Dark red = Boss
- **Connection lines**: thin box meshes between adjacent-floor room markers.
- **States (material change)**:
  - `INACTIVE` — dim, not yet reachable
  - `CURRENT` — bright glowing, player is here now
  - `SELECTABLE` — glowing, clickable next-floor room
  - `VISITED` — faded, already cleared

### Interaction

Each selectable marker has a `StaticBody3D` with `input_ray_pickable = true`.
Left-click on a SELECTABLE marker calls `RoomManager.select_room()` and
unlocks the arena exit. The player's camera raycasts through the viewport
— no special interaction key needed.

### Act transitions

`_refresh_markers()` detects `RoomManager.current_act != _current_act` and
triggers a full `_clear_map()` + `_build_map()` for the new act's data.
Otherwise only marker materials are updated in-place.

## Arena changes (`scripts/Arena.gd`)

Converted from single-hardcoded-enemy loop to dynamic room loading:

- `configure(room_data)` — clears previous room, spawns content by type.
- `_spawn_enemies(room_data)` — instantiates N enemies at predefined spawn
  positions, applying act/floor HP scaling. Boss gets 2.5x HP multiplier and
  1.5x mesh scale.
- `_unlock_map_choices()` — called when room content is clear. Calls
  `RoomManager.complete_current_room()`, then auto-selects if only one
  choice exists.
- `_on_map_choice_made()` — connected to `RoomManager.room_selected`; sets
  `_map_choice_made = true` and unlocks exit via RPC.
- Backward-compatible API kept for `Autopilot.gd`: `get_enemy()`,
  `is_enemy_dead()`, `is_exit_unlocked()`.

### Arena.tscn changes

Removed hardcoded `Enemy` instance and three `FlammableProp` instances from
the scene file. They are now spawned dynamically by `Arena.configure()`.

## Main integration (`scripts/Main.gd`)

- `_start_run()` — called after first player spawns. Calls
  `RoomManager.start_run()`, connects `exit_triggered` and `run_complete`
  signals, configures arena for the first room.
- `_on_arena_exit()` — handles room transition. If no more choices
  (end of act), calls `RoomManager.start_next_act()`. If run is complete
  (act 3 cleared), calls `_on_run_complete()`.
- `_on_run_complete()` — prints completion message, unpauses tree.
- `_ensure_run_started()` — used by autopilot path; mirrors `_start_run()`.

## Enemy scaling table

| Act | Floor | Enemy count | HP multiplier |
|-----|-------|-------------|---------------|
| 1   | 0–5   | 1–3         | 1.0–1.75      |
| 1   | 6     | 1 (boss)    | 1.9 × 2.5     |
| 2   | 0–5   | 3–5         | 1.3–2.05      |
| 2   | 6     | 1 (boss)    | 2.2 × 2.5     |
| 3   | 0–5   | 5–6         | 1.6–2.35      |
| 3   | 6     | 1 (boss)    | 2.5 × 2.5     |

Formulas:
- `count = clampi(1 + floor/2 + (act-1)*2, 1, 6)`
- `hp_mult = 1.0 + floor*0.15 + (act-1)*0.3`
- Boss: `hp_mult *= 2.5`

## What this does NOT do (out of scope for this pass)

- No chest/shop/event room content — they auto-complete instantly (stubs).
- No gold/currency tracking.
- No item/relic/buff system.
- No victory screen — just a console print on run complete.
- Clients see a view-only map (interaction is server-authoritative).
- No late-join room state replay.
- No character persistence between rooms (stats carry implicitly but no
  explicit state serialization).

## Files

| Path                                 | Status    |
|--------------------------------------|-----------|
| `scripts/RoomManager.gd`             | New — autoload |
| `scripts/Map3D.gd`                   | New — 3D wall map |
| `scripts/Arena.gd`                   | Rewritten — dynamic rooms |
| `scenes/Arena.tscn`                  | Trimmed — no hardcoded enemies/props |
| `scripts/Main.gd`                    | Extended — room flow wiring |
| `project.godot`                      | Added RoomManager autoload |
