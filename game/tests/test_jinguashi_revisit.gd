extends SceneTree
## 第 40 章「金瓜石回訪・礦料調度」(scripts/jinguashi_revisit.gd) + 礦燈 rules test.
## Headless, World-level (World.act / save / load_world) plus an in-process Session
## for the public snapshot. No network.
##
## EARNED through real World.act: the picnic (World.act "picnic"), the Q07 hoist repair
## (mine_hoist_repair at the entry sign), every first Bobo sort (bobo_sort_start /
## bobo_sort_answer ×3 / bobo_sort_claim), beta's copper for the ferry crate
## (borrow_mine_pick at home + pick on a Jinguashi copper node = exactly 4 copper_ore),
## every jg_revisit_sort / jg_revisit_ship / jg_revisit_claim, every build / move /
## remove / deposit / withdraw of the lantern, the chest build.
## WRITTEN DIRECTLY (disclosed): board=true + soup 2 / bread 1 for the picnic,
## mine_depths {"unlocked":6,"pumped":24,"hoist":false} (opening B2–B6 is covered by the
## mine suites), the hoist materials (copper_joint 12, plank 4), gold_ore 3 for each
## Bobo sort, the shipped gold_ore 2 / stone 6 (and the season fixtures' ores), wood for
## the chest, player region/x/y (standing spots in Jinguashi and at home, no travel
## action), state.time jumps (day 15 = first day of summer, and the season fixtures),
## the kit count at the 1e9 cap for BAG_FULL, and the tampered / legacy save files.
const World=preload("res://scripts/world.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Bobo=preload("res://scripts/bobo_workshop.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Market=preload("res://scripts/market_stall.gd")
const Lanyang=preload("res://scripts/lanyang_revisit.gd")
const ALPHA:="jgrevisit-alpha-token-41ad"
const BETA:="jgrevisit-beta-token-9c03"
const LATE:="jgrevisit-late-token-7e1b"
const KIT:="mine_lantern_kit"
const KIND:="mine_lantern"
const HOME_SPOT:=Vector2(39.5,33.5)
const BUILD_TILE:=Vector2i(38,34)
const MOVE_TILE:=Vector2i(37,35)
const CHEST_TILE:=Vector2i(40,35)
const TABLE:=Vector2i(23,20)
const AT_TABLE:=Vector2(23.5,21.5)
const AT_HOIST:=Vector2(27.5,19.5)
const AT_SHUTTLE:=Vector2(12.5,20.5)
const COPPER_NODE:=Vector2i(28,20)
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
	print("JINGUASHI_REVISIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("jinguashi-revisit-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

func jg(w:World,token:String,at:Vector2) -> void:
	put(w,token,at,"jinguashi")

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"jgrevisit-req-%d"%serial,action,p,extra)

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

## Earned picnic (board + dishes written first).
func earn_picnic(w:World,token:String) -> bool:
	w.state["board"]=true
	put(w,token,Vector2(40.5,30.5),"home")
	pl(w,token).inventory["soup"]=int(pl(w,token).inventory.get("soup",0))+2
	pl(w,token).inventory["bread"]=int(pl(w,token).inventory.get("bread",0))+1
	return act(w,token,"picnic",Vector2i(40,29)).ok and w.state.picnic==true

## Earned Q07 hoist repair (B6 opened + materials written first).
func earn_hoist(w:World,token:String) -> bool:
	w.state["mine_depths"]={"unlocked":6,"ready":{},"pumped":24,"hoist":false}
	for item in Mines.HOIST_COST:pl(w,token).inventory[item]=int(pl(w,token).inventory.get(item,0))+int(Mines.HOIST_COST[item])
	jg(w,token,AT_HOIST)
	return act(w,token,World.HOIST_ACTION,Mines.ENTRY).ok and Mines.hoist_ready(w.state.mine_depths)

## Earned first Bobo sort (gold_ore 3 written first).
func earn_bobo(w:World,token:String) -> bool:
	pl(w,token).inventory["gold_ore"]=int(pl(w,token).inventory.get("gold_ore",0))+Bobo.INPUT
	jg(w,token,AT_TABLE)
	if not act(w,token,"bobo_sort_start",TABLE).ok:return false
	for step in Bobo.STEPS.size():
		if not act(w,token,"bobo_sort_answer",TABLE,"%d:%s"%[step,Bobo.STEPS[step]]).ok:return false
	return act(w,token,"bobo_sort_claim",TABLE).ok and w.state.bobo_workshop.done.get(token)==true

func earned_world() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	if not earn_picnic(w,ALPHA) or not earn_hoist(w,ALPHA) or not earn_bobo(w,ALPHA):return null
	return w

func sort(w:World,token:String,dest:String,ore:String,label:String) -> Dictionary:
	jg(w,token,AT_TABLE)
	return ok(w,token,JG.SORT_ACTION,TABLE,JG.sort_extra(dest,ore),label)

func spot_for(dest:String) -> Vector2:
	match dest:
		"bobo":return AT_TABLE
		"ferry":return AT_SHUTTLE
	return AT_HOIST

func ship(w:World,token:String,dest:String,label:String) -> Dictionary:
	jg(w,token,spot_for(dest))
	return ok(w,token,JG.SHIP_ACTION,JG.dest_cell(w.state,dest),"",label)

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(JG.ACTIONS==["jg_revisit_sort","jg_revisit_ship","jg_revisit_claim"],"action names")
	for action:String in JG.ACTIONS:
		expect(action.length()<=24 and Session.extra_allowed(action,JG.sort_extra("depot","copper_ore")),"%s passes the Session transport bounds"%action)
		expect(not action in Lanyang.ACTIONS+World.BOBO_WORKSHOP.ACTIONS+World.MINE_FREIGHT.ACTIONS+World.MINE_AUTO_FREIGHT.ACTIONS+World.MEMORY_EXHIBIT.ACTIONS+[World.HOIST_ACTION,"mine_travel","pick"],"%s does not collide with existing actions"%action)
	var seen_orders:={}
	for season:String in Weather.SEASONS:
		var order:Dictionary=JG.order_for(season)
		var ores:Array=order.values()
		ores.sort()
		var want:Array=JG.ORES.duplicate()
		want.sort()
		expect(order.keys().size()==3 and ores==want,"%s order sends each ore to exactly one crate (%s)"%[season,str(order)])
		expect(not JG.reason_for(season).is_empty(),"%s has a resident reason"%season)
		seen_orders[JSON.stringify(order)]=true
	for i in 4:
		expect(JG.order_for(Weather.SEASONS[i])!=JG.order_for(Weather.SEASONS[(i+3)%4]),"%s order differs from the previous season's"%Weather.SEASONS[i])
	expect(seen_orders.size()==3,"three distinct crate assignments over the year")
	expect(same(JG.order_for("spring"),{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"}) and same(JG.order_for("summer"),{"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"})
		and same(JG.order_for("autumn"),{"bobo":"gold_ore","ferry":"stone","depot":"copper_ore"}) and same(JG.order_for("winter"),{"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"}),"seasonal order table")
	expect(JG.amount_for("gold_ore")==2 and JG.amount_for("copper_ore")==4 and JG.amount_for("stone")==6 and JG.amount_for("wood")==0,"amounts gold 2 / copper 4 / stone 6")
	for ore:String in JG.ORES:expect(str(JG.ORE_NAMES[ore])==str(World.NAMES[ore]),"%s name matches the item name"%ore)
	expect(JG.DISCLAIMER.contains("原創") and JG.DISCLAIMER.contains("非史料"),"original-fiction disclaimer")
	expect(JG.HOIST==Mines.ENTRY and JG.SHUTTLE==World.REGIONS.exit_cell("jinguashi") and JG.SHUTTLE==World.TRANSIT.points("jinguashi").shuttle.cell,"hoist = entry sign, shuttle = 山城接駁站")
	var fresh:=World.new()
	expect(JG.sort_cell(fresh.state)==Bobo.sites(fresh.state).table and JG.sort_cell(fresh.state)==TABLE and JG.claim_cell(fresh.state)==TABLE,"sort/claim at Bobo's table (23,20)")
	expect(JG.dest_cell(fresh.state,"bobo")==TABLE and JG.dest_cell(fresh.state,"ferry")==JG.SHUTTLE and JG.dest_cell(fresh.state,"depot")==JG.HOIST,"destination cells")
	expect(JG.dest_at(fresh.state,JG.HOIST)=="depot" and JG.dest_at(fresh.state,Vector2i(1,1))=="","dest_at")
	expect(World.NAMES.get(KIT)=="礦燈" and World.BUILD.get(KIND)=={"name":"礦燈",KIT:1},"lantern kit and build entry")
	expect(JG.LANTERN_SOURCE=="來源：金瓜石回訪" and JG.LANTERN_PROJECT=="對應工程：合作礦場升降台修復" and not JG.LANTERN_BLURB.is_empty(),"provenance constants")
	expect(not KIND in World.UNDO_SOLID,"lantern is walk-through decor")
	expect(World.BUILD.has("water_share_plaque") and World.NAMES.has("water_share_plaque_kit") and World.BUILD.has("lamp") and World.BUILD.has("lantern_post"),"existing ids untouched")
	var prices:=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	expect(not prices.has(KIT) and not World.OTHER_SALES.has(KIT) and not World.CROPS.has(KIT) and not World.FISH.has(KIT),"lantern kit has no price")
	expect(not Market.sellable(KIT) and not World.trade_items().has(KIT) and World.trade_items().has("wood") and not World.trade_items().has("water_share_plaque_kit"),"lantern kit is not stall-listable nor tradeable")
	expect(not World.SHIPPING.quote([[KIT,1]],{KIT:1},prices).ok,"shipping quote refuses the lantern kit")
	# Client-shaped snapshots.
	var snap:={"time":0.0,"mine_depths":{"hoist":true},"bobo_workshop":{"site":0,"own_done":true}}
	expect(JG.unlocked(snap) and JG.player_ready(snap) and not JG.completed(snap),"view: unlocked/ready from a client-shaped snapshot")
	expect(JG.sort_block(snap)=="" and JG.ship_block(snap,"bobo",{})==JG.UNSORTED%"波波的整理桌" and JG.claim_block(snap,{})==JG.NOT_DONE,"view: block reasons before any sort")
	expect(JG.sort_block({"time":0.0,"mine_depths":{"hoist":false},"bobo_workshop":{"own_done":true}})==JG.LOCKED,"view: LOCKED without the hoist")
	expect(JG.sort_block({"time":0.0,"mine_depths":{"hoist":true},"bobo_workshop":{"own_done":false}})==JG.NOT_READY,"view: NOT_READY without own Bobo sort")
	snap[JG.STATE_KEY]={"crates":{"bobo":"gold_ore","ferry":"stone","depot":""},"day":0,"sent":[],"completed":false,"done_day":0,"claimed_own":false}
	var rows:=JG.rows(snap,{"gold_ore":1})
	expect(rows.size()==3 and rows[0].id=="bobo" and rows[0].ok and rows[0].amount==2 and rows[0].have==1 and not rows[1].ok and rows[1].needed=="copper_ore" and rows[2].ore=="" and rows[2].needed_name=="石材","view: rows() ore/needed/amount/have/ok")
	expect(JG.rows(snap)[0].have==-1,"view: rows() without inventory has have=-1")
	expect(JG.ship_block(snap,"ferry",{})==JG.WRONG_ORE%["渡口家園工坊","石材","銅礦"] and JG.ship_block(snap,"depot",{})==JG.UNSORTED%"坑內礦務站","view: WRONG_ORE / UNSORTED")
	expect(JG.ship_block(snap,"bobo",{})==JG.OTHER_WRONG%"波波的整理桌","view: OTHER_WRONG")
	snap[JG.STATE_KEY].crates={"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"}
	expect(JG.ship_block(snap,"bobo",{"gold_ore":1})==JG.SHORT%["含金礦料",2,1] and JG.ship_block(snap,"bobo",{"gold_ore":2})=="","view: SHORT then ok")
	snap["time"]=14*DAY+5.0
	expect(JG.order_season(snap)=="summer" and JG.ship_block(snap,"bobo",{"gold_ore":2})==JG.WRONG_ORE%["波波的整理桌","含金礦料","銅礦"],"view: nothing sent yet, a new season changes the order")
	snap[JG.STATE_KEY].sent=["ferry"]
	snap[JG.STATE_KEY].day=1
	expect(JG.order_season(snap)=="spring" and JG.ship_block(snap,"bobo",{"gold_ore":2})=="" and JG.sort_block(snap)==JG.SENT_LOCKED and JG.ship_block(snap,"ferry",{})==JG.ALREADY_SENT%"渡口家園工坊","view: after the first send the order stays locked to day 1 (spring)")
	snap[JG.STATE_KEY]={"crates":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},"day":1,"sent":["bobo","ferry","depot"],"completed":true,"done_day":15,"claimed_own":true}
	expect(JG.completed(snap) and JG.claim_block(snap,{})==JG.CLAIMED and JG.claimed_own(snap) and JG.sort_block(snap)==JG.ALREADY_DONE,"view: claimed_own from the snapshot flag")
	snap[JG.STATE_KEY].claimed_own=false
	expect(JG.can_claim(snap,{}) and JG.claim_block(snap,{KIT:JG.MAX_ITEM})==JG.BAG_FULL,"view: can_claim / BAG_FULL")
	expect(JG.public({})=={},"public() without a record")

## Every interaction point is a real standable spot reachable on foot from the shuttle arrival.
func check_site() -> void:
	var w:=World.new()
	w.switch_region("jinguashi")
	var seen:={Vector2i(12,20):true}
	var queue:=[Vector2i(12,20)]
	while not queue.is_empty():
		var c:Vector2i=queue.pop_front()
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var n:=c+d
			if seen.has(n) or n.x<0 or n.y<0 or n.x>=World.SIZE.x or n.y>=World.SIZE.y:continue
			if not w.can_stand(Vector2(n)+Vector2(0.5,0.5)):continue
			seen[n]=true
			queue.append(n)
	for spot:Vector2 in [AT_TABLE,AT_HOIST,AT_SHUTTLE]:
		expect(w.can_stand(spot) and seen.has(Vector2i(spot)),"standing spot %s is walkable and reachable from the shuttle"%str(spot))
	expect(AT_TABLE.distance_to(Vector2(TABLE)+Vector2(0.5,0.5))<=JG.REACH and AT_HOIST.distance_to(Vector2(JG.HOIST)+Vector2(0.5,0.5))<=JG.REACH and AT_SHUTTLE.distance_to(Vector2(JG.SHUTTLE)+Vector2(0.5,0.5))<=JG.REACH,"spots within reach")
	for cell:Vector2i in [TABLE,JG.HOIST,JG.SHUTTLE]:
		expect(w.protected(cell),"point %s is a protected existing feature"%str(cell))
	w.switch_region("home")

# --------------------------------------------------------------- main world --

func main_flow(w:World,path:String) -> bool:
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	if not expect(earn_picnic(w,ALPHA),"picnic earned"):return false
	jg(w,ALPHA,AT_TABLE)
	refuse(w,ALPHA,JG.SORT_ACTION,TABLE,"bobo:gold_ore",JG.LOCKED,"sort before the hoist repair")
	jg(w,ALPHA,AT_SHUTTLE)
	refuse(w,ALPHA,JG.SHIP_ACTION,JG.SHUTTLE,"",JG.LOCKED,"ship before the hoist repair")
	if not expect(earn_hoist(w,ALPHA),"Q07 hoist repair earned through mine_hoist_repair"):return false
	expect(w.save(),"pre-revisit world saves")
	var legacy_path:=temp_path("pre-revisit")
	expect(DirAccess.copy_absolute(path,legacy_path)==OK,"copy the pre-revisit save")
	# Prerequisite / placement rejections.
	jg(w,ALPHA,AT_TABLE)
	refuse(w,ALPHA,JG.SORT_ACTION,TABLE,"bobo:gold_ore",JG.NOT_READY,"alpha has not sorted with Bobo yet")
	if not expect(earn_bobo(w,ALPHA),"alpha's first Bobo sort earned"):return false
	jg(w,BETA,AT_TABLE)
	refuse(w,BETA,JG.SORT_ACTION,TABLE,"bobo:gold_ore",JG.NOT_READY,"beta not ready (sort)")
	jg(w,BETA,AT_HOIST)
	refuse(w,BETA,JG.SHIP_ACTION,JG.HOIST,"",JG.NOT_READY,"beta not ready (ship)")
	jg(w,BETA,AT_TABLE)
	refuse(w,BETA,JG.CLAIM_ACTION,TABLE,"",JG.NOT_READY,"beta not ready (claim)")
	put(w,ALPHA,HOME_SPOT,"home")
	refuse(w,ALPHA,JG.SORT_ACTION,TABLE,"bobo:gold_ore",JG.WRONG_REGION,"sort from home")
	put(w,ALPHA,Vector2(32.5,24.5),"lanyang")
	refuse(w,ALPHA,JG.SHIP_ACTION,JG.HOIST,"",JG.WRONG_REGION,"ship from Lanyang")
	put(w,ALPHA,Vector2(35.5,20.5),"mine_4")
	refuse(w,ALPHA,JG.SHIP_ACTION,Mines.SERVICE,"",JG.WRONG_REGION,"ship from the B4 depot")
	jg(w,ALPHA,AT_HOIST)
	refuse(w,ALPHA,JG.SORT_ACTION,JG.HOIST,"bobo:gold_ore",JG.WRONG_SORT_CELL,"sort at the hoist")
	refuse(w,ALPHA,JG.SHIP_ACTION,COPPER_NODE,"",JG.WRONG_SHIP_CELL,"ship at a copper node")
	refuse(w,ALPHA,JG.CLAIM_ACTION,JG.HOIST,"",JG.WRONG_CLAIM_CELL,"claim at the hoist")
	jg(w,ALPHA,AT_SHUTTLE)
	refuse(w,ALPHA,JG.SORT_ACTION,TABLE,"bobo:gold_ore",JG.TOO_FAR,"sort from the shuttle")
	refuse(w,ALPHA,JG.SHIP_ACTION,JG.HOIST,"",JG.TOO_FAR,"ship at the hoist from the shuttle")
	jg(w,ALPHA,AT_TABLE)
	for bad:String in ["","bobo","bobo:","bobo:wood","mine:stone","bobo:gold_ore:1","BOBO:gold_ore"," bobo:gold_ore",":"]:
		refuse(w,ALPHA,JG.SORT_ACTION,TABLE,bad,JG.BAD_SORT,"malformed sort extra '%s'"%bad)
	refuse(w,ALPHA,JG.SHIP_ACTION,TABLE,"x",JG.BAD_EXTRA,"ship with an extra")
	refuse(w,ALPHA,JG.SHIP_ACTION,TABLE,"",JG.UNSORTED%"波波的整理桌","ship before anything is sorted")
	refuse(w,ALPHA,JG.CLAIM_ACTION,TABLE,"",JG.NOT_DONE,"claim before completion")
	refuse(w,ALPHA,JG.CLAIM_ACTION,TABLE,"x",JG.BAD_EXTRA,"claim with an extra")
	expect(not w.state.has(JG.STATE_KEY),"no record before the first successful sort")
	# Day 1 (spring): bobo gold 2, ferry copper 4, depot stone 6.
	expect(JG.today(w.state)==1 and JG.order_season(w.state)=="spring","premise: day 1 spring")
	var s1:=sort(w,ALPHA,"bobo","copper_ore","alpha sorts copper into Bobo's crate (wrong)")
	expect(str(s1.message)==JG.SORT_OK%["銅礦","波波的整理桌"],"sort message (%s)"%str(s1.message))
	expect(same(w.state.get(JG.STATE_KEY),{"crates":{"bobo":"copper_ore","ferry":"","depot":""},"day":0,"sent":[],"completed":false,"done_day":0,"claimed":{}}),"record created by the first sort")
	refuse(w,ALPHA,JG.SORT_ACTION,TABLE,"bobo:copper_ore",JG.SAME_SORT%"銅礦","same ore again")
	pl(w,ALPHA).inventory["copper_ore"]=4
	refuse(w,ALPHA,JG.SHIP_ACTION,TABLE,"",JG.WRONG_ORE%["波波的整理桌","銅礦","含金礦料"],"wrong ore in Bobo's crate is named")
	pl(w,ALPHA).inventory.erase("copper_ore")
	sort(w,ALPHA,"bobo","gold_ore","alpha re-sorts gold into Bobo's crate")
	refuse(w,ALPHA,JG.SHIP_ACTION,TABLE,"",JG.OTHER_WRONG%"波波的整理桌","Bobo's crate right but the others unsorted")
	jg(w,ALPHA,AT_SHUTTLE)
	refuse(w,ALPHA,JG.SHIP_ACTION,JG.SHUTTLE,"",JG.UNSORTED%"渡口家園工坊","ferry crate unsorted")
	# Beta catches up and sorts the other two crates.
	if not expect(earn_bobo(w,BETA),"beta's first Bobo sort earned (catch-up path)"):return false
	sort(w,BETA,"ferry","copper_ore","beta sorts copper into the ferry crate")
	sort(w,BETA,"depot","gold_ore","beta sorts gold into the depot crate (wrong)")
	jg(w,ALPHA,AT_HOIST)
	pl(w,ALPHA).inventory["stone"]=6
	refuse(w,ALPHA,JG.SHIP_ACTION,JG.HOIST,"",JG.WRONG_ORE%["坑內礦務站","含金礦料","石材"],"wrong ore in the depot crate is named")
	sort(w,BETA,"depot","stone","beta fixes the depot crate")
	expect(JG.rows(w.state).all(func(r):return r.ok and not r.sent),"all three crates match the spring order")
	# Alpha ships Bobo's crate; short first.
	jg(w,ALPHA,AT_TABLE)
	refuse(w,ALPHA,JG.SHIP_ACTION,TABLE,"",JG.SHORT%["含金礦料",2,0],"alpha has no gold left")
	pl(w,ALPHA).inventory["gold_ore"]=2
	var bag_before:Dictionary=pl(w,ALPHA).inventory.duplicate(true)
	var sh:=ship(w,ALPHA,"bobo","alpha ships Bobo's crate")
	expect(str(sh.message)==JG.SHIP_OK%["波波的整理桌","含金礦料",2,1],"ship message (%s)"%str(sh.message))
	var want_bag:Dictionary=bag_before.duplicate(true)
	want_bag["gold_ore"]=0
	expect(same(pl(w,ALPHA).inventory,want_bag),"exactly 2 gold_ore taken from alpha's bag")
	expect(same(w.state[JG.STATE_KEY],{"crates":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},"day":1,"sent":["bobo"],"completed":false,"done_day":0,"claimed":{}}),"record after the first send (day stamped)")
	refuse(w,ALPHA,JG.SHIP_ACTION,TABLE,"",JG.ALREADY_SENT%"波波的整理桌","Bobo's crate twice")
	refuse(w,ALPHA,JG.SORT_ACTION,TABLE,"bobo:copper_ore",JG.SENT_LOCKED,"re-sort after a send")
	# Beta earns copper on the Jinguashi node and ships the ferry crate.
	put(w,BETA,Vector2(53.5,24.5),"home")
	ok(w,BETA,"borrow_mine_pick",World.COPPER_CELL,"","beta borrows the public pick")
	jg(w,BETA,Vector2(27.5,20.5))
	ok(w,BETA,"pick",COPPER_NODE,"","beta mines a Jinguashi copper node")
	expect(int(pl(w,BETA).inventory.get("copper_ore",0))==4,"beta earned exactly 4 copper_ore")
	ship(w,BETA,"ferry","beta ships the ferry crate at the shuttle")
	expect(int(pl(w,BETA).inventory.get("copper_ore",0))==0,"beta's 4 copper_ore taken")
	# Summer arrives before the last crate: the order stays locked to day 1.
	set_day(w,14)
	expect(JG.today(w.state)==15 and Weather.season_on_day(14.0)=="summer" and JG.order_season(w.state)=="spring","day 15 is summer but the batch keeps the spring order")
	var done:=ship(w,ALPHA,"depot","alpha ships the depot crate by the hoist: completion")
	expect(str(done.message)==JG.COMPLETE_OK and JG.completed(w.state),"completion message and flag")
	expect(int(pl(w,ALPHA).inventory.get("stone",0))==0,"alpha's 6 stone taken")
	expect(same(w.state[JG.STATE_KEY],{"crates":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},"day":1,"sent":["bobo","ferry","depot"],"completed":true,"done_day":15,"claimed":{}}),"exact completed record (no names or tokens)")
	jg(w,BETA,AT_TABLE)
	refuse(w,BETA,JG.SORT_ACTION,TABLE,"bobo:stone",JG.ALREADY_DONE,"sort after completion")
	refuse(w,BETA,JG.SHIP_ACTION,TABLE,"",JG.ALREADY_DONE,"ship after completion")
	# Claims: once each.
	jg(w,ALPHA,AT_TABLE)
	var kits_before:=int(pl(w,ALPHA).inventory.get(KIT,0))
	var claim:=ok(w,ALPHA,JG.CLAIM_ACTION,TABLE,"","alpha claims the lantern")
	expect(str(claim.message)==JG.CLAIM_OK and int(pl(w,ALPHA).inventory.get(KIT,0))==kits_before+1,"alpha gets exactly one kit")
	refuse(w,ALPHA,JG.CLAIM_ACTION,TABLE,"",JG.CLAIMED,"alpha claims twice")
	pl(w,BETA).inventory[KIT]=JG.MAX_ITEM
	refuse(w,BETA,JG.CLAIM_ACTION,TABLE,"",JG.BAG_FULL,"beta's kit count at the cap")
	pl(w,BETA).inventory.erase(KIT)
	ok(w,BETA,JG.CLAIM_ACTION,TABLE,"","beta claims the lantern")
	expect(int(pl(w,BETA).inventory.get(KIT,0))==1,"beta gets one kit")
	# A player who joins later.
	w.add_player(LATE,"Late")
	jg(w,LATE,AT_TABLE)
	refuse(w,LATE,JG.CLAIM_ACTION,TABLE,"",JG.NOT_READY,"late joiner must sort with Bobo before claiming")
	if not expect(earn_bobo(w,LATE),"late joiner earns own Bobo sort"):return false
	ok(w,LATE,JG.CLAIM_ACTION,TABLE,"","late joiner claims the lantern")
	refuse(w,LATE,JG.CLAIM_ACTION,TABLE,"",JG.CLAIMED,"late joiner claims twice")
	var claimed:Array=w.state[JG.STATE_KEY].claimed.keys()
	claimed.sort()
	var want:=[ALPHA,BETA,LATE]
	want.sort()
	expect(claimed==want,"claim set = alpha, beta, late")
	expect(w.save() and validates(JSON.parse_string(FileAccess.get_file_as_string(path))),"completed world saves and validates")
	var legacy:=World.new()
	expect(legacy.load_world(legacy_path) and not legacy.recovered_from_backup and not legacy.state.has(JG.STATE_KEY),"pre-revisit save (no field) loads without migration")
	return true

# --------------------------------------------------------------- placement --

func check_placement(w:World) -> void:
	put(w,ALPHA,HOME_SPOT,"home")
	var bag:Dictionary=pl(w,ALPHA).inventory
	expect(int(bag.get(KIT,0))==1,"alpha holds one lantern kit")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the lantern")
	expect(int(bag.get(KIT,0))==0 and same(w.state.objects.get(World.key(BUILD_TILE),{}),{"type":KIND,"owner":ALPHA,"items":{}}),"kit consumed, object on the home layer")
	expect(not w.blocked(BUILD_TILE) and w.can_stand(Vector2(BUILD_TILE)+Vector2(0.5,0.5)),"lantern is walk-through")
	refuse(w,ALPHA,"build",MOVE_TILE,KIND,"","second lantern without a kit")
	ok(w,ALPHA,"move_object",BUILD_TILE,"%d,%d"%[MOVE_TILE.x,MOVE_TILE.y],"alpha moves the lantern")
	expect(w.state.objects.has(World.key(MOVE_TILE)) and not w.state.objects.has(World.key(BUILD_TILE)),"lantern moved")
	put(w,BETA,HOME_SPOT,"home")
	refuse(w,BETA,"remove",MOVE_TILE,"","","beta cannot remove alpha's lantern")
	ok(w,ALPHA,"remove",MOVE_TILE,"","alpha picks the lantern up")
	expect(int(bag.get(KIT,0))==1 and not w.state.objects.has(World.key(MOVE_TILE)),"removal returns the kit")
	bag["wood"]=int(bag.get("wood",0))+20
	ok(w,ALPHA,"build",CHEST_TILE,"chest","alpha builds a shared chest")
	ok(w,ALPHA,"deposit",CHEST_TILE,KIT,"lantern kit goes into the chest")
	expect(int(bag.get(KIT,0))==0 and int(w.state.objects[World.key(CHEST_TILE)].items.get(KIT,0))==1,"kit stored in the chest")
	ok(w,ALPHA,"withdraw",CHEST_TILE,KIT,"lantern kit comes back out")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the lantern again (stays for the save test)")

func check_not_currency(w:World) -> void:
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
	for field in [JG.STATE_KEY,"mine_depths","bobo_workshop","objects"]:
		expect(same(reloaded.state.get(field),w.state.get(field)),"state.%s equal after reload"%field)
	expect(typeof(reloaded.state[JG.STATE_KEY].day)==TYPE_INT and typeof(reloaded.state[JG.STATE_KEY].done_day)==TYPE_INT,"reload normalises day/done_day to int")
	for token in [ALPHA,BETA,LATE]:
		expect(same(reloaded.state.players[token].inventory,pl(w,token).inventory),"%s bag equal after reload"%token.left(16))
	put(reloaded,LATE,AT_TABLE,"jinguashi")
	refuse(reloaded,LATE,JG.CLAIM_ACTION,TABLE,"",JG.CLAIMED,"claims survive reload")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"saved world parses and validates"):return
	var fixture:=temp_path("fixture")
	var old:Dictionary=pristine_of(base)
	expect(validates(old) and write_json(fixture,old) and World.new().load_world(fixture),"old-shape save without jinguashi_revisit (no lantern anywhere) loads")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["record is a list","record is null","record missing claimed","record extra key","crates missing depot","crates extra crate",
		"crate unknown ore","crate ore is a number","crates is a list","day in the future","day fractional","day zero with sends","day set with nothing sent",
		"unknown dest","duplicate dest","completed with two sends","three sends not completed","done_day without completion",
		"completed without done_day","done_day before day","crates off the day's order","claimed before completion","claimed by a stranger",
		"claim value false","claimer without a Bobo sort","record without the hoist","completed is a string","lantern placed without completion",
		"lantern kit in a bag without completion","lantern kit in a chest without completion","lantern in a regional layer without completion"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	expect(labels.size()>=20,"at least 20 tamper cases (%d)"%labels.size())
	var control:Dictionary=base.duplicate(true)
	control.players["nobobo-token-1234"]=control.players[BETA].duplicate(true)
	expect(validates(control),"control: the extra never-sorted player alone validates (so the claim is what is rejected)")
	var partial:Dictionary=pristine_of(base)
	partial[JG.STATE_KEY]={"crates":{"bobo":"gold_ore","ferry":"","depot":""},"day":0,"sent":[],"completed":false,"done_day":0,"claimed":{}}
	expect(validates(partial),"control: a sorted-but-unsent record validates")

## base without the record and without any lantern object or kit.
func pristine_of(base:Dictionary) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.erase(JG.STATE_KEY)
	s.objects.erase(World.key(BUILD_TILE))
	for token in s.players:(s.players[token].inventory as Dictionary).erase(KIT)
	return s

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var r:Dictionary=s[JG.STATE_KEY]
	match label:
		"record is a list":s[JG.STATE_KEY]=[r]
		"record is null":s[JG.STATE_KEY]=null
		"record missing claimed":r.erase("claimed")
		"record extra key":r["by"]=ALPHA
		"crates missing depot":r.crates.erase("depot")
		"crates extra crate":r.crates["mine"]="stone"
		"crate unknown ore":r.crates.bobo="wood"
		"crate ore is a number":r.crates.bobo=1
		"crates is a list":r.crates=["gold_ore","copper_ore","stone"]
		"day in the future":r.day=int(Weather.day_index(float(s.time)))+2
		"day fractional":r.day=1.5
		"day zero with sends":r.day=0
		"day set with nothing sent":
			s=pristine_of(base)
			s[JG.STATE_KEY]={"crates":{"bobo":"gold_ore","ferry":"","depot":""},"day":1,"sent":[],"completed":false,"done_day":0,"claimed":{}}
		"unknown dest":r.sent=["bobo","ferry","mine"]
		"duplicate dest":r.sent=["bobo","ferry","ferry"]
		"completed with two sends":r.sent=["bobo","ferry"]
		"three sends not completed":
			r.completed=false
			r.done_day=0
			r.claimed={}
		"done_day without completion":
			s=pristine_of(base)
			s[JG.STATE_KEY]={"crates":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},"day":1,"sent":["bobo"],"completed":false,"done_day":3,"claimed":{}}
		"completed without done_day":r.done_day=0
		"done_day before day":
			r.day=15
			r.done_day=3
			r.crates={"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"}
		"crates off the day's order":r.crates={"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"}
		"claimed before completion":
			r.completed=false
			r.done_day=0
			r.sent=["bobo"]
		"claimed by a stranger":r.claimed["stranger-token-0000"]=true
		"claim value false":r.claimed[ALPHA]=false
		"claimer without a Bobo sort":
			s.players["nobobo-token-1234"]=s.players[BETA].duplicate(true)
			r.claimed["nobobo-token-1234"]=true
		"record without the hoist":s.mine_depths.hoist=false
		"completed is a string":r.completed="true"
		"lantern placed without completion":
			s=pristine_of(base)
			s.objects[World.key(BUILD_TILE)]={"type":KIND,"owner":ALPHA,"items":{}}
		"lantern kit in a bag without completion":
			s=pristine_of(base)
			s.players[BETA].inventory[KIT]=1
		"lantern kit in a chest without completion":
			s=pristine_of(base)
			s.objects[World.key(CHEST_TILE)].items[KIT]=1
		"lantern in a regional layer without completion":
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
	w.add_player("jgrevisit-gamma-token-77aa","Gamma")
	session.peers={1:ALPHA,2:"jgrevisit-gamma-token-77aa"}
	var tokens:=[ALPHA,BETA,LATE,"jgrevisit-gamma-token-77aa"]
	var want:={"crates":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},"day":1,"sent":["bobo","ferry","depot"],"completed":true,"done_day":15}
	for region in ["home","jinguashi"]:
		var public:Dictionary=session.public_state(region)
		var rec:Variant=public.get(JG.STATE_KEY)
		expect(rec is Dictionary and same(rec,want),"public_state(%s) carries crates/day/sent/completed/done_day only"%region)
		var text:=JSON.stringify(public)
		var leaked:=false
		for token:String in tokens:
			if text.contains(token):leaked=true
		expect(not leaked,"public_state(%s) contains no raw player token"%region)
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.get(JG.STATE_KEY,{}).get("claimed_own")==true and not snap[JG.STATE_KEY].has("claimed"),"alpha's snapshot: own claim flag only")
	expect(JG.claimed_own(snap) and JG.completed(snap) and JG.claim_block(snap,{})==JG.CLAIMED and JG.player_ready(snap),"client helpers on alpha's snapshot")
	var dump:=JSON.stringify(snap)
	var leaked2:=false
	for token:String in tokens:
		if dump.contains(token):leaked2=true
	expect(not leaked2,"alpha's snapshot contains no raw token")
	session.peers={1:"jgrevisit-gamma-token-77aa"}
	session._send_snapshot(1)
	var gamma_snap:Dictionary=session.snapshot
	expect(gamma_snap.get(JG.STATE_KEY,{}).get("claimed_own")==false and not gamma_snap[JG.STATE_KEY].has("claimed"),"gamma's snapshot: completion visible, own flag false, no claim map")
	expect(JG.claim_block(gamma_snap,{})==JG.NOT_READY,"gamma (no Bobo sort) sees NOT_READY on the client")
	var fresh:=World.new()
	fresh.add_player("solo-token-123456","Solo")
	session.world=fresh
	session.peers={1:"solo-token-123456"}
	expect(not session.public_state("home").has(JG.STATE_KEY),"a world without the record publishes no jinguashi_revisit key")
	session._send_snapshot(1)
	expect(not session.snapshot.has(JG.STATE_KEY),"no record: snapshot has no jinguashi_revisit")
	session.world=null
	session.queue_free()
	w.save_path=keep
	w.state.players.erase("jgrevisit-gamma-token-77aa")

# ----------------------------------------------------------------- seasons --

func check_seasons() -> void:
	var order:=["spring","summer","autumn","winter"]
	for i in order.size():
		var season:String=order[i]
		var w:=earned_world()
		if not expect(w!=null,"%s: earned fixture (picnic + hoist + Bobo sort)"%season):continue
		set_day(w,int(SEASON_DAYS[season]))
		expect(JG.order_season(w.state)==season and same(JG.order(w.state),JG.order_for(season)),"%s: premise day %d uses the %s order"%[season,int(SEASON_DAYS[season])+1,season])
		# Previous season's assignment is wrong now.
		var wrong:Dictionary=JG.order_for(order[(i+3)%4])
		var right:Dictionary=JG.order_for(season)
		for dest:String in JG.DESTS:sort(w,ALPHA,dest,str(wrong[dest]),"%s: off-season sort %s"%[season,dest])
		var bad_dest:=""
		for dest:String in JG.DESTS:
			if str(wrong[dest])!=str(right[dest]):
				bad_dest=dest
				var have:=str(wrong[dest])
				pl(w,ALPHA).inventory[have]=JG.amount_for(have)
				jg(w,ALPHA,spot_for(dest))
				refuse(w,ALPHA,JG.SHIP_ACTION,JG.dest_cell(w.state,dest),"",JG.WRONG_ORE%[JG.DEST_NAMES[dest],JG.ORE_NAMES[have],JG.ORE_NAMES[right[dest]]],"%s: off-season crate refused at %s"%[season,dest])
				break
		expect(not bad_dest.is_empty(),"%s: the previous season's assignment differs somewhere"%season)
		for dest:String in JG.DESTS:
			if str(wrong[dest])!=str(right[dest]):sort(w,ALPHA,dest,str(right[dest]),"%s: sort %s"%[season,dest])
		for dest:String in JG.DESTS:
			var ore:=str(right[dest])
			pl(w,ALPHA).inventory[ore]=JG.amount_for(ore)
			ship(w,ALPHA,dest,"%s: ship %s"%[season,dest])
		expect(JG.completed(w.state) and int(w.state[JG.STATE_KEY].day)==int(SEASON_DAYS[season])+1 and validates(w.state),"%s: completed and the state validates"%season)

# ------------------------------------------------------------------ module --

func check_module() -> void:
	var bare:={"players":{"x":{"x":23.5,"y":21.5,"inventory":{}}},"mine_depths":{"hoist":true},"bobo_workshop":{"site":0,"done":{"x":true},"jobs":{}},"time":0.0}
	expect(JG.apply(bare,"nobody",JG.SORT_ACTION,TABLE,"bobo:stone",true).message==JG.NO_PLAYER,"module: unknown player")
	expect(JG.apply(bare,"x","bobo_sort_start",TABLE,"",true).message==JG.BAD_EXTRA,"module: foreign action")
	expect(JG.apply(bare,"x",JG.SORT_ACTION,TABLE,"bobo:stone",false).message==JG.WRONG_REGION,"module: wrong region")
	bare[JG.STATE_KEY]={"crates":{"bobo":"stone"},"day":0,"sent":[],"completed":false,"done_day":0,"claimed":{}}
	var before:=var_to_bytes(bare)
	expect(JG.apply(bare,"x",JG.SORT_ACTION,TABLE,"bobo:gold_ore",true).message==JG.BAD_EXTRA and var_to_bytes(bare)==before,"module: corrupt record refused without writing")
	bare.erase(JG.STATE_KEY)
	var r:=JG.apply(bare,"x",JG.SORT_ACTION,TABLE,"depot:stone",true)
	expect(r.ok==true and same(bare[JG.STATE_KEY].crates,{"bobo":"","ferry":"","depot":"stone"}),"module: sort writes the record")
