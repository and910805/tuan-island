extends SceneTree
const World = preload("res://scripts/world.gd")
const Shipping = preload("res://scripts/shipping.gd")
const Session = preload("res://scripts/session.gd")
var checks := 0
var failures := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var world := World.new()
	var path := OS.get_environment("TEMP").path_join("shipping-prototype-%d.json" % Time.get_ticks_usec())
	world.load_world(path)
	var token := "shipping-player"
	var other := "neighbor-player"
	world.add_player(token, "Player")
	world.add_player(other, "Neighbor")
	var actor: Dictionary = world.state.players[token]
	actor.x = Shipping.CELL.x + 0.5
	actor.y = Shipping.CELL.y + 0.5
	actor.inventory.radish = 4
	var fish: String = World.FISH.keys()[0]
	actor.inventory[fish] = 3
	actor.inventory.hoe = 1
	var prices := Shipping.prices(World.CROPS, World.FISH, World.OTHER_SALES)
	var lines := [["radish", 2], ["wood", 3], [fish, 1]]
	var expected: int = 48 + 6 + World.FISH[fish].price
	var payload := JSON.stringify([lines, expected])
	var preview := Shipping.quote(lines, actor.inventory, prices)
	expect(preview.ok and preview.total == expected, "Mixed farm/gather/fish quote")
	expect(not prices.has("hoe") and not prices.has("radish_seed"), "Tools and seeds excluded")
	for invalid in [[], [["radish", 0]], [["radish", -1]], [["radish", true]], [["radish", 1.5]], [["radish", "1"]],
		[["radish", 1], ["radish", 1]], [["radish", 9]], [["hoe", 1]], [["", 1]], [["radish", 1, 4]], {}]:
		expect(not Shipping.quote(invalid, actor.inventory, prices).ok, "Invalid line rejected")
	var too_many := []
	too_many.resize(17)
	expect(not Shipping.quote(too_many, actor.inventory, prices).ok, "Line count bound")
	expect(not Shipping.verify(" ".repeat(1025), actor.inventory, prices, 120).ok, "Payload byte bound")
	var pristine := world.state.duplicate(true)
	var legacy := {"type": "chair", "owner": other, "items": {}}
	world.state.objects[World.key(Shipping.CELL)] = legacy
	var fallback := Shipping.cell_for(world.state)
	expect(fallback != Shipping.CELL and fallback != Shipping.NO_CELL and world.protected(fallback) and world.blocked(fallback), "Legacy furniture shifts the protected landmark")
	expect(not world.act(token, "occupied", "ship", Shipping.CELL, payload).ok and world.state.objects[World.key(Shipping.CELL)] == legacy, "Legacy object is preserved and stale landmark rejected")
	world.state.ground[World.key(fallback)] = {"type": "path", "owner": other}
	world.state.crops[World.key(Shipping.cell_for(world.state))] = {}
	expect(Shipping.cell_for(world.state) == Shipping.NO_CELL, "All occupied candidates leave the legacy plaza intact")
	expect(not world.act(token, "all-occupied", "ship", Shipping.CELL, payload).ok and actor.coins == 120 and actor.inventory.radish == 4, "Fully occupied plaza rejects shipment without settlement")
	world.state = pristine.duplicate(true)
	actor = world.state.players[token]
	expect(not world.act(token, "wrong", "ship", Shipping.CELL + Vector2i.RIGHT, payload).ok, "Wrong target")
	expect(not world.act(other, "distance", "ship", Shipping.CELL, payload).ok, "Distance and actor are authoritative")
	expect(not world.act(token, "mismatch", "ship", Shipping.CELL, JSON.stringify([lines, expected + 1])).ok, "Forged total rejected")
	expect(not world.act(token, "stale", "ship", Shipping.CELL, JSON.stringify([[["radish", 5], ["wood", 1]], 122])).ok, "Stale quantity rejected")
	expect(world.state == pristine, "Invalid batches do not mutate state")
	actor.coins = Shipping.MAX_COINS
	expect(not world.act(token, "overflow", "ship", Shipping.CELL, payload).ok and actor.coins == Shipping.MAX_COINS, "Wallet cap prevents overflow")
	actor.coins = 120
	world.save_path = path.path_join("missing").path_join("world.json")
	expect(not world.act(token, "commit", "ship", Shipping.CELL, payload).ok and world.state == pristine, "Save failure rolls back items, coins and receipt")
	world.save_path = path
	var sold := world.act(token, "commit", "ship", Shipping.CELL, payload)
	actor = world.state.players[token]
	expect(sold.ok and actor.coins == 120 + expected, "Exact quoted value credited")
	expect(actor.inventory.radish == 2 and actor.inventory.wood == 9 and actor.inventory[fish] == 2, "Exact selected quantities deducted")
	expect(world.state.players[other] == pristine.players[other], "Neighbor wallet and inventory unchanged")
	expect(world.act(token, "commit", "ship", Shipping.CELL, payload) == sold and actor.coins == 120 + expected, "Retry does not duplicate sale")
	var reopened := World.new()
	expect(reopened.load_world(path), "World format reloads")
	expect(reopened.state.players[token].coins == 120 + expected and reopened.state.players[token].inventory.wood == 9, "Sale persisted")
	var retry := reopened.act(token, "commit", "ship", Shipping.CELL, payload)
	expect(retry.ok and retry.message == sold.message and int(retry.total) == expected and reopened.state.players[token].coins == 120 + expected, "Persisted retry remains idempotent")
	var session := Session.new()
	session.world = reopened
	session.peers[1] = token
	session.sequences[1] = 0
	var recent := []
	for index in range(11):
		recent.append(Time.get_ticks_msec())
	session.rates[1] = recent
	var completed := []
	session.action_completed.connect(func(sequence, action, result): completed.append([sequence, action, result]))
	var next_payload := JSON.stringify([[["radish", 1]], 24])
	session.perform("ship", Shipping.CELL, next_payload)
	session.perform("ship", Shipping.CELL, next_payload)
	expect(completed.size() == 2 and completed[0][2].ok and completed[1][0] == 2 and completed[1][1] == "ship" and not completed[1][2].ok, "Same-frame rate limit completes the pending shipment with its sequence")
	recent.clear()
	session._action(1, 2, "ship", Shipping.CELL, next_payload)
	expect(completed.size() == 2 and reopened.state.players[token].coins == 144 + expected and reopened.state.players[token].inventory.radish == 1, "Replaying the rejected sequence cannot charge or settle again")
	session.free()
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.remove_absolute(path)
	print("SHIPPING_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
