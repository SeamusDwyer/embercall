# Embercall — vertical slice

A minimal co-op first-person melee roguelike prototype, built to test exactly
two things before investing further: **audio-radar perception** and the
**Ignite status/synergy system** (a burn effect that bridges combat and
environment). Everything else is deliberately bare-bones.

## Requirements
- Godot 4.3+ (uses `@rpc` annotations, `MultiplayerSynchronizer`,
  `SceneReplicationConfig` — all Godot 4.x high-level multiplayer API).

## Running it
1. Open the project folder in Godot 4.
2. Run the project (F5). It opens on the host/join menu.
3. Click **Host** in one instance. Run a second instance (Godot lets you run
   the same project multiple times via the debug menu, or export two
   builds) and click **Join** with `127.0.0.1`.
4. Controls: **WASD** move, **mouse** look, **Space** jump, **left click**
   melee attack, **Esc** toggle mouse capture.

## What's actually implemented
- **Networking**: `NetworkManager.gd` (autoload `Net`) — ENet host/join,
  server-authoritative player spawning via `MultiplayerSynchronizer`.
- **Audio radar** (`Radar.gd`, autoload): server emits pings (footsteps,
  swings, growls, burning) with a position + audible radius; each client's
  HUD converts pings into bearing/distance blips relative to its own
  camera. This is the perception mechanic from our design discussion —
  intentionally *not* per-player-vision-based, so it stays clean over the
  network.
- **Ignite** (`IgniteStatus.gd`): a reusable component attached to Player,
  Enemy, and FlammableProp. Ticks damage, pings the radar, and spreads to
  nearby ignitable nodes via a physics-shape overlap query — the single
  system meant to unify combat and environment, per your "even split" call.
- **One enemy type** (`Enemy.gd`): chases the nearest player, melee-attacks
  in range, growls periodically (radar ping), can catch fire and burn to
  death from Ignite ticks.
- **One arena, one full loop** (`Arena.gd` + `Arena.tscn`): walled room,
  three flammable props, one enemy, an ExitZone that unlocks once the enemy
  dies and ends the "run" when a player walks into it.

## What's intentionally stubbed / left for next passes
- **Run-complete state**: `Arena._run_complete()` just prints to console.
  This is the seam where a real "choice offer" screen, next-room loader, or
  meta-progression would plug in.
- **No player death/respawn flow** beyond freezing input and showing
  "YOU DIED" — no retry loop yet.
- **No archetype/relic system yet** — the melee attack always applies 1
  Ignite stack. This is where you'd add the reticle-as-itemization or
  weapon-swap-changes-moveset ideas once the core Ignite+Radar loop feels
  good in practice.
- **No dedicated server mode** — host is a player too (listen-server model).
  Swap to a headless dedicated server later by having Godot run with
  `--headless` and skipping local player spawn for peer 1 if you want that.
- **Placeholder art everywhere** — capsules and colored boxes. Ignite is
  represented by a material swap + particles, not real shaders.

## Suggested next test pass
Get 2+ people in a room, see whether:
1. The radar actually helps you track the enemy/teammates without looking,
   or if it's just noise — this is the mechanic most likely to need
   iteration since it's the least proven idea in the design doc.
2. Igniting a FlammableProp near the enemy creates a moment that *feels*
   different from just meleeing it directly — that's the whole bet behind
   picking Ignite as the first synergy system.
