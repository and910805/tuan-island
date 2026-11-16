extends SceneTree
## 第 40 章「茶陶上桌」(scripts/tea_service.gd) rules test.
## Headless, World-level (World.act / save / load_world), plus an in-process Session for
## the public snapshot. No network.
##
## EARNED through real World.act: the picnic (World.act "picnic", which places the shared
## table at 39,30); alpha's whole tea comparison (tea_intro → tea_potter → tea_fire /
## tea_fire_take → tea_pick / tea_roast / tea_take → tea_pack light:jar → tea_ship → tea_sell →
## tea_return → tea_reclaim → tea_pack light:fiber → tea_ship → tea_sell → tea_discuss, plus one
## deep roast), the island-wide 貓空與鶯歌回訪 (six tea_revisit_jar, six tea_revisit_fill,
## tea_revisit_send) and alpha's tea_ware_kit claim (tea_revisit_claim); every tea_service_place /
## brew / sip / take; every build / remove of the home tea_ware decoration; the table warmer
## install, warm serve, hotpot / watermelon serve and claims. Timers pass through World.step,
## and so does every world-day change for the cold-tea rule (section 13: two real
## World.step(WEATHER.DAY_SECONDS) calls; state.time on a World is never written).
## WRITTEN DIRECTLY (disclosed): chapter_one.shipped/watered and board=true, soup 2 / bread 1
## for the picnic, player region/x/y and travel_book.visited (standing spots, no travel
## action), alpha's five extra worn jars and the roasted tea needed to fill the revisit order
## beyond her earned deep roast, beta's tea_ware_kit counts (beta never does the comparison),
## every tea_light / tea_deep used for brewing, alpha's kit at the 1e9 cap for BAG_FULL, the
## table-warmer materials, trout_hotpot / watermelon_platter counts, and the tampered / legacy
## save files (including the round.day tamper cases). Pure-helper and module-level checks use
## hand-written dictionaries, some with a hand-written "time" (a later world day) and
## hand-written round.day values to exercise the cold rule and valid().
const World=preload("res://scripts/world.gd")
const TS=preload("res://scripts/tea_service.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Community=preload("res://scripts/community.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const ALPHA:="teaservice-alpha-token-3b7e"
const BETA:="teaservice-beta-token-c41d"
const GUESTS:=["teaservice-guest-1-aa","teaservice-guest-2-bb","teaservice-guest-3-cc","teaservice-guest-4-dd","teaservice-guest-5-ee"]
const STRANGER:="teaservice-stranger-0000"
const KIT:="tea_ware_kit"
const KIND:="tea_ware"
const TABLE:=Vector2i(39,30)
const BOARD:=Vector2i(40,29)
const NEAR:=Vector2(40.5,30.5)
const HOME_SPOT:=Vector2(39.5,33.5)
const FAR:=Vector2(39.5,35.5)
const BUILD_TILE:=Vector2i(38,34)
const AT_POTTER:=Vector2(20.5,21.5)
const AT_PACKER:=Vector2(26.5,21.5)

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
	check_helpers()
	check_module()
	var path:=temp_path("main")
	var w:=World.new()
	w.save_path=path
	main_flow(w,path)
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("TEA_SERVICE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("tea-service-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

static func bag_of(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String="home") -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y
	if region in World.TRANSIT.ROUTE:p.travel_book.visited[region]=true

func setinv(w:World,token:String,item:String,count:int) -> void:
	w.state.players[token]["inventory"][item]=count

func give(w:World,token:String,item:String,count:int) -> void:
	var bag:Dictionary=pl(w,token).inventory
	bag[item]=int(bag.get(item,0))+count

func act(w:World,token:String,action:String,p:Vector2i,extra:String="",request:String="") -> Dictionary:
	serial+=1
	return w.act(token,request if not request.is_empty() else "teaservice-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

## Rejected with the exact message and the whole world state byte-identical (canonical).
func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or str(r.get("message",""))==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func record(w:World) -> Variant:
	return w.state.get(TS.STATE_KEY,null)

## Everyone at a standing spot within reach of the table (alpha at NEAR, beta at HOME_SPOT).
func seat_everyone(w:World) -> void:
	put(w,ALPHA,NEAR)
	put(w,BETA,HOME_SPOT)
	for i in GUESTS.size():put(w,GUESTS[i],Vector2(37.5+i,31.5) if i<4 else Vector2(41.5,29.5))

## Save, check the file validates, reload into a fresh World and compare state.tea_service.
## The reloaded World gets save_path "" so actions on it never touch the main save.
func roundtrip(w:World,path:String,label:String) -> World:
	expect(w.save(),"%s: world saves"%label)
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(data is Dictionary and validates(data),"%s: saved file passes SaveSchema"%label)
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"%s: fresh World reloads the save"%label)
	expect(same(reloaded.state.get(TS.STATE_KEY),w.state.get(TS.STATE_KEY)),"%s: state.tea_service equal after reload (%s)"%[label,str(reloaded.state.get(TS.STATE_KEY))])
	reloaded.save_path=""
	return reloaded

# --------------------------------------------------- earned revisit fixture --

## One tea worksite action from a standing spot one tile below the site.
func tea(w:World,token:String,action:String,region:String,cell:Vector2i,extra:String="") -> bool:
	put(w,token,Vector2(cell)+Vector2(0.5,1.5),region)
	var r:=act(w,token,action,cell,extra)
	if not r.ok:push_error("tea chain step %s failed: %s"%[action,str(r.message)])
	return bool(r.ok)

func wait(w:World,seconds:float) -> bool:
	return w.step(seconds,true)

## Earned two-packaging comparison through the real tea actions (copied from
## test_tea_revisit.gd). Leaves one recycled jar and one deep roast in the bag.
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

## Alpha alone completes the island-wide order through the real revisit actions and claims
## her kit. Her earned recycled jar + 5 written worn jars; earned deep roast + written tea.
func complete_revisit(w:World) -> bool:
	give(w,ALPHA,"tea_worn_jar",5)
	put(w,ALPHA,AT_POTTER,"yingge")
	if not bool(act(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar").get("ok",false)):return false
	for i in 5:
		if not bool(act(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar").get("ok",false)):return false
	var need:Dictionary=TR.order(w.state)
	for style:String in TR.STYLES:
		var item:String=TR.TEA_ITEMS[style]
		var have:=int(pl(w,ALPHA).inventory.get(item,0))
		if have<int(need[style]):give(w,ALPHA,item,int(need[style])-have)
	put(w,ALPHA,AT_PACKER,"maokong")
	for style:String in TR.STYLES:
		for k in int(need[style]):
			if not bool(act(w,ALPHA,TR.FILL_ACTION,TR.PACKER,style).get("ok",false)):return false
	if not bool(act(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"").get("ok",false)):return false
	put(w,ALPHA,AT_POTTER,"yingge")
	if not bool(act(w,ALPHA,TR.CLAIM_ACTION,TR.POTTER,"").get("ok",false)):return false
	put(w,ALPHA,NEAR)
	return TR.completed(w.state) and int(pl(w,ALPHA).inventory.get(KIT,0))==1

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(TS.ACTIONS==["tea_service_place","tea_service_take","tea_service_brew","tea_service_sip"] and TS.PLACE_ACTION=="tea_service_place" and TS.TAKE_ACTION=="tea_service_take" and TS.BREW_ACTION=="tea_service_brew" and TS.SIP_ACTION=="tea_service_sip","action names")
	expect(TS.STATE_KEY=="tea_service" and TS.KIT==KIT and TS.CUPS==6 and is_equal_approx(TS.REACH,3.2) and TS.LIMIT==TR.MAX_ITEM,"state key, kit id, six cups, reach 3.2, limit = revisit MAX_ITEM")
	expect(World.TEA_SERVICE==TS,"World.TEA_SERVICE is scripts/tea_service.gd")
	expect(World.NAMES.get(KIT)==TS.KIT_NAME,"kit name matches World.NAMES")
	expect(TS.STYLES==["light","deep"],"two styles")
	for style:String in TS.STYLES:
		expect(TS.TEA_ITEMS[style]==TR.TEA_ITEMS[style] and str(World.NAMES.get(TS.TEA_ITEMS[style]))==str(TS.STYLE_NAMES[style]) and TS.style_name(style)==TS.STYLE_NAMES[style],"%s tea item and name match World.NAMES"%style)
	expect(TS.style_name("green")=="茶","style_name fallback")
	for action:String in TS.ACTIONS:
		expect(action.length()<=24 and Session.extra_allowed(action,""),"%s passes the Session transport bounds"%action)
		expect(action not in Community.ACTIONS and action not in Warmer.ACTIONS and action not in TR.ACTIONS,"%s does not collide with community / warmer / revisit actions"%action)
	for style:String in TS.STYLES:expect(Session.extra_allowed(TS.BREW_ACTION,style),"brew extra '%s' passes the Session transport bounds"%style)
	expect(TS.NO_TEA%"淺焙茶"=="你的背包裡沒有淺焙茶。到貓空合作茶園的焙茶爐焙一份再來。","NO_TEA format")

# ------------------------------------------------------------- pure helpers --

func check_helpers() -> void:
	# Server-shaped state (tokens present).
	var server:={"players":{ALPHA:{},BETA:{}},"picnic":true,"community":{"table":"39,30"},"tea_revisit":{"completed":true}}
	expect(not TS.placed(server) and TS.public(server)=={} and TS.current_round(server)=={} and TS.portions(server)==0,"server: nothing placed")
	expect(TS.status_text(server)=="共餐桌上還沒有茶陶組。","server: status before placing")
	expect(TS.place_block(server,{KIT:1})=="" and TS.place_block(server,{KIT:0})==TS.NO_KIT and TS.place_block(server,{})==TS.NO_KIT and TS.place_block(server,null)==TS.NO_KIT,"server: place_block kit count")
	expect(TS.take_block(server,{},ALPHA)==TS.NOT_PLACED and TS.sip_block(server,ALPHA)==TS.NOT_PLACED and TS.brew_block(server,"light",{"tea_light":1})==TS.NOT_PLACED,"server: take / sip / brew before placing")
	expect(TS.brew_block(server,"green",{"tea_light":1})==TS.BAD_STYLE and TS.brew_block(server,"",{})==TS.BAD_STYLE,"server: brew_block BAD_STYLE before NOT_PLACED")
	expect(TS.place_block({"picnic":false,"community":{"table":""}},{KIT:1})==TS.LOCKED and TS.sip_block({"picnic":false})==TS.LOCKED,"LOCKED before the picnic")
	expect(TS.place_block({"picnic":true,"community":{"table":""},"tea_revisit":{"completed":true}},{KIT:1})==TS.NO_TABLE,"NO_TABLE without a table cell")
	expect(TS.place_block({"picnic":true,"community":{"table":"39,30"},"tea_revisit":{"completed":false}},{KIT:1})==TS.NOT_DONE and TS.place_block({"picnic":true,"community":{"table":"39,30"}},{KIT:1})==TS.NOT_DONE,"NOT_DONE before the revisit is completed")
	server[TS.STATE_KEY]={"lender":ALPHA}
	expect(TS.placed(server) and TS.lender_own(server,ALPHA) and not TS.lender_own(server,BETA) and not TS.lender_own(server),"server: placed / lender_own by token")
	expect(TS.place_block(server,{KIT:1})==TS.ALREADY,"server: ALREADY")
	expect(TS.take_block(server,{},ALPHA)=="" and TS.take_block(server,{},BETA)==TS.NOT_LENDER and TS.take_block(server,{})==TS.NOT_LENDER and TS.take_block(server,{KIT:TS.LIMIT},ALPHA)==TS.BAG_FULL,"server: take_block lender / NOT_LENDER / BAG_FULL")
	expect(TS.brew_block(server,"light",{})==TS.NO_TEA%"淺焙茶" and TS.brew_block(server,"deep",{"tea_light":3})==TS.NO_TEA%"深焙茶" and TS.brew_block(server,"deep",{"tea_deep":1})=="","server: brew_block NO_TEA / ok")
	expect(TS.sip_block(server,ALPHA)==TS.NO_ROUND and TS.current_round(server)=={} and TS.portions(server)==0,"server: no round yet")
	expect(TS.status_text(server)=="茶陶組擺在共餐桌上，茶壺還是空的。" and TS.public(server)=={"placed":true},"server: placed status / public")
	expect(TS.today(server)==1 and TS.today(server)==TR.today(server),"server: no time key reads as world day 1 (same as tea_revisit.today)")
	server[TS.STATE_KEY]["round"]={"style":"light","portions":5,"claimed":{ALPHA:true},"day":1}
	expect(same(TS.current_round(server),{"style":"light","portions":5,"day":1,"left":5,"cold":false}) and TS.portions(server)==5,"server: current_round / portions (%s)"%str(TS.current_round(server)))
	expect(TS.sipped_own(server,ALPHA) and not TS.sipped_own(server,BETA) and not TS.sipped_own(server),"server: sipped_own by token")
	expect(TS.sip_block(server,ALPHA)==TS.SIPPED and TS.sip_block(server,BETA)=="","server: sip_block SIPPED / ok")
	expect(TS.take_block(server,{},ALPHA)==TS.TEA_LEFT and TS.take_block(server,{},BETA)==TS.NOT_LENDER,"server: take_block TEA_LEFT for the lender, NOT_LENDER for others")
	expect(TS.brew_block(server,"deep",{"tea_deep":1})==TS.TEA_LEFT_BREW and TS.brew_block(server,"deep",{})==TS.TEA_LEFT_BREW,"server: brew_block TEA_LEFT_BREW before NO_TEA")
	expect(TS.status_text(server)=="桌上有一壺淺焙茶，還剩 5／6 杯。","server: status mid-round (%s)"%TS.status_text(server))
	var pub:=TS.public(server)
	expect(same(pub,{"placed":true,"round":{"style":"light","portions":5,"day":1}}) and not JSON.stringify(pub).contains(ALPHA),"server: public() whitelists placed/round(style,portions,day), no token (%s)"%str(pub))
	server[TS.STATE_KEY]["round"]["portions"]=0
	expect(TS.sip_block(server,BETA)==TS.EMPTY and TS.sip_block(server,ALPHA)==TS.EMPTY,"server: EMPTY before SIPPED")
	expect(TS.take_block(server,{},ALPHA)=="" and TS.brew_block(server,"deep",{"tea_deep":1})=="","server: finished round can be taken back or re-brewed")
	expect(TS.status_text(server)=="上一壺淺焙茶已經喝完了。","server: finished status")
	# Cold tea: the same 5-cup round seen on a later world day (hand-written time).
	var day_s:float=World.WEATHER.DAY_SECONDS
	server[TS.STATE_KEY]["round"]={"style":"light","portions":5,"claimed":{ALPHA:true},"day":1}
	server["time"]=day_s-1.0
	expect(TS.today(server)==1 and not bool(TS.current_round(server).cold) and TS.portions(server)==5,"server: last second of day 1 is still day 1, tea warm")
	expect(TS.take_block(server,{},ALPHA)==TS.TEA_LEFT and TS.brew_block(server,"deep",{"tea_deep":1})==TS.TEA_LEFT_BREW,"server: same-day leftover still blocks take / brew")
	server["time"]=day_s
	expect(TS.today(server)==2,"server: midnight belongs to day 2")
	expect(same(TS.current_round(server),{"style":"light","portions":0,"day":1,"left":5,"cold":true}) and TS.portions(server)==0,"server: cold round reads portions 0, left 5 (%s)"%str(TS.current_round(server)))
	expect(TS.sip_block(server,BETA)==TS.COLD and TS.sip_block(server,ALPHA)==TS.COLD,"server: COLD for everyone, checked before SIPPED")
	expect(TS.take_block(server,{},ALPHA)=="" and TS.take_block(server,{},BETA)==TS.NOT_LENDER and TS.take_block(server,{KIT:TS.LIMIT},ALPHA)==TS.BAG_FULL,"server: cold cups do not block the lender's take")
	expect(TS.brew_block(server,"deep",{"tea_deep":1})=="" and TS.brew_block(server,"deep",{})==TS.NO_TEA%"深焙茶","server: cold cups do not block brewing (NO_TEA still applies)")
	expect(TS.status_text(server)=="前一天泡的淺焙茶已經涼了，可以重新泡一壺。","server: cold status (%s)"%TS.status_text(server))
	expect(same(TS.public(server),{"placed":true,"round":{"style":"light","portions":5,"day":1}}),"server: public() of a cold round carries the cups actually left and the brew day")
	expect(TS.sipped_own(server,ALPHA) and not TS.sipped_own(server,BETA),"server: sipped_own unaffected by cold")
	server[TS.STATE_KEY]["round"]["portions"]=0
	expect(TS.sip_block(server,BETA)==TS.EMPTY and TS.status_text(server)=="上一壺淺焙茶已經喝完了。","server: an empty cold round reads EMPTY (EMPTY before COLD)")
	server[TS.STATE_KEY]["round"]={"style":"deep","portions":6,"claimed":{},"day":2}
	expect(not bool(TS.current_round(server).cold) and TS.portions(server)==6 and TS.sip_block(server,BETA)=="","server: a round brewed today is warm")
	server.erase("time")
	server[TS.STATE_KEY]["round"]={"style":"green","portions":5,"claimed":{},"day":1}
	expect(TS.current_round(server)=={} and TS.portions(server)==0,"server: unknown style reads as no round")
	server[TS.STATE_KEY]["round"]={"style":"light","portions":5,"claimed":{ALPHA:true}}
	expect(same(TS.current_round(server),{"style":"light","portions":5,"day":0,"left":5,"cold":false}),"server: a round without day reads day 0, never cold (%s)"%str(TS.current_round(server)))
	# Client-shaped snapshots (no tokens; per-recipient flags).
	var client:={"picnic":true,"community":{"table":"39,30"},"tea_revisit":{"completed":true,"claimed_own":true}}
	expect(not TS.placed(client) and TS.place_block(client,{KIT:1})=="" and TS.public(client)=={},"client: nothing placed, can place with a kit")
	client[TS.STATE_KEY]={"placed":true,"lender_own":false,"sipped_own":false}
	expect(TS.placed(client) and not TS.lender_own(client) and TS.sip_block(client)==TS.NO_ROUND and TS.brew_block(client,"light",{"tea_light":1})=="" and TS.take_block(client,{})==TS.NOT_LENDER,"client: placed only, not the lender")
	expect(TS.place_block(client,{KIT:1})==TS.ALREADY and TS.public(client)=={"placed":true},"client: ALREADY / public")
	client[TS.STATE_KEY]={"placed":true,"round":{"style":"deep","portions":3,"day":1},"lender_own":true,"sipped_own":false}
	expect(TS.today(client)==1,"client: snapshot without time reads world day 1")
	expect(TS.lender_own(client) and TS.lender_own(client,"whatever") and not TS.sipped_own(client),"client: lender_own flag wins")
	expect(same(TS.current_round(client),{"style":"deep","portions":3,"day":1,"left":3,"cold":false}) and TS.portions(client)==3,"client: current_round / portions (%s)"%str(TS.current_round(client)))
	expect(TS.sip_block(client)=="" and TS.take_block(client,{})==TS.TEA_LEFT and TS.brew_block(client,"light",{"tea_light":1})==TS.TEA_LEFT_BREW,"client: lender mid-round")
	expect(TS.status_text(client)=="桌上有一壺深焙茶，還剩 3／6 杯。","client: status")
	expect(same(TS.public(client),{"placed":true,"round":{"style":"deep","portions":3,"day":1}}),"client: public() re-derives the same view (%s)"%str(TS.public(client)))
	client[TS.STATE_KEY]={"placed":true,"round":{"style":"deep","portions":3.0,"day":1.0},"lender_own":false,"sipped_own":true}
	var floaty:Dictionary=TS.current_round(client)
	expect(TS.sip_block(client)==TS.SIPPED and TS.take_block(client,{})==TS.NOT_LENDER and typeof(floaty.portions)==TYPE_INT and typeof(floaty.left)==TYPE_INT and typeof(floaty.day)==TYPE_INT,"client: sipped flag / float portions and day read as int")
	client[TS.STATE_KEY]={"placed":true,"round":{"style":"deep","portions":0,"day":1},"lender_own":true,"sipped_own":true}
	expect(TS.sip_block(client)==TS.EMPTY and TS.take_block(client,{})=="" and TS.take_block(client,{KIT:TS.LIMIT})==TS.BAG_FULL,"client: finished round, lender can take back")
	# Client snapshot carrying the world time on a later day (hand-written): brewed day 2, now day 4.
	client["time"]=3.0*World.WEATHER.DAY_SECONDS+5.0
	client[TS.STATE_KEY]={"placed":true,"round":{"style":"deep","portions":3,"day":2},"lender_own":true,"sipped_own":false}
	expect(TS.today(client)==4 and TS.today(client)==TR.today(client),"client: time on day 4 reads today 4")
	expect(same(TS.current_round(client),{"style":"deep","portions":0,"day":2,"left":3,"cold":true}) and TS.portions(client)==0,"client: later-day snapshot reports the round cold (%s)"%str(TS.current_round(client)))
	expect(TS.sip_block(client)==TS.COLD and TS.take_block(client,{})=="" and TS.brew_block(client,"light",{"tea_light":1})=="","client: cold round -> sip COLD, lender may take, anyone may re-brew")
	expect(TS.status_text(client)=="前一天泡的深焙茶已經涼了，可以重新泡一壺。","client: cold status")
	client[TS.STATE_KEY]={"placed":true,"round":{"style":"deep","portions":3,"day":4},"lender_own":false,"sipped_own":false}
	expect(not bool(TS.current_round(client).cold) and TS.portions(client)==3 and TS.sip_block(client)=="" and TS.brew_block(client,"light",{"tea_light":1})==TS.TEA_LEFT_BREW,"client: a round brewed today (day 4) is warm and still blocks brewing")

# ------------------------------------------------------------------ module --

func check_module() -> void:
	var bare:={"players":{"x":{"x":40.5,"y":30.5,"inventory":{KIT:1}}},"picnic":true,"community":{"table":"39,30"},"tea_revisit":{"completed":true}}
	var before:=var_to_bytes(bare)
	expect(TS.apply(bare,"nobody",TS.PLACE_ACTION,TABLE,"",true).message==TS.NO_PLAYER,"module: unknown player")
	expect(TS.apply(bare,"x","serve_hotpot",TABLE,"",true).message==TS.BAD_EXTRA,"module: foreign action")
	expect(TS.apply(bare,"x",TS.PLACE_ACTION,TABLE,"",false).message==TS.WRONG_REGION,"module: not at home")
	bare.community.table=""
	expect(TS.apply(bare,"x",TS.PLACE_ACTION,TABLE,"",true).message==TS.NO_TABLE,"module: NO_TABLE")
	bare.community.table="39,30"
	bare.picnic=false
	expect(TS.apply(bare,"x",TS.PLACE_ACTION,TABLE,"",true).message==TS.LOCKED,"module: LOCKED")
	bare.picnic=true
	expect(var_to_bytes(bare)==before,"module: refusals write nothing")
	var r:=TS.apply(bare,"x",TS.PLACE_ACTION,TABLE,"",true)
	expect(r.ok==true and same(bare.get(TS.STATE_KEY),{"lender":"x"}) and not bare.players.x.inventory.has(KIT),"module: place writes the record and erases the last kit")
	# valid() unit checks on minimal dictionaries.
	var base:={"players":{ALPHA:{},BETA:{}},"picnic":true,"community":{"table":"39,30"},"tea_revisit":{"completed":true}}
	expect(TS.valid(base),"valid: absent record")
	var cases:={
		"placed only":[{"lender":ALPHA},true],
		"fresh round":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":1}},true],
		"half round":[{"lender":ALPHA,"round":{"style":"deep","portions":4.0,"claimed":{ALPHA:true,BETA:true},"day":1.0}},true],
		"lender unknown":[{"lender":STRANGER},false],
		"lender int":[{"lender":5},false],
		"empty":[{},false],
		"list":[[ALPHA],false],
		"extra key":[{"lender":ALPHA,"by":BETA},false],
		"extra key with round":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":1},"x":1},false],
		"round list":[{"lender":ALPHA,"round":[]},false],
		"bad style":[{"lender":ALPHA,"round":{"style":"green","portions":6,"claimed":{},"day":1}},false],
		"portions mismatch":[{"lender":ALPHA,"round":{"style":"light","portions":5,"claimed":{},"day":1}},false],
		"portions fractional":[{"lender":ALPHA,"round":{"style":"light","portions":5.5,"claimed":{ALPHA:true},"day":1}},false],
		"portions string":[{"lender":ALPHA,"round":{"style":"light","portions":"6","claimed":{},"day":1}},false],
		"round missing claimed":[{"lender":ALPHA,"round":{"style":"light","portions":6,"day":1}},false],
		"round extra key":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":1,"total":6}},false],
		"claimed by stranger":[{"lender":ALPHA,"round":{"style":"light","portions":5,"claimed":{STRANGER:true},"day":1}},false],
		"claimed false":[{"lender":ALPHA,"round":{"style":"light","portions":5,"claimed":{ALPHA:false},"day":1}},false],
		"claimed int":[{"lender":ALPHA,"round":{"style":"light","portions":5,"claimed":{ALPHA:1},"day":1}},false],
		"old 3-key round (no day)":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{}}},false],
		"day missing, extra key instead":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"brewed":1}},false],
		"day 0":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":0}},false],
		"day negative":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":-1}},false],
		"day fractional":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":1.5}},false],
		"day string":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":"1"}},false],
		"day null":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":null}},false],
		"day in the future (2 > today 1)":[{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":2}},false],
	}
	for label:String in cases:
		var s:Dictionary=base.duplicate(true)
		s[TS.STATE_KEY]=cases[label][0]
		expect(TS.valid(s)==bool(cases[label][1]),"valid: %s -> %s"%[label,str(cases[label][1])])
	# valid() against a later world day (hand-written time: day 3).
	var late:Dictionary=base.duplicate(true)
	late["time"]=2.0*World.WEATHER.DAY_SECONDS+1.0
	expect(TS.today(late)==3,"valid fixture: hand-written time reads today 3")
	for d:Variant in [1,2,3,3.0]:
		var s:Dictionary=late.duplicate(true)
		s[TS.STATE_KEY]={"lender":ALPHA,"round":{"style":"deep","portions":6,"claimed":{},"day":d}}
		expect(TS.valid(s),"valid: day %s <= today 3 -> true"%str(d))
	for d:Variant in [4,4.0,0,2.5,3.5]:
		var s:Dictionary=late.duplicate(true)
		s[TS.STATE_KEY]={"lender":ALPHA,"round":{"style":"deep","portions":6,"claimed":{},"day":d}}
		expect(not TS.valid(s),"valid: day %s on today 3 -> false"%str(d))
	# valid() normalises portions and day to int (as after a JSON reload).
	var norm:Dictionary=late.duplicate(true)
	norm[TS.STATE_KEY]=JSON.parse_string(JSON.stringify({"lender":ALPHA,"round":{"style":"light","portions":5,"claimed":{BETA:true},"day":2}}))
	var raw_round:Dictionary=norm[TS.STATE_KEY].round
	expect(typeof(raw_round.day)==TYPE_FLOAT and typeof(raw_round.portions)==TYPE_FLOAT,"valid fixture: JSON parse yields float day / portions")
	expect(TS.valid(norm) and typeof(raw_round.day)==TYPE_INT and raw_round.day==2 and typeof(raw_round.portions)==TYPE_INT and raw_round.portions==5,"valid: JSON-parsed round normalised to int day 2 / portions 5")
	var gated:={"no picnic":["picnic",false,false],"no table":["community",{"table":""},false],"revisit not completed":["tea_revisit",{"completed":false},false],"revisit missing":["tea_revisit",{},true]}
	for label:String in gated:
		var s:Dictionary=base.duplicate(true)
		s[TS.STATE_KEY]={"lender":ALPHA}
		var field:String=gated[label][0]
		if bool(gated[label][2]):s.erase(field)
		else:s[field]=gated[label][1]
		expect(not TS.valid(s),"valid: record rejected with %s"%label)
		s.erase(TS.STATE_KEY)
		expect(TS.valid(s),"valid: the same state without the record passes (%s)"%label)

# --------------------------------------------------------------- main world --

func main_flow(w:World,path:String) -> bool:
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	for g:String in GUESTS:w.add_player(g,g.left(10))
	seat_everyone(w)
	# 1. Before the picnic: every action LOCKED, even with a bad cell / extra.
	for action:String in TS.ACTIONS:
		refuse(w,ALPHA,action,TABLE,"light" if action==TS.BREW_ACTION else "",TS.LOCKED,"%s before the picnic"%action)
	refuse(w,BETA,TS.PLACE_ACTION,BOARD,"x",TS.LOCKED,"LOCKED is checked before cell and extra")
	expect(not w.state.has(TS.STATE_KEY),"no tea_service key before the picnic")
	# 2. Real picnic (prerequisite flags written).
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state["board"]=true
	setinv(w,ALPHA,"soup",2)
	setinv(w,ALPHA,"bread",1)
	var picnic:=act(w,ALPHA,"picnic",BOARD)
	if not expect(bool(picnic.get("ok",false)) and w.state.picnic==true and Community.table_cell(w.state)==TABLE,"real picnic sets the shared table at 39,30 (%s)"%str(picnic.get("message",""))):return false
	# 3. After the picnic, before the revisit is completed.
	refuse(w,ALPHA,TS.PLACE_ACTION,TABLE,"",TS.NOT_DONE,"place before the revisit is completed")
	refuse(w,ALPHA,TS.PLACE_ACTION,TABLE,"x",TS.BAD_EXTRA,"place with an extra (BAD_EXTRA before NOT_DONE)")
	put(w,ALPHA,AT_POTTER,"yingge")
	refuse(w,ALPHA,TS.PLACE_ACTION,TABLE,"",TS.WRONG_REGION,"place from 鶯歌")
	refuse(w,ALPHA,TS.SIP_ACTION,TABLE,"",TS.WRONG_REGION,"sip from 鶯歌")
	put(w,ALPHA,NEAR)
	refuse(w,ALPHA,TS.PLACE_ACTION,Vector2i(40,31),"",TS.WRONG_CELL,"place at a neighbour cell")
	refuse(w,ALPHA,TS.BREW_ACTION,BOARD,"light",TS.WRONG_CELL,"brew at the board")
	put(w,ALPHA,FAR)
	refuse(w,ALPHA,TS.PLACE_ACTION,TABLE,"",TS.TOO_FAR,"place from five tiles away")
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"",TS.TOO_FAR,"take from five tiles away")
	put(w,ALPHA,NEAR)
	refuse(w,ALPHA,TS.BREW_ACTION,TABLE,"light",TS.NOT_PLACED,"brew with nothing on the table")
	for bad:String in ["","green","Light","light ","light:1"]:
		refuse(w,ALPHA,TS.BREW_ACTION,TABLE,bad,TS.BAD_STYLE,"brew with style '%s'"%bad)
	refuse(w,ALPHA,TS.SIP_ACTION,TABLE,"",TS.NOT_PLACED,"sip with nothing on the table")
	refuse(w,ALPHA,TS.SIP_ACTION,TABLE,"x",TS.BAD_EXTRA,"sip with an extra")
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"",TS.NOT_PLACED,"take with nothing on the table")
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"x",TS.BAD_EXTRA,"take with an extra")
	# 4. Earn the comparison, complete the revisit, claim alpha's kit.
	if not expect(earn_comparison(w,ALPHA),"alpha's tea comparison earned through the tea actions"):return false
	if not expect(complete_revisit(w),"revisit completed and alpha's kit claimed through the real actions"):return false
	seat_everyone(w)
	expect(not w.state.has(TS.STATE_KEY),"completing the revisit writes no tea_service")
	var legacy_path:=temp_path("legacy")
	expect(w.save() and DirAccess.copy_absolute(path,legacy_path)==OK,"snapshot of the pre-placement save (no tea_service key)")
	# 5. Placement.
	refuse(w,GUESTS[0],TS.PLACE_ACTION,TABLE,"",TS.NO_KIT,"guest without a kit")
	setinv(w,BETA,KIT,1)
	ok(w,BETA,"build",BUILD_TILE,KIND,"beta places her kit at home as decoration")
	var deco:Variant=w.state.objects.get(World.key(BUILD_TILE))
	expect(same(deco,{"type":KIND,"owner":BETA,"items":{}}) and int(pl(w,BETA).inventory.get(KIT,0))==0,"home tea_ware decoration built, beta's kit used")
	refuse(w,BETA,TS.PLACE_ACTION,TABLE,"",TS.NO_KIT,"beta's only kit is decorating her home")
	var alpha_before:=bag_of(pl(w,ALPHA).inventory)
	var coins_before:=int(pl(w,ALPHA).coins)
	var placed:=act(w,ALPHA,TS.PLACE_ACTION,TABLE,"","teaservice-place-once")
	expect(bool(placed.get("ok",false)) and str(placed.get("message",""))==TS.PLACED_OK,"alpha lends her kit to the table (%s)"%str(placed.get("message","")))
	expect(not pl(w,ALPHA).inventory.has(KIT),"alpha's kit key erased when it reaches 0")
	var alpha_want:=alpha_before.duplicate()
	alpha_want.erase(KIT)
	expect(same(bag_of(pl(w,ALPHA).inventory),alpha_want) and int(pl(w,ALPHA).coins)==coins_before,"place takes exactly one kit and nothing else")
	expect(same(record(w),{"lender":ALPHA}),"state.tea_service == {lender: alpha}")
	expect(same(w.state.objects.get(World.key(BUILD_TILE)),deco),"home decoration untouched by placing")
	var replay_before:=var_to_bytes(canon(w.state))
	expect(act(w,ALPHA,TS.PLACE_ACTION,TABLE,"","teaservice-place-once")==placed and var_to_bytes(canon(w.state))==replay_before,"replayed request id returns the receipt without applying twice")
	refuse(w,ALPHA,TS.PLACE_ACTION,TABLE,"",TS.ALREADY,"alpha places again")
	ok(w,BETA,"remove",BUILD_TILE,"","beta picks her decoration up")
	expect(int(pl(w,BETA).inventory.get(KIT,0))==1 and not w.state.objects.has(World.key(BUILD_TILE)),"removal returns beta's kit")
	refuse(w,BETA,TS.PLACE_ACTION,TABLE,"",TS.ALREADY,"beta (with a kit) cannot place a second set")
	refuse(w,BETA,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"beta cannot take alpha's set")
	var r1:=roundtrip(w,path,"set placed")
	refuse(r1,BETA,TS.PLACE_ACTION,TABLE,"",TS.ALREADY,"placement survives reload")
	refuse(r1,BETA,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"lender survives reload")
	# 6. Brewing.
	refuse(w,GUESTS[0],TS.BREW_ACTION,TABLE,"light",TS.NO_TEA%"淺焙茶","guest without light tea")
	refuse(w,GUESTS[0],TS.BREW_ACTION,TABLE,"deep",TS.NO_TEA%"深焙茶","guest without deep tea")
	refuse(w,BETA,TS.BREW_ACTION,TABLE,"green",TS.BAD_STYLE,"brew an unknown style")
	refuse(w,ALPHA,TS.SIP_ACTION,TABLE,"",TS.NO_ROUND,"sip before anything is brewed")
	setinv(w,BETA,"tea_light",1)
	var beta_before:=bag_of(pl(w,BETA).inventory)
	var brewed:=ok(w,BETA,TS.BREW_ACTION,TABLE,"light","beta brews her light roast")
	expect(str(brewed.get("message",""))==TS.BREWED_OK%"淺焙茶","brew message (%s)"%str(brewed.get("message","")))
	expect(not pl(w,BETA).inventory.has("tea_light"),"beta's last light roast key erased")
	var beta_want:=beta_before.duplicate()
	beta_want.erase("tea_light")
	expect(same(bag_of(pl(w,BETA).inventory),beta_want),"brew takes exactly one light roast and nothing else")
	var brew_day:int=TS.today(w.state)
	expect(brew_day>=1 and brew_day==TR.today(w.state),"world day at the first brew is a valid 1-based day (%d)"%brew_day)
	if not expect(same(record(w),{"lender":ALPHA,"round":{"style":"light","portions":6,"claimed":{},"day":brew_day}}),"round {style light, portions 6, claimed {}, day today} (%s)"%str(record(w))):return false
	expect(typeof(w.state[TS.STATE_KEY].round.day)==TYPE_INT,"brew writes day as an int")
	setinv(w,ALPHA,"tea_deep",2)
	expect(not bool(TS.current_round(w.state).cold),"same-day round is not cold")
	refuse(w,ALPHA,TS.BREW_ACTION,TABLE,"deep",TS.TEA_LEFT_BREW,"brew while same-day cups remain")
	refuse(w,BETA,TS.BREW_ACTION,TABLE,"light",TS.TEA_LEFT_BREW,"TEA_LEFT_BREW is checked before NO_TEA")
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"",TS.TEA_LEFT,"lender cannot take while same-day tea is left")
	refuse(w,BETA,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"NOT_LENDER is checked before TEA_LEFT")
	# 7. Six islanders sip once each.
	var sippers:Array=[ALPHA,BETA]+GUESTS.slice(0,4)
	for i in sippers.size():
		var who:String=sippers[i]
		var bag_before:Dictionary=pl(w,who).inventory.duplicate(true)
		var coins:=int(pl(w,who).coins)
		var r:=act(w,who,TS.SIP_ACTION,TABLE)
		expect(bool(r.get("ok",false)) and str(r.get("message",""))==TS.SIP_OK%["淺焙茶",5-i],"sipper %d drinks (%s)"%[i+1,str(r.get("message",""))])
		expect(same(pl(w,who).inventory,bag_before) and int(pl(w,who).coins)==coins,"sipper %d: sip gives no item and no coins"%(i+1))
		var pot:Dictionary=w.state[TS.STATE_KEY].round
		expect(int(pot.portions)==5-i and pot.claimed.has(who) and pot.claimed.size()==i+1 and pot.claimed[who]==true,"sipper %d: portions %d, claimed %d"%[i+1,5-i,i+1])
		if i==0:refuse(w,ALPHA,TS.SIP_ACTION,TABLE,"",TS.SIPPED,"alpha sips twice")
		if i==2:
			var r2:=roundtrip(w,path,"mid-round")
			refuse(r2,ALPHA,TS.SIP_ACTION,TABLE,"",TS.SIPPED,"sips survive reload")
			var late:=act(r2,GUESTS[4],TS.SIP_ACTION,TABLE)
			expect(bool(late.get("ok",false)) and str(late.get("message",""))==TS.SIP_OK%["淺焙茶",2],"reloaded world: another islander sips (%s)"%str(late.get("message","")))
			var reloaded_pot:Variant=r2.state.get(TS.STATE_KEY,{}).get("round")
			expect(reloaded_pot is Dictionary and typeof(reloaded_pot.get("portions"))==TYPE_INT and int(reloaded_pot.portions)==2 and reloaded_pot.claimed.size()==4,"reloaded world: portions an int 2, four claimed")
			expect(reloaded_pot is Dictionary and typeof(reloaded_pot.get("day"))==TYPE_INT and int(reloaded_pot.day)==brew_day,"reloaded world: day stays an int (%d)"%brew_day)
	expect(int(w.state[TS.STATE_KEY].round.portions)==0 and w.state[TS.STATE_KEY].round.claimed.size()==6,"six cups out, six claimed")
	refuse(w,GUESTS[4],TS.SIP_ACTION,TABLE,"",TS.EMPTY,"seventh islander finds the pot empty")
	refuse(w,ALPHA,TS.SIP_ACTION,TABLE,"",TS.EMPTY,"EMPTY is checked before SIPPED")
	var r3:=roundtrip(w,path,"finished round")
	refuse(r3,GUESTS[4],TS.SIP_ACTION,TABLE,"",TS.EMPTY,"finished round survives reload")
	refuse(w,BETA,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"beta cannot take even when the pot is empty")
	# 8. A finished round is overwritten by a new brew.
	var deep:=ok(w,ALPHA,TS.BREW_ACTION,TABLE,"deep","alpha brews deep over the finished round")
	expect(str(deep.get("message",""))==TS.BREWED_OK%"深焙茶" and int(pl(w,ALPHA).inventory.get("tea_deep",0))==1,"deep brew message, alpha's deep roast 2 → 1")
	expect(same(record(w),{"lender":ALPHA,"round":{"style":"deep","portions":6,"claimed":{},"day":TS.today(w.state)}}),"new round replaces the finished one (claims cleared, day today) (%s)"%str(record(w)))
	ok(w,GUESTS[4],TS.SIP_ACTION,TABLE,"","the former seventh islander sips from the new round")
	for who:String in [ALPHA,BETA,GUESTS[0],GUESTS[1],GUESTS[2]]:ok(w,who,TS.SIP_ACTION,TABLE,"","%s sips the deep round"%who.left(20))
	expect(int(w.state[TS.STATE_KEY].round.portions)==0,"deep round finished")
	# 9. Take back.
	setinv(w,ALPHA,KIT,TS.LIMIT)
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"",TS.BAG_FULL,"alpha's kit count at the cap")
	pl(w,ALPHA).inventory.erase(KIT)
	var alpha_bag:=bag_of(pl(w,ALPHA).inventory)
	var taken:=act(w,ALPHA,TS.TAKE_ACTION,TABLE)
	expect(bool(taken.get("ok",false)) and str(taken.get("message",""))==TS.TAKEN_OK,"alpha takes her set back (%s)"%str(taken.get("message","")))
	alpha_bag[KIT]=1
	expect(same(bag_of(pl(w,ALPHA).inventory),alpha_bag) and not w.state.has(TS.STATE_KEY),"kit +1 and state.tea_service removed")
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"",TS.NOT_PLACED,"take again")
	refuse(w,GUESTS[0],TS.SIP_ACTION,TABLE,"",TS.NOT_PLACED,"sip after the set is taken back")
	refuse(w,ALPHA,TS.BREW_ACTION,TABLE,"deep",TS.NOT_PLACED,"brew after the set is taken back")
	# 10. Place again (beta, written kits), alpha's set decorates her home.
	put(w,ALPHA,HOME_SPOT)
	ok(w,ALPHA,"build",BUILD_TILE,KIND,"alpha places her kit at home")
	put(w,ALPHA,NEAR)
	var found_deco:Variant=w.state.objects.get(World.key(BUILD_TILE))
	var alpha_deco:Variant=found_deco.duplicate(true) if found_deco is Dictionary else null
	expect(same(alpha_deco,{"type":KIND,"owner":ALPHA,"items":{}}),"alpha's home decoration")
	setinv(w,BETA,KIT,2)
	ok(w,BETA,TS.PLACE_ACTION,TABLE,"","beta lends a set after alpha took hers back")
	expect(int(pl(w,BETA).inventory.get(KIT,0))==1 and same(record(w),{"lender":BETA}),"beta 2 → 1 kit, lender beta")
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"alpha cannot take beta's set")
	refuse(w,ALPHA,TS.PLACE_ACTION,TABLE,"",TS.ALREADY,"alpha cannot place while beta's set is on the table")
	# 11. Existing table actions still work with a set on the table.
	for item:String in Warmer.INSTALL_COST:setinv(w,ALPHA,item,int(Warmer.INSTALL_COST[item]))
	ok(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"","table warmer installs with a tea set on the table")
	setinv(w,ALPHA,"trout_hotpot",6)
	ok(w,ALPHA,Warmer.SERVE_ACTION,TABLE,"","warm hotpot served with a tea set on the table")
	expect(same(w.state.community.get("hotpot"),{"portions":6,"claimed":{},"total":6}),"warm hotpot round is six portions")
	ok(w,BETA,"claim_hotpot",TABLE,"","beta claims hotpot")
	setinv(w,ALPHA,"watermelon_platter",4)
	ok(w,ALPHA,"serve_watermelon",TABLE,"","watermelon served with a tea set on the table")
	ok(w,GUESTS[0],"claim_watermelon",TABLE,"","guest claims watermelon")
	expect(same(record(w),{"lender":BETA}),"meals leave tea_service untouched")
	setinv(w,GUESTS[0],"tea_deep",1)
	ok(w,GUESTS[0],TS.BREW_ACTION,TABLE,"deep","guest brews deep with meals on the table")
	ok(w,ALPHA,TS.SIP_ACTION,TABLE,"","alpha sips beta's pot")
	ok(w,GUESTS[1],"claim_hotpot",TABLE,"","hotpot claims still work with tea on the table")
	expect(int(w.state.community.get("hotpot",{}).get("portions",-1))==4 and int(w.state.community.get("watermelon",{}).get("portions",-1))==3,"hotpot 4/6 and watermelon 3/4 after claims")
	expect(same(record(w),{"lender":BETA,"round":{"style":"deep","portions":5,"claimed":{ALPHA:true},"day":TS.today(w.state)}}),"tea round unaffected by meal claims (%s)"%str(record(w)))
	expect(same(w.state.objects.get(World.key(BUILD_TILE)),alpha_deco),"alpha's home tea_ware decoration unaffected")
	expect(same(w.state.get("table_warmer"),{"installed":true}),"warmer installed")
	# 12. Final save → reload, snapshot, tampered saves.
	var reloaded:=roundtrip(w,path,"final")
	for field in ["community","table_warmer","tea_revisit","objects","picnic"]:
		expect(same(reloaded.state.get(field),w.state.get(field)),"state.%s equal after reload"%field)
	for token:String in [ALPHA,BETA]+GUESTS:
		expect(same(bag_of(reloaded.state.players[token].inventory),bag_of(pl(w,token).inventory)),"%s bag equal after reload"%token.left(20))
	refuse(reloaded,ALPHA,TS.SIP_ACTION,TABLE,"",TS.SIPPED,"sip claims survive the final reload")
	refuse(reloaded,BETA,TS.TAKE_ACTION,TABLE,"",TS.TEA_LEFT,"beta (lender) still has to wait after reload")
	check_snapshot(reloaded)
	check_saves(path,legacy_path)
	# 13. Cold tea across a real world day (after check_saves, which reads the section-12 save).
	return cold_flow(w,path)

## Solo-world dead end fix: cups left from an earlier world day are cold. They can't be
## sipped, and they no longer block re-brewing or the lender taking the set back.
## Days advance only through World.step(WEATHER.DAY_SECONDS).
func cold_flow(w:World,path:String) -> bool:
	var d0:int=TS.today(w.state)
	var pot_before:Variant=record(w).duplicate(true) if record(w) is Dictionary else null
	if not expect(pot_before is Dictionary and int(pot_before.round.day)==d0 and int(pot_before.round.portions)==5,"cold: start from beta's same-day deep round, 5 left (%s)"%str(pot_before)):return false
	refuse(w,GUESTS[1],TS.BREW_ACTION,TABLE,"light",TS.TEA_LEFT_BREW,"cold: same-day leftover still blocks brewing")
	refuse(w,BETA,TS.TAKE_ACTION,TABLE,"",TS.TEA_LEFT,"cold: same-day leftover still blocks the lender")
	if not expect(wait(w,World.WEATHER.DAY_SECONDS) and TS.today(w.state)==d0+1,"cold: one real World.step day passes (today %d -> %d)"%[d0,TS.today(w.state)]):return false
	expect(same(record(w),pot_before),"cold: World.step leaves state.tea_service untouched")
	expect(same(TS.current_round(w.state),{"style":"deep","portions":0,"day":d0,"left":5,"cold":true}) and TS.portions(w.state)==0,"cold: current_round portions 0, left 5 unchanged (%s)"%str(TS.current_round(w.state)))
	expect(TS.status_text(w.state)=="前一天泡的深焙茶已經涼了，可以重新泡一壺。","cold: status sentence (%s)"%TS.status_text(w.state))
	expect(same(TS.public(w.state),{"placed":true,"round":{"style":"deep","portions":5,"day":d0}}),"cold: public() shows the cups actually left and the brew day")
	refuse(w,GUESTS[1],TS.SIP_ACTION,TABLE,"",TS.COLD,"cold: an islander who has not sipped finds the tea cold")
	refuse(w,ALPHA,TS.SIP_ACTION,TABLE,"",TS.COLD,"cold: COLD is checked before SIPPED")
	refuse(w,GUESTS[1],TS.SIP_ACTION,TABLE,"x",TS.BAD_EXTRA,"cold: BAD_EXTRA still first")
	var r4:=roundtrip(w,path,"cold round")
	var cold_pot:Variant=r4.state.get(TS.STATE_KEY,{}).get("round")
	expect(cold_pot is Dictionary and typeof(cold_pot.get("day"))==TYPE_INT and int(cold_pot.day)==d0 and typeof(cold_pot.get("portions"))==TYPE_INT,"cold: reload keeps day and portions as ints")
	refuse(r4,GUESTS[1],TS.SIP_ACTION,TABLE,"",TS.COLD,"cold: still cold after reload")
	# A solo islander re-brews over the cold pot: round overwritten, claims cleared, new day.
	pl(w,ALPHA).inventory.erase("tea_light")
	refuse(w,ALPHA,TS.BREW_ACTION,TABLE,"light",TS.NO_TEA%"淺焙茶","cold: re-brew still needs the tea (NO_TEA)")
	setinv(w,ALPHA,"tea_light",1)
	var rebrew:=ok(w,ALPHA,TS.BREW_ACTION,TABLE,"light","cold: alpha re-brews over yesterday's cold cups")
	expect(str(rebrew.get("message",""))==TS.BREWED_OK%"淺焙茶" and not pl(w,ALPHA).inventory.has("tea_light"),"cold: re-brew message, alpha's light roast used")
	expect(same(record(w),{"lender":BETA,"round":{"style":"light","portions":6,"claimed":{},"day":d0+1}}),"cold: round overwritten with today's day, claims reset (%s)"%str(record(w)))
	ok(w,ALPHA,TS.SIP_ACTION,TABLE,"","cold: alpha sips the fresh pot (her earlier claim was cleared)")
	refuse(w,ALPHA,TS.BREW_ACTION,TABLE,"deep",TS.TEA_LEFT_BREW,"cold: the fresh same-day pot blocks brewing again")
	refuse(w,BETA,TS.TAKE_ACTION,TABLE,"",TS.TEA_LEFT,"cold: the fresh same-day pot blocks the lender")
	# Next day: the lender takes the set back with five cold cups still in the pot.
	if not expect(wait(w,World.WEATHER.DAY_SECONDS) and TS.today(w.state)==d0+2,"cold: a second real day passes"):return false
	refuse(w,GUESTS[2],TS.SIP_ACTION,TABLE,"",TS.COLD,"cold: the second pot is cold the next day")
	refuse(w,ALPHA,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"cold: NOT_LENDER still applies to a cold pot")
	var kits:=int(pl(w,BETA).inventory.get(KIT,0))
	var taken:=act(w,BETA,TS.TAKE_ACTION,TABLE)
	expect(bool(taken.get("ok",false)) and str(taken.get("message",""))==TS.TAKEN_OK,"cold: beta takes her set back with cold cups left (%s)"%str(taken.get("message","")))
	expect(int(pl(w,BETA).inventory.get(KIT,0))==kits+1 and not w.state.has(TS.STATE_KEY),"cold: beta's kit +1, record removed")
	return true

# ---------------------------------------------------------------- snapshot --

func token_free(text:String) -> bool:
	for token:String in [ALPHA,BETA]+GUESTS:
		if text.contains(token):return false
	return true

func check_snapshot(w:World) -> void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	var keep:=w.save_path
	w.save_path=""
	session.peers={1:ALPHA,2:BETA}
	var today:int=TS.today(w.state)
	var want:={"placed":true,"round":{"style":"deep","portions":5,"day":today}}
	for region in ["home","yingge","maokong"]:
		var public:Dictionary=session.public_state(region)
		expect(same(public.get(TS.STATE_KEY),want),"public_state(%s) tea_service == {placed, round{style, portions, day}} (%s)"%[region,str(public.get(TS.STATE_KEY))])
		expect(token_free(JSON.stringify(public.get(TS.STATE_KEY))),"public_state(%s) tea_service carries no token"%region)
		expect(token_free(JSON.stringify(public)),"public_state(%s) contains no raw player token"%region)
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	var own:Variant=snap.get(TS.STATE_KEY)
	expect(own is Dictionary and own.get("lender_own")==false and own.get("sipped_own")==true and not own.has("lender") and own.get("round") is Dictionary and not own.round.has("claimed"),"alpha's snapshot: not the lender, has sipped, no lender / claim map (%s)"%str(own))
	expect(own is Dictionary and own.get("round") is Dictionary and int(own.round.get("day",-1))==today,"alpha's snapshot round carries the brew day %d (%s)"%[today,str(own)])
	expect(TS.placed(snap) and not TS.lender_own(snap) and TS.sipped_own(snap) and TS.portions(snap)==5,"client helpers on alpha's snapshot")
	expect(same(TS.current_round(snap),{"style":"deep","portions":5,"day":today,"left":5,"cold":false}),"client current_round on alpha's snapshot (%s)"%str(TS.current_round(snap)))
	expect(TS.sip_block(snap)==TS.SIPPED and TS.take_block(snap,{})==TS.NOT_LENDER and TS.brew_block(snap,"light",{"tea_light":1})==TS.TEA_LEFT_BREW and TS.place_block(snap,{KIT:1})==TS.ALREADY,"alpha's snapshot block reasons")
	expect(TS.status_text(snap)=="桌上有一壺深焙茶，還剩 5／6 杯。","status text from alpha's snapshot")
	expect(token_free(JSON.stringify(snap)),"alpha's snapshot contains no raw token")
	session.peers={1:BETA}
	session._send_snapshot(1)
	var beta_snap:Dictionary=session.snapshot
	var beta_own:Variant=beta_snap.get(TS.STATE_KEY)
	expect(beta_own is Dictionary and beta_own.get("lender_own")==true and beta_own.get("sipped_own")==false,"beta's snapshot: lender, not yet sipped")
	expect(TS.sip_block(beta_snap)=="" and TS.take_block(beta_snap,{})==TS.TEA_LEFT,"beta's snapshot: may sip, must wait to take back")
	expect(token_free(JSON.stringify(beta_snap)),"beta's snapshot contains no raw token")
	session.peers={1:GUESTS[4]}
	session._send_snapshot(1)
	var guest_own:Variant=session.snapshot.get(TS.STATE_KEY)
	expect(guest_own is Dictionary and guest_own.get("lender_own")==false and guest_own.get("sipped_own")==false and TS.sip_block(session.snapshot)=="","another islander: neither lender nor sipped")
	var fresh:=World.new()
	fresh.add_player("teaservice-solo-123456","Solo")
	session.world=fresh
	session.peers={1:"teaservice-solo-123456"}
	expect(not session.public_state("home").has(TS.STATE_KEY),"a world without the set publishes no tea_service key")
	session._send_snapshot(1)
	expect(not session.snapshot.has(TS.STATE_KEY),"no set: snapshot has no tea_service")
	session.world=null
	session.queue_free()
	w.save_path=keep

# ------------------------------------------------------------------- saves --

## Tea ware decorations, chest kits and bag kits removed (so an incomplete revisit is legal).
func strip_tea_ware(s:Dictionary) -> void:
	var layers:Array=[s.get("objects",{})]
	var regions:Variant=s.get("regions",{})
	if regions is Dictionary:
		for region in regions:
			if regions[region] is Dictionary:layers.append(regions[region].get("objects",{}))
	for layer:Variant in layers:
		if not layer is Dictionary:continue
		for cell in layer.keys():
			var obj:Variant=layer[cell]
			if not obj is Dictionary:continue
			if str(obj.get("type",""))==KIND:
				layer.erase(cell)
				continue
			if obj.get("items") is Dictionary:obj.items.erase(KIT)
	for token in s.players:(s.players[token].inventory as Dictionary).erase(KIT)

func incomplete_revisit(base:Dictionary) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	strip_tea_ware(s)
	var r:Dictionary=s[TR.STATE_KEY]
	r.completed=false
	r.done_day=0
	r.claimed={}
	return s

func check_saves(path:String,legacy_path:String) -> void:
	var legacy:=World.new()
	expect(legacy.load_world(legacy_path) and not legacy.recovered_from_backup and not legacy.state.has(TS.STATE_KEY),"legacy save without tea_service loads without migration")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary,"saved world parses"):return
	var base:Dictionary=parsed
	if not expect(base.get(TS.STATE_KEY) is Dictionary and base[TS.STATE_KEY].get("round") is Dictionary,"final save carries a tea_service round"):return
	expect(validates(base),"control: final save (beta's set, deep round 5 left, alpha sipped) validates")
	var saved_round:Dictionary=base[TS.STATE_KEY].round
	expect(saved_round.size()==4 and saved_round.has("day") and int(saved_round.day)==TS.today(base) and int(saved_round.day)>=1,"final save: round has exactly style/portions/claimed/day, day == today (%s)"%str(saved_round))
	var day_one:Dictionary=base.duplicate(true)
	day_one[TS.STATE_KEY].round.day=1
	expect(validates(day_one),"control: a round brewed on day 1 (<= today) validates")
	var fixture:=temp_path("fixture")
	var old:Dictionary=base.duplicate(true)
	old.erase(TS.STATE_KEY)
	expect(validates(old) and write_json(fixture,old) and World.new().load_world(fixture),"old-shape save without the key loads")
	var only:Dictionary=base.duplicate(true)
	only[TS.STATE_KEY]={"lender":BETA}
	expect(validates(only),"control: placed-only record validates")
	var finished:Dictionary=base.duplicate(true)
	var all_six:={}
	for token:String in [ALPHA,BETA]+GUESTS.slice(0,4):all_six[token]=true
	finished[TS.STATE_KEY]={"lender":BETA,"round":{"style":"light","portions":0,"claimed":all_six,"day":TS.today(base)}}
	expect(validates(finished) and write_json(fixture,finished) and World.new().load_world(fixture),"control: a finished round (0 left, six claimed) validates and loads")
	var unsent:=incomplete_revisit(base)
	unsent.erase(TS.STATE_KEY)
	expect(validates(unsent),"control: the incomplete-revisit fixture without tea_service validates (so the record is what is rejected)")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["record is a list","record is null","record is a string","record empty","lender unknown","lender not a string",
		"extra key","extra key without round","round is a list","round extra key","round missing claimed","bad style",
		"style not a string","portions not 6 minus claimed","portions too low","portions fractional","portions string",
		"seven claimed","claimed by unknown player","claimed value false","claimed value int","claimed is a list",
		"record with revisit not completed","record without picnic","record without a table",
		"day missing (old 3-key round)","day zero","day negative","day fractional","day string","day null","day in the future"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	expect(labels.size()>=20,"at least 20 tamper cases (%d)"%labels.size())

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var r:Dictionary=s[TS.STATE_KEY]
	var pot:Dictionary=r.round
	match label:
		"record is a list":s[TS.STATE_KEY]=[r]
		"record is null":s[TS.STATE_KEY]=null
		"record is a string":s[TS.STATE_KEY]=BETA
		"record empty":s[TS.STATE_KEY]={}
		"lender unknown":r.lender=STRANGER
		"lender not a string":r.lender=5
		"extra key":r["by"]=ALPHA
		"extra key without round":s[TS.STATE_KEY]={"lender":BETA,"placed":true}
		"round is a list":r.round=[pot]
		"round extra key":pot["total"]=6
		"round missing claimed":pot.erase("claimed")
		"bad style":pot.style="green"
		"style not a string":pot.style=1
		"portions not 6 minus claimed":pot.portions=6
		"portions too low":pot.portions=4
		"portions fractional":pot.portions=4.5
		"portions string":pot.portions="5"
		"seven claimed":
			var everyone:={}
			for token in s.players:everyone[str(token)]=true
			pot.claimed=everyone
			pot.portions=6-everyone.size()
		"claimed by unknown player":
			pot.claimed[STRANGER]=true
			pot.portions=4
		"claimed value false":pot.claimed[ALPHA]=false
		"claimed value int":pot.claimed[ALPHA]=1
		"claimed is a list":pot.claimed=[ALPHA]
		"record with revisit not completed":
			s=incomplete_revisit(base)
		"record without picnic":
			s.picnic=false
			s.community={"table":""}
			s.erase("table_warmer")
		"record without a table":
			s.community={"table":""}
			s.erase("table_warmer")
		"day missing (old 3-key round)":pot.erase("day")
		"day zero":pot.day=0
		"day negative":pot.day=-1
		"day fractional":pot.day=float(TS.today(s))-0.5
		"day string":pot.day=str(TS.today(s))
		"day null":pot.day=null
		"day in the future":pot.day=TS.today(s)+1
	return s
