extends "res://tests/test_regions_journey.gd"

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	var bench := Vector2i(40,35)
	var mill := Vector2i(40,36)
	gather("wood","tree","axe",42,3)
	gather("stone","rock","pick",17,2)
	act("build",bench,"bench")
	act("craft",bench,"sawmill_kit")
	act("build",mill,"sawmill")
	for count in range(3):
		mill_batch(mill)
	expect(int(bag().plank) == 6,"Three real sawmill batches produce repair planks")
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	checkpoint("newbefore")
	for site: Vector2i in World.LANYANG_LIFE.BLOCKAGES:
		act("lanyang_clear",site)
	expect(world.state.lanyang_life.cleared.size() == 3,"All three waterway blockages cleared")
	checkpoint("cleared")
	var service := World.LANYANG_LIFE.SERVICE
	act("lanyang_donate",service)
	expect(world.state.lanyang_life.repaired and int(bag().plank) == 0,"Crafted boards fund the repair")
	checkpoint("repaired")
	var prior: int = bag().sapling
	act("nursery_start",service)
	expect(int(bag().sapling) == prior - 1,"Nursery consumed one tree seedling")
	checkpoint("nursery")
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	expect(world.step(World.LANYANG_LIFE.NURSERY_TIME,true),"Accelerated nursery wait takes place back at home")
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	checkpoint("ready")
	act("nursery_claim",service)
	expect(int(bag().sapling) == prior + 2,"Ready nursery returned three seedlings")
	var plot := Vector2i(14,24)
	act("plant_tree",plot)
	expect(world.step(World.TREE_TIME,true) and world.state.regions.lanyang.forest[World.key(plot)].mature,"A planted tree matures in Lanyang")
	checkpoint("forest")
	var lumber: int = bag().wood
	for hit in range(3):act("axe",plot)
	expect(int(bag().wood) == lumber + 6,"Harvesting the planted tree yields usable wood")
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	mill_batch(mill)
	expect(int(bag().plank) == 2 and not world.state.lanyang_life.jobs.has(TOKEN),"Lanyang wood closes the production loop at home")
	var reload := World.new()
	expect(reload.load_world(world.save_path) and reload.state.lanyang_life.repaired and reload.player_region(TOKEN) == "home" and reload.state.players[TOKEN].inventory.plank == 2,"Repair, production and return persist")
	print("GARDEN_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f" % [actions,walking,world.state.time])

func gather(item: String, kind: String, tool: String, minimum: int, hits: int) -> void:
	while int(bag().get(item,0)) < minimum and not failed:
		var target := find_resource(kind)
		if target == Vector2i(-1,-1):
			expect(false,"No reachable " + kind)
			return
		for hit in range(hits):act(tool,target)

func mill_batch(mill: Vector2i) -> void:
	act("start_processing",mill,"plank")
	expect(world.step(World.INDUSTRY.PROCESS.plank.time,true),"Accelerated sawmill processing completes")
	act("claim_processing",mill)
