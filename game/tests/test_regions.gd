extends SceneTree
const World = preload("res://scripts/world.gd")
const Regions = preload("res://scripts/regions.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var rice_world:=World.new()
	rice_world.add_player("grower","Grower")
	var grower:Dictionary=rice_world.state.players.grower
	grower.x=42.5
	grower.y=30.5
	expect(rice_world.act("grower","buy-rice","buy",Vector2i(43,29),"rice").ok,"Purchase rice seed with starting coins")
	expect(rice_world.act("grower","buy-eggplant","buy",Vector2i(43,29),"eggplant").ok,"Purchase eggplant seed with starting coins")
	rice_world.state.picnic=true
	grower.x=46.5
	grower.y=30.5
	expect(rice_world.act("grower","to-farm","travel",Regions.exit_cell("home"),"lanyang").ok,"Travel to Lanyang for the rice")
	grower.x=32.5
	grower.y=25.5
	var paddy:=Vector2i(32,26)
	var upland:=Vector2i(31,26)
	expect(rice_world.act("grower","dry-hoe","hoe",upland).ok,"Prepare a dry field next to the paddy")
	expect(not rice_world.act("grower","dry-seed","seed",upland,"rice").ok and grower.inventory.rice_seed==1,"Dry field does not consume rice seed")
	rice_world.state.time=World.WEATHER.DAYS_PER_SEASON*World.WEATHER.DAY_SECONDS+720.0
	expect(rice_world.act("grower","rice-hoe","hoe",paddy).ok and rice_world.act("grower","rice-seed","seed",paddy,"rice").ok,"Summer rice can plant at the canal")
	expect(rice_world.act("grower","rice-water","water",paddy).ok and rice_world.step(float(World.CROPS.rice.time),true),"Watered paddy matures")
	expect(rice_world.act("grower","rice-harvest","harvest",paddy).ok and grower.inventory.rice==2 and grower.collection.crops.has("rice"),"Two rice enter the backpack and collection")
	grower.x=12.5
	grower.y=20.5
	expect(rice_world.act("grower","rice-return","travel",Regions.exit_cell("lanyang"),"home").ok,"Return home carrying the rice")
	grower.x=40.5
	grower.y=34.5
	var eggplant_plot:=Vector2i(41,34)
	for action in ["hoe","seed","water"]:
		expect(rice_world.act("grower","eggplant-"+action,action,eggplant_plot,"eggplant" if action=="seed" else "").ok,"Grow eggplant: "+action)
	expect(rice_world.step(float(World.CROPS.eggplant.time),true) and rice_world.act("grower","pick-eggplant","harvest",eggplant_plot).ok,"Harvest eggplant for the dish")
	var stove:=Vector2i(40,33)
	grower.inventory.merge({"stone":15,"wood":12},true)
	expect(rice_world.act("grower","build-stove","build",stove,"stove").ok,"Build a stove for the harvested ingredients")
	expect(rice_world.act("grower","queue-rice","queue_cook",stove,"eggplant_rice").ok and grower.inventory.get("rice",0)==0 and grower.inventory.get("eggplant",0)==1,"Queue consumes two rice and one eggplant")
	expect(rice_world.step(30.1,true) and rice_world.act("grower","claim-rice","claim_cook",stove).ok,"Claim the cooked rice")
	expect(grower.inventory.get("eggplant_rice",0)==2 and grower.collection.meals.has("eggplant_rice"),"Two servings and the discovery are recorded")
	var path := OS.get_environment("TEMP").path_join("region-%d.json" % Time.get_ticks_usec())
	var world := World.new()
	world.add_player("alpha","Alpha")
	world.add_player("beta","Beta")
	var home_exit := Regions.exit_cell("home")
	var outer_exit := Regions.exit_cell("lanyang")
	var springs:=World.new()
	springs.add_player("angler","Angler")
	var angler:Dictionary=springs.state.players.angler
	angler.x=46.5
	angler.y=30.5
	expect(not springs.act("angler","locked-springs","transit",home_exit,"jiaoxi").ok,"Jiaoxi cannot be reached before the ferry opens")
	springs.state.picnic=true
	expect(springs.act("angler","to-toucheng","transit",home_exit,"toucheng").ok,"Travel from the ferry to Toucheng")
	angler.x=24.5
	angler.y=19.5
	expect(springs.act("angler","to-springs","transit",Vector2i(25,19),"jiaoxi").ok,"Toucheng rail point reaches Jiaoxi")
	expect(angler.travel_book.visited.jiaoxi and springs.region_snapshot("jiaoxi").players.has("angler"),"Jiaoxi visit and regional projection are recorded")
	angler.x=20.5
	angler.y=22.5
	springs.state.time=720.0
	var warm_pool:=Vector2i(20,21)
	expect(springs.act("angler","spring-cast","fish_start",warm_pool).ok and springs.step(3.1,true) and springs.act("angler","spring-reel","fish_catch",warm_pool).ok,"Daytime warm spring catch")
	expect(angler.inventory.get("glass_shrimp",0)==1,"The warm pool yields glass shrimp")
	angler.x=32.5
	angler.y=24.5
	var cold_pool:=Vector2i(32,25)
	angler.jiaoxi_trout_misses=19
	expect(springs.act("angler","summer-cast","fish_start",cold_pool).ok and springs.step(3.1,true) and springs.act("angler","summer-reel","fish_catch",cold_pool).ok and angler.jiaoxi_trout_misses==19,"Outside winter the cold pool preserves trout pity")
	springs.state.time=3*World.WEATHER.DAYS_PER_SEASON*World.WEATHER.DAY_SECONDS+720.0
	expect(springs.act("angler","winter-cast","fish_start",cold_pool).ok and springs.step(3.1,true) and springs.act("angler","winter-reel","fish_catch",cold_pool).ok,"Winter cold spring catch")
	expect(angler.inventory.get("snow_trout",0)==1 and angler.jiaoxi_trout_misses==0,"Winter cold pool honors and clears the trout guarantee")
	springs.save_path=path+".springs"
	expect(springs.save(),"Save the springs visit and catches")
	var reopened_springs:=World.new()
	expect(reopened_springs.load_world(springs.save_path) and reopened_springs.player_region("angler")=="jiaoxi","Reload at Jiaoxi")
	expect(reopened_springs.state.players.angler.collection.fish.has("snow_trout"),"Reload the trout discovery")
	angler.x=14.5
	angler.y=25.5
	expect(springs.act("angler","return-springs","transit",Vector2i(13,25),"home").ok,"Return to the ferry from the springs stop")
	for suffix in [".springs",".springs.bak"]:DirAccess.remove_absolute(path+suffix)
	var grove:=World.new()
	grove.add_player("angler","Angler")
	var walker:Dictionary=grove.state.players.angler
	walker.region="maokong"
	walker.travel_book.visited.maokong=true
	walker.x=13.5
	walker.y=25.5
	grove.state.picnic=true
	var gate:=Vector2i(12,25)
	expect(not grove.act("angler","locked-grove","transit",gate,"bamboo_grove").ok,"The tea route must be unlocked first")
	expect(World.TRANSIT.options("maokong",walker.travel_book,true,"transfer",true).any(func(option):return option.region=="bamboo_grove" and option.mode=="茶園步道"),"The unlocked tea station shows the grove trail")
	# Set regional position directly to exercise fishing independently of the story fixture.
	walker.region="bamboo_grove"
	walker.travel_book.visited.bamboo_grove=true
	walker.x=22.5
	walker.y=22.5
	var brook:=Vector2i(23,22)
	walker.bamboo_ayu_misses=19
	grove.state.time=720.0
	expect(grove.act("angler","noon-cast","fish_start",brook).ok and grove.step(3.1,true) and grove.act("angler","noon-reel","fish_catch",brook).ok and walker.bamboo_ayu_misses==19,"Noon catch preserves the morning guarantee")
	grove.state.time=World.WEATHER.DAY_SECONDS+480.0
	expect(grove.act("angler","morning-cast","fish_start",brook).ok and grove.step(3.1,true) and grove.act("angler","morning-reel","fish_catch",brook).ok,"Fish during the morning breeze")
	expect(walker.inventory.get("bamboo_ayu",0)==1 and walker.bamboo_ayu_misses==0 and walker.collection.fish.has("bamboo_ayu"),"Ayu enters the backpack and almanac and clears pity")
	grove.save_path=path+".grove"
	expect(grove.save(),"Save the grove catch")
	var reopened_grove:=World.new()
	expect(reopened_grove.load_world(grove.save_path) and reopened_grove.state.players.angler.inventory.get("bamboo_ayu",0)==1,"Ayu survives reopening the world")
	for suffix in [".grove",".grove.bak"]:DirAccess.remove_absolute(path+suffix)
	var garden:=World.new()
	garden.add_player("angler","Angler")
	var visitor:Dictionary=garden.state.players.angler
	garden.state.picnic=true
	visitor.region="tianwei"
	visitor.travel_book.visited.tianwei=true
	visitor.x=13.5
	visitor.y=25.5
	expect(not garden.act("angler","locked-stars","transit",gate,"star_garden").ok,"Star garden stays locked before the public garden project")
	expect(World.TRANSIT.options("tianwei",visitor.travel_book,true,"transfer",true,true,false,true).any(func(option):return option.region=="star_garden"),"The public garden completion enables the branch")
	visitor.region="star_garden"
	visitor.travel_book.visited.star_garden=true
	visitor.x=22.5
	visitor.y=21.5
	var reflecting_pool:=Vector2i(23,21)
	visitor.star_spot_misses=19
	garden.state.time=720.0
	expect(garden.act("angler","day-star-cast","fish_start",reflecting_pool).ok and garden.step(3.1,true) and garden.act("angler","day-star-reel","fish_catch",reflecting_pool).ok and visitor.star_spot_misses==19,"Day catch preserves Star Spot pity")
	garden.state.time=1260.0
	expect(garden.act("angler","night-star-cast","fish_start",reflecting_pool).ok and garden.step(3.1,true) and garden.act("angler","night-star-reel","fish_catch",reflecting_pool).ok,"Night catch in the reflecting pool")
	expect(visitor.collection.fish.has("star_spot") and visitor.star_spot_misses==0 and World.FISH.size()==12,"Star Spot joins the twelve-fish collection")
	garden.save_path=path+".stars"
	expect(garden.save(),"Save the Star Spot discovery")
	var reopened_garden:=World.new()
	expect(reopened_garden.load_world(garden.save_path) and reopened_garden.state.players.angler.inventory.get("star_spot",0)==1,"Star Spot survives reopening the world")
	for suffix in [".stars",".stars.bak"]:DirAccess.remove_absolute(path+suffix)
	expect(not world.act("alpha","locked","travel",home_exit,"lanyang").ok, "Picnic unlock required")
	world.state.picnic = true
	expect(not world.act("alpha","far","travel",home_exit,"lanyang").ok, "Exit reach enforced")
	world.state.players.alpha.x = 46.5
	world.state.players.alpha.y = 30.5
	world.save_path = path.path_join("missing").path_join("save")
	expect(not world.act("alpha","out","travel",home_exit,"lanyang").ok and world.player_region("alpha") == "home" and world.state.players.alpha.travel_epoch == 0, "Travel save failure rolls back")
	world.save_path = path
	var travel := world.act("alpha","out","travel",home_exit,"lanyang")
	expect(travel.ok and world.player_region("alpha") == "lanyang" and world.state.players.alpha.travel_epoch == 1, "Arrival persisted")
	expect(world.act("alpha","out","travel",home_exit,"lanyang") == travel and world.state.players.alpha.travel_epoch == 1, "Travel retry is idempotent")
	var plot := Vector2i(13,20)
	expect(world.act("alpha","hoe","hoe",plot).ok and world.act("alpha","seed","seed",plot,"radish").ok and world.act("alpha","water","water",plot).ok, "Normal field actions route to Lanyang")
	expect(not world.state.crops.has("13,20") and world.state.regions.lanyang.crops.has("13,20"), "Same coordinate remains isolated")
	expect(world.act("alpha","back","travel",outer_exit,"home").ok and world.player_region("alpha") == "home", "Return via regional exit")
	expect(world.step(World.CROPS.radish.time,true) and world.state.regions.lanyang.crops["13,20"].growth == World.CROPS.radish.time, "Unoccupied region grows under shared world clock")
	expect(world.act("alpha","again","travel",home_exit,"lanyang").ok and world.act("alpha","harvest","harvest",plot).ok and world.state.players.alpha.inventory.radish == 1, "Harvest uses shared backpack")
	world.state.players.beta.x = 13.5
	world.state.players.beta.y = 21.5
	expect(world.act("alpha","regional-build","build",Vector2i(13,21),"wall").ok and not world.state.objects.has("13,21"), "Occupant at matching home coordinates does not block Lanyang construction")
	var snapshot := world.region_snapshot("lanyang")
	expect(snapshot.region_id == "lanyang" and snapshot.players.has("alpha") and not snapshot.players.has("beta") and not snapshot.has("regions"), "Projection isolates region and players")
	var reload := World.new()
	expect(reload.load_world(path) and reload.player_region("alpha") == "lanyang" and reload.state.players.alpha.travel_epoch == 3, "Reconnect restores persisted region and epoch")
	world.state.objects["46,30"] = {"type":"wall","owner":"beta","items":{}}
	var returned := world.act("alpha","safe-back","travel",outer_exit,"home")
	var landed := Vector2(world.state.players.alpha.x,world.state.players.alpha.y)
	expect(returned.ok and landed != Regions.spawn("home") and world.can_stand(landed), "Blocked legacy arrival uses a nearby standable tile")
	var actor: Dictionary = world.state.players.alpha
	actor.x = 42.5
	actor.y = 32.5
	expect(world.act("alpha","sale","ship",World.SHIPPING.cell_for(world.state),JSON.stringify([[["radish",1]],24])).ok and actor.coins == 144, "Lanyang harvest can be carried back and sold at the home stall")
	var outer: Dictionary = world.state.regions.lanyang
	for layer in [world.state,outer]:
		layer.crops["13,20"] = {"kind":"radish","owner":"alpha","growth":0.0,"wet":false,"remaining":1}
		layer.objects["13,21"] = {"type":"sprinkler","owner":"alpha","items":{},"water":1,"enabled":true,"next_water":0.0,"last_water":-1.0}
	var before := world.state.duplicate(true)
	world.save_path = path.path_join("missing").path_join("save")
	expect(not world.step(1.0,true) and world.state == before, "Failed automation save rolls back both regions and shared clock")
	world.save_path = path
	expect(world.step(1.0,true) and world.state.crops["13,20"].wet and world.state.regions.lanyang.crops["13,20"].wet and world.state.time == before.time + 1.0, "Both regions automate within one tick and clock advances once")
	var legacy := World.new()
	legacy.add_player("legacy","Legacy")
	legacy.state.version = 1;legacy.state.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.state.erase("flower_nursery")
	legacy.state.regions.erase("tianwei")
	legacy.state.erase("salt_pan")
	legacy.state.regions.erase("beimen")
	legacy.state.erase("regions")
	legacy.state.players.legacy.erase("region")
	legacy.state.players.legacy.erase("travel_epoch")
	legacy.state.objects["41,35"] = {"type":"private_chest","owner":"legacy","items":{"wood":5}}
	legacy.state.objects["42,35"] = {"type":"conveyor","owner":"legacy","items":{},"dir":1,"enabled":false,"filter":"wood"}
	legacy.state.objects["43,35"] = {"type":"sprinkler","owner":"legacy","items":{},"water":2,"enabled":false,"next_water":0,"last_water":-1}
	legacy.state.crops["41,36"] = {"kind":"radish","owner":"legacy","growth":4,"wet":true,"remaining":1}
	legacy.state.forest["42,36"] = {"owner":"legacy","mature":false,"growth":12}
	legacy.state.chapter_one.harvests.legacy = {"radish":2}
	legacy.state.players.legacy.x = 46.5
	legacy.state.players.legacy.y = 31.5
	legacy.state.crops["47,30"] = {"kind":"radish","owner":"legacy","growth":World.CROPS.radish.time,"wet":false,"remaining":1}
	legacy.state.objects["46,30"] = {"type":"chair","owner":"legacy","items":{}}
	legacy.save_path = path + ".legacy"
	expect(legacy.save() and reload.load_world(legacy.save_path) and reload.state.version == 26 and reload.player_region("legacy") == "home" and reload.state.players.legacy.inventory.wood == 12, "Legacy world migrates without changing inventory")
	expect(reload.state.objects["41,35"].items.wood == 5 and reload.state.objects["42,35"].dir == 1 and reload.state.objects["43,35"].water == 2 and reload.state.crops["41,36"].growth == 4 and reload.state.forest["42,36"].growth == 12 and reload.state.chapter_one.harvests.legacy.radish == 2, "Legacy private chest, belt, equipment, crop, trees and chapter remain intact")
	expect(reload.act("legacy","water-exit","water",home_exit).ok and reload.act("legacy","harvest-exit","harvest",home_exit).ok and reload.act("legacy","clear-exit","remove",home_exit).ok, "Legacy crop at exit can be watered, harvested and removed")
	var wood: int = reload.state.players.legacy.inventory.wood
	var arrival := Vector2i(Regions.spawn("home"))
	expect(reload.act("legacy","clear-arrival","remove",arrival).ok and reload.state.players.legacy.inventory.wood == wood + World.BUILD.chair.wood, "Legacy arrival furniture can be removed with its normal refund")
	expect(not reload.act("legacy","replace-exit","build",home_exit,"chair").ok and not reload.act("legacy","replace-arrival","build",arrival,"chair").ok, "Cleared travel tiles cannot be built over")
	var schema = preload("res://scripts/save_schema.gd")
	var malformed := reload.state.duplicate(true)
	malformed.players.legacy.region = "unknown"
	expect(not schema.validate(malformed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME), "Unknown player region rejected")
	malformed = reload.state.duplicate(true)
	malformed.regions.lanyang.objects["2,2"] = {"type":"chair","owner":"legacy","items":{}}
	expect(not schema.validate(malformed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME), "Off-map Lanyang object rejected")
	for key in ["33,20", "33,29", "11,20"]:
		malformed = reload.state.duplicate(true)
		malformed.regions.lanyang.objects[key] = {"type":"water_pump","owner":"legacy","items":{},"enabled":false}
		expect(not schema.validate(malformed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME), "Water pump rejected in water or reserved cell " + key)
	malformed = reload.state.duplicate(true)
	malformed.regions.lanyang.objects["32,20"] = {"type":"water_pump","owner":"legacy","items":{},"enabled":false}
	expect(schema.validate(malformed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME), "Legal dry riverbank pump accepted")
	var disk := FileAccess.get_sha256(path)
	world.switch_region(Regions.LANYANG)
	expect(not world.save() and FileAccess.get_sha256(path) == disk, "Regional projection cannot overwrite world save")
	world.switch_region(Regions.HOME)
	for file in [path,path+".bak",legacy.save_path,legacy.save_path+".bak"]:
		DirAccess.remove_absolute(file)
	print("REGION_TESTS checks=%d failures=%d" % [checks,failures])
	quit(int(failures > 0))

