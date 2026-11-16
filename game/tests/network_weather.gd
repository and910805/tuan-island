extends SceneTree
## Real multi-process network regression of T039 weather (protocol 43 / save 24)
## over plain loopback WebSocket (ws://127.0.0.1:<port>; NOT wss/TLS, NOT cloud,
## no adverse-network model). Clients only join through Session.join and read
## the authoritative snapshots the SEPARATE dedicated server broadcasts; no
## client ever touches a World, calls World.step or sends a mutating action.
## Weather is derived from the snapshot `time` with the shipped weather.gd.
##
## SEEDED NETWORK FIXTURE - NOT AN EARNED JOURNEY. The `seed` step is the ONLY
## direct state write (labelled, printed in WX_FIXTURE.seeded):
##   clock        world time = SEED_TIME (rainy day 3, RAIN_WINDOW world s before
##                the day-4 midnight); the server clock is paused until a player joins
##   chapter      chapter_one shipped=true + board=true, watered=false, so a wrong
##                irrigation credit by rain would be observable
##   plots        home row of naturally clear cells (searched): alpha exposed
##                pumpkin (growth 0, dry), alpha unplanted soil, alpha mature
##                pumpkin (growth 270, dry), alpha roofed pumpkin (dry), beta
##                exposed pumpkin, beta unplanted soil
##   roof         manual roof record over alpha's roofed plot (SEEDED, non-natural:
##                hoe refuses floors and roofs need floors, so a greenhouse plot
##                cannot be produced by validated actions)
##   mine_plot    alpha pumpkin in mine_1 (indoor), dry, growth 0 (disk-checked by
##                the runner; home clients never receive mine_1 snapshots)
##   inventories  alpha {wheat 3, egg 1}; beta {wheat 4}
## The saved fixture is reloaded through World.load_world (SaveSchema) before
## the runner continues. Tokens come from WX_TOKENS and the room key from
## WX_ROOM_KEY (environment only) and are never printed.
##
## Driven by work/weather-network/network_weather.py. Args after `--`:
##   seed <world.json>                          -> WX_FIXTURE {json}
##   <live|restart> <port> <role> <handoff_dir>
## Barriers: client prints `WX_BARRIER <phase> <role> <name>` and waits for
## <handoff>/go-<phase>-<name>. Missing barrier/result = failure, never a skip.
##
## live (server runs with Godot --time-scale N: LABELLED accelerated clock):
##   both clients see their own AND the other's exposed plots wet while it rains
##   (time < midnight), growth == time - SEED_TIME, roofed plot dry/no growth,
##   mature plot capped; then, after the day-4 midnight, every plot dry, exposed
##   growth == RAIN_WINDOW (only wet time), mature not rotted, values stable while
##   the clock runs; bags unchanged; chapter_one.watered stays false.
##   Presentation: alpha computes with reduced_motion=true, beta false (fixture
##   preference values only; nothing is rendered or claimed about pixels).
## restart (normal stop + restart on the same save at the real clock): alpha and
##   beta reconnect, gamma joins late; exact saved time (sunny day 4), identical
##   plots, own bags; no foreign inventory.
## Output: WX_CHECK ok ..., WX_COVER <tag> <phase> <role>, WX_MARK {json},
## WX_WS_PASS / WX_WS_FAIL.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const Weather=preload("res://scripts/weather.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
const REGIONS=preload("res://scripts/regions.gd")
const MINES=preload("res://scripts/mine_depths.gd")

const CONTRACT_PROTOCOL:=45
const CONTRACT_SAVE:=26
const SEED_LABEL:="SEEDED NETWORK FIXTURE (game/tests/network_weather.gd seed) - not an earned journey"
const SEEDED:=["clock","chapter","plots","roof","mine_plot","inventories"]
const DAY:=1440.0
const RAIN_END:=4320.0          # day-4 midnight (day 3 = rainy, day 4 = sunny)
const RAIN_WINDOW:=180.0        # world s of rain after the first join (~18 real s at x10)
const SEED_TIME:=RAIN_END-RAIN_WINDOW
const DAY4_END:=5760.0
const PUMPKIN_TIME:=270.0       # > RAIN_WINDOW: the exposed pumpkins never mature here
const GROWTH_TOL:=0.01
const MINE:="mine_1"
const PLOT_ORDER:=["a_crop","a_soil","a_mature","a_roof","b_crop","b_soil"]
const PLOTS:={
	"a_crop":{"owner":"alpha","kind":"pumpkin","growth":0.0,"roof":false},
	"a_soil":{"owner":"alpha","kind":"","growth":0.0,"roof":false},
	"a_mature":{"owner":"alpha","kind":"pumpkin","growth":PUMPKIN_TIME,"roof":false},
	"a_roof":{"owner":"alpha","kind":"pumpkin","growth":0.0,"roof":true},
	"b_crop":{"owner":"beta","kind":"pumpkin","growth":0.0,"roof":false},
	"b_soil":{"owner":"beta","kind":"","growth":0.0,"roof":false}}
const SEED_INV:={"alpha":{"wheat":3,"egg":1},"beta":{"wheat":4}}
const REDUCED_MOTION:={"alpha":true,"beta":false,"gamma":true}
const PHASE_ROLES:={"live":["alpha","beta"],"restart":["alpha","beta","gamma"]}
const WATCHDOG:={"live":45.0,"restart":22.0}
const JOIN_WAIT:=12.0
const PEER_WAIT:=10.0
const RESULT_WAIT:=6.0
const BARRIER_WAIT:=25.0
const RAIN_WAIT:=25.0
const MIDNIGHT_WAIT:=25.0
const MIDNIGHT_SETTLE:=2.0      # world s past midnight before judging the dry state
const STABLE_GAP:=0.6           # real s between the two "stable" snapshots
const RESTART_DRIFT:=40.0       # world s a restart client may see beyond the saved time (real clock)

var session:Session
var phase:=""
var role:=""
var roles:Array=[]
var tokens:={}
var handoff:=""
var fixture:Dictionary={}
var plan:Dictionary={}
var snapshots:=0
var home_snapshots:=0
var online_max:=0
var first_time:=-1.0
var violation:=""
var checks:=0
var finished:=false
var expect_inv:Dictionary={}

func _initialize() -> void:
	run.call_deferred()

# ---------------------------------------------------------------- helpers

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

static func hid(token:String) -> String:
	return token.sha256_text().left(16)

static func ints(d:Variant) -> Dictionary:
	if not d is Dictionary:return {"<invalid>":-1}
	var out:={}
	for item in d:
		var v=d[item]
		if not (v is int or v is float):return {"<invalid>":-1}
		if int(v)!=0:out[str(item)]=int(v)
	return out

func snap() -> Dictionary:
	return session.snapshot if session!=null else {}

func inventory() -> Dictionary:
	var p=snap().get("players",{}).get(session.own_id,{})
	var inv=p.get("inventory",{}) if p is Dictionary else {}
	return inv if inv is Dictionary else {}

func inv_text() -> String:
	return JSON.stringify(ints(inventory())) if session!=null else "{}"

func inv_ok() -> bool:
	return ints(inventory())==expect_inv

func world_time() -> float:
	var t=snap().get("time")
	return float(t) if (t is int or t is float) else -1.0

func weather() -> Dictionary:
	return Weather.at(world_time(),str(snap().get("region_id","home")))

func credit_free() -> bool:
	var ch=snap().get("chapter_one")
	return ch is Dictionary and ch.get("watered")==false

## Authoritative plot record as received (owner already hashed by the server).
func plot_view(name:String) -> Dictionary:
	var c=snap().get("crops",{}).get(str(fixture.plots[name]))
	if not c is Dictionary:return {"missing":true}
	return {"kind":str(c.get("kind","")),"wet":c.get("wet")==true,"growth":snappedf(float(c.get("growth",-1.0)),0.001),
		"owner":str(c.get("owner","")),"remaining":int(c.get("remaining",-1))}

func plots_view() -> Dictionary:
	var out:={}
	for name in PLOT_ORDER:out[name]=plot_view(name)
	return out

static func same_plot(a:Variant,b:Variant) -> bool:
	if not a is Dictionary or not b is Dictionary or a.has("missing") or b.has("missing"):return false
	return str(a.get("kind"))==str(b.get("kind")) and bool(a.get("wet"))==bool(b.get("wet")) and str(a.get("owner"))==str(b.get("owner")) \
		and int(a.get("remaining",-1))==int(b.get("remaining",-2)) and absf(float(a.get("growth",-1))-float(b.get("growth",-2)))<=0.001

func same_plots(a:Dictionary,b:Dictionary) -> bool:
	for name in PLOT_ORDER:
		if not same_plot(a.get(name),b.get(name)):return false
	return true

## Empty string when every plot matches the weather rule at the snapshot time:
## wet iff raining and unroofed; growth only for wet time (from SEED_TIME, capped).
func plots_problem(raining:bool) -> String:
	var t:=minf(world_time(),RAIN_END)
	var roofs=snap().get("roofs",{})
	for name in PLOT_ORDER:
		var spec:Dictionary=PLOTS[name]
		var v:=plot_view(name)
		if v.has("missing"):return "%s missing from snapshot"%name
		var want_growth:=float(spec.growth)
		if str(spec.kind)!="" and not spec.roof and want_growth<PUMPKIN_TIME:want_growth=minf(t-SEED_TIME,PUMPKIN_TIME)
		var want_wet:bool=raining and not spec.roof
		var roofed:bool=roofs is Dictionary and roofs.has(str(fixture.plots[name]))
		if v.kind!=str(spec.kind) or v.wet!=want_wet or absf(float(v.growth)-want_growth)>GROWTH_TOL or v.owner!=hid(tokens[spec.owner]) \
			or v.remaining!=(1 if str(spec.kind)!="" else 0) or roofed!=bool(spec.roof):
			return "%s=%s (want wet=%s growth=%.3f roof=%s, t=%.3f)"%[name,JSON.stringify(v),str(want_wet),want_growth,str(spec.roof),world_time()]
	return ""

## Presentation values a client derives from the snapshot clock with its own
## preference. Fixture numbers only - nothing is drawn or verified on screen.
func presentation() -> Dictionary:
	var info:Dictionary=WeatherArt.current(snap())
	var reduced:bool=REDUCED_MOTION[role]
	return {"id":WeatherArt.weather_id(info),"label":WeatherArt.label(info),"raining":WeatherArt.rains(info),"icon":WeatherArt.icon_id(info),
		"tint_alpha":snappedf(WeatherArt.tint(info).a,0.001),"reduced_motion":reduced,"moving_drops":WeatherArt.rains(info) and not reduced,
		"rendered":false}

# ---------------------------------------------------------------- signals

func flag(text:String) -> void:
	if violation.is_empty():violation=text

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
	if first_time<0.0 and (data.get("time") is float or data.get("time") is int):first_time=float(data.time)
	var text:=var_to_str(data)+"|"+id
	for who in tokens:
		if text.contains(tokens[who]):flag("snapshot %d contains raw %s token"%[snapshots,who])
	var pop=data.get("region_population",{})
	var n:=0
	if pop is Dictionary:
		for region in pop:n+=int(pop[region])
	online_max=maxi(online_max,n)
	if str(data.get("region_id",""))!="home":return
	home_snapshots+=1
	var players=data.get("players",{})
	if players is Dictionary:
		for pid in players:
			var person=players[pid]
			if person is Dictionary and str(pid)!=id and (person.has("inventory") or person.has("receipts")):
				flag("snapshot %d shows another player's inventory/receipts"%snapshots)

func _on_notice(message:String,ok:bool) -> void:
	for who in tokens:
		if message.contains(tokens[who]):flag("notice contains raw %s token"%who)
	print("WX_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("WX_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("WX_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	data["phase"]=phase
	data["role"]=role
	print("WX_MARK "+JSON.stringify(data))

func until(predicate:Callable,seconds:float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if finished:return false
		if predicate.call():return true
		await create_timer(0.05).timeout
	return not finished and predicate.call()

func settle() -> void:
	var seen:=snapshots
	await until(func():return snapshots>=seen+2,RESULT_WAIT)

func barrier(name:String) -> bool:
	if finished:return false
	print("WX_BARRIER %s %s %s"%[phase,role,name])
	var path:=handoff.path_join("go-%s-%s"%[phase,name])
	var go:bool=await until(func():return FileAccess.file_exists(path),BARRIER_WAIT)
	if not check(go,"runner released barrier '%s' (every role reached it)"%name):return false
	await settle()
	return not finished

# ---------------------------------------------------------------- entry

func read_secrets() -> bool:
	var data=JSON.parse_string(OS.get_environment("WX_TOKENS"))
	if not data is Dictionary:return false
	for who in ["alpha","beta","gamma"]:
		var t=data.get(who)
		if not t is String or (t as String).length()<12 or (t as String).length()>64:return false
		tokens[who]=t
	return true

func read_json(name:String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join(name)))

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=4 or not PHASE_ROLES.has(args[0]) or not args[2] in PHASE_ROLES[args[0]]:
		push_error("WX_FAIL usage: <live|restart> <port> <role> <handoff_dir>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	roles=PHASE_ROLES[phase]
	handoff=args[3]
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG[phase])))
	if not read_secrets():
		finish(false,"WX_TOKENS environment missing or invalid")
		return
	var room_key:=OS.get_environment("WX_ROOM_KEY")
	if room_key.length()<12:
		finish(false,"WX_ROOM_KEY environment missing")
		return
	var fx=read_json("fixture.json")
	if not fx is Dictionary or not fx.get("plots") is Dictionary or not PLOT_ORDER.all(func(n):return fx.plots.has(n)):
		finish(false,"handoff fixture.json missing or invalid")
		return
	fixture=fx
	if phase=="restart":
		var p=read_json("plan-restart.json")
		if not p is Dictionary or not p.get("plots") is Dictionary or not p.get("inventory") is Dictionary or not (p.get("time") is float or p.get("time") is int):
			finish(false,"handoff plan-restart.json (live result) missing or invalid")
			return
		plan=p
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=tokens[role]
	session.changed.connect(_on_changed)
	session.notice.connect(_on_notice)
	if not check(int(Session.PROTOCOL)==CONTRACT_PROTOCOL and int(SaveSchema.VERSION)==CONTRACT_SAVE,
		"Session.PROTOCOL %d / SaveSchema.VERSION %d == contract %d / %d"%[int(Session.PROTOCOL),int(SaveSchema.VERSION),CONTRACT_PROTOCOL,CONTRACT_SAVE]):return
	if not check(is_equal_approx(Weather.DAY_SECONDS,DAY) and Weather.CYCLE[2]=="rainy" and Weather.CYCLE[3]=="sunny" and is_equal_approx(float(World.CROPS.pumpkin.time),PUMPKIN_TIME),
		"weather calendar 1440 s/day, day 3 rainy, day 4 sunny; pumpkin 270 s"):return
	var port:=int(args[1])
	var address:="ws://127.0.0.1:%d"%port
	var err:=session.join(address,port,role,room_key)
	if not check(err==OK,"loopback WebSocket join to %s (err %d)"%[address,err]):return
	var joined:bool=await until(func():return not session.own_id.is_empty() and snap().get("players",{}).has(session.own_id),JOIN_WAIT)
	if not check(joined and peer_class()=="WebSocketMultiplayerPeer","registered over plain ws:// with protocol %d and the room key (peer %s)"%[Session.PROTOCOL,peer_class()]):return
	cover("transport_verified")
	if not check(session.own_id==hid(tokens[role]),"own id is the hashed profile token"):return
	var all_on:bool=await until(func():return online_max>=roles.size(),PEER_WAIT)
	if not check(all_on,"%d clients online together"%roles.size()):return
	if not check(str(snap().get("region_id",""))=="home","play happens in home"):return
	var ok:bool
	if phase=="live":ok=await live()
	else:ok=await restart()
	if finished or not ok:
		if not finished:finish(false,"phase stopped without a recorded failure")
		return
	if not check(home_snapshots>0 and violation.is_empty(),"%d snapshots: no raw token, no foreign inventory/receipts"%snapshots
		+("" if violation.is_empty() else " -- "+violation)):return
	cover("leak_free")
	finish(true,"")

func peer_class() -> String:
	var link:MultiplayerPeer=null
	if session!=null and session.is_inside_tree():link=session.multiplayer.multiplayer_peer
	if link is WebSocketMultiplayerPeer:return "WebSocketMultiplayerPeer"
	return "none" if link==null else link.get_class()

func finish(ok:bool,step:String) -> void:
	if finished:return
	finished=true
	if ok:print("WX_WS_PASS %s %s transport=ws checks=%d snapshots=%d"%[phase,role,checks,snapshots])
	else:push_error("WX_WS_FAIL %s %s transport=ws after %d checks: %s | t=%.3f | inv=%s | plots=%s | violation=%s"%[phase,role,checks,step,
		world_time(),inv_text(),JSON.stringify(plots_view()) if session!=null and not fixture.is_empty() else "{}",violation])
	if session!=null:session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

# ---------------------------------------------------------------- live

func live() -> bool:
	expect_inv=ints(SEED_INV[role])
	if not check(inv_ok(),"exact seeded backpack %s"%inv_text()):return false
	if not check(first_time>=SEED_TIME-0.001 and first_time<RAIN_END,"first snapshot at world %.3f: rainy day 3 (seeded %.0f)"%[first_time,SEED_TIME]):return false
	# ---- rain: own and other's exposed plots wet, roofed plot dry, growth == wet time
	var seen:bool=await until(func():return world_time()>=RAIN_END or (weather().raining and plots_problem(true)==""),RAIN_WAIT)
	var t:=world_time()
	if not check(seen and t<RAIN_END and weather().raining and int(weather().day)==3,
		"observed rain before midnight at world %.3f (day %d %s): %s"%[t,int(weather().day),str(weather().id),plots_problem(true)]):return false
	var view:=plots_view()
	var own:="a_crop" if role=="alpha" else "b_crop"
	var other:="b_crop" if role=="alpha" else "a_crop"
	if not check(view[own].wet and view[other].wet and view.a_soil.wet and view.b_soil.wet and view.a_mature.wet and not view.a_roof.wet,
		"%s sees own %s and other's %s wet, both unplanted soils wet, roofed plot dry"%[role,own,other]):return false
	if not check(absf(float(view[own].growth)-(t-SEED_TIME))<=GROWTH_TOL and float(view.a_roof.growth)==0.0 and float(view.a_mature.growth)==PUMPKIN_TIME,
		"growth == wet time %.3f; roofed 0; mature capped %d"%[t-SEED_TIME,int(PUMPKIN_TIME)]):return false
	if not check(credit_free() and inv_ok(),"rain grants no irrigation credit (chapter_one.watered false); backpack %s"%inv_text()):return false
	var show:=presentation()
	if not check(show.id=="rainy" and show.raining and show.icon=="calendar" and show.moving_drops==(not REDUCED_MOTION[role]),
		"presentation values from snapshot clock: %s (computed only, not rendered)"%JSON.stringify(show)):return false
	mark({"mark":"rain","time":t,"plots":view,"presentation":show})
	cover("rain_seen_own")
	cover("rain_seen_other")
	cover("roof_dry")
	var go:bool=await barrier("rain_seen")
	if not go:return false
	# ---- day-4 midnight: everything dry, growth only for wet time, mature kept
	var dried:bool=await until(func():return world_time()>=RAIN_END+MIDNIGHT_SETTLE and plots_problem(false)=="",MIDNIGHT_WAIT)
	t=world_time()
	if not check(dried and int(weather().day)==4 and str(weather().id)=="sunny",
		"after midnight (world %.3f, day %d %s) every plot dry: %s"%[t,int(weather().day),str(weather().id),plots_problem(false)]):return false
	var before:=plots_view()
	var t_before:=t
	await create_timer(STABLE_GAP).timeout
	await settle()
	var after:=plots_view()
	t=world_time()
	if not check(t>t_before and same_plots(before,after) and plots_problem(false)=="",
		"dry state stable while the clock runs (%.3f -> %.3f): exposed growth %.3f == rain window, mature %.0f not rotted"%[t_before,t,float(after.a_crop.growth),float(after.a_mature.growth)]):return false
	cover("midnight_dry")
	cover("mature_kept")
	show=presentation()
	if not check(show.id=="sunny" and not show.raining and not show.moving_drops and show.icon=="weather","presentation after midnight: %s"%JSON.stringify(show)):return false
	if not check(credit_free() and inv_ok() and t<DAY4_END,"no irrigation credit, backpack unchanged %s, still day 4"%inv_text()):return false
	cover("bags_unchanged")
	go=await barrier("dry_stable")
	if not go:return false
	if not check(plots_problem(false)=="","dry state unchanged at the final barrier"):return false
	mark({"mark":"final","time":world_time(),"plots":plots_view(),"inventory":ints(inventory()),"presentation":presentation()})
	return true

# ---------------------------------------------------------------- restart

func restart() -> bool:
	var saved:=float(plan.time)
	if not check(first_time>=saved-0.001 and first_time<saved+RESTART_DRIFT,"first snapshot time %.3f vs saved %.3f (no offline catch-up)"%[first_time,saved]):return false
	var w:=weather()
	if not check(str(w.id)=="sunny" and int(w.day)==4 and world_time()<DAY4_END,"still sunny day 4 after the normal restart (world %.3f)"%world_time()):return false
	if not check(same_plots(plots_view(),plan.plots) and plots_problem(false)=="","plots identical to the live final: %s"%JSON.stringify(plots_view())):return false
	if not check(credit_free(),"no irrigation credit after restart"):return false
	if role=="gamma":
		if not check(not plan.inventory.has("gamma"),"gamma never joined before (late joiner)"):return false
		expect_inv=ints(inventory())
		cover("late_join")
	else:
		expect_inv=ints(plan.inventory[role])
		if not check(inv_ok() and expect_inv==ints(SEED_INV[role]),"persisted own backpack %s == seeded"%inv_text()):return false
		cover("reconnect")
	var go:bool=await barrier("observed")
	if not go:return false
	if not check(same_plots(plots_view(),plan.plots) and inv_ok(),"plots and backpack unchanged at the final barrier"):return false
	mark({"mark":"final","time":world_time(),"first_time":first_time,"plots":plots_view(),"inventory":ints(inventory()),"presentation":presentation()})
	return true

# ---------------------------------------------------------------- fixture seed

func clear_cell(world,c:Vector2i) -> bool:
	if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c)!="":return false
	for layer in ["objects","ground","roofs","crops","forest"]:
		if world.state[layer].has(k(c)):return false
	return Vector2(c).distance_to(World.SPAWN)>3.0

## First naturally clear home row of PLOT_ORDER.size() cells with a clear border.
func find_row(world) -> Vector2i:
	var n:=PLOT_ORDER.size()
	for oy in range(30,56):
		for ox in range(3,70):
			var ok:=true
			for y in range(oy-1,oy+2):
				for x in range(ox-1,ox+n+1):
					if not clear_cell(world,Vector2i(x,y)):ok=false;break
				if not ok:break
			if ok:return Vector2i(ox,oy)
	return Vector2i(-1,-1)

func mine_cell() -> Vector2i:
	for y in range(8,50):
		for x in range(8,60):
			var c:=Vector2i(x,y)
			if World.land(c,MINE) and not REGIONS.water(c,MINE) and not REGIONS.protected(c,MINE) and c not in MINES.NODES:return c
	return Vector2i(-1,-1)

func seed_world(args:Array) -> void:
	if args.size()!=2 or not read_secrets():
		push_error("WX_SEED_FAIL usage: seed <world.json> with WX_TOKENS in the environment")
		quit(2)
		return
	var world:=World.new()
	world.save_path=args[1]
	# SEED clock + chapter
	world.state.time=SEED_TIME
	world.state.board=true
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=false
	# SEED inventories
	for who in ["alpha","beta"]:
		world.add_player(tokens[who],who)
		world.state.players[tokens[who]].inventory=(SEED_INV[who] as Dictionary).duplicate(true)
	# SEED plots + roof
	var origin:=find_row(world)
	var mine:=mine_cell()
	if origin.x<0 or mine.x<0:
		push_error("WX_SEED_FAIL no clear home row or mine_1 land cell")
		quit(1)
		return
	var cells:={}
	for i in PLOT_ORDER.size():
		var name:String=PLOT_ORDER[i]
		var spec:Dictionary=PLOTS[name]
		var c:=k(origin+Vector2i(i,0))
		cells[name]=c
		world.state.crops[c]={"kind":spec.kind,"growth":float(spec.growth),"wet":false,"owner":tokens[spec.owner],"remaining":1 if str(spec.kind)!="" else 0}
		if spec.roof:world.state.roofs[c]={"type":"roof","owner":tokens[spec.owner],"items":{}}
	# SEED mine_plot (indoor region layer)
	world.state.regions[MINE].crops[k(mine)]={"kind":"pumpkin","growth":0.0,"wet":false,"owner":tokens.alpha,"remaining":1}
	if not world.save():
		push_error("WX_SEED_FAIL save: "+str(world.save_error))
		quit(1)
		return
	var reloaded:=World.new()
	var ok:bool=reloaded.load_world(args[1]) and not reloaded.recovered_from_backup and int(reloaded.state.version)==SaveSchema.VERSION
	ok=ok and is_equal_approx(float(reloaded.state.time),SEED_TIME) and reloaded.state.chapter_one.watered==false and reloaded.state.chapter_one.shipped==true
	for name in PLOT_ORDER:
		var crop=reloaded.state.crops.get(cells[name])
		ok=ok and crop is Dictionary and crop.wet==false and str(crop.kind)==str(PLOTS[name].kind) and reloaded.state.roofs.has(cells[name])==bool(PLOTS[name].roof)
	ok=ok and reloaded.state.regions[MINE].crops.has(k(mine))
	for who in ["alpha","beta"]:
		ok=ok and ints(reloaded.state.players[tokens[who]].inventory)==ints(SEED_INV[who])
	if not ok:
		push_error("WX_SEED_FAIL seeded save did not reload through SaveSchema with the exact clock/plots/roof/mine plot/bags")
		quit(1)
		return
	var out:={"label":SEED_LABEL,"seeded":SEEDED,"seed_version":int(reloaded.state.version),"protocol":int(Session.PROTOCOL),
		"seed_time":SEED_TIME,"rain_end":RAIN_END,"day4_end":DAY4_END,"pumpkin_time":PUMPKIN_TIME,"plots":cells,"mine":k(mine),
		"plot_specs":PLOTS,"inventories":SEED_INV,"reduced_motion":REDUCED_MOTION}
	print("WX_FIXTURE "+JSON.stringify(out))
	quit(0)
