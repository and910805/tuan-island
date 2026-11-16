extends SceneTree

const World=preload("res://scripts/world.gd")
const Auto=World.MINE_AUTO_FREIGHT
const Schema=preload("res://scripts/save_schema.gd")
const ACTOR="freight-owner"
var world:=World.new()
var checks:=0
var failures:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func action(id:String,kind:String,extra:String="")->bool:
	return world.act(ACTOR,id,kind,World.MINES.SERVICE,extra).ok

func box(owner:String,items:Dictionary)->Dictionary:
	return {"type":"private_chest","owner":owner,"items":items}

func source()->Dictionary:
	return world.state.regions.mine_4.objects["27,24"]

func target()->Dictionary:
	return world.state.objects["41,36"]

func status()->String:
	return Auto.status(world.state,ACTOR).id

func valid(data:Dictionary)->bool:
	return Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func _initialize()->void:
	var path:=OS.get_environment("TEMP").path_join("auto-freight-%s.json"%Crypto.new().generate_random_bytes(12).hex_encode())
	world.save_path=path
	world.add_player(ACTOR,"礦車")
	world.state.mine_depths.unlocked=5
	world.state.mine_depths.pumped=24
	var person:Dictionary=world.state.players[ACTOR]
	person.region="mine_4"
	person.x=34.5
	person.y=21.5
	person.inventory.copper_ore=1
	world.state.regions.mine_4.objects["27,24"]=box(ACTOR,{"copper_ore":9})
	world.state.objects["41,36"]=box(ACTOR,{})
	var config:={"source":"27,24","target":"41,36","item":"copper_ore","reserve":1,"batch":4}
	var bad:=config.duplicate()
	bad.batch=33
	check(not action("bad","mine_auto_config",JSON.stringify(bad)) and not source().has("freight_id") and not target().has("freight_id"),"Invalid payload does not register IDs")
	target().owner="other"
	check(not action("foreign","mine_auto_config",JSON.stringify(config)) and not source().has("freight_id"),"Foreign destination is rejected before registration")
	target().owner=ACTOR
	world.save_path=path.path_join("missing")
	check(not action("failed","mine_auto_config",JSON.stringify(config)) and status()=="unconfigured" and not source().has("freight_id") and not target().has("freight_id"),"Config save rolls back both box IDs and route")
	world.save_path=path
	person=world.state.players[ACTOR]
	check(action("configure","mine_auto_config",JSON.stringify(config)) and status()=="off","Valid route is disabled initially")
	check(action("enable","mine_auto_toggle") and status()=="ready" and not action("clear-live","mine_auto_clear"),"Enable checks both boxes and quantity")
	check(action("manual","freight_load","copper_ore:1") and status()=="manual_draft","Manual draft takes priority")
	check(not action("cancel-loaded","freight_cancel"),"Cannot cancel a draft with cargo")
	check(action("unload","freight_unload","copper_ore:1") and action("cancel","freight_cancel") and status()=="ready","Empty draft can be cancelled without loss")
	person.region="home"
	var before:=world.state.duplicate(true)
	check(world.step(5,false) and world.state==before,"No players pauses the route")
	world.save_path=path.path_join("missing")
	check(not world.step(1,true) and world.state==before,"Dispatch rollback restores source and job")
	world.save_path=path
	check(world.step(1,true) and source().items.copper_ore==5 and status()=="transit","First batch ships while owner is away")
	var loaded:=World.new()
	check(loaded.load_world(path) and loaded.state.mine_freight.jobs[ACTOR].items.copper_ore==4 and loaded.state.mine_auto_freight.routes[ACTOR].enabled,"In-flight route and cargo persist")
	var legacy:=loaded.state.duplicate(true)
	legacy.version=12;legacy.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.erase("flower_nursery")
	legacy.regions.erase("tianwei")
	legacy.erase("salt_pan")
	legacy.regions.erase("beimen")
	legacy.mine_freight.jobs={}
	legacy.erase("mine_auto_freight")
	check(valid(legacy) and legacy.version==26 and legacy.mine_auto_freight==Auto.fresh(),"Legacy migration preserves boxes and adds empty routes")

	var before_delivery:=world.state.duplicate(true)
	world.save_path=path.path_join("missing")
	check(not world.step(60,true) and world.state==before_delivery,"Delivery and next dispatch roll back together when saving fails")
	world.save_path=path
	check(world.step(60,true) and target().items.copper_ore==4 and source().items.copper_ore==1 and status()=="transit","Retry delivers first batch once and dispatches exactly one new batch")
	var original_target:=target()
	var original_id:String=original_target.freight_id
	world.state.objects["42,36"]=original_target
	world.state.objects.erase("41,36")
	check(world.step(1,true) and original_target.items.copper_ore==4 and status()=="transit","Moving the destination preserves its ID and leaves in-flight cargo pending")
	world.state.objects["41,36"]=original_target
	world.state.objects.erase("42,36")
	check(world.step(59,true) and target().freight_id==original_id and target().items.copper_ore==8 and status()=="waiting","Original destination restored at its cell receives the second batch once")
	source().items.copper_ore=5
	world.state.objects["42,36"]=original_target
	world.state.objects.erase("41,36")
	check(world.step(1,true) and source().items.copper_ore==5 and status()=="missing_target","Route waits while the original destination is away from its cell")
	world.state.objects["41,36"]=original_target
	world.state.objects.erase("42,36")
	check(world.step(1,true) and source().items.copper_ore==1 and status()=="transit","Third batch is dispatched to the original destination")
	world.state.objects["41,36"]=box(ACTOR,{})
	check(world.step(60,true) and status()=="held" and target().items.is_empty() and original_target.items.copper_ore==8,"Same-cell replacement holds in-flight cargo without credit")
	person=world.state.players[ACTOR]
	person.x=40.5
	person.y=30.5
	check(world.act(ACTOR,"claim","freight_claim",World.MINE_FREIGHT.CLAIM_CELL,"").ok and person.inventory.copper_ore==5 and status()=="missing_target","Held cargo claimed once; replaced destination still invalid")
	check(not world.act(ACTOR,"claim-again","freight_claim",World.MINE_FREIGHT.CLAIM_CELL,"").ok,"Cannot claim delivered cargo again")
	person.region="mine_4"
	person.x=34.5
	person.y=21.5
	check(action("stop","mine_auto_toggle") and action("replace","mine_auto_config",JSON.stringify(config)) and action("re-enable","mine_auto_toggle"),"Owner can explicitly bind replacement")
	target().items.copper_ore=1000000000
	source().items.copper_ore=9
	check(world.step(1,true) and status()=="target_full" and source().items.copper_ore==9,"Full destination leaves source untouched")
	source().erase("freight_id")
	check(world.step(1,true) and status()=="missing_source" and source().items.copper_ore==9,"Rebuilt source is never drained")
	var malformed:=world.state.duplicate(true)
	malformed.mine_auto_freight.routes[ACTOR].batch=0
	check(not valid(malformed),"Malformed persisted route rejected")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("MINE_AUTO_FREIGHT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
