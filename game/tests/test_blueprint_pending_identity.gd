extends SceneTree
## Isolated filesystem recovery fixture, not a network or human play test.
const Controller = preload("res://scripts/blueprint_controller.gd")
const Pending = preload("res://scripts/blueprint_pending.gd")
const World = preload("res://scripts/world.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var controller := Controller.new()
	controller._scope = "pending-identity-fixture"
	controller._library_path = "user://pending-identity-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode()
	var design := {"version":1,"name":"地板","width":1,"height":1,"pieces":[{"x":0,"y":0,"kind":"floor"}]}
	var made := Pending.make(controller._scope, "0123456789abcdef", "a".repeat(32), design,
		Vector2i(40,30), 0, "b".repeat(64), "home", 0, World.BUILD, World.NAMES)
	expect(made.ok, "Valid pending fixture")
	controller.pending = made.record
	var path := controller.pending_path()
	expect(Pending.save_pending(path, made.record, World.BUILD, World.NAMES).is_empty(), "Save original intent")
	expect(controller._clear_pending_file(), "Matching successful intent can be cleared")
	expect(not FileAccess.file_exists(path), "Matching record removed")
	var other: Dictionary = made.record.duplicate(true)
	other.nonce = "c".repeat(32)
	expect(Pending.save_pending(path, other, World.BUILD, World.NAMES).is_empty(), "Save second client intent")
	var before := FileAccess.get_file_as_bytes(path)
	expect(not controller._clear_pending_file(), "Late first-client receipt cannot delete another intent")
	expect(FileAccess.get_file_as_bytes(path) == before, "Second intent bytes preserved")
	expect(controller.mode == "unknown" and controller.busy(), "Changed file blocks new submission")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken recovery file")
	file.close()
	before = FileAccess.get_file_as_bytes(path)
	expect(not controller._clear_pending_file(), "Corrupt replacement cannot be cleared by late receipt")
	expect(FileAccess.get_file_as_bytes(path) == before, "Corrupt bytes preserved")
	expect(DirAccess.remove_absolute(path) == OK, "Remove only isolated test record")
	expect(controller._clear_pending_file(), "Already absent record allows confirmed receipt to finish")
	controller.free()
	print("BLUEPRINT_PENDING_IDENTITY_TESTS checks=%d failures=%d" % [checks,failures])
	quit(int(failures > 0))
