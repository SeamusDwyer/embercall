# Architecture — Embercall

## Component diagram

```
Main.gd (root scene)
│
├── UI/MenuPanel                 host/join buttons, IP field
├── Arena.gd
│   ├── PlayerRoot/              spawned by Net
│   │   └── Player (body)
│   │       ├── IgniteStatus     burn state, ticks, spread
│   │       ├── PlayerMovement   WASD/jump/sprint, footstep pings
│   │       ├── PlayerCamera     mouse look, settings toggle
│   │       ├── PlayerCombat     swing phase machine, hit detection → Ignite stacks
│   │       ├── PlayerHealth     damage → _sync_health, _on_death
│   │       └── CameraPivot
│   │           ├── WeaponPivot  spring-driven weapon transform
│   │           │   └── hammer   real weapon mesh
│   │           └── Swings/      ghost keyframe poses (editor authoring)
│   │               └── SwingN/{Anticipation, Final}
│   │
│   ├── Enemies/
│   │   └── Enemy (body)
│   │       ├── IgniteStatus     same component, separate instance
│   │       ├── EnemyMovement    chase nearest player, growl pings
│   │       ├── EnemyCombat      TELL→SWING→RECOVERY attack state machine
│   │       ├── EnemyHealth      damage → _sync_health, _die
│   │       └── HealthBar3D      world-space billboarded health bar
│   │
│   ├── Props/                   FlammableProp (crates etc.)
│   │   ├── IgniteStatus         catches fire from spread
│   │   └── HazardArea           burning prop ignites bodies on contact
│   │
│   └── ExitZone                 unlocks when enemy dies; run complete on enter
│
└── Autopilot.gd                 scripted bot for headless CI tests
```

## Autoload singletons

```
┌─────────────┐     ┌──────────────────────┐     ┌─────────────┐
│    Radar    │     │         Net           │     │ DebugShapes │
│─────────────│     │──────────────────────│     │─────────────│
│ emit_ping() │──▶  │ host/join (ENet)      │     │ hitbox/     │
│   (server   │     │ spawn_player()        │     │ impact viz  │
│    only)    │     │ players{} dict        │     │ toggle      │
│             │     │ replay_state_to_peer()│     │             │
│ ↓ RPC       │     │                        │     │             │
│ ping_received│    └──────────────────────┘     └─────────────┘
│   signal    │
└──────┬──────┘
       │ subscribed by
       ▼
     HUD.gd ←── instantiated per authority peer, bound to one Player
       │
       ├── RadarDisplay.gd     draws bearing/distance blips
       ├── HealthBar/Label     bound from Player._sync_health
       ├── DamageLogPanel      recent player hits + reason (settings toggle)
       └── Settings panel      vsync, resolution, debug toggles
```

## Data flow: melee attack with Ignite

```
1. Client clicks → Player._physics_process → PlayerCombat.trigger_attack()
2. Player._request_attack.rpc_id(1)        (any_peer → server)
3. Server: PlayerCombat.resolve_hits()
   ├── for each body in attack_area:
   │   ├── body.take_damage(DAMAGE, "player_melee", player)
   │   ├── body.apply_knockback(dir, strength)
   │   └── body.IgniteStatus.apply_stacks(1, player)
   │       └── IgniteStatus._server_process
   │           ├── ticked signal → take_damage(dmg, "burning", igniter)
   │           ├── Radar.emit_ping("burning")   (server only, RPC'd to all)
   │           └── _try_spread() → overlap query → nearby IgniteStatus.apply_stacks(1, self)
   └── Player._spawn_hit_impact.rpc(pos)
```

## Data flow: player damage logging

```
Every player hit carries a reason + source:
  EnemyCombat  → take_damage(DAMAGE, "enemy_melee", enemy)
  PlayerCombat → take_damage(DAMAGE, "player_melee", attacker)   (friendly fire)
  IgniteStatus → take_damage(dmg, "burning", igniter)            (tracked by apply_stacks)

1. PlayerHealth.take_damage(amount, reason, source)  (server only)
   └── Player._sync_health.rpc(new_hp, reason, source_name, amount)
2. Every peer: PlayerHealth.sync_hp(...) → DamageLog.record(...)
   ├── appends {time, player, amount, reason, source, health_after}
   ├── prints "[DAMAGE] ..." to console
   └── emits `logged` → HUD DamageLogPanel refreshes (if enabled)
```

## Data flow: weapon swing animation

```
Authoring (editor only):
  CameraPivot/Swings/SwingN/{Anticipation, Final}   ghost hammers
    ├── transforms are the swing keyframes
    └── SwingGhost.gd renders them translucent + shadowless; Player hides
        them at runtime unless the `show_ghosts` export is enabled

Runtime (cosmetic, runs on every peer, per render frame):
1. Player._physics_process → PlayerCombat.trigger_attack()
   └── snapshots Anticipation + Final ghost transforms into WeaponPivot space
       (scaled by swing_amplitude), advances to the next SwingN
2. Player._process(delta) → PlayerCombat.process_visual(delta)
   ├── phase machine: ANTICIPATION → STRIKE → HOLD → IDLE
   │     (durations: anticipation_time / strike_time / hold_time)
   ├── target transform = current phase pose, or rest pose when IDLE
   └── DampedSpring3D.step() for position + rotation (frequency / bounce)
       └── weapon_pivot.position / rotation = spring value
           → frame-rate independent, stable on large deltas
```

## Data flow: audio-radar ping

```
1. Source emits (server only):
   ├── PlayerMovement: footstep pings     tag="footstep"  strength=6
   ├── PlayerCombat.resolve_hits: swing   tag="swing"     strength=5
   ├── EnemyMovement: growl               tag="growl"     strength=14
   ├── IgniteStatus: burn tick / ignite   tag="burning"/"ignite_whoosh"  strength=8/10
   └── Radar.emit_ping(pos, tag, strength) ← server-gated

2. Radar._broadcast_ping.rpc(pos, tag, strength)  (authority, call_local, reliable)

3. Every client: Radar.ping_received signal fires

4. Each HUD._on_ping_received():
   ├── compute vector from bound player to ping position
   ├── skip if dist > strength (out of hearing range)
   ├── compute bearing angle relative to player forward
   ├── append fading blip to _blips[]
   └── RadarDisplay.queue_redraw() → _draw() blips as circles
```

## Networking model

```
Host (peer 1)                          Client (peer 2+)
────────────                           ────────────
Server authority:                       Authority: own Player
  enemy AI, Ignite ticks,               Input → RPCs to server
  Radar pings, health, arena            HUD reads local Radar signal
  state, exit unlock                    Remote players: interpolated
                                        Enemy/Ignite: synced via
Replicates to all:                      MultiplayerSynchronizer
  Player positions (MultiplayerSync)
  Enemy health, death (RPCs)
  Ignite stacks (MultiplayerSync)
  Arena state (RPCs)
```

## File layout

```
scripts/
├── Main.gd                    root scene: menu + CLI flags (autopilot, autojoin, steam)
├── Arena.gd                   run loop: enemy death → exit unlock → run complete
├── Player.gd                  thin wrapper; movement/camera/combat/health + swing poses
├── Enemy.gd                   thin wrapper, instantiates movement/combat/health
├── IgniteStatus.gd            reusable burn component (stacks, ticks, spread)
├── Flammable.gd               environmental prop using IgniteStatus
├── HUD.gd                     per-authority-peer canvas (health, radar blips, settings)
├── Radar.gd                   autoload: server-side ping emit → broadcast to all
├── RadarDisplay.gd            draws radar blips on circular minimap
├── NetworkManager.gd          autoload: ENet/Steam host/join, player spawn, late-join replay
├── DebugShapes.gd             autoload: hitbox/impact visualization overlay
├── DamageLog.gd               autoload: player damage log (reason + source)
├── DampedSpring3D.gd          analytic frame-rate-independent spring (position/rotation)
├── SwingGhost.gd              @tool ghost pose marker (translucent, authoring only)
├── player/
│   ├── PlayerMovement.gd      WASD, jump, sprint (louder steps), remote interpolation
│   ├── PlayerCamera.gd        mouse capture/look, sprint FOV kick, settings toggle
│   ├── PlayerCombat.gd        swing phase machine (anticipation/strike/hold), hit detect
│   └── PlayerHealth.gd        damage sync, death
├── enemy/
│   ├── EnemyMovement.gd       chase nearest player, growl pings, knockback
│   ├── EnemyCombat.gd         TELL→SWING→RECOVERY state machine
│   └── EnemyHealth.gd         damage sync, death visuals
├── vfx/
│   ├── HitImpact.gd           shared hit marker sphere (tweened fade-out)
│   └── HealthBar3D.gd         billboarded health bar + health_bar.gdshader
└── lobby/
    └── LobbyManager.gd        Steam lobby lifecycle (not yet wired into Main)

scenes/
├── Main.tscn                  root: UI + Arena
├── Arena.tscn                 walled room, enemy, 3 props, exit zone
├── Player.tscn                body + IgniteStatus + WeaponPivot/hammer + Swings ghost poses
├── Enemy.tscn                 CharacterBody3D + IgniteStatus + MultiplayerSynchronizer
├── FlammableProp.tscn         Node3D + IgniteStatus + fire VFX + hazard area
└── HUD.tscn                   CanvasLayer with health bar, radar display, settings

tests/
├── Autopilot.gd               scripted bot: seek enemy → attack → enter exit
├── run_multiplayer_test.sh    bash: host + join two processes, assert PASS
└── unit/
    ├── test_ignite_status.gd  GUT: stack application, tick damage, extinguish
    └── test_player_camera.gd  GUT: camera setup, mouse input, pitch clamp
```
