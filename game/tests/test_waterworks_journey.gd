extends "res://tests/test_station_life_journey.gd"

# The public mill (MillRestoration) permanently reserves its approach cell (48,26), so the
# output chest can no longer sit there. The whole line sits one column east; the water
# network turns north because (54,y) is public shore and a pump there is refused.
const WORKSHOP := Vector2i(51,26)
const ORE_CHEST := Vector2i(51,24)
const ORE_BELT := Vector2i(51,25)
const WOOD_CHEST := Vector2i(51,28)
const WOOD_BELT := Vector2i(51,27)
const OUT_CHEST := Vector2i(49,26)
const OUT_BELT := Vector2i(50,26)
const PIPE := Vector2i(52,26)
const TANK := Vector2i(52,25)
const PUMP := Vector2i(53,25)
const SPRINKLER := Vector2i(52,27)
const EXPANSION_PLOT := Vector2i(52,28)
const BENCH := GARDEN_JOURNEY_BENCH
const KILN := Vector2i(41,37)

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	collect_production_ore()
	gather("wood","tree","axe",131,3)
	gather("stone","rock","pick",22,2)
	for batch in range(11):mill_batch(MILL)
	act("start_processing",KILN,"charcoal")
	expect(world.step(World.INDUSTRY.PROCESS.charcoal.time,true),"Natural charcoal fires the home pump kit")
	act("claim_processing",KILN)
	for batch in range(12):act("craft",BENCH,"copper_joint")
	for kit in ["waterworks_kit","pump_kit","pipe_kit","tank_kit","conveyor_kit","conveyor_kit"]:
		act("craft",BENCH,kit)
	if failed:return
	build_clear(WORKSHOP,"waterworks")
	for cell in [ORE_CHEST,WOOD_CHEST,OUT_CHEST]:build_clear(cell,"private_chest")
	build_clear(PIPE,"water_pipe")
	build_clear(TANK,"water_tank")
	build_clear(PUMP,"water_pump")
	configure_belt(ORE_BELT,2,"copper_ore")
	configure_belt(WOOD_BELT,0,"wood")
	configure_belt(OUT_BELT,3,"copper_joint")
	for unit in range(4):act("deposit",ORE_CHEST,"copper_ore")
	for unit in range(2):act("deposit",WOOD_CHEST,"wood")
	act("toggle_pump",PUMP)
	checkpoint("waterworks-before")
	act("waterworks_toggle",WORKSHOP)
	for tick in range(8):
		expect(world.step(World.LOGISTICS.INTERVAL,true),"Pump and conveyor world clock advances")
		if workbench().has("job"):break
	expect(workbench().has("job"),"Same-owner river network and both belt inputs start an unattended batch")
	checkpoint("waterworks-running")
	for tick in range(24):
		expect(world.step(World.LOGISTICS.INTERVAL,true),"Unattended production and conveyor transfer advance")
	expect(output_count()==2 and not workbench().has("job"),"Exactly two joints reach the private output chest and missing inputs stop production")
	expect(world.step(12.0,true) and output_count()==2 and not workbench().has("job"),"Lack of feed cannot start a phantom batch")
	checkpoint("waterworks-output")
	for unit in range(2):act("withdraw",OUT_CHEST,"copper_joint")
	act("craft",BENCH,"sprinkler_kit")
	expect(int(bag().get("copper_joint",0))==0,"Original sprinkler recipe consumes the two produced joints")
	build_clear(SPRINKLER,"sprinkler")
	if world.resource(EXPANSION_PLOT)=="grass":act("axe",EXPANSION_PLOT)
	act("hoe",EXPANSION_PLOT)
	act("seed",EXPANSION_PLOT,"radish")
	act("toggle_sprinkler",SPRINKLER)
	if failed:return
	expect(world.step(World.INDUSTRY.INTERVAL,true) and world.state.crops[World.key(EXPANSION_PLOT)].wet,"Expanded farm plot is irrigated by the existing network")
	checkpoint("waterworks-expandedfarm")
	var reopened := World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"Production and expanded farm reload the primary save")
	if failed:return
	world=reopened
	world.add_player(TOKEN,str(person().name))
	expect(workbench().type=="waterworks" and output_count()==0 and world.state.crops[World.key(EXPANSION_PLOT)].wet,"Reload keeps the workshop, emptied output and watered expansion")
	checkpoint("waterworks-reloaded")
	print("WATERWORKS_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f" % [actions,walking,world.state.time])

func collect_production_ore() -> void:
	act("transit",World.REGIONS.exit_cell("home"),"jinguashi")
	for node: Vector2i in World.JINGUASHI.NODES:act("pick",node)
	if int(bag().get("copper_ore",0))<32:
		expect(world.step(World.JINGUASHI.COOLDOWN,true),"Surface ore respawns in normal world time")
		act("pick",World.JINGUASHI.NODES[0])
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")

func build_clear(cell: Vector2i, kind: String) -> void:
	match world.resource(cell):
		"grass":act("axe",cell)
		"tree":
			for hit in range(3):act("axe",cell)
		"rock":
			for hit in range(2):act("pick",cell)
	act("build",cell,kind)

func configure_belt(cell: Vector2i, direction: int, item: String) -> void:
	build_clear(cell,"conveyor")
	act("configure_conveyor",cell,"dir:%d"%direction)
	act("configure_conveyor",cell,"filter:"+item)
	act("toggle_conveyor",cell)

func workbench() -> Dictionary:
	return world.state.objects.get(World.key(WORKSHOP),{})

func output_count() -> int:
	return int(world.state.objects.get(World.key(OUT_CHEST),{}).get("items",{}).get("copper_joint",0))
