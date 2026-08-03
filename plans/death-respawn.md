# Death/Respawn Loop

## Goal
Remove the hard dead-end that kills playtesting iteration speed. Players
respawn after a short delay; a team-wipe restarts the arena without tearing
down the multiplayer session.

## Changes

### A. Player respawn after delay (`Player.gd`)

**Problem**: `_on_death()` disables `_physics_process` and shows "YOU DIED"
permanently. The only way out is restarting both game instances.

**Fix**:
1. On the server, when `_on_death` fires, start a 3-second timer (or
   `await get_tree().create_timer(3.0).timeout` inside a coroutine).
2. After the timer expires (server-side only), reset the dead player:
   - Set `health = max_health` and sync via `_sync_health.rpc`.
   - Move to the nearest unused spawn point (use `Net.player_spawn_points`,
     or re-use the player's original spawn point stored at spawn time).
   - Re-enable `set_physics_process(true)`.
   - Call `IgniteStatus._extinguish()` to clear any burn state.
   - RPC to all clients: hide death label, show respawn effect, re-enable
     input for the authority peer.
3. Add brief invincibility (1.5s) so a respawning player isn't instantly
   killed by an enemy camping the spawn. Tracked via a bool gated in
   `take_damage`.

**Files touched**: `scripts/Player.gd` only.

### B. Team-wipe detection (`Arena.gd`)

**Problem**: No condition exists for "all players are dead so the run is
over." The only way the arena resets is manually.

**Fix**:
1. Arena tracks `_alive_players: Dictionary` (peer_id -> bool) — updated
   when a player dies or respawns.
2. After each player death, check if all tracked players are dead. If so,
   call `_team_wipe.rpc()`.
3. `_team_wipe` reloads the arena scene via
   `get_tree().reload_current_scene()` (just the arena, not Main). Since
   Main.tscn instances Arena as a child, we can free and re-instance it, or
   simply call `get_tree().reload_current_scene()` and let the host/join
   menu reappear — but preserving the multiplayer session is better.
   Actually, the simplest correct approach: free all existing players,
   reload the Arena scene by queue_free + re-instance, then re-spawn all
   connected peers from Net.

   **Simpler alternative**: use `get_tree().reload_current_scene()` which
   reloads Main.tscn. The menu is hidden by `Main.gd:_on_host_pressed` but
   it re-appears on reload. A cleaner approach is to reset only the Arena
   subtree: `$Arena.queue_free()`, instance a fresh Arena, add it back,
   then call `Net._spawn_player` for each connected peer.

**Files touched**: `scripts/Arena.gd`, possible small hook in `NetworkManager.gd`.

### C. Death clears ignite state

On respawn, explicitly call `IgniteStatus._extinguish()` so the player
doesn't come back already burning. This is a one-liner in the respawn path.

### D. Edge cases to handle

- If the player was holding an attack when they died, `_attack_cooldown_left`
  should reset to 0 on respawn.
- If the exit zone was unlocked (enemy already dead), it should stay
  unlocked across respawns — only team-wipe resets the arena.
- Multiple enemies later: team-wipe detection should be based on "all
  players dead" regardless of enemy state.

## What this does NOT do (out of scope for this pass)

- No limited lives / shared-life-pool — infinite respawns for now.
- No death penalty (loot loss, ignite stacks persist, etc.).
- No spectator mode while dead.
- No "respawn at teammate" mechanic.
- No per-player respawn timer configuration.

## Sequence

1. Player A takes lethal damage → `take_damage` → `_on_death.rpc`
2. Server-side: Arena marks Player A as dead, checks team-wipe → not yet
3. Server starts 3s respawn timer for Player A
4. (If all players die during this window → team-wipe → arena resets)
5. Timer fires → server resets Player A's state → RPCs to all
6. Player A reappears at spawn with full health, 1.5s invuln
