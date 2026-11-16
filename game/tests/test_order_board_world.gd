extends SceneTree

const World = preload("res://scripts/world.gd")
const Village = preload("res://scripts/village.gd")
const Board := Vector2i(40, 29)

var checks := 0
var failures := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var world := World.new()
	var path := "user://order-board-%d.json" % Time.get_ticks_usec()
	world.save_path = path
	for token in ["alice", "bob"]:
		world.add_player(token, token)
		var player: Dictionary = world.state.players[token]
		player.x = 40.5
		player.y = 30.5
		player.inventory.radish = 3
	world.state.time = 100.0
	expect(not world.act("alice", "board-1", "order_accept", Board, "radish").ok, "Unrepaired board refuses orders")
	world.state.board = true
	expect(not world.act("alice", "board-2", "order", Board, "radish").ok, "Delivery requires prior acceptance")
	expect(world.act("alice", "board-3", "order_accept", Board, "radish").ok, "Acceptance commits")
	expect(not world.act("bob", "board-4", "order", Board, "radish").ok, "A different player cannot deliver an accepted order")
	var reopened := World.new()
	var loaded := reopened.load_world(path)
	expect(loaded, "Saved active order can be loaded")
	if loaded:
		var alice: Dictionary = reopened.state.players.alice
		var before := int(alice.coins)
		expect(alice.orders.get("active", {}).has("radish"), "Active order survives a fresh World instance")
		expect(reopened.act("alice", "board-5", "order", Board, "radish").ok, "Accepted order can be delivered after reload")
		expect(alice.inventory.radish == 0 and alice.coins == before + 90, "Exact materials and reward commit together")
		expect(not reopened.act("alice", "board-6", "order", Board, "radish").ok, "Successful order cannot pay twice")
		reopened.state.time += Village.DAY
		alice.inventory.radish = 3
		expect(reopened.act("alice", "board-7", "order_accept", Board, "radish").ok, "A later day permits another order")
		reopened.state.time = float(alice.orders.active.radish.due)
		expect(not reopened.act("alice", "board-8", "order", Board, "radish").ok, "Delivery expires by world time")
		expect(alice.inventory.radish == 3 and alice.coins == before + 90, "Expired order preserves materials and coins")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("ORDER BOARD WORLD checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
