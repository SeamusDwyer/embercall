extends GutTest

const PlayerStaminaClass = preload("res://scripts/player/PlayerStamina.gd")

class FakePlayer:
	extends CharacterBody3D
	var stamina: float = 100.0
	var max_stamina: float = 100.0
	var sprint_drain_per_second: float = 20.0
	var sprint_restart_threshold: float = 20.0
	var stamina_regen_per_second: float = 25.0

var _parent: Node3D
var _player: FakePlayer
var _stamina: PlayerStamina


func before_each() -> void:
	_parent = add_child_autofree(Node3D.new())
	_player = FakePlayer.new()
	_parent.add_child(_player)
	_stamina = PlayerStaminaClass.new()
	_stamina.name = "PlayerStamina"
	_player.add_child(_stamina)
	_stamina.setup(_player)


func after_each() -> void:
	_player.remove_child(_stamina)
	_stamina.free()
	_parent.remove_child(_player)
	_player.free()


func test_can_sprint_at_full() -> void:
	assert_true(_stamina.can_sprint(), "should be able to sprint with full stamina")


func test_spend_deducts_stamina() -> void:
	assert_true(_stamina.spend(25), "spend should succeed when enough stamina")
	assert_eq(_player.stamina, 75.0, "stamina should drop by the cost")


func test_spend_blocks_below_cost() -> void:
	_player.stamina = 10.0
	assert_false(_stamina.spend(25), "spend should fail when stamina is too low")
	assert_eq(_player.stamina, 10.0, "stamina should not change on failed spend")


func test_sprint_drain_reduces_stamina() -> void:
	_stamina.update(0.5, true, true)
	assert_eq(_player.stamina, 90.0, "sprinting 0.5s at 20/s drains 10")


func test_no_drain_when_stationary() -> void:
	_stamina.spend(40.0)
	_stamina.update(1.0, true, false)
	assert_eq(_player.stamina, 85.0, "sprinting in place should regen, not drain")


func test_drain_clamps_at_zero_and_exhausts() -> void:
	_stamina.update(5.0, true, true)
	assert_eq(_player.stamina, 0.0, "stamina should clamp at 0")
	assert_false(_stamina.can_sprint(), "sprint should be disabled when exhausted")


func test_regen_restores_stamina() -> void:
	_stamina.spend(40.0)
	assert_eq(_player.stamina, 60.0)
	_stamina.update(1.0, false, false)
	assert_eq(_player.stamina, 85.0, "regen should add 25/s")


func test_regen_clamps_at_max() -> void:
	_stamina.spend(10.0)
	_stamina.update(5.0, false, false)
	assert_eq(_player.stamina, 100.0, "regen should not exceed max_stamina")


func test_exhausted_requires_restart_threshold() -> void:
	_stamina.update(5.0, true, true)
	assert_eq(_player.stamina, 0.0)
	assert_false(_stamina.can_sprint(), "should be exhausted after draining to 0")

	_stamina.update(0.7, false, false)
	assert_eq(_player.stamina, 17.5)
	assert_false(_stamina.can_sprint(), "should still be exhausted below restart threshold")

	_stamina.update(0.2, false, false)
	assert_eq(_player.stamina, 22.5)
	assert_true(_stamina.can_sprint(), "should re-enable sprint past the restart threshold")