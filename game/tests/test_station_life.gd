extends SceneTree
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Life=World.STATION_LIFE
var checks:=0
var failures:=0
var world:=World.new()

func expect(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func place(region:String)->void:
	var person:Dictionary=world.state.players.alpha
	var tile:Vector2i=Life.RESIDENTS[region].cell
	person.region=region
	person.x=tile.x+0.5
	person.y=tile.y+0.5
	person.travel_book.visited[region]=true

func action(request:String,action_id:String,region:String,extra:String)->Dictionary:
	return world.act("alpha",request,action_id,Life.RESIDENTS[region].cell,extra)

func valid(state:Dictionary)->bool:
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func _initialize()->void:
	var path:=OS.get_environment("TEMP").path_join("station-%s.json"%Crypto.new().generate_random_bytes(12).hex_encode())
	world.save_path=path
	world.add_player("alpha","Alpha")
	world.add_player("beta","Beta")
	var old:=world.state.duplicate(true)
	old.version=9;old.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	old.erase("flower_nursery")
	old.regions.erase("tianwei")
	old.erase("salt_pan")
	old.regions.erase("beimen")
	old.erase("station_life")
	expect(valid(old) and old.version==preload("res://scripts/save_schema.gd").VERSION and old.station_life==Life.fresh() and old.players.alpha.inventory==world.state.players.alpha.inventory,"v9 migration preserves inventory and adds empty records")
	place("toucheng")
	expect(not action("locked","station_story","toucheng","0").ok,"Picnic is required")
	world.state.picnic=true
	expect(not action("wrong","station_story","ruifang","0").ok,"Other region is rejected")
	world.state.players.alpha.x=12.5
	expect(not action("far","station_story","toucheng","0").ok,"Distant resident is rejected")
	place("toucheng")
	expect(action("accept","station_story","toucheng","0").ok,"Accept route note")
	expect(action("accept","station_story","toucheng","0").ok and not action("stale","station_story","toucheng","0").ok,"Receipt and stale stage cannot double advance")
	place("ruifang")
	expect(not action("bench","station_story","ruifang","1").ok and not action("missing","station_repair","ruifang","ruifang").ok,"Stage and repair each enforce prerequisites")
	world.state.players.alpha.inventory.plank=2
	var committed:int=world.state.committed
	world.save_path=path.path_join("missing")
	expect(not action("io","station_repair","ruifang","ruifang").ok and world.state.players.alpha.inventory.plank==2 and not world.state.station_life.repairs.ruifang and world.state.committed==committed,"Repair save failure rolls back materials and flag")
	world.save_path=path
	expect(action("repair","station_repair","ruifang","ruifang").ok and world.state.players.alpha.inventory.plank==0 and world.state.players.alpha.inventory.stone==2,"Repair consumes exact materials")
	expect(not action("repair-again","station_repair","ruifang","ruifang").ok and action("bench-ready","station_story","ruifang","1").ok,"Repair is shared and once only")
	place("jiufen")
	expect(not action("no-bread","station_story","jiufen","2").ok,"A real bread is required")
	world.state.players.alpha.inventory.bread=1
	expect(action("bread","station_story","jiufen","2").ok and world.state.players.alpha.inventory.bread==0,"Sharing consumes a single bread")
	place("toucheng")
	world.state.players.beta.travel_book.visited.jinguashi=true
	expect(not action("other-visited","station_story","toucheng","3").ok,"Another player visiting cannot satisfy personal requirement")
	world.state.players.alpha.travel_book.visited.jinguashi=true
	world.state.players.alpha.coins=999999921
	expect(not action("coins-cap","station_story","toucheng","3").ok,"Coin overflow refused")
	world.state.players.alpha.coins=120
	world.state.players.alpha.inventory.sapling=1000000000
	expect(not action("seed-cap","station_story","toucheng","3").ok,"Sapling overflow refused")
	world.state.players.alpha.inventory.sapling=2
	world.save_path=path.path_join("missing")
	expect(not action("reward-fail","station_story","toucheng","3").ok and Life.story(world.state,"alpha").stage==3 and world.state.players.alpha.coins==120,"Reward and progress both roll back")
	world.save_path=path
	expect(action("reward","station_story","toucheng","3").ok and world.state.players.alpha.coins==200 and world.state.players.alpha.inventory.sapling==3,"Exact completion reward")
	expect(not action("reward-again","station_story","toucheng","3").ok and Life.story(world.state,"beta").stage==0,"Rewards and story are private and once-only")
	var loaded:=World.new()
	expect(loaded.load_world(path) and Life.story(loaded.state,"alpha").stage==4 and loaded.state.station_life.repairs.ruifang,"Reload preserves completed story and public repair")
	var bad:=world.state.duplicate(true)
	bad.station_life.repairs.ruifang=false
	expect(not valid(bad),"Save rejects impossible stage without repair")
	bad=world.state.duplicate(true)
	bad.station_life.players.alpha.stage=2.5
	expect(not valid(bad),"Save rejects fractional stage")
	bad=world.state.duplicate(true)
	bad.station_life.players.unknown={"stage":1}
	expect(not valid(bad),"Save rejects orphan progress")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("STATION_LIFE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
