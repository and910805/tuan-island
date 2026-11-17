extends SceneTree

const World=preload("res://scripts/world.gd")
const MILL:=Vector2i(40,34)
const PUMP:=Vector2i(53,24)
var w:=World.new()
var checks:=0
var failures:=0

func check(condition:bool, message:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL "+message)

func act(action:String,tile:Vector2i,extra:="",who:="a") -> bool:
	w.state.players[who].x=tile.x+0.5
	w.state.players[who].y=tile.y+1.5
	return w.act(who,str(checks),action,tile,extra).ok

func fixture(key:String,kind:String,extra:Dictionary={}) -> void:
	var data:Dictionary={"owner":"a","type":kind,"items":{}}
	data.merge(extra,true)
	w.state.objects[key]=data

func write(path:String,data:Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func _initialize() -> void:
	w.add_player("a","甲")
	w.add_player("b","乙")
	fixture("40,34","sawmill")
	fixture("42,34","charcoal_kiln")
	var inv:Dictionary=w.state.players.a.inventory
	inv.wood=12
	check(not act("start_processing",MILL,"charcoal"),"wrong recipe denied")
	check(act("start_processing",MILL,"plank") and inv.wood==8,"sawmill consumes wood")
	check(not act("claim_processing",MILL),"early claim denied")
	check(not act("cancel_processing",MILL,"","b"),"other player cannot cancel")
	check(not act("remove",MILL),"busy machine cannot be removed")
	check(not act("move_object",MILL,"41,34"),"busy machine cannot move")
	check(w.step(12,false) and not act("claim_processing",MILL),"offline processing pauses")
	check(w.step(12,true) and act("claim_processing",MILL) and inv.plank==2,"sawmill grants two planks")
	check(not act("claim_processing",MILL),"output cannot be claimed twice")
	w.state.forest["41,35"]={"owner":"a","growth":World.TREE_TIME,"mature":true}
	var harvest_tile:=Vector2i(41,35)
	w.state.players.a.x=41.5
	w.state.players.a.y=34.5
	var trees_before:=int(inv.sapling)
	for hit in range(3):
		w.act("a","resin-hit-%d"%hit,"axe",harvest_tile)
	check(inv.get("resin",0)==1 and inv.sapling==trees_before+1 and inv.wood==14,"mature trees add resin and retain existing drops")
	inv.wood=8
	check(act("start_processing",Vector2i(42,34),"charcoal"),"kiln starts")
	check(act("cancel_processing",Vector2i(42,34)) and inv.wood==8,"cancellation refunds exact input")
	check(act("start_processing",Vector2i(42,34),"charcoal") and w.step(16,true),"kiln ready online")
	inv.charcoal=999999999
	check(not act("claim_processing",Vector2i(42,34)) and w.state.objects["42,34"].has("job"),"inventory limit keeps job intact")
	inv.charcoal=0
	check(act("claim_processing",Vector2i(42,34)) and inv.charcoal==2,"kiln outputs two charcoal")
	check(World.INDUSTRY.near_river(w,PUMP) and not World.INDUSTRY.near_river(w,MILL),"pump siting checks river")
	fixture("53,24","water_pump",{"enabled":true})
	fixture("53,25","water_pipe")
	fixture("53,26","water_tank",{"water":0})
	fixture("52,26","sprinkler",{"water":0,"enabled":true,"next_water":0,"last_water":-1})
	fixture("52,25","water_tank",{"water":7,"owner":"b"})
	w.state.crops["51,26"]={"owner":"a","kind":"radish","growth":0,"wet":false,"remaining":1}
	var info:=World.INDUSTRY.network_info(w.state,"52,26")
	check(info.connected_tanks==1 and info.connected_pumps==1,"graph separates owners")
	var industry:=World.INDUSTRY
	check(industry.pipe_caption(0,{})=="水管 · 未接通","Unconnected pipe has its own reason")
	check(industry.pipe_caption(1,{"connected_pumps":1})=="水管 · 未接水桶或水塔","A pump without storage is explained")
	check(industry.pipe_caption(5,info)=="水管 · 蓄水已空","An empty connected tank stays distinguishable from a disconnected pipe")
	check(industry.pipe_caption(5,{"tower_water":12,"tower_capacity":48})=="水管 · 管網蓄水 12／48","Tower-only storage is included")
	var split:={"objects":{
		"1,1":{"type":"water_tank","owner":"a","water":24},
		"2,1":{"type":"diversion_gate","owner":"a","mode":"closed"},
		"3,1":{"type":"water_pipe","owner":"a"},
		"4,1":{"type":"water_tower","owner":"a","water":0,"enabled":true}}}
	check(not industry.network_info(split,"3,1").flow_visible,"An empty nearby outlet cannot animate water stored across a closed gate")
	split.objects["4,1"].water=1
	check(industry.network_info(split,"3,1").flow_visible,"A wet outlet on this side can animate the pipe")
	split.objects["4,1"].enabled=false
	check(not industry.network_info(split,"3,1").flow_visible,"Storage-only tower stops feeding the pipe animation")
	split.objects["4,1"].merge({"enabled":true,"quota":4,"quota_day":industry.tower_day(0.0),"quota_used":4},true)
	check(not industry.network_info(split,"3,1").flow_visible,"An exhausted tower quota stops its pipe animation")
	split.time=1440.0
	check(industry.network_info(split,"3,1").flow_visible,"The next day restores the pipe animation")
	check(not act("refill_tank",Vector2i(53,26),"","b") and not act("toggle_pump",PUMP,"","b"),"foreign devices reject actions")
	var before:=w.state.duplicate(true)
	w.save_path="user://missing-industry-fixture/world.json"
	check(not w.step(8,true) and w.state==before,"flow rolls back pump, sprinkler, crop, time together")
	var path:="user://industry-%d.json"%Time.get_ticks_usec()
	w.save_path=path
	check(w.step(8,true) and w.state.objects["52,26"].water==7 and w.state.crops["51,26"].wet,"pump contributes eight and crop costs one")
	check(w.state.objects["52,25"].water==7,"foreign tank unchanged")
	var loaded:=World.new()
	check(loaded.load_world(path) and loaded.state.objects["52,26"].water==7,"flow persists with save")
	check(loaded.step(1,true) and loaded.state.objects["52,26"].water==7,"reload cannot bypass pump interval")
	w.state.objects.erase("53,25")
	check(World.INDUSTRY.network_info(w.state,"52,26").connected_pumps==0,"disconnect updates graph immediately")
	check(w.step(8,true) and w.state.objects["52,26"].water==7,"disconnected pump cannot refill")
	check(act("refill_tank",Vector2i(53,26)) and w.state.objects["53,26"].water==48,"manual tank fill remains available")
	check(industry.pipe_caption(1,industry.network_info(w.state,"53,26"))=="水管 · 管網蓄水 48／48","Refilled network reports actual available storage")
	check(w.step(8,false) and w.state.objects["53,26"].water==48,"offline water transfer pauses")
	check(w.step(8,true) and w.state.objects["53,26"].water==43 and w.state.objects["52,26"].water==12,"tank only transfers the missing amount")
	var broken:Dictionary=w.state.duplicate(true)
	broken.objects["53,26"].water=49
	write(path+".invalid",broken)
	check(not loaded.load_world(path+".invalid"),"out-of-range tank rejected")
	broken=w.state.duplicate(true)
	broken.objects["53,24"].enabled="yes"
	write(path+".invalid",broken)
	check(not loaded.load_world(path+".invalid"),"invalid pump flag rejected")
	broken=w.state.duplicate(true)
	broken.objects["40,34"].job={"kind":"plank","owner":"a","ready":w.state.time,"ingredients":{"wood":4},"yield":50}
	write(path+".invalid",broken)
	check(not loaded.load_world(path+".invalid"),"forged processing yield rejected")
	broken.objects["40,34"].job.yield=2
	broken.objects["40,34"].job.ingredients.wood=40
	write(path+".invalid",broken)
	check(not loaded.load_world(path+".invalid"),"forged processing refund rejected")
	broken.objects["40,34"].job.ingredients.wood=4
	write(path+".invalid",broken)
	check(loaded.load_world(path+".invalid") and loaded.state.objects["40,34"].job.kind=="plank","valid processing job reloads")
	DirAccess.remove_absolute(path+".invalid")
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("INDUSTRY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
