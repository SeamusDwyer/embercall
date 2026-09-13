extends Node
## Autoload singleton: "DamageLog".
## Central record of every hit a player takes, tagged with the reason it
## happened and the source that caused it.
##
## Damage sources call Player.take_damage(amount, reason, source). The reason
## and source name ride the health-sync RPC, so every peer records the same
## entry and a client sees why its own player is being hurt.

signal logged(entry: Dictionary)

## Damage reason categories.
const REASON_ENEMY_MELEE := "enemy_melee"
const REASON_PLAYER_MELEE := "player_melee"
const REASON_BURNING := "burning"
const REASON_UNKNOWN := "unknown"

const MAX_ENTRIES := 100

var entries: Array[Dictionary] = []
var _clock: float = 0.0


func _process(delta: float) -> void:
	_clock += delta


## Record one damage event. `reason` is a short category (see the reason
## constants on Player), `source_name` is the offending node's name.
func record(player_name: String, amount: float, reason: String, source_name: String, health_after: float) -> void:
	var entry := {
		"time": _clock,
		"player": player_name,
		"amount": amount,
		"reason": reason,
		"source": source_name,
		"health_after": health_after,
	}
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	print("[DAMAGE] t=%.2f %s -%.1f (%s) source=%s hp=%.1f" % [
		entry.time, player_name, amount, reason, source_name, health_after])
	logged.emit(entry)


## Most recent entries, oldest first.
func recent(count: int = 10) -> Array:
	var start := maxi(entries.size() - count, 0)
	return entries.slice(start)


## Total damage taken, grouped by reason.
func totals_by_reason() -> Dictionary:
	var totals := {}
	for entry in entries:
		totals[entry["reason"]] = totals.get(entry["reason"], 0.0) + entry["amount"]
	return totals


func clear() -> void:
	entries.clear()
