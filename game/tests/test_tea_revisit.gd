extends SceneTree
## 第 40 章「貓空與鶯歌回訪・茶罐大單」(scripts/tea_revisit.gd) + 茶陶組 rules test.
## Headless, World-level (World.act / save / load_world) plus an in-process Session
## for the public snapshot. No network.
##
## EARNED through real World.act: every player's tea comparison (tea_intro → tea_potter →
## tea_fire / tea_fire_take → tea_pick / tea_roast / tea_take → tea_pack light:jar →
## tea_ship → tea_sell → tea_return → tea_reclaim → second batch tea_pack light:fiber →
## tea_ship → tea_sell → tea_discuss = comparison_complete), which also earns each
## player's first recycled jar (tea_returned_jar 1, the jar that came back from the
## delivery); one extra deep roast per player (tea_pick / tea_roast deep / tea_take =
## tea_deep 1); every tea_revisit_jar / fill / send / claim; every build / move / remove /
## deposit / withdraw of the tea ware, the chest build. Timers pass through World.step.
## WRITTEN DIRECTLY (disclosed): chapter_one.shipped/watered, board=true, picnic=true
## (tea_ceramics' own suites do the same), player region/x/y and travel_book.visited
## (standing spots, no travel action), the extra recycled jars beyond the earned one
## (tea_returned_jar / tea_worn_jar) and the extra roasted tea (tea_light / tea_deep),
## wood for the chest, state.time jumps forward (day 15 = first day of summer, and the
## season fixtures), the kit count at the 1e9 cap for BAG_FULL, and the tampered /
## legacy save files.
const World=preload("res://scripts/world.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Market=preload("res://scripts/market_stall.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Lanyang=preload("res://scripts/lanyang_revisit.gd")
const ALPHA:="tearevisit-alpha-token-51c2"
const BETA:="tearevisit-beta-token-0d9e"
const LATE:="tearevisit-late-token-a3f7"
const KIT:="tea_ware_kit"
const KIND:="tea_ware"
const HOME_SPOT:=Vector2(39.5,33.5)
const BUILD_TILE:=Vector2i(38,34)
const MOVE_TILE:=Vector2i(37,35)
const CHEST_TILE:=Vector2i(40,35)
const AT_POTTER:=Vector2(20.5,21.5)
const AT_PACKER:=Vector2(26.5,21.5)
const ARRIVAL:=Vector2(13.5,25.5)
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
	print("TEA_REVISIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("tea-revisit-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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
	if region in World.TRANSIT.ROUTE:p.travel_book.visited[region]=true

func yingge(w:World,token:String,at:Vector2=AT_POTTER) -> void:
	put(w,token,at,"yingge")

func maokong(w:World,token:String,at:Vector2=AT_PACKER) -> void:
	put(w,token,at,"maokong")

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"tearevisit-req-%d"%serial,action,p,extra)

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

## Moves time forward only (tea timers stay consistent with the clock).
func set_day(w:World,day_index:int) -> void:
	var target:=float(day_index)*DAY+30.0
	if target>float(w.state.time):w.state["time"]=target

func earn_chapter(w:World) -> void:
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state["board"]=true
	w.state["picnic"]=true

## One tea worksite action from a standing spot one tile below the site.
func tea(w:World,token:String,action:String,region:String,cell:Vector2i,extra:String="") -> bool:
	put(w,token,Vector2(cell)+Vector2(0.5,1.5),region)
	var r:=act(w,token,action,cell,extra)
	if not r.ok:push_error("tea chain step %s failed: %s"%[action,str(r.message)])
	return bool(r.ok)

func wait(w:World,seconds:float) -> bool:
	return w.step(seconds,true)

## Earned two-packaging comparison through the real tea actions. Leaves the player with
## the one recycled jar that came back from the jar delivery (tea_returned_jar 1) and
## one deep roast (tea_deep 1). Returns false on any failed step.
func earn_comparison(w:World,token:String) -> bool:
	var bag:Dictionary=pl(w,token).inventory
	var jars_before:=int(bag.get("tea_returned_jar",0))
	var deep_before:=int(bag.get("tea_deep",0))
	if not tea(w,token,"tea_intro","home",Tea.RECEIVER):return false
	if not tea(w,token,"tea_potter",Tea.YINGGE,Tea.POTTER):return false
	if not tea(w,token,"tea_fire",Tea.YINGGE,Tea.KILN) or not wait(w,Tea.KILN_SECONDS):return false
	if not tea(w,token,"tea_fire_take",Tea.YINGGE,Tea.KILN):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[0]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not wait(w,Tea.ROAST_SECONDS.light) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:jar") or not tea(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not wait(w,Tea.SHIPPING_SECONDS) or not tea(w,token,"tea_sell","home",Tea.RECEIVER) or not tea(w,token,"tea_return","home",Tea.RECEIVER):return false
	if not wait(w,Tea.RETURN_SECONDS) or not tea(w,token,"tea_reclaim",Tea.MAOKONG,Tea.PACKER):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[1]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not wait(w,Tea.ROAST_SECONDS.light) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:fiber") or not tea(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not wait(w,Tea.SHIPPING_SECONDS) or not tea(w,token,"tea_sell","home",Tea.RECEIVER):return false
	if not tea(w,token,"tea_discuss",Tea.MAOKONG,Tea.TEA_NPC):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[2]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"deep"):return false
	if not wait(w,Tea.ROAST_SECONDS.deep) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	return Tea.own_record(w.state,token).comparison_complete==true and int(bag.get("tea_returned_jar",0))==jars_before+1 and int(bag.get("tea_deep",0))==deep_before+1

func earned_world() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	earn_chapter(w)
	if not earn_comparison(w,ALPHA):return null
	return w

func give(w:World,token:String,item:String,count:int) -> void:
	var bag:Dictionary=pl(w,token).inventory
	bag[item]=int(bag.get(item,0))+count

func hand(w:World,token:String,item:String,label:String) -> Dictionary:
	yingge(w,token)
	return ok(w,token,TR.JAR_ACTION,TR.POTTER,item,label)

func fill(w:World,token:String,style:String,label:String) -> Dictionary:
	maokong(w,token)
	return ok(w,token,TR.FILL_ACTION,TR.PACKER,style,label)

func record_is(w:World,returned:int,worn:int,light:int,deep:int,day:int,completed:bool,done_day:int,claimed:Dictionary={}) -> bool:
	return same(w.state.get(TR.STATE_KEY),{"jars":{"tea_returned_jar":returned,"tea_worn_jar":worn},"filled":{"light":light,"deep":deep},"day":day,"completed":completed,"done_day":done_day,"claimed":claimed})

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(TR.ACTIONS==["tea_revisit_jar","tea_revisit_fill","tea_revisit_send","tea_revisit_claim"],"action names")
	for action:String in TR.ACTIONS:
		expect(action.length()<=24 and Session.extra_allowed(action,"tea_returned_jar"),"%s passes the Session transport bounds"%action)
		expect(not action in Tea.SITES.keys()+JG.ACTIONS+Lanyang.ACTIONS+World.MEMORY_EXHIBIT.ACTIONS+["pick","build","transit"],"%s does not collide with existing actions"%action)
	var seen_orders:={}
	for season:String in Weather.SEASONS:
		var order:Dictionary=TR.order_for(season)
		expect(order.size()==2 and int(order.light)+int(order.deep)==TR.TOTAL and int(order.light)>=1 and int(order.deep)>=1,"%s order is 6 jars with both styles (%s)"%[season,str(order)])
		expect(not TR.reason_for(season).is_empty() and TR.reason_for(season).contains("茶茶"),"%s has 茶茶's reason"%season)
		seen_orders[JSON.stringify(order)]=true
	for i in 4:
		expect(TR.order_for(Weather.SEASONS[i])!=TR.order_for(Weather.SEASONS[(i+3)%4]),"%s order differs from the previous season's"%Weather.SEASONS[i])
	expect(seen_orders.size()==4,"four distinct seasonal mixes")
	expect(same(TR.order_for("spring"),{"light":4,"deep":2}) and same(TR.order_for("summer"),{"light":5,"deep":1})
		and same(TR.order_for("autumn"),{"light":2,"deep":4}) and same(TR.order_for("winter"),{"light":1,"deep":5}),"seasonal order table")
	for item:String in TR.JAR_NAMES:expect(str(TR.JAR_NAMES[item])==str(World.NAMES[item]),"%s name matches the item name"%item)
	for style:String in TR.STYLES:
		expect(str(TR.TEA_NAMES[style])==str(World.NAMES[TR.TEA_ITEMS[style]]),"%s tea name matches the item name"%style)
		expect(str(TR.TEA_ITEMS[style])=="tea_"+style,"%s tea item id"%style)
	expect(TR.JAR_ITEMS==["tea_returned_jar","tea_worn_jar"] and Tea.RETURN_ITEM.tea_jar=="tea_returned_jar" and Tea.RETURN_ITEM.tea_returned_jar=="tea_worn_jar","only jars that came back from a delivery count")
	expect(TR.DISCLAIMER=="回訪情節與訂單數字為原創，非史料。","original-fiction disclaimer")
	expect(TR.TITLE=="貓空與鶯歌回訪・茶罐大單","title")
	expect(TR.POTTER==Tea.POTTER and TR.PACKER==Tea.PACKER and TR.JAR_REGION==Tea.YINGGE and TR.FILL_REGION==Tea.MAOKONG,"potter / packer / regions are the existing tea points")
	expect(TR.jar_cell()==TR.POTTER and TR.claim_cell()==TR.POTTER and TR.fill_cell()==TR.PACKER and TR.send_cell()==TR.PACKER,"step cells")
	expect(World.NAMES.get(KIT)=="茶陶組" and World.BUILD.get(KIND)=={"name":"茶陶組",KIT:1},"tea ware kit and build entry")
	expect(TR.TEAWARE_SOURCE=="來源：貓空與鶯歌回訪" and TR.TEAWARE_PROJECT=="對應紀錄：茶陶合作手帳（貓空茶園與鶯歌陶坊）" and TR.TEAWARE_BLURB.contains("茶壺") and TR.TEAWARE_BLURB.contains("杯"),"provenance constants")
	expect(not KIND in World.UNDO_SOLID,"tea ware is walk-through decor")
	expect(World.BUILD.has("mine_lantern") and World.NAMES.has("mine_lantern_kit") and World.BUILD.has("water_share_plaque") and World.NAMES.get("tea_jar")=="陶罐","existing ids untouched")
	var prices:=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	expect(not prices.has(KIT) and not World.OTHER_SALES.has(KIT) and not World.CROPS.has(KIT) and not World.FISH.has(KIT),"tea ware kit has no price")
	expect(not Market.sellable(KIT) and not World.trade_items().has(KIT) and World.trade_items().has("wood") and not World.trade_items().has("mine_lantern_kit"),"tea ware kit is not stall-listable nor tradeable")
	expect(not World.SHIPPING.quote([[KIT,1]],{KIT:1},prices).ok,"shipping quote refuses the tea ware kit")
	# Client-shaped snapshots.
	var snap:={"time":0.0,"tea_ceramics":{"own_record":{"comparison_complete":true}}}
	expect(TR.player_ready(snap) and not TR.completed(snap) and TR.order_season(snap)=="spring","view: ready from a client-shaped snapshot")
	expect(TR.jar_block(snap,"tea_returned_jar",{})==TR.NO_JAR%"回收陶罐" and TR.jar_block(snap,"tea_returned_jar",{"tea_returned_jar":1})=="","view: jar_block NO_JAR then ok")
	expect(TR.jar_block(snap,"tea_jar",{"tea_jar":1})==TR.NEW_JAR and TR.jar_block(snap,"tea_spent_jar",{"tea_spent_jar":1})==TR.SPENT_JAR and TR.jar_block(snap,"wood",{})==TR.BAD_JAR,"view: new / spent / unknown jars")
	expect(TR.fill_block(snap,"light",{"tea_light":1})==TR.NEED_JARS%[0,0] and TR.fill_block(snap,"green",{})==TR.BAD_STYLE,"view: fill needs a checked jar")
	expect(TR.send_block(snap)==TR.NOT_FILLED%0 and TR.claim_block(snap,{})==TR.NOT_DONE,"view: send / claim before anything")
	var cold:={"time":0.0,"tea_ceramics":{"own_record":{"comparison_complete":false}}}
	expect(TR.jar_block(cold,"tea_returned_jar",{"tea_returned_jar":1})==TR.NOT_READY and TR.fill_block(cold,"light",{})==TR.NOT_READY and TR.send_block(cold)==TR.NOT_READY and TR.claim_block(cold,{})==TR.NOT_READY and not TR.player_ready({"time":0.0}),"view: NOT_READY without the comparison")
	snap[TR.STATE_KEY]={"jars":{"tea_returned_jar":4,"tea_worn_jar":2},"filled":{"light":4,"deep":0},"day":1,"completed":false,"done_day":0,"claimed_own":false}
	expect(TR.jars_total(snap)==6 and TR.filled_total(snap)==4 and TR.jar_block(snap,"tea_worn_jar",{"tea_worn_jar":1})==TR.JARS_FULL,"view: six jars collected")
	expect(TR.fill_block(snap,"light",{"tea_light":1})==TR.QUOTA_FULL%["淺焙",4,4,"深焙"] and TR.fill_block(snap,"deep",{})==TR.NO_TEA%"深焙茶" and TR.fill_block(snap,"deep",{"tea_deep":1})=="","view: QUOTA_FULL / NO_TEA / ok")
	expect(TR.fill_block(snap,"light",{"tea_light":1})=="這張單淺焙只要 4 罐，已經裝了 4 罐；剩下的要深焙。","view: quota message text")
	var rows:=TR.rows(snap,{"tea_deep":3})
	expect(rows.size()==2 and rows[0].id=="light" and rows[0].need==4 and rows[0].filled==4 and rows[0].full and rows[0].have==0 and rows[1].id=="deep" and rows[1].need==2 and rows[1].filled==0 and not rows[1].full and rows[1].have==3 and rows[1].tea_name=="深焙茶","view: rows()")
	expect(TR.rows(snap)[0].have==-1,"view: rows() without inventory has have=-1")
	var prog:=TR.progress(snap)
	expect(prog.jars_total==6 and prog.jars_needed==6 and prog.filled_total==4 and not prog.ready_to_send and prog.season=="spring" and same(prog.order,{"light":4,"deep":2}),"view: progress()")
	snap["time"]=14*DAY+5.0
	expect(TR.order_season(snap)=="spring" and TR.fill_block(snap,"deep",{"tea_deep":1})=="","view: after the first fill the order stays locked to day 1 (spring) in summer")
	snap[TR.STATE_KEY]={"jars":{"tea_returned_jar":1,"tea_worn_jar":0},"filled":{"light":0,"deep":0},"day":0,"completed":false,"done_day":0,"claimed_own":false}
	expect(TR.order_season(snap)=="summer" and same(TR.order(snap),{"light":5,"deep":1}) and TR.reason(snap)==TR.reason_for("summer"),"view: nothing filled yet, today's season sets the order")
	snap[TR.STATE_KEY]={"jars":{"tea_returned_jar":6,"tea_worn_jar":0},"filled":{"light":4,"deep":2},"day":1,"completed":false,"done_day":0,"claimed_own":false}
	expect(TR.send_block(snap)=="" and TR.fill_block(snap,"light",{"tea_light":1})==TR.ALL_FILLED and TR.progress(snap).ready_to_send,"view: six filled, ready to send")
	snap[TR.STATE_KEY]={"jars":{"tea_returned_jar":6,"tea_worn_jar":0},"filled":{"light":4,"deep":2},"day":1,"completed":true,"done_day":15,"claimed_own":true}
	expect(TR.completed(snap) and TR.claim_block(snap,{})==TR.CLAIMED and TR.claimed_own(snap) and TR.send_block(snap)==TR.ALREADY_DONE and TR.jar_block(snap,"tea_worn_jar",{"tea_worn_jar":1})==TR.ALREADY_DONE,"view: claimed_own from the snapshot flag")
	snap[TR.STATE_KEY].claimed_own=false
	expect(TR.can_claim(snap,{}) and TR.claim_block(snap,{KIT:TR.MAX_ITEM})==TR.BAG_FULL,"view: can_claim / BAG_FULL")
	expect(TR.public({})=={},"public() without a record")

## Every interaction point is a real standable spot reachable on foot from the transfer arrival.
func check_site() -> void:
	var w:=World.new()
	for region:String in ["yingge","maokong"]:
		w.switch_region(region)
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
		var spot:=AT_POTTER if region=="yingge" else AT_PACKER
		var cell:=TR.POTTER if region=="yingge" else TR.PACKER
		expect(w.can_stand(ARRIVAL) and w.can_stand(spot) and seen.has(Vector2i(spot)),"%s: standing spot %s is walkable and reachable from the transfer arrival"%[region,str(spot)])
		expect(spot.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=TR.REACH and ARRIVAL.distance_to(Vector2(cell)+Vector2(0.5,0.5))>TR.REACH,"%s: spot within reach, arrival is not"%region)
		expect(w.protected(cell),"%s: point %s is a protected existing feature"%[region,str(cell)])
		w.switch_region("home")

# --------------------------------------------------------------- main world --

func main_flow(w:World,path:String) -> bool:
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	earn_chapter(w)
	yingge(w,ALPHA)
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.NOT_READY,"alpha has not done the comparison (jar)")
	maokong(w,ALPHA)
	refuse(w,ALPHA,TR.FILL_ACTION,TR.PACKER,"light",TR.NOT_READY,"alpha has not done the comparison (fill)")
	if not expect(earn_comparison(w,ALPHA),"alpha's two-packaging comparison earned through the tea actions"):return false
	expect(w.save(),"pre-revisit world saves")
	var legacy_path:=temp_path("pre-revisit")
	expect(DirAccess.copy_absolute(path,legacy_path)==OK,"copy the pre-revisit save")
	expect(int(pl(w,ALPHA).inventory.get("tea_returned_jar",0))==1 and int(pl(w,ALPHA).inventory.get("tea_jar",0))==0,"alpha's only jar is the one that came back from the delivery")
	# Prerequisite / placement rejections.
	yingge(w,BETA)
	refuse(w,BETA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.NOT_READY,"beta not ready (jar)")
	refuse(w,BETA,TR.CLAIM_ACTION,TR.POTTER,"",TR.NOT_READY,"beta not ready (claim)")
	maokong(w,BETA)
	refuse(w,BETA,TR.SEND_ACTION,TR.PACKER,"",TR.NOT_READY,"beta not ready (send)")
	maokong(w,ALPHA)
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.WRONG_REGION_YINGGE,"hand a jar in 貓空")
	refuse(w,ALPHA,TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"claim in 貓空")
	yingge(w,ALPHA)
	refuse(w,ALPHA,TR.FILL_ACTION,TR.PACKER,"light",TR.WRONG_REGION_MAOKONG,"fill in 鶯歌")
	put(w,ALPHA,HOME_SPOT,"home")
	refuse(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"",TR.WRONG_REGION_MAOKONG,"send from home")
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.WRONG_REGION_YINGGE,"hand a jar from home")
	yingge(w,ALPHA)
	refuse(w,ALPHA,TR.JAR_ACTION,Tea.CLAY,"tea_returned_jar",TR.WRONG_JAR_CELL,"hand a jar at the clay pile")
	refuse(w,ALPHA,TR.CLAIM_ACTION,Tea.KILN,"",TR.WRONG_CLAIM_CELL,"claim at the kiln")
	maokong(w,ALPHA)
	refuse(w,ALPHA,TR.FILL_ACTION,Tea.ROASTER,"light",TR.WRONG_FILL_CELL,"fill at the roaster")
	refuse(w,ALPHA,TR.SEND_ACTION,Tea.TEA_NPC,"",TR.WRONG_SEND_CELL,"send at 茶茶")
	yingge(w,ALPHA,ARRIVAL)
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.TOO_FAR,"hand a jar from the transfer")
	maokong(w,ALPHA,ARRIVAL)
	refuse(w,ALPHA,TR.FILL_ACTION,TR.PACKER,"light",TR.TOO_FAR,"fill from the transfer")
	yingge(w,ALPHA)
	pl(w,ALPHA).inventory["tea_jar"]=1
	pl(w,ALPHA).inventory["tea_spent_jar"]=1
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_jar",TR.NEW_JAR,"a new / repaired jar is not a recycled jar")
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_spent_jar",TR.SPENT_JAR,"a spent jar is refused")
	pl(w,ALPHA).inventory.erase("tea_jar")
	pl(w,ALPHA).inventory.erase("tea_spent_jar")
	for bad:String in ["","wood","tea_returned_jar ","TEA_WORN_JAR","tea_returned_jar:1","light"]:
		refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,bad,TR.BAD_JAR,"malformed jar extra '%s'"%bad)
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar",TR.NO_JAR%"磨損陶罐","no worn jar in the bag")
	refuse(w,ALPHA,TR.CLAIM_ACTION,TR.POTTER,"",TR.NOT_DONE,"claim before completion")
	refuse(w,ALPHA,TR.CLAIM_ACTION,TR.POTTER,"x",TR.BAD_EXTRA,"claim with an extra")
	maokong(w,ALPHA)
	refuse(w,ALPHA,TR.FILL_ACTION,TR.PACKER,"light",TR.NEED_JARS%[0,0],"fill before any jar is checked")
	refuse(w,ALPHA,TR.FILL_ACTION,TR.PACKER,"green",TR.BAD_STYLE,"unknown style")
	refuse(w,ALPHA,TR.FILL_ACTION,TR.PACKER,"",TR.BAD_STYLE,"empty style")
	refuse(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"",TR.NOT_FILLED%0,"send an empty order")
	refuse(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"x",TR.BAD_EXTRA,"send with an extra")
	expect(not w.state.has(TR.STATE_KEY),"no record before the first successful action")
	# Day 1 (spring): light 4 / deep 2. Alpha hands in her earned recycled jar at 鶯歌.
	expect(TR.today(w.state)==1 and TR.order_season(w.state)=="spring","premise: day 1 spring")
	var bag_before:Dictionary=pl(w,ALPHA).inventory.duplicate(true)
	var j1:=hand(w,ALPHA,"tea_returned_jar","alpha hands in her earned recycled jar")
	expect(str(j1.message)==TR.JAR_OK%["回收陶罐",1],"jar message (%s)"%str(j1.message))
	var want_bag:Dictionary=bag_before.duplicate(true)
	want_bag["tea_returned_jar"]=0
	expect(same(pl(w,ALPHA).inventory,want_bag),"exactly one recycled jar taken from alpha's bag")
	expect(record_is(w,1,0,0,0,0,false,0),"record created by the first jar (day still 0)")
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.NO_JAR%"回收陶罐","handed jars are committed; none left")
	# Beta catches up (late-joiner path) and fills in 貓空 while alpha stays in 鶯歌.
	if not expect(earn_comparison(w,BETA),"beta's comparison earned (catch-up path)"):return false
	yingge(w,ALPHA)
	var deep_before:=int(pl(w,BETA).inventory.get("tea_deep",0))
	var f1:=fill(w,BETA,"deep","beta fills her earned deep roast")
	expect(str(f1.message)==TR.FILL_OK%["深焙茶",1,0,1],"fill message (%s)"%str(f1.message))
	expect(int(pl(w,BETA).inventory.get("tea_deep",0))==deep_before-1,"exactly one deep roast taken from beta")
	expect(record_is(w,1,0,0,1,1,false,0),"first fill stamps day 1")
	refuse(w,BETA,TR.FILL_ACTION,TR.PACKER,"deep",TR.NEED_JARS%[1,1],"no checked empty jar left for beta")
	expect(TR.fill_block(w.state,"deep",pl(w,BETA).inventory,BETA)=="從鶯歌檢查好送來的空罐有 1 只，已經裝了 1 罐；再帶回收空罐到鶯歌交給陶師。","NEED_JARS text says how many checked jars arrived")
	# Beta's own earned jar plus written jars for alpha: six in total, the seventh refused.
	hand(w,BETA,"tea_returned_jar","beta hands in her earned recycled jar")
	give(w,ALPHA,"tea_worn_jar",5)
	for i in 3:hand(w,ALPHA,"tea_worn_jar","alpha hands in worn jar %d"%(i+1))
	var j6:=hand(w,ALPHA,"tea_worn_jar","alpha hands in the sixth jar")
	expect(str(j6.message)==TR.JAR_OK%["磨損陶罐",6],"sixth jar message")
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar",TR.JARS_FULL,"a seventh jar is refused")
	expect(int(pl(w,ALPHA).inventory.get("tea_worn_jar",0))==1 and record_is(w,2,4,0,1,1,false,0),"jars 2 returned + 4 worn; alpha keeps her fifth worn jar")
	# Summer arrives before the rest is filled: the order stays locked to day 1 (spring).
	set_day(w,14)
	expect(TR.today(w.state)==15 and Weather.season_on_day(14.0)=="summer" and TR.order_season(w.state)=="spring","day 15 is summer but the batch keeps the spring order")
	maokong(w,BETA)
	refuse(w,BETA,TR.FILL_ACTION,TR.PACKER,"light",TR.NO_TEA%"淺焙茶","beta has no light roast")
	give(w,BETA,"tea_deep",2)
	fill(w,BETA,"deep","second deep fill under the locked spring order (summer would allow only 1)")
	refuse(w,BETA,TR.FILL_ACTION,TR.PACKER,"deep",TR.QUOTA_FULL%["深焙",2,2,"淺焙"],"deep quota full")
	expect(TR.fill_block(w.state,"deep",pl(w,BETA).inventory,BETA)=="這張單深焙只要 2 罐，已經裝了 2 罐；剩下的要淺焙。","deep quota message text")
	refuse(w,BETA,TR.SEND_ACTION,TR.PACKER,"",TR.NOT_FILLED%2,"send with two filled")
	give(w,BETA,"tea_light",5)
	for i in 4:fill(w,BETA,"light","beta fills light %d"%(i+1))
	refuse(w,BETA,TR.FILL_ACTION,TR.PACKER,"light",TR.ALL_FILLED,"a seventh fill is refused")
	expect(record_is(w,2,4,4,2,1,false,0),"six filled, day still 1")
	expect(int(pl(w,BETA).inventory.get("tea_light",0))==1 and int(pl(w,BETA).inventory.get("tea_deep",0))==1,"beta keeps one light and one deep roast")
	maokong(w,ALPHA)
	var done:=ok(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"","alpha sends the big order (she filled nothing)")
	expect(str(done.message)==TR.COMPLETE_OK and TR.completed(w.state),"completion message and flag")
	expect(record_is(w,2,4,4,2,1,true,15),"exact completed record (no names or tokens)")
	refuse(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"",TR.ALREADY_DONE,"send after completion")
	refuse(w,BETA,TR.FILL_ACTION,TR.PACKER,"light",TR.ALREADY_DONE,"fill after completion")
	yingge(w,ALPHA)
	refuse(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar",TR.ALREADY_DONE,"jar after completion")
	# Claims: once each.
	maokong(w,BETA)
	refuse(w,BETA,TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"claim from 貓空")
	var claim:=ok(w,ALPHA,TR.CLAIM_ACTION,TR.POTTER,"","alpha claims the tea ware")
	expect(str(claim.message)==TR.CLAIM_OK and int(pl(w,ALPHA).inventory.get(KIT,0))==1,"alpha gets exactly one kit")
	refuse(w,ALPHA,TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"alpha claims twice")
	yingge(w,BETA)
	pl(w,BETA).inventory[KIT]=TR.MAX_ITEM
	refuse(w,BETA,TR.CLAIM_ACTION,TR.POTTER,"",TR.BAG_FULL,"beta's kit count at the cap")
	pl(w,BETA).inventory.erase(KIT)
	ok(w,BETA,TR.CLAIM_ACTION,TR.POTTER,"","beta claims the tea ware")
	expect(int(pl(w,BETA).inventory.get(KIT,0))==1,"beta gets one kit")
	# A player who joins later.
	w.add_player(LATE,"Late")
	yingge(w,LATE)
	refuse(w,LATE,TR.CLAIM_ACTION,TR.POTTER,"",TR.NOT_READY,"late joiner must finish the comparison before claiming")
	if not expect(earn_comparison(w,LATE),"late joiner earns own comparison"):return false
	yingge(w,LATE)
	ok(w,LATE,TR.CLAIM_ACTION,TR.POTTER,"","late joiner claims the tea ware")
	refuse(w,LATE,TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"late joiner claims twice")
	var claimed:Array=w.state[TR.STATE_KEY].claimed.keys()
	claimed.sort()
	var want:=[ALPHA,BETA,LATE]
	want.sort()
	expect(claimed==want,"claim set = alpha, beta, late")
	put(w,LATE,HOME_SPOT,"home")
	for token in [ALPHA,BETA]:put(w,token,HOME_SPOT,"home")
	expect(w.save() and validates(JSON.parse_string(FileAccess.get_file_as_string(path))),"completed world saves and validates")
	var legacy:=World.new()
	expect(legacy.load_world(legacy_path) and not legacy.recovered_from_backup and not legacy.state.has(TR.STATE_KEY),"pre-revisit save (no field) loads without migration")
	return true

# --------------------------------------------------------------- placement --

func check_placement(w:World) -> void:
	put(w,ALPHA,HOME_SPOT,"home")
	var bag:Dictionary=pl(w,ALPHA).inventory
	expect(int(bag.get(KIT,0))==1,"alpha holds one tea ware kit")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the tea ware")
	expect(int(bag.get(KIT,0))==0 and same(w.state.objects.get(World.key(BUILD_TILE),{}),{"type":KIND,"owner":ALPHA,"items":{}}),"kit consumed, object on the home layer")
	expect(not w.blocked(BUILD_TILE) and w.can_stand(Vector2(BUILD_TILE)+Vector2(0.5,0.5)),"tea ware is walk-through")
	refuse(w,ALPHA,"build",MOVE_TILE,KIND,"","second tea ware without a kit")
	ok(w,ALPHA,"move_object",BUILD_TILE,"%d,%d"%[MOVE_TILE.x,MOVE_TILE.y],"alpha moves the tea ware")
	expect(w.state.objects.has(World.key(MOVE_TILE)) and not w.state.objects.has(World.key(BUILD_TILE)),"tea ware moved")
	put(w,BETA,HOME_SPOT,"home")
	refuse(w,BETA,"remove",MOVE_TILE,"","","beta cannot remove alpha's tea ware")
	ok(w,ALPHA,"remove",MOVE_TILE,"","alpha picks the tea ware up")
	expect(int(bag.get(KIT,0))==1 and not w.state.objects.has(World.key(MOVE_TILE)),"removal returns the kit")
	bag["wood"]=int(bag.get("wood",0))+20
	ok(w,ALPHA,"build",CHEST_TILE,"chest","alpha builds a shared chest")
	ok(w,ALPHA,"deposit",CHEST_TILE,KIT,"tea ware kit goes into the chest")
	expect(int(bag.get(KIT,0))==0 and int(w.state.objects[World.key(CHEST_TILE)].items.get(KIT,0))==1,"kit stored in the chest")
	ok(w,ALPHA,"withdraw",CHEST_TILE,KIT,"tea ware kit comes back out")
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places the tea ware again (stays for the save test)")

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
	for field in [TR.STATE_KEY,"tea_ceramics","objects"]:
		expect(same(reloaded.state.get(field),w.state.get(field)),"state.%s equal after reload"%field)
	var rr:Dictionary=reloaded.state[TR.STATE_KEY]
	expect(typeof(rr.day)==TYPE_INT and typeof(rr.done_day)==TYPE_INT and typeof(rr.jars.tea_worn_jar)==TYPE_INT and typeof(rr.filled.light)==TYPE_INT,"reload normalises counts and days to int")
	for token in [ALPHA,BETA,LATE]:
		expect(same(reloaded.state.players[token].inventory,pl(w,token).inventory),"%s bag equal after reload"%token.left(16))
	put(reloaded,LATE,AT_POTTER,"yingge")
	refuse(reloaded,LATE,TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"claims survive reload")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"saved world parses and validates"):return
	var fixture:=temp_path("fixture")
	var old:Dictionary=pristine_of(base)
	expect(validates(old) and write_json(fixture,old) and World.new().load_world(fixture),"old-shape save without tea_revisit (no tea ware anywhere) loads")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["record is a list","record is null","record missing claimed","record extra key","jars missing worn","jars extra kind","jars count negative",
		"jars count fractional","jars count string","jars total over six","jars is a list","filled missing deep","filled extra style","filled over jars",
		"filled light over the order","day in the future","day fractional","day zero with fills","day set with nothing filled","completed with five filled",
		"done_day without completion","completed without done_day","done_day before day","completed is a string",
		"claimed before completion","claimed by a stranger","claim value false","claimer without the comparison","record with no compared player",
		"tea ware placed without completion","tea ware kit in a bag without completion","tea ware kit in a chest without completion",
		"tea ware in a regional layer without completion"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	expect(labels.size()>=30,"at least 30 tamper cases (%d)"%labels.size())
	var control:Dictionary=base.duplicate(true)
	control.players["nocompare-token-1234"]=control.players[BETA].duplicate(true)
	expect(validates(control),"control: the extra never-compared player alone validates (so the claim is what is rejected)")
	var partial:Dictionary=pristine_of(base)
	partial[TR.STATE_KEY]={"jars":{"tea_returned_jar":3,"tea_worn_jar":1},"filled":{"light":2,"deep":0},"day":1,"completed":false,"done_day":0,"claimed":{}}
	expect(validates(partial),"control: a partly filled record validates")
	var only_jars:Dictionary=pristine_of(base)
	only_jars[TR.STATE_KEY]={"jars":{"tea_returned_jar":1,"tea_worn_jar":0},"filled":{"light":0,"deep":0},"day":0,"completed":false,"done_day":0,"claimed":{}}
	expect(validates(only_jars),"control: a jars-only record (day 0) validates")
	# 六罐裝滿、還沒寄出是正常的中間狀態：存檔必須能讀回來，而且讀回後仍可寄出。
	var unsent:Dictionary=pristine_of(base)
	var sent_record:Dictionary=base[TR.STATE_KEY]
	unsent[TR.STATE_KEY]={"jars":(sent_record.jars as Dictionary).duplicate(true),"filled":(sent_record.filled as Dictionary).duplicate(true),"day":sent_record.day,"completed":false,"done_day":0,"claimed":{}}
	expect(validates(unsent),"control: six filled but not yet sent validates")
	var unsent_world:=World.new()
	expect(write_json(fixture,unsent) and unsent_world.load_world(fixture),"a save with six filled jars waiting to be sent loads")
	expect(TR.progress(unsent_world.state).ready_to_send==true and not TR.completed(unsent_world.state),"the reloaded order is ready to send and not completed")

## base without the record and without any tea ware object or kit.
func pristine_of(base:Dictionary) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	s.erase(TR.STATE_KEY)
	s.objects.erase(World.key(BUILD_TILE))
	for token in s.players:(s.players[token].inventory as Dictionary).erase(KIT)
	return s

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var r:Dictionary=s[TR.STATE_KEY]
	match label:
		"record is a list":s[TR.STATE_KEY]=[r]
		"record is null":s[TR.STATE_KEY]=null
		"record missing claimed":r.erase("claimed")
		"record extra key":r["by"]=ALPHA
		"jars missing worn":r.jars.erase("tea_worn_jar")
		"jars extra kind":r.jars["tea_jar"]=0
		"jars count negative":
			r.jars.tea_worn_jar=-1
			r.jars.tea_returned_jar=7
		"jars count fractional":
			r.jars.tea_worn_jar=3.5
			r.jars.tea_returned_jar=2.5
		"jars count string":r.jars.tea_worn_jar="4"
		"jars total over six":r.jars.tea_worn_jar=5
		"jars is a list":r.jars=[2,4]
		"filled missing deep":r.filled.erase("deep")
		"filled extra style":r.filled["green"]=0
		"filled over jars":
			s=pristine_of(base)
			s[TR.STATE_KEY]={"jars":{"tea_returned_jar":1,"tea_worn_jar":0},"filled":{"light":2,"deep":0},"day":1,"completed":false,"done_day":0,"claimed":{}}
		"filled light over the order":r.filled={"light":5,"deep":1}
		"day in the future":r.day=int(Weather.day_index(float(s.time)))+2
		"day fractional":r.day=1.5
		"day zero with fills":r.day=0
		"day set with nothing filled":
			s=pristine_of(base)
			s[TR.STATE_KEY]={"jars":{"tea_returned_jar":1,"tea_worn_jar":0},"filled":{"light":0,"deep":0},"day":1,"completed":false,"done_day":0,"claimed":{}}
		"completed with five filled":r.filled={"light":3,"deep":2}
		"done_day without completion":
			s=pristine_of(base)
			s[TR.STATE_KEY]={"jars":{"tea_returned_jar":2,"tea_worn_jar":0},"filled":{"light":1,"deep":0},"day":1,"completed":false,"done_day":3,"claimed":{}}
		"completed without done_day":r.done_day=0
		"done_day before day":
			r.day=15
			r.done_day=3
			r.filled={"light":5,"deep":1}
		"completed is a string":r.completed="true"
		"claimed before completion":
			r.completed=false
			r.done_day=0
			r.filled={"light":4,"deep":1}
		"claimed by a stranger":r.claimed["stranger-token-0000"]=true
		"claim value false":r.claimed[ALPHA]=false
		"claimer without the comparison":
			s.players["nocompare-token-1234"]=s.players[BETA].duplicate(true)
			r.claimed["nocompare-token-1234"]=true
		"record with no compared player":
			s=pristine_of(base)
			s[TR.STATE_KEY]={"jars":{"tea_returned_jar":1,"tea_worn_jar":0},"filled":{"light":0,"deep":0},"day":0,"completed":false,"done_day":0,"claimed":{}}
			for token in s.tea_ceramics.players:s.tea_ceramics.players[token].comparison_complete=false
		"tea ware placed without completion":
			s=pristine_of(base)
			s.objects[World.key(BUILD_TILE)]={"type":KIND,"owner":ALPHA,"items":{}}
		"tea ware kit in a bag without completion":
			s=pristine_of(base)
			s.players[BETA].inventory[KIT]=1
		"tea ware kit in a chest without completion":
			s=pristine_of(base)
			s.objects[World.key(CHEST_TILE)].items[KIT]=1
		"tea ware in a regional layer without completion":
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
	const GAMMA:="tearevisit-gamma-token-66bb"
	w.add_player(GAMMA,"Gamma")
	session.peers={1:ALPHA,2:GAMMA}
	var tokens:=[ALPHA,BETA,LATE,GAMMA]
	var want:={"jars":{"tea_returned_jar":2,"tea_worn_jar":4},"filled":{"light":4,"deep":2},"day":1,"completed":true,"done_day":15}
	for region in ["home","maokong","yingge"]:
		var public:Dictionary=session.public_state(region)
		var rec:Variant=public.get(TR.STATE_KEY)
		expect(rec is Dictionary and same(rec,want),"public_state(%s) carries jars/filled/day/completed/done_day only"%region)
		var text:=JSON.stringify(public)
		var leaked:=false
		for token:String in tokens:
			if text.contains(token):leaked=true
		expect(not leaked,"public_state(%s) contains no raw player token"%region)
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.get(TR.STATE_KEY,{}).get("claimed_own")==true and not snap[TR.STATE_KEY].has("claimed"),"alpha's snapshot: own claim flag only")
	expect(TR.claimed_own(snap) and TR.completed(snap) and TR.claim_block(snap,{})==TR.CLAIMED and TR.player_ready(snap),"client helpers on alpha's snapshot")
	var dump:=JSON.stringify(snap)
	var leaked2:=false
	for token:String in tokens:
		if dump.contains(token):leaked2=true
	expect(not leaked2,"alpha's snapshot contains no raw token")
	session.peers={1:GAMMA}
	session._send_snapshot(1)
	var gamma_snap:Dictionary=session.snapshot
	expect(gamma_snap.get(TR.STATE_KEY,{}).get("claimed_own")==false and not gamma_snap[TR.STATE_KEY].has("claimed"),"gamma's snapshot: completion visible, own flag false, no claim map")
	expect(TR.claim_block(gamma_snap,{})==TR.NOT_READY and not TR.player_ready(gamma_snap),"gamma (no comparison) sees NOT_READY on the client")
	var fresh:=World.new()
	fresh.add_player("solo-token-123456","Solo")
	session.world=fresh
	session.peers={1:"solo-token-123456"}
	expect(not session.public_state("home").has(TR.STATE_KEY),"a world without the record publishes no tea_revisit key")
	session._send_snapshot(1)
	expect(not session.snapshot.has(TR.STATE_KEY),"no record: snapshot has no tea_revisit")
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
		if not expect(w!=null,"%s: earned fixture (comparison through the tea actions)"%season):continue
		set_day(w,int(SEASON_DAYS[season]))
		var need:Dictionary=TR.order_for(season)
		expect(TR.order_season(w.state)==season and same(TR.order(w.state),need) and TR.reason(w.state)==TR.reason_for(season),"%s: premise day %d uses the %s order"%[season,TR.today(w.state),season])
		give(w,ALPHA,"tea_worn_jar",5)
		hand(w,ALPHA,"tea_returned_jar","%s: earned jar"%season)
		for j in 5:hand(w,ALPHA,"tea_worn_jar","%s: worn jar %d"%[season,j+1])
		give(w,ALPHA,"tea_light",int(need.light)+1)
		give(w,ALPHA,"tea_deep",int(need.deep))
		# Spring/autumn fill light first and hit the light quota; summer/winter fill deep first.
		var first:="light" if i%2==0 else "deep"
		var second:="deep" if first=="light" else "light"
		for k in int(need[first]):fill(w,ALPHA,first,"%s: fill %s %d"%[season,first,k+1])
		expect(int(pl(w,ALPHA).inventory.get(TR.TEA_ITEMS[first],0))>=1,"%s: alpha still holds %s tea, so only the quota stops her"%[season,first])
		refuse(w,ALPHA,TR.FILL_ACTION,TR.PACKER,first,TR.QUOTA_FULL%[TR.STYLE_NAMES[first],int(need[first]),int(need[first]),TR.STYLE_NAMES[second]],"%s: %s quota full"%[season,first])
		for k in int(need[second]):fill(w,ALPHA,second,"%s: fill %s %d"%[season,second,k+1])
		ok(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"","%s: send"%season)
		expect(TR.completed(w.state) and int(w.state[TR.STATE_KEY].day)==int(SEASON_DAYS[season])+1 and same(TR.filled(w.state),need),"%s: completed with the season's mix"%season)
		put(w,ALPHA,HOME_SPOT,"home")
		expect(validates(w.state),"%s: the state validates"%season)

# ------------------------------------------------------------------ module --

func check_module() -> void:
	var bare:={"players":{"x":{"x":20.5,"y":21.5,"inventory":{"tea_worn_jar":1}}},"tea_ceramics":{"players":{"x":{"comparison_complete":true}}},"time":0.0}
	expect(TR.apply(bare,"nobody",TR.JAR_ACTION,TR.POTTER,"tea_worn_jar","yingge").message==TR.NO_PLAYER,"module: unknown player")
	expect(TR.apply(bare,"x","tea_potter",TR.POTTER,"","yingge").message==TR.BAD_EXTRA,"module: foreign action")
	expect(TR.apply(bare,"x",TR.JAR_ACTION,TR.POTTER,"tea_worn_jar","maokong").message==TR.WRONG_REGION_YINGGE,"module: wrong region")
	bare[TR.STATE_KEY]={"jars":{"tea_worn_jar":1},"filled":{"light":0,"deep":0},"day":0,"completed":false,"done_day":0,"claimed":{}}
	var before:=var_to_bytes(bare)
	expect(TR.apply(bare,"x",TR.JAR_ACTION,TR.POTTER,"tea_worn_jar","yingge").message==TR.BAD_EXTRA and var_to_bytes(bare)==before,"module: corrupt record refused without writing")
	bare.erase(TR.STATE_KEY)
	var r:=TR.apply(bare,"x",TR.JAR_ACTION,TR.POTTER,"tea_worn_jar","yingge")
	expect(r.ok==true and same(bare[TR.STATE_KEY].jars,{"tea_returned_jar":0,"tea_worn_jar":1}) and int(bare.players.x.inventory.tea_worn_jar)==0,"module: jar writes the record and takes the jar")
