extends SceneTree
## 第 40 章地方記憶展第四件展品「鹽籃」(memory_exhibit.gd + salt_revisit.gd) rules test.
## Headless, World-level (World.act / World.step / save / load_world) plus an in-process
## Session for the public / own snapshot. No network.
##
## EARNED through real World.act / World.step: every player's salt letter, the transit trip
## home → 田尾 → 北門, salt_intro, the three gate repairs, every player's first hand rake
## (salt_flood on a public pan, World.step until salt, salt_rake); the whole 鹽籃批次
## (salt_revisit_stock ×6, salt_revisit_pack ×6, salt_revisit_send); every basket claim;
## every exhibit_view; for the unchanged-output check also the Lanyang chain, the Jinguashi
## chain and the tea chain + 茶罐大單 exactly as test_memory_exhibit_teaware earns them.
## WRITTEN DIRECTLY (disclosed): state.festival_story_open=true (the festival opening is
## covered by the festival suites), the chapter 1/2/3 story fixture used by
## test_salt_pan_world (picnic/board/chapter_one, a finished tea record when the player has
## none, the finished flower record + completed garden, travel_book.visited.tianwei), the
## gate materials, sea_salt beyond each player's earned 3, all fiber, player region/x/y
## inside a region the player really reached (and "home" for exhibit views), state.time
## jumps forward (day 2 cloudy, day 3 rainy, day 4 sunny), the Lanyang / Jinguashi / tea
## materials exactly as test_memory_exhibit_teaware writes them, tampered save files and
## synthetic client-shaped snapshots.
const World=preload("res://scripts/world.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Transit=preload("res://scripts/transit.gd")
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
const ALPHA:="saltbasket-alpha-token-3c81"
const BETA:="saltbasket-beta-token-a0f5"
const LATE:="saltbasket-late-token-6d2e"
const KIT:="salt_basket_kit"
const STALL:=Vector2i(43,29)
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
const OLD_PERSONAL_KEYS:=["comparison_done","first_share_done","hint","lantern_claimed","lantern_hint","plaque_claimed","seen","sorting_done","teaware_claimed","teaware_hint","unread"]
const OLD_OWN_KEYS:=["comparison_done","first_share_done","lantern_claimed","plaque_claimed","seen","sorting_done","teaware_claimed"]

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
	print("MEMORY_EXHIBIT_SALTBASKET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("exhibit-saltbasket-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

## Teleport inside 北門 (the player really travelled there).
func beimen(w:World,token:String,at:Vector2) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=SR.REGION
	p["x"]=at.x
	p["y"]=at.y

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"saltbasket-req-%d"%serial,action,p,extra)

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

func set_day(w:World,day_index:int) -> void:
	var target:=float(day_index)*DAY+30.0
	if target>float(w.state.time):w.state["time"]=target

# --------------------------------------------------------------- salt chain --

func story_fixture(w:World,token:String) -> void:
	w.state.picnic=true
	w.state.board=true
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	if not w.state.tea_ceramics.players.has(token):
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

func arrive(w:World,token:String) -> bool:
	story_fixture(w,token)
	put(w,token,Vector2(STALL)+Vector2(0.5,1.5),"home")
	if not step_ok("salt_letter",act(w,token,"salt_letter",STALL)):return false
	if not travel(w,token,Flower.REGION) or not travel(w,token,Salt.REGION):return false
	if not stand(w,token,Salt.SALT_WORKER):return false
	return step_ok("salt_intro",act(w,token,"salt_intro",Salt.SALT_WORKER))

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

## Earned first hand rake on public pan 16 (flood, World.step until salt, rake).
func hand_rake(w:World,token:String) -> bool:
	var cell:=Salt.pan_rect(Salt.PUBLIC_LOT*2).position
	if not stand(w,token,cell) or not step_ok("salt_flood",act(w,token,"salt_flood",cell)):return false
	for n in 60:
		if str(w.state.salt_pan.pans[Salt.PUBLIC_LOT*2].s)=="salt":break
		if not w.step(60.0,true):return false
	return step_ok("salt_rake",act(w,token,"salt_rake",cell)) and SR.player_ready(w.state,token)

func stock(w:World,token:String) -> bool:
	beimen(w,token,SR.WORKER_STAND)
	return step_ok("stock",act(w,token,SR.STOCK_ACTION,SR.WORKER))

func pack(w:World,token:String,kind:String) -> bool:
	beimen(w,token,SR.CHEST_STAND)
	return step_ok("pack",act(w,token,SR.PACK_ACTION,SR.CHEST,kind))

func send(w:World,token:String) -> bool:
	beimen(w,token,SR.STOP_STAND)
	return step_ok("send",act(w,token,SR.SEND_ACTION,SR.STOP)) and SR.completed(w.state)

## Earned dry-day spring batch by `token` (earned 3 salt + 15 written, 12 written fiber).
func earn_batch(w:World,token:String) -> bool:
	give(w,token,"sea_salt",18-int(pl(w,token).inventory.get("sea_salt",0)))
	give(w,token,"fiber",12)
	for i in 6:
		if not stock(w,token):return false
	for kind:String in ["kitchen","pickle","kitchen","pickle","kitchen","pickle"]:
		if not pack(w,token,kind):return false
	return send(w,token)

func earn_claim(w:World,token:String) -> bool:
	beimen(w,token,SR.WORKER_STAND)
	return step_ok("claim",act(w,token,SR.CLAIM_ACTION,SR.WORKER))

func row(rows:Array,id:String) -> Dictionary:
	for r:Dictionary in rows:
		if r.id==id:return r
	return {}

func hint(w:World,token:String) -> String:
	return Exhibit.personal_hint_for(w.state,"beimen",token)

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	var hints:={}
	for h:String in [Exhibit.HINT_SALT_LOCKED,Exhibit.HINT_SALT_NOT_DONE_NOT_READY,Exhibit.HINT_SALT_NOT_DONE,Exhibit.HINT_SALT_NOT_READY,Exhibit.HINT_SALT_UNCLAIMED,Exhibit.HINT_SALT_CLAIMED,
		Exhibit.HINT_TEA_NOT_DONE_NOT_READY,Exhibit.HINT_TEA_NOT_DONE,Exhibit.HINT_TEA_NOT_READY,Exhibit.HINT_TEA_UNCLAIMED,Exhibit.HINT_TEA_CLAIMED,
		Exhibit.HINT_JG_LOCKED,Exhibit.HINT_JG_NOT_DONE_NOT_READY,Exhibit.HINT_JG_NOT_DONE,Exhibit.HINT_JG_NOT_READY,Exhibit.HINT_JG_UNCLAIMED,Exhibit.HINT_JG_CLAIMED,
		Exhibit.HINT_REVISIT_LOCKED,Exhibit.HINT_NOT_DONE_NOT_READY,Exhibit.HINT_NOT_DONE,Exhibit.HINT_NOT_READY,Exhibit.HINT_UNCLAIMED,Exhibit.HINT_CLAIMED]:hints[h]=true
	expect(hints.size()==23,"six salt basket hints, all distinct from the other exhibits' hints")
	expect(Exhibit.HINT_SALT_UNCLAIMED.contains("阿曬") and Exhibit.HINT_SALT_NOT_READY.contains("手作池") and Exhibit.HINT_SALT_LOCKED.contains("閘門"),"salt hints point at 阿曬 / the hand pool / the gates")
	expect(str(Exhibit.EXHIBITS.beimen.name)=="鹽籃" and str(Exhibit.EXHIBITS.beimen.region)=="臺南北門" and Exhibit.EXHIBIT_ORDER==["lanyang","jinguashi","tea_pottery","beimen"],"exhibit slot unchanged (鹽籃・臺南北門), fixed order")
	var empty:={}
	expect(not Exhibit.available(empty,"beimen") and Exhibit.personal_hint_for(empty,"beimen")==Exhibit.HINT_SALT_LOCKED and Exhibit.personal_hint_for(empty,"bogus")=="","no record: not available, locked hint, unknown id has none")
	expect(Exhibit.salt_recap(empty)=={} and Exhibit.recap_for(empty,"beimen")=={} and Exhibit.recap_pages("beimen",empty).is_empty(),"no recap without completion")

# ------------------------------------------------------- order A: festival first --

func order_a() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.state.festival_story_open=true # PRESET
	expect(hint(w,ALPHA)==Exhibit.HINT_SALT_LOCKED,"hint before anything: locked")
	if not expect(arrive(w,ALPHA) and arrive(w,BETA),"alpha and beta reach 北門 and meet 阿曬"):return null
	expect(hint(w,ALPHA)==Exhibit.HINT_SALT_LOCKED and hint(w,BETA)==Exhibit.HINT_SALT_LOCKED,"gates not repaired: locked hint for both")
	if not expect(repair_gates(w,ALPHA),"alpha repairs the gates"):return null
	expect(hint(w,ALPHA)==Exhibit.HINT_SALT_NOT_DONE_NOT_READY,"gates repaired, no rake yet: not done, not ready")
	if not expect(hand_rake(w,ALPHA),"alpha rakes by hand"):return null
	expect(hint(w,ALPHA)==Exhibit.HINT_SALT_NOT_DONE and hint(w,BETA)==Exhibit.HINT_SALT_NOT_DONE_NOT_READY,"hints: alpha ready / beta not ready, batch not sent")
	expect(Exhibit.personal_hint(w.state,ALPHA)==Exhibit.HINT_REVISIT_LOCKED and Exhibit.personal_hint_for(w.state,"jinguashi",ALPHA)==Exhibit.HINT_JG_LOCKED and Exhibit.personal_hint_for(w.state,"tea_pottery",ALPHA)==Exhibit.HINT_TEA_NOT_DONE,"plaque / lantern / tea hints untouched by salt progress")
	put(w,ALPHA,NEAR,"home")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"beimen",Exhibit.NOT_ON_DISPLAY,"salt basket before the batch")
	expect(Exhibit.view_block(w.state,"beimen",ALPHA)==Exhibit.NOT_ON_DISPLAY,"view_block before completion")
	# Day 1 sunny: three lots; day 2 cloudy: three lots and two kitchen baskets (order day 2);
	# day 3 rainy: four baskets under the shed, then the send.
	give(w,ALPHA,"sea_salt",15)
	give(w,ALPHA,"fiber",12)
	for i in 3:expect(stock(w,ALPHA),"alpha stocks sunny lot %d"%(i+1))
	set_day(w,1)
	for i in 3:expect(stock(w,ALPHA),"alpha stocks cloudy lot %d"%(i+1))
	for i in 2:expect(pack(w,ALPHA,"kitchen"),"alpha packs kitchen %d on day 2"%(i+1))
	set_day(w,2)
	expect(SR.rainy_today(w.state),"premise: day 3 rains")
	for kind:String in ["kitchen","pickle","pickle","pickle"]:
		expect(not Exhibit.available(w.state,"beimen") and Exhibit.on_display_ids(w.state).is_empty(),"before packing %s the basket is not on display"%kind)
		expect(pack(w,ALPHA,kind),"alpha packs %s on the rainy day"%kind)
	expect(row(Exhibit.exhibits(w.state,ALPHA),"beimen").lines==[Exhibit.EMPTY_LINE] and Exhibit.recap_pages("beimen",w.state).is_empty(),"empty card and no pages while all six are packed but not sent")
	expect(send(w,ALPHA),"alpha sends the batch on the rainy day 3")
	# The exhibit updates with progress.
	expect(Exhibit.on_display_ids(w.state)==["beimen"] and Exhibit.on_display(w.state,"beimen") and not Exhibit.on_display(w.state,"tea_pottery"),"salt basket on display, the others still empty")
	expect(Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"unread 1 for both")
	expect(same(Exhibit.public(w.state),{"cell":STAND,"paused":false,"on_display":["beimen"],"blocked_cells":[]}),"public block lists beimen")
	expect(hint(w,ALPHA)==Exhibit.HINT_SALT_UNCLAIMED and hint(w,BETA)==Exhibit.HINT_SALT_NOT_READY,"hints: alpha unclaimed, beta not ready")
	var card:=row(Exhibit.exhibits(w.state,ALPHA),"beimen")
	expect(card.on_display and card.unread and not card.seen and card.source==SR.BASKET_SOURCE and card.project==SR.BASKET_PROJECT and card.blurb==SR.BASKET_BLURB and card.disclaimer==SR.DISCLAIMER and card.name=="鹽籃","salt basket card: provenance + disclaimer")
	var want_lines:=[SR.BASKET_BLURB,SR.BASKET_SOURCE,SR.BASKET_PROJECT,"完成那天：第 3 日・北門小雨",
		"春季的訂單：料理用 3 籃／醃漬用 3 籃","入倉的散鹽：晴天 3 批、多雲 3 批；雨天裝籃 4 籃",SR.DISCLAIMER]
	expect(card.lines==want_lines,"salt basket card lines restate the record (%s)"%str(card.lines))
	for id:String in ["lanyang","jinguashi","tea_pottery"]:
		expect(row(Exhibit.exhibits(w.state,ALPHA),id).lines==[Exhibit.EMPTY_LINE],"%s still empty"%id)
	var r:=Exhibit.salt_recap(w.state)
	expect(same(r,{"day":3,"weather":"rainy","weather_label":"小雨","order_day":2,"season":"spring","season_label":"春季","reason":SR.reason_for("spring"),
		"order":{"kitchen":3,"pickle":3},"sunny":3,"cloudy":3,"kitchen":3,"pickle":3,"rain_packs":4}),"recap from the stored record (%s)"%str(r))
	expect(same(Exhibit.recap_for(w.state,"beimen"),r) and Exhibit.recap(w.state)=={} and Exhibit.tea_recap(w.state)=={},"recap_for(beimen); other recaps still empty")
	var pages:=Exhibit.recap_pages("beimen",w.state)
	expect(pages.size()==4,"four recap pages")
	var titles:=pages.map(func(p):return str(p.title))
	expect(titles==["回訪的緣由","訂單上的需要","怎麼入倉與裝籃","帶回家的紀念"],"page titles (%s)"%str(titles))
	for page:Dictionary in pages:expect((page.lines as Array).size()>=2,"page '%s' has lines"%page.title)
	var all_text:=JSON.stringify(pages)
	expect(all_text.contains("料理用 3 籃、醃漬用 3 籃") and all_text.contains("晴天入倉 3 批、多雲入倉 3 批") and all_text.contains("其中 4 籃是在下雨天") and all_text.contains("第 2 日裝下第一籃") and all_text.contains("第 3 日・北門小雨") and all_text.contains(SR.reason_for("spring")) and all_text.contains("沒有記錄是誰"),"pages: numbers, rain packs, both days, reason, honest no-actor note (%s)"%all_text)
	expect(not all_text.contains(ALPHA) and not all_text.contains("Alpha"),"pages name no player")
	expect(not all_text.contains("1818") and not all_text.contains("井仔腳") and not all_text.contains("儲滷槽"),"pages add no historical claim and no unimplemented device")
	expect(str((pages[3].lines as Array).back())==SR.DISCLAIMER,"last page ends with the disclaimer")
	# Views.
	view(w,ALPHA,"beimen","alpha views the salt basket")
	expect(same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["beimen"]}) and not pl(w,BETA).has(Exhibit.RECORD_KEY),"only alpha's record changes")
	put(w,ALPHA,NEAR,"home")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"beimen",Exhibit.ALREADY_SEEN,"alpha views again")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"tea_pottery",Exhibit.NOT_ON_DISPLAY,"tea ware still not on display")
	beimen(w,ALPHA,SR.WORKER_STAND)
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"beimen",Exhibit.WRONG_REGION,"view from 北門")
	# Claims update the hint.
	expect(earn_claim(w,ALPHA),"alpha claims her basket")
	expect(hint(w,ALPHA)==Exhibit.HINT_SALT_CLAIMED,"alpha: claimed hint")
	expect(same(Exhibit.own(w.state,ALPHA),{"seen":["beimen"],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":true,"teaware_claimed":false,"raking_done":true,"basket_claimed":true}),"alpha's own block (comparison_done from the written chapter-2 fixture)")
	var me:=Exhibit.personal(w.state,ALPHA)
	expect(sorted_keys(me)==PERSONAL_KEYS and me.basket_hint==Exhibit.HINT_SALT_CLAIMED and me.hint==Exhibit.HINT_REVISIT_LOCKED and me.lantern_hint==Exhibit.HINT_JG_LOCKED and me.teaware_hint==Exhibit.HINT_TEA_NOT_DONE and me.raking_done and me.basket_claimed and me.unread==0,"alpha personal(): basket keys alongside the other exhibits' keys")
	# Late joiner: never in 北門.
	w.add_player(LATE,"Late")
	put(w,LATE,NEAR,"home")
	expect(Exhibit.unread_count(w.state,LATE)==1 and hint(w,LATE)==Exhibit.HINT_SALT_NOT_READY,"late joiner: unread 1, catch-up hint")
	expect(same(only(Exhibit.personal(w.state,LATE),["raking_done","basket_claimed","basket_hint","seen","unread"]),{"raking_done":false,"basket_claimed":false,"basket_hint":Exhibit.HINT_SALT_NOT_READY,"seen":[],"unread":1}),"late joiner personal() basket keys")
	view(w,LATE,"beimen","late joiner views the salt basket")
	expect(same(pl(w,LATE).get(Exhibit.RECORD_KEY),{"seen":["beimen"]}) and Exhibit.unread_count(w.state,LATE)==0,"late joiner marked seen")
	set_day(w,3) # day 4 is dry, so the late joiner can flood
	if expect(arrive(w,LATE) and hand_rake(w,LATE),"late joiner travels to 北門 and rakes by hand later"):
		expect(hint(w,LATE)==Exhibit.HINT_SALT_UNCLAIMED,"late joiner: basket waiting at 阿曬")
		expect(earn_claim(w,LATE) and hint(w,LATE)==Exhibit.HINT_SALT_CLAIMED,"late joiner claims; claimed hint")
	put(w,LATE,NEAR,"home")
	put(w,ALPHA,NEAR,"home")
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
	for region in ["home","beimen","tianwei"]:
		var public:Dictionary=session.public_state(region)
		expect(same(public.get(Exhibit.STATE_KEY),{"cell":STAND,"paused":false,"on_display":["beimen"],"blocked_cells":[]}),"public_state(%s): exhibit block lists the salt basket"%region)
		expect(not JSON.stringify(public).contains("\"seen\"") and not JSON.stringify(public).contains("basket_claimed") and not JSON.stringify(public).contains("raking_done"),"public_state(%s): no seen list, no personal basket flags"%region)
	session._send_snapshot(1)
	var a:Dictionary=session.snapshot
	expect(sorted_keys(a.get(Exhibit.OWN_KEY,{}))==OWN_KEYS and same(a.get(Exhibit.OWN_KEY),Exhibit.own(w.state,ALPHA)),"alpha's own block carries the basket keys")
	expect(not JSON.stringify(a).contains(ALPHA) and not JSON.stringify(a).contains(BETA),"no raw token in alpha's snapshot")
	expect(same(Exhibit.exhibits(a),Exhibit.exhibits(w.state,ALPHA)),"client exhibits() == server exhibits(alpha)")
	expect(same(Exhibit.personal(a),Exhibit.personal(w.state,ALPHA)),"client personal() == server personal(alpha)")
	expect(Exhibit.personal_hint_for(a,"beimen")==Exhibit.HINT_SALT_CLAIMED,"client basket hint for alpha")
	expect(same(Exhibit.recap_pages("beimen",a),Exhibit.recap_pages("beimen",w.state)) and same(Exhibit.salt_recap(a),Exhibit.salt_recap(w.state)),"client recap == server recap")
	session.peers={1:BETA,2:ALPHA}
	session._send_snapshot(1)
	var b:Dictionary=session.snapshot
	expect(same(b.get(Exhibit.OWN_KEY),{"seen":[],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":true,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}),"beta's own block shows nothing of alpha's")
	expect(Exhibit.unread_count(b)==1 and Exhibit.personal_hint_for(b,"beimen")==Exhibit.HINT_SALT_NOT_READY and Exhibit.view_block(b,"beimen")=="","beta's client: unread, catch-up hint, may view")
	expect(same(Exhibit.personal(b),Exhibit.personal(w.state,BETA)),"client personal() == server personal(beta)")
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
	expect(same(Exhibit.recap_pages("beimen",reloaded.state),Exhibit.recap_pages("beimen",w.state)),"pages identical after reload")
	refuse(reloaded,ALPHA,Exhibit.VIEW_ACTION,STAND,"beimen",Exhibit.ALREADY_SEEN,"after reload alpha has still seen it")
	var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(validates(base),"saved world validates")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	for label:String in ["seen beimen without the record","seen beimen before completion","seen beimen with only lots stocked"]:
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
		"seen beimen without the record":
			s.erase(SR.STATE_KEY)
		"seen beimen before completion":
			s[SR.STATE_KEY]={"stocked":{"sunny":3,"cloudy":3},"packed":{"kitchen":3,"pickle":2},"rain_packs":3,"day":2,"completed":false,"done_day":0,"claimed":{}}
		"seen beimen with only lots stocked":
			s[SR.STATE_KEY]={"stocked":{"sunny":3,"cloudy":3},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0,"claimed":{}}
	return s

# ----------------------------------------------- order B: batch first --

func order_b() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	if not expect(arrive(w,ALPHA) and repair_gates(w,ALPHA) and hand_rake(w,ALPHA),"order B: alpha reaches 北門, repairs the gates and rakes"):return
	if not expect(earn_batch(w,ALPHA),"order B: batch sent before the festival (day 1)"):return
	put(w,ALPHA,NEAR,"home")
	expect(not Exhibit.unlocked(w.state) and Exhibit.on_display_ids(w.state).is_empty() and Exhibit.public(w.state)=={},"order B: batch sent but festival closed -> nothing shown")
	expect(Exhibit.available(w.state,"beimen") and not Exhibit.on_display(w.state,"beimen"),"order B: story complete, not on display")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"beimen",Exhibit.LOCKED,"order B: view before the festival")
	w.state.festival_story_open=true # PRESET
	expect(Exhibit.on_display_ids(w.state)==["beimen"] and Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"order B: opening the festival shows the basket at once, unread for both")
	var card:=row(Exhibit.exhibits(w.state,BETA),"beimen")
	expect(card.lines[3]=="完成那天：第 1 日・北門晴天" and card.lines[4]=="春季的訂單：料理用 3 籃／醃漬用 3 籃" and card.lines[5]=="入倉的散鹽：晴天 6 批、多雲 0 批；雨天裝籃 0 籃","order B: dry day-1 batch (%s)"%str(card.lines))
	var r:=Exhibit.salt_recap(w.state)
	expect(int(r.day)==1 and int(r.order_day)==1 and r.weather=="sunny" and r.season=="spring" and int(r.rain_packs)==0,"order B: recap day 1, no rain packs")
	var pages:=Exhibit.recap_pages("beimen",w.state)
	expect(JSON.stringify(pages).contains("這批沒有在下雨天裝籃") and not JSON.stringify(pages).contains("其中 0 籃"),"order B: pages say plainly that nothing was packed in the rain")
	view(w,BETA,"beimen","order B: beta (never in 北門) views")
	expect(same(pl(w,BETA).get(Exhibit.RECORD_KEY),{"seen":["beimen"]}) and Exhibit.personal_hint_for(w.state,"beimen",BETA)==Exhibit.HINT_SALT_NOT_READY,"order B: beta seen, catch-up hint")
	expect(validates(w.state),"order B: state validates")

# ------------------------------------------- other three exhibits unchanged --

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

func earn_tea_order(w:World,token:String) -> bool:
	give(w,token,"tea_worn_jar",5)
	put(w,token,AT_POTTER,"yingge")
	if not act(w,token,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar").ok:return false
	for i in 5:
		if not act(w,token,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar").ok:return false
	give(w,token,"tea_light",4)
	give(w,token,"tea_deep",1)
	put(w,token,AT_PACKER,"maokong")
	for style:String in ["deep","light","light","deep","light","light"]:
		if not act(w,token,TR.FILL_ACTION,TR.PACKER,style).ok:return false
	if not act(w,token,TR.SEND_ACTION,TR.PACKER).ok:return false
	put(w,token,AT_POTTER,"yingge")
	return TR.completed(w.state) and act(w,token,TR.CLAIM_ACTION,TR.POTTER).ok

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
	for id:String in ["lanyang","jinguashi","tea_pottery"]:
		out[id]={"row_a":Exhibit.exhibit(w.state,id,ALPHA),"row_b":Exhibit.exhibit(w.state,id,BETA),"recap":Exhibit.recap_for(w.state,id),
			"pages":Exhibit.recap_pages(id,w.state),"hint_a":Exhibit.personal_hint_for(w.state,id,ALPHA),"hint_b":Exhibit.personal_hint_for(w.state,id,BETA)}
	# unread counts every exhibit on display, so it legitimately grows with the salt story;
	# check_others_unchanged checks it separately.
	var keys:=OLD_PERSONAL_KEYS.filter(func(k):return k!="unread")
	out["personal_a"]=only(Exhibit.personal(w.state,ALPHA),keys)
	out["personal_b"]=only(Exhibit.personal(w.state,BETA),keys)
	out["own_a"]=only(Exhibit.own(w.state,ALPHA),OLD_OWN_KEYS)
	out["own_b"]=only(Exhibit.own(w.state,BETA),OLD_OWN_KEYS)
	return out

## The plaque, lantern and tea ware cards, recaps, pages and hints are identical whether or
## not the salt story exists; with all four done the exhibits are independent.
func check_others_unchanged() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.state.festival_story_open=true # PRESET
	if not expect(earn_lanyang(w,ALPHA),"Lanyang revisit earned"):return
	if not expect(earn_jinguashi(w,ALPHA),"Jinguashi revisit earned and lantern claimed"):return
	earn_chapter(w)
	if not expect(earn_comparison(w,ALPHA) and earn_tea_order(w,ALPHA),"tea story earned and tea ware claimed"):return
	put(w,ALPHA,NEAR,"home")
	var before:=snapshot_of(w)
	expect(Exhibit.unread_count(w.state,ALPHA)==3 and Exhibit.unread_count(w.state,BETA)==3,"three unread before the salt story")
	expect(Exhibit.on_display_ids(w.state)==["lanyang","jinguashi","tea_pottery"],"three exhibits before the salt story")
	expect((before.tea_pottery.pages as Array).size()==4 and (before.lanyang.row_a.lines as Array).size()==7,"plaque and tea ware cards as in their own suites")
	expect(Exhibit.personal_hint_for(w.state,"beimen",ALPHA)==Exhibit.HINT_SALT_LOCKED,"salt hint locked before the gates")
	if not expect(arrive(w,ALPHA) and repair_gates(w,ALPHA) and hand_rake(w,ALPHA) and earn_batch(w,ALPHA) and earn_claim(w,ALPHA),"salt story earned and basket claimed on the same day"):return
	put(w,ALPHA,NEAR,"home")
	var after:=snapshot_of(w)
	expect(var_to_bytes(before)==var_to_bytes(after),"plaque, lantern and tea ware outputs byte-identical before and after the salt story")
	expect(sorted_keys(Exhibit.personal(w.state,ALPHA))==PERSONAL_KEYS and sorted_keys(Exhibit.own(w.state,ALPHA))==OWN_KEYS,"personal()/own() only gained the basket keys")
	expect(Exhibit.on_display_ids(w.state)==["lanyang","jinguashi","tea_pottery","beimen"] and Exhibit.unread_count(w.state,ALPHA)==4 and Exhibit.unread_count(w.state,BETA)==4,"four exhibits on display in fixed order, unread 3 -> 4")
	view(w,ALPHA,"beimen","alpha views the salt basket first")
	view(w,ALPHA,"tea_pottery","alpha views the tea ware")
	view(w,ALPHA,"lanyang","alpha views the plaque")
	view(w,ALPHA,"jinguashi","alpha views the lantern")
	expect(same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["beimen","tea_pottery","lanyang","jinguashi"]}) and Exhibit.unread_count(w.state,ALPHA)==0,"all four seen in viewing order")
	expect(Exhibit.personal_hint_for(w.state,"beimen",ALPHA)==Exhibit.HINT_SALT_CLAIMED and Exhibit.personal_hint_for(w.state,"tea_pottery",ALPHA)==Exhibit.HINT_TEA_CLAIMED and Exhibit.personal_hint_for(w.state,"jinguashi",ALPHA)==Exhibit.HINT_JG_CLAIMED,"each exhibit keeps its own claimed hint")
	expect(validates(w.state),"world with all four stories and all seen validates")

# --------------------------------------------------------- client shapes --

func check_client_shapes() -> void:
	var snap:={"time":0.0,"festival_story":{"opened":true},Exhibit.STATE_KEY:{"cell":STAND,"paused":false,"on_display":["beimen"],"blocked_cells":[]},
		SR.STATE_KEY:{"stocked":{"sunny":6,"cloudy":0},"packed":{"kitchen":3,"pickle":3},"rain_packs":0,"day":1,"completed":true,"done_day":1,"claimed_own":false},
		"salt_pan":{"repaired":true,"own":{"record":{"raked":0}}},
		Exhibit.OWN_KEY:{"seen":[],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}}
	expect(Exhibit.on_display_ids(snap)==["beimen"] and Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_NOT_READY,"client: not ready")
	snap[Exhibit.OWN_KEY].raking_done=true
	expect(Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_UNCLAIMED,"client: own block says raked → unclaimed")
	snap[Exhibit.OWN_KEY].basket_claimed=true
	expect(Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_CLAIMED,"client: claimed")
	expect(same(Exhibit.recap_for(snap,"beimen"),{"day":1,"weather":"sunny","weather_label":"晴天","order_day":1,"season":"spring","season_label":"春季","reason":SR.reason_for("spring"),"order":{"kitchen":3,"pickle":3},"sunny":6,"cloudy":0,"kitchen":3,"pickle":3,"rain_packs":0}),"client recap from the public block")
	snap.erase(Exhibit.OWN_KEY)
	snap.salt_pan.own.record.raked=1
	snap[SR.STATE_KEY].claimed_own=true
	expect(Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_CLAIMED,"client without own block falls back to salt_pan.own.record / claimed_own")
	snap[SR.STATE_KEY].claimed_own=false
	expect(Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_UNCLAIMED,"client fallback: unclaimed")
	snap.erase(SR.STATE_KEY)
	expect(Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_NOT_DONE and Exhibit.on_display_ids(snap).is_empty(),"client: no record → not done, nothing on display (record decides, not the public list)")
	snap.salt_pan.own.record.raked=0
	expect(Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_NOT_DONE_NOT_READY,"client: not done and not ready")
	snap.salt_pan.repaired=false
	expect(Exhibit.personal_hint_for(snap,"beimen")==Exhibit.HINT_SALT_LOCKED,"client: gates not repaired → locked")
