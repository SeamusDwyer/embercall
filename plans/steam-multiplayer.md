# Steam Multiplayer & Lobbies — Implementation Plan

Based on analysis of wizards-in-godot architecture. Ordered by testability.

---

## Pre-requisite: Godot Binary with GodotSteam

None of the Steam-specific code (LobbyManager, `--steam-host`, `--steam-join`) can be tested
until the project switches from standard Godot 4.3 to a custom build with GodotSteam baked in.
Until then, the ENet transport continues to work transparently through the abstraction layer.

Temporary: `SteamMultiplayerPeer` references use `ClassDB.instantiate("SteamMultiplayerPeer")`
with `.set()` for dynamic properties — no compile-time dependency.

---

## 1. Transport Abstraction (`NetworkManager.gd`)

Refactor `Net` autoload to support both ENet and Steam through a unified interface.

**Changes:**
- Extract ENet host/join into `_start_enet_host()` / `_start_enet_client(address)`
- Add parallel `_start_steam_host()` / `_start_steam_client(lobby_id)` stubs
- Add `_transport: String` tracking (set to "enet" or "steam")
- `host_game()` and `join_game()` detect transport from flags or auto-detect
- `_cleanup_connection()` explicitly disconnects multiplayer signals before nullifying peer
- Add `--steam-host` / `--steam-join <lobby_id>` CLI flags (handled in Main.gd)

**Validatable:** Unit tests can verify signal cleanup; autopilot/multiplayer test verifies
ENet still works through the new abstraction.

---

## 2. Signal Cleanup (`NetworkManager.gd`)

Current code nullifies `multiplayer.multiplayer_peer` without disconnecting signals.
This can cause dangling references and error logs on quit.

**Changes:**
- Add `_cleanup_connection()` method
- Disconnect `connected_to_server`, `connection_failed`, `server_disconnected` before nullifying
- Call in `_on_server_disconnected` and before any peer switch
- Unsuppress `_suppress_reload` on cleanup

**Validatable:** Error-free shutdown in autopilot/multiplayer tests (no "multiplayer instance
isn't currently active" spam).

---

## 3. Client Interpolation (`Player.gd`)

Remote players currently snap to their synchronized position every frame.
Interpolate smoothly with a lerp toward the target position.

**Changes:**
- Add `_interp_from: Vector3`, `_interp_to: Vector3`, `_interp_progress: float`
- Add `_has_received_sync: bool` flag
- When `_on_synchronized` fires (or position arrives from synchronizer):
  - On authority peer: do nothing (we ARE the authority)
  - On remote peers: set `_interp_from = position`, `_interp_to = new_position`,
    `_interp_progress = 0.0`, `_has_received_sync = true`
- In `_process` (NOT `_physics_process`): lerp position toward target
- Snake correction: if error > 2.0, snap immediately

**Validatable:** Multiplayer test runs with a second peer connected; remote player movement
should be smooth in practice. Headless can verify no errors.

---

## 4. Late-Join Replay (`Arena.gd` + `NetworkManager.gd`)

A player joining after the run has started should see all existing state:
existing players, enemy status (alive/dead), exit zone status.

**Changes:**
- In `NetworkManager._spawn_player`, for the NEW peer, also replay:
  - All existing players via `_do_spawn_player.rpc_id(new_peer, ...)`
  - Arena state via new `_sync_arena_state.rpc_id(new_peer, ...)`
- `Arena._sync_arena_state` RPC tells the joining peer whether enemy is dead,
  exit is unlocked, and any other run state
- Enemy's death state synced via existing `_die.rpc` which is `call_local` but
  late-joiners miss it — need explicit replay

**Validatable:** Multiplayer test with join after enemy death (modify test script).

---

## 5. LobbyManager (`scripts/lobby/LobbyManager.gd`)

Standalone class managing Steam lobby lifecycle. No autoload — instantiated by Main.gd
when Steam mode is active.

**Static methods:**
- `is_steam_available() -> bool` — calls `Steam.steamInit()`
- `steam_init() -> bool` — one-time initialization

**Instance methods:**
- `create_lobby(max_players: int)` → `Steam.createLobby()`
- `join_lobby(lobby_id: int)` → `Steam.joinLobby()`
- `leave_lobby()`
- `open_invite_dialog()`
- `_process(delta)` → `Steam.run_callbacks()` every frame

**Signals:**
- `lobby_created(lobby_id: int)`
- `lobby_joined(lobby_id: int, owner_id: int)`
- `lobby_error(message: String)`
- `join_requested(lobby_id: int, friend_id: int)`

**Steam callback connections:**
- `Steam.lobby_created(connect_result, lobby_id)`
- `Steam.lobby_joined(lobby_id, permissions, locked, response)`
- `Steam.join_requested(lobby_id, friend_id)`

**Not testable** without Steam binary — code compiles but `Steam.steamInit()` returns false,
so LobbyManager gracefully no-ops on all host platforms.

---

## 6. CLI Flags (`Main.gd`)

Add to existing `_ready()` flag detection:
- `--steam-host` → calls `Net.host_game()` with `transport = "steam"` (no lobby ID needed — auto-creates)
- `--steam-join=<lobby_id>` → calls `Net.join_game("")` with `transport = "steam"` and lobby ID
- `--local-host` / `--local-join` → explicit ENet mode (current `--host` is implicit ENet)

Existing `--autopilot` and `--autojoin` remain ENet-only for CI.

**Not testable** without Steam binary — flags parse correctly, fall back to ENet gracefully.

---

## Implementation Order

1. Signal cleanup (smallest, fixes existing bugs)
2. Transport abstraction (refactor existing code, no new features)
3. Client interpolation (new feature, testable)
4. Late-join replay (new feature, testable)
5. LobbyManager (new class, can't test without Steam)
6. CLI flags (wire up LobbyManager to Main.gd)

After each step: run `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
and `godot --headless --path . --autopilot` to verify no regressions.

After step 4: run `bash tests/run_multiplayer_test.sh` to verify multiplayer still works.
