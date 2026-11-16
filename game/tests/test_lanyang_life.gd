extends SceneTree
const World = preload("res://scripts/world.gd")
const Life = preload("res://scripts/lanyang_life.gd")
const Schema = preload("res://scripts/save_schema.gd")
var checks := 0
var failures := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func place(world: World, actor: String, cell: Vector2i) -> void:
	world.state.players[actor].x = cell.x - 0.5
	world.state.players[actor].y = cell.y + 0.5

func _initialize() -> void:
	var path := OS.get_environment("TEMP").path_join("lanyang-life-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode())
	var world := World.new()
	world.save_path = path
	world.add_player("alpha","Alpha")
	world.add_player("beta","Beta")
	expect(not world.act("alpha","home","lanyang_clear",World.LANYANG_LIFE.BLOCKAGES[0]).ok, "Home cannot clear Lanyang")
	for actor in ["alpha","beta"]:
		world.state.players[actor].region = "lanyang"
		place(world,actor,Life.SERVICE)
	expect(not world.act("alpha","early","lanyang_donate",Life.SERVICE).ok and not world.act("alpha","early-nursery","nursery_start",Life.SERVICE).ok, "Repair and nursery locked until prerequisites")
	expect(not world.act("alpha","far","lanyang_clear",Life.BLOCKAGES[0]).ok, "Out of reach blockage refused")
	for index in Life.BLOCKAGES.size():
		var target: Vector2i = Life.BLOCKAGES[index]
		place(world,"alpha",target)
		var id := "clear-%d" % index
		var result := world.act("alpha",id,"lanyang_clear",target)
		expect(result.ok and world.act("alpha",id,"lanyang_clear",target) == result, "Normal clear and replay")
		expect(not world.act("alpha",id+"-again","lanyang_clear",target).ok, "Already-cleared point cannot progress twice")
	place(world,"alpha",Life.SERVICE)
	var alpha: Dictionary = world.state.players.alpha
	alpha.inventory.plank = 8
	var beta: Dictionary = world.state.players.beta
	beta.inventory.stone = 10
	beta.inventory.resin = 3
	var before := world.state.duplicate(true)
	world.save_path = path.path_join("missing").path_join("world.json")
	expect(not world.act("alpha","donate","lanyang_donate",Life.SERVICE).ok and world.state == before, "Failed donation rolls back exact inventory and shared work")
	world.save_path = path
	expect(world.act("alpha","donate","lanyang_donate",Life.SERVICE).ok and not world.state.lanyang_life.repaired and world.state.players.alpha.inventory.plank == 2, "Partial contribution caps at required amount")
	expect(world.act("beta","repair","lanyang_donate",Life.SERVICE).ok and world.state.lanyang_life.repaired and world.state.players.beta.inventory.stone == 6 and world.state.players.beta.inventory.resin == 1, "Second player completes shared repair")
	expect(world.act("alpha","nursery","nursery_start",Life.SERVICE).ok and not world.act("alpha","extra","nursery_start",Life.SERVICE).ok, "One paid nursery queue per player")
	expect(not world.act("beta","other-claim","nursery_claim",Life.SERVICE).ok and not world.act("alpha","too-soon","nursery_claim",Life.SERVICE).ok, "Other player's work and early claim denied")
	expect(world.act("beta","nursery","nursery_start",Life.SERVICE).ok and world.state.lanyang_life.jobs.size() == 2, "Second player has independent queue")
	var local: Dictionary = world.state.regions.lanyang
	local.objects["32,22"] = {"type":"water_pump","owner":"alpha","items":{},"enabled":true}
	local.objects["31,22"] = {"type":"water_tank","owner":"alpha","items":{},"water":0}
	world.state.objects["54,22"] = {"type":"water_pump","owner":"alpha","items":{},"enabled":true}
	world.state.objects["53,22"] = {"type":"water_tank","owner":"alpha","items":{},"water":0}
	expect(world.step(8,true) and local.objects["31,22"].water == 12 and world.state.objects["53,22"].water == 8, "Repaired Lanyang pump upgrades only local network")
	var reopened := World.new()
	expect(reopened.load_world(path) and reopened.state.lanyang_life.jobs.size() == 2, "Queues persist on reload")
	reopened.state.picnic = true
	place(reopened,"alpha",World.REGIONS.exit_cell("lanyang"))
	expect(reopened.act("alpha","leave","travel",World.REGIONS.exit_cell("lanyang"),"home").ok and reopened.step(52,true), "Nursery time elapses while actor travels home")
	place(reopened,"alpha",World.REGIONS.exit_cell("home"))
	expect(reopened.act("alpha","return","travel",World.REGIONS.exit_cell("home"),"lanyang").ok, "Return to nursery region")
	place(reopened,"alpha",Life.SERVICE)
	var bag: Dictionary = reopened.state.players.alpha.inventory
	bag.sapling = 1000000000
	expect(not reopened.act("alpha","claim","nursery_claim",Life.SERVICE).ok and reopened.state.lanyang_life.jobs.has("alpha"), "Inventory cap preserves ready job")
	bag.sapling = 1
	var claim := reopened.act("alpha","claim","nursery_claim",Life.SERVICE)
	expect(claim.ok and bag.sapling == 4 and reopened.act("alpha","claim","nursery_claim",Life.SERVICE) == claim and not reopened.act("alpha","repeat","nursery_claim",Life.SERVICE).ok and reopened.state.lanyang_life.jobs.has("beta"), "Ready claim settles once and leaves other queue")
	var invalid := reopened.state.duplicate(true)
	invalid.lanyang_life.jobs.beta.ready = float(invalid.time)+61
	expect(not Schema.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME), "Future ready deadline beyond recipe duration rejected")
	reopened.state.version = 2;reopened.state.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	reopened.state.erase("flower_nursery")
	reopened.state.regions.erase("tianwei")
	reopened.state.erase("salt_pan")
	reopened.state.regions.erase("beimen")
	for region in World.REGIONS.ANGLING_RESERVES:reopened.state.regions.erase(region)
	for region in World.TRANSIT.TEA_STOPS:reopened.state.regions.erase(region)
	for region in World.TRANSIT.LOCAL:reopened.state.regions.erase(region)
	reopened.state.regions.erase("jinguashi")
	reopened.state.erase("jinguashi")
	for region in World.MINES.IDS:reopened.state.regions.erase(region)
	reopened.state.erase("mine_depths")
	reopened.state.erase("lanyang_life")
	expect(reopened.save() and reopened.load_world(path) and reopened.state.version == 26 and reopened.state.lanyang_life == Life.fresh(), "Old save without progress migrates cleanly")
	for file in [path,path+".bak"]:
		DirAccess.remove_absolute(file)
	print("LANYANG_LIFE_TESTS checks=%d failures=%d" % [checks,failures])
	quit(int(failures > 0))
