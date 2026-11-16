extends SceneTree
## 第 40 章北門合作鹽田「儲滷槽」(scripts/salt_brine.gd) rules test.
## Headless, World-level (World.act / World.step / save / load_world) plus an in-process
## Session for the client-shaped snapshot. No network (see test_salt_brine_session.gd).
##
## EARNED through real World.act / World.step: every player's salt letter (at 小栗's stall),
## the trip home → 田尾 → 北門 by `transit`, salt_intro with 阿曬, the three gate repairs
## (salt_gate_give), every first hand rake (salt_flood on a public pan, World.step until the
## salt crystallises, salt_rake), every salt_claim of a private lot and of the apprentice
## station, every salt_install (wheel / collector), the chest build + salt_auto_cfg +
## salt_auto_toggle, every wheel refill and crystallisation (World.step), every hand rake of a
## wheel pan, and EVERY salt_brine_store / salt_brine_pour (all brine progress in the pans is
## made by the real lazy time model; no pan p/t is ever written in the World tests).
## WRITTEN DIRECTLY (disclosed): chapter_one.shipped/watered, board=true, picnic=true, the
## finished chapter-2 tea record and chapter-3 flower record + completed shared garden and
## travel_book.visited.tianwei (the same FIXTURE as test_salt_pan_world), the gate materials
## (plank/resin/stone), the machine kits (salt_wheel_kit / salt_rake_kit, not crafted here),
## wood/stone for the chest, standing spots (player region/x/y teleports, region "home" for
## WRONG_REGION), ONE forward jump of state.time by 2 s (a pan that the lazy model says has
## crystallised while the stored record still reads "brine"), the 8 filler owners of the
## private lots in the apprentice world (lots[i].owner written; fillers have no salt record),
## the pure-module dictionaries (module checks write pan / level values on COPIES of the
## world state), and the tampered / legacy save files.
## Two identical worlds (section 5) are made by saving one earned world and loading it twice.
const World=preload("res://scripts/world.gd")
const SB=preload("res://scripts/salt_brine.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Transit=preload("res://scripts/transit.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const ALPHA:="saltbrine-alpha-token-5c1e"
const BETA:="saltbrine-beta-token-9a07"
const CAROL:="saltbrine-carol-token-33d4"
const NOBODY:="saltbrine-nobody-token-0000"
const STALL:=Vector2i(43,29)
const HOME_SPOT:=Vector2(39.5,33.5)
const DAY:=1440.0

var checks:=0
var failures:=0
var serial:=0
var temp_files:=[]
var view_session:Session=null

func expect(value:bool,message:String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize() -> void:
	check_static()
	check_site()
	check_main()
	check_feature()
	check_apprentice()
	if view_session!=null:
		view_session.world=null
		view_session.queue_free()
		view_session=null
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("SALT_BRINE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("salt-brine-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

func at_tank(w:World,token:String) -> void:
	put(w,token,SB.TANK_STAND,SB.REGION)

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"saltbrine-req-%d"%serial,action,p,extra)

## Rejected with the exact message and the whole world state byte-identical.
func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and str(r.get("message",""))==message,"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

## Both actions refused with the same message at the tank.
func refuse_both(w:World,token:String,extra:String,message:String,label:String) -> void:
	refuse(w,token,SB.STORE_ACTION,SB.TANK,extra,message,label+" (store)")
	refuse(w,token,SB.POUR_ACTION,SB.TANK,extra,message,label+" (pour)")

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## The JSON shape World.save() would write for the current state.
func shape(w:World) -> Dictionary:
	var parsed:Variant=JSON.parse_string(JSON.stringify(w.state))
	return parsed if parsed is Dictionary else {}

func give(w:World,token:String,item:String,count:int) -> void:
	var bag:Dictionary=pl(w,token).inventory
	bag[item]=int(bag.get(item,0))+count

func held(w:World,token:String,item:String) -> int:
	return int(pl(w,token).inventory.get(item,0))

func now(w:World) -> float:
	return float(w.state.time)

func pan(w:World,i:int) -> Dictionary:
	return w.state.salt_pan.pans[i]

func progress(w:World,i:int) -> float:
	return float(SB.pan_progress(w.state,i).p)

func step_to(w:World,target:float,chunk:float=600.0) -> bool:
	while now(w)<target:
		var dt:=minf(chunk,target-now(w))
		if not w.step(dt,true):return false
	return now(w)==target

## 48·level + Σ integrated pan progress over all 20 pans (salt pans count as NEED).
func tank_total(s:Dictionary) -> float:
	var total:=SB.BUCKET*float(SB.level(s))
	for i in Salt.PAN_COUNT:
		total+=float(SB.pan_progress(s,i).p)
	return total

func others_same(before:Array,after:Array,skip:int) -> bool:
	if before.size()!=after.size():return false
	for i in before.size():
		if i==skip:continue
		if not same(before[i],after[i]):return false
	return true

# --------------------------------------------------- earned salt prerequisites --

## FIXTURE (as test_salt_pan_world): chapter 1, chapter 2 tea comparison, chapter 3 flowers.
func story_fixture(w:World,token:String) -> void:
	w.state.picnic=true
	w.state.board=true
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	var tea:Dictionary=Tea.FRESH.duplicate(true)
	tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1
	tea.trials={"jar":true,"fiber":true};tea.tea_discussed=true;tea.comparison_complete=true
	w.state.tea_ceramics.players[token]=tea
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	w.state.flower_nursery.players[token]=a
	w.state.players[token].travel_book.visited[Flower.REGION]=true
	if not w.state.flower_nursery.get("garden",{}).get("complete",false):
		w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{token:10},"complete":true,"completed_at":0.0}

## FIXTURE teleport: nearest standable spot (0.9..2.9 tiles) of `cell` in the player's region.
func stand(w:World,token:String,cell:Vector2i) -> bool:
	var region:String=w.player_region(token)
	w.switch_region(region)
	var best:=Vector2.ZERO
	var best_d:=INF
	var centre:=Vector2(cell)+Vector2(0.5,0.5)
	for dy in range(-3,4):
		for dx in range(-3,4):
			var pos:=Vector2(cell.x+dx,cell.y+dy)+Vector2(0.5,0.5)
			var d:=pos.distance_to(centre)
			if d<0.9 or d>2.9:continue
			if w.can_stand(pos) and d<best_d:
				best=pos
				best_d=d
	w.switch_region("home")
	if best_d==INF:return false
	pl(w,token).x=best.x
	pl(w,token).y=best.y
	return true

func step_ok(label:String,r:Dictionary) -> bool:
	if not r.get("ok",false):push_error("salt chain step %s failed: %s"%[label,str(r.get("message",""))])
	return bool(r.get("ok",false))

func travel(w:World,token:String,destination:String) -> bool:
	var points:Dictionary=Transit.points(w.player_region(token))
	if points.is_empty():return false
	var cell:Vector2i=points[points.keys()[0]].cell
	if not stand(w,token,cell):return false
	return step_ok("transit "+destination,act(w,token,"transit",cell,destination)) and w.player_region(token)==destination

## Earned: letter at 小栗's stall, home → 田尾 → 北門 by transit, salt_intro with 阿曬.
func arrive(w:World,token:String) -> bool:
	story_fixture(w,token)
	put(w,token,Vector2(STALL)+Vector2(0.5,1.5),"home")
	if not step_ok("salt_letter",act(w,token,"salt_letter",STALL)):return false
	if not travel(w,token,Flower.REGION) or not travel(w,token,Salt.REGION):return false
	if not stand(w,token,Salt.SALT_WORKER):return false
	return step_ok("salt_intro",act(w,token,"salt_intro",Salt.SALT_WORKER))

## Earned donations (materials written): all three gates repaired.
func repair_gates(w:World,token:String) -> bool:
	give(w,token,"plank",18)
	give(w,token,"resin",3)
	give(w,token,"stone",12)
	for g in Salt.GATE_ROWS.size():
		var cell:=Vector2i(8,int(Salt.GATE_ROWS[g])+1)
		if not stand(w,token,cell):return false
		for item in Salt.GATE_MATERIALS:
			if not step_ok("salt_gate_give",act(w,token,"salt_gate_give",cell,item)):return false
	return Salt.repaired(w.state)

## Earned: each token floods one public pan (16, 17), World.step until salt.
func flood_public(w:World,tokens:Array) -> bool:
	for i in tokens.size():
		var cell:=Salt.pan_rect(Salt.PUBLIC_LOT*2+i).position
		if not stand(w,tokens[i],cell):return false
		if not step_ok("salt_flood",act(w,tokens[i],"salt_flood",cell)):return false
	for n in 60:
		var all_salt:=true
		for i in tokens.size():
			if str(w.state.salt_pan.pans[Salt.PUBLIC_LOT*2+i].s)!="salt":all_salt=false
		if all_salt:return true
		if not w.step(60.0,true):return false
	return false

## Earned hand rake of a public pan (offset 0 → pan 16).
func rake(w:World,token:String,pan_offset:int) -> bool:
	var cell:=Salt.pan_rect(Salt.PUBLIC_LOT*2+pan_offset).position
	if not stand(w,token,cell):return false
	var raked:=int(Salt.own_record(w.state,token).raked)
	var salt:=held(w,token,"sea_salt")
	if not step_ok("salt_rake",act(w,token,"salt_rake",cell)):return false
	return int(Salt.own_record(w.state,token).raked)==raked+1 and held(w,token,"sea_salt")==salt+Salt.YIELD

## Earned hand rake of any pan the player may work.
func rake_pan(w:World,token:String,pan_id:int) -> bool:
	var cell:=Salt.pan_rect(pan_id).position
	if not stand(w,token,cell):return false
	var salt:=held(w,token,"sea_salt")
	return step_ok("salt_rake",act(w,token,"salt_rake",cell)) and held(w,token,"sea_salt")==salt+Salt.YIELD

func claim(w:World,token:String,lot:int) -> bool:
	var cell:=Salt.pan_rect(lot*2).position
	return stand(w,token,cell) and step_ok("salt_claim",act(w,token,"salt_claim",cell)) and Salt.unit_of(w.state,token).index==lot

## Kit WRITTEN, install EARNED.
func install_wheel(w:World,token:String,lot:int) -> bool:
	give(w,token,"salt_wheel_kit",1)
	var cell:=Salt.wheel_socket(lot).position
	if not stand(w,token,cell) or not step_ok("salt_install",act(w,token,"salt_install",cell,"wheel")):return false
	return SB.unit(w.state,token).wheel==true

# ------------------------------------------------------- store / pour helpers --

func brine_ok(w:World,token:String,action:String,side:String,label:String) -> Dictionary:
	var total:=tank_total(w.state)
	var t:=now(w)
	var r:=act(w,token,action,SB.TANK,side)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	expect(now(w)==t,"%s: the action does not move time"%label)
	var after:=tank_total(w.state)
	expect(absf(after-total)<1e-9,"%s: conservation 48·level+Σ pan progress %.4f -> %.4f"%[label,total,after])
	return r

## Store from `side` at the tank; k = exact buckets expected.
func store(w:World,token:String,side:String,k:int,label:String) -> Dictionary:
	at_tank(w,token)
	var ids:=SB.pan_ids(w.state,token)
	var at:=SB.SIDES.find(side)
	if not expect(ids.size()==2 and at>=0,"%s: actor has a unit"%label):return {}
	var pid:=int(ids[at])
	var pans_before:Array=(w.state.salt_pan.pans as Array).duplicate(true)
	var old:Dictionary=pan(w,pid).duplicate(true)
	var cur:=progress(w,pid)
	var held_before:=SB.level(w.state)
	var rainy:=SB.rainy_now(w.state)
	var t:=now(w)
	var r:=brine_ok(w,token,SB.STORE_ACTION,side,label)
	if not bool(r.get("ok",false)):return r
	var want:=SB.STORE_OK%[k,held_before+k]+(SB.STORE_RAIN_NOTE if rainy else "")
	expect(str(r.message)==want,"%s: message '%s' (got '%s')"%[label,want,str(r.message)])
	expect(SB.level(w.state)==held_before+k and typeof(w.state[SB.STATE_KEY].level)==TYPE_INT and w.state[SB.STATE_KEY].size()==1,"%s: level %d -> %d (int, single key)"%[label,held_before,held_before+k])
	var now_pan:Dictionary=pan(w,pid)
	expect(float(now_pan.p)==cur-SB.BUCKET*float(k) and float(now_pan.t)==t,"%s: pan %d p %.3f -> %.3f exactly, t = now"%[label,pid,cur,float(now_pan.p)])
	expect(str(now_pan.s)=="brine" and str(old.s)=="brine" and str(now_pan.f)==str(old.f) and now_pan.size()==4,"%s: pan stays brine, s/f unchanged"%label)
	expect(others_same(pans_before,w.state.salt_pan.pans,pid),"%s: the other 19 pans are untouched"%label)
	return r

## Pour into `side` at the tank; k = exact buckets expected.
func pour(w:World,token:String,side:String,k:int,label:String) -> Dictionary:
	at_tank(w,token)
	var ids:=SB.pan_ids(w.state,token)
	var at:=SB.SIDES.find(side)
	if not expect(ids.size()==2 and at>=0,"%s: actor has a unit"%label):return {}
	var pid:=int(ids[at])
	var pans_before:Array=(w.state.salt_pan.pans as Array).duplicate(true)
	var old:Dictionary=pan(w,pid).duplicate(true)
	var cur:=progress(w,pid)
	var held_before:=SB.level(w.state)
	var t:=now(w)
	var r:=brine_ok(w,token,SB.POUR_ACTION,side,label)
	if not bool(r.get("ok",false)):return r
	var after_p:=cur+SB.BUCKET*float(k)
	var want:=SB.POUR_OK%[k,int(floorf(after_p/SB.BUCKET)),held_before-k]
	expect(str(r.message)==want,"%s: message '%s' (got '%s')"%[label,want,str(r.message)])
	expect(SB.level(w.state)==held_before-k and typeof(w.state[SB.STATE_KEY].level)==TYPE_INT,"%s: level %d -> %d"%[label,held_before,held_before-k])
	var now_pan:Dictionary=pan(w,pid)
	expect(float(now_pan.p)==after_p and float(now_pan.t)==t,"%s: pan %d p %.3f -> %.3f exactly, t = now"%[label,pid,cur,float(now_pan.p)])
	expect(float(now_pan.p)<=Salt.NEED-1.0 and str(now_pan.s)=="brine" and str(now_pan.f)==str(old.f),"%s: p <= NEED-1, pan stays a valid brine pan, f unchanged"%label)
	expect(others_same(pans_before,w.state.salt_pan.pans,pid),"%s: the other 19 pans are untouched"%label)
	return r

# ---------------------------------------------------------------- views (9) --

## Pure views on the server state (with token) == the same views on the client-shaped
## snapshot an in-process Session sends to `token`.
func views(w:World,token:String,label:String) -> void:
	if view_session==null:
		view_session=Session.new()
		root.add_child(view_session)
		view_session.set_physics_process(false)
	view_session.world=w
	view_session.peers={1:token}
	view_session._send_snapshot(1)
	var snap:Dictionary=view_session.snapshot
	var tag:="view %s [%s]"%[label,token.left(15)]
	expect(float(snap.get("time",-1.0))==now(w),"%s: snapshot carries the world time"%tag)
	var server_rows:=SB.rows(w.state,token)
	var client_rows:=SB.rows(snap)
	expect(same(server_rows,client_rows),"%s: rows() equal (server %s / client %s)"%[tag,JSON.stringify(server_rows),JSON.stringify(client_rows)])
	var blocks_ok:=true
	for side:String in ["a","b","x",""]:
		if SB.store_block(w.state,side,token)!=SB.store_block(snap,side) or SB.pour_block(w.state,side,token)!=SB.pour_block(snap,side):blocks_ok=false
	expect(blocks_ok,"%s: store_block / pour_block equal for a, b and bad sides"%tag)
	expect(SB.common_block(w.state,token)==SB.common_block(snap),"%s: common_block equal ('%s')"%[tag,SB.common_block(snap)])
	expect(same(SB.unit(w.state,token),SB.unit(snap)) and SB.pan_ids(w.state,token)==SB.pan_ids(snap),"%s: unit / pan_ids equal (%s)"%[tag,str(SB.unit(snap))])
	var progress_ok:=true
	for i in Salt.PAN_COUNT:
		if not same(SB.pan_progress(w.state,i),SB.pan_progress(snap,i)):progress_ok=false
	expect(progress_ok,"%s: pan_progress equal for all 20 pans"%tag)
	expect(SB.level(w.state)==SB.level(snap) and SB.rainy_now(w.state)==SB.rainy_now(snap) and SB.unlocked(w.state)==SB.unlocked(snap) and SB.player_ready(w.state,token)==SB.player_ready(snap),"%s: level / rainy_now / unlocked / player_ready equal"%tag)
	if w.state.has(SB.STATE_KEY):
		var pub:Variant=snap.get(SB.STATE_KEY)
		expect(pub is Dictionary and same(pub,{"level":SB.level(w.state)}) and same(pub,SB.public(w.state)),"%s: snapshot.salt_brine is exactly {level}"%tag)
	else:
		expect(not snap.has(SB.STATE_KEY) and SB.public(w.state).is_empty(),"%s: no record → no salt_brine key"%tag)
	var dump:=JSON.stringify(snap)
	var leaked:=false
	for t:String in [ALPHA,BETA,CAROL]:
		if dump.contains(t):leaked=true
	expect(not leaked,"%s: snapshot contains no raw token"%tag)
	expect(not JSON.stringify(SB.public(w.state)).contains(token),"%s: public() contains no token"%tag)

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(SB.ACTIONS==["salt_brine_store","salt_brine_pour"] and SB.STORE_ACTION=="salt_brine_store" and SB.POUR_ACTION=="salt_brine_pour","action names")
	for action:String in SB.ACTIONS:
		expect(action.length()<=24 and Session.extra_allowed(action,"a") and Session.extra_allowed(action,"b"),"%s passes the Session transport bounds"%action)
		expect(not action in Salt.ACTIONS+SR.ACTIONS+["pick","build","transit"],"%s does not collide with existing actions"%action)
	expect(SB.TANK==Salt.BRINE_TANK and SB.TANK==Vector2i(48,14) and SB.REGION==Salt.REGION,"tank cell = SaltPan.BRINE_TANK in 北門")
	expect(SB.BUCKET==48.0 and SB.CAP==30 and SB.PAN_BUCKETS==10 and SB.BUCKET*float(SB.PAN_BUCKETS)==Salt.NEED and SB.REACH==3.2,"units: 48 per bucket, 10 buckets per pan, 30 in the tank, reach 3.2")
	expect(SB.SIDES==["a","b"] and SB.SIDE_NAMES=={"a":"西側鹽田","b":"東側鹽田"},"sides")
	expect(SB.DISCLAIMER.contains("原創") and SB.DISCLAIMER.contains("非史料"),"original-fiction disclaimer")
	expect(SB.THIN%0=="這方鹽田的滷水還太淡（曬了約 0 成），抽不滿一桶。","THIN text carries the floor tenths")
	expect(SB.TANK_FULL.contains("30／30"),"TANK_FULL names the 30-bucket cap")
	expect(SB.public({}).is_empty() and SB.level({})==0 and SB.valid({}),"no record: public {}, level 0, valid")
	expect(same(SB.public({"salt_brine":{"level":7}}),{"level":7}),"public() is exactly {level}")
	# Client-shaped snapshots (salt_pan.repaired / own.record.raked / own.unit / pans).
	var pans:=[]
	for i in Salt.PAN_COUNT:pans.append(Salt.fresh_pan())
	pans[0]={"s":"brine","p":100.0,"t":0.0,"f":"wheel"}
	var locked:={"time":0.0,"salt_pan":{"repaired":false,"pans":pans,"own":{"record":{"raked":1},"unit":{"kind":"lot","index":0,"wheel":true}}}}
	expect(SB.common_block(locked)==SB.LOCKED and SB.store_block(locked,"a")==SB.LOCKED and SB.pour_block(locked,"a")==SB.LOCKED and not SB.unlocked(locked),"client view: LOCKED before the gates")
	var cold:Dictionary=locked.duplicate(true)
	cold.salt_pan.repaired=true
	cold.salt_pan.own.record.raked=0
	expect(SB.common_block(cold)==SB.NOT_READY and not SB.player_ready(cold),"client view: NOT_READY without a hand rake")
	var no_unit:Dictionary=locked.duplicate(true)
	no_unit.salt_pan.repaired=true
	no_unit.salt_pan.own.unit={"kind":"","index":-1,"wheel":false}
	expect(SB.common_block(no_unit)==SB.NO_UNIT and SB.rows(no_unit).is_empty() and SB.pan_ids(no_unit).is_empty(),"client view: NO_UNIT, no rows")
	var public_lot:Dictionary=no_unit.duplicate(true)
	public_lot.salt_pan.own.unit={"kind":"lot","index":Salt.PUBLIC_LOT,"wheel":true}
	expect(SB.common_block(public_lot)==SB.NO_UNIT and int(SB.unit(public_lot).index)==-1,"client view: the public pool (保留手作池) never counts as a unit")
	var dry:Dictionary=no_unit.duplicate(true)
	dry.salt_pan.own.unit={"kind":"lot","index":0,"wheel":false}
	expect(SB.common_block(dry)==SB.NO_WHEEL,"client view: NO_WHEEL")
	var wet:Dictionary=dry.duplicate(true)
	wet.salt_pan.own.unit.wheel=true
	var rows:=SB.rows(wet)
	expect(rows.size()==2 and rows[0].id=="a" and int(rows[0].pan)==0 and int(rows[0].store)==2 and int(rows[0].pour)==0 and rows[0].pour_block==SB.TANK_EMPTY and rows[0].store_block=="" and int(rows[0].tenths)==2,"client view: rows for a 100-progress pan (store 2, tank empty)")
	expect(rows[1].id=="b" and int(rows[1].pan)==1 and rows[1].store_block==SB.PAN_EMPTY and rows[1].pour_block==SB.PAN_EMPTY,"client view: empty east pan")
	expect(SB.store_block(wet,"c")==SB.BAD_PAN and SB.pour_block(wet,"")==SB.BAD_PAN,"client view: BAD_PAN")
	wet[SB.STATE_KEY]={"level":30}
	expect(SB.store_block(wet,"a")==SB.TANK_FULL and int(SB.rows(wet)[0].pour)==7,"client view: full tank, pour 7 into a 100 pan (floor(379/48))")
	wet["time"]=2.0*DAY+5.0
	wet.salt_pan.pans[0].t=2.0*DAY+5.0
	expect(SB.rainy_now(wet) and SB.pour_block(wet,"a")==SB.RAIN_POUR and SB.store_block(wet,"a")==SB.TANK_FULL,"client view: rainy day → RAIN_POUR")

# ---------------------------------------------------------------- site (10) --

func check_site() -> void:
	expect(Salt.blocked(SB.TANK) and Salt.site_at(SB.TANK)=="brine_tank","SaltPan.blocked(TANK) and site_at(TANK)=='brine_tank'")
	expect(not Salt.blocked(Vector2i(SB.TANK_STAND)),"the tank stand cell is not a SaltPan obstacle")
	var w:=World.new()
	w.switch_region(SB.REGION)
	var start:=Vector2i(Salt.ARRIVAL)
	var seen:={start:true}
	var queue:=[start]
	while not queue.is_empty():
		var c:Vector2i=queue.pop_front()
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var n:=c+d
			if seen.has(n) or n.x<0 or n.y<0 or n.x>=World.SIZE.x or n.y>=World.SIZE.y:continue
			if not w.can_stand(Vector2(n)+Vector2(0.5,0.5)):continue
			seen[n]=true
			queue.append(n)
	expect(w.can_stand(Salt.ARRIVAL),"the bus arrival is standable")
	expect(w.can_stand(SB.TANK_STAND) and seen.has(Vector2i(SB.TANK_STAND)),"TANK_STAND %s is walkable and reachable on foot from the bus arrival"%str(SB.TANK_STAND))
	expect(SB.TANK_STAND.distance_to(Vector2(SB.TANK)+Vector2(0.5,0.5))<=SB.REACH,"TANK_STAND is within reach of the tank")
	expect(w.blocked(SB.TANK) and w.protected(SB.TANK) and not seen.has(SB.TANK),"the tank blocks walking and is protected")
	expect(Salt.ARRIVAL.distance_to(Vector2(SB.TANK)+Vector2(0.5,0.5))>SB.REACH,"the tank is out of reach of the bus arrival (a walk is needed)")
	w.switch_region("home")

# --------------------------------------------------------------- main world --

func check_main() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.add_player(CAROL,"Carol")
	if not expect(arrive(w,ALPHA) and arrive(w,BETA) and arrive(w,CAROL),"alpha, beta and carol earn the letter, ride to 北門 and meet 阿曬"):return
	# 1. Refusals in check order. Unknown token: World.act's own guard.
	var before:=var_to_bytes(canon(w.state))
	var r0:=act(w,NOBODY,SB.STORE_ACTION,SB.TANK,"a")
	expect(not bool(r0.get("ok",true)) and var_to_bytes(canon(w.state))==before,"unknown token refused by World.act, world byte-identical ('%s')"%str(r0.get("message","")))
	put(w,ALPHA,HOME_SPOT,"home")
	refuse_both(w,ALPHA,"a",SB.WRONG_REGION,"from home before the gates (region is checked before the lock)")
	at_tank(w,ALPHA)
	refuse_both(w,ALPHA,"a",SB.LOCKED,"before the gates")
	views(w,ALPHA,"before the gates")
	expect(SB.common_block(w.state,ALPHA)==SB.LOCKED,"common_block LOCKED on the server state")
	var pre_gate:=shape(w)
	if not expect(repair_gates(w,ALPHA),"alpha repairs the three gates (salt_gate_give)"):return
	at_tank(w,ALPHA)
	refuse_both(w,ALPHA,"a",SB.NOT_READY,"alpha never raked")
	at_tank(w,CAROL)
	refuse_both(w,CAROL,"a",SB.NOT_READY,"carol never raked")
	views(w,CAROL,"gates repaired, never raked")
	var post_gate:=shape(w)
	if not expect(flood_public(w,[ALPHA,BETA]) and rake(w,ALPHA,0) and rake(w,BETA,1),"alpha and beta flood the public pans, World.step until salt, rake by hand"):return
	var start:=now(w)
	expect(Weather.day_index(start)==0.0 and start<=600.0,"premise: first rakes on day 1 (sunny), t=%.0f"%start)
	var p16:=Salt.pan_rect(16).position
	expect(stand(w,CAROL,p16) and bool(act(w,CAROL,"salt_flood",p16).get("ok",false)),"carol floods the public pan 16")
	# Raked, no lot: NO_UNIT. Position checks run before the unit check.
	at_tank(w,ALPHA)
	refuse_both(w,ALPHA,"a",SB.NO_UNIT,"alpha raked but has no lot")
	refuse(w,ALPHA,SB.STORE_ACTION,SB.TANK+Vector2i(0,1),"a",SB.WRONG_CELL,"store at the stand cell instead of the tank")
	refuse(w,ALPHA,SB.POUR_ACTION,Salt.SALT_WORKER,"a",SB.WRONG_CELL,"pour at 阿曬")
	put(w,ALPHA,Salt.ARRIVAL,SB.REGION)
	refuse(w,ALPHA,SB.STORE_ACTION,Salt.SALT_WORKER,"a",SB.WRONG_CELL,"wrong cell from far away (cell before reach)")
	refuse_both(w,ALPHA,"a",SB.TOO_FAR,"from the bus arrival")
	put(w,ALPHA,Vector2(SB.TANK)+Vector2(0.5,0.5+3.25),SB.REGION)
	refuse_both(w,ALPHA,"a",SB.TOO_FAR,"3.25 tiles from the tank")
	put(w,ALPHA,Vector2(SB.TANK)+Vector2(0.5,0.5+3.15),SB.REGION)
	refuse(w,ALPHA,SB.STORE_ACTION,SB.TANK,"a",SB.NO_UNIT,"3.15 tiles is within reach (next check: NO_UNIT)")
	# Claim lots: NO_WHEEL.
	if not expect(claim(w,ALPHA,0) and claim(w,BETA,1),"alpha claims lot 0, beta lot 1 (salt_claim)"):return
	at_tank(w,ALPHA)
	refuse_both(w,ALPHA,"a",SB.NO_WHEEL,"alpha's lot has no wheel")
	at_tank(w,BETA)
	refuse_both(w,BETA,"b",SB.NO_WHEEL,"beta's lot has no wheel")
	views(w,ALPHA,"claimed, no wheel")
	if not expect(install_wheel(w,ALPHA,0) and install_wheel(w,BETA,1),"alpha and beta install wheels (salt_install; kits written)"):return
	expect(same(SB.unit(w.state,ALPHA),{"index":0,"kind":"lot","wheel":true}) and SB.pan_ids(w.state,ALPHA)==[0,1] and SB.pan_ids(w.state,BETA)==[2,3],"units: alpha lot 0 pans 0/1, beta lot 1 pans 2/3")
	at_tank(w,ALPHA)
	for bad:String in ["","c","A","a ","ab","west","0"]:
		refuse_both(w,ALPHA,bad,SB.BAD_PAN,"malformed side '%s'"%bad)
	expect(str(pan(w,0).s)=="empty" and str(pan(w,1).s)=="empty","premise: the wheel has not run yet")
	refuse_both(w,ALPHA,"a",SB.PAN_EMPTY,"empty west pan")
	# 2. The wheels fill all four pans at the start of the next tick (day 1, sunny).
	var fill:=now(w)
	expect(step_to(w,fill+30.0),"World.step 30 s")
	for i in 4:expect(same(pan(w,i),{"s":"brine","p":0.0,"t":fill,"f":"wheel"}),"wheel filled pan %d at %.0f (%s)"%[i,fill,str(pan(w,i))])
	at_tank(w,ALPHA)
	refuse(w,ALPHA,SB.STORE_ACTION,SB.TANK,"a",SB.THIN%0,"30 progress is less than a bucket (THIN, floor tenths 0)")
	refuse(w,ALPHA,SB.POUR_ACTION,SB.TANK,"a",SB.TANK_EMPTY,"pour with no record (TANK_EMPTY)")
	expect(not w.state.has(SB.STATE_KEY),"no record before the first successful store")
	expect(step_to(w,fill+300.0),"World.step to 300 s of sun")
	for i in 4:expect(progress(w,i)==300.0 and float(pan(w,i).p)==0.0,"pan %d: lazy progress 300 while the record still says p=0"%i)
	views(w,ALPHA,"300 s of sun")
	views(w,BETA,"300 s of sun")
	expect(int(SB.rows(w.state,ALPHA)[0].store)==6 and SB.rows(w.state,ALPHA)[0].pour_block==SB.TANK_EMPTY,"rows: alpha can store 6 buckets")
	# Mixed scripted sequence (conservation checked at every action instant).
	store(w,ALPHA,"a",6,"alpha stores 6 buckets from pan 0")
	expect(float(pan(w,0).p)==12.0 and same(w.state[SB.STATE_KEY],{"level":6}),"pan 0 keeps 12, tank level 6")
	store(w,BETA,"a",6,"beta's side a is her own pan 2")
	expect(float(pan(w,2).p)==12.0 and float(pan(w,0).p)==12.0 and float(pan(w,1).p)==0.0 and SB.level(w.state)==12,"beta's store touched pan 2 only; one shared level 12")
	pour(w,ALPHA,"b",3,"alpha pours into her east pan (capped by NEED-1: floor(179/48)=3)")
	expect(float(pan(w,1).p)==444.0 and SB.level(w.state)==9,"pan 1 at 444, leftover 9 stays in the tank")
	at_tank(w,ALPHA)
	refuse(w,ALPHA,SB.POUR_ACTION,SB.TANK,"b",SB.PAN_RICH,"pan 1 is almost salt (PAN_RICH)")
	pour(w,BETA,"b",3,"beta pours the shared brine into her pan 3")
	expect(SB.level(w.state)==6 and float(pan(w,3).p)==444.0,"level 6 after beta's pour")
	expect(step_to(w,fill+719.0),"World.step to 719 s")
	expect(str(pan(w,1).s)=="salt" and float(pan(w,1).t)==fill+336.0 and str(pan(w,3).s)=="salt","pans 1 and 3 crystallised exactly 36 s after the pours (444 → 480)")
	at_tank(w,ALPHA)
	refuse_both(w,ALPHA,"b",SB.PAN_SALT,"stored salt in pan 1")
	expect(progress(w,0)==431.0,"premise: pan 0 at 431")
	pour(w,ALPHA,"a",1,"one bucket lands exactly on NEED-1")
	expect(float(pan(w,0).p)==Salt.NEED-1.0 and str(pan(w,0).s)=="brine","pan 0 is a valid brine pan at 479")
	at_tank(w,ALPHA)
	refuse(w,ALPHA,SB.POUR_ACTION,SB.TANK,"a",SB.PAN_RICH,"479 cannot take another bucket")
	# WRITTEN: time +2 s without a World.step; the stored record still says brine.
	w.state["time"]=now(w)+2.0
	expect(str(pan(w,0).s)=="brine" and str(SB.pan_progress(w.state,0).s)=="salt","premise: pan 0 lazily crystallised (record brine, advance salt)")
	refuse_both(w,ALPHA,"a",SB.PAN_SALT,"lazily crystallised brine pan")
	views(w,ALPHA,"lazily crystallised pan")
	# Carol: public pool only.
	if expect(rake(w,CAROL,0),"carol rakes the public pan by hand"):
		expect(stand(w,CAROL,p16) and bool(act(w,CAROL,"salt_flood",p16).get("ok",false)),"carol refloods the public pan (brine in the manual pool)")
	at_tank(w,CAROL)
	refuse_both(w,CAROL,"a",SB.NO_UNIT,"carol works only the public pool")
	refuse(w,CAROL,SB.STORE_ACTION,SB.TANK,"b",SB.NO_UNIT,"carol cannot reach alpha's or beta's pans")
	expect(SB.rows(w.state,CAROL).is_empty() and SB.common_block(w.state,CAROL)==SB.NO_UNIT,"carol: no rows, NO_UNIT")
	views(w,CAROL,"public pool only")
	# Day 2 (cloudy): hand-rake the four lot pans; credit still counts them as wheel pans.
	expect(Weather.outdoor_id(Weather.day_index(2000.0))=="cloudy","premise: t=2000 is day 2 (cloudy)")
	expect(step_to(w,2000.0),"World.step to t=2000")
	var wr_a:=int(Salt.own_record(w.state,ALPHA).wheel_raked)
	var wr_b:=int(Salt.own_record(w.state,BETA).wheel_raked)
	expect(rake_pan(w,ALPHA,0) and rake_pan(w,ALPHA,1) and rake_pan(w,BETA,2) and rake_pan(w,BETA,3),"the four lot pans are raked by hand (3 salt each)")
	expect(int(Salt.own_record(w.state,ALPHA).wheel_raked)==wr_a+2 and int(Salt.own_record(w.state,BETA).wheel_raked)==wr_b+2,"pans that went through the tank still credit wheel_raked (f stays 'wheel')")
	# Day 3 (rain).
	expect(Salt.raining(2910.0),"premise: t=2910 rains in 北門")
	expect(step_to(w,2910.0),"World.step into the rain")
	for i in 4:expect(progress(w,i)==432.5,"pan %d: 440 by midnight, 432.5 after 30 s of rain"%i)
	views(w,ALPHA,"rain, level 5")
	at_tank(w,ALPHA)
	refuse(w,ALPHA,SB.POUR_ACTION,SB.TANK,"a",SB.RAIN_POUR,"no pouring in the rain")
	store(w,ALPHA,"a",9,"store in the rain (rain note)")
	store(w,BETA,"a",9,"beta stores in the rain")
	store(w,BETA,"b",7,"partial store: only 7 buckets of room")
	expect(SB.level(w.state)==30 and float(pan(w,3).p)==96.5,"tank full at 30; pan 3 keeps the 2-bucket remainder (96.5)")
	at_tank(w,ALPHA)
	refuse(w,ALPHA,SB.STORE_ACTION,SB.TANK,"b",SB.TANK_FULL,"store into a full tank")
	refuse(w,ALPHA,SB.POUR_ACTION,SB.TANK,"b",SB.RAIN_POUR,"pour from a full tank in the rain")
	views(w,ALPHA,"full tank in the rain")
	# Day 4 (sunny): pour back, both pans, two players, leftovers stay.
	expect(not Salt.raining(4330.0) and Weather.outdoor_id(Weather.day_index(4330.0))=="sunny","premise: t=4330 is sunny")
	expect(step_to(w,4330.0),"World.step through the rain")
	expect(progress(w,0)==10.0 and progress(w,1)==90.0 and progress(w,2)==10.0 and progress(w,3)==10.0,"after the rain: pans 10 / 90 / 10 / 10 (got %.2f %.2f %.2f %.2f)"%[progress(w,0),progress(w,1),progress(w,2),progress(w,3)])
	pour(w,ALPHA,"a",9,"alpha pours 9 into pan 0")
	pour(w,BETA,"b",9,"beta pours 9 into pan 3")
	pour(w,ALPHA,"b",8,"alpha pours 8 into pan 1 (floor(389/48))")
	pour(w,BETA,"a",4,"beta takes the last 4")
	expect(w.state.has(SB.STATE_KEY) and SB.level(w.state)==0,"the record stays with level 0")
	at_tank(w,BETA)
	refuse(w,BETA,SB.POUR_ACTION,SB.TANK,"a",SB.TANK_EMPTY,"pour from a level-0 tank")
	var level0:=shape(w)
	store(w,ALPHA,"a",9,"alpha stores 9 again (pan 0 back to 10)")
	views(w,ALPHA,"end")
	views(w,BETA,"end")
	check_module(w)
	check_saves(w,pre_gate,post_gate,level0)

# ------------------------------------------------------------ pure module --

func check_module(w:World) -> void:
	var s:Dictionary=w.state.duplicate(true)
	var before:=var_to_bytes(s)
	expect(str(SB.apply(s,NOBODY,SB.STORE_ACTION,SB.TANK,"a","beimen").message)==SB.NO_PLAYER and var_to_bytes(s)==before,"module: NO_PLAYER, nothing written")
	expect(str(SB.apply(s,ALPHA,"salt_rake",SB.TANK,"a","beimen").message)==SB.BAD_EXTRA and var_to_bytes(s)==before,"module: foreign action BAD_EXTRA")
	for bad:Variant in [{"level":1.5},{"level":"3"},{"level":31},{"level":-1},{"level":3,"by":ALPHA},{},[3],null]:
		var t:Dictionary=s.duplicate(true)
		t[SB.STATE_KEY]=bad
		var tb:=var_to_bytes(t)
		expect(str(SB.apply(t,ALPHA,SB.STORE_ACTION,SB.TANK,"a","beimen").message)==SB.BAD_EXTRA and var_to_bytes(t)==tb,"module: corrupt record %s refused without writing"%JSON.stringify(bad))
	var future:Dictionary=s.duplicate(true)
	future.salt_pan.pans[0].t=float(future.time)+100.0
	var fb:=var_to_bytes(future)
	expect(str(SB.apply(future,ALPHA,SB.STORE_ACTION,SB.TANK,"a","beimen").message)==SB.BAD_EXTRA and var_to_bytes(future)==fb,"module: pan time in the future refused")
	# Written pans on copies: exact edges.
	var e:Dictionary=s.duplicate(true)
	e.salt_pan.pans[0]={"s":"brine","p":431.0,"t":float(e.time),"f":"wheel"}
	var r:=SB.apply(e,ALPHA,SB.POUR_ACTION,SB.TANK,"a","beimen")
	expect(bool(r.ok) and float(e.salt_pan.pans[0].p)==479.0 and SB.level(e)==8 and str(r.message)==SB.POUR_OK%[1,9,8],"module: 431 + one bucket = 479 = NEED-1 (%s)"%str(r.message))
	e.salt_pan.pans[0]={"s":"brine","p":431.5,"t":float(e.time),"f":"wheel"}
	expect(str(SB.apply(e,ALPHA,SB.POUR_ACTION,SB.TANK,"a","beimen").message)==SB.PAN_RICH,"module: 431.5 is PAN_RICH")
	e.salt_pan.pans[0]={"s":"brine","p":47.9,"t":float(e.time),"f":"hand"}
	expect(str(SB.apply(e,ALPHA,SB.STORE_ACTION,SB.TANK,"a","beimen").message)==SB.THIN%0,"module: 47.9 is THIN")
	e.salt_pan.pans[0]={"s":"brine","p":96.0,"t":float(e.time),"f":"hand"}
	r=SB.apply(e,ALPHA,SB.STORE_ACTION,SB.TANK,"a","beimen")
	expect(bool(r.ok) and float(e.salt_pan.pans[0].p)==0.0 and e.salt_pan.pans[0].f=="hand" and SB.level(e)==10,"module: 96 → 2 buckets, pan at 0 stays brine with f unchanged")
	e[SB.STATE_KEY]={"level":29}
	e.salt_pan.pans[0]={"s":"brine","p":300.0,"t":float(e.time),"f":"wheel"}
	r=SB.apply(e,ALPHA,SB.STORE_ACTION,SB.TANK,"a","beimen")
	expect(bool(r.ok) and float(e.salt_pan.pans[0].p)==252.0 and SB.level(e)==30 and str(r.message)==SB.STORE_OK%[1,30],"module: one bucket of room → partial store")

# ------------------------------------------------------------------- saves --

func check_saves(w:World,pre_gate:Dictionary,post_gate:Dictionary,level0:Dictionary) -> void:
	var path:=temp_path("main")
	w.save_path=path
	expect(w.save(),"main world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"fresh World reloads the save")
	expect(same(reloaded.state.get(SB.STATE_KEY),w.state.get(SB.STATE_KEY)) and same(reloaded.state.salt_pan,w.state.salt_pan),"salt_brine and salt_pan equal after reload")
	expect(typeof(reloaded.state[SB.STATE_KEY].level)==TYPE_INT and int(reloaded.state[SB.STATE_KEY].level)==9,"reload normalises the JSON level to int 9")
	reloaded.save_path=""
	pour(reloaded,ALPHA,"a",9,"reloaded world: alpha pours the 9 buckets back")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"saved world parses and validates"):return
	expect(typeof(base[SB.STATE_KEY].level)==TYPE_FLOAT,"premise: JSON gives the level as a float")
	var norm:Dictionary=base.duplicate(true)
	expect(Schema.validate(norm,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME) and typeof(norm[SB.STATE_KEY].level)==TYPE_INT,"SaveSchema normalises the float level to int")
	var fixture:=temp_path("fixture")
	var old:Dictionary=base.duplicate(true)
	old.erase(SB.STATE_KEY)
	expect(validates(old) and write_json(fixture,old) and World.new().load_world(fixture),"old save without salt_brine loads")
	expect(level0.get(SB.STATE_KEY) is Dictionary and validates(level0) and write_json(fixture,level0) and World.new().load_world(fixture),"a level-0 record (earned) is legal")
	var zero:Dictionary=base.duplicate(true)
	zero[SB.STATE_KEY]={"level":0}
	expect(validates(zero),"level 0 on the final save validates")
	var full:Dictionary=base.duplicate(true)
	full[SB.STATE_KEY]={"level":30}
	expect(validates(full),"level 30 validates")
	expect(validates(pre_gate) and not pre_gate.has(SB.STATE_KEY),"control: the pre-gate save validates")
	expect(validates(post_gate) and not post_gate.has(SB.STATE_KEY),"control: the gates-repaired, nobody-raked save validates")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var cases:={}
	for v:Variant in [-1,31,1.5,"3",true,null]:
		var t:Dictionary=base.duplicate(true)
		t[SB.STATE_KEY]={"level":v}
		cases["level %s"%JSON.stringify(v)]=t
	var extra:Dictionary=base.duplicate(true)
	extra[SB.STATE_KEY]={"level":3,"by":ALPHA}
	cases["extra key"]=extra
	var missing:Dictionary=base.duplicate(true)
	missing[SB.STATE_KEY]={}
	cases["missing level"]=missing
	var listed:Dictionary=base.duplicate(true)
	listed[SB.STATE_KEY]=[3]
	cases["record is a list"]=listed
	var nulled:Dictionary=base.duplicate(true)
	nulled[SB.STATE_KEY]=null
	cases["record is null"]=nulled
	var locked:Dictionary=pre_gate.duplicate(true)
	locked[SB.STATE_KEY]={"level":0}
	cases["record while the gates are unrepaired"]=locked
	var locked5:Dictionary=pre_gate.duplicate(true)
	locked5[SB.STATE_KEY]={"level":5}
	cases["level 5 while the gates are unrepaired"]=locked5
	var unraked:Dictionary=post_gate.duplicate(true)
	unraked[SB.STATE_KEY]={"level":0}
	cases["record while no player has raked"]=unraked
	for label:String in cases:
		var bad:Dictionary=cases[label]
		expect(not validates(bad),"schema rejects: "+label)
		expect(write_json(fixture,bad) and not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)

# ------------------------------------------------- the point of the feature --

## Earned: alpha arrives, repairs, rakes once, claims lot 0, installs the wheel; the wheel
## fills both pans on day 1 and they crystallise; on day 2 (cloudy) alpha hand-rakes pan 0 at
## t=2280, the wheel refills it and it reaches 295 at t=2870, 10 s before the day-3 rain.
func wheel_base() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	if not arrive(w,ALPHA) or not repair_gates(w,ALPHA) or not flood_public(w,[ALPHA]) or not rake(w,ALPHA,0):return null
	if not claim(w,ALPHA,0) or not install_wheel(w,ALPHA,0):return null
	var fill:=now(w)
	if fill+480.0>2280.0 or not step_to(w,fill+60.0) or not step_to(w,2280.0):return null
	if str(pan(w,0).s)!="salt" or str(pan(w,1).s)!="salt":return null
	if not rake_pan(w,ALPHA,0):return null
	if not step_to(w,2340.0) or not step_to(w,2870.0):return null
	at_tank(w,ALPHA)
	return w

## SaltPan.step over [t0,t1] in one call == many short calls, bit for bit (salt_pan, beimen
## objects, players), on copies of the world state.
func long_short(w:World,t0:float,t1:float,label:String) -> void:
	var s1:Dictionary=w.state.duplicate(true)
	var s2:Dictionary=w.state.duplicate(true)
	var r1:=Salt.step(s1,t0,t1,s1.regions[Salt.REGION].objects)
	var ok2:=true
	var t:=t0
	while t<t1:
		var nxt:=minf(t+37.0,t1)
		if not bool(Salt.step(s2,t,nxt,s2.regions[Salt.REGION].objects).ok):ok2=false
		t=nxt
	expect(bool(r1.ok) and ok2,"%s: both SaltPan.step paths ok"%label)
	expect(var_to_bytes(s1.salt_pan)==var_to_bytes(s2.salt_pan) and var_to_bytes(s1.regions[Salt.REGION].objects)==var_to_bytes(s2.regions[Salt.REGION].objects) and var_to_bytes(s1.players)==var_to_bytes(s2.players),"%s: one long step == many short steps, bit for bit"%label)

func chest_salt(w:World,cell:Vector2i) -> int:
	var obj:Variant=w.state.regions[Salt.REGION].objects.get(World.key(cell))
	if not obj is Dictionary:return -1
	return int(obj.get("items",{}).get("sea_salt",0))

func check_feature() -> void:
	var base:=wheel_base()
	if not expect(base!=null,"feature: earned wheel world (claim, install, refills, hand rake on day 2)"):return
	var path:=temp_path("feature")
	base.save_path=path
	expect(base.save(),"feature: the earned world saves")
	var a:=World.new()
	var b:=World.new()
	if not expect(a.load_world(path) and b.load_world(path),"feature: two identical worlds A and B load from the one save"):return
	a.save_path=""
	b.save_path=""
	expect(same(a.state,b.state),"feature: A and B are identical")
	expect(now(a)==2870.0 and progress(a,0)==295.0 and str(pan(a,0).f)=="wheel" and not SB.rainy_now(a.state) and Salt.raining(2880.0),"premise: pan 0 at 295 on a cloudy evening, rain from t=2880")
	var wr:=int(Salt.own_record(a.state,ALPHA).wheel_raked)
	# A stores before the rain; B does nothing.
	store(a,ALPHA,"a",6,"A: store 6 buckets before the rain")
	long_short(a,2870.0,4400.0,"after the store, across the rain")
	expect(step_to(a,4330.0) and step_to(b,4330.0),"A and B World.step through the rain")
	expect(progress(a,0)==10.0 and progress(b,0)==10.0,"the rain washed both pans down to the same 10 (got A %.2f B %.2f); A's 6 buckets were safe in the tank"%[progress(a,0),progress(b,0)])
	pour(a,ALPHA,"a",6,"A: pour the 6 buckets back after the rain")
	long_short(a,4330.0,6000.0,"after the pour")
	var ta:=float(Salt.advance(pan(a,0).p,pan(a,0).t,4330.0+DAY).at)
	var tb:=float(Salt.advance(pan(b,0).p,pan(b,0).t,4330.0+DAY).at)
	expect(ta==4512.0 and tb==4800.0,"crystallisation: A at %.1f (4330+182), B at %.1f (4320+480)"%[ta,tb])
	expect(ta<tb and tb-ta==SB.BUCKET*6.0/float(Salt.RATES.sunny),"A crystallises earlier by exactly the 6 stored buckets (288 sunny seconds)")
	expect(step_to(a,4600.0) and step_to(b,4600.0),"World.step to 4600")
	expect(str(pan(a,0).s)=="salt" and float(pan(a,0).t)==ta and str(pan(b,0).s)=="brine","at 4600 A's pan is salt (written at %.1f), B's is still brine"%ta)
	expect(step_to(a,4810.0) and step_to(b,4810.0),"World.step to 4810")
	expect(str(pan(b,0).s)=="salt" and float(pan(b,0).t)==tb,"B crystallises at 4800")
	expect(rake_pan(a,ALPHA,0) and rake_pan(b,ALPHA,0),"both worlds: hand rake pan 0 (3 salt)")
	expect(int(Salt.own_record(a.state,ALPHA).wheel_raked)==wr+1 and int(Salt.own_record(b.state,ALPHA).wheel_raked)==wr+1,"wheel_raked credit identical with and without the tank")
	expect(step_to(a,4870.0) and step_to(b,4870.0),"World.step 60 s")
	expect(same(pan(a,0),{"s":"brine","p":0.0,"t":4810.0,"f":"wheel"}) and same(pan(b,0),pan(a,0)),"the wheel refills pan 0 in both worlds at 4810")
	# 7. Collector + chest still behave after store / pour (kits, wood written).
	give(a,ALPHA,"salt_rake_kit",1)
	give(a,ALPHA,"wood",40)
	var rake_cell:=Salt.rake_socket(0).position
	var chest_cell:Vector2i=Salt.chest_sockets(0)[0]
	expect(stand(a,ALPHA,rake_cell) and step_ok("install rake",act(a,ALPHA,"salt_install",rake_cell,"rake")),"A installs the collector")
	expect(stand(a,ALPHA,chest_cell) and step_ok("build chest",act(a,ALPHA,"build",chest_cell,"chest")),"A builds a chest on the lot's chest socket")
	expect(stand(a,ALPHA,rake_cell) and step_ok("auto cfg",act(a,ALPHA,"salt_auto_cfg",rake_cell,"%d,%d|60"%[chest_cell.x,chest_cell.y])) and step_ok("auto toggle",act(a,ALPHA,"salt_auto_toggle",rake_cell)),"A links the chest and switches the collector on")
	var auto_before:=int(Salt.own_record(a.state,ALPHA).auto_raked)
	expect(step_to(a,4880.0),"World.step 10 s")
	expect(chest_salt(a,chest_cell)==3 and int(Salt.own_record(a.state,ALPHA).auto_raked)==auto_before+1,"the collector delivers pan 1's salt: 3 into the chest")
	expect(same(pan(a,1),{"s":"brine","p":0.0,"t":4870.0,"f":"wheel"}),"the wheel refills pan 1 right after the collection")
	store(a,ALPHA,"a",1,"A stores 1 bucket from pan 0 (70)")
	pour(a,ALPHA,"b",1,"A pours it into pan 1 (10 → 58)")
	long_short(a,4880.0,5400.0,"with the collector running")
	expect(step_to(a,5400.0),"World.step to 5400")
	expect(chest_salt(a,chest_cell)==9 and int(Salt.own_record(a.state,ALPHA).auto_raked)==auto_before+3,"each pan still yields exactly 3 salt into the chest (9 total)")
	expect(float(pan(a,1).t)==5302.0 and float(pan(a,0).t)==5338.0 and str(pan(a,0).f)=="wheel" and str(pan(a,1).f)=="wheel" and str(pan(a,0).s)=="brine","collections at exactly 5302 (58 → 480) and 5338 (22 → 480), refilled by the wheel")
	expect(int(Salt.own_record(a.state,ALPHA).wheel_raked)==wr+1,"automation leaves wheel_raked unchanged")
	put(a,ALPHA,SB.TANK_STAND,SB.REGION)
	expect(validates(a.state),"world A (tank used, collector running) validates")

# ------------------------------------------------------- apprentice unit (6) --

func check_apprentice() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	if not expect(arrive(w,ALPHA) and repair_gates(w,ALPHA) and flood_public(w,[ALPHA]) and rake(w,ALPHA,0),"apprentice: alpha earns her first rake"):return
	for i in Salt.LOT_COUNT:
		var filler:="saltbrine-filler-%d-token"%i
		w.add_player(filler,"F%d"%i)
		w.state.salt_pan.lots[i].owner=filler # WRITTEN: every private lot is taken
	var app_cell:=Salt.pan_rect(Salt.APPRENTICE_LOT*2).position
	expect(stand(w,ALPHA,app_cell) and step_ok("apprentice claim",act(w,ALPHA,"salt_claim",app_cell)) and Salt.is_tenant(w.state,ALPHA),"apprentice: alpha takes the apprentice shift (salt_claim)")
	at_tank(w,ALPHA)
	refuse_both(w,ALPHA,"a",SB.NO_WHEEL,"apprentice station without a wheel")
	if not expect(install_wheel(w,ALPHA,Salt.APPRENTICE_LOT),"apprentice: wheel installed on the station"):return
	expect(same(SB.unit(w.state,ALPHA),{"index":Salt.APPRENTICE_LOT,"kind":"apprentice","wheel":true}) and SB.pan_ids(w.state,ALPHA)==[18,19],"apprentice: unit 9, pans 18/19")
	var fill:=now(w)
	expect(step_to(w,fill+200.0),"apprentice: World.step 200 s")
	expect(progress(w,18)==200.0 and progress(w,19)==200.0,"apprentice: both station pans at 200")
	views(w,ALPHA,"apprentice")
	store(w,ALPHA,"a",4,"apprentice: store 4 buckets from pan 18")
	pour(w,ALPHA,"b",4,"apprentice: pour them into pan 19")
	expect(float(pan(w,18).p)==8.0 and float(pan(w,19).p)==392.0 and SB.level(w.state)==0,"apprentice: 200/200 → 8/392 via the tank")
	expect(Salt.is_tenant(w.state,ALPHA),"apprentice: the shift continues")
