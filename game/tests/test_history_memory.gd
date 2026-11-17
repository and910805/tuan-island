extends SceneTree
const World = preload("res://scripts/world.gd")
const Memory = preload("res://scripts/history_memory.gd")
const Schema = preload("res://scripts/save_schema.gd")
var checks := 0
var failures := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func position(world: World, actor: String, cell: Vector2i) -> void:
	world.state.players[actor].x = cell.x - 0.5
	world.state.players[actor].y = cell.y + 0.5

func valid(state: Dictionary) -> bool:
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func _initialize() -> void:
	var path := OS.get_environment("TEMP").path_join("memory-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode())
	var world := World.new()
	world.save_path = path
	for actor in ["alpha","beta"]:
		world.add_player(actor,actor)
		position(world,actor,Memory.SERVICE)
	expect(not world.act("alpha","home","memory_gate",Memory.SERVICE,"a:2").ok,"Outside Lanyang cannot interact")
	for actor in ["alpha","beta"]:
		world.state.players[actor].region = "lanyang"
	var site: Vector2i = Memory.OBSERVATIONS[1]
	expect(not world.act("alpha","unrepaired","memory_observe",site).ok,"Repair is prerequisite")
	var repair: Dictionary = world.state.lanyang_life
	for point: Vector2i in Memory.OBSERVATIONS:repair.cleared[Memory.key(point)] = true
	repair.donations = World.LANYANG_LIFE.REPAIR_COST.duplicate()
	repair.repaired = true
	expect(not world.act("alpha","far","memory_observe",site).ok,"Out-of-range observation refused")
	expect(not world.act("alpha","early","memory_gate",Memory.SERVICE,"a:2").ok,"Gate requires three observations")
	var original_inventory: Dictionary = world.state.players.alpha.inventory.duplicate(true)
	for index in Memory.OBSERVATIONS.size():
		var point: Vector2i = Memory.OBSERVATIONS[index]
		position(world,"alpha",point)
		var id := "observe-%d" % index
		var observed := world.act("alpha",id,"memory_observe",point)
		expect(observed.ok and world.act("alpha",id,"memory_observe",point) == observed,"Observation saves and replays")
		expect(not world.act("alpha",id+"-repeat","memory_observe",point).ok,"New request cannot re-observe")
	position(world,"alpha",Memory.SERVICE)
	expect(not world.act("beta","copy","memory_flow",Memory.SERVICE).ok and not world.state.history_memory.players.has("beta"),"Other actor does not inherit observations")
	var gates := [[2,2],[1,3],[2,1]]
	for index in gates.size():
		var pair: Array = gates[index]
		var id := str(index)
		var before := world.state.duplicate(true)
		expect(not world.act("alpha","incorrect-"+id,"memory_flow",Memory.SERVICE).ok and world.state == before,"Wrong flow leaves current round unchanged")
		expect(not world.act("alpha","malformed-"+id,"memory_gate",Memory.SERVICE,"a:04").ok,"Forged gate rejected")
		expect(world.act("alpha","a-"+id,"memory_gate",Memory.SERVICE,"a:%d"%pair[0]).ok and world.act("alpha","b-"+id,"memory_gate",Memory.SERVICE,"b:%d"%pair[1]).ok,"Valid gate pair")
		if index == 1:
			before = world.state.duplicate(true)
			world.save_path = path.path_join("missing").path_join("world.json")
			expect(not world.act("alpha","flow-"+id,"memory_flow",Memory.SERVICE).ok and world.state == before,"Failed round save rolls back gate and round state")
			world.save_path = path
		var flow := world.act("alpha","flow-"+id,"memory_flow",Memory.SERVICE)
		var record: Dictionary = world.state.history_memory.players.alpha
		expect(flow.ok and record.round == index + 1 and record.gates == [0,0] and world.act("alpha","flow-"+id,"memory_flow",Memory.SERVICE) == flow,"Correct flow advances exactly once and clears gates")
	expect(not world.act("beta","plaque","memory_plaque",Memory.SERVICE).ok,"Incomplete actor cannot place public plaque")
	expect(world.act("alpha","plaque","memory_plaque",Memory.SERVICE).ok and not world.act("alpha","duplicate-plaque","memory_plaque",Memory.SERVICE).ok and world.state.players.alpha.inventory == original_inventory,"Public plaque once, no materials or rewards")
	var reload := World.new()
	expect(reload.load_world(path) and reload.state.version == 26 and reload.state.history_memory.plaque and reload.state.history_memory.players.alpha.completed,"World four restores memory and plaque")
	var invalid := reload.state.duplicate(true)
	expect(invalid.history_memory.players.alpha.get("completed_day",-1)==int(World.WEATHER.day_index(invalid.time)),"Completion date persists")
	var historical := invalid.duplicate(true)
	historical.history_memory.players.alpha.erase("completed_day")
	expect(valid(historical),"Older completed memories without a date remain valid")
	invalid.history_memory.players.alpha.completed_day=int(World.WEATHER.day_index(invalid.time))+1
	expect(not valid(invalid),"A completion date in the future is rejected")
	invalid = reload.state.duplicate(true)
	invalid.history_memory.players.alpha.gates = [1,0]
	expect(not valid(invalid),"Completed record cannot retain adjusted gates")
	invalid = reload.state.duplicate(true)
	invalid.history_memory.players.alpha.seen.append(Memory.key(site))
	expect(not valid(invalid),"Duplicate observations rejected")
	invalid = reload.state.duplicate(true)
	invalid.history_memory.players.clear()
	expect(not valid(invalid),"Plaque needs a real completer")
	reload.state.version = 3;reload.state.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	reload.state.erase("flower_nursery")
	reload.state.regions.erase("tianwei")
	reload.state.erase("salt_pan")
	reload.state.regions.erase("beimen")
	for region in World.REGIONS.ANGLING_RESERVES:reload.state.regions.erase(region)
	for region in World.TRANSIT.TEA_STOPS:reload.state.regions.erase(region)
	for region in World.TRANSIT.LOCAL:reload.state.regions.erase(region)
	reload.state.regions.erase("jinguashi")
	reload.state.erase("jinguashi")
	for region in World.MINES.IDS:reload.state.regions.erase(region)
	reload.state.erase("mine_depths")
	reload.state.erase("history_memory")
	expect(reload.save() and world.load_world(path) and world.state.version == 26 and world.state.history_memory == Memory.fresh() and world.state.lanyang_life.repaired,"Version three migrates with repair intact and no invented memory")
	for file in [path,path+".bak"]:
		DirAccess.remove_absolute(file)
	print("HISTORY_MEMORY_TESTS checks=%d failures=%d" % [checks,failures])
	quit(int(failures > 0))
