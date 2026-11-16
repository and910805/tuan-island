extends "res://tests/test_transit_journey.gd"

const STOPS := ["toucheng","ruifang","jiufen"]
const STOVE := Vector2i(40,34)
const MILL := Vector2i(40,36)
const WHEAT_PLOT := Vector2i(42,36)

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	var ferry: Vector2i = World.TRANSIT.points("home").ferry.cell
	gather("wood","tree","axe",12,3)
	gather("stone","rock","pick",6,2)
	for batch in range(3):mill_batch(MILL)
	if int(bag().get("wheat",0))<2:
		act("seed",WHEAT_PLOT,"wheat")
		act("water",WHEAT_PLOT)
		expect(world.step(World.CROPS.wheat.time,true),"Naturally planted wheat matures")
		act("harvest",WHEAT_PLOT)
	act("cook",STOVE,"bread")
	expect(world.step(World.RECIPES.bread.time,true),"Bread bakes at the original home stove")
	act("claim_cook",STOVE)
	var before := int(person().coins)
	var saplings := int(bag().get("sapling",0))
	var plank := int(bag().get("plank",0))
	var stone := int(bag().get("stone",0))
	var bread := int(bag().get("bread",0))
	var clock := float(world.state.time)
	var npc: Vector2i = World.STATION_LIFE.RESIDENTS.toucheng.cell
	act("transit",ferry,"toucheng")
	walk_to(npc)
	checkpoint("station-toucheng-first")
	act("station_story",npc,"0")
	expect(stage()==1,"Toucheng resident starts the personal story")
	repair("toucheng")
	var rail: Vector2i = World.TRANSIT.points("toucheng").rail.cell
	act("transit",rail,"ruifang")
	npc=World.STATION_LIFE.RESIDENTS.ruifang.cell
	expect_rejected("station_story",npc,"1")
	repair("ruifang")
	walk_to(npc)
	checkpoint("station-ruifang-repaired")
	act("station_story",npc,"1")
	expect(stage()==2,"Repairing the public bench unlocks the next story stage")
	var bus: Vector2i = World.TRANSIT.points("ruifang").bus.cell
	act("transit",bus,"jiufen")
	npc=World.STATION_LIFE.RESIDENTS.jiufen.cell
	repair("jiufen")
	walk_to(npc)
	checkpoint("station-jiufen-delivery")
	act("station_story",npc,"2")
	expect(stage()==3 and int(bag().get("bread",0))==bread-1,"Jiufen resident receives exactly one naturally baked bread")
	expect(int(bag().get("plank",0))==plank-6 and int(bag().get("stone",0))==stone-6,"Three public repairs consume exactly six boards and six stones")
	var shuttle: Vector2i = World.TRANSIT.points("jiufen").shuttle.cell
	act("transit",shuttle,"toucheng")
	npc=World.STATION_LIFE.RESIDENTS.toucheng.cell
	walk_to(npc)
	checkpoint("station-toucheng-reward-ready")
	act("station_story",npc,"3")
	expect(stage()==4 and int(person().coins)==before+80 and int(bag().get("sapling",0))==saplings+1,"Finishing the personal story awards 80 coins and one seedling exactly once")
	expect_rejected("station_story",npc,"3")
	expect_rejected("station_story",npc,"4")
	expect_rejected("station_repair",World.STATION_LIFE.RESIDENTS.toucheng.cell,"toucheng")
	checkpoint("station-toucheng-done")
	var street: Vector2i = World.TRANSIT.points("toucheng").street.cell
	act("transit",street,"home")
	expect(float(world.state.time)==clock,"Station actions and travel do not jump the world clock")
	checkpoint("station-home")
	var reopened := World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"Station journey reloads the primary save")
	if failed:return
	world=reopened
	expect(stage()==4 and world.player_region(TOKEN)=="home" and int(person().coins)==before+80 and int(bag().sapling)==saplings+1,"Reload preserves personal completion, reward, and free return")
	for stop in STOPS:
		expect(world.state.station_life.repairs.get(stop,false),"Public repair survives reload at "+stop)
	expect(int(world.state.station_life.players.get(FARMER,{}).get("stage",0))==0,"The islander at home gains no personal story progress")
	checkpoint("station-reloaded")
	print("STATION_LIFE_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f" % [actions,walking,world.state.time])

func stage() -> int:
	return int(world.state.station_life.players.get(TOKEN,{}).get("stage",0))

func repair(stop: String) -> void:
	act("station_repair",World.STATION_LIFE.RESIDENTS[stop].cell,stop)
	expect(world.state.station_life.repairs.get(stop,false),"Station repair is shared at "+stop)

func expect_rejected(action: String, target: Vector2i, extra: String) -> void:
	walk_to(target)
	if failed:return
	var unchanged := world.state.duplicate(true)
	actions+=1
	var result := world.act(TOKEN,"journey-%d"%actions,action,target,extra)
	print("%d %s %s %s | %s" % [actions,action,target,extra,result.message])
	expect(not result.ok and world.state==unchanged,"Rejected station action preserves materials, coins and progress")
