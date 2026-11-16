extends SceneTree
const World=preload("res://scripts/world.gd")
const Works=World.WATERWORKS
const Schema=preload("res://scripts/save_schema.gd")
var checks:=0
var failures:=0
var world:=World.new()

func expect(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func device(kind:String,owner:String,fields:Dictionary)->Dictionary:
	var result:Dictionary={"type":kind,"owner":owner,"items":{}}
	result.merge(fields,true)
	return result

func operate(id:String,action:String,extra:String="",owner:String="alpha")->bool:
	return world.act(owner,id,action,Vector2i(31,24),extra).ok

func valid(data:Dictionary)->bool:
	return Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func _initialize()->void:
	var path:=OS.get_environment("TEMP").path_join("waterworks-%s.json"%Crypto.new().generate_random_bytes(12).hex_encode())
	world.save_path=path
	for actor in ["alpha","beta"]:
		world.add_player(actor,actor)
		var person:Dictionary=world.state.players[actor]
		person.region="lanyang"
		person.x=31.5
		person.y=25.5
	var old:=world.state.duplicate(true)
	old.version=10;old.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	old.erase("flower_nursery")
	old.regions.erase("tianwei")
	old.erase("salt_pan")
	old.regions.erase("beimen")
	expect(valid(old) and old.version==26 and old.players.alpha.inventory.wood==12,"v10 retains starting inventory and migrates")
	var objects:Dictionary=world.state.regions.lanyang.objects
	objects["31,25"]=device("bench","alpha",{})
	var inv:Dictionary=world.state.players.alpha.inventory
	inv.merge({"plank":12,"copper_joint":8,"stone":16,"resin":4},true)
	expect(not world.act("alpha","locked","craft",Vector2i(31,25),"waterworks_kit").ok,"Craft requires completed mine drainage")
	world.state.mine_depths.unlocked=4
	world.state.mine_depths.pumped=24
	expect(world.act("alpha","kit","craft",Vector2i(31,25),"waterworks_kit").ok and inv.waterworks_kit==1 and inv.plank==0,"Exact kit cost")
	expect(operate("build","build","waterworks"),"Place blocking waterworks")
	expect(not operate("wrong","waterworks_feed","stone:5") and not operate("count","waterworks_feed","wood:05") and not operate("foreign","waterworks_toggle","","beta"),"Invalid item/count and foreign access refused")
	objects["32,24"]=device("water_pump","alpha",{"enabled":true})
	objects["32,23"]=device("water_tank","alpha",{"water":0})
	objects["30,24"]=device("conveyor","alpha",{"enabled":true,"filter":"copper_ore","dir":1,"items":{"copper_ore":1}})
	objects["31,23"]=device("conveyor","beta",{"enabled":true,"filter":"wood","dir":2,"items":{"wood":1}})
	inv.copper_ore=1
	expect(operate("wood","waterworks_feed","wood:1") and operate("ore","waterworks_feed","copper_ore:5") and operate("enable","waterworks_toggle"),"Bounded feed and enable")
	var now:float=world.state.time
	expect(world.step(8,false) and world.state.time==now,"No players means no progression")
	var before:=world.state.duplicate(true)
	world.save_path=path.path_join("missing")
	expect(not world.step(8,true) and world.state==before,"Water, belts and processing roll back together")
	world.save_path=path
	expect(world.step(8,true),"Water and belts applied before processing")
	objects=world.state.regions.lanyang.objects
	var machine:Dictionary=objects["31,24"]
	expect(machine.has("job") and machine.water==6 and machine.input.wood==0 and machine.input.copper_ore==0 and objects["30,24"].items.is_empty(),"Batch used same-tick water and belt feed without overwrites")
	expect(objects["31,23"].items.wood==1,"Foreign conveyor remains untouched")
	expect(not operate("move","move_object","29,25") and not operate("remove","remove"),"Active machine cannot be moved or removed")
	expect(operate("stop","waterworks_toggle") and not operate("drain-early","waterworks_drain"),"Stopping preserves active job and prevents draining")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.regions.lanyang.objects["31,24"].has("job"),"Active batch persists")
	expect(world.step(12,true) and not machine.has("job") and machine.items.copper_joint==1,"Stopped batch completes exactly one output")
	var current_inv:Dictionary=world.state.players.alpha.inventory
	current_inv.copper_joint=1000000000
	expect(not operate("overflow","waterworks_collect") and machine.items.copper_joint==1,"Overflow preserves output")
	current_inv.copper_joint=0
	expect(operate("collect","waterworks_collect") and operate("collect","waterworks_collect") and current_inv.copper_joint==1,"Receipt prevents duplicate output")
	expect(not operate("wet-remove","remove") and operate("drain","waterworks_drain") and operate("remove-empty","remove") and current_inv.waterworks_kit==1,"Drain required before safe kit refund")
	var invalid:=before.duplicate(true)
	invalid.regions.lanyang.objects["31,24"].input.wood=33
	expect(not valid(invalid),"Malformed oversized input rejected")
	invalid=before.duplicate(true)
	invalid.regions.lanyang.objects["31,24"].items={"wood":1}
	expect(not valid(invalid),"Wrong output ID rejected")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("WATERWORKS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
