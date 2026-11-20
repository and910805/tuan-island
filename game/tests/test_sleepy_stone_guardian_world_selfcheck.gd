extends "res://tests/test_sleepy_stone_guardian_world.gd"
## Self-check of the test itself: runs the whole world test against the TEST-ONLY
## reference World (test_sleepy_stone_guardian_reference.gd) instead of the real
## one. It proves the checks can be satisfied by a contract-conforming server and
## says nothing about the production World. SaveSchema and Session are still the
## real ones, so the [schema] rejections (and anything Session must add) keep
## failing here until the real wiring lands.

const Reference=preload("res://tests/test_sleepy_stone_guardian_reference.gd")

func make_world() -> World:
	print_once()
	return Reference.new()

var announced:=false
func print_once() -> void:
	if announced:return
	announced=true
	print("SELFCHECK: using the test-only reference World, not production World.act")
