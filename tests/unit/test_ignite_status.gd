extends GutTest

const IgniteStatusClass = preload("res://scripts/IgniteStatus.gd")

var _parent: Node3D
var _ignite: IgniteStatus
var _damage_log: Array[float] = []

func _on_tick(dmg: float) -> void:
	_damage_log.append(dmg)


func before_each() -> void:
	_parent = add_child_autofree(Node3D.new())
	_ignite = IgniteStatusClass.new()
	_ignite.name = "IgniteStatus"
	_parent.add_child(_ignite)
	_damage_log.clear()
	_ignite.ticked.connect(_on_tick)


func after_each() -> void:
	_ignite.ticked.disconnect(_on_tick)
	_parent.remove_child(_ignite)
	_ignite.free()


func test_apply_stacks_sets_burning() -> void:
	assert_false(_ignite.is_burning, "should not be burning initially")
	assert_eq(_ignite.stacks, 0, "stacks should be 0 initially")

	_ignite.apply_stacks(1)
	assert_true(_ignite.is_burning, "should be burning after apply_stacks(1)")
	assert_eq(_ignite.stacks, 1, "stacks should be 1")


func test_apply_stacks_clamps_at_max() -> void:
	_ignite.apply_stacks(_ignite.MAX_STACKS + 3)
	assert_eq(_ignite.stacks, _ignite.MAX_STACKS, "stacks should clamp at MAX_STACKS")
	assert_true(_ignite.is_burning)


func test_apply_stacks_adds_to_existing() -> void:
	_ignite.apply_stacks(2)
	assert_eq(_ignite.stacks, 2)
	_ignite.apply_stacks(1)
	assert_eq(_ignite.stacks, 3)


func test_tick_damage_math() -> void:
	_ignite.apply_stacks(3)
	assert_eq(_ignite.stacks, 3)

	_ignite._server_process(_ignite.TICK_INTERVAL)
	assert_eq(_damage_log.size(), 1, "should have emitted one tick")
	var expected_dmg: float = _ignite.DAMAGE_PER_TICK * 3
	assert_eq(_damage_log[0], expected_dmg, "tick damage should be DAMAGE_PER_TICK * stacks")


func test_burn_timer_decrements() -> void:
	_ignite.apply_stacks(1)
	_ignite._server_process(_ignite.STACK_DURATION * 0.5)
	assert_true(_ignite.is_burning, "should still be burning at half duration")


func test_extinguish_on_timer_expiry() -> void:
	_ignite.apply_stacks(1)
	assert_true(_ignite.is_burning)
	_ignite._server_process(_ignite.STACK_DURATION + 0.1)
	assert_false(_ignite.is_burning, "should be extinguished after STACK_DURATION")
	assert_eq(_ignite.stacks, 0, "stacks should be 0 after extinguish")


func test_burn_timer_refresh_on_reapply() -> void:
	_ignite.apply_stacks(1)
	_ignite._server_process(_ignite.STACK_DURATION - 0.5)
	assert_true(_ignite.is_burning, "should still burn just before expiry")
	_ignite.apply_stacks(1)
	_ignite._server_process(_ignite.STACK_DURATION - 0.5)
	assert_true(_ignite.is_burning, "should still burn after re-application extended timer")


func test_multiple_ticks_over_duration() -> void:
	_ignite.apply_stacks(2)
	_ignite._server_process(_ignite.TICK_INTERVAL)
	_ignite._server_process(_ignite.TICK_INTERVAL)
	_ignite._server_process(_ignite.TICK_INTERVAL)
	assert_eq(_damage_log.size(), 3, "should have 3 ticks in ~3s")
	for dmg in _damage_log:
		assert_eq(dmg, _ignite.DAMAGE_PER_TICK * 2, "each tick should do DAMAGE_PER_TICK * stacks")


func test_extinguish_clears_state() -> void:
	_ignite.apply_stacks(3)
	_ignite._server_process(_ignite.STACK_DURATION + 0.1)
	assert_false(_ignite.is_burning)
	assert_eq(_ignite.stacks, 0)
