extends SceneTree
## 第 40 章地方記憶展第三件展品「陶器」／茶陶組 (memory_exhibit.gd + tea_revisit.gd) rules test.
## Headless, World-level (World.act / save / load_world) plus an in-process Session for
## the public / own snapshot. No network.
##
## EARNED through real World.act: every player's tea two-packaging comparison (tea_intro →
## tea_potter → tea_fire / tea_fire_take → pick / roast / take → pack light:jar → ship →
## sell → return → reclaim → pick / roast / take → pack light:fiber → ship → sell →
## tea_discuss), which also earns each player's first recycled jar and (extra pick / roast
## deep / take) one deep roast; the whole 茶罐大單 (tea_revisit_jar ×6, tea_revisit_fill ×6,
## tea_revisit_send); every tea ware claim (tea_revisit_claim); every exhibit_view; for the
## unchanged-output check also the Lanyang chain (canal repair, first 分水, plaque, 旱日分流)
## and the Jinguashi chain (picnic, hoist repair, Bobo sort, dispatch) exactly as
## test_memory_exhibit_lantern earns them.
## WRITTEN DIRECTLY (disclosed): state.festival_story_open=true (the festival opening is
## covered by the festival suites), chapter_one.shipped/watered + board + picnic for the tea
## chain, the extra recycled jars (tea_worn_jar 5) and roasted tea beyond the earned ones,
## Lanyang repair materials, board + soup/bread for the Jinguashi picnic, mine_depths
## unlocked 6 / pumped 24, hoist materials, gold_ore 3 per Bobo sort, the shipped ores,
## player region/x/y (no travel action), state.time jumps forward (day 3), tampered save
## files and synthetic client-shaped snapshots.
const World=preload("res://scripts/world.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Bobo=preload("res://scripts/bobo_workshop.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const ALPHA:="teaware-alpha-token-5e21"
const BETA:="teaware-beta-token-90ac"
const LATE:="teaware-late-token-d7f3"
const KIT:="tea_ware_kit"
const STAND:=Vector2i(39,26)
const NEAR:=Vector2(39.5,27.5)
const AT_POTTER:=Vector2(20.5,21.5)
const AT_PACKER:=Vector2(26.5,21.5)
const TABLE:=Vector2i(23,20)
const AT_TABLE:=Vector2(23.5,21.5)
const AT_HOIST:=Vector2(27.5,19.5)
const AT_SHUTTLE:=Vector2(12.5,20.5)
const DAY:=1440.0
const SPRING:={"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"}
const OWN_KEYS:=["basket_claimed","comparison_done","first_share_done","lantern_claimed","plaque_claimed","raking_done","seen","sorting_done","teaware_claimed"]
const PERSONAL_KEYS:=["basket_claimed","basket_hint","comparison_done","first_share_done","hint","lantern_claimed","lantern_hint","plaque_claimed","raking_done","seen","sorting_done","teaware_claimed","teaware_hint","unread"]
const OLD_PERSONAL_KEYS:=["first_share_done","hint","lantern_claimed","lantern_hint","plaque_claimed","seen","sorting_done","unread"]

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
	run.call_deferred()

func run() -> void:
	check_static()
	var w:World=await order_a()
	if w!=null:check_save(w)
	order_b()
	check_others_unchanged()
	check_client_shapes()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("MEMORY_EXHIBIT_TEAWARE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("exhibit-teaware-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

static func sorted_keys(d:Dictionary) -> Array:
	var keys:=[]
	for k in d:keys.append(str(k))
	keys.sort()
	return keys

static func only(d:Dictionary,keys:Array) -> Dictionary:
	var out:={}
	for k:String in keys:out[k]=d.get(k)
	return out

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y
	if region in World.TRANSIT.ROUTE:p.travel_book.visited[region]=true

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"teaware-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or str(r.get("message",""))==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func view(w:World,token:String,id:String,label:String) -> Dictionary:
	put(w,token,NEAR,"home")
	return ok(w,token,Exhibit.VIEW_ACTION,Exhibit.stand_cell(w.state),Exhibit.extra_for(id),label)

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func give(w:World,token:String,item:String,count:int) -> void:
	var bag:Dictionary=pl(w,token).inventory
	bag[item]=int(bag.get(item,0))+count

# ---------------------------------------------------------------- tea chain --

func earn_chapter(w:World) -> void:
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state["board"]=true
	w.state["picnic"]=true

func tea(w:World,token:String,action:String,region:String,cell:Vector2i,extra:String="") -> bool:
	put(w,token,Vector2(cell)+Vector2(0.5,1.5),region)
	var r:=act(w,token,action,cell,extra)
	if not r.ok:push_error("tea chain step %s failed: %s"%[action,str(r.message)])
	return bool(r.ok)

func earn_comparison(w:World,token:String) -> bool:
	if not tea(w,token,"tea_intro","home",Tea.RECEIVER) or not tea(w,token,"tea_potter",Tea.YINGGE,Tea.POTTER):return false
	if not tea(w,token,"tea_fire",Tea.YINGGE,Tea.KILN) or not w.step(Tea.KILN_SECONDS,true) or not tea(w,token,"tea_fire_take",Tea.YINGGE,Tea.KILN):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[0]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not w.step(Tea.ROAST_SECONDS.light,true) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:jar") or not tea(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not w.step(Tea.SHIPPING_SECONDS,true) or not tea(w,token,"tea_sell","home",Tea.RECEIVER) or not tea(w,token,"tea_return","home",Tea.RECEIVER):return false
	if not w.step(Tea.RETURN_SECONDS,true) or not tea(w,token,"tea_reclaim",Tea.MAOKONG,Tea.PACKER):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[1]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not w.step(Tea.ROAST_SECONDS.light,true) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:fiber") or not tea(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not w.step(Tea.SHIPPING_SECONDS,true) or not tea(w,token,"tea_sell","home",Tea.RECEIVER) or not tea(w,token,"tea_discuss",Tea.MAOKONG,Tea.TEA_NPC):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[2]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"deep"):return false
	if not w.step(Tea.ROAST_SECONDS.deep,true) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	return Tea.own_record(w.state,token).comparison_complete==true

func hand(w:World,token:String,item:String) -> bool:
	put(w,token,AT_POTTER,"yingge")
	return act(w,token,TR.JAR_ACTION,TR.POTTER,item).ok

func fill(w:World,token:String,style:String) -> bool:
	put(w,token,AT_PACKER,"maokong")
	return act(w,token,TR.FILL_ACTION,TR.PACKER,style).ok

## Earned spring big order by `token` (earned jar + 5 written worn jars; light 4 / deep 2
## with the earned deep roast). When `last_day_index` >= 0 the clock jumps forward there
## before the send.
func earn_order(w:World,token:String,last_day_index:int=-1) -> bool:
	give(w,token,"tea_worn_jar",5)
	if not hand(w,token,"tea_returned_jar"):return false
	for i in 5:
		if not hand(w,token,"tea_worn_jar"):return false
	give(w,token,"tea_light",4)
	give(w,token,"tea_deep",1)
	for style:String in ["deep","light","light","deep","light","light"]:
		if not fill(w,token,style):return false
	if last_day_index>=0:w.state["time"]=maxf(float(w.state.time),float(last_day_index)*DAY+30.0)
	put(w,token,AT_PACKER,"maokong")
	return act(w,token,TR.SEND_ACTION,TR.PACKER).ok and TR.completed(w.state)

func earn_claim(w:World,token:String) -> bool:
	put(w,token,AT_POTTER,"yingge")
	return act(w,token,TR.CLAIM_ACTION,TR.POTTER).ok

func row(rows:Array,id:String) -> Dictionary:
	for r:Dictionary in rows:
		if r.id==id:return r
	return {}

func hint(w:World,token:String) -> String:
	return Exhibit.personal_hint_for(w.state,"tea_pottery",token)

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	var hints:={}
	for h:String in [Exhibit.HINT_TEA_NOT_DONE_NOT_READY,Exhibit.HINT_TEA_NOT_DONE,Exhibit.HINT_TEA_NOT_READY,Exhibit.HINT_TEA_UNCLAIMED,Exhibit.HINT_TEA_CLAIMED,
		Exhibit.HINT_JG_LOCKED,Exhibit.HINT_JG_NOT_DONE_NOT_READY,Exhibit.HINT_JG_NOT_DONE,Exhibit.HINT_JG_NOT_READY,Exhibit.HINT_JG_UNCLAIMED,Exhibit.HINT_JG_CLAIMED,
		Exhibit.HINT_REVISIT_LOCKED,Exhibit.HINT_NOT_DONE_NOT_READY,Exhibit.HINT_NOT_DONE,Exhibit.HINT_NOT_READY,Exhibit.HINT_UNCLAIMED,Exhibit.HINT_CLAIMED]:hints[h]=true
	expect(hints.size()==17,"five tea ware hints, all distinct from the lantern and plaque hints")
	expect(Exhibit.HINT_TEA_UNCLAIMED.contains("鶯歌") and Exhibit.HINT_TEA_NOT_READY.contains("茶茶"),"tea hints point at the 鶯歌 potter / 茶茶")
	expect(str(Exhibit.EXHIBITS.tea_pottery.name)=="陶器" and str(Exhibit.EXHIBITS.tea_pottery.region)=="貓空與鶯歌","exhibit slot unchanged (陶器・貓空與鶯歌)")
	var empty:={}
	expect(not Exhibit.available(empty,"tea_pottery") and Exhibit.personal_hint_for(empty,"tea_pottery")==Exhibit.HINT_TEA_NOT_DONE_NOT_READY and Exhibit.personal_hint_for(empty,"beimen")==Exhibit.HINT_SALT_LOCKED and Exhibit.personal_hint_for(empty,"bogus")=="","no record: not available, tea hint present, salt basket has its own (locked) hint")
	expect(Exhibit.tea_recap(empty)=={} and Exhibit.recap_for(empty,"tea_pottery")=={} and Exhibit.recap_pages("tea_pottery",empty).is_empty(),"no recap without completion")

# ------------------------------------------------------- order A: festival first --

func order_a() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.state.festival_story_open=true # PRESET
	earn_chapter(w)
	expect(hint(w,ALPHA)==Exhibit.HINT_TEA_NOT_DONE_NOT_READY,"hint before the comparison: not done, not ready")
	if not expect(earn_comparison(w,ALPHA),"alpha's comparison earned"):return null
	expect(hint(w,ALPHA)==Exhibit.HINT_TEA_NOT_DONE and hint(w,BETA)==Exhibit.HINT_TEA_NOT_DONE_NOT_READY,"hints: alpha ready / beta not ready, order not sent")
	expect(Exhibit.personal_hint(w.state,ALPHA)==Exhibit.HINT_REVISIT_LOCKED and Exhibit.personal_hint_for(w.state,"jinguashi",ALPHA)==Exhibit.HINT_JG_LOCKED,"plaque and lantern hints untouched by tea progress")
	put(w,ALPHA,NEAR,"home")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"tea_pottery",Exhibit.NOT_ON_DISPLAY,"tea ware before the order")
	expect(Exhibit.view_block(w.state,"tea_pottery",ALPHA)==Exhibit.NOT_ON_DISPLAY,"view_block before completion")
	# Partial order keeps the pedestal empty.
	give(w,ALPHA,"tea_worn_jar",5)
	expect(hand(w,ALPHA,"tea_returned_jar"),"alpha hands in her earned jar")
	for i in 5:expect(hand(w,ALPHA,"tea_worn_jar"),"alpha hands in worn jar %d"%(i+1))
	give(w,ALPHA,"tea_light",4)
	give(w,ALPHA,"tea_deep",1)
	for style:String in ["light","deep","light","light","deep","light"]:
		expect(not Exhibit.available(w.state,"tea_pottery") and Exhibit.on_display_ids(w.state).is_empty(),"before filling %s the tea ware is not on display"%style)
		expect(fill(w,ALPHA,style),"alpha fills %s"%style)
	expect(row(Exhibit.exhibits(w.state,ALPHA),"tea_pottery").lines==[Exhibit.EMPTY_LINE] and Exhibit.recap_pages("tea_pottery",w.state).is_empty(),"empty card and no pages while all six are filled but not sent")
	put(w,ALPHA,AT_PACKER,"maokong")
	ok(w,ALPHA,TR.SEND_ACTION,TR.PACKER,"","alpha sends the big order")
	if not expect(TR.completed(w.state),"big order completed"):return null
	# The exhibit updates with progress.
	expect(Exhibit.on_display_ids(w.state)==["tea_pottery"] and Exhibit.on_display(w.state,"tea_pottery") and not Exhibit.on_display(w.state,"lanyang") and not Exhibit.on_display(w.state,"jinguashi"),"tea ware on display, plaque and lantern still empty")
	expect(Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"unread 1 for both")
	expect(same(Exhibit.public(w.state),{"cell":STAND,"paused":false,"on_display":["tea_pottery"],"blocked_cells":[]}),"public block lists tea_pottery")
	expect(hint(w,ALPHA)==Exhibit.HINT_TEA_UNCLAIMED and hint(w,BETA)==Exhibit.HINT_TEA_NOT_READY,"hints: alpha unclaimed, beta not ready")
	var card:=row(Exhibit.exhibits(w.state,ALPHA),"tea_pottery")
	expect(card.on_display and card.unread and not card.seen and card.source==TR.TEAWARE_SOURCE and card.project==TR.TEAWARE_PROJECT and card.blurb==TR.TEAWARE_BLURB and card.disclaimer==TR.DISCLAIMER and card.name=="陶器","tea ware card: provenance + disclaimer")
	var want_lines:=[TR.TEAWARE_BLURB,TR.TEAWARE_SOURCE,TR.TEAWARE_PROJECT,"完成那天：第 1 日・貓空晴天",
		"春季的訂單：淺焙 4 罐／深焙 2 罐","回收的空罐：回收陶罐 1 只、磨損陶罐 5 只",TR.DISCLAIMER]
	expect(card.lines==want_lines,"tea ware card lines restate the record (%s)"%str(card.lines))
	for id:String in ["lanyang","jinguashi","beimen"]:
		expect(row(Exhibit.exhibits(w.state,ALPHA),id).lines==[Exhibit.EMPTY_LINE],"%s still empty"%id)
	var r:=Exhibit.tea_recap(w.state)
	expect(same(r,{"day":1,"weather":"sunny","weather_label":"晴天","order_day":1,"season":"spring","season_label":"春季","reason":TR.reason_for("spring"),
		"order":{"light":4,"deep":2},"returned":1,"worn":5,"light":4,"deep":2}),"recap from the stored record (%s)"%str(r))
	expect(same(Exhibit.recap_for(w.state,"tea_pottery"),r) and Exhibit.recap(w.state)=={} and Exhibit.jinguashi_recap(w.state)=={},"recap_for(tea_pottery); other recaps still empty")
	var pages:=Exhibit.recap_pages("tea_pottery",w.state)
	expect(pages.size()==4,"four recap pages")
	var titles:=pages.map(func(p):return str(p.title))
	expect(titles==["回訪的緣由","訂單上的需要","怎麼回收與裝罐","帶回家的紀念"],"page titles (%s)"%str(titles))
	for page:Dictionary in pages:expect((page.lines as Array).size()>=2,"page '%s' has lines"%page.title)
	var all_text:=JSON.stringify(pages)
	expect(all_text.contains("淺焙 4 罐、深焙 2 罐") and all_text.contains("回收陶罐 1 只、磨損陶罐 5 只") and all_text.contains("第 1 日・貓空晴天") and all_text.contains(TR.reason_for("spring")) and all_text.contains("沒有記錄是誰"),"pages: numbers, reason, honest no-actor note (%s)"%all_text)
	expect(not all_text.contains(ALPHA) and not all_text.contains("Alpha"),"pages name no player")
	expect(str((pages[3].lines as Array).back())==TR.DISCLAIMER,"last page ends with the disclaimer")
	expect(not all_text.contains("上菜"),"pages do not claim a serving mechanic")
	# Views.
	view(w,ALPHA,"tea_pottery","alpha views the tea ware")
	expect(same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["tea_pottery"]}) and not pl(w,BETA).has(Exhibit.RECORD_KEY),"only alpha's record changes")
	put(w,ALPHA,NEAR,"home")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"tea_pottery",Exhibit.ALREADY_SEEN,"alpha views again")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"jinguashi",Exhibit.NOT_ON_DISPLAY,"lantern still not on display")
	put(w,ALPHA,AT_PACKER,"maokong")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"tea_pottery",Exhibit.WRONG_REGION,"view from 貓空")
	# Claims update the hint.
	expect(earn_claim(w,ALPHA),"alpha claims her tea ware")
	expect(hint(w,ALPHA)==Exhibit.HINT_TEA_CLAIMED,"alpha: claimed hint")
	expect(same(Exhibit.own(w.state,ALPHA),{"seen":["tea_pottery"],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":true,"teaware_claimed":true,"raking_done":false,"basket_claimed":false}),"alpha's own block")
	var me:=Exhibit.personal(w.state,ALPHA)
	expect(sorted_keys(me)==PERSONAL_KEYS and me.teaware_hint==Exhibit.HINT_TEA_CLAIMED and me.hint==Exhibit.HINT_REVISIT_LOCKED and me.lantern_hint==Exhibit.HINT_JG_LOCKED and me.comparison_done and me.teaware_claimed and me.unread==0,"alpha personal(): tea ware keys alongside the plaque and lantern keys")
	# Late joiner: never visited 貓空 or 鶯歌.
	w.add_player(LATE,"Late")
	put(w,LATE,NEAR,"home")
	expect(Exhibit.unread_count(w.state,LATE)==1 and hint(w,LATE)==Exhibit.HINT_TEA_NOT_READY,"late joiner: unread 1, catch-up hint")
	view(w,LATE,"tea_pottery","late joiner views the tea ware")
	expect(same(pl(w,LATE).get(Exhibit.RECORD_KEY),{"seen":["tea_pottery"]}) and Exhibit.unread_count(w.state,LATE)==0,"late joiner marked seen")
	if expect(earn_comparison(w,LATE),"late joiner finishes the tea comparison later"):
		expect(hint(w,LATE)==Exhibit.HINT_TEA_UNCLAIMED,"late joiner: tea ware waiting at the potter")
		expect(earn_claim(w,LATE) and hint(w,LATE)==Exhibit.HINT_TEA_CLAIMED,"late joiner claims; claimed hint")
	put(w,LATE,NEAR,"home")
	await check_snapshot(w)
	return w

# ------------------------------------------------------------------ snapshot --

func check_snapshot(w:World) -> void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	var saved_path:=w.save_path
	w.save_path=""
	session.peers={1:ALPHA,2:BETA}
	for region in ["home","maokong","yingge"]:
		var public:Dictionary=session.public_state(region)
		expect(same(public.get(Exhibit.STATE_KEY),{"cell":STAND,"paused":false,"on_display":["tea_pottery"],"blocked_cells":[]}),"public_state(%s): exhibit block lists the tea ware"%region)
		expect(not JSON.stringify(public).contains("\"seen\"") and not JSON.stringify(public).contains("teaware_claimed") and not JSON.stringify(public).contains("comparison_done"),"public_state(%s): no seen list, no personal tea ware flags"%region)
	session._send_snapshot(1)
	var a:Dictionary=session.snapshot
	expect(sorted_keys(a.get(Exhibit.OWN_KEY,{}))==OWN_KEYS and same(a.get(Exhibit.OWN_KEY),Exhibit.own(w.state,ALPHA)),"alpha's own block carries the tea ware keys")
	expect(not JSON.stringify(a).contains(ALPHA) and not JSON.stringify(a).contains(BETA),"no raw token in alpha's snapshot")
	expect(same(Exhibit.exhibits(a),Exhibit.exhibits(w.state,ALPHA)),"client exhibits() == server exhibits(alpha)")
	expect(same(Exhibit.personal(a),Exhibit.personal(w.state,ALPHA)),"client personal() == server personal(alpha)")
	expect(Exhibit.personal_hint_for(a,"tea_pottery")==Exhibit.HINT_TEA_CLAIMED,"client tea ware hint for alpha")
	expect(same(Exhibit.recap_pages("tea_pottery",a),Exhibit.recap_pages("tea_pottery",w.state)) and same(Exhibit.tea_recap(a),Exhibit.tea_recap(w.state)),"client recap == server recap")
	session.peers={1:BETA,2:ALPHA}
	session._send_snapshot(1)
	var b:Dictionary=session.snapshot
	expect(same(b.get(Exhibit.OWN_KEY),{"seen":[],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}),"beta's own block shows nothing of alpha's")
	expect(Exhibit.unread_count(b)==1 and Exhibit.personal_hint_for(b,"tea_pottery")==Exhibit.HINT_TEA_NOT_READY and Exhibit.view_block(b,"tea_pottery")=="","beta's client: unread, catch-up hint, may view")
	session.world=null
	session.queue_free()
	w.save_path=saved_path
	await process_frame

# ------------------------------------------------------------------- saving --

func check_save(w:World) -> void:
	var path:=temp_path("main")
	var fixture:=temp_path("fixture")
	w.save_path=path
	for token in [ALPHA,BETA,LATE]:put(w,token,NEAR,"home")
	if not expect(w.save(),"world saves"):return
	var reloaded:=World.new()
	if not expect(reloaded.load_world(path),"reload"):return
	for token in [ALPHA,BETA,LATE]:
		expect(same(Exhibit.personal(reloaded.state,token),Exhibit.personal(w.state,token)) and same(Exhibit.exhibits(reloaded.state,token),Exhibit.exhibits(w.state,token)),"%s's exhibit view identical after reload"%token)
	expect(same(Exhibit.recap_pages("tea_pottery",reloaded.state),Exhibit.recap_pages("tea_pottery",w.state)),"pages identical after reload")
	refuse(reloaded,ALPHA,Exhibit.VIEW_ACTION,STAND,"tea_pottery",Exhibit.ALREADY_SEEN,"after reload alpha has still seen it")
	var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(validates(base),"saved world validates")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	for label:String in ["seen tea_pottery without the record","seen tea_pottery before completion","seen tea_pottery with only jars collected"]:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad) and not validates(bad) and not probe.load_world(fixture),"schema rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
		var control:=bad.duplicate(true)
		for token in control.players:(control.players[token] as Dictionary).erase(Exhibit.RECORD_KEY)
		expect(validates(control),"control: the same save without exhibit records validates (%s)"%label)

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	for token in s.players:(s.players[token].inventory as Dictionary).erase(KIT)
	match label:
		"seen tea_pottery without the record":
			s.erase(TR.STATE_KEY)
		"seen tea_pottery before completion":
			s[TR.STATE_KEY]={"jars":{"tea_returned_jar":1,"tea_worn_jar":5},"filled":{"light":4,"deep":1},"day":1,"completed":false,"done_day":0,"claimed":{}}
		"seen tea_pottery with only jars collected":
			s[TR.STATE_KEY]={"jars":{"tea_returned_jar":1,"tea_worn_jar":5},"filled":{"light":0,"deep":0},"day":0,"completed":false,"done_day":0,"claimed":{}}
	return s

# ----------------------------------------------- order B: order first --

func order_b() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	earn_chapter(w)
	if not expect(earn_comparison(w,ALPHA),"order B: comparison earned"):return
	if not expect(earn_order(w,ALPHA,2),"order B: big order sent before the festival (sent on day 3)"):return
	put(w,ALPHA,NEAR,"home")
	expect(not Exhibit.unlocked(w.state) and Exhibit.on_display_ids(w.state).is_empty() and Exhibit.public(w.state)=={},"order B: order sent but festival closed -> nothing shown")
	expect(Exhibit.available(w.state,"tea_pottery") and not Exhibit.on_display(w.state,"tea_pottery"),"order B: story complete, not on display")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"tea_pottery",Exhibit.LOCKED,"order B: view before the festival")
	w.state.festival_story_open=true # PRESET
	expect(Exhibit.on_display_ids(w.state)==["tea_pottery"] and Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"order B: opening the festival shows the tea ware at once, unread for both")
	var card:=row(Exhibit.exhibits(w.state,BETA),"tea_pottery")
	expect(card.lines[3]=="完成那天：第 3 日・貓空小雨" and card.lines[4]=="春季的訂單：淺焙 4 罐／深焙 2 罐" and card.lines[5]=="回收的空罐：回收陶罐 1 只、磨損陶罐 5 只","order B: completion day 3 (rain) differs from the day-1 order (%s)"%str(card.lines))
	var r:=Exhibit.tea_recap(w.state)
	expect(int(r.day)==3 and int(r.order_day)==1 and r.weather=="rainy" and r.season=="spring","order B: recap keeps order day 1 and completion day 3")
	var pages:=Exhibit.recap_pages("tea_pottery",w.state)
	expect(JSON.stringify(pages).contains("第 1 日裝下第一罐") and JSON.stringify(pages).contains("第 3 日・貓空小雨寄出"),"order B: pages tell the order day and the send day apart")
	view(w,BETA,"tea_pottery","order B: beta (never in 貓空 or 鶯歌) views")
	expect(same(pl(w,BETA).get(Exhibit.RECORD_KEY),{"seen":["tea_pottery"]}) and Exhibit.personal_hint_for(w.state,"tea_pottery",BETA)==Exhibit.HINT_TEA_NOT_READY,"order B: beta seen, catch-up hint")
	expect(validates(w.state),"order B: state validates")

# ---------------------------------------- Lanyang / Jinguashi outputs unchanged --

func earn_lanyang(w:World,token:String) -> bool:
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:
		put(w,token,Vector2(cell.x-0.5,cell.y+0.5),"lanyang")
		if not act(w,token,"lanyang_clear",cell).ok:return false
	put(w,token,Vector2(World.LANYANG_LIFE.SERVICE.x-0.5,World.LANYANG_LIFE.SERVICE.y+0.5),"lanyang")
	for item in World.LANYANG_LIFE.REPAIR_COST:pl(w,token).inventory[item]=int(World.LANYANG_LIFE.REPAIR_COST[item])
	if not act(w,token,"lanyang_donate",World.LANYANG_LIFE.SERVICE).ok:return false
	for cell:Vector2i in Memory.OBSERVATIONS:
		put(w,token,Vector2(cell.x-0.5,cell.y+0.5),"lanyang")
		if not act(w,token,"memory_observe",cell).ok:return false
	put(w,token,Vector2(Memory.SERVICE.x-0.5,Memory.SERVICE.y+0.5),"lanyang")
	for pair in [[2,2],[1,3],[2,1]]:
		if not act(w,token,"memory_gate",Memory.SERVICE,"a:%d"%pair[0]).ok:return false
		if not act(w,token,"memory_gate",Memory.SERVICE,"b:%d"%pair[1]).ok:return false
		if not act(w,token,"memory_flow",Memory.SERVICE).ok:return false
	if not act(w,token,"memory_plaque",Memory.SERVICE).ok:return false
	w.state.history_memory.players[token].erase("completed_day")  # Legacy record for the day-one fixture.
	put(w,token,Vector2(Revisit.GATE_CELL.x-0.5,Revisit.GATE_CELL.y+0.5),"lanyang")
	if not act(w,token,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3").ok:return false
	if not act(w,token,Revisit.GATE_ACTION,Revisit.GATE_CELL,"b:2").ok:return false
	for field:String in Revisit.FIELDS:
		var cell:Vector2i=Revisit.FIELD_CELLS[field]
		put(w,token,Vector2(cell.x-0.5,cell.y+0.5),"lanyang")
		if not act(w,token,Revisit.CHECK_ACTION,cell).ok:return false
	return Revisit.completed(w.state)

func earn_jinguashi(w:World,token:String) -> bool:
	w.state["board"]=true
	put(w,token,Vector2(40.5,30.5),"home")
	pl(w,token).inventory["soup"]=2
	pl(w,token).inventory["bread"]=1
	if not act(w,token,"picnic",Vector2i(40,29)).ok:return false
	w.state["mine_depths"]={"unlocked":6,"ready":{},"pumped":24,"hoist":false}
	for item in Mines.HOIST_COST:pl(w,token).inventory[item]=int(pl(w,token).inventory.get(item,0))+int(Mines.HOIST_COST[item])
	put(w,token,AT_HOIST,"jinguashi")
	if not act(w,token,World.HOIST_ACTION,Mines.ENTRY).ok:return false
	pl(w,token).inventory["gold_ore"]=int(pl(w,token).inventory.get("gold_ore",0))+Bobo.INPUT
	put(w,token,AT_TABLE,"jinguashi")
	if not act(w,token,"bobo_sort_start",TABLE).ok:return false
	for step in Bobo.STEPS.size():
		if not act(w,token,"bobo_sort_answer",TABLE,"%d:%s"%[step,Bobo.STEPS[step]]).ok:return false
	if not act(w,token,"bobo_sort_claim",TABLE).ok:return false
	for dest:String in JG.DESTS:
		if not act(w,token,JG.SORT_ACTION,TABLE,JG.sort_extra(dest,str(SPRING[dest]))).ok:return false
	for dest:String in JG.DESTS:
		var ore:=str(SPRING[dest])
		pl(w,token).inventory[ore]=int(pl(w,token).inventory.get(ore,0))+JG.amount_for(ore)
		put(w,token,AT_TABLE if dest=="bobo" else (AT_SHUTTLE if dest=="ferry" else AT_HOIST),"jinguashi")
		if not act(w,token,JG.SHIP_ACTION,JG.dest_cell(w.state,dest)).ok:return false
	put(w,token,AT_TABLE,"jinguashi")
	return JG.completed(w.state) and act(w,token,JG.CLAIM_ACTION,TABLE).ok

func snapshot_of(w:World) -> Dictionary:
	var out:={}
	for id:String in ["lanyang","jinguashi"]:
		out[id]={"row_a":Exhibit.exhibit(w.state,id,ALPHA),"row_b":Exhibit.exhibit(w.state,id,BETA),"recap":Exhibit.recap_for(w.state,id),
			"pages":Exhibit.recap_pages(id,w.state),"hint_a":Exhibit.personal_hint_for(w.state,id,ALPHA),"hint_b":Exhibit.personal_hint_for(w.state,id,BETA)}
	# unread counts every exhibit on display, so it legitimately grows with the tea story;
	# check_others_unchanged checks it separately.
	var keys:=OLD_PERSONAL_KEYS.filter(func(k):return k!="unread")
	out["personal_a"]=only(Exhibit.personal(w.state,ALPHA),keys)
	out["personal_b"]=only(Exhibit.personal(w.state,BETA),keys)
	out["own_a"]=only(Exhibit.own(w.state,ALPHA),["first_share_done","lantern_claimed","plaque_claimed","seen","sorting_done"])
	return out

## The plaque and lantern cards, recaps, pages and hints are identical whether or not the
## tea story exists; with all three done the exhibits are independent.
func check_others_unchanged() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.state.festival_story_open=true # PRESET
	if not expect(earn_lanyang(w,ALPHA),"Lanyang revisit earned"):return
	if not expect(earn_jinguashi(w,ALPHA),"Jinguashi revisit earned and lantern claimed"):return
	put(w,ALPHA,NEAR,"home")
	var before:=snapshot_of(w)
	expect(Exhibit.unread_count(w.state,ALPHA)==2 and Exhibit.unread_count(w.state,BETA)==2,"two unread before the tea story")
	expect((before.lanyang.row_a.lines as Array).size()==7 and str(before.lanyang.row_a.lines[3])=="完成那天：第 1 日・春季・晴天" and (before.jinguashi.pages as Array).size()==4,"plaque and lantern cards as in their own suites")
	expect(Exhibit.on_display_ids(w.state)==["lanyang","jinguashi"],"two exhibits before the tea story")
	earn_chapter(w)
	if not expect(earn_comparison(w,ALPHA) and earn_order(w,ALPHA) and earn_claim(w,ALPHA),"tea story earned and tea ware claimed on the same day"):return
	put(w,ALPHA,NEAR,"home")
	var after:=snapshot_of(w)
	expect(var_to_bytes(before)==var_to_bytes(after),"plaque and lantern outputs byte-identical before and after the tea story")
	expect(sorted_keys(Exhibit.personal(w.state,ALPHA))==PERSONAL_KEYS and sorted_keys(Exhibit.own(w.state,ALPHA))==OWN_KEYS,"personal()/own() only gained the tea keys")
	expect(Exhibit.on_display_ids(w.state)==["lanyang","jinguashi","tea_pottery"] and Exhibit.unread_count(w.state,ALPHA)==3,"three exhibits on display in fixed order, three unread")
	view(w,ALPHA,"tea_pottery","alpha views the tea ware first")
	view(w,ALPHA,"lanyang","alpha views the plaque")
	view(w,ALPHA,"jinguashi","alpha views the lantern")
	expect(same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["tea_pottery","lanyang","jinguashi"]}) and Exhibit.unread_count(w.state,ALPHA)==0,"all three seen in viewing order")
	expect(Exhibit.personal_hint_for(w.state,"tea_pottery",ALPHA)==Exhibit.HINT_TEA_CLAIMED and Exhibit.personal_hint_for(w.state,"jinguashi",ALPHA)==Exhibit.HINT_JG_CLAIMED,"each exhibit keeps its own claimed hint")
	expect(validates(w.state),"world with all three stories and all seen validates")

# --------------------------------------------------------- client shapes --

func check_client_shapes() -> void:
	var snap:={"festival_story":{"opened":true},Exhibit.STATE_KEY:{"cell":STAND,"paused":false,"on_display":["tea_pottery"],"blocked_cells":[]},
		TR.STATE_KEY:{"jars":{"tea_returned_jar":6,"tea_worn_jar":0},"filled":{"light":4,"deep":2},"day":1,"completed":true,"done_day":1,"claimed_own":false},
		"tea_ceramics":{"own_record":{"comparison_complete":false}},
		Exhibit.OWN_KEY:{"seen":[],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false}}
	expect(Exhibit.on_display_ids(snap)==["tea_pottery"] and Exhibit.personal_hint_for(snap,"tea_pottery")==Exhibit.HINT_TEA_NOT_READY,"client: not ready")
	snap[Exhibit.OWN_KEY].comparison_done=true
	expect(Exhibit.personal_hint_for(snap,"tea_pottery")==Exhibit.HINT_TEA_UNCLAIMED,"client: own block says compared → unclaimed")
	snap[Exhibit.OWN_KEY].teaware_claimed=true
	expect(Exhibit.personal_hint_for(snap,"tea_pottery")==Exhibit.HINT_TEA_CLAIMED,"client: claimed")
	expect(same(Exhibit.recap_for(snap,"tea_pottery"),{"day":1,"weather":"sunny","weather_label":"晴天","order_day":1,"season":"spring","season_label":"春季","reason":TR.reason_for("spring"),"order":{"light":4,"deep":2},"returned":6,"worn":0,"light":4,"deep":2}),"client recap from the public block")
	snap.erase(Exhibit.OWN_KEY)
	snap.tea_ceramics.own_record.comparison_complete=true
	snap[TR.STATE_KEY].claimed_own=true
	expect(Exhibit.personal_hint_for(snap,"tea_pottery")==Exhibit.HINT_TEA_CLAIMED,"client without own block falls back to tea_ceramics.own_record / claimed_own")
	snap[TR.STATE_KEY].claimed_own=false
	expect(Exhibit.personal_hint_for(snap,"tea_pottery")==Exhibit.HINT_TEA_UNCLAIMED,"client fallback: unclaimed")
	snap.erase(TR.STATE_KEY)
	expect(Exhibit.personal_hint_for(snap,"tea_pottery")==Exhibit.HINT_TEA_NOT_DONE and Exhibit.on_display_ids(snap).is_empty(),"client: no record → not done, nothing on display (record decides, not the public list)")
	snap.tea_ceramics.own_record.comparison_complete=false
	expect(Exhibit.personal_hint_for(snap,"tea_pottery")==Exhibit.HINT_TEA_NOT_DONE_NOT_READY,"client: not done and not ready")
