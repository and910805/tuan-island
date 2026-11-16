extends SceneTree

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const CENTER := Vector2i(42, 36)
var checks := 0
var failures := 0
var sequence := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func fresh(center: Vector2i = CENTER):
	var world = World.new()
	world.add_player("farmer", "農夫")
	var player: Dictionary = world.state.players.farmer
	player.x = center.x + 0.5
	player.y = center.y + 0.5
	player.inventory.merge({"seeder": 1, "charcoal": 4, "radish_seed": 9, "tomato_seed": 1}, true)
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			world.state.crops[World.key(Vector2i(x,y))] = {"kind": "", "owner": "farmer", "growth": 0.0, "wet": x == center.x, "remaining": 0}
	return world

func act(world, kind: String = "radish", center: Vector2i = CENTER, id: String = "") -> Dictionary:
	sequence += 1
	return world.act("farmer", "seed-area-%d" % sequence if id.is_empty() else id, "seed_area", center, kind)

func valid(state: Dictionary) -> bool:
	return Schema.validate(state, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME)

func _initialize() -> void:
	var world = fresh()
	var player: Dictionary = world.state.players.farmer
	var ordered := ["42,36", "42,35", "41,36", "43,36", "42,37", "41,35", "43,35", "41,37", "43,37"]
	var plan: Dictionary = World.SEEDER.plan(world, "farmer", CENTER, "radish")
	expect(plan.cells == ordered and plan.eligible == ordered, "nearest center, then y then x ordering")
	expect(act(world, "radish", CENTER, "retry").ok, "full pass succeeds")
	expect(player.inventory.radish_seed == 0 and player.inventory.charcoal == 3, "nine seeds and only one charcoal consumed")
	for tile in ordered:
		var plot: Dictionary = world.state.crops[tile]
		expect(plot.owner == "farmer" and plot.kind == "radish" and plot.growth == 0 and plot.remaining == 1 and plot.wet == tile.begins_with("42,"), "planted plot preserves prior wet state " + tile)
	var after: Dictionary = world.state.duplicate(true)
	expect(act(world, "radish", CENTER, "retry").ok and world.state == after, "identical request is idempotent")
	player.inventory.radish_seed = 4
	after = world.state.duplicate(true)
	expect(not act(world).ok and world.state == after, "cooldown has no side effects")
	world.step(1.0, true)
	after = world.state.duplicate(true)
	expect(not act(world).ok and world.state == after, "fully planted field costs nothing")

	world = fresh()
	world.state.players.farmer.inventory.radish_seed = 4
	plan = World.SEEDER.plan(world, "farmer", CENTER, "radish")
	expect(plan.cells == ordered.slice(0,4) and plan.eligible == ordered, "seed stock limits cells but not eligibility")
	expect(plan.skipped["42,37"] == "種子不足" and act(world).ok, "partial pass succeeds in previewed order")
	expect(world.state.players.farmer.last_seed.cells == ordered.slice(0,4) and world.state.players.farmer.inventory.charcoal == 3, "partial pass records only planted tiles and costs one charcoal")
	expect(world.state.crops["42,37"].kind == "", "eligible tile beyond available stock stays empty")

	world = fresh()
	world.state.crops["42,35"].owner = "other"
	world.state.crops["41,36"].kind = "lettuce"
	world.state.crops.erase("43,36")
	world.state.objects["41,35"] = {"type": "chair"}
	world.state.ground["43,35"] = {"type": "path"}
	world.state.roofs["41,37"] = {"type": "roof"}
	world.state.forest["43,37"] = {"owner": "farmer", "mature": false}
	plan = World.SEEDER.plan(world, "farmer", CENTER, "radish")
	expect(plan.cells == ["42,36", "42,37"] and plan.skipped.size() == 7, "existing crops, ownership, untiled land and each obstacle excluded")
	expect(act(world).ok and world.state.crops["42,35"].kind == "" and world.state.crops["41,36"].kind == "lettuce", "pass preserves occupied and foreign crops")
	expect(not world.state.crops.has("43,36"), "seeder cannot create a field")

	for item in ["seeder", "charcoal", "radish_seed"]:
		world = fresh()
		world.state.players.farmer.inventory[item] = 0
		after = world.state.duplicate(true)
		expect(not act(world).ok and world.state == after, "missing %s costs nothing" % item)
	world = fresh()
	after = world.state.duplicate(true)
	expect(not act(world, "invalid").ok and world.state == after, "invalid crop costs nothing")
	expect(not act(world, "radish", Vector2i(50,36)).ok and world.state == after, "far center costs nothing")
	world.state.players.farmer.y = 39.5
	plan = World.SEEDER.plan(world, "farmer", CENTER, "radish")
	expect(plan.cells == ["42,36", "41,36", "43,36", "42,37", "41,37", "43,37"], "each tile independently obeys reach")
	for center in [Vector2i(40,30), Vector2i(55,36)]:
		world = fresh(center)
		expect(World.SEEDER.plan(world, "farmer", center, "radish").cells.is_empty() and not act(world, "radish", center).ok, "public or water area rejects artificial fields")

	world = fresh()
	world.save_path = "user://missing-seeder-directory-%d/world.json" % Time.get_ticks_usec()
	after = world.state.duplicate(true)
	expect(not act(world, "tomato").ok and world.state == after, "failed save rolls back inventory, crops, event and receipt")
	world.save_path = "user://seed-area-%d.json" % Time.get_ticks_usec()
	expect(act(world, "tomato").ok and world.state.crops["42,36"].remaining == 3, "tomato begins all three cycles")
	var loaded = World.new()
	expect(loaded.load_world(world.save_path) and loaded.state.players.farmer.last_seed == world.state.players.farmer.last_seed, "reload preserves seed event")
	expect(loaded.state.crops["42,36"].wet and loaded.state.players.farmer.inventory.tomato_seed == 0, "reload preserves planting and inventory")
	for variant in ["unknown crop", "duplicate", "far cell"]:
		after = world.state.duplicate(true)
		var event: Dictionary = after.players.farmer.last_seed
		match variant:
			"unknown crop": event.kind = "invalid"
			"duplicate": event.cells.append(event.cells[0])
			"far cell": event.cells = ["50,36"]
		expect(not valid(after), "schema rejects " + variant)
	after = world.state.duplicate(true)
	after.players.farmer.erase("last_seed")
	expect(valid(after), "older save can omit seed event")
	DirAccess.remove_absolute(world.save_path)
	print("SEEDER_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
