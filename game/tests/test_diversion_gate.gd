extends SceneTree
## 第 40 章家園「分流閘」diversion_gate (industry.gd GATE_* + World craft/build/gate_mode +
## INDUSTRY.plan gate semantics) rules test. Headless World-level, real World.step time.
##
## EARNED through real World.act: bench, every kit craft (diversion_gate_kit), every
## build / move / remove / undo_build, hoe + seed of the four radish plots, sprinkler /
## pump toggles, refill_tank, every gate_mode change. Crop watering and growth come
## only from real World.step ticks (no direct crop writes).
## WRITTEN DIRECTLY (disclosed): player x/y (standing spots), craft materials and the
## device kits (pump/tank/pipe/sprinkler kits, wood/stone for the bench), state.removed
## on the two river-side tiles whose base resource would block building, the completed
## Lanyang revisit fixture (lanyang_life repaired, one completed history_memory record +
## plaque, lanyang_revisit completed; earned path is covered in test_lanyang_revisit),
## tank/sprinkler water levels for the scarce-water plan checks, and tampered saves.
const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const OWNER:="gate-owner-token-81f0"
const OTHER:="gate-other-token-2b6c"
const BENCH:=Vector2i(50,27)
## The water row sits at y=28, clear of the reserved mill site (47..49,23..25) and approach (48,26).
const FAR_S:=Vector2i(46,28)
const PIPE_A:=Vector2i(47,28)
const GATE:=Vector2i(48,28)
const NEAR_S:=Vector2i(49,28)
const PIPE_B:=Vector2i(50,28)
const TANK:=Vector2i(51,28)
const PIPE_C:=Vector2i(52,28)
const PUMP:=Vector2i(53,28)
const NEAR_CROPS:=[Vector2i(49,27),Vector2i(49,29)]
const FAR_CROPS:=[Vector2i(46,27),Vector2i(46,29)]
const EXTRA_GATES:=[Vector2i(46,22),Vector2i(47,22),Vector2i(48,22),Vector2i(49,22),Vector2i(50,22),Vector2i(51,22),Vector2i(46,23)]
const NINTH_GATE:=Vector2i(51,23)
const MOVE_TO:=Vector2i(48,29)
const LEGACY_NETWORK:=["water_pipe","water_tank","water_pump","sprinkler","medium_sprinkler","waterworks"]

var checks:=0
var failures:=0
var serial:=0
var temp_files:=[]

func expect(value:bool,message:String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize() -> void:
	check_static()
	check_gate_free_identical()
	var path:=temp_path("main")
	var w:=World.new()
	w.save_path=path
	if main_flow(w):
		check_time(w)
		check_scarce(w)
		check_save(w,path)
		check_snapshot(w)
		check_undo_move_remove(w)
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("DIVERSION_GATE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("diversion-gate-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
	for suffix in ["",".bak",".tmp"]:temp_files.append(path+suffix)
	return path

static func canon(value:Variant) -> Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			out[k]=canon(value[k] if value.has(k) else value[StringName(k)])
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_equal_approx(value,roundf(value)) and absf(value)<9.0e15:return int(value)
	if value is StringName:return str(value)
	return value

static func same(a:Variant,b:Variant) -> bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

func k(c:Vector2i) -> String:
	return World.key(c)

func near(w:World,token:String,tile:Vector2i) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]="home"
	p["x"]=tile.x+0.5
	p["y"]=tile.y+2.5

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"gate-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	near(w,token,p)
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String,stand:=true) -> void:
	if stand:near(w,token,p)
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or str(r.get("message",""))==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func obj(w:World,c:Vector2i) -> Dictionary:
	return w.state.objects.get(k(c),{})

func crop(w:World,c:Vector2i) -> Dictionary:
	return w.state.crops.get(k(c),{})

func run_steps(w:World,count:int,dt:float=1.0) -> void:
	for i in count:w.step(dt,true)

## Disclosed fixture: canal repaired, OWNER's first memory completed + plaque, revisit completed (spring day 1 split).
func write_revisit_fixture(w:World) -> void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
	life.repaired=true
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{OWNER:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}

# ---------------------------------------------------------------- legacy plan --
# Verbatim copy of the pre-chapter-40 INDUSTRY.components/plan (without gates), used
# to prove gate-free networks are planned exactly as before.

static func legacy_components(state:Dictionary) -> Array:
	var objects:Dictionary=state.get("objects",{})
	var seen:Dictionary={}
	var result:Array=[]
	for start in objects:
		if seen.has(start) or objects[start].type not in LEGACY_NETWORK:continue
		var group:Dictionary={"keys":[],"tanks":[],"pumps":[],"sprinklers":[],"waterworks":[]}
		var queue:Array[String]=[start]
		seen[start]=true
		var owner:String=objects[start].owner
		var index:=0
		while index<queue.size():
			var key:=queue[index]
			index+=1
			group["keys"].append(key)
			match objects[key].type:
				"water_tank":group.tanks.append(key)
				"sprinkler","medium_sprinkler":group.sprinklers.append(key)
				"waterworks":group.waterworks.append(key)
				"water_pump":group.pumps.append(key)
			var parts:=key.split(",")
			var cell:=Vector2i(int(parts[0]),int(parts[1]))
			for offset in Industry.NEIGHBORS:
				var next:Vector2i=cell+offset
				var neighbor:="%d,%d"%[next.x,next.y]
				if seen.has(neighbor) or not objects.has(neighbor):continue
				var other:Dictionary=objects[neighbor]
				if other.owner!=owner or other.type not in LEGACY_NETWORK:continue
				seen[neighbor]=true
				queue.append(neighbor)
		result.append(group)
	return result

static func legacy_plan(world,pump_rate:int) -> Dictionary:
	var objects:Dictionary=world.state.objects
	var water:Dictionary={}
	for group in legacy_components(world.state):
		var tanks:Array=group.tanks
		if tanks.is_empty():continue
		var consumers:Array=group.sprinklers+group.waterworks
		var pumps:=0
		for pump in group.pumps:
			if objects[pump].enabled and Industry.near_river(world,world.cell(pump)):pumps+=1
		var incoming:=pumps*pump_rate
		for tank in tanks:
			var existing:=int(objects[tank].water)
			var accepted:=mini(incoming,Industry.TANK_CAPACITY-existing)
			water[tank]=existing+accepted
			incoming-=accepted
		var tank_index:=0
		for sprinkler in consumers:
			if not objects[sprinkler].enabled:continue
			var current:=int(objects[sprinkler].water)
			var supplied:=current
			var capacity:int=world.WATERWORKS.CAPACITY if objects[sprinkler].type=="waterworks" else Industry.SPRINKLER_CAPACITIES[objects[sprinkler].type]
			while supplied<capacity and tank_index<tanks.size():
				var tank:String=tanks[tank_index]
				var amount:=mini(int(water[tank]),capacity-supplied)
				water[tank]-=amount
				supplied+=amount
				if int(water[tank])==0:tank_index+=1
			if supplied!=current:water[sprinkler]=supplied
	for key in water.keys():
		if int(water[key])==int(objects[key].water):water.erase(key)
	return water

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(World.CRAFT.get("diversion_gate_kit")=={"name":"分流閘","ingredients":{"plank":2,"copper_joint":1,"stone":2},"yield":1},"craft recipe plank 2 / copper_joint 1 / stone 2 -> 1")
	expect(World.BUILD.get("diversion_gate")=={"name":"分流閘","diversion_gate_kit":1} and World.NAMES.get("diversion_gate_kit")=="分流閘","build entry and item name")
	expect("diversion_gate" in Industry.NETWORK and int(Industry.LIMITS.get("diversion_gate",0))==8,"gate joins the water network; limit 8 per region")
	expect(not "diversion_gate" in World.UNDO_SOLID,"gate is walk-through like water_pipe")
	expect(Industry.GATE_MODES==["open","low","closed"] and Industry.gate_mode_name("low")=="餘水" and Industry.gate_mode_name("closed")=="關閉" and Industry.gate_mode_name("open")=="全開","mode ids and names")
	expect(Industry.zone_report({"objects":{}},"1,1").ok==false,"zone_report on a missing gate")

# ------------------------------------------------- gate-free plan == legacy --

func gate_free_world(pipe_for_gate:bool) -> World:
	var w:=World.new()
	w.add_player(OWNER,"Owner")
	var o:Dictionary=w.state.objects
	var sprinkler:={"type":"sprinkler","owner":OWNER,"items":{},"water":0,"enabled":true,"next_water":0.0,"last_water":-1.0}
	o[k(FAR_S)]=sprinkler.duplicate(true)
	o[k(PIPE_A)]={"type":"water_pipe","owner":OWNER,"items":{}}
	o[k(GATE)]={"type":"water_pipe","owner":OWNER,"items":{}} if pipe_for_gate else {"type":"diversion_gate","owner":OWNER,"items":{},"mode":"open"}
	o[k(NEAR_S)]=sprinkler.duplicate(true)
	o[k(PIPE_B)]={"type":"water_pipe","owner":OWNER,"items":{}}
	o[k(TANK)]={"type":"water_tank","owner":OWNER,"items":{},"water":0}
	o[k(PIPE_C)]={"type":"water_pipe","owner":OWNER,"items":{}}
	o[k(PUMP)]={"type":"water_pump","owner":OWNER,"items":{},"enabled":true}
	# A second, separate gate-free network with a waterworks consumer and two tanks.
	o["30,40"]={"type":"water_tank","owner":OWNER,"items":{},"water":20}
	o["31,40"]={"type":"waterworks","owner":OWNER,"items":{},"enabled":true,"water":0,"input":{}}
	o["32,40"]={"type":"water_tank","owner":OWNER,"items":{},"water":5}
	o["33,40"]={"type":"medium_sprinkler","owner":OWNER,"items":{},"water":3,"enabled":true,"next_water":0.0,"last_water":-1.0}
	return w

func check_gate_free_identical() -> void:
	var plain:=gate_free_world(true)
	var gated:=gate_free_world(false)
	var cases:=[[0,0,0,true],[10,0,0,false],[16,2,0,false],[48,12,5,true],[30,11,12,false],[1,0,11,true]]
	for c:Array in cases:
		for w:World in [plain,gated]:
			w.state.objects[k(TANK)].water=int(c[0])
			w.state.objects[k(NEAR_S)].water=int(c[1])
			w.state.objects[k(FAR_S)].water=int(c[2])
			w.state.objects[k(PUMP)].enabled=bool(c[3])
		var now:=Industry.plan(plain,8)
		var old:=legacy_plan(plain,8)
		expect(same(now,old),"gate-free network: plan == legacy plan for %s (got %s vs %s)"%[str(c),str(now),str(old)])
		expect(same(Industry.plan(plain,12),legacy_plan(plain,12)),"gate-free network: plan == legacy at the Lanyang pump rate for %s"%str(c))
		expect(same(Industry.plan(gated,8),now),"all-open gate in place of a pipe plans exactly like the pipe for %s"%str(c))
	expect(same(Industry.components(plain.state),legacy_components(plain.state)),"gate-free components() unchanged")

# --------------------------------------------------------------- main flow --

func main_flow(w:World) -> bool:
	w.add_player(OWNER,"Owner")
	w.add_player(OTHER,"Other")
	var inv:Dictionary=w.state.players[OWNER].inventory
	for tile:Vector2i in [PIPE_C,PUMP]:
		if World.base_resource(tile)!="":w.state.removed[k(tile)]=true
	inv["wood"]=40
	inv["stone"]=40
	ok(w,OWNER,"build",BENCH,"bench","owner builds a workbench")
	inv["plank"]=18
	inv["copper_joint"]=9
	inv["stone"]=18
	near(w,OWNER,BENCH)
	refuse(w,OWNER,"craft",BENCH,"diversion_gate_kit",Industry.GATE_LOCKED,"craft before the Lanyang revisit")
	refuse(w,OWNER,"craft",BENCH,"diversion_gate_kit|chest:1,1",Industry.GATE_LOCKED,"sourced craft before the Lanyang revisit")
	write_revisit_fixture(w)
	expect(validates(w.state),"disclosed revisit fixture validates")
	for i in 9:
		ok(w,OWNER,"craft",BENCH,"diversion_gate_kit","craft gate kit %d"%(i+1))
	expect(int(inv.get("diversion_gate_kit",0))==9 and int(inv.plank)==0 and int(inv.copper_joint)==0 and int(inv.stone)==0,"nine kits for exactly 9×(plank 2, copper_joint 1, stone 2)")
	# Network: far sprinkler first (so it is first in the network order), then the rest.
	inv["sprinkler_kit"]=2
	inv["pipe_kit"]=3
	inv["tank_kit"]=1
	inv["pump_kit"]=1
	ok(w,OWNER,"build",FAR_S,"sprinkler","far sprinkler")
	ok(w,OWNER,"build",PIPE_A,"water_pipe","pipe A")
	ok(w,OWNER,"build",GATE,"diversion_gate","the diversion gate")
	expect(same(obj(w,GATE),{"type":"diversion_gate","owner":OWNER,"items":{},"mode":"open"}),"new gate is open with the standard object shape")
	expect(not w.blocked(GATE),"gate tile stays walkable")
	ok(w,OWNER,"build",NEAR_S,"sprinkler","near sprinkler")
	ok(w,OWNER,"build",PIPE_B,"water_pipe","pipe B")
	ok(w,OWNER,"build",TANK,"water_tank","tank")
	ok(w,OWNER,"build",PIPE_C,"water_pipe","pipe C")
	ok(w,OWNER,"build",PUMP,"water_pump","river pump")
	var groups:=Industry.components(w.state)
	var main_group:Dictionary={}
	for g in groups:
		if k(GATE) in g["keys"]:main_group=g
	expect(main_group.get("keys",[]).size()==8 and main_group.get("sprinklers",[])==[k(FAR_S),k(NEAR_S)],"one connected network; far sprinkler first in network order")
	# Limit: 8 gates per owner per region.
	for c:Vector2i in EXTRA_GATES:ok(w,OWNER,"build",c,"diversion_gate","extra gate %s"%k(c))
	inv["diversion_gate_kit"]=int(inv.get("diversion_gate_kit",0))+1
	refuse(w,OWNER,"build",NINTH_GATE,"diversion_gate","已達此設備的每人放置上限","ninth gate in the region")
	inv["diversion_gate_kit"]=int(inv.diversion_gate_kit)-1
	for c:Vector2i in EXTRA_GATES:ok(w,OWNER,"remove",c,"","remove extra gate %s"%k(c))
	expect(int(inv.get("diversion_gate_kit",0))==8,"removing returns each kit (8 in the bag)")
	# Crops: two plots per zone.
	for c:Vector2i in NEAR_CROPS+FAR_CROPS:
		ok(w,OWNER,"hoe",c,"","hoe %s"%k(c))
		w.state.players[OWNER].inventory["radish_seed"]=5
		ok(w,OWNER,"seed",c,"radish","seed radish %s"%k(c))
	# gate_mode rejections.
	refuse(w,OWNER,"gate_mode",GATE,"half",Industry.GATE_BAD_MODE,"unknown mode")
	refuse(w,OWNER,"gate_mode",GATE,"",Industry.GATE_BAD_MODE,"empty mode")
	refuse(w,OWNER,"gate_mode",GATE,"open",Industry.GATE_SAME_MODE,"same mode")
	refuse(w,OWNER,"gate_mode",PIPE_A,"closed",Industry.GATE_NOT_OWNER,"gate_mode on a pipe cell")
	refuse(w,OWNER,"gate_mode",Vector2i(45,22),"closed",Industry.GATE_NOT_OWNER,"gate_mode on an empty cell")
	refuse(w,OTHER,"gate_mode",GATE,"closed",Industry.GATE_NOT_OWNER,"another player's gate")
	var owner_person:Dictionary=w.state.players[OWNER]
	owner_person.x=GATE.x+0.5
	owner_person.y=GATE.y+6.5
	refuse(w,OWNER,"gate_mode",GATE,"closed","靠近一點，才能和它互動","gate_mode from six tiles away",false)
	return true

# ------------------------------------------------------------- real time --

func check_time(w:World) -> void:
	for c:Vector2i in [NEAR_S,FAR_S]:ok(w,OWNER,"toggle_sprinkler",c,"","enable sprinkler %s"%k(c))
	ok(w,OWNER,"refill_tank",TANK,"","fill the tank")
	ok(w,OWNER,"toggle_pump",PUMP,"","switch the river pump on")
	var closed:=ok(w,OWNER,"gate_mode",GATE,"closed","close the gate")
	expect(str(closed.message).contains("關閉") and obj(w,GATE).mode=="closed","gate closed")
	var report:=Industry.zone_report(w.state,k(GATE))
	var zones:={}
	for row in report.get("consumers",[]):zones[row.key]=row.zone
	expect(report.ok and report.mode=="closed" and zones.get(k(NEAR_S))==Industry.ZONE_FULL and zones.get(k(FAR_S))==Industry.ZONE_CUT,"zone_report: near full, far cut (%s)"%str(report))
	var t0:=float(w.state.time)
	run_steps(w,12)
	expect(float(w.state.time)>=t0+12.0-0.001,"12 s of real World.step time passed")
	for c:Vector2i in NEAR_CROPS:
		expect(crop(w,c).wet==true and float(crop(w,c).growth)>0.0,"closed gate: near crop %s watered and growing (growth %s)"%[k(c),str(crop(w,c).growth)])
	for c:Vector2i in FAR_CROPS:
		expect(crop(w,c).wet==false and float(crop(w,c).growth)==0.0,"closed gate: far crop %s dry, no growth"%k(c))
	expect(int(obj(w,FAR_S).water)==0 and int(obj(w,NEAR_S).water)>0,"closed gate: far sprinkler got no water (near %d)"%int(obj(w,NEAR_S).water))
	ok(w,OWNER,"gate_mode",GATE,"open","reopen the gate")
	run_steps(w,12)
	for c:Vector2i in FAR_CROPS:
		expect(crop(w,c).wet==true and float(crop(w,c).growth)>0.0,"reopened: far crop %s watered and growing (growth %s)"%[k(c),str(crop(w,c).growth)])
	expect(int(obj(w,FAR_S).water)>0,"reopened: far sprinkler received water")

func check_scarce(w:World) -> void:
	ok(w,OWNER,"toggle_pump",PUMP,"","switch the pump off for the scarce-water checks")
	var o:Dictionary=w.state.objects
	# Disclosed direct water levels.
	o[k(TANK)].water=10
	for c:Vector2i in [NEAR_S,FAR_S]:
		o[k(c)].water=0
		o[k(c)].network_water=0 # schema: network_water <= water
	var open_plan:=Industry.plan(w)
	expect(same(open_plan,{k(TANK):0,k(FAR_S):10}),"open gate, 10 water: network order serves the far sprinkler first (%s)"%str(open_plan))
	ok(w,OWNER,"gate_mode",GATE,"low","gate to 餘水 (low)")
	var low_plan:=Industry.plan(w)
	expect(same(low_plan,{k(TANK):0,k(NEAR_S):10}),"low gate, 10 water: near zone first, far zone nothing left (%s)"%str(low_plan))
	o[k(TANK)].water=16
	low_plan=Industry.plan(w)
	expect(same(low_plan,{k(TANK):0,k(NEAR_S):12,k(FAR_S):4}),"low gate, 16 water: near full 12, far gets the remaining 4 (%s)"%str(low_plan))
	var report:=Industry.zone_report(w.state,k(GATE))
	var zones:={}
	for row in report.consumers:zones[row.key]=row.zone
	expect(report.mode=="low" and zones.get(k(FAR_S))==Industry.ZONE_LOW and zones.get(k(NEAR_S))==Industry.ZONE_FULL,"zone_report: far zone is low")
	w.state.next_network_check=float(w.state.time)
	run_steps(w,1)
	expect(int(o[k(NEAR_S)].water)==12 and int(o[k(FAR_S)].water)==4 and int(o[k(TANK)].water)==0,"real step applies the low-gate split (near %d, far %d, tank %d)"%[int(o[k(NEAR_S)].water),int(o[k(FAR_S)].water),int(o[k(TANK)].water)])
	ok(w,OWNER,"gate_mode",GATE,"closed","close again")
	o[k(TANK)].water=48
	var cut:=Industry.plan(w)
	expect(same(cut,{}),"closed gate, full tank, near already full: nothing to move, far sprinkler not supplied (%s)"%str(cut))
	expect(int(o[k(FAR_S)].water)==4,"closed gate: far sprinkler keeps its own stored 4")

# ------------------------------------------------------------------- saves --

func check_save(w:World,path:String) -> void:
	expect(w.save(),"world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"fresh World reloads")
	expect(same(reloaded.state.objects,w.state.objects) and same(reloaded.state.crops,w.state.crops),"objects and crops equal after reload")
	expect(str(reloaded.state.objects[k(GATE)].mode)=="closed","gate mode survives reload")
	expect(same(Industry.plan(reloaded),Industry.plan(w)),"plan after reload identical")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"saved world validates"):return
	var fixture:=temp_path("fixture")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["mode missing","mode half","mode int","mode null","mode uppercase","gate holds items","nine gates for one owner","gate without the completed revisit","gate in Lanyang without the revisit"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	var eight:Dictionary=base.duplicate(true)
	for i in 7:eight.objects[k(EXTRA_GATES[i])]={"type":"diversion_gate","owner":OWNER,"items":{},"mode":"low"}
	expect(validates(eight),"control: eight gates for one owner validate")
	for mode:String in Industry.GATE_MODES:
		var each:Dictionary=base.duplicate(true)
		each.objects[k(GATE)].mode=mode
		expect(validates(each),"control: mode %s validates"%mode)

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var g:Dictionary=s.objects[k(GATE)]
	match label:
		"mode missing":g.erase("mode")
		"mode half":g.mode="half"
		"mode int":g.mode=1
		"mode null":g.mode=null
		"mode uppercase":g.mode="OPEN"
		"gate holds items":g.items={"wood":1}
		"nine gates for one owner":
			for i in 7:s.objects[k(EXTRA_GATES[i])]={"type":"diversion_gate","owner":OWNER,"items":{},"mode":"open"}
			s.objects[k(NINTH_GATE)]={"type":"diversion_gate","owner":OWNER,"items":{},"mode":"open"}
		"gate without the completed revisit":s.erase(Revisit.STATE_KEY)
		"gate in Lanyang without the revisit":
			s.objects.erase(k(GATE))
			s.erase(Revisit.STATE_KEY)
			s.regions.lanyang.objects["30,30"]={"type":"diversion_gate","owner":OWNER,"items":{},"mode":"open"}
	return s

# ---------------------------------------------------------------- snapshot --

func check_snapshot(w:World) -> void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	var keep:=w.save_path
	w.save_path=""
	session.peers={1:OWNER}
	var public:Dictionary=session.public_state("home")
	var server_report:=Industry.zone_report(w.state,k(GATE))
	var client_report:=Industry.zone_report(public,k(GATE))
	expect(public.objects[k(GATE)].get("mode")=="closed" and not JSON.stringify(public).contains(OWNER),"public snapshot carries the gate mode, no raw owner token")
	expect(client_report.ok and same(client_report.consumers,server_report.consumers) and client_report.mode==server_report.mode,"zone_report on the client snapshot matches the server")
	session.world=null
	session.queue_free()
	w.save_path=keep

# ----------------------------------------------------- undo / move / remove --

func check_undo_move_remove(w:World) -> void:
	var inv:Dictionary=w.state.players[OWNER].inventory
	var kits:=int(inv.get("diversion_gate_kit",0))
	var spot:=Vector2i(51,26)
	ok(w,OWNER,"build",spot,"diversion_gate","build a gate to undo")
	var summary:=w.undo_summary(OWNER)
	expect(summary.available==true,"undo is available for the new gate (%s)"%str(summary.reason))
	ok(w,OWNER,"undo_build",spot,str(summary.id),"undo the gate build")
	inv=w.state.players[OWNER].inventory # undo installs a fresh inventory dictionary
	expect(not w.state.objects.has(k(spot)) and int(inv.get("diversion_gate_kit",0))==kits,"undo removed the gate and returned the kit")
	refuse(w,OTHER,"move_object",GATE,k(MOVE_TO),"","another player cannot move the gate")
	ok(w,OWNER,"move_object",GATE,k(MOVE_TO),"owner moves the gate")
	expect(not w.state.objects.has(k(GATE)) and str(obj(w,MOVE_TO).get("mode",""))=="closed","moved gate keeps its mode")
	var split:=false
	for g in Industry.components(w.state):
		if k(NEAR_S) in g["keys"] and k(FAR_S) in g["keys"]:split=true
	expect(not split,"moving the gate out splits the network (far sprinkler no longer connected)")
	ok(w,OWNER,"remove",MOVE_TO,"","owner removes the gate")
	expect(not w.state.objects.has(k(MOVE_TO)) and int(inv.get("diversion_gate_kit",0))==kits+1,"removal returns the kit")
	expect(validates(w.state),"final world validates")
