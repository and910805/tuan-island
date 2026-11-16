extends SceneTree

const World=preload("res://scripts/world.gd")
const STATION:=Vector2i(41,34)
const NORTH:="41,32"
const EAST:="43,34"
const SOUTH:="41,36"
const WEST:="39,34"
var w:=World.new()
var checks:=0
var failures:=0
var serial:=0

func check(condition:bool,label:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL "+label)

func act(verb:String,extra:="",who:="a",tile:=STATION,request:="") -> bool:
	serial+=1
	return w.act(who,request if not request.is_empty() else str(serial),verb,tile,extra).ok

func grown(owner:String) -> Dictionary:
	return {"owner":owner,"growth":World.TREE_TIME,"mature":true}

func _initialize() -> void:
	w.add_player("a","甲")
	w.add_player("b","乙")
	for player in w.state.players.values():
		player.x=41.5
		player.y=35.5
	var inv:Dictionary=w.state.players.a.inventory
	inv.merge({"forester_kit":3,"charcoal":9,"sapling":9},true)
	var key:=World.key(STATION)
	check(act("build","forester") and w.blocked(STATION) and inv.forester_kit==2,"place station")
	var station:Dictionary=w.state.objects[key]
	check(not station.enabled and station.last_cycle==-1,"new station is disabled")
	check(not act("toggle_forester","","b") and not act("load_forester","sapling","b"),"other owner denied")
	check(not act("load_forester","wood"),"invalid input denied")
	var native:=Vector2i.ZERO
	for x in range(10,70):
		for y in range(10,48):
			var candidate:=Vector2i(x,y)
			if not w.protected(candidate) and not w.water(candidate) and w.resource(candidate)=="tree":
				native=candidate
				break
		if native!=Vector2i.ZERO:break
	check(native!=Vector2i.ZERO and World.FORESTRY.plot_status(w,native,"a")=="blocked","natural trees are excluded")
	check(act("load_forester","sapling") and station.saplings==4 and inv.sapling==5,"load at most four")
	check(act("toggle_forester"),"enable")
	check(w.step(12,false) and not w.state.forest.has(NORTH),"offline pauses")
	check(w.step(1,true) and w.state.forest.has(NORTH) and station.saplings==3 and station.fuel==0,"seeds without fuel")
	w.state.forest[EAST]=grown("a")
	check(w.step(12,true) and w.state.forest[EAST].mature,"without fuel no harvest")
	check(act("load_forester","charcoal") and act("load_forester","charcoal") and not act("load_forester","charcoal") and station.fuel==8,"fuel cap")
	w.state.forest[SOUTH]=grown("b")
	check(w.step(12,true) and w.state.forest[SOUTH].mature and station.fuel==8,"other owner's tree untouched")
	w.state.crops[WEST]={"owner":"a","kind":"","wet":false,"growth":0,"remaining":1}
	check(w.step(12,true) and not w.state.forest.has(WEST),"farm tile untouched")
	w.state.forest[NORTH]=grown("a")
	station.items={"wood":48,"fiber":16,"resin":8}
	check(w.step(12,true) and station.fuel==8 and w.state.forest[NORTH].mature,"full output prevents harvest")
	station.items.clear()
	station.cursor=0
	var second:=Vector2i(43,32)
	var second_key:=World.key(second)
	w.state.objects[second_key]={"type":"forester","owner":"a","items":{}}
	w.state.objects[second_key].merge(World.FORESTRY.fresh(w.state.time))
	w.state.objects[second_key].merge({"enabled":true,"cursor":3,"fuel":1},true)
	var before:=w.state.duplicate(true)
	w.save_path="user://missing-forestry-dir/test.json"
	check(not w.step(12,true) and w.state==before,"failed write rolls back harvest, growth, and cursors")
	var save_path:="user://forestry-%d.json"%Time.get_ticks_usec()
	w.save_path=save_path
	check(w.step(12,true),"harvest saves")
	station=w.state.objects[key]
	inv=w.state.players.a.inventory
	check(station.items=={"wood":6,"fiber":2,"resin":1} and station.fuel==7 and station.saplings==3,"harvest exact yields and fuel, no sapling cost")
	check(not w.state.forest[NORTH].mature and w.state.forest[NORTH].growth==0 and w.state.objects[second_key].fuel==1,"overlapping stations cannot harvest twice")
	var reloaded:=World.new()
	check(reloaded.load_world(save_path) and reloaded.state.objects[key].fuel==7 and not reloaded.state.forest[NORTH].mature,"station and replant persist")
	var malformed:=w.state.duplicate(true)
	var malformed_path:=save_path+".invalid"
	for variant in [{"fuel":9},{"cursor":4},{"enabled":"true"},{"next_cycle":float(w.state.time)+13.0},
			{"items":{"plank":1}},{"items":{"resin":9}}]:
		malformed.objects[key].merge(variant,true)
		var file:=FileAccess.open(malformed_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(malformed))
		file.close()
		check(not reloaded.load_world(malformed_path),"malformed station rejected: "+str(variant))
		malformed=w.state.duplicate(true)
	DirAccess.remove_absolute(malformed_path)
	check(not act("build","forester","a",Vector2i(42,35)) and inv.forester_kit==2,"limit two per owner")
	check(not act("remove") and not act("move_object","40,35"),"enabled loaded station cannot be moved or removed")
	inv.wood=1000000000
	check(not act("collect_forester") and station.items.wood==6 and not inv.has("resin"),"collection overflow leaves all products")
	inv.wood=12
	check(act("collect_forester","","a",STATION,"collect") and inv.wood==18 and inv.resin==1,"collect exact products")
	check(act("collect_forester","","a",STATION,"collect") and not act("collect_forester") and inv.wood==18,"replay and fresh duplicate cannot pay twice")
	check(act("toggle_forester") and not act("remove"),"stopping alone cannot remove supplied station")
	check(act("unload_forester") and station.fuel==0 and station.saplings==0 and inv.charcoal==8 and inv.sapling==8,"unload returns remaining supplies")
	check(act("move_object","40,35") and not w.state.objects.has(key),"empty stopped station can move")
	check(act("remove","","a",Vector2i(40,35)) and inv.forester_kit==3 and w.state.forest.has(NORTH),"remove returns kit, preserves replanted trees")
	for file in [save_path,save_path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("FORESTRY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
