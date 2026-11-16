extends SceneTree
const World = preload("res://scripts/world.gd")
const Chapter = preload("res://scripts/chapter_one.gd")
var checks := 0
var failures := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var world := World.new()
	var path := OS.get_environment("TEMP").path_join("chapter-one-%d.json" % Time.get_ticks_usec())
	world.save_path = path
	var token := "chapter-player"
	world.add_player(token, "Island")
	var player: Dictionary = world.state.players[token]
	player.x = 42.5
	player.y = 32.5
	player.inventory.radish = 3
	var payload := JSON.stringify([[["radish", 1]], 24])
	expect(world.act(token, "untracked", "ship", World.SHIPPING.CELL, payload).ok and Chapter.phase(world.state) == "grow", "Prior inventory cannot stand in for a harvest")
	var plot := Vector2i(42, 34)
	var crop_key := World.key(plot)
	world.state.crops[crop_key] = {"kind": "radish", "wet": true, "growth": World.CROPS.radish.time, "owner": token, "remaining": 1}
	expect(world.act(token, "harvest", "harvest", plot).ok and Chapter.phase(world.state) == "ship", "Real harvest unlocks shipment goal")
	var bad_path := path.path_join("missing").path_join("world.json")
	world.save_path = bad_path
	expect(not world.act(token, "sale", "ship", World.SHIPPING.CELL, payload).ok and Chapter.phase(world.state) == "ship", "Save failure rolls back shipment evidence")
	world.save_path = path
	expect(world.act(token, "sale", "ship", World.SHIPPING.CELL, payload).ok and Chapter.phase(world.state) == "works", "Successful shipment advances to public works")
	player = world.state.players[token]
	player.inventory.wood = 30
	player.inventory.stone = 10
	player.x = 40.5
	player.y = 30.5
	expect(world.act(token, "board", "donate", Vector2i(40,29)).ok and Chapter.phase(world.state) == "water", "Existing public works action advances chapter")
	var starter := Chapter.STARTER_CELL
	expect(not world.act(token, "starter", "chapter_starter", starter).ok, "Insufficient repair materials rejected")
	player.inventory.merge(Chapter.STARTER_COST, true)
	world.save_path = bad_path
	expect(not world.act(token, "starter", "chapter_starter", starter).ok and world.state.chapter_one.starter_claims.is_empty() and world.state.players[token].inventory.wood == 12, "Starter save failure refunds materials and leaves entitlement unused")
	world.save_path = path
	player = world.state.players[token]
	var exchange := world.act(token, "starter", "chapter_starter", starter)
	expect(exchange.ok and player.inventory.wood == 0 and player.inventory.stone == 0 and player.inventory.fiber == 0 and player.inventory.pipe_kit == 2 and player.inventory.tank_kit == 1 and player.inventory.sprinkler_kit == 1, "Starter uses exact repair cost and grants the existing kits")
	expect(world.act(token, "starter", "chapter_starter", starter) == exchange and not world.act(token, "starter-again", "chapter_starter", starter).ok and player.inventory.pipe_kit == 2, "Retries and new requests cannot claim the starter twice")
	var second := "second-islander"
	world.add_player(second, "Neighbor")
	var neighbor: Dictionary = world.state.players[second]
	neighbor.inventory.merge(Chapter.STARTER_COST, true)
	neighbor.x = 70.5
	neighbor.y = 40.5
	expect(not world.act(second, "far", "chapter_starter", starter).ok, "Cannot exchange remotely")
	neighbor.x = 38.5
	neighbor.y = 30.5
	expect(world.act(second, "starter", "chapter_starter", starter).ok and world.state.chapter_one.starter_claims.size() == 2, "A second player earns their own starter exchange")
	world.state.crops[crop_key] = {"kind": "radish", "wet": false, "growth": 0.0, "owner": token, "remaining": 1}
	world.state.objects["43,34"] = {"type": "sprinkler", "owner": token, "items": {}, "water": 1, "enabled": true, "next_water": 0.0, "last_water": -1.0}
	expect(world.step(1.0,true) and world.state.crops[crop_key].wet and Chapter.phase(world.state) == "water", "Manual reservoir can water a plot but cannot certify the network")
	world.state.crops[crop_key].wet = false
	world.state.objects["43,34"].next_water = 0.0
	world.state.next_network_check = 0.0
	world.state.objects["44,34"] = {"type": "water_pipe", "owner": token, "items": {}}
	world.state.objects["45,34"] = {"type": "water_tank", "owner": token, "items": {}, "water": 1}
	world.save_path = bad_path
	expect(not world.step(1.0,true) and not world.state.crops[crop_key].wet and Chapter.phase(world.state) == "water" and world.state.objects["45,34"].water == 1, "Failed pipe tick rolls back water transfer, wet transition and chapter")
	world.save_path = path
	world.state.objects["43,34"].next_water = float(world.state.time) + 7.0
	expect(world.step(1.0,true) and not world.state.crops[crop_key].wet and world.state.objects["43,34"].network_water == 1, "Network water remains in a sprinkler that is still on cooldown")
	world = World.new()
	expect(world.load_world(path) and world.state.objects["43,34"].network_water == 1 and world.state.chapter_one.starter_claims.size() == 2, "Stored network source and exchanges survive reopening")
	var removal := World.new()
	removal.state = world.state.duplicate(true)
	var near: Dictionary = removal.state.players[token]
	near.x = 43.5
	near.y = 33.5
	expect(removal.act(token, "remove-device", "remove", Vector2i(43,34)).ok and removal.act(token, "place-device", "build", Vector2i(43,34), "sprinkler").ok and not removal.state.objects["43,34"].has("network_water"), "Removing and replacing a sprinkler cannot inherit stored water attribution")
	expect(world.step(7.0,true) and world.state.crops[crop_key].wet and Chapter.phase(world.state) == "meal", "Stored pipe water is consumed on a later tick after reload")
	player = world.state.players[token]
	player.inventory.soup = 2
	player.inventory.bread = 1
	var prior: int = player.inventory.radish_seed
	expect(world.act(token, "meal", "picnic", Vector2i(40,29)).ok and Chapter.phase(world.state) == "complete", "Existing picnic concludes chapter")
	expect(player.inventory.radish_seed == prior + 3 and not world.act(token, "second-meal", "picnic", Vector2i(40,29)).ok, "Meal reward granted once")
	var reopened := World.new()
	expect(reopened.load_world(path) and Chapter.phase(reopened.state) == "complete", "Completed chapter persists")
	expect(not Chapter.valid({"shipped": false, "watered": true, "harvests": {}, "starter_claims": {}}, reopened.state.players, World.CROPS, true), "Impossible optional state rejected")
	reopened.state.erase("chapter_one")
	expect(reopened.save() and world.load_world(path) and world.state.board and world.state.picnic and Chapter.phase(world.state) == "grow", "Legacy board and meal retained without inventing harvest evidence")
	world.state.chapter_one.shipped = true
	expect(Chapter.phase(world.state) == "water", "Legacy picnic does not bypass the new network goal")
	Chapter.record_irrigation(world.state)
	expect(Chapter.phase(world.state) == "complete" and world.state.players[token].inventory.radish_seed == prior + 3, "Legacy meal recognized with no new donation or payout")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	print("CHAPTER_ONE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
