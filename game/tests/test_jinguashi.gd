extends SceneTree
const World = preload("res://scripts/world.gd")
const Mine = World.JINGUASHI
const Regions = World.REGIONS
var checks := 0
var failures := 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func near(world: World, actor: String, tile: Vector2i) -> void:
	world.state.players[actor].x = tile.x - 0.5
	world.state.players[actor].y = tile.y + 0.5

func _initialize() -> void:
	var path := OS.get_environment("TEMP").path_join("jinguashi-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode())
	var world := World.new()
	world.save_path = path
	var exit := Regions.exit_cell(Regions.HOME)
	var node: Vector2i = Mine.NODES[0]
	for actor in ["alpha","beta"]:
		world.add_player(actor,actor)
		near(world,actor,exit)
		# This fixture isolates mountain mining after a known route.
		world.state.players[actor].travel_book.visited.jinguashi=true
	expect(not world.act("alpha","locked","transit",exit,Regions.JINGUASHI).ok,"Existing picnic unlock required")
	world.state.picnic = true
	expect(world.act("alpha","arrive","transit",exit,Regions.JINGUASHI).ok and world.player_region("alpha") == Regions.JINGUASHI,"Normal regional travel arrives")
	world.switch_region(Regions.JINGUASHI)
	var entrance := Vector2i(24,18)
	expect(world.blocked(entrance) and world.protected(entrance) and world.resource(entrance).is_empty(),"Illustrated mine entrance is solid, protected and resource-free")
	var queue := [Vector2i(12,20)]
	var visited := {queue[0]:true}
	var cursor := 0
	while cursor < queue.size() and not visited.has(Vector2i(27,20)):
		var point:Vector2i=queue[cursor]
		cursor+=1
		for direction:Vector2i in World.INDUSTRY.NEIGHBORS:
			var next:=point+direction
			if not visited.has(next) and world.can_stand(Vector2(next)+Vector2(0.5,0.5)):
				visited[next]=true
				queue.append(next)
	expect(visited.has(Vector2i(27,20)),"Entrance and workshop leave a walkable route to the first node and back")
	world.switch_region(Regions.HOME)
	near(world,"alpha",entrance)
	expect(not world.act("alpha","hoe-entrance","hoe",entrance).ok and not world.act("alpha","build-entrance","build",entrance,"chair").ok,"Entrance footprint cannot be tilled or built over")
	near(world,"alpha",Vector2i(6,20))
	var cliff := Vector2i(5,20)
	expect(not world.act("alpha","cliff-fish","fish_start",cliff).ok and not world.state.players.alpha.has("fishing"),"Mountain edge cannot be treated as a fishing shore")
	near(world,"alpha",Vector2i(13,20))
	expect(not world.act("alpha","far","mine_copper",node).ok,"Mining distance enforced")
	near(world,"alpha",node)
	expect(not world.act("alpha","bare","pick",node).ok,"Reinforced pick required")
	world.state.players.alpha.inventory.reinforced_pick = 1
	expect(not world.act("alpha","build","build",node,"chair").ok,"Mine cannot be built over")
	expect(world.act("beta","arrive","transit",exit,Regions.JINGUASHI).ok,"Second miner joins")
	near(world,"beta",node)
	world.state.players.beta.inventory.reinforced_pick = 1
	var snapshot := world.region_snapshot(Regions.JINGUASHI)
	expect(snapshot.region_id == Regions.JINGUASHI and snapshot.players.size() == 2 and not snapshot.has("regions"),"Isolated snapshot")
	var before := world.state.duplicate(true)
	world.save_path = path.path_join("missing").path_join("world")
	expect(not world.act("alpha","mine","mine_copper",node).ok and world.state == before,"Failed disk save rolls back ore and node cooldown")
	world.save_path = path
	var mined := world.act("alpha","mine","mine_copper",node)
	expect(mined.ok and world.state.players.alpha.inventory.copper_ore == Mine.YIELD and world.act("alpha","mine","mine_copper",node)==mined,"Normal mine and retry award one yield")
	expect(not world.act("beta","contended","pick",node).ok and not world.state.players.beta.inventory.has("copper_ore"),"Shared node cooldown prevents simultaneous second payout")
	var other: Vector2i = Mine.NODES[1]
	near(world,"beta",other)
	expect(world.act("beta","independent","pick",other).ok,"Another node has an independent cooldown")
	var old_clock: float = world.state.time
	expect(world.step(Mine.COOLDOWN,true) and world.state.time == old_clock + Mine.COOLDOWN and world.act("alpha","mine-again","pick",node).ok,"All regions share one clock and node respawns")
	var reopened := World.new()
	expect(reopened.load_world(path) and reopened.state.version == preload("res://scripts/save_schema.gd").VERSION and reopened.player_region("alpha") == Regions.JINGUASHI,"Reopen restores region and cooldown")
	var schema = preload("res://scripts/save_schema.gd")
	for malformed in [{"28,20":reopened.state.time+Mine.COOLDOWN+1},{"30,20":reopened.state.time},{"28,20":true}]:
		var invalid := reopened.state.duplicate(true)
		invalid.jinguashi.ready = malformed
		expect(not schema.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Malformed mining deadline rejected")
	var invalid := reopened.state.duplicate(true)
	invalid.players.alpha.region = "unknown"
	expect(not schema.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Unknown region rejected")
	expect(not reopened.act("alpha","cooldown","pick",node).ok,"Persisted cooldown still blocks")
	var back := Regions.exit_cell(Regions.JINGUASHI)
	near(reopened,"alpha",back)
	expect(reopened.act("alpha","leave","transit",back,Regions.HOME).ok and reopened.player_region("alpha") == Regions.HOME and reopened.state.players.alpha.inventory.copper_ore == Mine.YIELD*2,"Free return carries copper to home")
	reopened.state.version = 4;reopened.state.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	reopened.state.erase("flower_nursery")
	reopened.state.regions.erase("tianwei")
	reopened.state.erase("salt_pan")
	reopened.state.regions.erase("beimen")
	for region in World.REGIONS.ANGLING_RESERVES:reopened.state.regions.erase(region)
	for region in World.TRANSIT.TEA_STOPS:reopened.state.regions.erase(region)
	for region in World.TRANSIT.LOCAL:reopened.state.regions.erase(region)
	reopened.state.regions.erase(World.PARTY_CART.REGION)
	reopened.state.regions.erase(Regions.JINGUASHI)
	reopened.state.erase("jinguashi")
	for region in World.MINES.IDS:reopened.state.regions.erase(region)
	reopened.state.erase("mine_depths")
	reopened.state.players.beta.region = Regions.LANYANG
	reopened.state.players.beta.x = 12.5
	reopened.state.players.beta.y = 20.5
	reopened.state.copper.ready = reopened.state.time + 3
	expect(reopened.save() and world.load_world(path) and not world.recovered_from_backup and world.state.version == preload("res://scripts/save_schema.gd").VERSION and world.state.copper.ready == world.state.time + 3 and world.state.regions.has(Regions.JINGUASHI),"V4 main save migration preserves home copper timer and adds the new region")
	for layer in [world.state,world.state.regions.lanyang,world.state.regions.jinguashi]:
		layer.crops["13,20"] = {"kind":"radish","owner":"alpha","growth":0.0,"wet":false,"remaining":1}
		layer.objects["13,21"] = {"type":"sprinkler","owner":"alpha","items":{},"water":1,"enabled":true,"next_water":0.0,"last_water":-1.0}
	var before_tick := world.state.duplicate(true)
	world.save_path = path.path_join("missing").path_join("world")
	expect(not world.step(1.0,true) and world.state == before_tick,"All three regions and clock roll back together on failed automation save")
	world.save_path = path
	expect(world.step(1.0,true) and world.state.time == before_tick.time + 1.0 and world.state.crops["13,20"].wet and world.state.regions.lanyang.crops["13,20"].wet and world.state.regions.jinguashi.crops["13,20"].wet,"Three simultaneous device ticks advance the clock once")
	for file in [path,path+".bak"]:DirAccess.remove_absolute(file)
	print("JINGUASHI_TESTS checks=%d failures=%d" % [checks,failures])
	quit(int(failures>0))
