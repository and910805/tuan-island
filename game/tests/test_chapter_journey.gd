extends SceneTree
const World = preload("res://scripts/world.gd")
const TOKEN := "chapter-journey"
var world := World.new()
var actions := 0
var walking := 0
var failed := false
var checks := 0
var failures := 0

func _initialize() -> void:
	run_chapter_journey()

func run_chapter_journey() -> void:
	var path := OS.get_environment("TEMP").path_join("chapter-journey-%d.json" % Time.get_ticks_usec())
	# Never adopt or later delete a save this run did not create.
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
		expect(false, "Journey save path already exists: " + path)
		print("CHAPTER_JOURNEY_TESTS checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	expect(true, "Journey save path is new")
	world.save_path = path
	world.add_player(TOKEN, "Island")
	expect(World.CHAPTER_ONE.phase(world.state) == "grow", "Fresh world starts in the grow chapter phase")
	var tea_items := bag().keys().filter(func(item): return str(item).begins_with("tea_") or str(item) == "clay")
	expect(not world.state.tea_ceramics.players.has(TOKEN) and World.TEA_CERAMICS.own_record(world.state, TOKEN) == World.TEA_CERAMICS.FRESH and tea_items.is_empty(), "No tea progress or tea items before the first action")
	checkpoint("grow")
	var first := Vector2i(41,34)
	var plots := [first, Vector2i(42,34), Vector2i(41,35), Vector2i(42,35), Vector2i(41,36)]
	for index in plots.size():
		var kind := "radish" if index < 3 else "wheat"
		act("hoe", plots[index])
		act("seed", plots[index], kind)
		act("water", plots[index])
	expect(world.step(maxf(World.CROPS.wheat.time, World.CROPS.radish.time), true), "Advance crop growth")
	for plot in plots:
		act("harvest", plot)
	act("ship", World.SHIPPING.cell_for(world.state), JSON.stringify([[["radish",1]],24]))
	act("buy", Vector2i(43,29), "radish")
	for item in ["wood","stone"]:
		var need := 54 if item == "wood" else 33
		while int(bag().get(item,0)) < need and not failed:
			var target := find_resource("tree" if item == "wood" else "rock")
			if target == Vector2i(-1,-1):
				expect(false, "No reachable source for " + item)
				break
			for hit in range(3 if item == "wood" else 2):
				act("axe" if item == "wood" else "pick", target)
	act("donate", Vector2i(40,29))
	act("chapter_starter", World.CHAPTER_ONE.STARTER_CELL)
	checkpoint("water")
	act("build", Vector2i(43,34), "sprinkler")
	act("build", Vector2i(44,34), "water_pipe")
	act("build", Vector2i(44,35), "water_pipe")
	act("build", Vector2i(44,36), "water_tank")
	act("seed", Vector2i(42,34), "radish")
	act("refill_tank", Vector2i(44,36))
	act("toggle_sprinkler", Vector2i(43,34))
	expect(world.step(8.0,true), "Advance irrigation")
	expect(World.CHAPTER_ONE.phase(world.state) == "meal" and world.state.crops["42,34"].wet, "Network waters the planted second batch")
	act("build", Vector2i(40,34), "stove")
	for recipe in ["soup","bread"]:
		act("cook", Vector2i(40,34), recipe)
		expect(world.step(World.RECIPES[recipe].time,true), "Advance " + recipe)
		act("claim_cook", Vector2i(40,34))
	act("picnic", Vector2i(40,29))
	var table := World.COMMUNITY.table_cell(world.state)
	expect(table != World.COMMUNITY.NO_CELL and world.blocked(table) and not route(Vector2i(43,29)).is_empty(), "Public table leaves a passable route to the stall")
	checkpoint("complete")
	var reload := World.new()
	expect(FileAccess.file_exists(path) and reload.load_world(path) and not reload.recovered_from_backup and World.CHAPTER_ONE.phase(reload.state) == "complete", "Completed chapter reloads from the primary save")
	after_chapter()
	print("CHAPTER_JOURNEY actions=%d walk_tiles=%d world_seconds=%.1f coins=%d inventory=%s passed=%s" % [actions, walking, world.state.time, person().coins, JSON.stringify(bag()), not failed])
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path+".bak")
	print("CHAPTER_JOURNEY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failed))

func after_chapter()->void:
	pass

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		failed = true
		push_error(message)

func person() -> Dictionary:
	return world.state.players[TOKEN]

func checkpoint(stage: String) -> void:
	if failed:
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-output-prefix="):
			var file := FileAccess.open(argument.trim_prefix("--qa-output-prefix=") + "-" + stage + ".json", FileAccess.WRITE)
			if file == null:
				expect(false, "Open " + stage + " checkpoint")
				return
			file.store_string(JSON.stringify(world.state))
			file.flush()
			var status := file.get_error()
			file.close()
			expect(status == OK, "Write " + stage + " checkpoint")

func bag() -> Dictionary:
	return person().inventory

func find_resource(kind: String) -> Vector2i:
	var origin := Vector2i(int(person().x),int(person().y))
	for distance in range(1,30):
		for y in range(origin.y-distance,origin.y+distance+1):
			for x in range(origin.x-distance,origin.x+distance+1):
				var tile := Vector2i(x,y)
				if maxi(absi(x-origin.x),absi(y-origin.y)) != distance:
					continue
				if world.resource(tile) == kind and not world.protected(tile) and not route(tile).is_empty():
					return tile
	return Vector2i(-1,-1)

func route(target: Vector2i, reach: float = 2.0, actor:String=TOKEN) -> Array:
	var local_world:=World.new()
	local_world.state=world.region_snapshot(world.player_region(actor))
	local_world._region=world.player_region(actor)
	var walker:Dictionary=world.state.players[actor]
	var start := Vector2i(int(walker.x),int(walker.y))
	var queue := [start]
	var previous := {start: start}
	var index := 0
	while index < queue.size():
		var tile: Vector2i = queue[index]
		index += 1
		if tile != target and Vector2(tile-target).length() <= reach:
			var path := [tile]
			while tile != start:
				tile = previous[tile]
				path.push_front(tile)
			return path
		for offset in World.INDUSTRY.NEIGHBORS:
			var next: Vector2i = tile+offset
			if not previous.has(next) and local_world.can_stand(Vector2(next)+Vector2(0.5,0.5)):
				previous[next]=tile
				queue.append(next)
	return []

func walk_to(target: Vector2i, reach: float = 2.0, actor:String=TOKEN) -> void:
	if failed:
		return
	var path := route(target,reach,actor)
	if path.is_empty():
		expect(false, "No path to %s" % target)
		return
	for index in range(1,path.size()):
		var direction := Vector2(path[index]-path[index-1])
		for step in range(4):
			world.move_player(actor,direction,0.25/3.6)
		walking += 1
		var walker:Dictionary=world.state.players[actor]
		expect(Vector2(walker.x,walker.y).distance_to(Vector2(path[index])+Vector2(0.5,0.5)) <= 0.001, "Movement did not follow passable route")
		if failed:
			return
func collect_gathered(target: Vector2i) -> void:
	if Vector2(person().x,person().y).distance_to(Vector2(target)+Vector2(0.5,0.5))>World.GATHER_PICKUP_RADIUS:
		walk_to(target,1.0)
	if failed:return
	expect(world.step(ceilf(World.GATHER_DROP_DELAY),true),"Ground items land and can be picked up")
	var drops:Dictionary=world.state.get("gather_drops",{}).get(world.player_region(TOKEN),{})
	expect(not drops.has(World.key(target)),"Picked up the bundle at %s (position %s, active %s, time %.2f, drop %s)"%[target,Vector2(person().x,person().y),world.active_tokens.has(TOKEN),float(world.state.time),drops.get(World.key(target),{})])

func act(action: String, target: Vector2i, extra: String = "") -> void:
	walk_to(target)
	if failed:return
	actions += 1
	var result := world.act(TOKEN,"journey-%d"%actions,action,target,extra)
	print("%d %s %s %s | %s | wood=%d stone=%d coins=%d" % [actions,action,target,extra,result.message,bag().wood,bag().stone,person().coins])
	expect(result.ok, "World action failed: " + action)
	if result.get("gather_dropped",false):collect_gathered(target)
