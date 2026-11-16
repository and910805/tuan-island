extends "res://tests/test_bobo_journey.gd"

const FARMER := "transit-farm-neighbor"
const FARM_PLOT := Vector2i(42,35)
const NETWORK := ["toucheng","ruifang","jiufen","jinguashi"]
const DEPARTURES := ["rail","bus","shuttle"]
var trip_clock := 0.0


func first_mountain_trip() -> void:
	act("seed",FARM_PLOT,"radish")
	act("water",FARM_PLOT)
	if failed:return
	world.add_player(FARMER,"田區島民")
	expect(world.player_region(FARMER)=="home","Second islander remains at the home field")
	var neighbor_before: Dictionary = world.state.players[FARMER].duplicate(true)
	var crop_key := World.key(FARM_PLOT)
	var growth_before := float(world.state.crops[crop_key].growth)
	trip_clock=float(world.state.time)
	attempt_locked_hop(World.REGIONS.exit_cell("home"),"jinguashi")
	act("transit",World.REGIONS.exit_cell("home"),NETWORK[0])
	assert_leg(NETWORK[0])
	for index in range(1,NETWORK.size()):
		var station: Vector2i = World.TRANSIT.points(NETWORK[index-1])[DEPARTURES[index-1]].cell
		var walk_start := walking
		walk_to(station,1.0)
		if index==1:attempt_locked_hop(station,"jiufen")
		act("transit",station,NETWORK[index])
		expect(walking>walk_start,"Walk to the connecting station before boarding")
		assert_leg(NETWORK[index])
	expect(world.state.players[FARMER]==neighbor_before,"The islander who stayed home keeps their region, position and inventory")
	expect(float(world.state.crops[crop_key].growth)==growth_before,"Boarding and transfer do not grow the farm crop")
	expect(world.step(1.0,true) and float(world.state.crops[crop_key].growth)>growth_before,"The home crop advances on an ordinary world tick while the traveler stays in Jinguashi")

func attempt_locked_hop(station: Vector2i, destination: String) -> void:
	if failed:return
	walk_to(station)
	if failed:return
	var before:=world.state.duplicate(true)
	actions+=1
	var result := world.act(TOKEN,"journey-%d"%actions,"transit",station,destination)
	print("%d transit %s %s | %s" % [actions,station,destination,result.message])
	expect(not result.ok and world.state==before,"Unvisited shortcut is rejected without changing the world")

func assert_leg(region: String) -> void:
	expect(world.player_region(TOKEN)==region and float(world.state.time)==trip_clock,"Scheduled connection lands in " + region + " without a world clock jump")
	checkpoint("transit-"+region)

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	var coins := int(person().coins)
	var carry := bag().duplicate(true)
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")
	expect(world.player_region(TOKEN)=="home" and int(person().coins)==coins and bag()==carry,"Free return retains fare balance and cargo")
	checkpoint("transit-home")
	var reopened := World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup and reopened.player_region(TOKEN)=="home","Return survives reopening the primary save")
	if failed:return
	world=reopened
	var departure: Vector2i = World.TRANSIT.points("home").ferry.cell
	expect(person().travel_book.visited.size()==NETWORK.size()+1 and person().travel_book.visited.has("home") and not person().travel_book.visited.has("maokong") and not person().travel_book.visited.has("yingge"),"Visited mountain route survives reload without inventing tea branch visits")
	var shortcut_options := World.TRANSIT.route_options(world.state,TOKEN,"ferry")
	for destination in NETWORK:
		expect(shortcut_options.any(func(option):return option.region==destination),"Visited destination is listed: " + destination)
	act("transit",departure,"jinguashi")
	expect(world.player_region(TOKEN)=="jinguashi","A single transfer returns to the already visited mining town")
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")
	checkpoint("transit-reloaded")
	print("TRANSIT_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f" % [actions,walking,world.state.time])
