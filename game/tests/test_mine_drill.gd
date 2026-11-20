extends SceneTree
const World=preload("res://scripts/world.gd")
const Drill=World.MINE_DRILL
const Schema=preload("res://scripts/save_schema.gd")
const CELL:=Vector2i(28,24)
var world:=World.new()
var checks:=0
var failures:=0

func expect(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func valid(data:Dictionary)->bool:
	return Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func act(id:String,action:String,extra:String="",tile:Vector2i=CELL,actor:String="alpha")->bool:
	return world.act(actor,id,action,tile,extra).ok

func machine(owner:String="alpha")->Dictionary:
	var result:=Drill.fresh(0)
	result.merge({"type":"mine_drill","owner":owner})
	return result

func stand(actor:String,region:String)->void:
	var person:Dictionary=world.state.players[actor]
	person.region=region
	person.x=27.5
	person.y=23.5

func _initialize()->void:
	var path:=OS.get_environment("TEMP").path_join("mine-drill-%s.json"%Crypto.new().generate_random_bytes(12).hex_encode())
	world.save_path=path
	for actor in ["alpha","beta"]:
		world.add_player(actor,actor)
		world.state.players[actor].inventory.merge({"reinforced_pick":1,"charcoal":10,"mine_drill_kit":3})
	var legacy:=world.state.duplicate(true)
	legacy.version=11;legacy.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.erase("flower_nursery")
	legacy.regions.erase("tianwei")
	legacy.erase("salt_pan")
	legacy.regions.erase("beimen")
	expect(valid(legacy) and legacy.version==preload("res://scripts/save_schema.gd").VERSION and legacy.players.alpha.inventory.wood==12,"v11 migrates without losing inventory")
	var home:Dictionary=world.state.players.alpha
	home.x=41.5;home.y=36.5
	home.inventory.merge(Drill.COST,true)
	world.state.objects["41,36"]={"type":"bench","owner":"alpha","items":{}}
	expect(not act("locked-craft","craft","mine_drill_kit",Vector2i(41,36)),"Locked craft refused despite materials")
	world.state.mine_depths.unlocked=4
	world.state.mine_depths.pumped=24
	stand("alpha","mine_4")
	expect(not act("locked-build","build","mine_drill"),"Locked placement refused despite kit")
	world.state.mine_depths.unlocked=5
	home.region="home";home.x=41.5;home.y=36.5
	expect(act("craft","craft","mine_drill_kit",Vector2i(41,36)) and home.inventory.mine_drill_kit==4 and home.inventory.plank==0,"Recipe consumes exact requirements")
	expect(not act("home-build","build","mine_drill",Vector2i(42,36)),"Above-ground placement refused")
	stand("alpha","mine_4")
	stand("beta","mine_4")
	expect(not act("off-node","build","mine_drill",Vector2i(26,23)) and act("place","build","mine_drill"),"Placement restricted to designated node")
	expect(not act("two","build","mine_drill",Vector2i(28,22),"beta"),"Different owner cannot claim same designated node")
	var objects:Dictionary=world.state.regions.mine_4.objects
	var drill:Dictionary=objects["28,24"]
	expect(not act("foreign","mine_drill_toggle","",CELL,"beta"),"Foreign operation refused")
	expect(act("manual","mine_extract","",Drill.NODE,"beta"),"Manual can extract while drill idle")
	expect(act("enable","mine_drill_toggle"),"Enable machine")
	objects["28,25"]={"type":"conveyor","owner":"alpha","items":{"charcoal":1},"filter":"charcoal","dir":0,"enabled":true}
	expect(world.step(1,true) and drill.fuel==1 and not drill.has("job"),"Same-owner belt delivers fuel but manual cooldown blocks start")
	expect(world.step(50,false) and world.state.time==1,"No players means clock and fuel pause")
	var before:=world.state.duplicate(true)
	world.save_path=path.path_join("missing")
	expect(not world.step(11,true) and world.state==before,"Batch start and clock roll back together")
	world.save_path=path
	expect(world.step(11,true),"Batch start succeeds after storage recovers")
	objects=world.state.regions.mine_4.objects
	drill=objects["28,24"]
	expect(drill.has("job") and drill.fuel==0 and drill.job.ready==32,"Batch consumes one fuel and reserves node for 20 seconds")
	expect(not act("reserved","mine_extract","",Drill.NODE,"beta"),"Reserved node refuses manual extraction")
	world.state.players.beta.x=24.5;world.state.players.beta.y=23.5
	expect(act("other","mine_extract","",World.MINES.NODES[1],"beta"),"Other ore nodes remain manual")
	expect(act("stop","mine_drill_toggle") and not act("active-remove","remove"),"Stop still preserves active job and blocks dismantling")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.regions.mine_4.objects["28,24"].has("job"),"Active batch is reloadable")
	world.state.players.alpha.region="home"
	world.state.players.beta.region="home"
	expect(world.step(20,true) and drill.items.copper_ore==4 and not drill.has("job") and world.state.mine_depths.ready.mine_4[Drill.NODE_KEY]==44,"Home activity completes mine batch and starts shared cooldown")
	stand("alpha","mine_4")
	expect(not act("cooldown","mine_extract","",Drill.NODE),"Manual mining shares drill cooldown")
	home=world.state.players.alpha
	home.inventory.copper_ore=1000000000
	expect(not act("full-bag","mine_drill_collect") and drill.items.copper_ore==4,"Overflow preserves output")
	home.inventory.copper_ore=0
	expect(act("collect","mine_drill_collect") and act("collect","mine_drill_collect") and home.inventory.copper_ore==4,"Collection retry does not duplicate output")
	expect(not act("wrong-move","move_object","27,25") and act("move","move_object","28,22") and objects["28,22"].dir==2,"Moving requires valid placement and updates direction")
	stand("alpha","mine_5")
	expect(act("place-gold","build","mine_drill"),"One owner can place another mine level drill")
	stand("alpha","mine_3")
	expect(not act("global-cap","build","mine_drill"),"Owner maximum applies across levels")
	var gold:Dictionary=world.state.regions.mine_5.objects["28,24"]
	gold.items.gold_ore=32;gold.enabled=true;gold.fuel=1
	expect(world.step(1,true) and not gold.has("job") and gold.fuel==1,"Full gold output does not consume fuel")
	var bad:=world.state.duplicate(true)
	bad.regions.mine_5.objects["28,24"].items={"stone":1}
	expect(not valid(bad),"Save rejects wrong regional output")
	bad=world.state.duplicate(true)
	bad.regions.mine_5.objects["28,24"].dir=1
	expect(not valid(bad),"Save rejects direction not pointing at node")
	bad=world.state.duplicate(true)
	bad.regions.mine_3.objects["28,24"]=machine()
	expect(not valid(bad),"Save enforces global owner cap")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("MINE_DRILL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
