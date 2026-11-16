extends SceneTree
## 第 40 章家園「水塔」water_tower (industry.gd TOWER_* + World craft/build/tower_toggle +
## INDUSTRY.plan tower semantics) rules test. Headless World-level, real World.step time.
##
## EARNED through real World.act: bench, every kit craft (water_tower_kit ×5,
## diversion_gate_kit ×1), every build / move / remove / undo_build, hoe + seed of the four
## radish plots, the day-10 harvest + reseed of the two far plots, sprinkler / pump toggles,
## refill_tank, gate_mode changes, every tower_toggle. Tower refill, sprinkler refills, crop
## watering and growth in the main world come only from real World.step ticks.
## WRITTEN DIRECTLY (disclosed): player x/y (standing spots), craft materials and the device
## kits (pump/tank/pipe/sprinkler kits, wood/stone for the bench, radish seeds),
## state.removed on the two river-side tiles whose base resource would block building,
## next_network_check (= now, so the first step runs a network tick), the completed Lanyang
## revisit fixture (same as test_diversion_gate; earned path is covered in
## test_lanyang_revisit), the contrast world (a reload of the main save with the tower cell
## rewritten to a water_pipe), every object of the pure plan() fixture worlds
## (tank/tower/sprinkler/waterworks water, gate modes, tower enabled flags) and the tampered
## saves.
const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Weather=preload("res://scripts/weather.gd")
const OWNER:="tower-owner-token-5d1a"
const OTHER:="tower-other-token-c37e"
const BENCH:=Vector2i(50,27)
const FAR_S:=Vector2i(46,24)
const TOWER:=Vector2i(47,24)
const GATE:=Vector2i(48,24)
const NEAR_S:=Vector2i(49,24)
const PIPE_B:=Vector2i(50,24)
const TANK:=Vector2i(51,24)
const PIPE_C:=Vector2i(52,24)
const PUMP:=Vector2i(53,24)
const NEAR_CROPS:=[Vector2i(49,23),Vector2i(49,25)]
const FAR_CROPS:=[Vector2i(46,23),Vector2i(46,25)]
const EXTRA_TOWERS:=[Vector2i(46,28),Vector2i(47,28),Vector2i(48,28)]
const FIFTH_TOWER:=Vector2i(49,28)
const DAYS:=30
const DAY_STEPS:=15
const DAY_DT:=96.0

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
	check_tower_free_identical()
	check_plan_fixtures()
	var path:=temp_path("main")
	var w:=World.new()
	w.save_path=path
	if main_flow(w):
		if check_fill(w):
			check_closed_gate_days(w,path)
		check_save(w,path)
		check_snapshot(w)
		check_undo_move_remove(w)
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("WATER_TOWER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("water-tower-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
	for suffix in ["",".bak",".tmp"]:temp_files.append(path+suffix)
	return path

static func canon(value:Variant) -> Variant:
	if value is Dictionary:
		var keys:Array=[]
		for key in value:keys.append(str(key))
		keys.sort()
		var out:={}
		for key:String in keys:
			out[key]=canon(value[key] if value.has(key) else value[StringName(key)])
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
	return w.act(token,"tower-req-%d"%serial,action,p,extra)

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

## Disclosed fixture: canal repaired, OWNER's first memory completed + plaque, revisit completed.
func write_revisit_fixture(w:World) -> void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
	life.repaired=true
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{OWNER:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}

## Sum of stored water over tanks, towers, sprinklers and waterworks; `plan` overrides.
static func water_total(w:World,plan:Dictionary={}) -> int:
	var total:=0
	for key in w.state.objects:
		var o:Dictionary=w.state.objects[key]
		if o.get("type") in ["water_tank","water_tower","sprinkler","medium_sprinkler","waterworks"]:
			total+=int(plan.get(key,o.get("water",0)))
	return total

# ------------------------------------------------------ pre-tower plan copy --
# Verbatim copy of INDUSTRY.plan as it was before the water tower (chapter 40 gates
# included), used to prove tower-free networks are planned exactly as before.

static func pre_tower_plan(world,pump_rate:int) -> Dictionary:
	var objects:Dictionary=world.state.objects
	var water:Dictionary={}
	for group in Industry.components(world.state):
		var tanks:Array=group.tanks
		if tanks.is_empty():continue
		var consumers:Array=group.sprinklers+group.waterworks
		if Industry._has_gate(objects,group):consumers=Industry.gated_consumers(objects,group)
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

# ---------------------------------------------------------- fixture objects --

func f_tank(water:int) -> Dictionary:
	return {"type":"water_tank","owner":OWNER,"items":{},"water":water}

func f_tower(water:int,enabled:=true) -> Dictionary:
	return {"type":"water_tower","owner":OWNER,"items":{},"water":water,"enabled":enabled}

func f_spr(water:int) -> Dictionary:
	return {"type":"sprinkler","owner":OWNER,"items":{},"water":water,"enabled":true,"next_water":0.0,"last_water":-1.0}

func f_pipe() -> Dictionary:
	return {"type":"water_pipe","owner":OWNER,"items":{}}

func f_gate(mode:String) -> Dictionary:
	return {"type":"diversion_gate","owner":OWNER,"items":{},"mode":mode}

func f_world(row:Array,y:int,x0:int=20) -> World:
	var w:=World.new()
	w.add_player(OWNER,"Owner")
	for i in row.size():
		w.state.objects[k(Vector2i(x0+i,y))]=row[i]
	return w

func c(x:int,y:int) -> String:
	return k(Vector2i(x,y))

## plan() equals `expected`, and stored water is conserved (+pump_in).
func plan_is(w:World,expected:Dictionary,label:String,pump_in:int=0) -> Dictionary:
	var plan:=Industry.plan(w)
	expect(same(plan,expected),"%s: plan %s (expected %s)"%[label,str(plan),str(expected)])
	expect(water_total(w,plan)==water_total(w)+pump_in,"%s: water conserved (before %d, after %d, pump %d)"%[label,water_total(w),water_total(w,plan),pump_in])
	return plan

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(World.CRAFT.get("water_tower_kit")=={"name":"水塔","ingredients":{"plank":6,"copper_joint":2,"stone":6},"yield":1},"craft recipe plank 6 / copper_joint 2 / stone 6 -> 1")
	expect(World.BUILD.get("water_tower")=={"name":"水塔","water_tower_kit":1} and World.NAMES.get("water_tower_kit")=="水塔","build entry and item name")
	expect(Industry.TOWER_KIND=="water_tower" and Industry.TOWER_KIT=="water_tower_kit" and Industry.TOWER_CAPACITY==96 and Industry.TOWER_ACTION=="tower_toggle","tower constants")
	expect(Industry.TOWER_LOCKED=="完成蘭陽回訪的旱日分流後，家園工坊才會開放水塔。先到宜蘭水圳找星禾。" and Industry.TOWER_NOT_OWNER=="只能切換自己的水塔","tower messages")
	expect(Industry.tower_enabled_name(true)=="出水" and Industry.tower_enabled_name(false)=="只蓄水","enabled names")
	expect("water_tower" in Industry.NETWORK and int(Industry.LIMITS.get("water_tower",0))==4,"tower joins the water network; limit 4 per region")
	expect("water_tower" in World.UNDO_SOLID and "water_tower" in preload("res://scripts/house_rooms.gd").SOLID_OBJECTS,"tower is solid like water_tank")
	expect(World.trade_items().has("water_tower_kit")==World.trade_items().has(Industry.GATE_KIT),"tower kit trade rule follows the gate kit")
	expect("water_tower_kit" in preload("res://scripts/life_ui_panels.gd").BUILD_MATERIALS and preload("res://scripts/automation_ui.gd").GUIDE.has("water_tower_kit"),"kit listed in the 生活 build materials and workbench guide")
	var none:=Industry.tower_report({"objects":{}},"1,1")
	expect(none.ok==false and none.consumers==[] and int(none.water)==0,"tower_report on a missing tower")
	expect(Industry.network_info({"objects":{}},"1,1").get("towers")==0,"network_info default carries tower keys")

# -------------------------------------------------- tower-free plan unchanged --

func gate_layout(mode:String) -> World:
	# Same shape as test_diversion_gate (far sprinkler first) plus a second network.
	var w:=f_world([f_spr(0),f_pipe(),f_gate(mode),f_spr(0),f_pipe(),f_tank(0),f_pipe(),{"type":"water_pump","owner":OWNER,"items":{},"enabled":true}],24,46)
	w.state.objects["30,40"]=f_tank(20)
	w.state.objects["31,40"]={"type":"waterworks","owner":OWNER,"items":{},"enabled":true,"water":0,"input":{}}
	w.state.objects["32,40"]=f_tank(5)
	w.state.objects["33,40"]={"type":"medium_sprinkler","owner":OWNER,"items":{},"water":3,"enabled":true,"next_water":0.0,"last_water":-1.0}
	return w

func check_tower_free_identical() -> void:
	var cases:=[[0,0,0,true],[10,0,0,false],[16,2,0,false],[48,12,5,true],[30,11,12,false],[1,0,11,true]]
	for mode in ["open","low","closed"]:
		var w:=gate_layout(mode)
		for v:Array in cases:
			w.state.objects[c(51,24)].water=int(v[0])
			w.state.objects[c(49,24)].water=int(v[1])
			w.state.objects[c(46,24)].water=int(v[2])
			w.state.objects[c(53,24)].enabled=bool(v[3])
			expect(same(Industry.plan(w,8),pre_tower_plan(w,8)) and same(Industry.plan(w,12),pre_tower_plan(w,12)),"tower-free %s-gate network: plan == pre-tower plan for %s"%[mode,str(v)])
	# A tower network next to a tower-free one: the tower-free network is untouched.
	var mixed:=gate_layout("low")
	mixed.state.objects[c(51,24)].water=16
	mixed.state.objects["30,44"]=f_tank(30)
	mixed.state.objects["31,44"]=f_tower(0)
	mixed.state.objects["32,44"]=f_spr(0)
	var now:=Industry.plan(mixed,8)
	var old:=pre_tower_plan(mixed,8)
	var free_now:={}
	var free_old:={}
	for key in now:
		if key.ends_with(",24") or key.ends_with(",40"):free_now[key]=now[key]
	for key in old:
		if key.ends_with(",24") or key.ends_with(",40"):free_old[key]=old[key]
	expect(same(free_now,free_old) and not free_now.is_empty(),"tower-free networks unchanged beside a tower network (%s vs %s)"%[str(free_now),str(free_old)])
	expect(same(now,free_now.merged({"30,44":0,"32,44":12,"31,44":18})),"the tower network beside it: sprinkler 12, tower 18 (%s)"%str(now))

# --------------------------------------------------------- plan() fixtures --

## Row y=40: TW_F S1 TANK PIPE G(low) TW_L S2 G(closed) TW_C S3 (x = 20..29).
func zone_row(tank:int,tw_f:int,tw_l:int,tw_c:int,s:int,en_f:=true,en_c:=true) -> World:
	return f_world([f_tower(tw_f,en_f),f_spr(s),f_tank(tank),f_pipe(),f_gate("low"),f_tower(tw_l),f_spr(s),f_gate("closed"),f_tower(tw_c,en_c),f_spr(s)],40)

func check_plan_fixtures() -> void:
	var TF:=c(20,40);var S1:=c(21,40);var T:=c(22,40);var TL:=c(25,40);var S2:=c(26,40);var TC:=c(28,40);var S3:=c(29,40)
	var w:=zone_row(30,0,0,0,0)
	var zones:=Industry.tower_refill_zones(w.state.objects,Industry.components(w.state)[0])
	expect(zones.get(TF)=="full" and zones.get(TL)=="low" and zones.get(TC)=="cut","tower refill zones full/low/cut (%s)"%str(zones))
	plan_is(w,{T:0,S1:12,S2:12,TF:6},"leftover only: sprinklers (full then low) first, the full-zone tower gets the 6 left, low tower none")
	plan_is(zone_row(30,0,0,0,0,false),{T:0,S1:12,S2:12,TF:6},"a 只蓄水 (disabled) tower still refills")
	plan_is(zone_row(40,90,0,20,0),{T:0,S1:12,S2:12,TF:96,TL:10,TC:8,S3:12},"full-zone tower tops up first (+6), low-zone tower gets the rest (+10); cut tower discharges its own 20 into S3")
	plan_is(zone_row(48,96,90,0,12),{T:42,TL:96},"cut-zone tower gets nothing even with 42 left in the tank")
	plan_is(zone_row(40,90,0,20,0,true,false),{T:0,S1:12,S2:12,TF:96,TL:10},"disabled cut tower keeps its 20, S3 stays dry")
	plan_is(zone_row(0,50,50,0,0),{TF:38,S1:12,TL:38,S2:12},"each tower feeds only its open-gate zone: the low gate stops TF reaching S2, the closed gate stops TL reaching S3")
	plan_is(zone_row(0,50,50,0,0,false),{TL:38,S2:12},"disabled full-zone tower stores but does not discharge")
	var row:=zone_row(0,50,50,0,0)
	var report:=Industry.tower_report(row.state,TL)
	expect(report.ok and int(report.water)==50 and int(report.capacity)==96 and report.enabled==true and report.refill_zone=="low" and int(report.tanks)==1 and same(report.consumers,[{"key":S2,"type":"sprinkler"}]),"tower_report for the low-zone tower (%s)"%str(report))
	var gate_rep:=Industry.zone_report(row.state,c(24,40))
	expect(gate_rep.ok and same(gate_rep.towers,[{"key":TF,"zone":"full"},{"key":TL,"zone":"low"},{"key":TC,"zone":"cut"}]),"zone_report lists the network's towers with their refill zones (%s)"%str(gate_rep.towers))
	# Scarce water behind a low gate: TANK SN G(low) TW SF (y=42).
	var scarce:=f_world([f_tank(16),f_spr(0),f_gate("low"),f_tower(10),f_spr(0)],42)
	var plan:=plan_is(scarce,{c(20,42):0,c(21,42):12,c(24,42):12,c(23,42):2},"low gate, 16 tank water: tower covers the far shortfall (4 from the tank + 8 from the tower)")
	var no_tower:=f_world([f_tank(16),f_spr(0),f_gate("low"),f_pipe(),f_spr(0)],42)
	plan_is(no_tower,{c(20,42):0,c(21,42):12,c(24,42):4},"same layout without a tower: the far sprinkler only gets 4")
	scarce.state.next_network_check=float(scarce.state.time)
	scarce.step(1.0,true)
	var applied:={}
	for key in plan:applied[key]=int(scarce.state.objects[key].water)
	expect(same(applied,plan),"real World.step writes the tower plan (%s)"%str(applied))
	# Tower-only networks (no tank): TW G S (y=44).
	for mode in ["open","low","closed"]:
		var only:=f_world([f_tower(20),f_gate(mode),f_spr(0)],44)
		plan_is(only,{c(20,44):8,c(22,44):12} if mode=="open" else {},"tower-only network through a %s gate"%mode)
		var rep:=Industry.tower_report(only.state,c(20,44))
		expect(rep.ok and rep.refill_zone=="none" and int(rep.tanks)==0 and rep.consumers.size()==(1 if mode=="open" else 0),"tower_report without a tank (%s): %s"%[mode,str(rep)])
	plan_is(f_world([f_tower(20),f_pipe(),f_spr(0),{"type":"waterworks","owner":OWNER,"items":{},"enabled":true,"water":0,"input":{}}],46),{c(20,46):0,c(22,46):12,c(23,46):8},"tower-only network discharges into a sprinkler then a waterworks")
	plan_is(f_world([f_tower(50),f_tank(0),f_tower(0)],48),{},"towers never feed a tank or another tower")
	# Pump input still goes only to tanks; the tower then takes the tank's leftover.
	var pumped:=f_world([f_spr(12),f_tower(0),f_tank(40),f_pipe(),{"type":"water_pump","owner":OWNER,"items":{},"enabled":true}],24,49)
	plan_is(pumped,{c(51,24):0,c(50,24):48},"pump fills the tank (+8), the tank leftover refills the tower",8)
	var network:=Industry.network_info(pumped.state,c(50,24))
	expect(int(network.towers)==1 and int(network.tower_water)==0 and int(network.tower_capacity)==96 and int(network.connected_tanks)==1 and int(network.water)==40,"network_info tower keys (%s)"%str(network))

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
	inv["plank"]=32
	inv["copper_joint"]=11
	inv["stone"]=32
	refuse(w,OWNER,"craft",BENCH,"water_tower_kit",Industry.TOWER_LOCKED,"craft before the Lanyang revisit")
	refuse(w,OWNER,"craft",BENCH,"water_tower_kit|chest:1,1",Industry.TOWER_LOCKED,"sourced craft before the Lanyang revisit")
	write_revisit_fixture(w)
	expect(validates(w.state),"disclosed revisit fixture validates")
	var before:=inv.duplicate()
	ok(w,OWNER,"craft",BENCH,"water_tower_kit","craft tower kit 1")
	expect(int(inv.plank)==int(before.plank)-6 and int(inv.copper_joint)==int(before.copper_joint)-2 and int(inv.stone)==int(before.stone)-6 and int(inv.get("water_tower_kit",0))==1,"one craft debits exactly plank 6 / copper_joint 2 / stone 6")
	for i in 4:ok(w,OWNER,"craft",BENCH,"water_tower_kit","craft tower kit %d"%(i+2))
	ok(w,OWNER,"craft",BENCH,"diversion_gate_kit","craft the gate kit")
	expect(int(inv.get("water_tower_kit",0))==5 and int(inv.plank)==0 and int(inv.copper_joint)==0 and int(inv.stone)==0,"five tower kits + one gate kit use every plank, copper joint and stone")
	inv["sprinkler_kit"]=2
	inv["pipe_kit"]=2
	inv["tank_kit"]=1
	inv["pump_kit"]=1
	ok(w,OWNER,"build",FAR_S,"sprinkler","far sprinkler")
	refuse(w,OWNER,"build",BENCH,"water_tower","這格有東西，請選空地","tower on the occupied bench cell")
	ok(w,OWNER,"build",TOWER,"water_tower","the water tower")
	expect(same(obj(w,TOWER),{"type":"water_tower","owner":OWNER,"items":{},"water":0,"enabled":true}),"new tower: water 0, enabled, standard object shape (%s)"%str(obj(w,TOWER)))
	expect(w.blocked(TOWER) and not w.can_stand(Vector2(TOWER)+Vector2(0.5,0.5)),"tower tile blocks walking")
	ok(w,OWNER,"build",GATE,"diversion_gate","the diversion gate")
	ok(w,OWNER,"build",NEAR_S,"sprinkler","near sprinkler")
	ok(w,OWNER,"build",PIPE_B,"water_pipe","pipe B")
	ok(w,OWNER,"build",TANK,"water_tank","tank")
	ok(w,OWNER,"build",PIPE_C,"water_pipe","pipe C")
	ok(w,OWNER,"build",PUMP,"water_pump","river pump")
	var main_group:Dictionary={}
	for g in Industry.components(w.state):
		if k(TOWER) in g["keys"]:main_group=g
	expect(main_group.get("keys",[]).size()==8 and main_group.get("sprinklers",[])==[k(FAR_S),k(NEAR_S)],"one connected network through the tower")
	# Limit: 4 towers per owner per region.
	for cell:Vector2i in EXTRA_TOWERS:ok(w,OWNER,"build",cell,"water_tower","extra tower %s"%k(cell))
	expect(int(inv.get("water_tower_kit",0))==1,"one kit left for the fifth tower")
	refuse(w,OWNER,"build",FIFTH_TOWER,"water_tower","已達此設備的每人放置上限","fifth tower in the region")
	for cell:Vector2i in EXTRA_TOWERS:ok(w,OWNER,"remove",cell,"","remove extra tower %s"%k(cell))
	expect(int(inv.get("water_tower_kit",0))==4,"removing returns each kit (4 in the bag)")
	# tower_toggle rejections and the owner's toggle.
	refuse(w,OTHER,Industry.TOWER_ACTION,TOWER,"",Industry.TOWER_NOT_OWNER,"another player's tower")
	refuse(w,OWNER,Industry.TOWER_ACTION,PIPE_B,"",Industry.TOWER_NOT_OWNER,"tower_toggle on a pipe")
	refuse(w,OWNER,Industry.TOWER_ACTION,Vector2i(45,22),"",Industry.TOWER_NOT_OWNER,"tower_toggle on an empty cell")
	var owner_person:Dictionary=w.state.players[OWNER]
	owner_person.x=TOWER.x+0.5
	owner_person.y=TOWER.y+6.5
	refuse(w,OWNER,Industry.TOWER_ACTION,TOWER,"","靠近一點，才能和它互動","tower_toggle from six tiles away",false)
	var off:=ok(w,OWNER,Industry.TOWER_ACTION,TOWER,"","owner sets 只蓄水")
	expect(str(off.message)=="水塔已設為「只蓄水」" and obj(w,TOWER).enabled==false,"toggle off message and flag")
	var on:=ok(w,OWNER,Industry.TOWER_ACTION,TOWER,"","owner sets 出水")
	expect(str(on.message)=="水塔已設為「出水」" and obj(w,TOWER).enabled==true,"toggle on message and flag")
	# Crops: near plots seeded now; far plots only hoed (seeded when the gate closes).
	for cell:Vector2i in NEAR_CROPS+FAR_CROPS:ok(w,OWNER,"hoe",cell,"","hoe %s"%k(cell))
	for cell:Vector2i in NEAR_CROPS:
		w.state.players[OWNER].inventory["radish_seed"]=5
		ok(w,OWNER,"seed",cell,"radish","seed radish %s"%k(cell))
	return true

# ------------------------------------------------- tower fill (real step) --

func check_fill(w:World) -> bool:
	for cell:Vector2i in [NEAR_S,FAR_S]:ok(w,OWNER,"toggle_sprinkler",cell,"","enable sprinkler %s"%k(cell))
	ok(w,OWNER,"refill_tank",TANK,"","fill the tank")
	var plan:=Industry.plan(w)
	expect(same(plan,{k(TANK):0,k(FAR_S):12,k(NEAR_S):12,k(TOWER):24}),"open gate, pump off: both sprinklers 12, the tower takes the 24 left (%s)"%str(plan))
	w.state.next_network_check=float(w.state.time)
	w.step(1.0,true)
	expect(int(obj(w,TOWER).water)==24 and int(obj(w,TANK).water)==0 and int(obj(w,FAR_S).water)==12,"real step: tower 24, tank 0, far sprinkler 12 (tower %d)"%int(obj(w,TOWER).water))
	var closed:=ok(w,OWNER,"gate_mode",GATE,"closed","close the gate")
	expect(str(closed.message).contains("關閉"),"gate closed")
	ok(w,OWNER,"toggle_pump",PUMP,"","switch the river pump on")
	for cell:Vector2i in FAR_CROPS:
		w.state.players[OWNER].inventory["radish_seed"]=5
		ok(w,OWNER,"seed",cell,"radish","seed far radish %s"%k(cell))
	var report:=Industry.tower_report(w.state,k(TOWER))
	expect(report.ok and report.refill_zone=="cut" and int(report.water)==24 and report.enabled==true and same(report.consumers,[{"key":k(FAR_S),"type":"sprinkler"}]),"tower_report behind the closed gate (%s)"%str(report))
	var gate_rep:=Industry.zone_report(w.state,k(GATE))
	return expect(same(gate_rep.get("towers"),[{"key":k(TOWER),"zone":"cut"}]),"zone_report: the tower is cut off from the tank (%s)"%str(gate_rep.get("towers")))

# ------------------------------------------- closed gate over several days --

static func far_reserve(x:World) -> int:
	return int(x.state.objects[World.key(FAR_S)].water)+int(x.state.objects[World.key(TOWER)].get("water",0))

func check_closed_gate_days(w:World,path:String) -> void:
	expect(w.save(),"save before the contrast copy")
	var plain:=World.new()
	if not expect(plain.load_world(path),"contrast copy loads"):return
	plain.save_path=""
	plain.state.objects[k(TOWER)]={"type":"water_pipe","owner":OWNER,"items":{}} # disclosed contrast
	var keep:=w.save_path
	w.save_path=""
	var worlds:={"tower":w,"plain":plain}
	var stats:={}
	for name in worlds:
		stats[name]={"used":0,"rounds":0,"rose":false,"fed":0,"dry":0,"bad":[],"empty_day":-1,"start":far_reserve(worlds[name])}
	expect(int(stats.tower.start)==36 and int(stats.plain.start)==12,"start: tower world far reserve 24+12, contrast 12")
	for day in DAYS:
		if day==10:
			for name in worlds:
				var x:World=worlds[name]
				for cell:Vector2i in FAR_CROPS:
					ok(x,OWNER,"harvest",cell,"","%s: harvest far radish %s"%[name,k(cell)])
					x.state.players[OWNER].inventory["radish_seed"]=5
					ok(x,OWNER,"seed",cell,"radish","%s: reseed far radish %s"%[name,k(cell)])
		for name in worlds:
			var x:World=worlds[name]
			var s:Dictionary=stats[name]
			var reserve_start:=far_reserve(x)
			for i in DAY_STEPS:
				var res:=far_reserve(x)
				var tw:=int(x.state.objects[k(TOWER)].get("water",0))
				x.step(DAY_DT,true)
				var res_after:=far_reserve(x)
				var tw_after:=int(x.state.objects[k(TOWER)].get("water",0))
				if res_after>res:s.rose=true
				s.used=int(s.used)+res-res_after
				if tw_after<tw:s.rounds=int(s.rounds)+1
				if tw_after>tw:s.rose=true
			var d:=int(Weather.day_index(x.state.time))
			var wet:bool=crop(x,FAR_CROPS[0]).get("wet")==true and crop(x,FAR_CROPS[1]).get("wet")==true
			if Weather.outdoor_id(d)!="rainy":
				if reserve_start>=4:
					if wet:s.fed=int(s.fed)+1
					else:s.bad.append("day %d dry with reserve %d"%[d,reserve_start])
				elif reserve_start==0:
					if wet:s.bad.append("day %d wet with no reserve"%d)
					else:s.dry=int(s.dry)+1
			if far_reserve(x)==0 and int(s.empty_day)<0:s.empty_day=d
		if day==10:
			var tower_growth:=float(crop(w,FAR_CROPS[0]).get("growth",0.0))
			var plain_growth:=float(crop(plain,FAR_CROPS[0]).get("growth",0.0))
			expect(tower_growth>0.0 and plain_growth==0.0,"reseeded far radish grows only where the tower still feeds the sprinkler (tower %s, contrast %s)"%[str(tower_growth),str(plain_growth)])
	w.save_path=keep
	var t:Dictionary=stats.tower
	var p:Dictionary=stats.plain
	expect(not t.rose and not p.rose,"no water ever reaches the far side through the closed gate (tower never refilled)")
	expect(int(t.used)==36 and far_reserve(w)==0,"tower world: the far sprinkler used exactly the tower's 24 + its own 12, then ran dry (used %d)"%int(t.used))
	expect(int(p.used)==12 and far_reserve(plain)==0,"contrast: only the sprinkler's own 12 (used %d)"%int(p.used))
	expect(int(t.rounds)>=3,"tower refilled the far sprinkler over several rounds (%d)"%int(t.rounds))
	expect(t.bad.is_empty() and p.bad.is_empty(),"far crops watered exactly while water remains (tower %s, contrast %s)"%[str(t.bad),str(p.bad)])
	expect(int(t.fed)>=int(p.fed)+8,"tower keeps far crops watered on many more dry days (tower %d, contrast %d)"%[int(t.fed),int(p.fed)])
	expect(int(t.empty_day)>int(p.empty_day) and int(p.empty_day)>=0,"the tower world runs dry later (day %d vs %d)"%[int(t.empty_day),int(p.empty_day)])
	expect(int(t.dry)>=2 and int(p.dry)>=2,"once dry, far crops stay dry on non-rainy days (tower %d, contrast %d)"%[int(t.dry),int(p.dry)])
	expect(int(obj(w,TANK).water)>0 or int(obj(w,NEAR_S).water)>0,"near side kept its pump/tank water meanwhile")

# ------------------------------------------------------------------- saves --

func check_save(w:World,path:String) -> void:
	expect(w.save(),"world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"fresh World reloads")
	expect(same(reloaded.state.objects,w.state.objects) and same(reloaded.state.crops,w.state.crops),"objects and crops equal after reload")
	var tw:Dictionary=reloaded.state.objects.get(k(TOWER),{})
	expect(tw.get("type")=="water_tower" and int(tw.get("water",-1))==int(obj(w,TOWER).water) and tw.get("enabled")==true,"tower water and enabled survive reload")
	expect(same(Industry.plan(reloaded),Industry.plan(w)),"plan after reload identical")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"saved world validates"):return
	var fixture:=temp_path("fixture")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["water 97","water -1","water 2.5","water text","water missing","enabled int","enabled missing","extra field","tower holds items","five towers for one owner","tower without the completed revisit","kit in the bag without the revisit","kit in a chest without the revisit","tower in Lanyang without the revisit"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	# Controls.
	var four:Dictionary=base.duplicate(true)
	for cell:Vector2i in EXTRA_TOWERS:four.objects[k(cell)]={"type":"water_tower","owner":OWNER,"items":{},"water":96,"enabled":false}
	expect(validates(four),"control: four towers (water 96, disabled) validate")
	var stripped:=without_revisit(base)
	expect(validates(stripped),"control: no revisit, no gate/tower objects, no tower kits validates")
	var chest:=stripped.duplicate(true)
	chest.objects["40,40"]={"type":"chest","owner":OWNER,"items":{"wood":1}}
	expect(validates(chest),"control: a chest without the kit validates")
	var old:Dictionary=base.duplicate(true)
	old.objects.erase(k(TOWER))
	old.players[OWNER].inventory.erase("water_tower_kit")
	expect(validates(old) and write_json(fixture,old) and probe.load_world(fixture),"old save without any tower loads")

## Base without the revisit record and without everything that needs it.
func without_revisit(base:Dictionary) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.erase(Revisit.STATE_KEY)
	for key in s.objects.keys():
		if s.objects[key].get("type") in ["diversion_gate","water_tower"]:s.objects.erase(key)
	s.players[OWNER].inventory.erase("water_tower_kit")
	return s

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var g:Dictionary=s.objects[k(TOWER)]
	match label:
		"water 97":g.water=97
		"water -1":g.water=-1
		"water 2.5":g.water=2.5
		"water text":g.water="5"
		"water missing":g.erase("water")
		"enabled int":g.enabled=1
		"enabled missing":g.erase("enabled")
		"extra field":g.mode="open"
		"tower holds items":g.items={"wood":1}
		"five towers for one owner":
			for cell:Vector2i in EXTRA_TOWERS+[FIFTH_TOWER]:s.objects[k(cell)]={"type":"water_tower","owner":OWNER,"items":{},"water":0,"enabled":true}
		"tower without the completed revisit":
			s=without_revisit(base)
			s.objects[k(TOWER)]={"type":"water_tower","owner":OWNER,"items":{},"water":0,"enabled":true}
		"kit in the bag without the revisit":
			s=without_revisit(base)
			s.players[OWNER].inventory["water_tower_kit"]=1
		"kit in a chest without the revisit":
			s=without_revisit(base)
			s.objects["40,40"]={"type":"chest","owner":OWNER,"items":{"water_tower_kit":1}}
		"tower in Lanyang without the revisit":
			s=without_revisit(base)
			s.regions.lanyang.objects["30,30"]={"type":"water_tower","owner":OWNER,"items":{},"water":0,"enabled":true}
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
	var shown:Dictionary=public.objects.get(k(TOWER),{})
	expect(shown.get("type")=="water_tower" and int(shown.get("water",-1))==int(obj(w,TOWER).water) and shown.get("enabled")==true and not JSON.stringify(public).contains(OWNER),"public snapshot carries tower water and enabled, no raw owner token")
	expect(same(Industry.tower_report(public,k(TOWER)),Industry.tower_report(w.state,k(TOWER))),"tower_report on the client snapshot matches the server")
	session.world=null
	session.queue_free()
	w.save_path=keep

# ----------------------------------------------------- undo / move / remove --

func check_undo_move_remove(w:World) -> void:
	var inv:Dictionary=w.state.players[OWNER].inventory
	var kits:=int(inv.get("water_tower_kit",0))
	var spot:=Vector2i(51,26)
	ok(w,OWNER,"build",spot,"water_tower","build a tower to undo")
	var summary:=w.undo_summary(OWNER)
	expect(summary.available==true,"undo is available for the new tower (%s)"%str(summary.reason))
	ok(w,OWNER,"undo_build",spot,str(summary.id),"undo the tower build")
	inv=w.state.players[OWNER].inventory # undo installs a fresh inventory dictionary
	expect(not w.state.objects.has(k(spot)) and int(inv.get("water_tower_kit",0))==kits,"undo removed the tower and returned the kit")
	# Give the tower some stored water through a real tick: reopen the gate.
	ok(w,OWNER,"gate_mode",GATE,"open","reopen the gate")
	ok(w,OWNER,"refill_tank",TANK,"","refill the tank")
	w.state.next_network_check=float(w.state.time)
	w.step(1.0,true)
	var stored:=int(obj(w,TOWER).water)
	expect(stored>0,"tower refilled again once the gate is open (%d)"%stored)
	refuse(w,OTHER,"move_object",TOWER,"48,26","","another player cannot move the tower")
	var person:Dictionary=w.state.players[OWNER]
	person.x=46.5
	person.y=26.5
	var moved:=act(w,OWNER,"move_object",TOWER,"48,26")
	expect(bool(moved.get("ok",false)),"owner moves the tower (%s)"%str(moved.get("message","")))
	var at:Dictionary=obj(w,Vector2i(48,26))
	expect(not w.state.objects.has(k(TOWER)) and at.get("type")=="water_tower" and int(at.get("water",-1))==stored and at.get("enabled")==true,"moved tower keeps its water and setting")
	expect(w.blocked(Vector2i(48,26)) and not w.blocked(TOWER),"collision moves with the tower")
	ok(w,OWNER,"remove",Vector2i(48,26),"","owner removes the tower")
	inv=w.state.players[OWNER].inventory
	expect(not w.state.objects.has("48,26") and int(inv.get("water_tower_kit",0))==kits+1,"removal returns the kit (stored water is discarded, like water_tank)")
	expect(validates(w.state),"final world validates")
