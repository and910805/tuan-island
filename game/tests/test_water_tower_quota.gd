extends SceneTree
## 第 40 章「定量分區配水」：水塔的 reserve（桶水保留）與 quota（每日配水）規則測試
## (industry.gd TOWER_RESERVES / TOWER_QUOTAS / tower_day / tower_reserve / tower_quota /
## tower_quota_used / tower_set_apply / tower_set_message / plan_detail / tower_report,
## World tower_set action, World.step quota write-back, save_schema water tower block).
## Headless World-level, real World.step time.
##
## EARNED through real World.act: every build (sprinklers, tower, pipes, tank, pump), every
## tower_set (reserve / quota, accepted and refused), toggle_pump, toggle_sprinkler,
## move_object and remove of the tower and the re-placed tower. Tank, tower and sprinkler
## water in the two real worlds come only from real World.step ticks (pump inflow, tower
## refill, tower discharge); in the real worlds quota_day / quota_used are written only by
## the tower_set action and World.step.
## WRITTEN DIRECTLY (disclosed): player x/y (standing spots), the device kits in the bag
## (sprinkler/tower/pipe/tank/pump kits), state.removed on the two river-side tiles whose
## base resource would block building, next_network_check (= now, so the first step runs a
## network tick), the completed Lanyang revisit fixture (same as test_water_tower; earned
## path is covered in test_lanyang_revisit), every object of the pure plan()/plan_detail()
## fixture worlds (tank/tower/sprinkler/waterworks water, gate modes, tower enabled flags,
## reserve/quota/quota_day/quota_used fields, state.time of those fixture worlds), the
## plain dictionaries handed to the pure helpers, and the tampered / control saves.
const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const OWNER:="quota-owner-token-8b2e"
const OTHER:="quota-other-token-41fa"
const S_A:=Vector2i(46,21)
const TOWER:=Vector2i(47,21)
const S_B:=Vector2i(48,21)
const S_C:=Vector2i(49,21)
const PIPE_B:=Vector2i(50,21)
const TANK:=Vector2i(51,21)
const PIPE_C:=Vector2i(52,21)
const PUMP:=Vector2i(53,21)
const SPRS:=[S_A,S_B,S_C]
const MOVED:=Vector2i(50,24)
const DAY_DT:=96.0
const SET:="tower_set"
const BAD_EXTRAS:=["quota:04","quota:-4","reserve:12:1","water:5","","reserve","quota","reserve:","quota:",":12","reserve:abc","reserve:12.0","quota:8.0","reserve: 12","quota:8 ","Reserve:12","QUOTA:8","reserve:13","reserve:-12","reserve:60","reserve:-0","quota:5","quota:32","quota:+4","quota:-0","reserve:1e1","quota:0x8","reserve:012","enabled:1","reserve=12","reserve:12,quota:8"]

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
	check_constants()
	check_helpers()
	check_set_apply()
	check_messages_and_report()
	check_identity()
	check_reserve_fixtures()
	check_quota_fixtures()
	var path:=temp_path("main")
	var w:=World.new()
	w.save_path=path
	if build_world(w,"main"):
		check_act_settings(w)
		var plain:=World.new()
		plain.save_path=temp_path("contrast")
		if build_world(plain,"contrast"):
			check_reserve_ticks(w,plain)
		check_quota_days(w,path)
		check_move_remove(w)
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("WATER_TOWER_QUOTA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("water-tower-quota-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

func k(p:Vector2i) -> String:
	return World.key(p)

func c(x:int,y:int) -> String:
	return k(Vector2i(x,y))

func near(w:World,token:String,tile:Vector2i) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]="home"
	p["x"]=tile.x+0.5
	p["y"]=tile.y+2.5

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"quota-req-%d"%serial,action,p,extra)

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

func obj(w:World,p:Vector2i) -> Dictionary:
	return w.state.objects.get(k(p),{})

func tw(w:World) -> Dictionary:
	return obj(w,TOWER)

func wat(w:World,p:Vector2i) -> int:
	return int(obj(w,p).get("water",-1))

func wkey(w:World,key:String) -> int:
	return int(w.state.objects.get(key,{}).get("water",-1))

func spr_total(w:World) -> int:
	var total:=0
	for cell:Vector2i in SPRS:total+=wat(w,cell)
	return total

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

# ------------------------------------------- pre-setting plan (reconstructed) --
# Reconstruction of INDUSTRY.plan as it was before reserve/quota existed (tower round
# with no allowance and no daily limit); used to prove a tower without settings is
# planned exactly as before.

static func pre_setting_plan(world,pump_rate:int) -> Dictionary:
	var objects:Dictionary=world.state.objects
	var water:Dictionary={}
	for group in Industry.components(world.state):
		var tanks:Array=group.tanks
		var towers:Array=Industry._towers(objects,group)
		if tanks.is_empty() and towers.is_empty():continue
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
		if towers.is_empty():continue
		var zones:Dictionary=Industry.tower_refill_zones(objects,group)
		for tower in towers:water[tower]=int(objects[tower].get("water",0))
		for zone in [Industry.ZONE_FULL,Industry.ZONE_LOW]:
			for tower in towers:
				if zones[tower]!=zone:continue
				for tank in tanks:
					var room:=Industry.TOWER_CAPACITY-int(water[tower])
					if room<=0:break
					var amount:=mini(int(water[tank]),room)
					if amount<=0:continue
					water[tank]=int(water[tank])-amount
					water[tower]=int(water[tower])+amount
		for tower in towers:
			if objects[tower].get("enabled",false)!=true:continue
			for consumer in Industry.tower_consumers(objects,group,tower):
				if int(water[tower])<=0:break
				var device:Dictionary=objects[consumer]
				if not device.enabled:continue
				var capacity:int=world.WATERWORKS.CAPACITY if device.type=="waterworks" else Industry.SPRINKLER_CAPACITIES[device.type]
				var current:=int(water.get(consumer,device.water))
				var amount:=mini(int(water[tower]),capacity-current)
				if amount<=0:continue
				water[tower]=int(water[tower])-amount
				water[consumer]=current+amount
	for key in water.keys():
		if int(water[key])==int(objects[key].water):water.erase(key)
	return water

# ---------------------------------------------------------- fixture objects --

func f_tank(water:int) -> Dictionary:
	return {"type":"water_tank","owner":OWNER,"items":{},"water":water}

func f_tower(water:int,enabled:=true,settings:Dictionary={}) -> Dictionary:
	var t:={"type":"water_tower","owner":OWNER,"items":{},"water":water,"enabled":enabled}
	t.merge(settings,true)
	return t

func f_spr(water:int,enabled:=true) -> Dictionary:
	return {"type":"sprinkler","owner":OWNER,"items":{},"water":water,"enabled":enabled,"next_water":0.0,"last_water":-1.0}

func f_ww(water:int) -> Dictionary:
	return {"type":"waterworks","owner":OWNER,"items":{},"enabled":true,"water":water,"input":{}}

func f_pipe() -> Dictionary:
	return {"type":"water_pipe","owner":OWNER,"items":{}}

func f_gate(mode:String) -> Dictionary:
	return {"type":"diversion_gate","owner":OWNER,"items":{},"mode":mode}

func f_pump() -> Dictionary:
	return {"type":"water_pump","owner":OWNER,"items":{},"enabled":true}

func rs(reserve:int) -> Dictionary:
	return {} if reserve==0 else {"reserve":reserve}

func qs(quota:int,day:int=0,used:int=0) -> Dictionary:
	return {"quota":quota,"quota_day":day,"quota_used":used}

func f_world(row:Array,y:int,x0:int=20) -> World:
	var w:=World.new()
	w.add_player(OWNER,"Owner")
	for i in row.size():
		w.state.objects[k(Vector2i(x0+i,y))]=row[i]
	return w

## plan_detail() water equals `expected` and its quota equals `quota`; plan() equals
## plan_detail().water; stored water is conserved (+pump_in); planning mutates nothing.
func plan_is(w:World,expected:Dictionary,label:String,quota:Dictionary={},pump_in:int=0) -> Dictionary:
	var before:=var_to_bytes(canon(w.state))
	var detail:=Industry.plan_detail(w)
	var water:Dictionary=detail.get("water",{})
	var got_quota:Dictionary=detail.get("quota",{})
	expect(same(water,expected),"%s: plan %s (expected %s)"%[label,str(water),str(expected)])
	expect(same(got_quota,quota),"%s: quota %s (expected %s)"%[label,str(got_quota),str(quota)])
	expect(same(Industry.plan(w),water),"%s: plan() == plan_detail().water"%label)
	expect(water_total(w,water)==water_total(w)+pump_in,"%s: water conserved (before %d, after %d, pump %d)"%[label,water_total(w),water_total(w,water),pump_in])
	expect(var_to_bytes(canon(w.state))==before,"%s: planning leaves the world untouched"%label)
	return water

# --------------------------------------------------------------- constants --

func check_constants() -> void:
	expect(Industry.TOWER_RESERVES==[0,12,24,36,48],"TOWER_RESERVES = [0,12,24,36,48]")
	expect(Industry.TOWER_QUOTAS==[0,4,8,16,24],"TOWER_QUOTAS = [0,4,8,16,24]")
	expect(Industry.TOWER_QUOTA_MAX==24 and is_equal_approx(Industry.TOWER_DAY,1440.0),"TOWER_QUOTA_MAX 24, TOWER_DAY 1440")
	expect(Industry.TOWER_SET_ACTION=="tower_set" and SET==Industry.TOWER_SET_ACTION,"TOWER_SET_ACTION is tower_set")
	expect(Industry.TOWER_BAD_SETTING=="水塔設定只能選面板上的數值","TOWER_BAD_SETTING text")
	expect(Industry.TOWER_SAME_SETTING=="水塔已經是這個設定了","TOWER_SAME_SETTING text")
	expect(Industry.TOWER_NOT_OWNER=="只能切換自己的水塔","TOWER_NOT_OWNER text")
	var days:=[[0.0,0],[1.0,0],[1439.0,0],[1439.999,0],[1440.0,1],[1440.5,1],[2879.9,1],[2880.0,2],[4320.0,3],[100000.0,69]]
	for d:Array in days:
		expect(Industry.tower_day(float(d[0]))==int(d[1]),"tower_day(%s) == %d (got %d)"%[str(d[0]),int(d[1]),Industry.tower_day(float(d[0]))])

# ------------------------------------------------------------ pure helpers --

func check_helpers() -> void:
	for r in [12,24,36,48]:
		expect(Industry.tower_reserve({"reserve":r})==r,"tower_reserve %d"%r)
		expect(Industry.tower_reserve({"reserve":float(r)})==r,"tower_reserve accepts the JSON float %d.0"%r)
	var bad_reserves:=[{},{"reserve":0},{"reserve":"12"},{"reserve":12.5},{"reserve":13},{"reserve":-12},{"reserve":60},{"reserve":null},{"reserve":true},{"reserve":[12]},{"reserve":{"v":12}},{"reserve":4},{"quota":12}]
	for t:Dictionary in bad_reserves:
		expect(Industry.tower_reserve(t)==0,"tower_reserve of %s is 0"%str(t))
	for q in [4,8,16,24]:
		expect(Industry.tower_quota({"quota":q})==q,"tower_quota %d"%q)
		expect(Industry.tower_quota({"quota":float(q)})==q,"tower_quota accepts the JSON float %d.0"%q)
	var bad_quotas:=[{},{"quota":0},{"quota":"8"},{"quota":8.5},{"quota":5},{"quota":-8},{"quota":32},{"quota":12},{"quota":null},{"quota":false},{"quota":[8]},{"reserve":8}]
	for t:Dictionary in bad_quotas:
		expect(Industry.tower_quota(t)==0,"tower_quota of %s is 0"%str(t))
	# tower_quota_used across days.
	var t8:=qs(8,3,5)
	expect(Industry.tower_quota_used(t8,3)==5,"quota_used on the record's day")
	expect(Industry.tower_quota_used(t8,4)==0,"quota_used on the next day counts 0")
	expect(Industry.tower_quota_used(t8,2)==0,"quota_used on another (earlier) day counts 0")
	expect(Industry.tower_quota_used(t8,30)==0,"quota_used many days later counts 0")
	expect(Industry.tower_quota_used({"quota_day":3,"quota_used":5},3)==0,"no quota: used is 0 even with day/used fields")
	expect(Industry.tower_quota_used({"quota":5,"quota_day":3,"quota_used":5},3)==0,"quota not in the list: used is 0")
	expect(Industry.tower_quota_used(qs(8,3,30),3)==24,"used clamps to TOWER_QUOTA_MAX")
	expect(Industry.tower_quota_used(qs(8,3,-3),3)==0,"negative used clamps to 0")
	expect(Industry.tower_quota_used(qs(4,3,8),3)==8,"used above a lowered quota is kept")
	expect(Industry.tower_quota_used({"quota":8,"quota_day":"3","quota_used":5},3)==0,"text quota_day counts 0")
	expect(Industry.tower_quota_used({"quota":8,"quota_day":3,"quota_used":"5"},3)==0,"text quota_used counts 0")
	expect(Industry.tower_quota_used({"quota":8,"quota_used":5},0)==0,"missing quota_day counts 0")
	expect(Industry.tower_quota_used({"quota":8,"quota_day":3},3)==0,"missing quota_used counts 0")
	expect(Industry.tower_quota_used({"quota":8.0,"quota_day":3.0,"quota_used":5.0},3)==5,"JSON floats count like ints")

# ------------------------------------------------------------ tower_set_apply --

func base_tower() -> Dictionary:
	return {"type":"water_tower","owner":OWNER,"items":{},"water":30,"enabled":true}

func apply_bad(t:Dictionary,extra:String,expected:String,day:int,label:String) -> void:
	var before:=var_to_bytes(t)
	var copy:=t.duplicate(true)
	var r:=Industry.tower_set_apply(t,extra,day)
	expect(r==expected,"%s: '%s' -> '%s' (got '%s')"%[label,extra,expected,r])
	expect(var_to_bytes(t)==before and same(t,copy),"%s: '%s' leaves the tower byte-identical"%[label,extra])

func check_set_apply() -> void:
	# Every valid reserve from a plain tower, then the same setting again.
	for r in [12,24,36,48]:
		var t:=base_tower()
		expect(Industry.tower_set_apply(t,"reserve:%d"%r,5)=="","reserve:%d applies"%r)
		expect(same(t,base_tower().merged({"reserve":r})),"reserve:%d stores only the reserve field (%s)"%[r,str(t)])
		apply_bad(t,"reserve:%d"%r,Industry.TOWER_SAME_SETTING,5,"same reserve %d"%r)
		expect(Industry.tower_set_apply(t,"reserve:0",5)=="" and same(t,base_tower()),"reserve:0 from %d erases the field"%r)
	# Every valid quota from a plain tower.
	for q in [4,8,16,24]:
		var t:=base_tower()
		expect(Industry.tower_set_apply(t,"quota:%d"%q,5)=="","quota:%d applies"%q)
		expect(same(t,base_tower().merged(qs(q,5,0))),"quota:%d stores quota/quota_day today/quota_used 0 (%s)"%[q,str(t)])
		apply_bad(t,"quota:%d"%q,Industry.TOWER_SAME_SETTING,5,"same quota %d"%q)
		expect(Industry.tower_set_apply(t,"quota:0",5)=="" and same(t,base_tower()),"quota:0 from %d erases all three fields"%q)
	# Switching between non-zero values.
	var chain:=base_tower()
	for r in [12,48,24,36,12]:
		expect(Industry.tower_set_apply(chain,"reserve:%d"%r,0)=="" and int(chain.get("reserve",0))==r,"reserve switches to %d"%r)
	apply_bad(base_tower(),"reserve:0",Industry.TOWER_SAME_SETTING,0,"reserve:0 on a plain tower")
	apply_bad(base_tower(),"quota:0",Industry.TOWER_SAME_SETTING,0,"quota:0 on a plain tower")
	# Settings are independent.
	var both:=base_tower()
	expect(Industry.tower_set_apply(both,"reserve:24",2)=="" and Industry.tower_set_apply(both,"quota:8",2)=="","reserve then quota both apply")
	expect(same(both,base_tower().merged({"reserve":24}).merged(qs(8,2,0))),"both settings stored (%s)"%str(both))
	expect(Industry.tower_set_apply(both,"quota:0",2)=="" and same(both,base_tower().merged({"reserve":24})),"quota:0 keeps the reserve")
	expect(Industry.tower_set_apply(both,"quota:16",2)=="" and Industry.tower_set_apply(both,"reserve:0",2)=="" and same(both,base_tower().merged(qs(16,2,0))),"reserve:0 keeps the quota")
	# Lowering the quota mid-day keeps what was already sent today.
	var mid:=base_tower().merged(qs(16,5,10))
	expect(Industry.tower_set_apply(mid,"quota:4",5)=="" and same(mid,base_tower().merged(qs(4,5,10))),"lowering 16 -> 4 on the same day keeps used 10 (%s)"%str(mid))
	expect(Industry.tower_set_apply(mid,"quota:24",5)=="" and same(mid,base_tower().merged(qs(24,5,10))),"raising 4 -> 24 on the same day keeps used 10")
	# 0 then back starts from 0.
	expect(Industry.tower_set_apply(mid,"quota:0",5)=="" and same(mid,base_tower()),"quota:0 erases the record")
	expect(Industry.tower_set_apply(mid,"quota:8",5)=="" and same(mid,base_tower().merged(qs(8,5,0))),"quota back to 8 counts from 0")
	# A record from a previous day counts as 0 when changing the quota.
	var old:=base_tower().merged(qs(8,3,8))
	expect(Industry.tower_set_apply(old,"quota:16",5)=="" and same(old,base_tower().merged(qs(16,5,0))),"previous-day record: day moves to today, used 0 (%s)"%str(old))
	var stale_same:=base_tower().merged(qs(8,3,8))
	apply_bad(stale_same,"quota:8",Industry.TOWER_SAME_SETTING,5,"same quota with a stale record")
	# Garbage existing fields: treated as no setting.
	var garbage:=base_tower().merged({"reserve":"24"})
	apply_bad(garbage,"reserve:0",Industry.TOWER_SAME_SETTING,0,"text reserve counts as no reserve")
	expect(Industry.tower_set_apply(garbage,"reserve:24",0)=="" and int(garbage.reserve)==24,"reserve:24 overwrites a text reserve")
	# Bad formats on a plain tower and on a tower with both settings.
	var configured:=base_tower().merged({"reserve":36}).merged(qs(16,5,7))
	for extra:String in BAD_EXTRAS:
		apply_bad(base_tower(),extra,Industry.TOWER_BAD_SETTING,5,"bad setting on a plain tower")
		apply_bad(configured,extra,Industry.TOWER_BAD_SETTING,5,"bad setting on a configured tower")

# ------------------------------------------------------ messages / report --

func check_messages_and_report() -> void:
	expect(Industry.tower_set_message("reserve:12")=="水塔已設為「儲水桶留 12 份」","message reserve 12")
	expect(Industry.tower_set_message("reserve:0")=="水塔已設為「不保留桶水」","message reserve 0")
	expect(Industry.tower_set_message("quota:8")=="水塔已設為「每日配水 8 份」","message quota 8")
	expect(Industry.tower_set_message("quota:0")=="水塔已設為「每日配水不限」","message quota 0")
	for r in [12,24,36,48]:
		expect(Industry.tower_set_message("reserve:%d"%r)=="水塔已設為「儲水桶留 %d 份」"%r,"message reserve %d"%r)
	for q in [4,8,16,24]:
		expect(Industry.tower_set_message("quota:%d"%q)=="水塔已設為「每日配水 %d 份」"%q,"message quota %d"%q)
	# tower_report settings fields.
	var w:=f_world([f_tank(10),f_tower(40,true,{"reserve":24}.merged(qs(8,0,3))),f_spr(0)],90)
	w.state.time=100.0
	var key:=c(21,90)
	var rep:=Industry.tower_report(w.state,key)
	expect(rep.ok and int(rep.reserve)==24 and int(rep.quota)==8 and int(rep.quota_used)==3 and int(rep.quota_left)==5,"tower_report: reserve 24, quota 8, used 3, left 5 (%s)"%str(rep))
	var next:=Industry.tower_report(w.state,key,1)
	expect(int(next.quota_used)==0 and int(next.quota_left)==8,"tower_report on the next day: used 0, left 8")
	w.state.time=1500.0
	var later:=Industry.tower_report(w.state,key)
	expect(int(later.quota_used)==0 and int(later.quota_left)==8,"tower_report day from snapshot time 1500 (day 1): used 0")
	w.state.objects[key]=f_tower(40,true,qs(4,0,8))
	w.state.time=10.0
	var over:=Industry.tower_report(w.state,key)
	expect(int(over.quota)==4 and int(over.quota_used)==8 and int(over.quota_left)==0,"tower_report: lowered quota, left clamps to 0 (%s)"%str(over))
	w.state.objects[key]=f_tower(40)
	var plain:=Industry.tower_report(w.state,key)
	expect(int(plain.reserve)==0 and int(plain.quota)==0 and int(plain.quota_used)==0 and int(plain.quota_left)==-1,"tower_report without settings: reserve 0, quota 0, left -1")
	var none:=Industry.tower_report({"objects":{}},"1,1")
	expect(none.ok==false and int(none.reserve)==0 and int(none.quota)==0 and int(none.quota_left)==-1,"tower_report on a missing tower carries the new keys")

# ---------------------------------------------------- no settings == before --

## Row y=40: TW_F S1 TANK PIPE G(low) TW_L S2 G(closed) TW_C S3 (x = 20..29).
func zone_row(tank:int,tw_f:int,tw_l:int,tw_c:int,s:int,en_f:=true,en_c:=true) -> World:
	return f_world([f_tower(tw_f,en_f),f_spr(s),f_tank(tank),f_pipe(),f_gate("low"),f_tower(tw_l),f_spr(s),f_gate("closed"),f_tower(tw_c,en_c),f_spr(s)],40)

func set_all_towers(w:World,settings:Dictionary) -> void:
	for key in w.state.objects:
		var o:Dictionary=w.state.objects[key]
		if o.get("type")=="water_tower":o.merge(settings,true)

func check_identity() -> void:
	var TF:=c(20,40);var S1:=c(21,40);var T:=c(22,40);var TL:=c(25,40);var S2:=c(26,40);var TC:=c(28,40);var S3:=c(29,40)
	# The chapter-40 tower numbers (test_water_tower) still hold with no settings.
	plan_is(zone_row(30,0,0,0,0),{T:0,S1:12,S2:12,TF:6},"no settings: leftover goes to the full-zone tower")
	plan_is(zone_row(40,90,0,20,0),{T:0,S1:12,S2:12,TF:96,TL:10,TC:8,S3:12},"no settings: full then low refill, cut tower discharges")
	plan_is(zone_row(48,96,90,0,12),{T:42,TL:96},"no settings: cut tower gets nothing")
	plan_is(zone_row(0,50,50,0,0),{TF:38,S1:12,TL:38,S2:12},"no settings: each tower feeds its open-gate zone")
	var cases:=[[30,0,0,0,0,true,true],[40,90,0,20,0,true,true],[48,96,90,0,12,true,true],[40,90,0,20,0,true,false],[0,50,50,0,0,true,true],[0,50,50,0,0,false,true],[25,10,5,30,3,true,true],[48,0,0,96,7,false,false],[12,95,1,0,11,true,true],[1,0,96,96,0,true,true]]
	var variants:=[{},{"reserve":0,"quota":0},{"reserve":"24","quota":"8","quota_day":0,"quota_used":0},{"reserve":13,"quota":5,"quota_day":0,"quota_used":2},{"reserve":12.5,"quota":-8}]
	for v:Array in cases:
		var w:=zone_row(int(v[0]),int(v[1]),int(v[2]),int(v[3]),int(v[4]),bool(v[5]),bool(v[6]))
		var reference:=pre_setting_plan(w,8)
		for settings:Dictionary in variants:
			set_all_towers(w,settings)
			var detail:=Industry.plan_detail(w)
			expect(same(detail.water,reference),"tower %s for %s: plan == pre-setting plan (%s vs %s)"%[str(settings),str(v),str(detail.water),str(reference)])
			expect(same(detail.quota,{}),"tower %s for %s: no quota entries"%[str(settings),str(v)])
	# Pumped network (pump rate 8 and 12) with no settings.
	var pumped:=f_world([f_spr(12),f_tower(0),f_tank(40),f_pipe(),f_pump()],24,49)
	plan_is(pumped,{c(51,24):0,c(50,24):48},"no settings, pump on: the tank leftover refills the tower",{},8)
	expect(same(Industry.plan(pumped,12),pre_setting_plan(pumped,12)) and same(Industry.plan(pumped,8),pre_setting_plan(pumped,8)),"pumped network: plan == pre-setting plan at rates 8 and 12")
	# A tower-free network beside a tower network with settings is untouched.
	var mixed:=f_world([f_tank(30),f_spr(0),f_pipe(),f_spr(5)],80)
	var alone:=f_world([f_tank(30),f_spr(0),f_pipe(),f_spr(5)],80)
	mixed.state.objects[c(20,84)]=f_tank(40)
	mixed.state.objects[c(21,84)]=f_tower(10,true,{"reserve":24}.merged(qs(4)))
	mixed.state.objects[c(22,84)]=f_spr(0)
	var free_expected:={c(20,80):11,c(21,80):12,c(23,80):12}
	plan_is(alone,free_expected,"tower-free network on its own")
	plan_is(mixed,free_expected.merged({c(20,84):24,c(21,84):14,c(22,84):12}),"tower-free network unchanged beside a reserve/quota tower network (sprinkler 12 from the tank, tower +4 above the reserve 24, nothing to discharge)")
	var now:=Industry.plan(mixed)
	var free_now:={}
	for key in now:
		if key.ends_with(",80"):free_now[key]=now[key]
	expect(same(free_now,Industry.plan(alone)),"tower-free part of the mixed plan == its own plan")
	expect(same(Industry.plan_detail(alone).quota,{}),"tower-free world: plan_detail quota is empty")

# ------------------------------------------------------- reserve fixtures --

func check_reserve_fixtures() -> void:
	# One tank, one tower: TANK TW (y=50).
	var T:=c(20,50);var W:=c(21,50)
	var one:=[[40,0,12,{T:12,W:28}],[40,0,24,{T:24,W:16}],[40,0,36,{T:36,W:4}],[40,0,48,{}],[48,0,48,{}],[36,0,36,{}],[37,0,36,{T:36,W:1}],[48,90,12,{T:42,W:96}],[48,0,0,{T:0,W:48}],[10,0,12,{}],[48,96,12,{}],[0,0,12,{}]]
	for v:Array in one:
		var w:=f_world([f_tank(int(v[0])),f_tower(int(v[1]),true,rs(int(v[2])))],50)
		plan_is(w,v[3],"one tank %d, tower %d, reserve %d"%[int(v[0]),int(v[1]),int(v[2])])
	# Sprinklers take theirs first: S TANK TW (y=52).
	plan_is(f_world([f_spr(0),f_tank(40),f_tower(0,true,rs(24))],52),{c(20,52):12,c(21,52):24,c(22,52):4},"sprinkler takes 12 first, tower only gets the 4 above reserve 24")
	plan_is(f_world([f_spr(0),f_tank(40),f_tower(0,true,rs(36))],52),{c(20,52):12,c(21,52):28},"sprinkler leaves 28 < reserve 36: tower gets nothing")
	# Two tanks: A PIPE B TW (y=54); allowance is across the tank total.
	var A:=c(20,54);var B:=c(22,54);var W2:=c(23,54)
	var two:=[[30,20,0,24,{A:4,W2:26}],[30,20,0,48,{A:28,W2:2}],[5,40,0,12,{A:0,B:12,W2:33}],[20,20,0,48,{}],[24,24,0,48,{}],[48,48,50,12,{A:2,W2:96}],[48,48,0,0,{A:0,B:0,W2:96}],[0,30,0,24,{B:24,W2:6}],[48,48,0,36,{A:0,B:36,W2:60}]]
	for v:Array in two:
		var w:=f_world([f_tank(int(v[0])),f_pipe(),f_tank(int(v[1])),f_tower(int(v[2]),true,rs(int(v[3])))],54)
		plan_is(w,v[4],"two tanks %d+%d, tower %d, reserve %d"%[int(v[0]),int(v[1]),int(v[2]),int(v[3])])
	# Two tanks behind a sprinkler: S A PIPE B TW (y=56).
	plan_is(f_world([f_spr(0),f_tank(10),f_pipe(),f_tank(20),f_tower(0,true,rs(12))],56),{c(20,56):12,c(21,56):0,c(23,56):12,c(24,56):6},"sprinkler empties A and takes 2 from B; tower takes 6 from B down to the reserve 12")
	plan_is(f_world([f_spr(0),f_tank(10),f_pipe(),f_tank(20),f_tower(0,true,rs(24))],56),{c(20,56):12,c(21,56):0,c(23,56):18},"18 left after the sprinkler < reserve 24: tower gets nothing")
	# Two towers with different reserves (network order): A TW1 TW2 (y=58).
	var A3:=c(20,58);var X1:=c(21,58);var X2:=c(22,58)
	plan_is(f_world([f_tank(48),f_tower(0,true,rs(36)),f_tower(0,true,rs(12))],58),{A3:12,X1:12,X2:24},"first tower (reserve 36) takes 12, second (reserve 12) takes 24 more")
	plan_is(f_world([f_tank(48),f_tower(0,true,rs(12)),f_tower(0,true,rs(36))],58),{A3:12,X1:36},"first tower (reserve 12) takes 36, the second (reserve 36) gets nothing")
	plan_is(f_world([f_tank(48),f_tower(0,true,rs(24)),f_tower(0)],58),{A3:0,X1:24,X2:24},"reserved tower takes 24, the plain tower after it takes the rest")
	plan_is(f_world([f_tank(48),f_tower(0),f_tower(0,true,rs(24))],58),{A3:0,X1:48},"a plain tower first takes everything; the reserved one gets nothing")
	# Low and cut zone towers: TF TANK PIPE G(low) TL G(closed) TC (y=60).
	var TF:=c(20,60);var TK:=c(21,60);var TL:=c(24,60);var TC:=c(26,60)
	plan_is(reserve_zone_row(48,0,36,0,12,0,0),{TK:12,TF:12,TL:24},"full tower reserve 36 takes 12, low tower reserve 12 takes 24, cut tower nothing")
	plan_is(reserve_zone_row(48,0,48,0,0,0,0),{TK:0,TL:48},"full tower reserve 48 gets nothing; the plain low tower takes all 48")
	plan_is(reserve_zone_row(48,90,0,0,24,0,0),{TK:24,TF:96,TL:18},"full tower tops up 6; low tower reserve 24 takes 18")
	plan_is(reserve_zone_row(48,96,0,96,0,0,12),{},"cut tower with reserve 12 gets nothing")
	plan_is(reserve_zone_row(48,96,0,96,0,0,0),{},"cut tower without reserve also gets nothing")
	# Full zone first even when the low tower is earlier in network order: TL G(low) PIPE TANK TF (y=62).
	var LL:=c(20,62);var LT:=c(23,62);var LF:=c(24,62)
	plan_is(f_world([f_tower(0,true,rs(0)),f_gate("low"),f_pipe(),f_tank(48),f_tower(0,true,rs(24))],62),{LT:0,LF:24,LL:24},"full-zone tower (reserve 24) refills before the earlier low-zone tower")
	plan_is(f_world([f_tower(0,true,rs(12)),f_gate("low"),f_pipe(),f_tank(48),f_tower(0)],62),{LT:0,LF:48},"plain full-zone tower takes all; low tower (reserve 12) gets nothing")
	plan_is(f_world([f_tower(0,true,rs(12)),f_gate("low"),f_pipe(),f_tank(48),f_tower(0,true,rs(36))],62),{LT:12,LF:12,LL:24},"full reserve 36 takes 12, then low reserve 12 takes 24")
	# A 只蓄水 tower still refills, still above its reserve.
	plan_is(f_world([f_tank(40),f_tower(0,false,rs(24))],64),{c(20,64):24,c(21,64):16},"disabled tower refills only above reserve 24")
	# Pump inflow lands in the tank first; the tower takes only what is above the reserve.
	var pumped:=f_world([f_spr(12),f_tower(0,true,rs(24)),f_tank(40),f_pipe(),f_pump()],24,49)
	plan_is(pumped,{c(51,24):24,c(50,24):24},"pump +8 to 48, reserved tower takes 24 down to 24",{},8)
	var pumped_low:=f_world([f_spr(12),f_tower(0,true,rs(48)),f_tank(40),f_pipe(),f_pump()],24,49)
	plan_is(pumped_low,{c(51,24):48},"pump +8 to 48 = reserve 48: tower gets nothing",{},8)

## Row y=60: TF TANK PIPE G(low) TL G(closed) TC with per-tower water and reserve.
func reserve_zone_row(tank:int,tf:int,rf:int,tl:int,rl:int,tc:int,rc:int) -> World:
	return f_world([f_tower(tf,true,rs(rf)),f_tank(tank),f_pipe(),f_gate("low"),f_tower(tl,true,rs(rl)),f_gate("closed"),f_tower(tc,true,rs(rc))],60)

# --------------------------------------------------------- quota fixtures --

## Tower-only row y=66: TW S1 S2 S3; sprinklers default to empty and enabled.
func q_row(tower:Dictionary,s1:Dictionary={},s2:Dictionary={},s3:Dictionary={}) -> World:
	return f_world([tower,f_spr(0) if s1.is_empty() else s1,f_spr(0) if s2.is_empty() else s2,f_spr(0) if s3.is_empty() else s3],66)

func check_quota_fixtures() -> void:
	# Tower-only network: TW S1 S2 S3 (y=66).
	var W:=c(20,66);var S1:=c(21,66);var S2:=c(22,66);var S3:=c(23,66)
	plan_is(q_row(f_tower(50,true,qs(4))),{S1:4,W:46},"quota 4: S1 partly filled",{W:{"day":0,"used":4}})
	plan_is(q_row(f_tower(50,true,qs(8))),{S1:8,W:42},"quota 8: S1 gets 8",{W:{"day":0,"used":8}})
	plan_is(q_row(f_tower(50,true,qs(16))),{S1:12,S2:4,W:34},"quota 16: S1 full, S2 partly (4)",{W:{"day":0,"used":16}})
	plan_is(q_row(f_tower(50,true,qs(24))),{S1:12,S2:12,W:26},"quota 24: S1, S2 full, S3 none",{W:{"day":0,"used":24}})
	plan_is(q_row(f_tower(50)),{S1:12,S2:12,S3:12,W:14},"no quota: every sprinkler filled",{})
	plan_is(q_row(f_tower(50,true,qs(16)),f_spr(10)),{S1:12,S2:12,S3:2,W:34},"quota 16 over S1 (+2), S2 (+12), S3 (+2)",{W:{"day":0,"used":16}})
	plan_is(q_row(f_tower(10,true,qs(24))),{S1:10,W:0},"quota 24 but only 10 in the tower",{W:{"day":0,"used":10}})
	plan_is(q_row(f_tower(50,true,qs(16)),f_spr(0,false)),{S2:12,S3:4,W:34},"disabled S1 skipped; quota 16 over S2, S3",{W:{"day":0,"used":16}})
	plan_is(q_row(f_tower(50,true,qs(16,0,10))),{S1:6,W:44},"10 already sent today: only 6 more",{W:{"day":0,"used":16}})
	plan_is(q_row(f_tower(50,true,qs(8,0,8))),{},"quota already used up today: nothing sent, no quota entry",{})
	plan_is(q_row(f_tower(50,true,qs(4,0,8))),{},"lowered quota below today's used: nothing sent",{})
	plan_is(q_row(f_tower(50,true,qs(24,0,24))),{},"quota 24 used 24: nothing sent",{})
	plan_is(q_row(f_tower(50,false,qs(8))),{},"只蓄水 tower with quota: nothing sent, no quota entry",{})
	plan_is(q_row(f_tower(50,true,qs(8)),f_spr(12),f_spr(12),f_spr(12)),{},"consumers full: no quota entry",{})
	plan_is(q_row(f_tower(0,true,qs(8))),{},"empty tower: no quota entry",{})
	# Days: previous-day record counts 0; the day is taken from world.state.time.
	var prev:World=q_row(f_tower(50,true,qs(8,2,8)))
	prev.state.time=3.0*1440.0+100.0
	plan_is(prev,{S1:8,W:42},"record from day 2 on day 3 counts 0",{W:{"day":3,"used":8}})
	var prev_partial:World=q_row(f_tower(50,true,qs(16,0,12)))
	prev_partial.state.time=1440.0
	plan_is(prev_partial,{S1:12,S2:4,W:34},"day-0 record at time 1440 (day 1) counts 0",{W:{"day":1,"used":16}})
	var edge:World=q_row(f_tower(50,true,qs(8,0,8)))
	edge.state.time=1439.5
	plan_is(edge,{},"time 1439.5 is still day 0: quota stays used up",{})
	edge.state.time=1440.0
	plan_is(edge,{S1:8,W:42},"time 1440 is day 1: delivery resumes",{W:{"day":1,"used":8}})
	var future:World=q_row(f_tower(50,true,qs(8,5,8)))
	future.state.time=100.0
	plan_is(future,{S1:8,W:42},"record of another day (5) on day 0 counts 0",{W:{"day":0,"used":8}})
	# Garbage quota values behave as no quota.
	plan_is(q_row(f_tower(50,true,{"quota":"8","quota_day":0,"quota_used":0})),{S1:12,S2:12,S3:12,W:14},"text quota counts as no quota",{})
	plan_is(q_row(f_tower(50,true,{"quota":5,"quota_day":0,"quota_used":0})),{S1:12,S2:12,S3:12,W:14},"quota 5 (not an option) counts as no quota",{})
	# Sprinklers before waterworks regardless of position: TW WW S1 (y=68).
	plan_is(f_world([f_tower(50,true,qs(16)),f_ww(0),f_spr(0)],68),{c(22,68):12,c(21,68):4,c(20,68):34},"quota 16: sprinkler 12 first, waterworks 4",{c(20,68):{"day":0,"used":16}})
	plan_is(f_world([f_tower(50,true,qs(24)),f_ww(0),f_spr(0)],68),{c(22,68):12,c(21,68):World.WATERWORKS.CAPACITY,c(20,68):50-12-World.WATERWORKS.CAPACITY},"quota 24: sprinkler 12, waterworks to its capacity",{c(20,68):{"day":0,"used":12+World.WATERWORKS.CAPACITY}})
	# Two towers: S1 TW1 PIPE TW2 S2(full) (y=70).
	var R1:=c(20,70);var X1:=c(21,70);var X2:=c(23,70)
	plan_is(f_world([f_spr(0),f_tower(30,true,qs(8)),f_pipe(),f_tower(30,true,qs(16)),f_spr(12)],70),{R1:12,X1:22,X2:26},"TW1 sends 8, TW2 tops S1 up with 4",{X1:{"day":0,"used":8},X2:{"day":0,"used":4}})
	plan_is(f_world([f_spr(0),f_tower(30,true,qs(8)),f_pipe(),f_tower(30,true,qs(4,0,4)),f_spr(12)],70),{R1:8,X1:22},"TW2 used up: quota lists only TW1",{X1:{"day":0,"used":8}})
	plan_is(f_world([f_spr(0),f_tower(30),f_pipe(),f_tower(30,true,qs(16)),f_spr(12)],70),{R1:12,X1:18},"plain TW1 fills S1; TW2 sends nothing and is not listed",{})
	plan_is(f_world([f_spr(0),f_tower(30,true,qs(8,0,8)),f_pipe(),f_tower(30,true,qs(8,0,3)),f_spr(12)],70),{R1:5,X2:25},"TW1 used up; TW2 has 5 left today",{X2:{"day":0,"used":8}})
	# Gates stop a tower's outflow (only open passes): TW G S (y=72).
	for mode in ["open","low","closed"]:
		var gated:=f_world([f_tower(50,true,qs(8)),f_gate(mode),f_spr(0)],72)
		if mode=="open":plan_is(gated,{c(22,72):8,c(20,72):42},"quota tower through an open gate",{c(20,72):{"day":0,"used":8}})
		else:plan_is(gated,{},"quota tower behind a %s gate: nothing sent, no quota entry"%mode,{})
	# Tank first, then the tower within its quota: S1 TANK TW(reserve 12, quota 4) S2 (y=74).
	plan_is(f_world([f_spr(0),f_tank(10),f_tower(50,true,{"reserve":12}.merged(qs(4))),f_spr(0)],74),{c(20,74):12,c(21,74):0,c(23,74):2,c(22,74):46},"tank gives S1 10; tower adds 2 to S1 and 2 to S2 (quota 4)",{c(22,74):{"day":0,"used":4}})
	# Refill and discharge in the same round: TANK TW(reserve 24, quota 8) S (y=76); S fed by the tank first.
	plan_is(f_world([f_tank(48),f_tower(0,true,{"reserve":24}.merged(qs(8))),f_spr(12)],76),{c(20,76):24,c(21,76):24},"full sprinkler: tower refills 24 above the reserve, sends nothing",{})
	plan_is(f_world([f_tank(10),f_tower(20,true,{"reserve":24}.merged(qs(8))),f_spr(0)],76),{c(20,76):0,c(22,76):12,c(21,76):18},"tank 10 to the sprinkler, tower adds 2 (quota 8 not reached)",{c(21,76):{"day":0,"used":2}})
	# Cut-zone tower discharging with a quota (zone_row-like): TANK G(closed) TW S (y=78).
	plan_is(f_world([f_tank(48),f_gate("closed"),f_tower(30,true,qs(4)),f_spr(0)],78),{c(23,78):4,c(22,78):26},"cut tower still discharges its own water within quota 4",{c(22,78):{"day":0,"used":4}})

# ------------------------------------------------------------- real world --

func build_world(w:World,label:String) -> bool:
	w.add_player(OWNER,"Owner")
	w.add_player(OTHER,"Other")
	# Row y=21 stays clear of the reserved public-mill parcel (47..49,23..25 and 48,26).
	for tile:Vector2i in [S_A,TOWER,S_B,S_C,PIPE_B,TANK,PIPE_C,PUMP,MOVED]:
		if World.base_resource(tile)!="":w.state.removed[k(tile)]=true
	write_revisit_fixture(w)
	var inv:Dictionary=w.state.players[OWNER].inventory
	inv["sprinkler_kit"]=3
	inv["water_tower_kit"]=1
	inv["pipe_kit"]=2
	inv["tank_kit"]=1
	inv["pump_kit"]=1
	ok(w,OWNER,"build",S_A,"sprinkler","%s: sprinkler A"%label)
	ok(w,OWNER,"build",TOWER,"water_tower","%s: water tower"%label)
	ok(w,OWNER,"build",S_B,"sprinkler","%s: sprinkler B"%label)
	ok(w,OWNER,"build",S_C,"sprinkler","%s: sprinkler C"%label)
	ok(w,OWNER,"build",PIPE_B,"water_pipe","%s: pipe B"%label)
	ok(w,OWNER,"build",TANK,"water_tank","%s: tank"%label)
	ok(w,OWNER,"build",PIPE_C,"water_pipe","%s: pipe C"%label)
	ok(w,OWNER,"build",PUMP,"water_pump","%s: river pump"%label)
	expect(same(tw(w),{"type":"water_tower","owner":OWNER,"items":{},"water":0,"enabled":true}),"%s: new tower has no settings fields (%s)"%[label,str(tw(w))])
	var group:Dictionary={}
	for g in Industry.components(w.state):
		if k(TOWER) in g["keys"]:group=g
	return expect(group.get("keys",[]).size()==8 and group.get("sprinklers",[]).size()==3 and group.get("tanks",[])==[k(TANK)],"%s: one connected network of 8 with 3 sprinklers and the tank"%label)

func check_act_settings(w:World) -> void:
	refuse(w,OTHER,SET,TOWER,"reserve:12",Industry.TOWER_NOT_OWNER,"another player sets the reserve")
	refuse(w,OTHER,SET,TOWER,"quota:8",Industry.TOWER_NOT_OWNER,"another player sets the quota")
	refuse(w,OTHER,SET,TOWER,"water:5",Industry.TOWER_NOT_OWNER,"another player with a bad setting still gets not-owner")
	refuse(w,OWNER,SET,PIPE_B,"reserve:12",Industry.TOWER_NOT_OWNER,"tower_set on a pipe")
	refuse(w,OWNER,SET,TANK,"quota:8",Industry.TOWER_NOT_OWNER,"tower_set on a tank")
	refuse(w,OWNER,SET,S_B,"quota:8",Industry.TOWER_NOT_OWNER,"tower_set on a sprinkler")
	refuse(w,OWNER,SET,PUMP,"reserve:24",Industry.TOWER_NOT_OWNER,"tower_set on a pump")
	refuse(w,OWNER,SET,Vector2i(45,22),"reserve:12",Industry.TOWER_NOT_OWNER,"tower_set on an empty cell")
	var person:Dictionary=w.state.players[OWNER]
	person.x=TOWER.x+0.5
	person.y=TOWER.y+6.5
	refuse(w,OWNER,SET,TOWER,"reserve:12","靠近一點，才能和它互動","tower_set from six tiles away",false)
	refuse(w,OWNER,SET,TOWER,"reserve:0",Industry.TOWER_SAME_SETTING,"reserve:0 on a new tower")
	refuse(w,OWNER,SET,TOWER,"quota:0",Industry.TOWER_SAME_SETTING,"quota:0 on a new tower")
	for extra:String in BAD_EXTRAS:
		refuse(w,OWNER,SET,TOWER,extra,Industry.TOWER_BAD_SETTING,"bad setting '%s' on a new tower"%extra)
	var r:=ok(w,OWNER,SET,TOWER,"reserve:24","owner sets reserve 24")
	expect(str(r.get("message",""))=="水塔已設為「儲水桶留 24 份」","reserve 24 message (%s)"%str(r.get("message","")))
	refuse(w,OWNER,SET,TOWER,"reserve:24",Industry.TOWER_SAME_SETTING,"reserve 24 again")
	var q:=ok(w,OWNER,SET,TOWER,"quota:8","owner sets quota 8")
	expect(str(q.get("message",""))=="水塔已設為「每日配水 8 份」","quota 8 message (%s)"%str(q.get("message","")))
	refuse(w,OWNER,SET,TOWER,"quota:8",Industry.TOWER_SAME_SETTING,"quota 8 again")
	expect(same(tw(w),{"type":"water_tower","owner":OWNER,"items":{},"water":0,"enabled":true,"reserve":24,"quota":8,"quota_day":0,"quota_used":0}),"tower carries reserve 24, quota 8, quota_day 0, quota_used 0 (%s)"%str(tw(w)))
	refuse(w,OTHER,SET,TOWER,"reserve:0",Industry.TOWER_NOT_OWNER,"another player clears the reserve")
	refuse(w,OTHER,SET,TOWER,"quota:0",Industry.TOWER_NOT_OWNER,"another player clears the quota")
	for extra:String in BAD_EXTRAS:
		refuse(w,OWNER,SET,TOWER,extra,Industry.TOWER_BAD_SETTING,"bad setting '%s' on a configured tower"%extra)
	var rep:=Industry.tower_report(w.state,k(TOWER))
	expect(rep.ok and int(rep.reserve)==24 and int(rep.quota)==8 and int(rep.quota_used)==0 and int(rep.quota_left)==8,"tower_report after the settings (%s)"%str(rep))
	expect(validates(w.state),"configured world validates")

## Pump on, sprinklers disabled: the reserve-24 tower never draws the tank below 24;
## the contrast tower (no reserve) drains the tank every tick.
func check_reserve_ticks(w:World,plain:World) -> void:
	for x:World in [w,plain]:
		var on:=ok(x,OWNER,"toggle_pump",PUMP,"","switch the river pump on")
		expect(str(on.get("message",""))=="河水泵已啟用","pump on message")
		x.state.next_network_check=float(x.state.time)
	var held:=true
	for n in range(1,13):
		expect(w.step(8.0,true) and plain.step(8.0,true),"tick %d steps"%n)
		var tank:=wat(w,TANK)
		var tower:=wat(w,TOWER)
		expect(tank==mini(8*n,24) and tower==maxi(0,8*n-24),"reserve 24, tick %d: tank %d (expected %d), tower %d (expected %d)"%[n,tank,mini(8*n,24),tower,maxi(0,8*n-24)])
		expect(wat(plain,TANK)==0 and wat(plain,TOWER)==8*n,"contrast, tick %d: tank 0 (%d), tower %d (%d)"%[n,wat(plain,TANK),8*n,wat(plain,TOWER)])
		expect(tank+tower==8*n and wat(plain,TANK)+wat(plain,TOWER)==8*n,"tick %d: tank+tower == pump inflow 8n in both worlds"%n)
		if n>=3 and tank<24:held=false
	expect(held,"from tick 3 on the reserve-24 tank never drops below 24")
	expect(spr_total(w)==0 and spr_total(plain)==0,"disabled sprinklers stay dry")
	var t:=tw(w)
	expect(int(t.get("quota_day",-1))==0 and int(t.get("quota_used",-1))==0,"no discharge (sprinklers disabled): quota record untouched (%s)"%str(t))

func check_quota_days(w:World,path:String) -> void:
	var off:=ok(w,OWNER,"toggle_pump",PUMP,"","switch the pump off")
	expect(str(off.get("message",""))=="河水泵已停用","pump off message")
	var clear:=ok(w,OWNER,SET,TOWER,"reserve:0","owner clears the reserve")
	expect(str(clear.get("message",""))=="水塔已設為「不保留桶水」" and not tw(w).has("reserve"),"reserve 0 message and the field is erased")
	var tank_before:=wat(w,TANK)
	var tower_before:=wat(w,TOWER)
	expect(w.step(8.0,true),"refill step")
	expect(wat(w,TANK)==0 and wat(w,TOWER)==tower_before+tank_before and wat(w,TOWER)==96,"without the reserve the tower takes the tank's %d (tower %d)"%[tank_before,wat(w,TOWER)])
	for cell:Vector2i in SPRS:ok(w,OWNER,"toggle_sprinkler",cell,"","enable sprinkler %s"%k(cell))
	var order:Array=[]
	for g in Industry.components(w.state):
		if k(TOWER) in g["keys"]:order=Industry.tower_consumers(w.state.objects,g,k(TOWER))
	expect(order.size()==3,"the tower feeds all three sprinklers (%s)"%str(order))
	expect(float(w.state.time)<Industry.TOWER_DAY and int(tw(w).quota_day)==0 and int(tw(w).quota_used)==0,"day 0, nothing sent yet")
	var straddled:=false
	var steps:=0
	while float(w.state.time)<Industry.TOWER_DAY:
		var start:=float(w.state.time)
		expect(w.step(DAY_DT,true),"day 0 step from %s"%str(start))
		steps+=1
		var t:=tw(w)
		expect(wat(w,TOWER)==88 and spr_total(w)==8 and int(t.get("quota_used",-1))==8 and int(t.get("quota_day",-1))==0,"day 0 step %d (from %s): quota 8 reached and held: tower %d, sprinklers %d, used %s, day %s"%[steps,str(start),wat(w,TOWER),spr_total(w),str(t.get("quota_used")),str(t.get("quota_day"))])
		expect(wat(w,TOWER)>0 and spr_total(w)<36,"day 0 step %d: the tower still has water and the sprinklers still have room"%steps)
		if start<Industry.TOWER_DAY and float(w.state.time)>Industry.TOWER_DAY:straddled=true
	expect(steps>=10,"several network ticks within day 0 (%d)"%steps)
	if order.size()==3:expect(wkey(w,order[0])==8 and wkey(w,order[1])==0 and wkey(w,order[2])==0,"day 0: the first consumer in order got all 8")
	expect(straddled,"the round crossing midnight still counted as day 0 (nothing sent)")
	var rep0:=Industry.tower_report(w.state,k(TOWER),0)
	expect(int(rep0.quota_used)==8 and int(rep0.quota_left)==0,"tower_report day 0: used 8, left 0 (%s)"%str(rep0))
	expect(w.step(DAY_DT,true),"first day-1 step")
	var t1:=tw(w)
	expect(wat(w,TOWER)==80 and spr_total(w)==16 and int(t1.get("quota_day",-1))==1 and int(t1.get("quota_used",-1))==8,"day 1: delivery resumes, quota_day 1, used 8 (tower %d, sprinklers %d, %s)"%[wat(w,TOWER),spr_total(w),str(t1)])
	if order.size()==3:expect(wkey(w,order[0])==12 and wkey(w,order[1])==4 and wkey(w,order[2])==0,"day 1: first consumer topped up to 12, second gets 4")
	expect(w.step(DAY_DT,true),"second day-1 step")
	expect(wat(w,TOWER)==80 and spr_total(w)==16 and int(tw(w).quota_used)==8,"day 1: held at the quota")
	var res:=ok(w,OWNER,SET,TOWER,"reserve:36","owner sets reserve 36")
	expect(str(res.get("message",""))=="水塔已設為「儲水桶留 36 份」","reserve 36 message")
	check_save(w,path)
	check_snapshot(w)
	# Lowering mid-day keeps what was sent.
	var low:=ok(w,OWNER,SET,TOWER,"quota:4","owner lowers the quota to 4 mid-day")
	expect(str(low.get("message",""))=="水塔已設為「每日配水 4 份」","quota 4 message")
	var tl:=tw(w)
	expect(int(tl.get("quota",-1))==4 and int(tl.get("quota_day",-1))==1 and int(tl.get("quota_used",-1))==8,"lowered quota keeps quota_used 8 (%s)"%str(tl))
	expect(w.step(DAY_DT,true),"step after lowering")
	expect(wat(w,TOWER)==80 and spr_total(w)==16 and int(tw(w).quota_used)==8,"used 8 > quota 4: nothing more today")
	var rep:=Industry.tower_report(w.state,k(TOWER),1)
	expect(int(rep.quota)==4 and int(rep.quota_used)==8 and int(rep.quota_left)==0 and int(rep.reserve)==36,"tower_report after lowering (%s)"%str(rep))
	# Unlimited, then back: counts from 0.
	var unl:=ok(w,OWNER,SET,TOWER,"quota:0","owner sets the quota to unlimited")
	expect(str(unl.get("message",""))=="水塔已設為「每日配水不限」","quota 0 message")
	var tu:=tw(w)
	expect(not tu.has("quota") and not tu.has("quota_day") and not tu.has("quota_used") and int(tu.get("reserve",0))==36,"quota fields erased, reserve kept (%s)"%str(tu))
	expect(w.step(DAY_DT,true),"unlimited step")
	expect(wat(w,TOWER)==60 and spr_total(w)==36,"unlimited: every sprinkler filled (tower %d, sprinklers %d)"%[wat(w,TOWER),spr_total(w)])
	expect(not tw(w).has("quota_used") and not tw(w).has("quota_day"),"unlimited delivery writes no quota record")
	var back:=ok(w,OWNER,SET,TOWER,"quota:16","owner sets quota 16 again")
	expect(str(back.get("message",""))=="水塔已設為「每日配水 16 份」","quota 16 message")
	var tb:=tw(w)
	expect(int(tb.get("quota",-1))==16 and int(tb.get("quota_day",-1))==1 and int(tb.get("quota_used",-1))==0,"back from unlimited: quota_day 1, used 0 (%s)"%str(tb))
	expect(validates(w.state),"world validates after the quota changes")

# ------------------------------------------------------------------- saves --

func check_save(w:World,path:String) -> void:
	expect(w.save(),"world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"fresh World reloads")
	expect(same(reloaded.state.objects,w.state.objects),"objects equal after reload")
	var t:Dictionary=reloaded.state.objects.get(k(TOWER),{})
	expect(int(t.get("reserve",-1))==36 and int(t.get("quota",-1))==8 and int(t.get("quota_day",-1))==1 and int(t.get("quota_used",-1))==8 and int(t.get("water",-1))==80,"reserve 36 / quota 8 / quota_day 1 / quota_used 8 survive reload (%s)"%str(t))
	expect(same(Industry.plan_detail(reloaded),Industry.plan_detail(w)),"plan_detail after reload identical")
	var base_v:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base_v is Dictionary and validates(base_v),"saved world validates"):return
	var base:Dictionary=base_v
	var today:=int(floor(float(base.time)/Industry.TOWER_DAY))
	expect(today==1,"saved on day 1 (%d)"%today)
	var fixture:=temp_path("fixture")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["reserve 0 present","reserve 13","reserve text","reserve 12.5","reserve -12","reserve 60","reserve null","quota 0 present","quota 5","quota text","quota 8.5","quota 32","quota -8","quota without quota_day","quota without quota_used","quota alone","quota_day without quota","quota_used without quota","day and used without quota","quota_day in the future","quota_day negative","quota_day fractional","quota_day text","quota_used 25","quota_used negative","quota_used fractional","quota_used text","unknown field quota_left","unknown field limit"]
	for label:String in labels:
		var bad:=tampered(base,label,today)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	# Controls.
	for label:String in ["neither","only reserve","only quota","both"]:
		var good:=variant(base,label)
		expect(validates(good),"schema accepts a tower with %s"%label)
	var neither:=variant(base,"neither")
	expect(write_json(fixture,neither) and probe.load_world(fixture),"a tower without any setting loads")
	for r in [12,24,36,48]:
		var s:Dictionary=base.duplicate(true)
		s.objects[k(TOWER)]["reserve"]=r
		expect(validates(s),"schema accepts reserve %d"%r)
	for q in [4,8,16,24]:
		var s:Dictionary=base.duplicate(true)
		s.objects[k(TOWER)]["quota"]=q
		expect(validates(s),"schema accepts quota %d"%q)
	var cases:=[[4,1,8,"used above a lowered quota"],[24,1,24,"used 24"],[8,0,8,"a record from an earlier day"],[8,1,0,"used 0 today"]]
	for v:Array in cases:
		var s:Dictionary=base.duplicate(true)
		var g:Dictionary=s.objects[k(TOWER)]
		g["quota"]=int(v[0])
		g["quota_day"]=int(v[1])
		g["quota_used"]=int(v[2])
		expect(validates(s),"schema accepts quota %d day %d used %d (%s)"%[int(v[0]),int(v[1]),int(v[2]),str(v[3])])

func variant(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var g:Dictionary=s.objects[k(TOWER)]
	match label:
		"neither":
			for field in ["reserve","quota","quota_day","quota_used"]:g.erase(field)
		"only reserve":
			for field in ["quota","quota_day","quota_used"]:g.erase(field)
		"only quota":g.erase("reserve")
	return s

func tampered(base:Dictionary,label:String,today:int) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var g:Dictionary=s.objects[k(TOWER)]
	match label:
		"reserve 0 present":g.reserve=0
		"reserve 13":g.reserve=13
		"reserve text":g.reserve="12"
		"reserve 12.5":g.reserve=12.5
		"reserve -12":g.reserve=-12
		"reserve 60":g.reserve=60
		"reserve null":g.reserve=null
		"quota 0 present":g.quota=0
		"quota 5":g.quota=5
		"quota text":g.quota="8"
		"quota 8.5":g.quota=8.5
		"quota 32":g.quota=32
		"quota -8":g.quota=-8
		"quota without quota_day":g.erase("quota_day")
		"quota without quota_used":g.erase("quota_used")
		"quota alone":
			g.erase("quota_day")
			g.erase("quota_used")
		"quota_day without quota":
			g.erase("quota")
			g.erase("quota_used")
		"quota_used without quota":
			g.erase("quota")
			g.erase("quota_day")
		"day and used without quota":g.erase("quota")
		"quota_day in the future":g.quota_day=today+1
		"quota_day negative":g.quota_day=-1
		"quota_day fractional":g.quota_day=0.5
		"quota_day text":g.quota_day="1"
		"quota_used 25":g.quota_used=25
		"quota_used negative":g.quota_used=-1
		"quota_used fractional":g.quota_used=2.5
		"quota_used text":g.quota_used="8"
		"unknown field quota_left":g.quota_left=0
		"unknown field limit":g.limit=8
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
	var t:=tw(w)
	expect(int(shown.get("reserve",-1))==int(t.reserve) and int(shown.get("quota",-1))==int(t.quota) and int(shown.get("quota_day",-1))==int(t.quota_day) and int(shown.get("quota_used",-1))==int(t.quota_used),"public snapshot carries reserve / quota / quota_day / quota_used (%s)"%str(shown))
	var day:=Industry.tower_day(float(w.state.time))
	expect(same(Industry.tower_report(public,k(TOWER),day),Industry.tower_report(w.state,k(TOWER),day)),"tower_report on the client snapshot matches the server")
	session.world=null
	session.queue_free()
	w.save_path=keep

# ------------------------------------------------------------ move / remove --

func check_move_remove(w:World) -> void:
	var before:=tw(w).duplicate(true)
	expect(before.has("reserve") and before.has("quota"),"tower has both settings before the move")
	refuse(w,OTHER,"move_object",TOWER,k(MOVED),"","another player cannot move the tower")
	var person:Dictionary=w.state.players[OWNER]
	person.x=49.5
	person.y=23.5
	var moved:=act(w,OWNER,"move_object",TOWER,k(MOVED))
	expect(bool(moved.get("ok",false)),"owner moves the tower (%s)"%str(moved.get("message","")))
	expect(not w.state.objects.has(k(TOWER)) and same(obj(w,MOVED),before),"moved tower keeps water, enabled, reserve and quota record (%s)"%str(obj(w,MOVED)))
	refuse(w,OWNER,SET,MOVED,"quota:16",Industry.TOWER_SAME_SETTING,"moved tower still has quota 16")
	refuse(w,OWNER,SET,MOVED,"reserve:36",Industry.TOWER_SAME_SETTING,"moved tower still has reserve 36")
	var inv:Dictionary=w.state.players[OWNER].inventory
	var kits:=int(inv.get("water_tower_kit",0))
	ok(w,OWNER,"remove",MOVED,"","owner removes the tower")
	inv=w.state.players[OWNER].inventory
	expect(not w.state.objects.has(k(MOVED)) and int(inv.get("water_tower_kit",0))==kits+1,"removal returns the kit")
	ok(w,OWNER,"build",TOWER,"water_tower","re-place the tower")
	expect(same(tw(w),{"type":"water_tower","owner":OWNER,"items":{},"water":0,"enabled":true}),"re-placed tower has no settings fields (%s)"%str(tw(w)))
	refuse(w,OWNER,SET,TOWER,"reserve:0",Industry.TOWER_SAME_SETTING,"re-placed tower: reserve:0 is the same setting")
	refuse(w,OWNER,SET,TOWER,"quota:0",Industry.TOWER_SAME_SETTING,"re-placed tower: quota:0 is the same setting")
	var rep:=Industry.tower_report(w.state,k(TOWER))
	expect(int(rep.reserve)==0 and int(rep.quota)==0 and int(rep.quota_left)==-1,"re-placed tower report: no settings")
	expect(validates(w.state),"final world validates")
