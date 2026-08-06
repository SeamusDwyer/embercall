# AGENTS.md — Embercall

Instructions for AI coding assistants working in this repo.

## Project

Godot 4.3+ first-person co-op melee roguelike vertical slice (GDScript).
Core mechanics: audio-radar perception + Ignite status/synergy system.
Multiplayer via ENet (Steam stubbed).

## Setup

```bash
bash setup.sh        # download and install GUT test framework
```

## Run

```bash
godot --headless --path . --import --quit    # import assets (one-time)
godot --headless --path . --autopilot        # run single-process autopilot test
bash tests/run_multiplayer_test.sh           # two-process host+join multiplayer test
```

## Test

```bash
# Unit tests (GUT)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# Autopilot integration test
godot --headless --path . --autopilot

# Full multiplayer integration test (host + join)
bash tests/run_multiplayer_test.sh
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for component diagram and data flow.

## Key autoloads (global singletons)

| Name        | Script                          | Role                                           |
|-------------|---------------------------------|--------------------------------------------------|
| `Net`       | `scripts/NetworkManager.gd`     | ENet host/join, player spawning, RPC authority |
| `Radar`     | `scripts/Radar.gd`              | Server-authoritative audio pings → client HUD |
| `DebugShapes` | `scripts/DebugShapes.gd`     | Toggleable hitbox/impact visualization        |

## Code conventions

- Server-authoritative: all game logic runs on host (peer 1). Clients send input via RPCs.
- `@rpc("authority", "call_local", "reliable")` for syncing state to all clients.
- `@rpc("any_peer", "call_local", "reliable")` for client→server requests.
- Component pattern: `Player.gd` / `Enemy.gd` are thin wrappers that instantiate sub-nodes for movement, combat, health, camera.
- `IgniteStatus` is a reusable scene component attached to Player, Enemy, and FlammableProp.

## Plans

| File                          | Status             |
|-------------------------------|---------------------|
| `plans/death-respawn.md`      | Not yet implemented |
| `plans/steam-multiplayer.md`  | Partially implemented (stubs exist) |
