extends SceneTree

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const FIELD := Vector2i(38, 34)
const STOVE := Vector2i(38, 33)
const WATER := Vector2i(55, 34)

var w = World.new()
var sequence := 0
var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func act(action: String, cell: Vector2i, extra: String = "", player: String = "alice") -> Dictionary:
	sequence += 1
	return w.act(player, "collection-%d" % sequence, action, cell, extra)

func claim(id: String, player: String = "alice") -> Dictionary:
	return act("claim_milestone", Vector2i.ZERO, id, player)

func grow(crop: String) -> void:
	expect(act("seed", FIELD, crop).ok, "seed " + crop)
	expect(act("water", FIELD).ok, "water " + crop)
	w.step(151.0, true)

func _initialize() -> void:
	w.add_player("alice", "米米")
	w.add_player("bob", "豆豆")
	var path := OS.get_environment("TEMP").path_join("tuantuan-collection-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	expect(DirAccess.make_dir_absolute(path) == OK, "isolated save directory")
	var save := path.path_join("world.json")
	var legacy: Dictionary = w.state.players.alice
	legacy.erase("collection")
	legacy.harvests = 30
	legacy.fish_caught = 5
	legacy.cooked = 20
	legacy.inventory.merge({"carp": 3, "radish": 3, "soup": 3, "stone": 30, "wood": 60}, true)
	w.save_path = save
	expect(w.save(), "legacy world saved")
	w = World.new()
	expect(w.load_world(save), "legacy world migrated")
	var alice: Dictionary = w.state.players.alice
	expect(alice.collection == {"crops": {}, "fish": {}, "meals": {}, "claimed": {}}, "legacy counters and inventory do not count as discoveries")
	expect(not claim("garden_sampler").ok, "early milestone denied")
	expect(not claim("forged").ok, "unknown milestone denied")

	expect(act("hoe", FIELD).ok, "prepare plot")
	expect(not act("harvest", FIELD).ok, "empty plot does not count")
	for crop in ["radish", "radish", "lettuce"]:
		grow(crop)
		expect(act("harvest", FIELD).ok, "harvest " + crop)
	expect(alice.collection.crops == {"radish": true, "lettuce": true}, "duplicates count once")
	expect(not claim("garden_sampler").ok, "two species are insufficient")
	grow("wheat")
	w.save_path = path.path_join("missing/world.json")
	expect(not act("harvest", FIELD).ok, "failed save rejects harvest")
	alice = w.state.players.alice
	expect(not alice.collection.crops.has("wheat") and w.state.crops[World.key(FIELD)].kind == "wheat", "failed harvest restores plot and discovery")
	w.save_path = save
	expect(act("harvest", FIELD).ok, "harvest retries after storage recovers")
	grow("wheat")
	expect(act("harvest", FIELD).ok, "second wheat harvest stocks the kitchen")
	w.save_path = path.path_join("missing/world.json")
	var coins_before: int = alice.coins
	expect(not w.act("alice", "claim-once", "claim_milestone", Vector2i.ZERO, "garden_sampler").ok, "failed save rejects reward")
	alice = w.state.players.alice
	expect(alice.coins == coins_before and not alice.inventory.has("tomato_seed") and not alice.collection.claimed.has("garden_sampler"), "reward and marker roll back together")
	w.save_path = save
	expect(w.act("alice", "claim-once", "claim_milestone", Vector2i.ZERO, "garden_sampler").ok, "same request retries after save failure")
	expect(alice.coins == coins_before + 60 and alice.inventory.tomato_seed == 2, "garden reward matches display")
	expect(w.act("alice", "claim-once", "claim_milestone", Vector2i.ZERO, "garden_sampler").ok, "exact retry receives prior receipt")
	expect(alice.coins == coins_before + 60 and not claim("garden_sampler").ok, "receipt replay and fresh id cannot pay twice")
	expect(not claim("garden_sampler", "bob").ok, "another player cannot use Alice's progress")

	alice.x = 54.5
	alice.y = 34.5
	for fish_id in ["minnow", "redfish", "loach", "carp"]:
		expect(act("fish_start", WATER).ok, "cast at river")
		expect(not act("fish_catch", WATER).ok, "early catch denied")
		expect(not alice.collection.fish.has(fish_id), "early catch records no " + fish_id)
		w.step(3.1, true)
		expect(act("fish_catch", WATER).ok and alice.collection.fish.has(fish_id), "old rotation records " + fish_id)
	expect(alice.fish_discoveries.size()==4 and alice.fish_discoveries.carp.region=="home","Each new species records its first location")
	var first_minnow:Dictionary=alice.fish_discoveries.minnow.duplicate()
	var island_first:Dictionary=w.state.island_fish_discoveries.minnow.duplicate()
	var rival:Dictionary=w.state.players.bob
	var prior_position:=Vector2(rival.x,rival.y)
	rival.x=alice.x
	rival.y=alice.y
	rival.fish_caught=1
	expect(act("fish_start",WATER,"","bob").ok and w.step(3.1,true),"Another player casts at the river")
	expect(act("fish_catch",WATER,"","bob").ok and rival.collection.fish.has("minnow"),"Another player gets independent discovery")
	expect(w.state.island_fish_discoveries.minnow==island_first,"Second player cannot overwrite island first")
	rival.collection.fish.clear()
	rival.erase("fish_discoveries")
	rival.x=prior_position.x
	rival.y=prior_position.y
	expect(claim("fish_survey").ok and alice.coins == coins_before + 160, "four species pay fish reward")

	alice.x = World.SPAWN.x
	alice.y = World.SPAWN.y
	expect(act("build", STOVE, "stove").ok, "build working stove")
	for recipe in ["feed", "soup", "bread", "grilled_fish"]:
		expect(act("cook", STOVE, recipe).ok, "start " + recipe)
		expect(not act("claim_cook", STOVE).ok, "early claim denied")
		expect(not alice.collection.meals.has(recipe), "starting a recipe records no " + recipe)
		w.step(16.0, true)
		expect(act("claim_cook", STOVE).ok, "claim finished " + recipe)
	expect(alice.collection.meals == {"soup": true, "bread": true, "grilled_fish": true}, "only claimed meals count")
	expect(claim("kitchen_sampler").ok and alice.coins == coins_before + 240 and alice.inventory.carrot_seed == 2, "third milestone pays kitchen reward")
	expect(w.state.players.bob.collection == {"crops": {}, "fish": {}, "meals": {}, "claimed": {}}, "all discoveries are player-specific")
	expect(act("cook", STOVE, "grilled_fish").ok, "Alice starts a shared stove order")
	w.step(16.0, true)
	expect(act("claim_cook", STOVE, "", "bob").ok, "Bob collects the shared order")
	expect(w.state.players.bob.collection.meals == {"grilled_fish": true}, "shared order discovery follows the player who collects")

	expect(w.state.island_meals_discoveries.grilled_fish.name==w.state.players.alice.name and w.state.players.bob.meals_discoveries.grilled_fish.region=="home","Later collector has a personal record without replacing the first collector")
	expect(w.state.island_crops_discoveries.wheat.region=="home","First harvested crop stores its region")
	alice.inventory["strawberry"]=2
	alice.inventory["cucumber"]=2
	expect(not act("cook",STOVE,"strawberry_jam").ok and alice.inventory.strawberry==2,"Missing sugar leaves the strawberries intact")
	alice.inventory["sugar_beet"]=1
	expect(act("queue_cook",STOVE,"sugar").ok and alice.inventory.get("sugar_beet",0)==0,"Beet sugar recipe consumes the root")
	expect(w.step(40.1,true) and act("claim_cook",STOVE).ok and alice.inventory.get("sugar",0)==2,"One beet produces two sugar")
	expect(not alice.collection.meals.has("sugar"),"Sugar is an ingredient and does not count as a dish")
	alice.inventory["snow_trout"]=1
	alice.inventory["cabbage"]=1
	alice.inventory["star_mushroom"]=1
	alice.inventory["sweet_potato"]=2
	for dish in ["strawberry_jam","cucumber_salad","trout_hotpot","roasted_sweet_potato"]:
		var portions:int=World.RECIPES[dish].yield
		var queued:=act("queue_cook",STOVE,dish)
		expect(queued.ok,"Queue "+dish+": "+str(queued.message))
		for ingredient in World.RECIPES[dish].ingredients:
			expect(int(alice.inventory.get(ingredient,0))==(1 if ingredient=="sugar" else 0),"Use the required "+ingredient)
		expect(not act("claim_cook",STOVE).ok,"Cannot collect early "+dish)
		expect(w.step(float(World.RECIPES[dish].time)+0.1,true),"Prepare "+dish)
		expect(act("claim_cook",STOVE).ok and alice.inventory.get(dish,0)==portions and alice.collection.meals.has(dish),"Collect the correct portions and register "+dish)
		expect(not act("claim_cook",STOVE).ok and alice.inventory.get(dish,0)==portions,"Cannot claim the portions twice")
	var restored = World.new()
	expect(restored.load_world(save), "world reloads")
	expect(restored.state.island_crops_discoveries.wheat==w.state.island_crops_discoveries.wheat and restored.state.island_meals_discoveries.grilled_fish==w.state.island_meals_discoveries.grilled_fish,"Crop and meal records survive reload")
	restored.add_player("alice", "米米")
	expect(restored.state.players.alice.collection == alice.collection, "discoveries and claims survive rejoining")
	expect(not restored.act("alice", "new-session", "claim_milestone", Vector2i.ZERO, "garden_sampler").ok, "new session cannot reclaim")
	restored.state.players.alice.receipts.clear()
	expect(not restored.act("alice", "claim-once", "claim_milestone", Vector2i.ZERO, "garden_sampler").ok, "old request cannot reclaim after receipt eviction")

	var invalid: Dictionary = restored.state.duplicate(true)
	invalid.players.alice.collection.meals.feed = true
	expect(not Schema.validate(invalid, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME), "schema rejects feed discovery")
	invalid = restored.state.duplicate(true)
	invalid.players.bob.collection.claimed.fish_survey = true
	expect(not Schema.validate(invalid, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME), "schema rejects inconsistent claim")
	invalid = restored.state.duplicate(true)
	invalid.players.alice.collection.fish.carp = false
	expect(not Schema.validate(invalid, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME), "schema rejects false discovery markers")

	var local_water:=Vector2i(33,26)
	var fisher:Dictionary=restored.state.players.alice
	fisher.region="lanyang"
	fisher.x=32.5
	fisher.y=26.5
	fisher.fish_caught=0
	restored.state.time=2*World.WEATHER.DAYS_PER_SEASON*World.WEATHER.DAY_SECONDS
	for cast in range(19):
		expect(restored.act("alice","rare-cast-%d"%cast,"fish_start",local_water).ok,"Cast in autumn canal")
		expect(restored.step(3.1,true),"Wait for canal bite")
		expect(restored.act("alice","rare-catch-%d"%cast,"fish_catch",local_water).ok,"Land eligible catch")
	expect(fisher.get("rare_fishing_misses",0)==19,"Nineteen eligible common catches accrue pity")
	var resumed:=World.new()
	expect(resumed.load_world(save) and not resumed.recovered_from_backup,"Load the latest fishing record")
	var angler:Dictionary=resumed.state.players.alice
	expect(resumed.region_snapshot("beimen").island_fish_discoveries.minnow==island_first,"Island first survives reloading and is visible from another region")
	expect(angler.fish_discoveries.minnow==first_minnow,"Later catches elsewhere and reload preserve first location and date")
	expect(angler.get("rare_fishing_misses",0)==19,"Pity survives reload")
	expect(resumed.act("alice","final-cast","fish_start",local_water).ok,"Cast for guaranteed candidate")
	expect(not resumed.act("alice","early-finish","fish_catch",local_water).ok and angler.rare_fishing_misses==19,"Early reel leaves pity intact")
	expect(resumed.step(3.1,true),"Wait for guaranteed bite")
	var loaches:=int(angler.inventory.get("loach",0))
	var rare:=resumed.act("alice","final-reel","fish_catch",local_water)
	expect(rare.ok and angler.inventory.loach==loaches+1 and angler.rare_fishing_misses==0,"Twentieth catch awards loach and resets pity")
	expect(resumed.act("alice","final-reel","fish_catch",local_water)==rare and angler.inventory.loach==loaches+1,"Replay cannot award a second loach")
	resumed.state.time=2*World.WEATHER.DAY_SECONDS+720.0
	angler.rare_fishing_misses=19
	expect(World.WEATHER.rains(World.WEATHER.day_index(resumed.state.time),"lanyang"),"Spring day three is rainy")
	expect(resumed.act("alice","spring-rain-cast","fish_start",local_water).ok and resumed.step(3.1,true),"Cast in the canal during spring rain")
	expect(resumed.act("alice","spring-rain-reel","fish_catch",local_water).ok and angler.inventory.loach==loaches+2 and angler.rare_fishing_misses==0,"Spring rain uses the same saved canal guarantee")
	expect(not World.Collections.fishing_result("lanyang","spring",0,{"rare_fishing_misses":19}).has("counter"),"Dry spring does not spend the canal guarantee")
	expect(not World.Collections.fishing_result("home","spring",0,{"rare_fishing_misses":19},720.0,"coast",true).has("counter"),"Rain elsewhere does not spend the canal guarantee")

	var regional_progress:={"rare_fishing_misses":17,"beimen_flounder_misses":19}
	var northern:=World.Collections.fishing_result("lanyang","autumn",0,regional_progress)
	var coast:=World.Collections.fishing_result("beimen","summer",0,regional_progress,1260.0)
	var off_season:=World.Collections.fishing_result("beimen","winter",0,regional_progress)
	expect(northern.counter=="rare_fishing_misses" and northern.misses==18,"Canal owns its own counter")
	expect(coast.counter=="beimen_flounder_misses" and coast.id=="flounder" and coast.misses==0,"Coastal catch has a separate guarantee")
	expect(off_season.id=="sardine" and not off_season.has("counter") and regional_progress.beimen_flounder_misses==19,"Off-season catch does not advance or reset the counter")
	var broken:Dictionary=resumed.state.duplicate(true)
	broken.players.alice.beimen_flounder_misses=20
	expect(not Schema.validate(broken,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Out-of-range coastal counter is rejected")

	expect(World.Collections.water_clues("beimen",{"fish_caught":7}).is_empty(),"Water clues stay locked at level two")
	expect(World.Collections.angling_level({"fish_caught":8})==3 and not World.Collections.water_clues("beimen",{"fish_caught":8}).is_empty(),"Eighth catch unlocks local clues")
	var skilled:={"fish_caught":45}
	expect(World.Collections.fishing_forecast("beimen",{"fish_caught":44},1199.0).is_empty(),"Forecast unlocks at level six")
	expect(World.Collections.fishing_forecast("beimen",skilled,1199.0).contains("20:00"),"Day forecast gives the night transition")
	expect(World.Collections.fishing_forecast("beimen",skilled,1200.0).contains("明日 06:00"),"Night forecast rolls the transition into tomorrow")
	expect(not World.Collections.fishing_forecast("beimen",skilled,359.0).contains("明日"),"Predawn forecast shows today's sunrise")
	var coast_world:=World.new()
	coast_world.add_player("coast","Coast")
	var coast_player:Dictionary=coast_world.state.players.coast
	coast_player.region="beimen"
	coast_player.x=50.5
	coast_player.y=25.5
	var sea:=Vector2i(52,25)
	coast_world.state.time=720.0
	expect(coast_world.act("coast","day-cast","fish_start",sea).ok and coast_world.step(3.1,true),"Cast on Beimen coast by day")
	expect(coast_world.act("coast","day-reel","fish_catch",sea).ok and coast_player.inventory.get("sardine",0)==1,"Daytime Beimen yields sardine")
	coast_world.state.time=1260.0
	for cast in range(20):
		expect(coast_world.act("coast","night-cast-%d"%cast,"fish_start",sea).ok and coast_world.step(3.1,true),"Cast on Beimen coast by night")
		expect(coast_world.act("coast","night-reel-%d"%cast,"fish_catch",sea).ok,"Land coastal catch")
	expect(coast_player.inventory.get("flounder",0)==1 and coast_player.beimen_flounder_misses==0,"Twentieth night catch guarantees flounder")

	for spot in [{"id":"moon_squid","y":22,"minute":1320.0},{"id":"gold_shrimp","y":36,"minute":1440.0+720.0}]:
		coast_player.y=float(spot.y)+0.5
		coast_world.state.time=spot.minute
		var water:=Vector2i(52,spot.y)
		expect(coast_world.act("coast","cast-"+spot.id,"fish_start",water).ok and coast_world.step(3.1,true),"Cast at named east-bank spot")
		expect(coast_world.act("coast","reel-"+spot.id,"fish_catch",water).ok and coast_player.inventory.get(spot.id,0)==1,"Land "+spot.id+" at its intended spot")
	expect(coast_player.beimen_flounder_misses==0,"Pier and tidepool leave the coast guarantee alone")

	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save + suffix):
			DirAccess.remove_absolute(save + suffix)
	DirAccess.remove_absolute(path)
	print("COLLECTION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
