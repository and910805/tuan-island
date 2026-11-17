extends SceneTree
## 第 40 章地方記憶展第二件展品「礦燈」(memory_exhibit.gd + jinguashi_revisit.gd) rules test.
## Headless, World-level (World.act / save / load_world) plus an in-process Session for
## the public / own snapshot. No network.
##
## EARNED through real World.act: the picnic, the Q07 hoist repair (mine_hoist_repair),
## every first Bobo sort (bobo_sort_start / answer ×3 / claim), the whole 金瓜石回訪
## (jg_revisit_sort ×3, jg_revisit_ship ×3), every lantern claim (jg_revisit_claim), every
## exhibit_view; for the Lanyang-unchanged check also the canal repair, first 分水, plaque
## and 旱日分流 (same actions test_memory_exhibit uses).
## WRITTEN DIRECTLY (disclosed): state.festival_story_open=true (the festival opening
## is covered by the festival suites), board=true + soup/bread for the picnic,
## mine_depths unlocked 6 / pumped 24, hoist materials, gold_ore 3 per Bobo sort, the
## shipped ores (gold_ore 2, copper_ore 4, stone 6), Lanyang repair materials, player
## region/x/y (no travel action), state.time jumps (day 3), tampered / legacy save files
## and synthetic client-shaped snapshots.
const World=preload("res://scripts/world.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Bobo=preload("res://scripts/bobo_workshop.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const ALPHA:="lantern-alpha-token-3b9e"
const BETA:="lantern-beta-token-c41f"
const LATE:="lantern-late-token-82d0"
const KIT:="mine_lantern_kit"
const STAND:=Vector2i(39,26)
const NEAR:=Vector2(39.5,27.5)
const TABLE:=Vector2i(23,20)
const AT_TABLE:=Vector2(23.5,21.5)
const AT_HOIST:=Vector2(27.5,19.5)
const AT_SHUTTLE:=Vector2(12.5,20.5)
const DAY:=1440.0
const SPRING:={"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"}
const OWN_KEYS:=["basket_claimed","comparison_done","first_share_done","lantern_claimed","plaque_claimed","raking_done","seen","sorting_done","teaware_claimed"]
const PERSONAL_KEYS:=["basket_claimed","basket_hint","comparison_done","first_share_done","hint","lantern_claimed","lantern_hint","plaque_claimed","raking_done","seen","sorting_done","teaware_claimed","teaware_hint","unread"]

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
	check_lanyang_unchanged()
	check_client_shapes()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("MEMORY_EXHIBIT_LANTERN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("exhibit-lantern-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"lantern-req-%d"%serial,action,p,extra)

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

func earn_picnic(w:World,token:String) -> bool:
	w.state["board"]=true
	put(w,token,Vector2(40.5,30.5),"home")
	pl(w,token).inventory["soup"]=2
	pl(w,token).inventory["bread"]=1
	return act(w,token,"picnic",Vector2i(40,29)).ok

func earn_hoist(w:World,token:String) -> bool:
	w.state["mine_depths"]={"unlocked":6,"ready":{},"pumped":24,"hoist":false}
	for item in Mines.HOIST_COST:pl(w,token).inventory[item]=int(pl(w,token).inventory.get(item,0))+int(Mines.HOIST_COST[item])
	put(w,token,AT_HOIST,"jinguashi")
	return act(w,token,World.HOIST_ACTION,Mines.ENTRY).ok

func earn_bobo(w:World,token:String) -> bool:
	pl(w,token).inventory["gold_ore"]=int(pl(w,token).inventory.get("gold_ore",0))+Bobo.INPUT
	put(w,token,AT_TABLE,"jinguashi")
	if not act(w,token,"bobo_sort_start",TABLE).ok:return false
	for step in Bobo.STEPS.size():
		if not act(w,token,"bobo_sort_answer",TABLE,"%d:%s"%[step,Bobo.STEPS[step]]).ok:return false
	return act(w,token,"bobo_sort_claim",TABLE).ok

func spot_for(dest:String) -> Vector2:
	match dest:
		"bobo":return AT_TABLE
		"ferry":return AT_SHUTTLE
	return AT_HOIST

## Earned spring dispatch: sort the three crates, then ship in `order` (ores written).
## When `last_day_index` >= 0 the clock jumps there before the final crate.
func earn_dispatch(w:World,token:String,order:Array,last_day_index:int=-1) -> bool:
	put(w,token,AT_TABLE,"jinguashi")
	for dest:String in JG.DESTS:
		if not act(w,token,JG.SORT_ACTION,TABLE,JG.sort_extra(dest,str(SPRING[dest]))).ok:return false
	for i in order.size():
		var dest:String=order[i]
		if i==order.size()-1 and last_day_index>=0:w.state["time"]=float(last_day_index)*DAY+30.0
		var ore:=str(SPRING[dest])
		pl(w,token).inventory[ore]=int(pl(w,token).inventory.get(ore,0))+JG.amount_for(ore)
		put(w,token,spot_for(dest),"jinguashi")
		if not act(w,token,JG.SHIP_ACTION,JG.dest_cell(w.state,dest)).ok:return false
	return JG.completed(w.state)

func earn_claim(w:World,token:String) -> bool:
	put(w,token,AT_TABLE,"jinguashi")
	return act(w,token,JG.CLAIM_ACTION,TABLE).ok

func row(rows:Array,id:String) -> Dictionary:
	for r:Dictionary in rows:
		if r.id==id:return r
	return {}

func hint(w:World,token:String) -> String:
	return Exhibit.personal_hint_for(w.state,"jinguashi",token)

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	var hints:={}
	for h:String in [Exhibit.HINT_JG_LOCKED,Exhibit.HINT_JG_NOT_DONE_NOT_READY,Exhibit.HINT_JG_NOT_DONE,Exhibit.HINT_JG_NOT_READY,Exhibit.HINT_JG_UNCLAIMED,Exhibit.HINT_JG_CLAIMED,
		Exhibit.HINT_REVISIT_LOCKED,Exhibit.HINT_NOT_DONE_NOT_READY,Exhibit.HINT_NOT_DONE,Exhibit.HINT_NOT_READY,Exhibit.HINT_UNCLAIMED,Exhibit.HINT_CLAIMED]:hints[h]=true
	expect(hints.size()==12,"six lantern hints, all distinct from the six plaque hints")
	expect(str(Exhibit.EXHIBITS.jinguashi.name)==JG.LANTERN_NAME,"exhibit name = lantern name (礦燈)")
	var empty:={}
	expect(not Exhibit.available(empty,"jinguashi") and Exhibit.personal_hint_for(empty,"tea_pottery")==Exhibit.HINT_TEA_NOT_DONE_NOT_READY and Exhibit.personal_hint_for(empty,"beimen")==Exhibit.HINT_SALT_LOCKED and Exhibit.personal_hint_for(empty,"bogus")=="","no record: not available; tea_pottery and beimen have their own hints, unknown has none")
	expect(Exhibit.jinguashi_recap(empty)=={} and Exhibit.recap_for(empty,"jinguashi")=={} and Exhibit.recap_for(empty,"tea_pottery")=={},"no recap without completion")

# ------------------------------------------------------- order A: festival first --

func order_a() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.state.festival_story_open=true # PRESET
	expect(hint(w,ALPHA)==Exhibit.HINT_JG_LOCKED,"hint before the hoist: locked")
	if not expect(earn_picnic(w,ALPHA) and earn_hoist(w,ALPHA),"picnic and hoist earned"):return null
	expect(hint(w,ALPHA)==Exhibit.HINT_JG_NOT_DONE_NOT_READY,"hoist fixed, alpha never sorted with Bobo")
	if not expect(earn_bobo(w,ALPHA),"alpha's Bobo sort earned"):return null
	expect(hint(w,ALPHA)==Exhibit.HINT_JG_NOT_DONE and hint(w,BETA)==Exhibit.HINT_JG_NOT_DONE_NOT_READY,"hints: alpha ready / beta not ready, dispatch not done")
	expect(Exhibit.personal_hint(w.state,ALPHA)==Exhibit.HINT_REVISIT_LOCKED,"the plaque hint (personal_hint) is untouched by Jinguashi progress")
	put(w,ALPHA,NEAR,"home")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"jinguashi",Exhibit.NOT_ON_DISPLAY,"lantern before the dispatch")
	expect(Exhibit.view_block(w.state,"jinguashi",ALPHA)==Exhibit.NOT_ON_DISPLAY,"view_block before completion")
	# Partial dispatch keeps the pedestal empty.
	put(w,ALPHA,AT_TABLE,"jinguashi")
	for dest:String in JG.DESTS:ok(w,ALPHA,JG.SORT_ACTION,TABLE,JG.sort_extra(dest,str(SPRING[dest])),"sort %s"%dest)
	for dest:String in ["ferry","bobo"]:
		var ore:=str(SPRING[dest])
		pl(w,ALPHA).inventory[ore]=JG.amount_for(ore)
		put(w,ALPHA,spot_for(dest),"jinguashi")
		ok(w,ALPHA,JG.SHIP_ACTION,JG.dest_cell(w.state,dest),"","ship %s"%dest)
		expect(not Exhibit.available(w.state,"jinguashi") and Exhibit.on_display_ids(w.state).is_empty(),"after shipping %s the lantern is still not on display"%dest)
	expect(row(Exhibit.exhibits(w.state,ALPHA),"jinguashi").lines==[Exhibit.EMPTY_LINE] and Exhibit.recap_pages("jinguashi",w.state).is_empty(),"empty card and no pages while incomplete")
	pl(w,ALPHA).inventory["stone"]=6
	put(w,ALPHA,AT_HOIST,"jinguashi")
	ok(w,ALPHA,JG.SHIP_ACTION,JG.HOIST,"","alpha ships the last crate")
	if not expect(JG.completed(w.state),"dispatch completed"):return null
	# The exhibit updates with progress.
	expect(Exhibit.on_display_ids(w.state)==["jinguashi"] and Exhibit.on_display(w.state,"jinguashi") and not Exhibit.on_display(w.state,"lanyang"),"lantern on display, plaque still empty")
	expect(Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"unread 1 for both")
	expect(same(Exhibit.public(w.state),{"cell":STAND,"paused":false,"on_display":["jinguashi"],"blocked_cells":[]}),"public block lists jinguashi")
	expect(hint(w,ALPHA)==Exhibit.HINT_JG_UNCLAIMED and hint(w,BETA)==Exhibit.HINT_JG_NOT_READY,"hints: alpha unclaimed, beta not ready")
	var card:=row(Exhibit.exhibits(w.state,ALPHA),"jinguashi")
	expect(card.on_display and card.unread and not card.seen and card.source==JG.LANTERN_SOURCE and card.project==JG.LANTERN_PROJECT and card.blurb==JG.LANTERN_BLURB and card.disclaimer==JG.DISCLAIMER and card.name=="礦燈","lantern card: provenance + disclaimer")
	var want_lines:=[JG.LANTERN_BLURB,JG.LANTERN_SOURCE,JG.LANTERN_PROJECT,"完成那天：第 1 日・晴天",
		"春季的訂單：波波的整理桌 含金礦料 2／渡口家園工坊 銅礦 4／坑內礦務站 石材 6",
		"送出的先後：渡口家園工坊、波波的整理桌、坑內礦務站",JG.DISCLAIMER]
	expect(card.lines==want_lines,"lantern card lines restate the record (%s)"%str(card.lines))
	for id:String in ["lanyang","tea_pottery","beimen"]:
		expect(row(Exhibit.exhibits(w.state,ALPHA),id).lines==[Exhibit.EMPTY_LINE],"%s still empty"%id)
	var r:=Exhibit.jinguashi_recap(w.state)
	expect(same(r,{"day":1,"weather":"sunny","weather_label":"晴天","order_day":1,"season":"spring","season_label":"春季","reason":JG.reason_for("spring"),
		"crates":[{"id":"bobo","name":"波波的整理桌","how":JG.DEST_HOW.bobo,"ore":"gold_ore","ore_name":"含金礦料","amount":2},
			{"id":"ferry","name":"渡口家園工坊","how":JG.DEST_HOW.ferry,"ore":"copper_ore","ore_name":"銅礦","amount":4},
			{"id":"depot","name":"坑內礦務站","how":JG.DEST_HOW.depot,"ore":"stone","ore_name":"石材","amount":6}],
		"sent":["ferry","bobo","depot"],"sent_names":["渡口家園工坊","波波的整理桌","坑內礦務站"]}),"recap from the stored record (%s)"%str(r))
	expect(same(Exhibit.recap_for(w.state,"jinguashi"),r) and Exhibit.recap(w.state)=={},"recap_for(jinguashi); Lanyang recap still empty")
	var pages:=Exhibit.recap_pages("jinguashi",w.state)
	expect(pages.size()==4,"four recap pages")
	var titles:=pages.map(func(p):return str(p.title))
	expect(titles==["回訪的緣由","訂單上的需要","怎麼分揀與寄運","帶回家的紀念"],"page titles (%s)"%str(titles))
	for page:Dictionary in pages:expect((page.lines as Array).size()>=2,"page '%s' has lines"%page.title)
	var all_text:=JSON.stringify(pages)
	expect(all_text.contains("波波的整理桌 含金礦料 2、渡口家園工坊 銅礦 4、坑內礦務站 石材 6") and all_text.contains("送出的先後是渡口家園工坊、波波的整理桌、坑內礦務站") and all_text.contains("第 1 日・晴天") and all_text.contains("沒有記錄是誰"),"pages: numbers, order, honest no-actor note (%s)"%all_text)
	expect(not all_text.contains(ALPHA) and not all_text.contains("Alpha"),"pages name no player")
	expect(str((pages[3].lines as Array).back())==JG.DISCLAIMER,"last page ends with the disclaimer")
	# Views.
	view(w,ALPHA,"jinguashi","alpha views the lantern")
	expect(same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["jinguashi"]}) and not pl(w,BETA).has(Exhibit.RECORD_KEY),"only alpha's record changes")
	put(w,ALPHA,NEAR,"home")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"jinguashi",Exhibit.ALREADY_SEEN,"alpha views again")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.NOT_ON_DISPLAY,"plaque still not on display")
	put(w,ALPHA,AT_TABLE,"jinguashi")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"jinguashi",Exhibit.WRONG_REGION,"view from Jinguashi")
	# Claims update the hint.
	expect(earn_claim(w,ALPHA),"alpha claims her lantern")
	expect(hint(w,ALPHA)==Exhibit.HINT_JG_CLAIMED,"alpha: claimed hint")
	expect(same(Exhibit.own(w.state,ALPHA),{"seen":["jinguashi"],"first_share_done":false,"plaque_claimed":false,"sorting_done":true,"lantern_claimed":true,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}),"alpha's own block")
	var me:=Exhibit.personal(w.state,ALPHA)
	expect(sorted_keys(me)==PERSONAL_KEYS and me.lantern_hint==Exhibit.HINT_JG_CLAIMED and me.hint==Exhibit.HINT_REVISIT_LOCKED and me.sorting_done and me.lantern_claimed and me.unread==0,"alpha personal(): lantern keys alongside the plaque keys")
	# Late joiner: never visited Jinguashi.
	w.add_player(LATE,"Late")
	put(w,LATE,NEAR,"home")
	expect(Exhibit.unread_count(w.state,LATE)==1 and hint(w,LATE)==Exhibit.HINT_JG_NOT_READY,"late joiner: unread 1, catch-up hint")
	view(w,LATE,"jinguashi","late joiner views the lantern")
	expect(same(pl(w,LATE).get(Exhibit.RECORD_KEY),{"seen":["jinguashi"]}) and Exhibit.unread_count(w.state,LATE)==0,"late joiner marked seen")
	if expect(earn_bobo(w,LATE),"late joiner sorts with Bobo later"):
		expect(hint(w,LATE)==Exhibit.HINT_JG_UNCLAIMED,"late joiner: lantern waiting at Bobo's")
		expect(earn_claim(w,LATE) and hint(w,LATE)==Exhibit.HINT_JG_CLAIMED,"late joiner claims; claimed hint")
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
	for region in ["home","jinguashi"]:
		var public:Dictionary=session.public_state(region)
		expect(same(public.get(Exhibit.STATE_KEY),{"cell":STAND,"paused":false,"on_display":["jinguashi"],"blocked_cells":[]}),"public_state(%s): exhibit block lists the lantern"%region)
		expect(not JSON.stringify(public).contains("\"seen\"") and not JSON.stringify(public).contains("lantern_claimed"),"public_state(%s): no seen list, no personal lantern flag"%region)
	session._send_snapshot(1)
	var a:Dictionary=session.snapshot
	expect(sorted_keys(a.get(Exhibit.OWN_KEY,{}))==OWN_KEYS and same(a.get(Exhibit.OWN_KEY),Exhibit.own(w.state,ALPHA)),"alpha's own block carries the lantern keys")
	expect(not JSON.stringify(a).contains(ALPHA) and not JSON.stringify(a).contains(BETA),"no raw token in alpha's snapshot")
	expect(same(Exhibit.exhibits(a),Exhibit.exhibits(w.state,ALPHA)),"client exhibits() == server exhibits(alpha)")
	expect(same(Exhibit.personal(a),Exhibit.personal(w.state,ALPHA)),"client personal() == server personal(alpha)")
	expect(Exhibit.personal_hint_for(a,"jinguashi")==Exhibit.HINT_JG_CLAIMED,"client lantern hint for alpha")
	expect(same(Exhibit.recap_pages("jinguashi",a),Exhibit.recap_pages("jinguashi",w.state)) and same(Exhibit.jinguashi_recap(a),Exhibit.jinguashi_recap(w.state)),"client recap == server recap")
	session.peers={1:BETA,2:ALPHA}
	session._send_snapshot(1)
	var b:Dictionary=session.snapshot
	expect(same(b.get(Exhibit.OWN_KEY),{"seen":[],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}),"beta's own block shows nothing of alpha's")
	expect(Exhibit.unread_count(b)==1 and Exhibit.personal_hint_for(b,"jinguashi")==Exhibit.HINT_JG_NOT_READY and Exhibit.view_block(b,"jinguashi")=="","beta's client: unread, catch-up hint, may view")
	session.world=null
	session.queue_free()
	w.save_path=saved_path
	await process_frame

# ------------------------------------------------------------------- saving --

func check_save(w:World) -> void:
	var path:=temp_path("main")
	var fixture:=temp_path("fixture")
	w.save_path=path
	if not expect(w.save(),"world saves"):return
	var reloaded:=World.new()
	if not expect(reloaded.load_world(path),"reload"):return
	for token in [ALPHA,BETA,LATE]:
		expect(same(Exhibit.personal(reloaded.state,token),Exhibit.personal(w.state,token)) and same(Exhibit.exhibits(reloaded.state,token),Exhibit.exhibits(w.state,token)),"%s's exhibit view identical after reload"%token)
	expect(same(Exhibit.recap_pages("jinguashi",reloaded.state),Exhibit.recap_pages("jinguashi",w.state)),"pages identical after reload")
	put(reloaded,ALPHA,NEAR,"home")
	refuse(reloaded,ALPHA,Exhibit.VIEW_ACTION,STAND,"jinguashi",Exhibit.ALREADY_SEEN,"after reload alpha has still seen it")
	var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(validates(base),"saved world validates")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	for label:String in ["seen jinguashi without the record","seen jinguashi before completion","seen jinguashi without the hoist (record dropped)"]:
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
		"seen jinguashi without the record":
			s.erase(JG.STATE_KEY)
		"seen jinguashi before completion":
			s[JG.STATE_KEY]={"crates":SPRING.duplicate(),"day":1,"sent":["ferry","bobo"],"completed":false,"done_day":0,"claimed":{}}
		"seen jinguashi without the hoist (record dropped)":
			s.erase(JG.STATE_KEY)
			s.mine_depths.hoist=false
	return s

# ----------------------------------------------- order B: dispatch first --

func order_b() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	if not expect(earn_picnic(w,ALPHA) and earn_hoist(w,ALPHA) and earn_bobo(w,ALPHA),"order B: picnic, hoist, Bobo sort earned"):return
	if not expect(earn_dispatch(w,ALPHA,["depot","ferry","bobo"],2),"order B: dispatch completed before the festival (last crate on day 3)"):return
	put(w,ALPHA,NEAR,"home")
	expect(not Exhibit.unlocked(w.state) and Exhibit.on_display_ids(w.state).is_empty() and Exhibit.public(w.state)=={},"order B: dispatch done but festival closed -> nothing shown")
	expect(Exhibit.available(w.state,"jinguashi") and not Exhibit.on_display(w.state,"jinguashi"),"order B: story complete, not on display")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"jinguashi",Exhibit.LOCKED,"order B: view before the festival")
	w.state.festival_story_open=true # PRESET
	expect(Exhibit.on_display_ids(w.state)==["jinguashi"] and Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"order B: opening the festival shows the lantern at once, unread for both")
	var card:=row(Exhibit.exhibits(w.state,BETA),"jinguashi")
	expect(card.lines[3]=="完成那天：第 3 日・小雨" and card.lines[4].begins_with("春季的訂單：") and card.lines[5]=="送出的先後：坑內礦務站、渡口家園工坊、波波的整理桌","order B: completion day 3 (rain) differs from the day-1 order (%s)"%str(card.lines))
	var r:=Exhibit.jinguashi_recap(w.state)
	expect(int(r.day)==3 and int(r.order_day)==1 and r.weather=="rainy" and r.season=="spring","order B: recap keeps order day 1 and completion day 3")
	view(w,BETA,"jinguashi","order B: beta (never in Jinguashi) views")
	expect(same(pl(w,BETA).get(Exhibit.RECORD_KEY),{"seen":["jinguashi"]}) and Exhibit.personal_hint_for(w.state,"jinguashi",BETA)==Exhibit.HINT_JG_NOT_READY,"order B: beta seen, catch-up hint")
	expect(validates(w.state),"order B: state validates")

# ------------------------------------------------- Lanyang output unchanged --

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

## The plaque card, recap, pages and hints are identical whether or not the lantern
## story exists; with both done the two exhibits are independent.
func check_lanyang_unchanged() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.state.festival_story_open=true # PRESET
	if not expect(earn_lanyang(w,ALPHA),"Lanyang revisit earned"):return
	put(w,ALPHA,NEAR,"home")
	var before:={"row":Exhibit.exhibit(w.state,"lanyang",ALPHA),"recap":Exhibit.recap(w.state),"pages":Exhibit.recap_pages("lanyang",w.state),
		"hint_a":Exhibit.personal_hint(w.state,ALPHA),"hint_b":Exhibit.personal_hint(w.state,BETA)}
	expect(before.hint_a==Exhibit.personal_hint_for(w.state,"lanyang",ALPHA) and before.hint_b==Exhibit.personal_hint_for(w.state,"lanyang",BETA),"personal_hint == personal_hint_for(lanyang)")
	expect((before.row.lines as Array).size()==7 and str(before.row.lines[3])=="完成那天：第 1 日・春季・晴天" and (before.pages as Array).size()==4,"plaque card as in test_memory_exhibit")
	if not expect(earn_picnic(w,ALPHA) and earn_hoist(w,ALPHA) and earn_bobo(w,ALPHA) and earn_dispatch(w,ALPHA,["bobo","ferry","depot"]),"Jinguashi dispatch earned on the same day"):return
	put(w,ALPHA,NEAR,"home")
	var after:={"row":Exhibit.exhibit(w.state,"lanyang",ALPHA),"recap":Exhibit.recap(w.state),"pages":Exhibit.recap_pages("lanyang",w.state),
		"hint_a":Exhibit.personal_hint(w.state,ALPHA),"hint_b":Exhibit.personal_hint(w.state,BETA)}
	expect(var_to_bytes(before)==var_to_bytes(after),"plaque outputs byte-identical before and after the lantern story")
	expect(Exhibit.on_display_ids(w.state)==["lanyang","jinguashi"] and Exhibit.unread_count(w.state,ALPHA)==2,"both exhibits on display in fixed order, two unread")
	view(w,ALPHA,"lanyang","alpha views the plaque")
	view(w,ALPHA,"jinguashi","alpha views the lantern")
	expect(same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["lanyang","jinguashi"]}) and Exhibit.unread_count(w.state,ALPHA)==0,"both seen in viewing order")
	expect(validates(w.state),"world with both stories and both seen validates")

# --------------------------------------------------------- client shapes --

func check_client_shapes() -> void:
	var snap:={"festival_story":{"opened":true},Exhibit.STATE_KEY:{"cell":STAND,"paused":false,"on_display":["jinguashi"],"blocked_cells":[]},
		JG.STATE_KEY:{"crates":SPRING.duplicate(),"day":1,"sent":["bobo","ferry","depot"],"completed":true,"done_day":1,"claimed_own":false},
		"mine_depths":{"hoist":true},"bobo_workshop":{"site":0,"own_done":false},
		Exhibit.OWN_KEY:{"seen":[],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false}}
	expect(Exhibit.on_display_ids(snap)==["jinguashi"] and Exhibit.personal_hint_for(snap,"jinguashi")==Exhibit.HINT_JG_NOT_READY,"client: not ready")
	snap[Exhibit.OWN_KEY].sorting_done=true
	expect(Exhibit.personal_hint_for(snap,"jinguashi")==Exhibit.HINT_JG_UNCLAIMED,"client: own block says sorted → unclaimed")
	snap[Exhibit.OWN_KEY].lantern_claimed=true
	expect(Exhibit.personal_hint_for(snap,"jinguashi")==Exhibit.HINT_JG_CLAIMED,"client: claimed")
	snap.erase(Exhibit.OWN_KEY)
	snap.bobo_workshop.own_done=true
	snap[JG.STATE_KEY].claimed_own=true
	expect(Exhibit.personal_hint_for(snap,"jinguashi")==Exhibit.HINT_JG_CLAIMED,"client without own block falls back to bobo_workshop.own_done / claimed_own")
	snap[JG.STATE_KEY].claimed_own=false
	expect(Exhibit.personal_hint_for(snap,"jinguashi")==Exhibit.HINT_JG_UNCLAIMED,"client fallback: unclaimed")
	snap.erase(JG.STATE_KEY)
	expect(Exhibit.personal_hint_for(snap,"jinguashi")==Exhibit.HINT_JG_NOT_DONE and Exhibit.on_display_ids(snap).is_empty(),"client: no record → not done, nothing on display (record decides, not the public list)")
	snap.mine_depths.hoist=false
	expect(Exhibit.personal_hint_for(snap,"jinguashi")==Exhibit.HINT_JG_LOCKED,"client: hoist not fixed → locked")
