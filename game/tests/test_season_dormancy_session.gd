extends SceneTree
## T048 四季休眠與再生作物 two-client Session acceptance over a real dedicated server and
## real WebSocket clients (plan acceptance「跨季不枯死，收成次數不重置」). Harness copied from
## test_corn_chowder_session.gd / test_water_tower_quota_session.gd.
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (甲 alpha = plot owner, 乙 beta =
## friend) and, after a restart, a late joiner (丙 gamma) join over loopback, each in its own
## branch with its own SceneMultiplayer. Clients only read their own received snapshots;
## World.plot_dormant is evaluated on each client's own snapshot (crop entry, roofs entry,
## region_id, time) and compared with the same call on the server World. The on-disk save is
## read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and validated
## with SaveSchema. Plot cells are found by a throwaway probe World (first adjacent pair near
## World.SPAWN that alpha can till from one standable spot, plus a beta spot within reach of
## both plots). EARNED there through World.act: alpha tills both plots, sows lettuce from
## the starter bag on plot 2 and harvests it (so island_crops_discoveries already exists before
## the baseline key set is taken), then sows tomato on plot 1.
## PRESET list (every direct write is marked # PRESET and counted; the count is printed):
##   seed : world time = summer day 15 (T_SUMMER1); alpha / beta x,y (standing spots);
##          lettuce growth = ripe (75) before its offline harvest; alpha inventory =
##          {tomato_seed 2}; tomato growth = ripe (120, first crop); receipts cleared.
##   live : server world time -> autumn day 29 (T_AUTUMN, case 3); -> 2 s before the midnight
##          that starts summer day 71 (case 4, the real midnight then dries the soil);
##          -> autumn day 85 (T_AUTUMN2, case 5). Time only ever moves forward.
## Nothing else is written: every water / harvest / sow is sent by a client over the network,
## growth comes only from real server ticks. Regrowth (60 -> 120) runs on the live server clock
## with a temporary Engine.time_scale (TIME_SCALE) inside this one process, restored to 1.0
## before any action; the dormant phase is also run at TIME_SCALE to show it does not grow.
## Replay: (a) the first harvest is sent twice back-to-back with the same fresh sequence over
## the raw request_action RPC; (b) that sequence is re-sent later. Session must apply it once.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), greenhouse roofs (rule level), harvest_access settings, sprinklers.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Weather=preload("res://scripts/weather.gd")
const KEY:="season-dormancy-session"
const ALPHA:="dormancy-session-alpha-token"
const BETA:="dormancy-session-beta-token"
const GAMMA:="dormancy-session-gamma-token"
const HOME:="home"
const TIME_SCALE:=20.0
const DAY:=1440.0
## Zero-based day indices: 14 = summer, 28 = autumn, 69 = spring (last day), 70 = summer,
## 84 = autumn. Days 14/28/70/84 are all CYCLE[0] (sunny), day 69 is cloudy: no rain wets a plot.
const T_SUMMER1:=14.0*DAY+200.0
const T_AUTUMN:=28.0*DAY+200.0
const T_SPRING_END:=70.0*DAY-2.0
const T_SUMMER2_START:=70.0*DAY
const T_AUTUMN2:=84.0*DAY+200.0
## Keys of a pre-existing plot (hoe creates kind/growth/wet/owner, sowing adds remaining).
const PLOT_KEYS:=["growth","kind","owner","remaining","wet"]
const QUALITY_KEYS:=["fertility","last_care_day","last_harvest_kind"]
## Literal strings from world.gd (seed / harvest / water branches).
const DORMANT_MSG:="作物正在休眠，等到適合的季節會繼續生長。"
const PLANT_DORMANT_MSG:="種下太陽番茄。現在不是它的季節，會休眠到夏季再生長。"
const CARE_MSG:="水分充足 · 照料 %d／5"
const NOT_RIPE_DRY:="還沒成熟，先澆點水吧"
const NO_CROP:="這裡沒有作物"
const H1_MSG:="收成了！太陽番茄 +2。太陽番茄還能再收 2 次，記得重新澆水"
const H2_MSG:="收成了！太陽番茄 +2。太陽番茄還能再收 1 次，記得重新澆水"
const H3_MSG:="收成了！太陽番茄 +2。可以出售或帶去做料理"

class Client:
	var label:=""
	var token:=""
	var branch:Node
	var session
	var notices:Array=[]
	var changes:=0
	func on_notice(message:String,success:bool)->void:
		notices.append([message,success])
	func on_changed(_data:Dictionary,_id:String)->void:
		changes+=1
	func me()->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary or session.own_id.is_empty():return {}
		var mine=people.get(session.own_id,{})
		return mine if mine is Dictionary else {}
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func crop(k:String)->Dictionary:
		var crops=session.snapshot.get("crops",{})
		if not crops is Dictionary:return {}
		var c=crops.get(k,{})
		return c if c is Dictionary else {}
	func roof(k:String)->Dictionary:
		var roofs=session.snapshot.get("roofs",{})
		if not roofs is Dictionary:return {}
		var r=roofs.get(k,{})
		return r if r is Dictionary else {}
	func now()->float:
		return float(session.snapshot.get("time",-1.0))
	## World.plot_dormant from this client's own snapshot only.
	func dormant(tile:Vector2i)->bool:
		var k:String=World.key(tile)
		var c:=crop(k)
		if c.is_empty():return false
		return World.plot_dormant(c,roof(k),str(session.snapshot.get("region_id","")),tile,now())

var checks:=0
var failures:=0
var serial:=0
var presets:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var alpha:Client
var beta:Client
var gamma:Client
var plot1:=Vector2i(-1,-1)
var plot2:=Vector2i(-1,-1)
var k1:=""
var k2:=""
var a_spot:=Vector2(-1,-1)
var b_spot:=Vector2(-1,-1)
var saw_mid:=false

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(110.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	Engine.time_scale=1.0
	print("SEASON_DORMANCY_SESSION watchdog fired before completion")
	print("SEASON_DORMANCY_SESSION presets=%d"%presets)
	print("SEASON_DORMANCY_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	Engine.time_scale=1.0
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("SEASON_DORMANCY_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("SEASON_DORMANCY_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("SEASON_DORMANCY_SESSION presets=%d"%presets)
	print("SEASON_DORMANCY_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

## Every direct state write goes through here (counted, marked # PRESET at the call site).
func preset(d:Dictionary,field:String,value:Variant)->void:
	d[field]=value
	presets+=1

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	var r:Dictionary=w.act(token,"seed-%d"%serial,action,p,extra)
	if not bool(r.get("ok",false)):print("SEASON_DORMANCY_SESSION seed action %s %s %s refused: %s"%[action,str(p),extra,str(r.get("message",""))])
	return bool(r.get("ok",false))

static func centre(t:Vector2i)->Vector2:
	return Vector2(t)+Vector2(0.5,0.5)

## Standable tile centre within 3.0 of every target (targets and `taken` tiles excluded).
static func stand_spot(w:World,targets:Array,taken:Array)->Vector2:
	var first:Vector2i=targets[0]
	for dy in range(-3,4):
		for dx in range(-3,4):
			var tile:=first+Vector2i(dx,dy)
			if tile in taken:continue
			var at:=centre(tile)
			if not w.can_stand(at):continue
			var near:=true
			for t:Vector2i in targets:
				if at.distance_to(centre(t))>3.0:near=false
			if near:return at
	return Vector2(-1,-1)

static func fresh_probe()->World:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	return w

## Throwaway probe World: the first adjacent pair of tillable home cells near the spawn.
func find_layout()->bool:
	var cands:Array=[]
	for y in range(26,42):
		for x in range(30,50):cands.append(Vector2i(x,y))
	cands.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return centre(a).distance_squared_to(World.SPAWN)<centre(b).distance_squared_to(World.SPAWN))
	var probe:=fresh_probe()
	for cand:Vector2i in cands:
		var p1:=cand
		var p2:=cand+Vector2i(1,0)
		var spot:=stand_spot(probe,[p1,p2],[p1,p2])
		if spot.x<0:continue
		var who:Dictionary=probe.state.players[ALPHA]
		who["x"]=spot.x
		who["y"]=spot.y
		serial+=1
		if not bool(probe.act(ALPHA,"probe-%d"%serial,"hoe",p1).get("ok",false)):continue
		serial+=1
		if not bool(probe.act(ALPHA,"probe-%d"%serial,"hoe",p2).get("ok",false)):
			probe=fresh_probe()
			continue
		var bspot:=stand_spot(probe,[p1,p2],[p1,p2,Vector2i(floori(spot.x),floori(spot.y))])
		if bspot.x<0:
			probe=fresh_probe()
			continue
		plot1=p1
		plot2=p2
		k1=World.key(p1)
		k2=World.key(p2)
		a_spot=spot
		b_spot=bspot
		return true
	return false

func seed_world(path:String)->bool:
	if not find_layout():
		print("SEASON_DORMANCY_SESSION no tillable plot pair found near the spawn")
		return false
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	preset(w.state,"time",T_SUMMER1) # PRESET summer day 15
	var a:Dictionary=w.state.players[ALPHA]
	preset(a,"x",a_spot.x) # PRESET
	preset(a,"y",a_spot.y) # PRESET
	var b:Dictionary=w.state.players[BETA]
	preset(b,"x",b_spot.x) # PRESET
	preset(b,"y",b_spot.y) # PRESET
	if not seed_act(w,ALPHA,"hoe",plot1):return false
	if not seed_act(w,ALPHA,"hoe",plot2):return false
	# Lettuce from the starter bag, harvested offline: the island's first crop discovery key
	# exists before the baseline, so later tomato harvests do not add a top-level key.
	if not seed_act(w,ALPHA,"seed",plot2,"lettuce"):return false
	preset(w.state.crops[k2],"growth",float(World.CROPS.lettuce.time)) # PRESET ripe lettuce
	if not seed_act(w,ALPHA,"harvest",plot2):return false
	a=w.state.players[ALPHA]
	b=w.state.players[BETA]
	preset(a,"inventory",{"tomato_seed":2}) # PRESET
	if not seed_act(w,ALPHA,"seed",plot1,"tomato"):return false
	preset(w.state.crops[k1],"growth",float(World.CROPS.tomato.time)) # PRESET ripe first tomato crop
	a=w.state.players[ALPHA]
	b=w.state.players[BETA]
	preset(a,"receipts",{}) # PRESET
	preset(b,"receipts",{}) # PRESET
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
	if not parsed.has("island_crops_discoveries"):return false
	var crops=parsed.get("crops",{})
	if not crops is Dictionary:return false
	if disk_row(crops.get(k1))!=want("tomato",120.0,3,false):return false
	if disk_row(crops.get(k2))!=want("",0.0,0,false):return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

# ------------------------------------------------------------- transport --

func new_branch(prefix:String)->Node:
	serial+=1
	var branch:=Node.new()
	branch.name="%s%d"%[prefix,serial]
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	return branch

func start_server()->int:
	server_branch=new_branch("Server")
	server=Session.new()
	server_branch.add_child(server)
	for attempt in 8:
		var port:=randi_range(31000,58000)
		if server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:return port
	return 0

func stop_server()->bool:
	var ok:bool=server.shutdown()
	await pause(0.2)
	server_branch.queue_free()
	await process_frame
	return ok

func join(label:String,token:String,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.branch=new_branch("Client_%s_"%label)
	c.session=Session.new()
	c.branch.add_child(c.session)
	c.session.profile["token"]=token
	c.session.notice.connect(c.on_notice)
	c.session.changed.connect(c.on_changed)
	if c.session.join("ws://127.0.0.1:%d"%port,port,label,KEY)!=OK:return c
	await wait_until(func():return joined(c),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("crops") is Dictionary

func leave(c:Client)->void:
	if c==null or not is_instance_valid(c.session):return
	if not c.session.shutting_down:c.session.shutdown()
	await process_frame
	c.branch.queue_free()

func wait_until(condition:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return condition.call()

func pause(seconds:float)->void:
	await create_timer(seconds,true,false,true).timeout

func settle(clients:Array)->void:
	var marks:Array=clients.map(func(c):return c.changes)
	await wait_until(func():
		for i in clients.size():
			if clients[i].changes<int(marks[i])+2:return false
		return true,3.0)

func act(c:Client,action:String,p:Vector2i,extra:String="")->Dictionary:
	var before:=c.notices.size()
	var sequence:int=c.session.perform(action,p,extra)
	var replied:=await wait_until(func():return c.notices.size()>before,4.0)
	if not replied:return {"replied":false,"ok":false,"message":"","sequence":sequence}
	await settle([c])
	var reply:Array=c.notices[before]
	return {"replied":true,"ok":bool(reply[1]),"message":str(reply[0]),"sequence":sequence}

## Live server clock at TIME_SCALE until `condition` holds (bounded), then back to 1.0.
func fast_forward(condition:Callable,seconds:float)->bool:
	Engine.time_scale=TIME_SCALE
	var ok:=await wait_until(condition,seconds)
	Engine.time_scale=1.0
	await pause(0.2)
	return ok

## Live server clock at TIME_SCALE for a fixed real duration, then back to 1.0.
func run_scaled(seconds:float)->void:
	Engine.time_scale=TIME_SCALE
	await pause(seconds)
	Engine.time_scale=1.0
	await pause(0.2)

## Every listed client's snapshot clock has reached `t`.
func clocks_reach(clients:Array,t:float,seconds:float)->bool:
	return await wait_until(func():
		for c in clients:
			if c==null or c.now()<t:return false
		return true,seconds)

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

static func key_list(d:Variant)->Array:
	var keys:Array=[]
	if not d is Dictionary:return keys
	for k in d:keys.append(str(k))
	keys.sort()
	return keys

static func added_keys(now_keys:Array,base:Array)->Array:
	var out:Array=[]
	for k in now_keys:
		if not base.has(k):out.append(k)
	return out

## The four compared crop fields of one entry (client, server or disk).
static func row_of(c:Dictionary)->String:
	if c.is_empty():return "none"
	return text({"kind":str(c.get("kind","<missing>")),"growth":float(c.get("growth",-1.0)),"remaining":int(c.get("remaining",-1)),"wet":c.get("wet")==true})

static func disk_row(c:Variant)->String:
	if not c is Dictionary:return "none"
	return row_of(c)

static func want(kind:String,growth:float,remaining:int,wet:bool)->String:
	return text({"kind":kind,"growth":growth,"remaining":remaining,"wet":wet})

static func season_of(t:float)->String:
	return Weather.season_on_day(Weather.day_index(t))

func server_ok()->bool:
	return server!=null and is_instance_valid(server) and server.world!=null

func srv_crop(k:String)->Dictionary:
	if not server_ok():return {"<no server>":true}
	var crops=server.world.state.get("crops",{})
	var c=crops.get(k,{}) if crops is Dictionary else {}
	return c.duplicate(true) if c is Dictionary else {}

func srv_time()->float:
	if not server_ok():return -1.0
	return float(server.world.state.get("time",-1.0))

func srv_dormant(tile:Vector2i)->bool:
	if not server_ok():return false
	var k:String=World.key(tile)
	var c:=srv_crop(k)
	if c.is_empty():return false
	var roofs=server.world.state.get("roofs",{})
	var r=roofs.get(k,{}) if roofs is Dictionary else {}
	return World.plot_dormant(c,r if r is Dictionary else {},HOME,tile,srv_time())

func srv_bag(token:String)->Dictionary:
	if not server_ok():return {"<no server>":-1}
	var people=server.world.state.get("players",{})
	var p=people.get(token,{}) if people is Dictionary else {}
	var inv=p.get("inventory",{}) if p is Dictionary else {}
	return canon(inv)

## PRESET: the only live writes to server state (world time), counted.
func preset_time(t:float)->void:
	preset(server.world.state,"time",t)

func marks_of(clients:Array)->Array:
	var out:Array=clients.map(func(x):return [row_of(x.crop(k1)),row_of(x.crop(k2)),text(canon(x.bag()))])
	out.append([row_of(srv_crop(k1)),row_of(srv_crop(k2)),text(srv_bag(ALPHA)),text(srv_bag(BETA))])
	return out

## Every listed client and the server hold `row` for the plot key.
func all_see(clients:Array,k:String,row:String,seconds:float)->bool:
	return await wait_until(func():
		if row_of(srv_crop(k))!=row:return false
		for c in clients:
			if c==null or row_of(c.crop(k))!=row:return false
		return true,seconds)

func seen_text(clients:Array,k:String)->String:
	var parts:Array=clients.map(func(c):return "%s %s"%[c.label,row_of(c.crop(k))])
	parts.append("server %s"%row_of(srv_crop(k)))
	return str(parts)

## Stable phase: each client's crop fields equal the server's, and plot_dormant computed from
## each client's own snapshot equals the server-side call and the expectation.
func agree(clients:Array,label:String,d1:bool,d2:bool)->void:
	for pair in [[plot1,d1],[plot2,d2]]:
		var tile:Vector2i=pair[0]
		var want_d:bool=pair[1]
		var k:String=World.key(tile)
		var server_crop:=srv_crop(k)
		var srow:=row_of(server_crop)
		var sd:=srv_dormant(tile)
		expect(sd==want_d,"%s: server plot_dormant(%s)==%s (got %s, time %.1f %s)"%[label,k,str(want_d),str(sd),srv_time(),season_of(srv_time())])
		for c:Client in clients:
			expect(row_of(c.crop(k))==srow,"%s: %s sees plot %s exactly as the server (client %s, server %s)"%[label,c.label,k,row_of(c.crop(k)),srow])
			expect(c.dormant(tile)==sd,"%s: %s plot_dormant(%s) from its own snapshot agrees with the server (client %s, server %s)"%[label,c.label,k,str(c.dormant(tile)),str(sd)])
			expect(key_list(c.crop(k))==key_list(server_crop) and quality_fields(c.crop(k))==quality_fields(server_crop),"%s: %s plot %s keeps the server plot fields and quality values"%[label,c.label,k])
		expect(valid_plot_keys(server_crop),"%s: server plot %s uses ordinary and recognized quality fields (got %s)"%[label,k,str(key_list(server_crop))])

static func valid_plot_keys(crop:Dictionary)->bool:
	return PLOT_KEYS.all(func(key):return crop.has(key)) and crop.keys().all(func(key):return key in PLOT_KEYS or key in QUALITY_KEYS)

static func quality_fields(crop:Dictionary)->Dictionary:
	var fields:Dictionary={}
	for key in QUALITY_KEYS:
		if crop.has(key):
			fields[key]=str(crop[key]) if key=="last_harvest_kind" else int(crop[key])
	return fields

func keys_same(pairs:Array,label:String)->void:
	for pair in pairs:
		var c:Client=pair[0]
		var base:Array=pair[1]
		var now_keys:Array=key_list(c.session.snapshot)
		expect(now_keys==base,"%s: %s top-level snapshot keys unchanged (added %s, missing %s)"%[label,c.label,str(added_keys(now_keys,base)),str(added_keys(base,now_keys))])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: both plots and bags unchanged on the server and in every watching snapshot (%s -> %s)"%[label,str(marks),str(marks_of(everyone))])

func succeed(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok and str(r.message)==message,"%s: ok with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

## Re-send an already-used sequence number over the raw RPC; Session must drop it.
func replay(c:Client,sequence:int,action:String,p:Vector2i,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var counts:Array=everyone.map(func(x):return x.notices.size())
	var before:=marks_of(everyone)
	c.session.request_action.rpc_id(1,sequence,action,p,"",str(c.session.snapshot.get("region_id","")),int(c.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle(everyone)
	expect(everyone.map(func(x):return x.notices.size())==counts,"%s: re-sent sequence %d gets no notice"%[label,sequence])
	expect(marks_of(everyone)==before,"%s: re-sent sequence %d changes nothing on the server or either client (applied once)"%[label,sequence])

func tomatoes(c:Client)->int:
	return int(c.bag().get("tomato",0))

func srv_tomatoes(token:String)->int:
	return int(srv_bag(token).get("tomato",0))

func token_free(c:Client,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	expect(not dump.contains(ALPHA) and not dump.contains(BETA) and not dump.contains(GAMMA),"%s: %s's snapshot contains no raw token (plot owners hashed)"%[label,c.label])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func disk_crop(disk:Variant,k:String)->Variant:
	if not disk is Dictionary:return null
	var crops=disk.get("crops",{})
	return crops.get(k) if crops is Dictionary else null

static func disk_tomatoes(disk:Variant,token:String)->int:
	if not disk is Dictionary:return -1
	var people=disk.get("players",{})
	var p=people.get(token,{}) if people is Dictionary else {}
	var inv=p.get("inventory",{}) if p is Dictionary else {}
	return int(inv.get("tomato",0)) if inv is Dictionary else -1

## Field-by-field save check of one plot against the last server row (JSON reorders keys).
func disk_plot_ok(disk:Variant,k:String,server_crop:Dictionary,owner:String,label:String)->void:
	var d=disk_crop(disk,k)
	if not expect(d is Dictionary,"%s: saved plot %s present"%[label,k]):return
	expect(disk_row(d)==row_of(server_crop),"%s: saved plot %s kind/growth/remaining/wet agree"%[label,k])
	expect(key_list(d)==key_list(server_crop) and quality_fields(d)==quality_fields(server_crop),"%s: saved plot %s preserves quality metadata"%[label,k])
	expect(str(d.get("owner",""))==owner,"%s: saved plot %s owner is alpha's raw token on disk"%[label,k])
	var g:Variant=d.get("growth")
	var r:Variant=d.get("remaining")
	expect(typeof(g) in [TYPE_INT,TYPE_FLOAT] and typeof(r) in [TYPE_INT,TYPE_FLOAT] and typeof(d.get("wet"))==TYPE_BOOL,"%s: saved plot %s growth/remaining numeric and wet boolean"%[label,k])

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	# Static rule facts the scenario relies on.
	expect(float(World.CROPS.tomato.get("regrow",-1.0))==60.0 and int(World.CROPS.tomato.get("cycles",0))==3 and float(World.CROPS.tomato.time)==120.0 and int(World.CROPS.tomato.yield)==2,"static: tomato time 120, regrow 60, cycles 3, yield 2")
	expect(World.regrow_start("tomato")==60.0,"static: World.regrow_start(\"tomato\")==60.0 (got %s)"%str(World.regrow_start("tomato")))
	expect(World.CROP_SEASONS.get("tomato",[])==["summer"],"static: tomato grows only in summer")
	expect(not World.CROPS.lettuce.has("cycles"),"static: lettuce is single-harvest (fixture plot 2 empties)")
	expect(season_of(T_SUMMER1)=="summer" and season_of(T_AUTUMN)=="autumn" and season_of(T_SPRING_END)=="spring" and season_of(T_SUMMER2_START)=="summer" and season_of(T_AUTUMN2)=="autumn","static: preset times fall in summer / autumn / spring(end) / summer / autumn")
	var no_rain:=true
	for t:float in [T_SUMMER1,T_AUTUMN,T_SPRING_END,T_SUMMER2_START,T_AUTUMN2]:
		if Weather.rains(Weather.day_index(t)):no_rain=false
	expect(no_rain,"static: no preset day is rainy (rain cannot wet a plot behind the test's back)")
	folder=OS.get_environment("TEMP").path_join("season-dormancy-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (plots tilled, lettuce sown+harvested, tomato sown offline; time, spots, bag, ripe growth written) accepted by SaveSchema"):return false
	print("SEASON_DORMANCY_SESSION layout plot1=%s plot2=%s alpha=%s beta=%s"%[k1,k2,str(a_spot),str(b_spot)])
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("SEASON_DORMANCY_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner after restart) fixture=SEEDED(plots+lettuce+tomato earned offline; time, spots, bag, ripe growth written) live_presets=world time only clock=Engine.time_scale %.0fx during growth/dormancy waits shutdown=normal-only"%[port,TIME_SCALE])

	# 1. Summer, ripe tomato: both ends agree; baseline key sets.
	var ab:Array=[alpha,beta]
	expect(await all_see(ab,k1,want("tomato",120.0,3,false),3.0),"case 1 both see the ripe tomato (120, remaining 3, dry) %s"%seen_text(ab,k1))
	expect(await all_see(ab,k2,want("",0.0,0,false),1.0),"case 1 both see the empty pre-existing plot 2 %s"%seen_text(ab,k2))
	for c:Client in ab:
		expect(str(c.session.snapshot.get("region_id",""))==HOME and season_of(c.now())=="summer","case 1 %s is at home in summer (time %.1f)"%[c.label,c.now()])
		token_free(c,"case 1")
	agree(ab,"case 1",false,false)
	var keys_a0:Array=key_list(alpha.session.snapshot)
	var keys_b0:Array=key_list(beta.session.snapshot)
	expect(keys_a0.has("crops") and keys_a0.has("roofs") and keys_a0.has("time") and keys_a0.has("region_id"),"case 1 snapshot carries crops/roofs/time/region_id (inputs of plot_dormant)")
	expect(canon(alpha.bag())==canon({"tomato_seed":1}) and srv_bag(ALPHA)==canon({"tomato_seed":1}),"case 1 alpha's bag is exactly tomato_seed 1 (client %s, server %s)"%[text(canon(alpha.bag())),text(srv_bag(ALPHA))])
	var beta_bag0:Dictionary=canon(beta.bag())
	expect(tomatoes(beta)==0 and srv_tomatoes(BETA)==0,"case 1 beta holds no tomato")

	# 2. In season: alpha harvests; same fresh sequence sent twice -> applied once.
	await settle(ab)
	var region:=str(alpha.session.snapshot.get("region_id",""))
	var epoch:=int(alpha.me().get("travel_epoch",0))
	var n0:=alpha.notices.size()
	var bn0:=beta.notices.size()
	var seq:int=int(alpha.session.counter)+1
	alpha.session.counter=seq
	alpha.session.request_action.rpc_id(1,seq,"harvest",plot1,"",region,epoch)
	alpha.session.request_action.rpc_id(1,seq,"harvest",plot1,"",region,epoch)
	await pause(0.8)
	await settle(ab)
	expect(alpha.notices.size()==n0+1 and alpha.notices[n0]==[H1_MSG,true],"case 2 the same harvest sequence sent twice gets exactly one reply '%s' (%s)"%[H1_MSG,str(alpha.notices.slice(n0))])
	expect(beta.notices.size()==bn0,"case 2 beta gets no notice from alpha's harvest")
	var regrow_row:=want("tomato",World.regrow_start("tomato"),2,false)
	expect(await all_see(ab,k1,regrow_row,3.0),"case 2 both see growth == regrow_start(tomato) 60, remaining 2, dry %s"%seen_text(ab,k1))
	expect(tomatoes(alpha)==2 and srv_tomatoes(ALPHA)==2,"case 2 alpha +2 tomato exactly once (client %d, server %d)"%[tomatoes(alpha),srv_tomatoes(ALPHA)])
	expect(tomatoes(beta)==0 and srv_tomatoes(BETA)==0 and canon(beta.bag())==beta_bag0,"case 2 beta's bag unchanged")
	await replay(alpha,seq,"harvest",plot1,"case 2 replay of the first harvest",[beta])
	expect(tomatoes(alpha)==2 and int(alpha.crop(k1).get("remaining",-1))==2,"case 2 after the replay alpha still has 2 tomatoes and remaining 2")
	await refuse(beta,"harvest",plot1,"",NOT_RIPE_DRY,"case 2 beta harvests the regrowing (dry, in-season) tomato",[alpha])
	agree(ab,"case 2",false,false)
	keys_same([[alpha,keys_a0],[beta,keys_b0]],"case 2")

	# 3. Out of season (autumn): watered, real ticks, no growth; harvests refused; dormant sowing.
	preset_time(T_AUTUMN) # PRESET autumn day 29
	expect(await clocks_reach(ab,T_AUTUMN,4.0),"case 3 both clients' clocks show autumn (%s)"%str(ab.map(func(c):return c.now())))
	await settle(ab)
	expect(await all_see(ab,k1,regrow_row,2.0),"case 3 the mid-regrow tomato survived into autumn unchanged %s"%seen_text(ab,k1))
	agree(ab,"case 3 autumn",true,false)
	await succeed(alpha,"water",plot1,"",CARE_MSG%1,"case 3 alpha waters the dormant tomato",[beta])
	var wet_regrow:=want("tomato",60.0,2,true)
	expect(await all_see(ab,k1,wet_regrow,3.0),"case 3 both see the dormant tomato wet, growth 60, remaining 2 %s"%seen_text(ab,k1))
	var t_before:=srv_time()
	await run_scaled(2.5)
	await settle(ab)
	var t_after:=srv_time()
	expect(t_after-t_before>=10.0 and Weather.day_index(t_after)==Weather.day_index(t_before),"case 3 the live server clock advanced %.1f world s within the same autumn day"%(t_after-t_before))
	expect(await all_see(ab,k1,wet_regrow,2.0),"case 3 after real ticks the watered dormant tomato is still 60 / remaining 2 / wet %s"%seen_text(ab,k1))
	agree(ab,"case 3 after ticks",true,false)
	await refuse(alpha,"harvest",plot1,"",DORMANT_MSG,"case 3 alpha harvests the dormant tomato",[beta])
	await refuse(beta,"harvest",plot1,"",DORMANT_MSG,"case 3 beta harvests the dormant tomato",[alpha])
	await succeed(alpha,"seed",plot2,"tomato",PLANT_DORMANT_MSG,"case 3 alpha sows tomato out of season",[beta])
	expect(await all_see(ab,k2,want("tomato",0.0,3,false),3.0),"case 3 both see the newly sown tomato on plot 2 (0, remaining 3) %s"%seen_text(ab,k2))
	expect(int(alpha.bag().get("tomato_seed",0))==0 and int(srv_bag(ALPHA).get("tomato_seed",0))==0,"case 3 alpha's last tomato seed was used")
	agree(ab,"case 3 sown",true,true)
	await refuse(beta,"harvest",plot2,"",DORMANT_MSG,"case 3 beta harvests the freshly sown dormant tomato",[alpha])
	expect(tomatoes(alpha)==2 and srv_tomatoes(ALPHA)==2 and tomatoes(beta)==0,"case 3 no tomato gained while dormant")
	keys_same([[alpha,keys_a0],[beta,keys_b0]],"case 3")

	# 4. Next summer: the real midnight dries the soil, watering regrows on real ticks,
	#    harvests 2 and 3 work, the plot empties, alpha totals 6 tomatoes.
	preset_time(T_SPRING_END) # PRESET 2 s before the midnight that starts summer day 71
	expect(await clocks_reach(ab,T_SUMMER2_START+0.5,8.0),"case 4 the live clock crossed the midnight into summer (%s)"%str(ab.map(func(c):return c.now())))
	await settle(ab)
	expect(await all_see(ab,k1,regrow_row,2.0),"case 4 at summer's first midnight the soil dried; growth 60 and remaining 2 kept through the dormancy %s"%seen_text(ab,k1))
	for c:Client in ab:expect(season_of(c.now())=="summer","case 4 %s's clock is in summer"%c.label)
	agree(ab,"case 4 summer",false,false)
	await succeed(alpha,"water",plot1,"",CARE_MSG%2,"case 4 alpha waters the tomato in season",[beta])
	saw_mid=false
	var ripe2:=await fast_forward(func():
		var g:=float(alpha.crop(k1).get("growth",-1.0))
		if g>60.0 and g<120.0:saw_mid=true
		return float(alpha.crop(k1).get("growth",-1.0))>=120.0 and float(beta.crop(k1).get("growth",-1.0))>=120.0,15.0)
	expect(ripe2,"case 4 the watered tomato regrew to ripe on the live server clock (time scale %.0fx) %s"%[TIME_SCALE,seen_text(ab,k1)])
	expect(saw_mid,"case 4 alpha's snapshots showed growth strictly between 60 and 120 (advanced by ticks, not jumped)")
	await settle(ab)
	expect(await all_see(ab,k1,want("tomato",120.0,2,true),2.0),"case 4 both see ripe 120, remaining 2 (never reset), wet %s"%seen_text(ab,k1))
	await succeed(alpha,"harvest",plot1,"",H2_MSG,"case 4 alpha's second harvest",[beta])
	expect(await all_see(ab,k1,want("tomato",60.0,1,false),3.0),"case 4 after harvest 2 both see 60 / remaining 1 / dry %s"%seen_text(ab,k1))
	expect(tomatoes(alpha)==4 and srv_tomatoes(ALPHA)==4,"case 4 alpha holds 4 tomatoes (client %d, server %d)"%[tomatoes(alpha),srv_tomatoes(ALPHA)])
	await succeed(alpha,"water",plot1,"","水分充足，幼苗會慢慢長大","case 4 alpha waters again",[beta])
	var ripe3:=await fast_forward(func():return float(alpha.crop(k1).get("growth",-1.0))>=120.0 and float(beta.crop(k1).get("growth",-1.0))>=120.0,15.0)
	expect(ripe3,"case 4 the tomato regrew a second time on the live clock %s"%seen_text(ab,k1))
	await settle(ab)
	expect(await all_see(ab,k1,want("tomato",120.0,1,true),2.0),"case 4 both see ripe 120, remaining 1, wet %s"%seen_text(ab,k1))
	await succeed(alpha,"harvest",plot1,"",H3_MSG,"case 4 alpha's third (last) harvest",[beta])
	expect(await all_see(ab,k1,want("",0.0,0,false),3.0),"case 4 after the third harvest the plot is empty on both ends %s"%seen_text(ab,k1))
	expect(tomatoes(alpha)==6 and srv_tomatoes(ALPHA)==6,"case 4 alpha received 6 tomatoes in total (client %d, server %d)"%[tomatoes(alpha),srv_tomatoes(ALPHA)])
	expect(tomatoes(beta)==0 and srv_tomatoes(BETA)==0 and canon(beta.bag())==beta_bag0,"case 4 beta's bag unchanged")
	await refuse(alpha,"harvest",plot1,"",NO_CROP,"case 4 a fourth harvest finds no crop",[beta])
	agree(ab,"case 4 emptied",false,false)
	keys_same([[alpha,keys_a0],[beta,keys_b0]],"case 4")

	# 5. Autumn again; dormant plot 2 watered; normal shutdown -> save; restart; late joiner.
	preset_time(T_AUTUMN2) # PRESET autumn day 85
	expect(await clocks_reach(ab,T_AUTUMN2,4.0),"case 5 both clocks show the second autumn")
	await settle(ab)
	await succeed(alpha,"water",plot2,"",CARE_MSG%3,"case 5 alpha waters the dormant plot-2 tomato",[beta])
	expect(await all_see(ab,k2,want("tomato",0.0,3,true),3.0),"case 5 plot 2 dormant: growth 0, remaining 3, wet %s"%seen_text(ab,k2))
	agree(ab,"case 5 before shutdown",false,true)
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	await pause(0.3)
	var saved1:=srv_crop(k1)
	var saved2:=srv_crop(k2)
	var last1:=row_of(saved1)
	var last2:=row_of(saved2)
	var last_time:=srv_time()
	expect(last2==want("tomato",0.0,3,true) and last1==want("",0.0,0,false),"case 5 last server state: plot 1 empty, plot 2 dormant tomato (%s / %s)"%[last1,last2])
	expect(await stop_server(),"case 5 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 5 save parses"):return false
	expect(disk_valid(disk),"case 5 saved world passes SaveSchema")
	disk_plot_ok(disk,k1,saved1,ALPHA,"case 5 save")
	disk_plot_ok(disk,k2,saved2,ALPHA,"case 5 save")
	# JSON.stringify without full precision may round the live clock in the last digits.
	expect(absf(float(disk.get("time",-1.0))-last_time)<0.01 and season_of(float(disk.get("time",-1.0)))=="autumn","case 5 saved time equals the last server time, autumn (%s vs %.3f)"%[str(disk.get("time")),last_time])
	expect(disk_tomatoes(disk,ALPHA)==6 and disk_tomatoes(disk,BETA)==0,"case 5 save: alpha 6 tomatoes, beta 0")

	var port2:=start_server()
	if not expect(port2>0,"case 5 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 5 alpha and beta rejoin"):return false
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 5 late joiner gamma joins"):return false
	var abg:Array=[alpha,beta,gamma]
	await settle(abg)
	expect(row_of(srv_crop(k1))==last1 and row_of(srv_crop(k2))==last2,"case 5 restarted server loaded both plots unchanged")
	expect(await all_see(abg,k1,last1,3.0),"case 5 alpha, beta and gamma see plot 1 as saved %s"%seen_text(abg,k1))
	expect(await all_see(abg,k2,last2,3.0),"case 5 alpha, beta and gamma see the dormant plot-2 tomato as saved %s"%seen_text(abg,k2))
	agree(abg,"case 5 after restart",false,true)
	for c:Client in abg:token_free(c,"case 5")
	await refuse(alpha,"harvest",plot2,"",DORMANT_MSG,"case 5 alpha harvests the dormant tomato after the restart",[beta,gamma])
	await refuse(beta,"harvest",plot2,"",DORMANT_MSG,"case 5 beta harvests the dormant tomato after the restart",[alpha,gamma])
	expect(tomatoes(alpha)==6 and srv_tomatoes(ALPHA)==6 and tomatoes(gamma)==0,"case 5 alpha still 6 tomatoes after the restart, gamma none")

	# 6. Public snapshot shape: no new top-level key anywhere, crop entries unchanged in shape.
	keys_same([[alpha,keys_a0],[beta,keys_b0],[gamma,keys_a0]],"case 6")
	agree(abg,"case 6",false,true)

	for c:Client in [gamma,alpha,beta]:await leave(c)
	gamma=null
	alpha=null
	beta=null
	await pause(0.3)
	var final1:=srv_crop(k1)
	var final2:=srv_crop(k2)
	expect(await stop_server(),"case 6 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after),"case 6 final save passes SaveSchema")
	disk_plot_ok(after,k1,final1,ALPHA,"case 6 final save")
	disk_plot_ok(after,k2,final2,ALPHA,"case 6 final save")
	expect(row_of(final2)==last2 and quality_fields(final2)==quality_fields(saved2),"case 6 the dormant tomato and quality fields did not change across the restart")
	expect(after is Dictionary and after.get("players",{}).has(GAMMA),"case 6 final save records gamma")
	return true

func teardown()->void:
	Engine.time_scale=1.0
	for c in [alpha,beta,gamma]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma]:
		if c!=null and is_instance_valid(c.branch):c.branch.queue_free()
	if is_instance_valid(server_branch):server_branch.queue_free()
	await process_frame

func remove_folder()->bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):return false
	var dir:=DirAccess.open(folder)
	if dir==null:return false
	for file in dir.get_files():
		if DirAccess.remove_absolute(folder.path_join(file))!=OK:return false
	return DirAccess.remove_absolute(folder)==OK and not DirAccess.dir_exists_absolute(folder)
