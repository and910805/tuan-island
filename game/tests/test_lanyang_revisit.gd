extends SceneTree
## 第 40 章「蘭陽回訪・旱日分流」(scripts/lanyang_revisit.gd) + 分水木牌 rules test.
## Headless, World-level (World.act / save / load_world) plus an in-process Session
## for the public snapshot. No network.
##
## EARNED through real World.act: the canal repair (lanyang_clear ×3 + lanyang_donate),
## every first-分水 memory (memory_observe ×3, memory_gate/memory_flow ×3 rounds),
## the plaque (memory_plaque), every revisit gate/check/claim, every build / move /
## remove / deposit / withdraw of the plaque, the picnic (World.act "picnic").
## WRITTEN DIRECTLY (disclosed): player region/x/y (standing spots in Lanyang and at
## home, no travel action), repair materials plank 6 / stone 8 / resin 2, wood for the
## chest, board=true + soup 2 / bread 1 for the picnic, state.time jumps between world
## days (rainy day 3, next day, and the first day of summer / autumn / winter), the
## kit count at the 1e9 cap for BAG_FULL, and the tampered / legacy save files.
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Market=preload("res://scripts/market_stall.gd")
const ALPHA:="revisit-alpha-token-5d1e"
const BETA:="revisit-beta-token-0c77"
const LATE:="revisit-late-token-e3a9"
const KIT:="water_share_plaque_kit"
const KIND:="water_share_plaque"
const HOME_SPOT:=Vector2(39.5,33.5)
const BUILD_TILE:=Vector2i(38,34)
const MOVE_TILE:=Vector2i(37,35)
const CHEST_TILE:=Vector2i(40,35)
const DAY:=1440.0
const SEASON_GATES:={"spring":[3,2],"summer":[2,1],"autumn":[1,3],"winter":[1,2]}
const SEASON_DAYS:={"spring":0,"summer":14,"autumn":28,"winter":42}

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
	var w:=World.new()
	var path:=temp_path("main")
	w.save_path=path
	if main_flow(w,path):
		check_placement(w)
		check_not_currency(w)
		check_save_reload(w,path)
		check_snapshot(w)
	check_seasons()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("LANYANG_REVISIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("lanyang-revisit-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

## Stand one tile west of a Lanyang cell (same spot test_history_memory uses).
func beside(w:World,token:String,cell:Vector2i) -> void:
	put(w,token,Vector2(cell.x-0.5,cell.y+0.5),"lanyang")

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"revisit-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

## Rejected with the exact message (when given) and the whole world state byte-identical.
func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> void:
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

func set_day(w:World,day_index:int) -> void:
	w.state["time"]=float(day_index)*DAY+30.0

## Earned canal repair by `token` (materials written into the bag first).
func earn_repair(w:World,token:String) -> bool:
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:
		beside(w,token,cell)
		if not act(w,token,"lanyang_clear",cell).ok:return false
	beside(w,token,World.LANYANG_LIFE.SERVICE)
	for item in World.LANYANG_LIFE.REPAIR_COST:pl(w,token).inventory[item]=int(World.LANYANG_LIFE.REPAIR_COST[item])
	return act(w,token,"lanyang_donate",World.LANYANG_LIFE.SERVICE).ok and w.state.lanyang_life.repaired==true

## Earned first 分水 memory (3 observations + 3 rounds) for `token`.
func earn_memory(w:World,token:String) -> bool:
	for cell:Vector2i in Memory.OBSERVATIONS:
		beside(w,token,cell)
		if not act(w,token,"memory_observe",cell).ok:return false
	beside(w,token,Memory.SERVICE)
	for pair in [[2,2],[1,3],[2,1]]:
		if not act(w,token,"memory_gate",Memory.SERVICE,"a:%d"%pair[0]).ok:return false
		if not act(w,token,"memory_gate",Memory.SERVICE,"b:%d"%pair[1]).ok:return false
		if not act(w,token,"memory_flow",Memory.SERVICE).ok:return false
	return w.state.history_memory.players[token].completed==true

## Repaired canal + alpha's completed memory + plaque, all earned.
func earned_world() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	if not earn_repair(w,ALPHA) or not earn_memory(w,ALPHA):return null
	beside(w,ALPHA,Memory.SERVICE)
	if not act(w,ALPHA,"memory_plaque",Memory.SERVICE).ok:return null
	return w

func gate(w:World,token:String,which:String,level:int,label:String) -> Dictionary:
	beside(w,token,Revisit.GATE_CELL)
	return ok(w,token,Revisit.GATE_ACTION,Revisit.GATE_CELL,Revisit.gate_extra(which,level),label)

func check(w:World,token:String,field:String,label:String) -> Dictionary:
	var cell:Vector2i=Revisit.FIELD_CELLS[field]
	beside(w,token,cell)
	return ok(w,token,Revisit.CHECK_ACTION,cell,"",label)

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(Revisit.ACTIONS==["revisit_gate","revisit_check","revisit_claim"],"action names")
	for action:String in Revisit.ACTIONS:
		expect(action.length()<=24 and Session.extra_allowed(action,"a:3"),"%s passes the Session transport bounds"%action)
	expect(Session.extra_allowed(World.INDUSTRY.GATE_ACTION,"closed"),"gate_mode passes the Session transport bounds")
	for season:String in Weather.SEASONS:
		var pair:Array=SEASON_GATES[season]
		expect(Memory.distribution(pair)==Revisit.demand_for(season),"%s demand %s reachable with gates %s"%[season,str(Revisit.demand_for(season)),str(pair)])
		expect(not Revisit.reason_for(season).is_empty(),"%s has a resident reason"%season)
	expect(Revisit.demand_for("spring")==[6,4,2] and Revisit.demand_for("summer")==[4,2,6] and Revisit.demand_for("autumn")==[2,6,4] and Revisit.demand_for("winter")==[2,4,6],"seasonal demand table")
	expect(Revisit.DISCLAIMER.contains("原創") and Revisit.DISCLAIMER.contains("非史料"),"original-fiction disclaimer")
	expect(Revisit.FIELD_CELLS.middle==Memory.SERVICE and Revisit.FIELD_CELLS.upstream==Vector2i(33,22) and Revisit.FIELD_CELLS.tail==Vector2i(33,32) and Revisit.GATE_CELL==Vector2i(33,25),"field and gate cells")
	expect(World.NAMES.get(KIT)=="分水木牌" and World.BUILD.get(KIND)=={"name":"分水木牌",KIT:1},"plaque kit and build entry")
	expect(Revisit.PLAQUE_SOURCE=="來源：宜蘭・蘭陽水圳回訪" and Revisit.PLAQUE_PROJECT=="對應工程：蘭陽水圳修復","provenance constants")
	expect(not KIND in World.UNDO_SOLID,"plaque is walk-through decor")
	var prices:=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	expect(not prices.has(KIT) and not World.OTHER_SALES.has(KIT) and not World.CROPS.has(KIT) and not World.FISH.has(KIT),"plaque kit has no price")
	expect(not Market.sellable(KIT) and not World.trade_items().has(KIT) and World.trade_items().has("wood"),"plaque kit is not stall-listable nor tradeable")
	expect(not World.SHIPPING.quote([[KIT,1]],{KIT:1},prices).ok,"shipping quote refuses the plaque kit")
	var snap:={"time":0.0,"lanyang_life":{"repaired":true},"history_memory":{"plaque":true,"own_memory":{"completed":true}}}
	expect(Revisit.unlocked(snap) and Revisit.player_ready(snap) and not Revisit.completed(snap) and not Revisit.tech_unlocked(snap),"view: unlocked/ready from a client-shaped snapshot")
	expect(Revisit.gate_block(snap)=="" and Revisit.check_block(snap,"upstream")==Revisit.NO_GATES_TODAY and Revisit.claim_block(snap,{})==Revisit.NOT_DONE,"view: block reasons before any gate")
	expect(Revisit.gate_block({"time":0.0,"lanyang_life":{"repaired":true},"history_memory":{"plaque":false}})==Revisit.LOCKED,"view: LOCKED without the plaque")
	expect(Revisit.gate_block({"time":0.0,"lanyang_life":{"repaired":true},"history_memory":{"plaque":true,"own_memory":{"completed":false}}})==Revisit.NOT_READY,"view: NOT_READY without own memory")
	snap["time"]=2*DAY
	expect(Revisit.raining(snap) and Revisit.gate_block(snap)==Revisit.RAINY,"view: day 3 is rainy in Lanyang")
	snap["time"]=0.0
	snap[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["tail"],"completed":false,"claimed_own":false}
	var rows:=Revisit.fields(snap)
	expect(rows.size()==3 and rows[0].current==6 and rows[0].needed==6 and rows[2].checked and not rows[0].checked and rows[1].ok,"view: fields() current/needed/checked")
	expect(Revisit.check_block(snap,"upstream")=="" and Revisit.check_block(snap,"tail")==Revisit.ALREADY_CHECKED,"view: check_block with matching gates")
	snap["time"]=DAY+5.0
	expect(Revisit.checked_today(snap).is_empty() and Revisit.check_block(snap,"upstream")==Revisit.NO_GATES_TODAY,"view: a new day clears the checks")
	snap[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["tail","upstream","middle"],"completed":true,"claimed_own":true}
	expect(Revisit.tech_unlocked(snap) and Revisit.claim_block(snap,{})==Revisit.CLAIMED and Revisit.claimed_own(snap),"view: claimed_own from the snapshot flag")
	snap[Revisit.STATE_KEY].claimed_own=false
	expect(Revisit.can_claim(snap,{}) and Revisit.claim_block(snap,{KIT:Revisit.MAX_ITEM})==Revisit.BAG_FULL,"view: can_claim / BAG_FULL")
	expect(Revisit.public({})=={} and Revisit.field_at(Vector2i(33,32))=="tail" and Revisit.field_at(Vector2i(1,1))=="","public()/field_at()")
	var bare:={"players":{"x":{"x":32.5,"y":25.5,"inventory":{}}},"lanyang_life":{"repaired":true},"history_memory":{"plaque":true,"players":{"x":{"completed":true}}},"time":0.0}
	expect(Revisit.apply(bare,"nobody",Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:1",true).message==Revisit.NO_PLAYER,"module: unknown player")
	expect(Revisit.apply(bare,"x","memory_gate",Revisit.GATE_CELL,"a:1",true).message==Revisit.BAD_EXTRA,"module: foreign action")

# --------------------------------------------------------------- main world --

func main_flow(w:World,path:String) -> bool:
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	beside(w,ALPHA,Revisit.GATE_CELL)
	beside(w,BETA,Revisit.GATE_CELL)
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.LOCKED,"gate before the canal repair")
	if not expect(earn_repair(w,ALPHA),"canal repair earned through lanyang_clear / lanyang_donate"):return false
	beside(w,ALPHA,Revisit.GATE_CELL)
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.LOCKED,"gate before any plaque")
	if not expect(earn_memory(w,ALPHA),"alpha's first 分水 memory earned"):return false
	beside(w,ALPHA,Revisit.GATE_CELL)
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.LOCKED,"gate with alpha's memory but no plaque yet")
	beside(w,ALPHA,Memory.SERVICE)
	ok(w,ALPHA,"memory_plaque",Memory.SERVICE,"","alpha sets the plaque")
	expect(w.save(),"pre-revisit world saves")
	var legacy_path:=temp_path("pre-revisit")
	expect(DirAccess.copy_absolute(path,legacy_path)==OK,"copy the pre-revisit save")
	# Prerequisite / placement rejections.
	beside(w,BETA,Revisit.GATE_CELL)
	refuse(w,BETA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.NOT_READY,"beta has not done her own first memory (gate)")
	beside(w,BETA,Revisit.FIELD_CELLS.upstream)
	refuse(w,BETA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"",Revisit.NOT_READY,"beta not ready (check)")
	beside(w,BETA,Revisit.SERVICE)
	refuse(w,BETA,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.NOT_READY,"beta not ready (claim)")
	put(w,ALPHA,HOME_SPOT,"home")
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.WRONG_REGION,"gate from home")
	beside(w,ALPHA,Revisit.GATE_CELL)
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.SERVICE,"a:3",Revisit.WRONG_GATE_CELL,"gate at the service cell")
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.GATE_CELL,"",Revisit.WRONG_FIELD_CELL,"check at the junction")
	refuse(w,ALPHA,Revisit.CLAIM_ACTION,Revisit.GATE_CELL,"",Revisit.WRONG_SERVICE_CELL,"claim at the junction")
	put(w,ALPHA,Vector2(32.5,32.5),"lanyang")
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.TOO_FAR,"gate from seven tiles away")
	beside(w,ALPHA,Revisit.GATE_CELL)
	for bad:String in ["a:4","c:1","a:01","a","","a:-1","b:3:1"]:
		refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,bad,Revisit.BAD_GATE,"malformed gate extra '%s'"%bad)
	beside(w,ALPHA,Revisit.FIELD_CELLS.upstream)
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"x",Revisit.BAD_EXTRA,"check with an extra")
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"",Revisit.NO_GATES_TODAY,"check before anyone set the gates")
	beside(w,ALPHA,Revisit.SERVICE)
	refuse(w,ALPHA,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.NOT_DONE,"claim before completion")
	refuse(w,ALPHA,Revisit.CLAIM_ACTION,Revisit.SERVICE,"x",Revisit.BAD_EXTRA,"claim with an extra")
	# Rainy day 3.
	set_day(w,2)
	expect(Weather.rains(2.0,"lanyang"),"premise: day 3 rains in Lanyang")
	beside(w,ALPHA,Revisit.GATE_CELL)
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.RAINY,"gate on a rainy day")
	set_day(w,0)
	expect(not w.state.has(Revisit.STATE_KEY),"no record before the first successful gate")
	# Day 1 (spring, dry): set gates, wrong distributions, gate change clears checks.
	var g1:=gate(w,ALPHA,"a",3,"alpha opens the upstream gate to 3")
	expect(str(g1.message)==Revisit.GATE_OK%["上游閘",3,6,0,6],"gate message shows the new split (%s)"%str(g1.message))
	expect(same(w.state.get(Revisit.STATE_KEY),{"gates":[3,0],"day":1,"checked":[],"completed":false,"claimed":{}}),"record created by the first gate")
	refuse(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.SAME_GATE,"same gate level on the same day")
	beside(w,ALPHA,Revisit.FIELD_CELLS.upstream)
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"",Revisit.OTHER_WRONG%["上游的田",6],"upstream right but the others wrong")
	beside(w,ALPHA,Revisit.FIELD_CELLS.middle)
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.middle,"",Revisit.WRONG_SHARE%["中段的田",0,4],"middle gets 0 but needs 4")
	gate(w,ALPHA,"b",2,"alpha sets the middle gate to 2")
	check(w,ALPHA,"upstream","alpha confirms the upstream field")
	expect(same(w.state[Revisit.STATE_KEY].checked,["upstream"]),"one field checked")
	beside(w,ALPHA,Revisit.FIELD_CELLS.upstream)
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"",Revisit.ALREADY_CHECKED,"upstream checked twice")
	gate(w,ALPHA,"b",3,"changing a gate")
	expect(same(w.state[Revisit.STATE_KEY].checked,[]) and same(w.state[Revisit.STATE_KEY].gates,[3,3]),"gate change clears today's checks")
	gate(w,ALPHA,"b",2,"back to the spring split")
	check(w,ALPHA,"tail","alpha confirms the tail field")
	# Rainy day with a record: checks refused; then a dry next day clears the check.
	set_day(w,2)
	beside(w,ALPHA,Revisit.FIELD_CELLS.middle)
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.middle,"",Revisit.RAINY,"check on a rainy day")
	set_day(w,1)
	expect(not Weather.rains(1.0,"lanyang") and Revisit.checked_today(w.state).is_empty(),"day 2 is dry and yesterday's check no longer counts")
	refuse(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.middle,"",Revisit.NO_GATES_TODAY,"day rollover: gates must be set again")
	# Late-comer catch-up: beta finishes her own memory first.
	if not expect(earn_memory(w,BETA),"beta's first memory earned (catch-up path)"):return false
	gate(w,BETA,"b",2,"beta re-confirms the middle gate on the new day (same level)")
	expect(int(w.state[Revisit.STATE_KEY].day)==2 and same(w.state[Revisit.STATE_KEY].checked,[]),"re-confirm stamps day 2 and clears the stale check")
	# Two players split the fields.
	check(w,ALPHA,"upstream","alpha checks upstream")
	check(w,BETA,"middle","beta checks the middle field")
	var done:=check(w,ALPHA,"tail","alpha checks the tail: completion")
	expect(str(done.message)==Revisit.COMPLETE_OK and Revisit.completed(w.state),"completion message and flag")
	expect(same(w.state[Revisit.STATE_KEY],{"gates":[3,2],"day":2,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}),"exact completed record (no names or tokens)")
	beside(w,BETA,Revisit.GATE_CELL)
	refuse(w,BETA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:1",Revisit.ALREADY_DONE,"gate after completion")
	beside(w,BETA,Revisit.FIELD_CELLS.tail)
	refuse(w,BETA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.tail,"",Revisit.ALREADY_DONE,"check after completion")
	set_day(w,5)
	refuse(w,BETA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.tail,"",Revisit.ALREADY_DONE,"completion is permanent (later rainy day)")
	expect(Revisit.tech_unlocked(w.state),"diversion gate tech unlocked")
	# Claims: once each.
	beside(w,ALPHA,Revisit.SERVICE)
	var bag_before:=int(pl(w,ALPHA).inventory.get(KIT,0))
	var claim:=ok(w,ALPHA,Revisit.CLAIM_ACTION,Revisit.SERVICE,"","alpha claims the plaque")
	expect(str(claim.message)==Revisit.CLAIM_OK and int(pl(w,ALPHA).inventory.get(KIT,0))==bag_before+1,"alpha gets exactly one kit")
	refuse(w,ALPHA,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.CLAIMED,"alpha claims twice")
	beside(w,BETA,Revisit.SERVICE)
	pl(w,BETA).inventory[KIT]=Revisit.MAX_ITEM
	refuse(w,BETA,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.BAG_FULL,"beta's kit count at the cap")
	pl(w,BETA).inventory.erase(KIT)
	ok(w,BETA,Revisit.CLAIM_ACTION,Revisit.SERVICE,"","beta claims the plaque")
	expect(int(pl(w,BETA).inventory.get(KIT,0))==1,"beta gets one kit")
	# A player who joins later.
	w.add_player(LATE,"Late")
	beside(w,LATE,Revisit.SERVICE)
	refuse(w,LATE,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.NOT_READY,"late joiner must finish own memory before claiming")
	if not expect(earn_memory(w,LATE),"late joiner earns own first memory"):return false
	beside(w,LATE,Revisit.SERVICE)
	ok(w,LATE,Revisit.CLAIM_ACTION,Revisit.SERVICE,"","late joiner claims the plaque")
	refuse(w,LATE,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.CLAIMED,"late joiner claims twice")
	var claimed:Array=w.state[Revisit.STATE_KEY].claimed.keys()
	claimed.sort()
	var want:=[ALPHA,BETA,LATE]
	want.sort()
	expect(claimed==want,"claim set = alpha, beta, late")
	expect(w.save() and validates(JSON.parse_string(FileAccess.get_file_as_string(path))),"completed world saves and validates")
	var legacy:=World.new()
	expect(legacy.load_world(legacy_path) and not legacy.recovered_from_backup and not legacy.state.has(Revisit.STATE_KEY),"pre-revisit save (no field) loads without migration")
	return true

# --------------------------------------------------------------- placement --

func check_placement(w:World) -> void:
	put(w,ALPHA,HOME_SPOT,"home")
	var bag:Dictionary=pl(w,ALPHA).inventory
	expect(int(bag.get(KIT,0))==1,"alpha holds one plaque kit")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the plaque")
	expect(int(bag.get(KIT,0))==0 and same(w.state.objects.get(World.key(BUILD_TILE),{}),{"type":KIND,"owner":ALPHA,"items":{}}),"kit consumed, object on the home layer")
	expect(not w.blocked(BUILD_TILE) and w.can_stand(Vector2(BUILD_TILE)+Vector2(0.5,0.5)),"plaque is walk-through")
	refuse(w,ALPHA,"build",MOVE_TILE,KIND,"","second plaque without a kit")
	ok(w,ALPHA,"move_object",BUILD_TILE,"%d,%d"%[MOVE_TILE.x,MOVE_TILE.y],"alpha moves the plaque")
	expect(w.state.objects.has(World.key(MOVE_TILE)) and not w.state.objects.has(World.key(BUILD_TILE)),"plaque moved")
	put(w,BETA,HOME_SPOT,"home")
	refuse(w,BETA,"remove",MOVE_TILE,"","","beta cannot remove alpha's plaque")
	ok(w,ALPHA,"remove",MOVE_TILE,"","alpha picks the plaque up")
	expect(int(bag.get(KIT,0))==1 and not w.state.objects.has(World.key(MOVE_TILE)),"removal returns the kit")
	# Chest storage.
	bag["wood"]=int(bag.get("wood",0))+20
	ok(w,ALPHA,"build",CHEST_TILE,"chest","alpha builds a shared chest")
	ok(w,ALPHA,"deposit",CHEST_TILE,KIT,"plaque kit goes into the chest")
	expect(int(bag.get(KIT,0))==0 and int(w.state.objects[World.key(CHEST_TILE)].items.get(KIT,0))==1,"kit stored in the chest")
	ok(w,ALPHA,"withdraw",CHEST_TILE,KIT,"plaque kit comes back out")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the plaque again (stays for the save test)")

func check_not_currency(w:World) -> void:
	w.state["board"]=true
	put(w,BETA,Vector2(40.5,30.5),"home")
	pl(w,BETA).inventory["soup"]=2
	pl(w,BETA).inventory["bread"]=1
	ok(w,BETA,"picnic",Vector2i(40,29),"","beta holds the picnic (unlocks shipping/market)")
	expect(int(pl(w,BETA).inventory.get(KIT,0))==1,"beta holds a kit")
	put(w,BETA,Vector2(43.5,30.5),"home")
	refuse(w,BETA,"sell",Vector2i(43,29),KIT,"這件商品尚未上架","sell the kit at the seed shop")
	var box:=World.SHIPPING.cell_for(w.state)
	put(w,BETA,Vector2(box)+Vector2(0.5,1.5),"home")
	refuse(w,BETA,"ship",box,JSON.stringify([[[KIT,1]],10]),"","ship the kit")
	var stall:=Market.cell_for(w.state)
	put(w,BETA,Vector2(stall)+Vector2(1.5,0.5),"home")
	refuse(w,BETA,"market_stock",stall,KIT+":1","","stock the kit on the market stall")
	put(w,BETA,HOME_SPOT,"home")

# ------------------------------------------------------------------- saves --

func check_save_reload(w:World,path:String) -> void:
	expect(w.save(),"final world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"fresh World reloads the save")
	for field in [Revisit.STATE_KEY,"history_memory","lanyang_life","objects"]:
		expect(same(reloaded.state.get(field),w.state.get(field)),"state.%s equal after reload"%field)
	for token in [ALPHA,BETA,LATE]:
		expect(same(reloaded.state.players[token].inventory,pl(w,token).inventory),"%s bag equal after reload"%token.left(14))
	put(reloaded,LATE,Vector2(32.5,29.5),"lanyang")
	refuse(reloaded,LATE,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.CLAIMED,"claims survive reload")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"saved world parses and validates"):return
	var fixture:=temp_path("fixture")
	var old:Dictionary=base.duplicate(true)
	old.erase(Revisit.STATE_KEY)
	old.objects.erase(World.key(BUILD_TILE))
	expect(validates(old) and write_json(fixture,old) and World.new().load_world(fixture),"old-shape save without lanyang_revisit (and no plaque placed) loads")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["record is a list","record is null","record missing claimed","record extra key","gates size 3","gate level 4","gate fractional",
		"gate string","day zero","day in the future","unknown field","duplicate field","completed with two checks","three checks not completed",
		"checks with gates off-season","checks on a rainy day","claimed before completion","claimed by a stranger","claim value false",
		"claimer without own memory","record without the plaque","plaque placed without completion","diversion gate without completion","completed is a string"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	expect(labels.size()>=15,"at least 15 tamper cases (%d)"%labels.size())
	var control:Dictionary=base.duplicate(true)
	control.players["nomemory-token-1234"]=control.players[BETA].duplicate(true)
	expect(validates(control),"control: the extra memory-less player alone validates (so the claim is what is rejected)")

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var r:Dictionary=s[Revisit.STATE_KEY]
	match label:
		"record is a list":s[Revisit.STATE_KEY]=[r]
		"record is null":s[Revisit.STATE_KEY]=null
		"record missing claimed":r.erase("claimed")
		"record extra key":r["by"]=ALPHA
		"gates size 3":r.gates=[3,2,0]
		"gate level 4":r.gates=[4,2]
		"gate fractional":r.gates=[3,1.5]
		"gate string":r.gates=["3",2]
		"day zero":r.day=0
		"day in the future":r.day=int(Weather.day_index(float(s.time)))+2
		"unknown field":r.checked=["upstream","middle","river"]
		"duplicate field":r.checked=["upstream","middle","middle"]
		"completed with two checks":r.checked=["upstream","middle"]
		"three checks not completed":
			r.completed=false
			r.claimed={}
		"checks with gates off-season":r.gates=[2,1]
		"checks on a rainy day":
			s.time=4*DAY+10.0
			r.day=3
		"claimed before completion":
			r.completed=false
			r.checked=["upstream"]
		"claimed by a stranger":r.claimed["stranger-token-0000"]=true
		"claim value false":r.claimed[ALPHA]=false
		"claimer without own memory":
			s.players["nomemory-token-1234"]=s.players[BETA].duplicate(true)
			r.claimed["nomemory-token-1234"]=true
		"record without the plaque":
			s.history_memory.plaque=false
		"plaque placed without completion":
			s.erase(Revisit.STATE_KEY)
		"diversion gate without completion":
			s.erase(Revisit.STATE_KEY)
			s.objects.erase(World.key(BUILD_TILE))
			s.objects[World.key(BUILD_TILE)]={"type":"diversion_gate","owner":ALPHA,"items":{},"mode":"open"}
		"completed is a string":r.completed="true"
	return s

# ---------------------------------------------------------------- snapshot --

func check_snapshot(w:World) -> void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	var keep:=w.save_path
	w.save_path=""
	w.add_player("revisit-gamma-token-77aa","Gamma")
	session.peers={1:ALPHA,2:"revisit-gamma-token-77aa"}
	var tokens:=[ALPHA,BETA,LATE,"revisit-gamma-token-77aa"]
	for region in ["home","lanyang"]:
		var public:Dictionary=session.public_state(region)
		var rec:Variant=public.get(Revisit.STATE_KEY)
		expect(rec is Dictionary and same(rec,{"gates":[3,2],"day":2,"checked":["upstream","middle","tail"],"completed":true}),"public_state(%s) carries gates/day/checked/completed only"%region)
		var text:=JSON.stringify(public)
		var leaked:=false
		for token:String in tokens:
			if text.contains(token):leaked=true
		expect(not leaked,"public_state(%s) contains no raw player token"%region)
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.get(Revisit.STATE_KEY,{}).get("claimed_own")==true and not snap[Revisit.STATE_KEY].has("claimed"),"alpha's snapshot: own claim flag only")
	expect(Revisit.claimed_own(snap) and Revisit.tech_unlocked(snap) and Revisit.claim_block(snap,{})!="","client helpers on alpha's snapshot")
	var dump:=JSON.stringify(snap)
	var leaked2:=false
	for token:String in tokens:
		if dump.contains(token):leaked2=true
	expect(not leaked2,"alpha's snapshot contains no raw token")
	session.peers={1:"revisit-gamma-token-77aa"}
	session._send_snapshot(1)
	var gamma_snap:Dictionary=session.snapshot
	expect(gamma_snap.get(Revisit.STATE_KEY,{}).get("claimed_own")==false and not gamma_snap[Revisit.STATE_KEY].has("claimed"),"gamma's snapshot: completion visible, own flag false, no claim map")
	expect(Revisit.claim_block(gamma_snap,{})==Revisit.NOT_READY,"gamma (no own memory) sees NOT_READY on the client")
	var fresh:=World.new()
	fresh.add_player("solo-token-123456","Solo")
	session.world=fresh
	session.peers={1:"solo-token-123456"}
	expect(not session.public_state("home").has(Revisit.STATE_KEY),"a world without the record publishes no lanyang_revisit key")
	session._send_snapshot(1)
	expect(not session.snapshot.has(Revisit.STATE_KEY),"no record: snapshot has no lanyang_revisit")
	session.world=null
	session.queue_free()
	w.save_path=keep
	w.state.players.erase("revisit-gamma-token-77aa")

# ----------------------------------------------------------------- seasons --

func check_seasons() -> void:
	var order:=["spring","summer","autumn","winter"]
	for i in order.size():
		var season:String=order[i]
		var w:=earned_world()
		if not expect(w!=null,"%s: earned fixture (repair + memory + plaque)"%season):continue
		set_day(w,int(SEASON_DAYS[season]))
		expect(Revisit.season(w.state)==season and not Revisit.raining(w.state),"%s: premise day %d is %s and dry"%[season,int(SEASON_DAYS[season])+1,season])
		expect(Revisit.demand(w.state)==Revisit.demand_for(season),"%s: demand %s"%[season,str(Revisit.demand(w.state))])
		# Previous season's gates are wrong now.
		var wrong:Array=SEASON_GATES[order[(i+3)%4]]
		gate(w,ALPHA,"a",int(wrong[0]),"%s: off-season gate a"%season)
		gate(w,ALPHA,"b",int(wrong[1]),"%s: off-season gate b"%season)
		var split:=Memory.distribution(wrong)
		var need:=Revisit.demand_for(season)
		var bad_field:=""
		for f in 3:
			if int(split[f])!=int(need[f]):
				bad_field=Revisit.FIELDS[f]
				var cell:Vector2i=Revisit.FIELD_CELLS[bad_field]
				beside(w,ALPHA,cell)
				refuse(w,ALPHA,Revisit.CHECK_ACTION,cell,"",Revisit.WRONG_SHARE%[Revisit.FIELD_NAMES[bad_field],int(split[f]),int(need[f])],"%s: off-season split refused at %s"%[season,bad_field])
				break
		expect(not bad_field.is_empty(),"%s: the previous season's split differs somewhere"%season)
		var right:Array=SEASON_GATES[season]
		if int(right[0])!=int(wrong[0]):gate(w,ALPHA,"a",int(right[0]),"%s: gate a"%season)
		if int(right[1])!=int(wrong[1]):gate(w,ALPHA,"b",int(right[1]),"%s: gate b"%season)
		for field:String in Revisit.FIELDS:check(w,ALPHA,field,"%s: check %s"%[season,field])
		expect(Revisit.completed(w.state) and validates(w.state),"%s: completed and the state validates"%season)
