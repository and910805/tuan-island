extends SceneTree
## 第 40 章「臺南北門回訪・鹽籃批次」(scripts/salt_revisit.gd) + 鹽籃 rules test.
## Headless, World-level (World.act / World.step / save / load_world) plus an in-process
## Session for the public snapshot. No network.
##
## EARNED through real World.act / World.step: every player's salt letter (at 小栗's stall),
## the trip home → 田尾 → 北門 by `transit`, salt_intro with 阿曬, the three Beimen gate
## repairs (salt_gate_give), every player's first hand rake (salt_flood on a public pan,
## World.step until the salt crystallises, salt_rake = 3 sea_salt and raked 1), every
## salt_revisit_stock / pack / send / claim, every build / move / remove / deposit / withdraw
## of the basket and the chest build.
## WRITTEN DIRECTLY (disclosed): chapter_one.shipped/watered, board=true, picnic=true, the
## finished chapter-2 tea record and chapter-3 flower record + completed shared garden and
## travel_book.visited.tianwei (the same FIXTURE as test_salt_pan_world), standing spots
## (player region/x/y within a region the player really reached; region "home" for the
## wrong-region refusals), the gate materials (plank/resin/stone), the extra sea_salt beyond
## each player's earned 3, all fiber, wood for the chest, state.time jumps forward (day 2
## cloudy, day 3 rainy, day 15 = first day of summer, the season starts), the kit count at
## the 1e9 cap for BAG_FULL, and the tampered / legacy save files.
const World=preload("res://scripts/world.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Transit=preload("res://scripts/transit.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Market=preload("res://scripts/market_stall.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Lanyang=preload("res://scripts/lanyang_revisit.gd")
const ALPHA:="saltrevisit-alpha-token-7e21"
const BETA:="saltrevisit-beta-token-c40a"
const LATE:="saltrevisit-late-token-19bd"
const KIT:="salt_basket_kit"
const KIND:="salt_basket"
const STALL:=Vector2i(43,29)
const HOME_SPOT:=Vector2(39.5,33.5)
const BUILD_TILE:=Vector2i(38,34)
const MOVE_TILE:=Vector2i(37,35)
const CHEST_TILE:=Vector2i(40,35)
const AT_WORKER:=SR.WORKER_STAND
const AT_CHEST:=SR.CHEST_STAND
const AT_STOP:=SR.STOP_STAND
const ARRIVAL:=Vector2(47.5,25.5)
const DAY:=1440.0
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
	check_site()
	var w:=World.new()
	var path:=temp_path("main")
	w.save_path=path
	if main_flow(w,path):
		check_placement(w)
		check_not_currency(w)
		check_save_reload(w,path)
		check_snapshot(w)
	check_seasons()
	check_module()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("SALT_REVISIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("salt-revisit-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

func beimen(w:World,token:String,at:Vector2) -> void:
	put(w,token,at,SR.REGION)

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"saltrevisit-req-%d"%serial,action,p,extra)

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

## Moves time forward only.
func set_day(w:World,day_index:int) -> void:
	var target:=float(day_index)*DAY+30.0
	if target>float(w.state.time):w.state["time"]=target

func give(w:World,token:String,item:String,count:int) -> void:
	var bag:Dictionary=pl(w,token).inventory
	bag[item]=int(bag.get(item,0))+count

func held(w:World,token:String,item:String) -> int:
	return int(pl(w,token).inventory.get(item,0))

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

## Nearest standable spot (0.9..2.9 tiles) of `cell` in the player's current region.
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

func step_ok(w:World,label:String,r:Dictionary) -> bool:
	if not r.get("ok",false):push_error("salt chain step %s failed: %s"%[label,str(r.get("message",""))])
	return bool(r.get("ok",false))

func travel(w:World,token:String,destination:String) -> bool:
	var points:Dictionary=Transit.points(w.player_region(token))
	if points.is_empty():return false
	var cell:Vector2i=points[points.keys()[0]].cell
	if not stand(w,token,cell):return false
	return step_ok(w,"transit "+destination,act(w,token,"transit",cell,destination)) and w.player_region(token)==destination

## Earned: letter at 小栗's stall, home → 田尾 → 北門 by transit, salt_intro with 阿曬.
func arrive(w:World,token:String) -> bool:
	story_fixture(w,token)
	put(w,token,Vector2(STALL)+Vector2(0.5,1.5),"home")
	if not step_ok(w,"salt_letter",act(w,token,"salt_letter",STALL)):return false
	if not travel(w,token,Flower.REGION) or not travel(w,token,Salt.REGION):return false
	if not stand(w,token,Salt.SALT_WORKER):return false
	return step_ok(w,"salt_intro",act(w,token,"salt_intro",Salt.SALT_WORKER))

## Earned donations (materials written): all three gates repaired.
func repair_gates(w:World,token:String) -> bool:
	give(w,token,"plank",18)
	give(w,token,"resin",3)
	give(w,token,"stone",12)
	for g in Salt.GATE_ROWS.size():
		var cell:=Vector2i(8,int(Salt.GATE_ROWS[g])+1)
		if not stand(w,token,cell):return false
		for item in Salt.GATE_MATERIALS:
			if not step_ok(w,"salt_gate_give",act(w,token,"salt_gate_give",cell,item)):return false
	return Salt.repaired(w.state)

## Earned: each token floods one public pan (16, 17), World.step until salt.
func flood_public(w:World,tokens:Array) -> bool:
	for i in tokens.size():
		var cell:=Salt.pan_rect(Salt.PUBLIC_LOT*2+i).position
		if not stand(w,tokens[i],cell):return false
		if not step_ok(w,"salt_flood",act(w,tokens[i],"salt_flood",cell)):return false
	for n in 60:
		var all_salt:=true
		for i in tokens.size():
			if str(w.state.salt_pan.pans[Salt.PUBLIC_LOT*2+i].s)!="salt":all_salt=false
		if all_salt:return true
		if not w.step(60.0,true):return false
	return false

func rake(w:World,token:String,pan_offset:int) -> bool:
	var cell:=Salt.pan_rect(Salt.PUBLIC_LOT*2+pan_offset).position
	if not stand(w,token,cell):return false
	var raked:=int(Salt.own_record(w.state,token).raked)
	var salt:=held(w,token,"sea_salt")
	if not step_ok(w,"salt_rake",act(w,token,"salt_rake",cell)):return false
	return int(Salt.own_record(w.state,token).raked)==raked+1 and held(w,token,"sea_salt")==salt+Salt.YIELD

func earned_world() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	if not arrive(w,ALPHA) or not repair_gates(w,ALPHA) or not flood_public(w,[ALPHA]) or not rake(w,ALPHA,0):return null
	return w

func stock(w:World,token:String,label:String) -> Dictionary:
	beimen(w,token,AT_WORKER)
	return ok(w,token,SR.STOCK_ACTION,SR.WORKER,"",label)

func pack(w:World,token:String,kind:String,label:String) -> Dictionary:
	beimen(w,token,AT_CHEST)
	return ok(w,token,SR.PACK_ACTION,SR.CHEST,kind,label)

func record_is(w:World,sunny:int,cloudy:int,kitchen:int,pickle:int,rain:int,day:int,completed:bool,done_day:int,claimed:Dictionary={}) -> bool:
	return same(w.state.get(SR.STATE_KEY),{"stocked":{"sunny":sunny,"cloudy":cloudy},"packed":{"kitchen":kitchen,"pickle":pickle},"rain_packs":rain,"day":day,"completed":completed,"done_day":done_day,"claimed":claimed})

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(SR.ACTIONS==["salt_revisit_stock","salt_revisit_pack","salt_revisit_send","salt_revisit_claim"],"action names")
	for action:String in SR.ACTIONS:
		expect(action.length()<=24 and Session.extra_allowed(action,"kitchen") and Session.extra_allowed(action,""),"%s passes the Session transport bounds"%action)
		expect(not action in Salt.ACTIONS+TR.ACTIONS+JG.ACTIONS+Lanyang.ACTIONS+World.MEMORY_EXHIBIT.ACTIONS+["pick","build","transit"],"%s does not collide with existing actions"%action)
	var seen_orders:={}
	for season:String in Weather.SEASONS:
		var order:Dictionary=SR.order_for(season)
		expect(order.size()==2 and int(order.kitchen)+int(order.pickle)==SR.TOTAL and int(order.kitchen)>=1 and int(order.pickle)>=1,"%s order is 6 baskets with both kinds (%s)"%[season,str(order)])
		expect(not SR.reason_for(season).is_empty() and SR.reason_for(season).contains("阿曬"),"%s has 阿曬's reason"%season)
		seen_orders[JSON.stringify(order)]=true
	for i in 4:
		expect(SR.order_for(Weather.SEASONS[i])!=SR.order_for(Weather.SEASONS[(i+3)%4]),"%s order differs from the previous season's"%Weather.SEASONS[i])
	expect(seen_orders.size()==4,"four distinct seasonal mixes")
	expect(same(SR.order_for("spring"),{"kitchen":3,"pickle":3}) and same(SR.order_for("summer"),{"kitchen":2,"pickle":4})
		and same(SR.order_for("autumn"),{"kitchen":4,"pickle":2}) and same(SR.order_for("winter"),{"kitchen":5,"pickle":1}),"seasonal order table")
	expect(SR.KIND_NAMES=={"kitchen":"料理用","pickle":"醃漬用"} and SR.KINDS==["kitchen","pickle"],"kinds")
	expect(World.NAMES.get(SR.SALT_ITEM)=="海鹽" and World.NAMES.get(SR.FIBER_ITEM)=="纖維" and SR.LOT_SALT==3 and SR.FIBER_PER_BASKET==2,"materials: 3 sea_salt per lot, 2 fiber per basket")
	expect(SR.DISCLAIMER=="回訪情節與訂單數字為原創，非史料。","original-fiction disclaimer")
	expect(SR.TITLE=="臺南北門回訪・鹽籃批次","title")
	expect(SR.WORKER==Salt.SALT_WORKER and SR.CHEST==Salt.APPRENTICE_CHEST and SR.STOP==Salt.TRANSFER and SR.REGION==Salt.REGION and SR.STOP_STAND==Salt.ARRIVAL,"阿曬 / co-op chest / bus stop are the existing Beimen points")
	expect(SR.stock_cell()==SR.WORKER and SR.claim_cell()==SR.WORKER and SR.pack_cell()==SR.CHEST and SR.send_cell()==SR.STOP,"step cells")
	expect(World.NAMES.get(KIT)=="鹽籃" and World.BUILD.get(KIND)=={"name":"鹽籃",KIT:1},"salt basket kit and build entry")
	expect(SR.BASKET_NAME=="鹽籃" and SR.BASKET_SOURCE=="來源：臺南北門回訪" and SR.BASKET_PROJECT=="對應工程：北門合作鹽田閘門修復" and SR.BASKET_BLURB.contains("籃") and SR.BASKET_BLURB.contains("海鹽"),"provenance constants")
	expect(World.MEMORY_EXHIBIT.EXHIBITS.beimen.name==SR.BASKET_NAME,"the exhibit slot name is the basket name")
	expect(not KIND in World.UNDO_SOLID,"salt basket is walk-through decor")
	expect(World.BUILD.has("tea_ware") and World.NAMES.get("tea_ware_kit")=="茶陶組" and World.BUILD.has("mine_lantern") and World.NAMES.get("sea_salt")=="海鹽","existing ids untouched")
	var prices:=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	expect(not prices.has(KIT) and not World.OTHER_SALES.has(KIT) and not World.CROPS.has(KIT) and not World.FISH.has(KIT),"salt basket kit has no price")
	expect(not Market.sellable(KIT) and not World.trade_items().has(KIT) and World.trade_items().has("wood") and not World.trade_items().has("tea_ware_kit"),"salt basket kit is not stall-listable nor tradeable")
	expect(not World.SHIPPING.quote([[KIT,1]],{KIT:1},prices).ok,"shipping quote refuses the salt basket kit")
	# Client-shaped snapshots (salt_pan.repaired + salt_pan.own.record.raked).
	var locked:={"time":0.0,"salt_pan":{"repaired":false,"own":{"record":{"raked":1}}}}
	expect(not SR.unlocked(locked) and SR.stock_block(locked,{"sea_salt":3})==SR.LOCKED and SR.pack_block(locked,"kitchen",{})==SR.LOCKED and SR.send_block(locked)==SR.LOCKED and SR.claim_block(locked,{})==SR.LOCKED,"view: LOCKED before the gates")
	var cold:={"time":0.0,"salt_pan":{"repaired":true,"own":{"record":{"raked":0}}}}
	expect(SR.unlocked(cold) and not SR.player_ready(cold) and SR.stock_block(cold,{"sea_salt":3})==SR.NOT_READY and SR.pack_block(cold,"kitchen",{})==SR.NOT_READY and SR.send_block(cold)==SR.NOT_READY and SR.claim_block(cold,{})==SR.NOT_READY,"view: NOT_READY without a hand rake")
	expect(not SR.unlocked({"time":0.0}) and not SR.player_ready({"time":0.0}),"view: no salt_pan block")
	var snap:={"time":0.0,"salt_pan":{"repaired":true,"own":{"record":{"raked":1}}}}
	expect(SR.player_ready(snap) and not SR.completed(snap) and SR.order_season(snap)=="spring" and SR.weather_today(snap)=="sunny" and not SR.rainy_today(snap),"view: ready, day 1 sunny spring")
	expect(SR.stock_block(snap,{"sea_salt":2})==SR.NO_SALT%[3,2] and SR.stock_block(snap,{"sea_salt":3})=="","view: stock_block NO_SALT then ok")
	expect(SR.stock_block(snap,{"sea_salt":2})=="入倉一批要海鹽 3 份，你的背包裡有 2 份。","view: NO_SALT text")
	expect(SR.pack_block(snap,"kitchen",{"fiber":2})==SR.NEED_STOCK%[0,0] and SR.pack_block(snap,"salt",{})==SR.BAD_KIND,"view: pack needs a stocked lot")
	expect(SR.send_block(snap)==SR.NOT_PACKED%0 and SR.claim_block(snap,{})==SR.NOT_DONE,"view: send / claim before anything")
	var rain:=snap.duplicate(true)
	rain["time"]=2*DAY+5.0
	expect(SR.rainy_today(rain) and SR.weather_today(rain)=="rainy" and SR.stock_block(rain,{"sea_salt":3})==SR.RAIN_STOCK,"view: RAIN_STOCK on day 3")
	expect(SR.RAIN_STOCK=="下雨天倉棚不收散鹽，怕受潮；已經入倉的鹽可以先裝籃。","rain message text")
	snap[SR.STATE_KEY]={"stocked":{"sunny":2,"cloudy":0},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0,"claimed_own":false}
	rain[SR.STATE_KEY]=snap[SR.STATE_KEY].duplicate(true)
	expect(SR.pack_block(rain,"kitchen",{"fiber":2})=="" and SR.progress(rain).rainy_today,"view: packing works on a rainy day")
	expect(SR.pack_block(snap,"pickle",{"fiber":1})==SR.NO_FIBER%[2,1] and SR.pack_block(snap,"pickle",{"fiber":1})=="裝一籃要纖維 2 份（編籃、綁口），你的背包裡有 1 份。","view: NO_FIBER")
	snap[SR.STATE_KEY]={"stocked":{"sunny":4,"cloudy":2},"packed":{"kitchen":3,"pickle":0},"rain_packs":0,"day":1,"completed":false,"done_day":0,"claimed_own":false}
	expect(SR.stocked_total(snap)==6 and SR.packed_total(snap)==3 and SR.stock_block(snap,{"sea_salt":3})==SR.STOCK_FULL,"view: six lots stocked")
	expect(SR.pack_block(snap,"kitchen",{"fiber":2})==SR.QUOTA_FULL%["料理用",3,3,"醃漬用"] and SR.pack_block(snap,"pickle",{"fiber":2})=="","view: QUOTA_FULL / ok")
	expect(SR.pack_block(snap,"kitchen",{"fiber":2})=="這批料理用只要 3 籃，已經裝了 3 籃；剩下的要醃漬用。","view: quota message text")
	var rows:=SR.rows(snap,{"fiber":5})
	expect(rows.size()==2 and rows[0].id=="kitchen" and rows[0].need==3 and rows[0].packed==3 and rows[0].full and rows[0].fiber==5 and rows[1].id=="pickle" and rows[1].need==3 and rows[1].packed==0 and not rows[1].full and rows[1].name=="醃漬用","view: rows()")
	expect(SR.rows(snap)[0].fiber==-1,"view: rows() without inventory has fiber=-1")
	var prog:=SR.progress(snap)
	expect(prog.stocked_total==6 and prog.lots_needed==6 and prog.packed_total==3 and not prog.ready_to_send and prog.season=="spring" and same(prog.order,{"kitchen":3,"pickle":3}) and prog.rain_packs==0,"view: progress()")
	snap["time"]=14*DAY+5.0
	expect(SR.order_season(snap)=="spring" and SR.pack_block(snap,"pickle",{"fiber":2})=="","view: after the first pack the order stays locked to day 1 (spring) in summer")
	snap[SR.STATE_KEY]={"stocked":{"sunny":1,"cloudy":0},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0,"claimed_own":false}
	expect(SR.order_season(snap)=="summer" and same(SR.order(snap),{"kitchen":2,"pickle":4}) and SR.reason(snap)==SR.reason_for("summer"),"view: nothing packed yet, today's season sets the order")
	snap[SR.STATE_KEY]={"stocked":{"sunny":6,"cloudy":0},"packed":{"kitchen":3,"pickle":3},"rain_packs":0,"day":1,"completed":false,"done_day":0,"claimed_own":false}
	expect(SR.send_block(snap)=="" and SR.pack_block(snap,"kitchen",{"fiber":2})==SR.ALL_PACKED and SR.progress(snap).ready_to_send,"view: six packed, ready to send")
	snap[SR.STATE_KEY]={"stocked":{"sunny":6,"cloudy":0},"packed":{"kitchen":3,"pickle":3},"rain_packs":0,"day":1,"completed":true,"done_day":15,"claimed_own":true}
	expect(SR.completed(snap) and SR.claim_block(snap,{})==SR.CLAIMED and SR.claimed_own(snap) and SR.send_block(snap)==SR.ALREADY_DONE and SR.stock_block(snap,{"sea_salt":3})==SR.ALREADY_DONE,"view: claimed_own from the snapshot flag")
	snap[SR.STATE_KEY].claimed_own=false
	expect(SR.can_claim(snap,{}) and SR.claim_block(snap,{KIT:SR.MAX_ITEM})==SR.BAG_FULL,"view: can_claim / BAG_FULL")
	expect(SR.public({})=={},"public() without a record")

## Every interaction point is a real standable spot reachable on foot from the bus arrival.
func check_site() -> void:
	var w:=World.new()
	w.switch_region(SR.REGION)
	var start:=Vector2i(ARRIVAL)
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
	expect(w.can_stand(ARRIVAL),"the bus arrival is standable")
	for pair in [[AT_WORKER,SR.WORKER,"阿曬"],[AT_CHEST,SR.CHEST,"co-op chest"],[AT_STOP,SR.STOP,"bus stop"]]:
		var spot:Vector2=pair[0]
		var cell:Vector2i=pair[1]
		expect(w.can_stand(spot) and seen.has(Vector2i(spot)),"%s: standing spot %s is walkable and reachable from the bus arrival"%[pair[2],str(spot)])
		expect(spot.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=SR.REACH,"%s: spot within reach"%pair[2])
		expect(w.protected(cell) and w.blocked(cell),"%s: point %s is a protected, blocking existing feature"%[pair[2],str(cell)])
	expect(ARRIVAL.distance_to(Vector2(SR.WORKER)+Vector2(0.5,0.5))>SR.REACH,"阿曬 is out of reach of the bus arrival (a walk is needed)")
	# Disclosed layout fact: the chest and the stop are both within reach of the arrival point.
	expect(ARRIVAL.distance_to(Vector2(SR.CHEST)+Vector2(0.5,0.5))<=SR.REACH and ARRIVAL.distance_to(Vector2(SR.STOP)+Vector2(0.5,0.5))<=SR.REACH,"the co-op chest and the bus stop are both in reach of the arrival (disclosed)")
	expect(AT_WORKER.distance_to(Vector2(SR.CHEST)+Vector2(0.5,0.5))>SR.REACH and AT_WORKER.distance_to(Vector2(SR.STOP)+Vector2(0.5,0.5))>SR.REACH,"the 阿曬 spot does not reach the chest or the stop")
	w.switch_region("home")

# --------------------------------------------------------------- main world --

func main_flow(w:World,path:String) -> bool:
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	if not expect(arrive(w,ALPHA) and arrive(w,BETA),"alpha and beta earn the letter, ride to 北門 and meet 阿曬"):return false
	# Before the gates: every action LOCKED.
	beimen(w,ALPHA,AT_WORKER)
	give(w,ALPHA,"sea_salt",3)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.LOCKED,"stock before the gates")
	refuse(w,ALPHA,SR.CLAIM_ACTION,SR.WORKER,"",SR.LOCKED,"claim before the gates")
	beimen(w,ALPHA,AT_CHEST)
	refuse(w,ALPHA,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.LOCKED,"pack before the gates")
	beimen(w,ALPHA,AT_STOP)
	refuse(w,ALPHA,SR.SEND_ACTION,SR.STOP,"",SR.LOCKED,"send before the gates")
	expect(SR.stock_block(w.state,pl(w,ALPHA).inventory,ALPHA)==SR.LOCKED,"stock_block LOCKED on the server state")
	pl(w,ALPHA).inventory.erase("sea_salt")
	if not expect(repair_gates(w,ALPHA),"alpha repairs the three gates (salt_gate_give)"):return false
	expect(SR.unlocked(w.state),"unlocked after the repair")
	beimen(w,ALPHA,AT_WORKER)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.NOT_READY,"alpha has not raked yet (stock)")
	# Both flood a public pan; alpha rakes now, beta's salt waits in the pan.
	if not expect(flood_public(w,[ALPHA,BETA]),"alpha and beta flood the two public pans; World.step until salt"):return false
	if not expect(rake(w,ALPHA,0),"alpha rakes her first salt by hand (3 sea_salt, raked 1)"):return false
	expect(SR.player_ready(w.state,ALPHA) and not SR.player_ready(w.state,BETA),"alpha ready, beta not")
	beimen(w,BETA,AT_WORKER)
	refuse(w,BETA,SR.STOCK_ACTION,SR.WORKER,"",SR.NOT_READY,"beta not ready (stock)")
	refuse(w,BETA,SR.CLAIM_ACTION,SR.WORKER,"",SR.NOT_READY,"beta not ready (claim)")
	beimen(w,BETA,AT_CHEST)
	refuse(w,BETA,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.NOT_READY,"beta not ready (pack)")
	refuse(w,BETA,SR.SEND_ACTION,SR.STOP,"",SR.NOT_READY,"beta not ready (send)")
	expect(w.save(),"pre-revisit world saves")
	var legacy_path:=temp_path("pre-revisit")
	expect(DirAccess.copy_absolute(path,legacy_path)==OK,"copy the pre-revisit save")
	# Placement rejections.
	put(w,ALPHA,HOME_SPOT,"home")
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.WRONG_REGION,"stock from home")
	refuse(w,ALPHA,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.WRONG_REGION,"pack from home")
	refuse(w,ALPHA,SR.SEND_ACTION,SR.STOP,"",SR.WRONG_REGION,"send from home")
	refuse(w,ALPHA,SR.CLAIM_ACTION,SR.WORKER,"",SR.WRONG_REGION,"claim from home")
	beimen(w,ALPHA,AT_WORKER)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.CHEST,"",SR.WRONG_STOCK_CELL,"stock at the chest")
	refuse(w,ALPHA,SR.CLAIM_ACTION,SR.STOP,"",SR.WRONG_CLAIM_CELL,"claim at the stop")
	refuse(w,ALPHA,SR.PACK_ACTION,SR.WORKER,"kitchen",SR.WRONG_PACK_CELL,"pack at 阿曬")
	refuse(w,ALPHA,SR.SEND_ACTION,SR.CHEST,"",SR.WRONG_SEND_CELL,"send at the chest")
	refuse(w,ALPHA,SR.STOCK_ACTION,Salt.HERITAGE_SIGN,"",SR.WRONG_STOCK_CELL,"stock at the heritage sign")
	refuse(w,ALPHA,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.TOO_FAR,"pack from 阿曬's spot")
	refuse(w,ALPHA,SR.SEND_ACTION,SR.STOP,"",SR.TOO_FAR,"send from 阿曬's spot")
	beimen(w,ALPHA,AT_STOP)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.TOO_FAR,"stock from the bus stop")
	refuse(w,ALPHA,SR.CLAIM_ACTION,SR.WORKER,"",SR.TOO_FAR,"claim from the bus stop")
	beimen(w,ALPHA,AT_WORKER)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"x",SR.BAD_EXTRA,"stock with an extra")
	refuse(w,ALPHA,SR.CLAIM_ACTION,SR.WORKER,"x",SR.BAD_EXTRA,"claim with an extra")
	refuse(w,ALPHA,SR.CLAIM_ACTION,SR.WORKER,"",SR.NOT_DONE,"claim before completion")
	beimen(w,ALPHA,AT_CHEST)
	for bad:String in ["","salt","KITCHEN","kitchen ","pickle:1","sunny"]:
		refuse(w,ALPHA,SR.PACK_ACTION,SR.CHEST,bad,SR.BAD_KIND,"malformed pack extra '%s'"%bad)
	refuse(w,ALPHA,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.NEED_STOCK%[0,0],"pack before any lot is stocked")
	beimen(w,ALPHA,AT_STOP)
	refuse(w,ALPHA,SR.SEND_ACTION,SR.STOP,"",SR.NOT_PACKED%0,"send an empty batch")
	refuse(w,ALPHA,SR.SEND_ACTION,SR.STOP,"x",SR.BAD_EXTRA,"send with an extra")
	expect(not w.state.has(SR.STATE_KEY),"no record before the first successful action")
	# Day 1 (sunny, spring): alpha stocks her earned salt.
	expect(SR.today(w.state)==1 and SR.weather_today(w.state)=="sunny" and SR.order_season(w.state)=="spring","premise: day 1 sunny spring")
	var bag_before:Dictionary=pl(w,ALPHA).inventory.duplicate(true)
	var s1:=stock(w,ALPHA,"alpha stocks her earned salt")
	expect(str(s1.message)==SR.STOCK_OK%[3,"晴天",1],"stock message (%s)"%str(s1.message))
	var want_bag:Dictionary=bag_before.duplicate(true)
	want_bag["sea_salt"]=0
	expect(same(pl(w,ALPHA).inventory,want_bag),"exactly three sea_salt taken from alpha's bag")
	expect(record_is(w,1,0,0,0,0,0,false,0),"record created by the first lot (day still 0)")
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.NO_SALT%[3,0],"no salt left")
	give(w,ALPHA,"sea_salt",2)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.NO_SALT%[3,2],"two salt is not a lot")
	# Beta catches up (late path): rakes the salt still waiting in her pan, then packs.
	if not expect(rake(w,BETA,1),"beta rakes her first salt (catch-up)"):return false
	pl(w,BETA).inventory.erase("fiber")
	beimen(w,BETA,AT_CHEST)
	refuse(w,BETA,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.NO_FIBER%[2,0],"beta has no fiber")
	give(w,BETA,"fiber",12)
	var p1:=pack(w,BETA,"kitchen","beta packs the first basket")
	expect(str(p1.message)==SR.PACK_OK%["料理用",1,1,0],"pack message (%s)"%str(p1.message))
	expect(held(w,BETA,"fiber")==10,"exactly two fiber taken from beta")
	expect(record_is(w,1,0,1,0,0,1,false,0),"first pack stamps day 1")
	refuse(w,BETA,SR.PACK_ACTION,SR.CHEST,"pickle",SR.NEED_STOCK%[1,1],"no stocked lot left for beta")
	expect(SR.pack_block(w.state,"pickle",pl(w,BETA).inventory,BETA)=="倉棚裡入倉的散鹽有 1 批，已經裝了 1 籃；先帶海鹽找阿曬入倉。","NEED_STOCK text says how many lots are in the shed")
	stock(w,BETA,"beta stocks her earned salt")
	expect(record_is(w,2,0,1,0,0,1,false,0),"two sunny lots")
	# Day 2 (cloudy): alpha stocks two cloudy lots.
	set_day(w,1)
	expect(SR.today(w.state)==2 and SR.weather_today(w.state)=="cloudy","premise: day 2 cloudy")
	give(w,ALPHA,"sea_salt",4)
	var s3:=stock(w,ALPHA,"alpha stocks a cloudy lot")
	expect(str(s3.message)==SR.STOCK_OK%[3,"多雲",3],"cloudy stock message (%s)"%str(s3.message))
	stock(w,ALPHA,"alpha stocks a second cloudy lot")
	expect(record_is(w,2,2,1,0,0,1,false,0) and held(w,ALPHA,"sea_salt")==0,"two sunny + two cloudy lots")
	# Day 3 (rainy): the shed refuses salt, packing still works on the same day.
	set_day(w,2)
	expect(SR.today(w.state)==3 and SR.rainy_today(w.state) and Salt.raining(float(w.state.time)),"premise: day 3 rains in 北門")
	give(w,ALPHA,"sea_salt",6)
	beimen(w,ALPHA,AT_WORKER)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.RAIN_STOCK,"stock on a rainy day")
	expect(SR.stock_block(w.state,pl(w,ALPHA).inventory,ALPHA)==SR.RAIN_STOCK,"stock_block RAIN_STOCK on the rainy day")
	var p2:=pack(w,BETA,"pickle","beta packs on the rainy day")
	expect(str(p2.message)==SR.PACK_OK%["醃漬用",2,1,1]+SR.PACK_RAIN_NOTE,"rainy pack message (%s)"%str(p2.message))
	expect(record_is(w,2,2,1,1,1,1,false,0),"rain_packs 1")
	# Day 15 (summer, sunny): the batch keeps the spring order.
	set_day(w,14)
	expect(SR.today(w.state)==15 and Weather.season_on_day(14.0)=="summer" and SR.order_season(w.state)=="spring" and SR.weather_today(w.state)=="sunny","day 15 is summer but the batch keeps the spring order")
	stock(w,ALPHA,"alpha stocks lot 5")
	stock(w,ALPHA,"alpha stocks lot 6")
	give(w,ALPHA,"sea_salt",3)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.STOCK_FULL,"a seventh lot is refused")
	pack(w,BETA,"kitchen","second kitchen basket")
	pack(w,BETA,"kitchen","third kitchen basket under the locked spring order (summer would allow only 2)")
	refuse(w,BETA,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.QUOTA_FULL%["料理用",3,3,"醃漬用"],"kitchen quota full")
	expect(SR.pack_block(w.state,"kitchen",pl(w,BETA).inventory,BETA)=="這批料理用只要 3 籃，已經裝了 3 籃；剩下的要醃漬用。","kitchen quota message text")
	beimen(w,BETA,AT_CHEST)
	refuse(w,BETA,SR.SEND_ACTION,SR.STOP,"",SR.NOT_PACKED%4,"send with four packed (from the chest spot, the stop is in reach)")
	pack(w,BETA,"pickle","pickle basket 2")
	pack(w,BETA,"pickle","pickle basket 3")
	refuse(w,BETA,SR.PACK_ACTION,SR.CHEST,"pickle",SR.ALL_PACKED,"a seventh basket is refused")
	expect(record_is(w,4,2,3,3,1,1,false,0),"six packed, day still 1")
	expect(held(w,BETA,"fiber")==0,"beta used all twelve fiber")
	beimen(w,ALPHA,AT_STOP)
	var done:=ok(w,ALPHA,SR.SEND_ACTION,SR.STOP,"","alpha sends the batch (she packed nothing)")
	expect(str(done.message)==SR.COMPLETE_OK and SR.completed(w.state),"completion message and flag")
	expect(record_is(w,4,2,3,3,1,1,true,15),"exact completed record (no names or tokens)")
	refuse(w,ALPHA,SR.SEND_ACTION,SR.STOP,"",SR.ALREADY_DONE,"send after completion")
	refuse(w,BETA,SR.PACK_ACTION,SR.CHEST,"pickle",SR.ALREADY_DONE,"pack after completion")
	beimen(w,ALPHA,AT_WORKER)
	refuse(w,ALPHA,SR.STOCK_ACTION,SR.WORKER,"",SR.ALREADY_DONE,"stock after completion")
	# Claims: once each.
	put(w,BETA,HOME_SPOT,"home")
	refuse(w,BETA,SR.CLAIM_ACTION,SR.WORKER,"",SR.WRONG_REGION,"claim from home")
	var claim:=ok(w,ALPHA,SR.CLAIM_ACTION,SR.WORKER,"","alpha claims the basket")
	expect(str(claim.message)==SR.CLAIM_OK and held(w,ALPHA,KIT)==1,"alpha gets exactly one kit")
	refuse(w,ALPHA,SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"alpha claims twice")
	beimen(w,BETA,AT_WORKER)
	pl(w,BETA).inventory[KIT]=SR.MAX_ITEM
	refuse(w,BETA,SR.CLAIM_ACTION,SR.WORKER,"",SR.BAG_FULL,"beta's kit count at the cap")
	pl(w,BETA).inventory.erase(KIT)
	ok(w,BETA,SR.CLAIM_ACTION,SR.WORKER,"","beta claims the basket")
	expect(held(w,BETA,KIT)==1,"beta gets one kit")
	# A player who joins later: must rake by hand first.
	w.add_player(LATE,"Late")
	if not expect(arrive(w,LATE),"late joiner earns the letter, the trip and the intro"):return false
	beimen(w,LATE,AT_WORKER)
	refuse(w,LATE,SR.CLAIM_ACTION,SR.WORKER,"",SR.NOT_READY,"late joiner must rake before claiming")
	if not expect(flood_public(w,[LATE]) and rake(w,LATE,0),"late joiner floods and rakes by hand on day 15"):return false
	beimen(w,LATE,AT_WORKER)
	ok(w,LATE,SR.CLAIM_ACTION,SR.WORKER,"","late joiner claims the basket")
	refuse(w,LATE,SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"late joiner claims twice")
	var claimed:Array=w.state[SR.STATE_KEY].claimed.keys()
	claimed.sort()
	var want:=[ALPHA,BETA,LATE]
	want.sort()
	expect(claimed==want,"claim set = alpha, beta, late")
	for token in [ALPHA,BETA,LATE]:put(w,token,HOME_SPOT,"home")
	expect(w.save() and validates(JSON.parse_string(FileAccess.get_file_as_string(path))),"completed world saves and validates")
	var legacy:=World.new()
	expect(legacy.load_world(legacy_path) and not legacy.recovered_from_backup and not legacy.state.has(SR.STATE_KEY),"pre-revisit save (no field) loads without migration")
	return true

# --------------------------------------------------------------- placement --

func check_placement(w:World) -> void:
	put(w,ALPHA,HOME_SPOT,"home")
	var bag:Dictionary=pl(w,ALPHA).inventory
	expect(int(bag.get(KIT,0))==1,"alpha holds one basket kit")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the basket")
	expect(int(bag.get(KIT,0))==0 and same(w.state.objects.get(World.key(BUILD_TILE),{}),{"type":KIND,"owner":ALPHA,"items":{}}),"kit consumed, object on the home layer")
	expect(not w.blocked(BUILD_TILE) and w.can_stand(Vector2(BUILD_TILE)+Vector2(0.5,0.5)),"basket is walk-through")
	refuse(w,ALPHA,"build",MOVE_TILE,KIND,"","second basket without a kit")
	ok(w,ALPHA,"move_object",BUILD_TILE,"%d,%d"%[MOVE_TILE.x,MOVE_TILE.y],"alpha moves the basket")
	expect(w.state.objects.has(World.key(MOVE_TILE)) and not w.state.objects.has(World.key(BUILD_TILE)),"basket moved")
	put(w,BETA,HOME_SPOT,"home")
	refuse(w,BETA,"remove",MOVE_TILE,"","","beta cannot remove alpha's basket")
	ok(w,ALPHA,"remove",MOVE_TILE,"","alpha picks the basket up")
	expect(int(bag.get(KIT,0))==1 and not w.state.objects.has(World.key(MOVE_TILE)),"removal returns the kit")
	bag["wood"]=int(bag.get("wood",0))+20
	ok(w,ALPHA,"build",CHEST_TILE,"chest","alpha builds a shared chest")
	ok(w,ALPHA,"deposit",CHEST_TILE,KIT,"basket kit goes into the chest")
	expect(int(bag.get(KIT,0))==0 and int(w.state.objects[World.key(CHEST_TILE)].items.get(KIT,0))==1,"kit stored in the chest")
	ok(w,ALPHA,"withdraw",CHEST_TILE,KIT,"basket kit comes back out")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the basket again (stays for the save test)")
	# Building the basket in 北門 is refused like any non-chest build there.
	beimen(w,LATE,AT_WORKER)
	refuse(w,LATE,"build",Vector2i(45,18),KIND,Salt.REJECT_MESSAGE,"no basket building in 北門")
	put(w,LATE,HOME_SPOT,"home")

func check_not_currency(w:World) -> void:
	expect(held(w,BETA,KIT)==1,"beta holds a kit")
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
	for field in [SR.STATE_KEY,"salt_pan","objects"]:
		expect(same(reloaded.state.get(field),w.state.get(field)),"state.%s equal after reload"%field)
	var rr:Dictionary=reloaded.state[SR.STATE_KEY]
	expect(typeof(rr.day)==TYPE_INT and typeof(rr.done_day)==TYPE_INT and typeof(rr.rain_packs)==TYPE_INT and typeof(rr.stocked.cloudy)==TYPE_INT and typeof(rr.packed.kitchen)==TYPE_INT,"reload normalises counts and days to int")
	for token in [ALPHA,BETA,LATE]:
		expect(same(reloaded.state.players[token].inventory,pl(w,token).inventory),"%s bag equal after reload"%token.left(16))
	put(reloaded,LATE,AT_WORKER,SR.REGION)
	refuse(reloaded,LATE,SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"claims survive reload")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"saved world parses and validates"):return
	var fixture:=temp_path("fixture")
	var old:Dictionary=pristine_of(base)
	expect(validates(old) and write_json(fixture,old) and World.new().load_world(fixture),"old-shape save without salt_revisit (no basket anywhere) loads")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["record is a list","record is null","record missing claimed","record extra key","stocked missing cloudy","stocked rainy key",
		"stocked count negative","stocked count fractional","stocked count string","stocked total over six","stocked is a list",
		"packed missing pickle","packed extra kind","packed over stocked","packed kitchen over the order","rain_packs over packed",
		"rain_packs negative","rain_packs fractional","rain_packs string","rain_packs without a rainy day","day in the future","day fractional",
		"day zero with packs","day set with nothing packed","completed with five packed","done_day without completion",
		"completed without done_day","done_day before day","completed is a string","claimed before completion","claimed by a stranger",
		"claim value false","claimer who never raked","record with no raked player","record before the gates are repaired",
		"basket placed without completion","basket kit in a bag without completion","basket kit in a chest without completion",
		"basket in a regional layer without completion"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	expect(labels.size()>=35,"at least 35 tamper cases (%d)"%labels.size())
	var control:Dictionary=base.duplicate(true)
	control.players["noraked-token-1234"]=control.players[BETA].duplicate(true)
	control.players["noraked-token-1234"].inventory.erase(KIT)
	expect(validates(control),"control: the extra never-raked player alone validates (so the claim is what is rejected)")
	var partial:Dictionary=pristine_of(base)
	partial[SR.STATE_KEY]={"stocked":{"sunny":3,"cloudy":1},"packed":{"kitchen":2,"pickle":0},"rain_packs":0,"day":1,"completed":false,"done_day":0,"claimed":{}}
	expect(validates(partial),"control: a partly packed record validates")
	var only_lots:Dictionary=pristine_of(base)
	only_lots[SR.STATE_KEY]={"stocked":{"sunny":1,"cloudy":0},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0,"claimed":{}}
	expect(validates(only_lots),"control: a lots-only record (day 0) validates")
	var ready:Dictionary=pristine_of(base)
	ready[SR.STATE_KEY]={"stocked":{"sunny":6,"cloudy":0},"packed":{"kitchen":3,"pickle":3},"rain_packs":2,"day":1,"completed":false,"done_day":0,"claimed":{}}
	expect(validates(ready),"control: six packed but not yet sent validates (a save between the last pack and the send loads)")
	var dry:Dictionary=base.duplicate(true)
	dry[SR.STATE_KEY].rain_packs=0
	expect(validates(dry),"control: the completed record with rain_packs 0 validates")

## base without the record and without any basket object or kit.
func pristine_of(base:Dictionary) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.erase(SR.STATE_KEY)
	s.objects.erase(World.key(BUILD_TILE))
	for token in s.players:(s.players[token].inventory as Dictionary).erase(KIT)
	return s

func lots_only(base:Dictionary) -> Dictionary:
	var s:=pristine_of(base)
	s[SR.STATE_KEY]={"stocked":{"sunny":1,"cloudy":0},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0,"claimed":{}}
	return s

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var r:Dictionary=s[SR.STATE_KEY]
	match label:
		"record is a list":s[SR.STATE_KEY]=[r]
		"record is null":s[SR.STATE_KEY]=null
		"record missing claimed":r.erase("claimed")
		"record extra key":r["by"]=ALPHA
		"stocked missing cloudy":r.stocked.erase("cloudy")
		"stocked rainy key":r.stocked["rainy"]=0
		"stocked count negative":
			r.stocked.cloudy=-1
			r.stocked.sunny=7
		"stocked count fractional":
			r.stocked.cloudy=2.5
			r.stocked.sunny=3.5
		"stocked count string":r.stocked.cloudy="2"
		"stocked total over six":r.stocked.cloudy=3
		"stocked is a list":r.stocked=[4,2]
		"packed missing pickle":r.packed.erase("pickle")
		"packed extra kind":r.packed["gift"]=0
		"packed over stocked":
			s=pristine_of(base)
			s[SR.STATE_KEY]={"stocked":{"sunny":1,"cloudy":0},"packed":{"kitchen":2,"pickle":0},"rain_packs":0,"day":1,"completed":false,"done_day":0,"claimed":{}}
		"packed kitchen over the order":r.packed={"kitchen":4,"pickle":2}
		"rain_packs over packed":
			s=pristine_of(base)
			s[SR.STATE_KEY]={"stocked":{"sunny":2,"cloudy":0},"packed":{"kitchen":1,"pickle":0},"rain_packs":2,"day":1,"completed":false,"done_day":0,"claimed":{}}
		"rain_packs negative":r.rain_packs=-1
		"rain_packs fractional":r.rain_packs=0.5
		"rain_packs string":r.rain_packs="1"
		"rain_packs without a rainy day":r.done_day=2
		"day in the future":r.day=int(Weather.day_index(float(s.time)))+2
		"day fractional":r.day=1.5
		"day zero with packs":r.day=0
		"day set with nothing packed":
			s=lots_only(base)
			s[SR.STATE_KEY].day=1
		"completed with five packed":r.packed={"kitchen":3,"pickle":2}
		"done_day without completion":
			s=pristine_of(base)
			s[SR.STATE_KEY]={"stocked":{"sunny":2,"cloudy":0},"packed":{"kitchen":1,"pickle":0},"rain_packs":0,"day":1,"completed":false,"done_day":3,"claimed":{}}
		"completed without done_day":r.done_day=0
		"done_day before day":
			r.day=15
			r.done_day=3
			r.rain_packs=0
			r.packed={"kitchen":2,"pickle":4}
		"completed is a string":r.completed="true"
		"claimed before completion":
			r.completed=false
			r.done_day=0
			r.packed={"kitchen":3,"pickle":2}
		"claimed by a stranger":r.claimed["stranger-token-0000"]=true
		"claim value false":r.claimed[ALPHA]=false
		"claimer who never raked":
			s.players["noraked-token-1234"]=s.players[BETA].duplicate(true)
			s.players["noraked-token-1234"].inventory.erase(KIT)
			r.claimed["noraked-token-1234"]=true
		"record with no raked player":
			s=lots_only(base)
			for token in s.salt_pan.players:s.salt_pan.players[token].raked=0
		"record before the gates are repaired":
			s=lots_only(base)
			s.salt_pan.gates[2].stone=3
			s.salt_pan.repaired_at=-1.0
		"basket placed without completion":
			s=pristine_of(base)
			s.objects[World.key(BUILD_TILE)]={"type":KIND,"owner":ALPHA,"items":{}}
		"basket kit in a bag without completion":
			s=pristine_of(base)
			s.players[BETA].inventory[KIT]=1
		"basket kit in a chest without completion":
			s=pristine_of(base)
			s.objects[World.key(CHEST_TILE)].items[KIT]=1
		"basket in a regional layer without completion":
			s=pristine_of(base)
			s.regions.lanyang.objects["30,30"]={"type":KIND,"owner":ALPHA,"items":{}}
	return s

# ---------------------------------------------------------------- snapshot --

func check_snapshot(w:World) -> void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	var keep:=w.save_path
	w.save_path=""
	const GAMMA:="saltrevisit-gamma-token-66bb"
	w.add_player(GAMMA,"Gamma")
	session.peers={1:ALPHA,2:GAMMA}
	var tokens:=[ALPHA,BETA,LATE,GAMMA]
	var want:={"stocked":{"sunny":4,"cloudy":2},"packed":{"kitchen":3,"pickle":3},"rain_packs":1,"day":1,"completed":true,"done_day":15}
	for region in ["home","beimen","tianwei"]:
		var public:Dictionary=session.public_state(region)
		var rec:Variant=public.get(SR.STATE_KEY)
		expect(rec is Dictionary and same(rec,want),"public_state(%s) carries stocked/packed/rain_packs/day/completed/done_day only"%region)
		var text:=JSON.stringify(public)
		var leaked:=false
		for token:String in tokens:
			if text.contains(token):leaked=true
		expect(not leaked,"public_state(%s) contains no raw player token"%region)
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.get(SR.STATE_KEY,{}).get("claimed_own")==true and not snap[SR.STATE_KEY].has("claimed"),"alpha's snapshot: own claim flag only")
	expect(SR.claimed_own(snap) and SR.completed(snap) and SR.claim_block(snap,{})==SR.CLAIMED and SR.player_ready(snap) and SR.unlocked(snap),"client helpers on alpha's snapshot (salt_pan.repaired + salt_pan.own.record.raked)")
	var dump:=JSON.stringify(snap)
	var leaked2:=false
	for token:String in tokens:
		if dump.contains(token):leaked2=true
	expect(not leaked2,"alpha's snapshot contains no raw token")
	session.peers={1:GAMMA}
	session._send_snapshot(1)
	var gamma_snap:Dictionary=session.snapshot
	expect(gamma_snap.get(SR.STATE_KEY,{}).get("claimed_own")==false and not gamma_snap[SR.STATE_KEY].has("claimed"),"gamma's snapshot: completion visible, own flag false, no claim map")
	expect(SR.claim_block(gamma_snap,{})==SR.NOT_READY and not SR.player_ready(gamma_snap) and SR.unlocked(gamma_snap),"gamma (never raked) sees NOT_READY on the client")
	var fresh:=World.new()
	fresh.add_player("solo-token-123456","Solo")
	session.world=fresh
	session.peers={1:"solo-token-123456"}
	expect(not session.public_state("home").has(SR.STATE_KEY),"a world without the record publishes no salt_revisit key")
	session._send_snapshot(1)
	expect(not session.snapshot.has(SR.STATE_KEY) and SR.stock_block(session.snapshot,{})==SR.LOCKED,"no record: snapshot has no salt_revisit, client sees LOCKED")
	session.world=null
	session.queue_free()
	w.save_path=keep
	w.state.players.erase(GAMMA)

# ----------------------------------------------------------------- seasons --

func check_seasons() -> void:
	var order:=["spring","summer","autumn","winter"]
	for i in order.size():
		var season:String=order[i]
		var w:=earned_world()
		if not expect(w!=null,"%s: earned fixture (letter, trip, gates, hand rake through World.act)"%season):continue
		set_day(w,int(SEASON_DAYS[season]))
		var need:Dictionary=SR.order_for(season)
		expect(SR.order_season(w.state)==season and same(SR.order(w.state),need) and SR.reason(w.state)==SR.reason_for(season) and not SR.rainy_today(w.state),"%s: premise day %d (dry) uses the %s order"%[season,SR.today(w.state),season])
		give(w,ALPHA,"sea_salt",15)
		for j in 6:stock(w,ALPHA,"%s: lot %d"%[season,j+1])
		give(w,ALPHA,"fiber",14-held(w,ALPHA,"fiber"))
		# Spring/autumn pack kitchen first and hit the kitchen quota; summer/winter pickle first.
		var first:="kitchen" if i%2==0 else "pickle"
		var second:="pickle" if first=="kitchen" else "kitchen"
		for k in int(need[first]):pack(w,ALPHA,first,"%s: pack %s %d"%[season,first,k+1])
		expect(held(w,ALPHA,"fiber")>=2,"%s: alpha still holds fiber, so only the quota stops her"%season)
		refuse(w,ALPHA,SR.PACK_ACTION,SR.CHEST,first,SR.QUOTA_FULL%[SR.KIND_NAMES[first],int(need[first]),int(need[first]),SR.KIND_NAMES[second]],"%s: %s quota full"%[season,first])
		for k in int(need[second]):pack(w,ALPHA,second,"%s: pack %s %d"%[season,second,k+1])
		beimen(w,ALPHA,AT_STOP)
		ok(w,ALPHA,SR.SEND_ACTION,SR.STOP,"","%s: send"%season)
		expect(SR.completed(w.state) and int(w.state[SR.STATE_KEY].day)==int(SEASON_DAYS[season])+1 and same(SR.packed(w.state),need) and int(w.state[SR.STATE_KEY].stocked.sunny)==6,"%s: completed with the season's mix"%season)
		put(w,ALPHA,HOME_SPOT,"home")
		expect(validates(w.state),"%s: the state validates"%season)

# ------------------------------------------------------------------ module --

func check_module() -> void:
	var bare:={"players":{"x":{"x":44.5,"y":18.5,"inventory":{"sea_salt":3}}},"salt_pan":{"repaired_at":0.0,"players":{"x":{"raked":1}}},"time":0.0}
	expect(SR.apply(bare,"nobody",SR.STOCK_ACTION,SR.WORKER,"","beimen").message==SR.NO_PLAYER,"module: unknown player")
	expect(SR.apply(bare,"x","salt_rake",SR.WORKER,"","beimen").message==SR.BAD_EXTRA,"module: foreign action")
	expect(SR.apply(bare,"x",SR.STOCK_ACTION,SR.WORKER,"","home").message==SR.WRONG_REGION,"module: wrong region")
	var no_salt:=bare.duplicate(true)
	no_salt.erase("salt_pan")
	expect(SR.apply(no_salt,"x",SR.STOCK_ACTION,SR.WORKER,"","beimen").message==SR.LOCKED,"module: no salt_pan block is LOCKED")
	var unrepaired:=bare.duplicate(true)
	unrepaired.salt_pan.repaired_at=-1.0
	expect(SR.apply(unrepaired,"x",SR.STOCK_ACTION,SR.WORKER,"","beimen").message==SR.LOCKED,"module: repaired_at -1 is LOCKED")
	var unraked:=bare.duplicate(true)
	unraked.salt_pan.players.x.raked=0
	expect(SR.apply(unraked,"x",SR.STOCK_ACTION,SR.WORKER,"","beimen").message==SR.NOT_READY,"module: raked 0 is NOT_READY")
	bare[SR.STATE_KEY]={"stocked":{"sunny":1},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0,"claimed":{}}
	var before:=var_to_bytes(bare)
	expect(SR.apply(bare,"x",SR.STOCK_ACTION,SR.WORKER,"","beimen").message==SR.BAD_EXTRA and var_to_bytes(bare)==before,"module: corrupt record refused without writing")
	bare.erase(SR.STATE_KEY)
	var r:=SR.apply(bare,"x",SR.STOCK_ACTION,SR.WORKER,"","beimen")
	expect(r.ok==true and same(bare[SR.STATE_KEY].stocked,{"sunny":1,"cloudy":0}) and int(bare.players.x.inventory.sea_salt)==0,"module: stock writes the record and takes three salt")
