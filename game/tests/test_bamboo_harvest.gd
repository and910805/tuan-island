extends SceneTree

const World=preload("res://scripts/world.gd")
const Bamboo=World.REGIONS.Bamboo
const Items=preload("res://scripts/inventory_item_art.gd")
const CUTTER:="bamboo-cutter"
const VISITOR:="bamboo-visitor"
var world:=World.new()
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func place(actor:String,cell:Vector2i,distance:float,region:=Bamboo.REGION)->void:
	var person:Dictionary=world.state.players[actor]
	person.region=region
	person.x=cell.x+0.5+distance
	person.y=cell.y+0.5

func amount(w:World,actor:String)->int:
	return int(w.state.players[actor].inventory.get(Bamboo.ITEM,0))

func ground(w:World,cell:Vector2i)->int:
	var drops:Dictionary=w.region_snapshot(Bamboo.REGION).get("gather_drops",{})
	return int(drops.get(World.key(cell),{}).get("items",{}).get(Bamboo.ITEM,0))

func refuse(actor:String,request:String,cell:Vector2i,action:="axe",extra:="")->void:
	var before:=world.state.duplicate(true)
	var response:=world.act(actor,request,action,cell,extra)
	expect(not response.ok and before==world.state,request+" leaves the world and bag unchanged")

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	var path:="user://bamboo-test-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	world.add_player(CUTTER,"採竹人")
	world.add_player(VISITOR,"溪谷訪客")
	world.active_tokens={CUTTER:true,VISITOR:true}
	world.state.time=540.0
	expect(World.NAMES.get(Bamboo.ITEM)=="竹材" and Items.icon(Bamboo.ITEM).get_size()==Vector2(32,32),"Bamboo has an inventory name and 32px artwork")
	expect(Bamboo.CLUMPS.size()==4 and Bamboo.YIELD==4 and Bamboo.REGROW_SECONDS==120.0,"The four clumps have the planned yield and renewal")
	expect(valid(world.state.duplicate(true)),"Older saves without bamboo timers remain valid")
	expect(World.RESIDENT_GOALS.cost(World.RESIDENT_GOALS.goal("chacha",2),"")=={Bamboo.ITEM:8,"cotton_cloth":2},"Chacha's blinds use the two materials from the setting")
	world.switch_region(Bamboo.REGION)
	for tile:Vector2i in Bamboo.CLUMPS:
		expect(Bamboo.LAND.has_point(tile) and not Bamboo.water(tile) and not Bamboo.TEA_BEDS.has_point(tile),"Clumps stay away from water and tea beds")
		expect(world.blocked(tile) and world.can_stand(Vector2(tile)+Vector2(1.5,0.5)),"Clumps have collision and an adjacent pickup position")
	world.switch_region(World.REGIONS.HOME)
	var a:=Bamboo.CLUMPS[0]
	var b:=Bamboo.CLUMPS[1]
	place(CUTTER,a,3.4)
	refuse(CUTTER,"out of range",a)
	place(CUTTER,a,1.0,World.REGIONS.HOME)
	refuse(CUTTER,"same coordinates on another island",a)
	place(CUTTER,a,3.1)
	refuse(CUTTER,"wrong tool",a,"pick")
	refuse(CUTTER,"unexpected choice",a,"axe","wood")
	var start:=float(world.state.time)
	var cut:=world.act(CUTTER,"first harvest","axe",a)
	expect(cut.ok and cut.get("gather_dropped",false),"One axe action creates a ground drop")
	expect(ground(world,a)==Bamboo.YIELD and amount(world,CUTTER)==0,"The bamboo drops beside the clump before pickup")
	expect(not Bamboo.ready(world.state,a) and Bamboo.ready(world.state,b),"Cutting one clump leaves the other available")
	expect(float(world.state[Bamboo.CUT_FIELD][World.key(a)])==start+Bamboo.REGROW_SECONDS,"The clump has one shared cooldown")
	expect(world.act(CUTTER,"first harvest","axe",a)==cut and ground(world,a)==Bamboo.YIELD,"Replaying an accepted request never duplicates the drop")
	place(VISITOR,a,5.0)
	refuse(CUTTER,"repeat during cooldown",a)
	place(VISITOR,a,1.0)
	refuse(VISITOR,"shared cooldown for another player",a)
	place(VISITOR,b,3.1)
	world.step(1.0,true)
	expect(ground(world,a)==Bamboo.YIELD and amount(world,CUTTER)==0 and amount(world,VISITOR)==0,"Passing the landing delay does not pick up from a distance")
	place(CUTTER,a,1.0)
	expect(world.step(0.2,true) and ground(world,a)==0 and amount(world,CUTTER)==Bamboo.YIELD,"Walking close collects the actual drop")
	world.step(1.0,true)
	expect(amount(world,CUTTER)==Bamboo.YIELD and amount(world,VISITOR)==0,"Staying beside an empty clump pays once")
	expect(world.act(VISITOR,"other clump","axe",b).ok and ground(world,b)==Bamboo.YIELD,"The second player can gather a different clump")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(amount(loaded,CUTTER)==Bamboo.YIELD and ground(loaded,b)==Bamboo.YIELD and not Bamboo.ready(loaded.state,a),"The bag, pending ground pickup and cooldown all survive reload")
	var invalid:=world.state.duplicate(true)
	invalid[Bamboo.CUT_FIELD]["-1,0"]=0.0
	expect(not valid(invalid),"A foreign clump coordinate is rejected in the save")
	invalid=world.state.duplicate(true)
	invalid[Bamboo.CUT_FIELD][World.key(a)]=float(world.state.time)+Bamboo.REGROW_SECONDS+1.0
	expect(not valid(invalid),"A cooldown beyond the permitted duration is rejected in the save")
	world.state.time=start+Bamboo.REGROW_SECONDS-0.1
	refuse(CUTTER,"just before renewal",a)
	world.state.time=start+Bamboo.REGROW_SECONDS
	expect(Bamboo.ready(world.state,a),"The clump returns at the scheduled world time")
	var blocked_path:=path+".directory"
	expect(DirAccess.make_dir_absolute(blocked_path)==OK,"Create an isolated failed-save fixture")
	world.save_path=blocked_path
	refuse(CUTTER,"unwritable harvest",a)
	expect(Bamboo.ready(world.state,a) and ground(world,a)==0,"A failed harvest save restores both readiness and drops")
	DirAccess.remove_absolute(blocked_path)
	world.save_path=path
	expect(world.act(CUTTER,"unwritable harvest","axe",a).ok and ground(world,a)==Bamboo.YIELD,"Retry after a failed write drops one bundle")
	for base in [path,blocked_path]:
		for suffix in ["",".bak",".tmp",".writer-lock"]:
			if FileAccess.file_exists(base+suffix):DirAccess.remove_absolute(base+suffix)
	print("BAMBOO_HARVEST_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
