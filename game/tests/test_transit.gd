extends SceneTree
const World=preload("res://scripts/world.gd")
const Transit=World.TRANSIT
var checks:=0
var failures:=0

func expect(value:bool, message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func near(world:World, token:String, cell:Vector2i)->void:
	world.state.players[token].x=cell.x+0.5
	world.state.players[token].y=cell.y+0.5

func check_landing(world:World,region:String,landing:Vector2,route:String)->void:
	var cell:=Vector2i(landing.floor())
	expect(Transit.point_at(region,cell).is_empty(),"%s leaves the station sign clear"%route)
	var adjacent:=false
	for point:Dictionary in Transit.points(region).values():
		adjacent=adjacent or cell.distance_squared_to(point.cell)==1
	expect(adjacent,"%s lands one tile from a transfer point"%route)
	world.switch_region(region)
	expect(world.can_stand(landing),"%s lands on walkable ground"%route)
	world.switch_region(World.REGIONS.HOME)

func check_boarded_landing(world:World,origin:String,destination:String)->void:
	var person:Dictionary=world.state.players.alpha
	var landing:=Vector2(person.x,person.y)
	expect(person.region==destination and landing==Transit.arrival(origin,destination),"%s → %s uses its designated arrival"%[origin,destination])
	check_landing(world,destination,landing,"%s → %s"%[origin,destination])

func _initialize()->void:
	var map=preload("res://scripts/island_map.gd")
	expect(map.return_sign("toucheng",1).is_empty(),"Return signage unlocks at exploration three")
	expect(map.return_sign("toucheng",2).cell==World.TRANSIT.POINTS.toucheng.street.cell,"Toucheng marks the homeward street stop")
	expect(map.return_sign("mine_5",2).cell==World.MINES.UP,"Mine marks the upward exit")
	var path:=OS.get_environment("TEMP").path_join("transit-%s.json"%Crypto.new().generate_random_bytes(12).hex_encode())
	var world:=World.new()
	world.save_path=path
	world.add_player("alpha","Alpha")
	world.add_player("beta","Beta")
	for destination:String in Transit.ROUTE:
		check_landing(world,destination,Transit.STATIONS[destination].arrival,"Default arrival at "+destination)
		for origin:String in Transit.CONNECTIONS[destination]:
			check_landing(world,destination,Transit.arrival(origin,destination),"%s → %s"%[origin,destination])
	var gate:=Vector2i(47,30)
	near(world,"alpha",gate)
	expect(not world.act("alpha","locked","transit",gate,"toucheng").ok,"Picnic unlock required")
	world.state.picnic=true
	var legacy:=world.state.duplicate(true)
	legacy.version=8;legacy.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.erase("flower_nursery")
	legacy.regions.erase("tianwei")
	legacy.erase("salt_pan")
	legacy.regions.erase("beimen")
	legacy.regions.erase(World.REGIONS.Cart.REGION)
	for region in World.REGIONS.ANGLING_RESERVES:legacy.regions.erase(region)
	for region in Transit.LOCAL:legacy.regions.erase(region)
	for person in legacy.players.values():person.erase("travel_book")
	var migrated:=preload("res://scripts/save_schema.gd").validate(legacy,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
	expect(migrated,"Valid v8 migrates")
	if not migrated:
		print("TRANSIT_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	expect(legacy.players.alpha.travel_book.legacy_pass and legacy.players.alpha.travel_book.visited.size()==1,"Legacy access preserves real visit history")
	expect(not world.act("alpha","skip","travel",gate,"jinguashi").ok and not world.act("alpha","skip2","transit",gate,"jinguashi").ok,"Fresh character cannot skip northern route")
	expect(Transit.intermediate("jinguashi","toucheng")==["jiufen","ruifang"],"Return itinerary lists intermediate stations in travel order")
	var invalid:=legacy.duplicate(true)
	invalid.players.alpha.travel_book.visited.fake=true
	expect(not preload("res://scripts/save_schema.gd").validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Unknown station in v9 save is rejected")
	var time:float=world.state.time
	expect(world.act("alpha","first","transit",gate,"toucheng").ok,"First trip reaches Toucheng")
	check_boarded_landing(world,"home","toucheng")
	expect(World.exploration_points(world.state.players.alpha)==1,"Arrival grants one exploration point even when also tracked in the travel book")
	var epoch:int=world.state.players.alpha.travel_epoch
	expect(world.act("alpha","first","transit",gate,"toucheng").ok and world.state.players.alpha.travel_epoch==epoch,"Duplicate receipt cannot replay travel")
	expect(World.exploration_points(world.state.players.alpha)==1,"A replay cannot add exploration points")
	expect(not world.act("alpha","from_street","transit",Vector2i(12,25),"ruifang").ok and not world.act("alpha","far_platform","transit",Vector2i(25,19),"ruifang").ok,"Reach platform before train")
	world.switch_region("toucheng")
	expect(world.blocked(Vector2i(16,18)) and world.blocked(Vector2i(24,16)) and world.blocked(Vector2i(8,20)) and not world.blocked(Vector2i(22,20)),"Station buildings and boundary collide; plaza is walkable")
	world.switch_region("home")
	expect(not world.act("alpha","dig","hoe",Vector2i(12,25),"").ok,"Public station cannot be farmed")
	near(world,"alpha",Vector2i(25,19))
	expect(world.act("alpha","train","transit",Vector2i(25,19),"ruifang").ok,"Train connects Toucheng and Ruifang")
	check_boarded_landing(world,"toucheng","ruifang")
	expect(not world.act("alpha","wrong_mode","transit",Vector2i(14,19),"jiufen").ok,"Rail entrance cannot depart by bus")
	near(world,"alpha",Vector2i(31,25))
	expect(world.act("alpha","bus","transit",Vector2i(31,25),"jiufen").ok,"Bus reaches Jiufen")
	check_boarded_landing(world,"ruifang","jiufen")
	near(world,"alpha",Vector2i(29,20))
	expect(world.act("alpha","shuttle","transit",Vector2i(29,20),"jinguashi").ok,"Shuttle reaches Jinguashi")
	check_boarded_landing(world,"jiufen","jinguashi")
	expect(world.state.time==time and world.state.players.beta.travel_book.visited.size()==1,"Transit does not advance the clock or visit on behalf of others")
	expect(world.act("alpha","return","transit",Vector2i(11,20),"home").ok,"Returning home is free")
	check_boarded_landing(world,"jinguashi","home")
	var save_path:=world.save_path
	world.save_path=save_path.path_join("invalid")
	expect(not world.act("alpha","rollback","transit",gate,"ruifang").ok and world.player_region("alpha")=="home","Failed save rolls back transfer")
	world.save_path=save_path
	expect(world.act("alpha","known","transit",gate,"ruifang").ok,"Known station supports direct transfer")
	var loaded:=World.new()
	loaded.save_path=save_path
	expect(loaded.load_world(save_path) and loaded.player_region("alpha")=="ruifang" and loaded.state.players.alpha.travel_book.visited.size()==5,"Reload preserves station and complete visited list")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("TRANSIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
