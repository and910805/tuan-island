extends SceneTree
## Real multi-process network regression of the chapter-4 Beimen cooperative
## salt pans (protocol 45 / save 26 / release 0.50-dev).
##
## SINGLE MACHINE, MULTIPLE PROCESSES: one SEPARATE dedicated Godot server
## process plus separate Godot client processes on the same computer, joined
## over plain loopback WebSocket (ws://127.0.0.1:<port>; NOT wss/TLS). This is
## NOT two physical machines, NOT cloud hosting, and there is NO adverse-network
## model (no loss/latency/drop injection). An extra ENet smoke phase joins the
## same save over ENet on 127.0.0.1.
## Every mutation goes client Session.perform -> request_action RPC ->
## dedicated server -> World.act. No client touches a World.
## salt_gate_give / salt_rake / salt_install / salt_uninstall / salt_auto_cfg /
## salt_order / salt_box_take are acknowledged by the correlated
## action_completed(sequence). salt_claim / salt_flood / salt_auto_toggle /
## build / withdraw / hoe / seed / water / transit are NOT in
## Session.CORRELATED_ACTIONS: their outcome is the requester's own notice plus
## the resulting snapshots (labelled "notice-observed").
##
## SEEDED NETWORK FIXTURE - NOT AN EARNED JOURNEY. The `seed` step is the ONLY
## direct state write (labelled, printed in SN_FIXTURE.seeded):
##   chapters        chapter 1 done, tea comparison done, flower chapter complete
##                   (garden complete) for every salted player
##   time            world time 4380 s (calendar day index 3, sunny; day 4 sunny)
##   salt_records    alpha/beta/delta/epsilon + 6 offline owners: letter, intro,
##                   raked 1 (hand-raked once; the gates are NOT yet repaired,
##                   which an earned journey could not produce - fixture only)
##   gates           gates 0/1 full, gate 2 plank 5/6 (last gap = 1 plank),
##                   givers {owner-0}
##   lots            lots 0..5 held by 6 OFFLINE seeded owners, lot 6 held by
##                   alpha, lot 7 free (raced over the network); with the race
##                   winner all 8 private lots are taken (7 seeded + 1 earned)
##   travel_book     beimen visited for every salted player
##   positions       alpha (22.5,30.2) at lot 6, beta/delta (11.0,28.5) at gate 2
##                   and the public pool, epsilon (44.5,23.5) at the apprentice
##                   station (epsilon stays OFFLINE until after the restart)
##   inventories     exact kits / planks / wood / seeds / fish (SEED_INV)
## gamma is NOT seeded: it joins fresh after the restart.
## Accelerated world time (live + restart servers only): the runner starts
## those two server processes with Godot's engine flag --time-scale N; clients
## run at the real clock and steer with |direction| <= 1/N so walking speed in
## real seconds is unchanged.
## Tokens come from SN_TOKENS and the room key from SN_ROOM_KEY (environment),
## never from the command line, and are never printed.
##
## Driven by work/salt/network/network_salt.py. Args after `--`:
##   seed <world.json>                                   -> SN_FIXTURE {json}
##   <live|restart|enet> <port> <role> <handoff_dir> <time_scale>
## Barriers: client prints `SN_BARRIER <phase> <role> <name>` and waits for
## <handoff>/go-<phase>-<name>. Missing barrier/result = failure, never a skip.
## Output: SN_CHECK ok ..., SN_COVER <tag> <phase> <role>, SN_MARK {json},
## SN_WS_PASS / SN_WS_FAIL (transport=ws|enet).

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")

const CONTRACT_PROTOCOL:=45
const CONTRACT_SAVE:=26
const SEED_LABEL:="SEEDED NETWORK FIXTURE (game/tests/network_salt.gd seed) - not an earned journey"
const SEEDED:=["chapters","time","salt_records","gates","lots","travel_book","positions","inventories"]
const SEED_TIME:=4380.0
const OWNER_COUNT:=6
const A_LOT:=6
const RACE_LOT:=7
const GATE:=2
const GATE_SEED:={"plank":5,"resin":1,"stone":4}
const GATE_CELL:=Vector2i(9,28)
const POOL_PAN:=16
const POOL_CELL:=Vector2i(13,28)
const GATE_STAND:=Vector2(11.0,28.5)
const L7_STAND:=Vector2(33.5,30.5)
const L7_CELL:=Vector2i(34,29)
const A_STAND:=Vector2(22.5,30.2)
const A_WHEEL:=Vector2i(22,28)
const A_RAKE:=Vector2i(25,30)
const A_CHEST:=Vector2i(24,30)
const A_PANS:=[12,13]
const E_STAND:=Vector2(44.5,23.5)
const E_CLAIM:=Vector2i(44,22)
const E_WHEEL:=Vector2i(42,21)
const E_RAKE:=Vector2i(45,23)
const BUS_STAND:=Vector2(46.8,25.5)
const HOME_STAND:=Vector2(45.5,30.5)
const HOME_FERRY:=Vector2i(47,30)
const XIAOLI:=Vector2i(43,29)
const CAP:=60
const START:={"alpha":A_STAND,"beta":GATE_STAND,"delta":GATE_STAND,"epsilon":E_STAND}
const SALTED:=["alpha","beta","delta","epsilon"]
const SEED_INV:={
	"alpha":{"salt_wheel_kit":1,"salt_rake_kit":1,"wood":20,"salt_grilled_fish":2},
	"beta":{"plank":3,"radish_seed":2},
	"delta":{"plank":2},
	"epsilon":{"salt_wheel_kit":1,"salt_rake_kit":1},
}
const SEED_COINS:={"alpha":100,"beta":100,"delta":100,"epsilon":100}
const MSG_GATE_FULL:="這道閘門已經不缺這項材料。"
const MSG_GATE_REPAIRED:="三道閘門都修好了"
const MSG_ORDER_EARLY:="先讓自己的收鹽台自動收一次鹽，再來交委託。"
const MSG_BOX_EMPTY_PREFIX:="合作社收鹽箱裡沒有你的"
const PHASE_ROLES:={"live":["alpha","beta","delta"],"restart":["alpha","beta","gamma","epsilon"],"enet":["epsilon"]}
const WATCHDOG:={"live":140.0,"restart":130.0,"enet":25.0}
const JOIN_WAIT:=20.0
const RESULT_WAIT:=10.0
const PEER_WAIT:=20.0
const BARRIER_WAIT:=150.0
const WALK_WAIT:=25.0
const ACTION_BUDGET:=9
const ACTION_WINDOW_MSEC:=1100
## Real seconds to wait for one sunny crystallisation (480 world s) at scale N,
## plus slack.
const SALT_SLACK:=40.0

var session:Session
var island:Node
var phase:=""
var role:=""
var roles:Array=[]
var tokens:={}
var owner_tokens:Array=[]
var handoff:=""
var scale:=1.0
var transport:="ws"
var port:=0
var room_key:=""
var plan:Dictionary={}
var fixture:Dictionary={}
var notices:Array=[]
var sent:Dictionary={}
var completed:Dictionary={}
var sends:Array=[]
var snapshots:=0
var online_max:=0
var online_now:=0
var violation:=""
var checks:=0
var finished:=false
var expect_inv:Dictionary={}
var expect_coins:=0

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

static func plus(a:Dictionary,b:Dictionary,direction:int=1) -> Dictionary:
	var out:=ints(a)
	for item in b:
		out[str(item)]=int(out.get(str(item),0))+direction*int(b[item])
		if int(out[str(item)])==0:out.erase(str(item))
	return out

## Canonical JSON (numbers become floats on both sides, keys sorted).
static func norm(v:Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)),"",true)

static func plain(v:Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))

func snap() -> Dictionary:
	return session.snapshot if session!=null else {}

func me() -> Dictionary:
	if session==null:return {}
	var p=snap().get("players",{}).get(session.own_id,{})
	return p if p is Dictionary else {}

func inventory() -> Dictionary:
	var inv=me().get("inventory",{})
	return inv if inv is Dictionary else {}

func coins() -> int:
	return int(me().get("coins",-1))

func inv_text() -> String:
	return JSON.stringify(ints(inventory()))+" coins=%d"%coins() if session!=null else "{}"

func inv_ok() -> bool:
	return ints(inventory())==expect_inv and coins()==expect_coins

func region() -> String:
	return str(snap().get("region_id",""))

func epoch() -> int:
	return int(me().get("travel_epoch",-1))

func pos() -> Vector2:
	return Vector2(float(me().get("x",-1)),float(me().get("y",-1)))

func now() -> float:
	return float(snap().get("time",-1.0))

func salt() -> Dictionary:
	var s=snap().get("salt_pan",{})
	return s if s is Dictionary else {}

func own() -> Dictionary:
	var o=salt().get("own",{})
	return o if o is Dictionary else {}

func record() -> Dictionary:
	var r=own().get("record",{})
	return r if r is Dictionary else {}

func pan(i:int) -> Dictionary:
	var pans=salt().get("pans",[])
	if not pans is Array or i<0 or i>=pans.size() or not pans[i] is Dictionary:return {}
	return {"s":str(pans[i].get("s","")),"p":float(pans[i].get("p",-1)),"t":float(pans[i].get("t",-1)),"f":str(pans[i].get("f",""))}

func lot(i:int) -> Dictionary:
	var lots=salt().get("lots",[])
	if not lots is Array or i<0 or i>=lots.size() or not lots[i] is Dictionary:return {}
	return lots[i]

func gates() -> Array:
	var g=salt().get("gates",[])
	return plain(g) if g is Array else []

func gate_plank() -> int:
	var g:=gates()
	return int(g[GATE].get("plank",-1)) if g.size()>GATE else -1

func chest_salt(cell:Vector2i) -> int:
	var obj=snap().get("objects",{}).get(k(cell))
	if not obj is Dictionary:return -1
	return int(obj.get("items",{}).get("sea_salt",0))

## Own salt view minus clock-dependent text (minutes, status wording).
func own_core() -> Dictionary:
	var o:=own()
	var unit=o.get("unit",{})
	var u:={}
	if unit is Dictionary:
		for f in ["kind","index","wheel","rake","chest","cap","on"]:u[f]=unit.get(f)
	return {"record":plain(o.get("record",{})),"phase":o.get("phase"),"lot":o.get("lot"),"unit":u,"coop_box":o.get("coop_box"),"free_lots":o.get("free_lots")}

## Shared salt view that a restart must leave untouched.
func public_core() -> Dictionary:
	var s:=salt()
	var lots:Array=[]
	for i in Salt.LOT_COUNT:
		var l:=lot(i)
		lots.append({"taken":l.get("taken"),"wheel":l.get("wheel"),"rake":l.get("rake"),"active":l.get("active")})
	var pans:Array=[]
	for i in Salt.PAN_COUNT:pans.append(pan(i))
	var app=s.get("apprentice",{})
	return {"gates":gates(),"repaired":s.get("repaired"),"giver_count":s.get("giver_count"),"lots":lots,"pans":pans,
		"apprentice_taken":app.get("taken") if app is Dictionary else null}

## Everything a refused request must leave untouched. Pans/lots are excluded:
## other clients' machines legitimately change them concurrently.
func probe_state() -> String:
	return norm({"inv":ints(inventory()),"coins":coins(),"own":own_core(),"gates":gates(),"region":region(),"epoch":epoch()})

# ---------------------------------------------------------------- signals

func flag(text:String) -> void:
	if violation.is_empty():violation=text

func all_tokens() -> Array:
	return tokens.values()+owner_tokens

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
	var text:=var_to_str(data)+"|"+id
	for t in all_tokens():
		if text.contains(str(t)):flag("snapshot %d contains a raw profile token"%snapshots)
	var pop=data.get("region_population",{})
	var n:=0
	if pop is Dictionary:
		for r in pop:n+=int(pop[r])
	online_now=n
	online_max=maxi(online_max,n)
	var players=data.get("players",{})
	if players is Dictionary:
		for pid in players:
			var person=players[pid]
			if person is Dictionary and str(pid)!=id:
				for field in ["inventory","coins","receipts","travel_book"]:
					if person.has(field):flag("snapshot %d shows another player's %s"%[snapshots,field])
	var s=data.get("salt_pan")
	if not s is Dictionary:
		flag("snapshot %d has no salt_pan projection"%snapshots)
		return
	for field in ["players","givers","coop_box","kit_box","waitlist","repaired_at"]:
		if s.has(field):flag("snapshot %d salt_pan carries server-only '%s'"%[snapshots,field])
	var o=s.get("own")
	if not o is Dictionary or not o.get("record") is Dictionary or not o.has("lot") or not o.get("unit") is Dictionary or not o.get("apprentice") is Dictionary:
		flag("snapshot %d salt_pan.own missing record/lot/unit/apprentice"%snapshots)
		return
	var lots=s.get("lots")
	if not lots is Array or lots.size()!=Salt.LOT_COUNT:
		flag("snapshot %d salt_pan.lots is not %d entries"%[snapshots,Salt.LOT_COUNT])
		return
	for i in lots.size():
		var l=lots[i]
		if not l is Dictionary:
			flag("snapshot %d lot %d not a dictionary"%[snapshots,i])
			continue
		for field in l:
			if not str(field) in ["taken","wheel","rake","active","mine"]:flag("snapshot %d lot %d exposes '%s' (owner/chest/cap/on must stay private)"%[snapshots,i,str(field)])
		if (l.get("mine")==true)!=(i==int(o.get("lot",-1))):flag("snapshot %d lot %d mine=%s but own lot is %d"%[snapshots,i,str(l.get("mine")),int(o.get("lot",-1))])
	var app=s.get("apprentice")
	if not app is Dictionary or (app.get("mine")==true)!=(o.apprentice.get("mine")==true):flag("snapshot %d apprentice.mine does not match own shift"%snapshots)
	if app is Dictionary:
		for field in app:
			if str(field) in ["tenant","since","cap","on","owner"]:flag("snapshot %d apprentice exposes '%s'"%[snapshots,str(field)])
	var objects=data.get("objects",{})
	if objects is Dictionary:
		for cell in objects:
			var obj=objects[cell]
			if obj is Dictionary and str(obj.get("type",""))=="private_chest" and str(obj.get("owner",""))!=id:
				if not (obj.get("items",{}) as Dictionary).is_empty() or obj.has("box_id"):flag("snapshot %d shows another owner's private chest %s contents/box id"%[snapshots,str(cell)])

func _on_notice(message:String,ok:bool) -> void:
	notices.append({"ok":ok,"message":message})
	for t in all_tokens():
		if message.contains(str(t)):flag("notice contains a raw profile token")
	print("SN_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func _on_completed(sequence:int,action:String,result:Dictionary) -> void:
	var text:=var_to_str(result)
	for t in all_tokens():
		if text.contains(str(t)):flag("action result contains a raw profile token")
	if not sent.has(sequence):flag("completion for unsent/replayed sequence %d (%s)"%[sequence,action])
	elif completed.has(sequence):flag("duplicate completion for sequence %d"%sequence)
	completed[sequence]={"action":action,"result":result}
	print("SN_DONE %s %s seq=%d action=%s ok=%s"%[phase,role,sequence,action,str(result.get("ok"))])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("SN_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("SN_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	data["phase"]=phase
	data["role"]=role
	print("SN_MARK "+JSON.stringify(data))

func until(predicate:Callable,seconds:float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if finished:return false
		if predicate.call():return true
		await create_timer(0.05).timeout
	return not finished and predicate.call()

func settle() -> void:
	if session==null:return
	var seen:=snapshots
	await until(func():return snapshots>=seen+2,RESULT_WAIT)

func barrier(name:String,quiet:bool=false) -> bool:
	if finished:return false
	print("SN_BARRIER %s %s %s"%[phase,role,name])
	var path:=handoff.path_join("go-%s-%s"%[phase,name])
	var go:bool=await until(func():return FileAccess.file_exists(path),BARRIER_WAIT)
	if not check(go,"runner released barrier '%s' (every role reached it)"%name):return false
	if not quiet:await settle()
	return not finished

func pace() -> void:
	while not finished:
		var now_ms:=Time.get_ticks_msec()
		while not sends.is_empty() and now_ms-int(sends[0])>ACTION_WINDOW_MSEC:sends.pop_front()
		if sends.size()+1<=ACTION_BUDGET:break
		await create_timer(0.05).timeout
	sends.append(Time.get_ticks_msec())

## Correlated action through Session.perform; waits for action_completed with
## EXACTLY this sequence. Returns the result plus "_seq".
func act(action:String,p:Vector2i,extra:String="") -> Dictionary:
	if not action in Session.CORRELATED_ACTIONS:return {"ok":false,"message":"<%s is not correlated>"%action,"timeout":true}
	await pace()
	var seq:int=session.perform(action,p,extra)
	if seq<=0:return {"ok":false,"message":"<perform refused locally>","timeout":true}
	sent[seq]=action
	var got:bool=await until(func():return completed.has(seq),RESULT_WAIT)
	if not got:return {"ok":false,"message":"<no correlated completion for sequence %d>"%seq,"timeout":true}
	var entry:Dictionary=completed[seq]
	if not check(str(entry.action)==action,"sequence %d acknowledged as '%s'"%[seq,action]):return {"ok":false,"timeout":true}
	await settle()
	var r:Dictionary=(entry.result as Dictionary).duplicate(true)
	r["_seq"]=seq
	return r

## NOT correlated: wait for this requester's next notice (the server notices
## only the actor) and then settle snapshots.
func act_notice(action:String,p:Vector2i,extra:String="") -> Dictionary:
	await pace()
	var before:=notices.size()
	var seq:int=session.perform(action,p,extra)
	if seq<=0:return {"ok":false,"message":"<perform refused locally>","timeout":true}
	sent[seq]=action
	var got:bool=await until(func():return notices.size()>before,RESULT_WAIT)
	if not got:return {"ok":false,"message":"<no notice for %s seq %d>"%[action,seq],"timeout":true}
	await settle()
	var n:Dictionary=notices[before]
	return {"ok":n.ok,"message":str(n.message),"_seq":seq,"notices":notices.size()-before}

func done(label:String,r:Dictionary) -> bool:
	return check(not r.has("timeout") and r.get("ok")==true,"%s: \"%s\""%[label,str(r.get("message",""))])

func refused(label:String,action:String,p:Vector2i,extra:String,message:String,correlated:bool,prefix:bool=false) -> bool:
	var before:=probe_state()
	var r:Dictionary
	if correlated:r=await act(action,p,extra)
	else:r=await act_notice(action,p,extra)
	var got:=str(r.get("message",""))
	var same:bool=got.begins_with(message) if prefix else got==message
	if not check(not r.has("timeout") and r.get("ok")==false and same,
		"%s: %s refusal '%s' (got '%s')"%[label,"acknowledged" if correlated else "notice-observed",message,got]):return false
	return check(inv_ok() and probe_state()==before,"%s: no debit/credit, salt record/public salt state/region unchanged (%s)"%[label,inv_text()])

## Real movement through Session.input_direction (movement RPC). The server may
## run with --time-scale N, so |direction| is capped at 1/N (same real speed).
func walk(points:Array) -> bool:
	var cap:=1.0/maxf(scale,1.0)
	for target in points:
		var arrived:=false
		var deadline:=Time.get_ticks_msec()+int(WALK_WAIT*1000)
		while Time.get_ticks_msec()<deadline and not finished:
			var d:Vector2=(target as Vector2)-pos()
			if d.length()<0.12:
				arrived=true
				break
			var f:=clampf(d.length()/1.2,0.12,1.0)
			session.input_direction(d.normalized()*f*cap)
			await create_timer(0.05).timeout
		session.input_direction(Vector2.ZERO)
		if not check(arrived,"walked over the movement RPC to %s (at %s)"%[str(target),str(pos())]):return false
	await create_timer(0.3).timeout
	await settle()
	return not finished

func reach(cell:Vector2i) -> float:
	return pos().distance_to(Vector2(cell)+Vector2(0.5,0.5))

# ---------------------------------------------------------------- entry

func read_secrets() -> bool:
	var data=JSON.parse_string(OS.get_environment("SN_TOKENS"))
	if not data is Dictionary:return false
	for who in ["alpha","beta","gamma","delta","epsilon"]:
		var t=data.get(who)
		if not t is String or (t as String).length()<12 or (t as String).length()>64:return false
		tokens[who]=t
	var owners=data.get("owners")
	if not owners is Array or owners.size()!=OWNER_COUNT:return false
	for t in owners:
		if not t is String or (t as String).length()<12 or (t as String).length()>64:return false
		owner_tokens.append(t)
	return true

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=5 or not PHASE_ROLES.has(args[0]) or not args[2] in PHASE_ROLES[args[0]]:
		push_error("SN_FAIL usage: <live|restart|enet> <port> <role> <handoff_dir> <time_scale>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	roles=PHASE_ROLES[phase]
	handoff=args[3]
	scale=maxf(1.0,float(args[4]))
	transport="enet" if phase=="enet" else "ws"
	port=int(args[1])
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG[phase])))
	if not read_secrets():
		finish(false,"SN_TOKENS environment missing or invalid")
		return
	room_key=OS.get_environment("SN_ROOM_KEY")
	if room_key.length()<12:
		finish(false,"SN_ROOM_KEY environment missing")
		return
	var fx=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("fixture.json")))
	if not fx is Dictionary or not fx.get("farm") is Array:
		finish(false,"handoff fixture.json (seed output) missing or invalid")
		return
	fixture=fx
	if phase!="live" and not read_plan():
		finish(false,"handoff plan-%s.json (previous phase final state) missing or invalid"%phase)
		return
	if not check(int(Session.PROTOCOL)==CONTRACT_PROTOCOL and int(SaveSchema.VERSION)==CONTRACT_SAVE,
		"Session.PROTOCOL %d / SaveSchema.VERSION %d == contract %d / %d"%[int(Session.PROTOCOL),int(SaveSchema.VERSION),CONTRACT_PROTOCOL,CONTRACT_SAVE]):return
	var corr:=true
	for a in ["salt_gate_give","salt_rake","salt_install","salt_auto_cfg","salt_order","salt_box_take"]:
		if not a in Session.CORRELATED_ACTIONS:corr=false
	if not check(corr,"salt_gate_give/salt_rake/salt_install/salt_auto_cfg/salt_order/salt_box_take are correlated (acknowledged by sequence)"):return
	if not await connect_world():return
	cover("transport_verified")
	if phase!="enet":
		var all_on:bool=await until(func():return online_max>=roles.size(),PEER_WAIT)
		if not check(all_on,"%d clients online together (single machine, %d processes + dedicated server)"%[roles.size(),roles.size()]):return
	await settle()
	var ok:bool
	if phase=="live":ok=await live()
	elif phase=="restart":ok=await restart()
	else:ok=await enet()
	if finished or not ok:
		if not finished:finish(false,"phase stopped without a recorded failure")
		return
	if not check(snapshots>0 and violation.is_empty(),"%d snapshots: no raw token, no foreign inventory/coins, salt_pan without players/givers/coop_box/kit_box/waitlist, lots without owner/chest/cap, mine only on own lot/shift, foreign private chests empty"%snapshots
		+("" if violation.is_empty() else " -- "+violation)):return
	cover("leak_free")
	finish(true,"")

## New Session node + join (ws:// or ENet) + wait for registration.
func connect_world() -> bool:
	island=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=tokens[role]
	session.changed.connect(_on_changed)
	session.notice.connect(_on_notice)
	session.action_completed.connect(_on_completed)
	var address:="ws://127.0.0.1:%d"%port if transport=="ws" else "127.0.0.1"
	var err:=session.join(address,port,role,room_key)
	if not check(err==OK,"loopback %s join to %s (err %d)"%[transport,address if transport=="ws" else "enet://127.0.0.1:%d"%port,err]):return false
	var joined:bool=await until(func():return not session.own_id.is_empty() and snap().get("players",{}).has(session.own_id),JOIN_WAIT)
	var want:="WebSocketMultiplayerPeer" if transport=="ws" else "ENetMultiplayerPeer"
	if not check(joined and peer_class()==want,"registered over %s with protocol %d and the room key (peer %s)"%[transport,Session.PROTOCOL,peer_class()]):return false
	if not check(session.own_id==hid(tokens[role]),"own id is the hashed profile token"):return false
	return true

func disconnect_world() -> void:
	if session!=null:
		session.input_direction(Vector2.ZERO)
		session.shutdown()
	for _frame in 6:await process_frame
	if island!=null:island.queue_free()
	for _frame in 4:await process_frame
	session=null
	island=null

func peer_class() -> String:
	var link:MultiplayerPeer=null
	if session!=null and session.is_inside_tree():link=session.multiplayer.multiplayer_peer
	if link is WebSocketMultiplayerPeer:return "WebSocketMultiplayerPeer"
	if link is ENetMultiplayerPeer:return "ENetMultiplayerPeer"
	return "none" if link==null else link.get_class()

func finish(ok:bool,step:String) -> void:
	if finished:return
	finished=true
	if ok:print("SN_WS_PASS %s %s transport=%s checks=%d snapshots=%d notices=%d completions=%d"%[phase,role,transport,checks,snapshots,notices.size(),completed.size()])
	else:push_error("SN_WS_FAIL %s %s transport=%s after %d checks: %s | inv=%s | own=%s | violation=%s"%[phase,role,transport,checks,step,
		inv_text(),JSON.stringify(own_core()) if session!=null else "{}",violation])
	if session!=null:
		if session.multiplayer.multiplayer_peer!=null and not session.shutting_down:session.input_direction(Vector2.ZERO)
		session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

func final_mark(extra:Dictionary={}) -> void:
	var p:=pos()
	var data:={"mark":"final","inventory":ints(inventory()),"coins":coins(),"own":own_core(),"public":public_core(),
		"region":region(),"epoch":epoch(),"x":p.x,"y":p.y,"time":now()}
	data.merge(extra)
	mark(data)

func read_plan() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("plan-%s.json"%phase)))
	if not data is Dictionary:return false
	plan=data
	return true

# ---------------------------------------------------------------- live

func live() -> bool:
	expect_inv=ints(SEED_INV[role])
	expect_coins=int(SEED_COINS[role])
	if not check(region()==Salt.REGION,"seeded region: %s plays in beimen (region_id %s)"%[role,region()]):return false
	if not check(inv_ok(),"exact seeded backpack + coins %s"%inv_text()):return false
	if not check(pos().distance_to(START[role])<0.05,"seeded stand %s (at %s)"%[str(START[role]),str(pos())]):return false
	var r:=record()
	if not check(r.get("letter")==true and r.get("intro")==true and int(r.get("raked",-1))==1 and int(r.get("auto_raked",-1))==0,"own seeded salt record letter/intro/raked 1: %s"%JSON.stringify(r)):return false
	var s:=salt()
	var g:=gates()
	if not check(s.get("repaired")==false and g.size()==3 and norm(g[GATE])==norm(GATE_SEED) and norm(g[0])==norm(Salt.GATE_NEEDS_EACH) and norm(g[1])==norm(Salt.GATE_NEEDS_EACH),
		"gates seeded: 0/1 full, gate 2 %s (last gap 1 plank), not repaired"%JSON.stringify(g[GATE] if g.size()>GATE else {})):return false
	var taken:=0
	for i in Salt.LOT_COUNT:
		if lot(i).get("taken")==true:taken+=1
	if not check(taken==7 and lot(RACE_LOT).get("taken")==false and int(own().get("free_lots",-1))==1,"7 of 8 private lots taken (6 offline owners + alpha), lot 7 free"):return false
	if role=="alpha":
		if not check(int(own().get("lot",-1))==A_LOT and lot(A_LOT).get("mine")==true and str(own().get("phase",""))=="gates","alpha owns lot 6 (mine flag only there), phase gates (not yet repaired)"):return false
	else:
		if not check(int(own().get("lot",-2))==-1,"%s owns no lot"%role):return false
	mark({"mark":"seeded","own":own_core(),"public":public_core(),"inventory":ints(inventory()),"coins":coins(),"time":now()})
	cover("seeded_view")
	# ---- gate race: beta + delta give the last plank of gate 2 at once
	var go:bool=await barrier("start")
	if not go:return false
	go=await barrier("gate",true)
	if not go:return false
	if role in ["beta","delta"]:
		if not check(reach(GATE_CELL)<=3.2,"%s within reach of gate 2 (%.2f)"%[role,reach(GATE_CELL)]):return false
		var before:=int(inventory().get("plank",0))
		var res:Dictionary=await act("salt_gate_give",GATE_CELL,"plank")
		if not check(not res.has("timeout"),"salt_gate_give acknowledged by its sequence: \"%s\""%str(res.get("message",""))):return false
		var won:bool=res.get("ok")==true
		var taken_now:=before-int(inventory().get("plank",0))
		if won:
			if not check(taken_now==1 and str(res.message).contains(MSG_GATE_REPAIRED),"gate race won: exactly 1 plank taken, repair settled (\"%s\")"%str(res.message)):return false
			expect_inv=plus(expect_inv,{"plank":1},-1)
		else:
			if not check(str(res.get("message",""))==MSG_GATE_FULL and taken_now==0,"gate race lost: '%s' and nothing taken (got '%s')"%[MSG_GATE_FULL,str(res.get("message",""))]):return false
		if not check(inv_ok(),"backpack exact after the gate race %s"%inv_text()):return false
		mark({"mark":"gate_race","won":won,"taken":taken_now,"message":str(res.get("message","")),"seq":int(res._seq)})
		cover("gate_race")
	go=await barrier("gate_seen")
	if not go:return false
	var seen_gates:=gates()
	if not check(salt().get("repaired")==true and norm(seen_gates[GATE])==norm(Salt.GATE_NEEDS_EACH) and int(salt().get("giver_count",-1))>=2,
		"%s sees all three gates repaired exactly at the needs (gate 2 %s)"%[role,JSON.stringify(seen_gates[GATE])]):return false
	cover("gate_seen")
	# ---- delta floods the public pool; beta + delta race for lot 7
	if role=="delta":
		var fl:Dictionary=await act_notice("salt_flood",POOL_CELL,"")
		if not done("delta floods public pool pan 16 (notice-observed)",fl):return false
		if not check(pan(POOL_PAN).s=="brine" and pan(POOL_PAN).f=="hand","pool pan 16 is hand brine %s"%JSON.stringify(pan(POOL_PAN))):return false
	if role in ["beta","delta"]:
		if not await walk([Vector2(GATE_STAND.x,31.5),Vector2(L7_STAND.x,31.5),L7_STAND]):return false
	go=await barrier("claim",true)
	if not go:return false
	if role in ["beta","delta"]:
		var res:Dictionary=await act_notice("salt_claim",L7_CELL,"")
		if not check(not res.has("timeout"),"salt_claim notice-observed: \"%s\""%str(res.get("message",""))):return false
		var won:bool=res.get("ok")==true
		if won:
			if not check(int(own().get("lot",-1))==RACE_LOT and lot(RACE_LOT).get("mine")==true,"claim race won: own lot 7 (mine flag)"):return false
		else:
			if not check(str(res.get("message",""))==Salt.CLAIMED_MESSAGE and int(own().get("lot",-2))==-1 and lot(RACE_LOT).get("mine")==false,
				"claim race lost: '%s', no lot, mine false (got '%s')"%[Salt.CLAIMED_MESSAGE,str(res.get("message",""))]):return false
		mark({"mark":"claim_race","won":won,"message":str(res.get("message",""))})
		cover("claim_race")
	go=await barrier("claim_seen")
	if not go:return false
	if not check(lot(RACE_LOT).get("taken")==true and int(own().get("free_lots",-1))==0,"%s sees all 8 private lots taken"%role):return false
	# ---- beta goes home (real transit), delta back to the pool
	if role=="beta":
		if not await walk([Vector2(L7_STAND.x,31.5),Vector2(BUS_STAND.x,31.5),BUS_STAND]):return false
		var e0:=epoch()
		var tr:Dictionary=await act_notice("transit",Salt.TRANSFER,"home")
		var home_ok:bool=await until(func():return region()=="home",RESULT_WAIT)
		if not check(tr.get("ok")==true and home_ok and epoch()==e0+1,"transit beimen -> home at the salt bus stop: \"%s\" (region %s, epoch %d)"%[str(tr.get("message","")),region(),epoch()]):return false
		if not await walk([HOME_STAND]):return false
	elif role=="delta":
		if not await walk([Vector2(L7_STAND.x,31.5),Vector2(GATE_STAND.x,31.5),GATE_STAND]):return false
	# ---- concurrency: alpha sets up automation in beimen while beta farms at home
	go=await barrier("concurrent",true)
	if not go:return false
	if role=="alpha":
		if not await alpha_setup():return false
	elif role=="beta":
		if not await beta_farm():return false
	go=await barrier("armed")
	if not go:return false
	var watched:={}
	for i in A_PANS:watched[i]=pan(i)
	if not check(lot(A_LOT).get("wheel")==true and lot(A_LOT).get("rake")==true and lot(A_LOT).get("active")==true,"%s sees lot 6 wheel+rake active (public, no owner/chest/cap)"%role):return false
	for i in A_PANS:
		if not check(watched[i].s=="brine" and watched[i].f=="wheel","%s sees alpha's pan %d as wheel brine %s"%[role,i,JSON.stringify(watched[i])]):return false
	mark({"mark":"armed","pans":watched,"time":now()})
	# ---- alpha disconnects while its automation keeps running server-side
	if role=="alpha":
		var unit:Dictionary=own().get("unit",{})
		var eta:int=Salt.eta(watched[A_PANS[0]],now())
		if not check(unit.get("on")==true and eta>0,"armed and not yet crystallised (eta %d min) before disconnecting"%eta):return false
		mark({"mark":"pre_offline","chest":chest_salt(A_CHEST),"own":own_core(),"time":now(),"pans":watched})
		await disconnect_world()
		print("SN_OFFLINE %s alpha session shut down"%phase)
		cover("disconnect")
	elif role=="beta":
		var e1:=epoch()
		var tr:Dictionary=await act_notice("transit",HOME_FERRY,Salt.REGION)
		var back:bool=await until(func():return region()==Salt.REGION,RESULT_WAIT)
		if not check(tr.get("ok")==true and back and epoch()==e1+1 and pos().distance_to(Salt.ARRIVAL)<1.5,"transit home ferry -> beimen: \"%s\" (at %s)"%[str(tr.get("message","")),str(pos())]):return false
		if not await walk([BUS_STAND,Vector2(BUS_STAND.x,31.5),Vector2(GATE_STAND.x,31.5),GATE_STAND]):return false
	go=await barrier("offline",role=="alpha")
	if not go:return false
	if role!="alpha":
		if not check(online_now==2,"server reports 2 online (alpha disconnected): %d"%online_now):return false
		for i in A_PANS:
			if not check(norm(pan(i))==norm(watched[i]),"pan %d unchanged between arming and alpha's disconnect (no delivery while alpha was still online)"%i):return false
		# ---- pool race
		var ready:bool=await until(func():return pan(POOL_PAN).s=="salt",480.0/scale+SALT_SLACK)
		if not check(ready,"pool pan 16 crystallised on the server clock (%s)"%JSON.stringify(pan(POOL_PAN))):return false
	go=await barrier("pool",true)
	if not go:return false
	if role!="alpha":
		if not check(reach(POOL_CELL)<=3.2,"%s within reach of pool pan 16 (%.2f)"%[role,reach(POOL_CELL)]):return false
		var before:=int(inventory().get("sea_salt",0))
		var raked:=int(record().get("raked",-1))
		var res:Dictionary=await act("salt_rake",POOL_CELL,"")
		if not check(not res.has("timeout"),"salt_rake acknowledged by its sequence: \"%s\""%str(res.get("message",""))):return false
		var won:bool=res.get("ok")==true
		var got:=int(inventory().get("sea_salt",0))-before
		if won:
			if not check(got==Salt.YIELD and int(record().get("raked",-1))==raked+1,"pool race won: sea_salt +%d, raked %d"%[got,int(record().get("raked",-1))]):return false
			expect_inv=plus(expect_inv,{"sea_salt":Salt.YIELD})
		else:
			if not check(str(res.get("message",""))==Salt.RAKED_MESSAGE and got==0 and int(record().get("raked",-1))==raked,"pool race lost: '%s', nothing gained (got '%s')"%[Salt.RAKED_MESSAGE,str(res.get("message",""))]):return false
		if not check(inv_ok() and pan(POOL_PAN).s=="empty","backpack exact %s, pool pan empty"%inv_text()):return false
		mark({"mark":"pool_race","won":won,"gained":got,"message":str(res.get("message","")),"seq":int(res._seq)})
		cover("pool_race")
		# ---- alpha's automation delivers while alpha is offline
		var t0:float=float(watched[A_PANS[0]].t)
		var moved:bool=await until(func():return pan(A_PANS[0]).t>t0+1.0 and pan(A_PANS[1]).t>t0+1.0,480.0/scale+SALT_SLACK)
		if not check(moved and online_now==2,"alpha's pans changed while alpha is offline (online %d)"%online_now):return false
		await settle()
		for i in A_PANS:
			var p:=pan(i)
			if not check(p.s=="brine" and p.f=="wheel" and absf(p.t-(float(watched[i].t)+Salt.NEED))<0.001,
				"pan %d crystallised at t+480 (sunny), collected and refilled by the wheel server-side: %s"%[i,JSON.stringify(p)]):return false
		mark({"mark":"offline_progress","pans":{A_PANS[0]:pan(A_PANS[0]),A_PANS[1]:pan(A_PANS[1])}})
		cover("offline_progress")
	go=await barrier("auto_seen",role=="alpha")
	if not go:return false
	if role=="alpha":
		if not await connect_world():return false
		var all_back:bool=await until(func():return online_now>=3,PEER_WAIT)
		if not check(all_back,"alpha reconnected (3 online)"):return false
		await settle()
		var o:=own()
		var unit:Dictionary=o.get("unit",{})
		if not check(int(record().get("auto_raked",-1))==2 and str(o.get("phase",""))=="order" and int(o.get("lot",-1))==A_LOT and unit.get("on")==true and str(unit.get("chest",""))==k(A_CHEST) and int(unit.get("cap",-1))==CAP,
			"after reconnect: auto_raked 2, phase order, own lot 6 on with chest %s cap %d: %s"%[k(A_CHEST),CAP,JSON.stringify(own_core())]):return false
		if not check(chest_salt(A_CHEST)==2*Salt.YIELD,"own private chest holds the 2 offline deliveries: sea_salt %d"%chest_salt(A_CHEST)):return false
		if not check(inv_ok(),"reconnect snapshot backpack exact %s"%inv_text()):return false
		mark({"mark":"reconnected","pans":{A_PANS[0]:pan(A_PANS[0]),A_PANS[1]:pan(A_PANS[1])},"chest":chest_salt(A_CHEST),"own":own_core()})
		cover("reconnect_snapshot")
	go=await barrier("final")
	if not go:return false
	if not check(inv_ok() and salt().get("repaired")==true,"final: backpack exact, gates repaired"):return false
	var extra:={}
	if role=="alpha":extra={"chest":chest_salt(A_CHEST),"apans":{A_PANS[0]:pan(A_PANS[0]),A_PANS[1]:pan(A_PANS[1])}}
	final_mark(extra)
	return true

func alpha_setup() -> bool:
	if not check(reach(A_WHEEL)<=3.2 and reach(A_RAKE)<=3.2 and reach(A_CHEST)<=3.2,"alpha within reach of wheel/rake/chest sockets"):return false
	var r:Dictionary=await act("salt_install",A_WHEEL,"wheel")
	if not done("salt_install wheel acknowledged",r):return false
	expect_inv=plus(expect_inv,{"salt_wheel_kit":1},-1)
	var flooded:bool=await until(func():return pan(A_PANS[0]).s=="brine" and pan(A_PANS[1]).s=="brine",RESULT_WAIT)
	if not check(flooded and pan(A_PANS[0]).f=="wheel" and region_population("home")==1,"wheel floods both pans while beta is at home (concurrent): %s / %s, population %s"%[JSON.stringify(pan(A_PANS[0])),JSON.stringify(pan(A_PANS[1])),JSON.stringify(snap().get("region_population",{}))]):return false
	cover("concurrent_beimen")
	r=await act("salt_install",A_RAKE,"rake")
	if not done("salt_install rake acknowledged",r):return false
	expect_inv=plus(expect_inv,{"salt_rake_kit":1},-1)
	cover("install")
	r=await act_notice("build",A_CHEST,"private_chest")
	if not done("build private chest on the lot-6 chest socket (notice-observed)",r):return false
	expect_inv=plus(expect_inv,{"wood":20},-1)
	r=await act("salt_auto_cfg",A_RAKE,"%s|%d"%[k(A_CHEST),CAP])
	if not done("salt_auto_cfg %s|%d acknowledged"%[k(A_CHEST),CAP],r):return false
	if not check(str(own().get("unit",{}).get("chest",""))==k(A_CHEST) and int(own().get("unit",{}).get("cap",-1))==CAP,"own view shows chest %s cap %d"%[k(A_CHEST),CAP]):return false
	cover("auto_cfg")
	var bad:bool=await refused("auto_cfg with cap below 3","salt_auto_cfg",A_RAKE,"%s|2"%k(A_CHEST),Salt.CAP_MESSAGE,true)
	if not bad:return false
	r=await act_notice("salt_auto_toggle",A_RAKE,"")
	if not done("salt_auto_toggle on (notice-observed)",r):return false
	var unit:Dictionary=own().get("unit",{})
	if not check(unit.get("on")==true and str(unit.get("status",{}).get("id",""))=="waiting","own unit on, status waiting: %s"%JSON.stringify(unit.get("status",{}))):return false
	if not check(inv_ok() and chest_salt(A_CHEST)==0,"backpack exact %s, chest empty"%inv_text()):return false
	cover("armed")
	return true

func region_population(r:String) -> int:
	return int(snap().get("region_population",{}).get(r,-1))

func beta_farm() -> bool:
	var farm:=Vector2i(int(fixture.farm[0]),int(fixture.farm[1]))
	if not check(reach(farm)<=3.2 and reach(XIAOLI)<=3.2 and reach(HOME_FERRY)<=3.2,"beta at home within reach of farm %s, Xiaoli and ferry"%k(farm)):return false
	var r:Dictionary=await act_notice("hoe",farm,"")
	if not done("hoe at home (notice-observed)",r):return false
	r=await act_notice("seed",farm,"radish")
	if not done("seed radish at home (notice-observed)",r):return false
	expect_inv=plus(expect_inv,{"radish_seed":1},-1)
	r=await act_notice("water",farm,"")
	if not done("water at home (notice-observed)",r):return false
	var crop=snap().get("crops",{}).get(k(farm))
	if not check(crop is Dictionary and str(crop.get("kind",""))=="radish" and crop.get("wet")==true and region_population(Salt.REGION)==2,
		"home plot has a watered radish while alpha + delta are in beimen (population %s)"%JSON.stringify(snap().get("region_population",{}))):return false
	cover("concurrent_home_farm")
	if not await refused("salt_order before own automation","salt_order",XIAOLI,"",MSG_ORDER_EARLY,true):return false
	cover("order_refused")
	if not check(inv_ok(),"beta backpack exact after farming %s"%inv_text()):return false
	return true

# ---------------------------------------------------------------- restart

func restart() -> bool:
	var live:Dictionary=plan.get("live",{})
	if role=="gamma":
		if not check(not live.has("gamma"),"gamma never joined before (late joiner)"):return false
		expect_inv=ints(inventory())
		expect_coins=coins()
		var g:=gates()
		var full:=g.size()==3
		for gate in g:
			if norm(gate)!=norm(Salt.GATE_NEEDS_EACH):full=false
		if not check(salt().get("repaired")==true and full,"late joiner sees all three gates repaired: %s"%JSON.stringify(g)):return false
		var o:=own()
		var fresh:=true
		for f in Salt.RECORD:
			if norm(record().get(f))!=norm(Salt.RECORD[f]):fresh=false
		if not check(fresh and str(o.get("phase",""))=="locked" and int(o.get("lot",-2))==-1 and str(o.get("unit",{}).get("kind","x"))=="" and int(o.get("coop_box",-1))==0 and o.get("apprentice",{}).get("eligible")==false,
			"late joiner has their own blank salt progress (record %s, phase %s, no lot, no shift)"%[JSON.stringify(record()),str(o.get("phase",""))]):return false
		if not check(region()=="home","late joiner starts at home"):return false
		cover("late_join_blank")
	elif role=="epsilon":
		expect_inv=ints(SEED_INV.epsilon)
		expect_coins=int(SEED_COINS.epsilon)
		if not check(not live.has("epsilon") and inv_ok() and region()==Salt.REGION and pos().distance_to(E_STAND)<0.05,"seeded late joiner epsilon (first connection after restart) at the apprentice station, backpack exact %s"%inv_text()):return false
		var o:=own()
		if not check(int(o.get("free_lots",-1))==0 and o.get("apprentice",{}).get("eligible")==true and int(o.get("lot",-2))==-1,"all 8 private lots taken; epsilon (no lot, raked 1) is eligible for the apprentice shift"):return false
	else:
		var mine:Dictionary=live.get(role,{})
		expect_inv=ints(mine.get("inventory",{}))
		expect_coins=int(mine.get("coins",-1))
		if not check(inv_ok(),"persisted backpack + coins %s == live final"%inv_text()):return false
		if not check(norm(own_core())==norm(mine.get("own",{})),"persisted own salt view identical to live final"):return false
		if not check(region()==str(mine.region) and epoch()==int(mine.epoch) and pos().distance_to(Vector2(float(mine.x),float(mine.y)))<0.05,"persisted region %s, epoch %d, position %s"%[region(),epoch(),str(pos())]):return false
		cover("reconnect")
	var persisted:Dictionary=live.get("alpha",{}).get("public",{})
	if not check(norm(public_core())==norm(persisted),"%s sees exactly the live-final public salt state after the normal restart (gates, lots, all 20 pans s/p/t/f)"%role):return false
	if role=="alpha":
		var chest_live:=int(live.alpha.get("chest",-1))
		if not check(chest_salt(A_CHEST)==chest_live and chest_live==2*Salt.YIELD,"chest count after restart %d == live final %d"%[chest_salt(A_CHEST),chest_live]):return false
		cover("persisted_pans_chest")
	mark({"mark":"view_restarted","public":public_core(),"own":own_core(),"inventory":ints(inventory()),"coins":coins(),"region":region(),"time":now(),
		"chest":chest_salt(A_CHEST) if role=="alpha" else -1})
	var go:bool=await barrier("observed")
	if not go:return false
	if role=="alpha":
		if not await alpha_restart(persisted):return false
	elif role=="epsilon":
		if not await epsilon_shift():return false
	elif role=="beta":
		if not check(region()==Salt.REGION and reach(GATE_CELL)<=3.2,"beta at gate 2 after restart"):return false
		if not await refused("give to the persisted repaired gate","salt_gate_give",GATE_CELL,"plank",MSG_GATE_FULL,true):return false
		cover("gate_enforced")
	go=await barrier("final")
	if not go:return false
	if not check(inv_ok() and salt().get("repaired")==true,"end of restart: backpack exact, gates repaired"):return false
	final_mark({"chest":chest_salt(A_CHEST) if role=="alpha" and region()==Salt.REGION else -1})
	return true

func alpha_restart(persisted:Dictionary) -> bool:
	# Automation continues after the restart: the refilled pans crystallise at
	# t+480 and the collector delivers into the same chest.
	var p0:Dictionary=persisted.pans[A_PANS[0]]
	var t0:=float(p0.t)
	var left:=maxf(0.0,t0+Salt.NEED-now())/scale
	var moved:bool=await until(func():return pan(A_PANS[0]).t>t0+1.0 and pan(A_PANS[1]).t>t0+1.0,left+SALT_SLACK)
	if not check(moved,"alpha's automation delivered again after the restart (pans %s)"%JSON.stringify([pan(A_PANS[0]),pan(A_PANS[1])])):return false
	await settle()
	if not check(absf(pan(A_PANS[0]).t-(t0+Salt.NEED))<0.001 and pan(A_PANS[0]).f=="wheel" and chest_salt(A_CHEST)==4*Salt.YIELD and int(record().get("auto_raked",-1))==4,
		"after restart: pans refilled at t+480, chest %d (== 12), auto_raked %d"%[chest_salt(A_CHEST),int(record().get("auto_raked",-1))]):return false
	mark({"mark":"automation_continues","chest":chest_salt(A_CHEST),"pans":{A_PANS[0]:pan(A_PANS[0]),A_PANS[1]:pan(A_PANS[1])}})
	cover("automation_continues")
	# ---- withdraw 4 salt and deliver the order to Xiaoli at home
	for _i in Salt.ORDER.sea_salt:
		var w:Dictionary=await act_notice("withdraw",A_CHEST,"sea_salt")
		if not done("withdraw sea_salt from own private chest (notice-observed)",w):return false
	expect_inv=plus(expect_inv,{"sea_salt":int(Salt.ORDER.sea_salt)})
	if not check(inv_ok() and chest_salt(A_CHEST)==4*Salt.YIELD-int(Salt.ORDER.sea_salt),"backpack %s, chest %d"%[inv_text(),chest_salt(A_CHEST)]):return false
	if not await walk([Vector2(A_STAND.x,31.5),Vector2(BUS_STAND.x,31.5),BUS_STAND]):return false
	var tr:Dictionary=await act_notice("transit",Salt.TRANSFER,"home")
	var home_ok:bool=await until(func():return region()=="home",RESULT_WAIT)
	if not check(tr.get("ok")==true and home_ok,"alpha transits beimen -> home: \"%s\""%str(tr.get("message",""))):return false
	if not await walk([HOME_STAND]):return false
	var r:Dictionary=await act("salt_order",XIAOLI,"")
	if not done("salt_order acknowledged",r):return false
	expect_inv=plus(expect_inv,Salt.ORDER,-1)
	expect_coins+=int(Salt.ORDER_PAY)
	if not check(inv_ok() and record().get("order")==true and str(own().get("phase",""))=="report","order debited %s, coins +%d, phase report: %s"%[JSON.stringify(Salt.ORDER),int(Salt.ORDER_PAY),inv_text()]):return false
	cover("order")
	return true

func epsilon_shift() -> bool:
	if not check(reach(E_CLAIM)<=3.2 and reach(E_WHEEL)<=3.2 and reach(E_RAKE)<=3.2 and reach(Salt.APPRENTICE_CHEST)<=3.2,"epsilon within reach of the apprentice pans, sockets and cooperative chest"):return false
	var r:Dictionary=await act_notice("salt_claim",E_CLAIM,"")
	if not done("epsilon takes the apprentice shift (notice-observed)",r):return false
	if not check(own().get("apprentice",{}).get("mine")==true and salt().get("apprentice",{}).get("taken")==true and salt().get("apprentice",{}).get("mine")==true and str(own().get("unit",{}).get("kind",""))=="apprentice",
		"shift is epsilon's (apprentice.mine only for epsilon, unit apprentice)"):return false
	cover("apprentice_shift")
	r=await act("salt_install",E_WHEEL,"wheel")
	if not done("salt_install wheel at the apprentice station acknowledged",r):return false
	r=await act("salt_install",E_RAKE,"rake")
	if not done("salt_install rake at the apprentice station acknowledged",r):return false
	expect_inv=plus(expect_inv,{"salt_wheel_kit":1,"salt_rake_kit":1},-1)
	r=await act("salt_auto_cfg",E_RAKE,"%s|%d"%[k(Salt.APPRENTICE_CHEST),CAP])
	if not done("salt_auto_cfg cooperative chest acknowledged",r):return false
	r=await act_notice("salt_auto_toggle",E_RAKE,"")
	if not done("salt_auto_toggle on (notice-observed)",r):return false
	if not check(inv_ok() and pan(18).s=="brine" and pan(18).f=="wheel","kits installed (backpack %s), apprentice pans flooded by the wheel"%inv_text()):return false
	var t0:=float(pan(18).t)
	var delivered:bool=await until(func():return int(own().get("coop_box",0))>=Salt.YIELD,maxf(0.0,t0+Salt.NEED-now())/scale+SALT_SLACK)
	if not check(delivered,"automatic delivery into the cooperative chest over the network (coop_box %d)"%int(own().get("coop_box",-1))):return false
	await settle()
	var esc:Dictionary=own().get("apprentice",{}).get("kits",{})
	var back:int=int(inventory().get("salt_wheel_kit",0))+int(esc.get("salt_wheel_kit",0))
	var back_rake:int=int(inventory().get("salt_rake_kit",0))+int(esc.get("salt_rake_kit",0))
	if not check(int(own().get("coop_box",-1))==Salt.YIELD and int(record().get("auto_raked",-1))==1 and own().get("apprentice",{}).get("mine")==false and salt().get("apprentice",{}).get("taken")==false and back==1 and back_rake==1,
		"graduated after the first delivery: coop_box 3, auto_raked 1, shift ended, both kits returned (inventory %s, escrow %s)"%[inv_text(),JSON.stringify(esc)]):return false
	expect_inv=ints(inventory())
	cover("apprentice_delivery")
	r=await act("salt_box_take",Salt.APPRENTICE_CHEST,"")
	if not done("salt_box_take acknowledged",r):return false
	if not check(int(inventory().get("sea_salt",0))==Salt.YIELD and int(own().get("coop_box",-1))==0,"cooperative compartment moved into the backpack: sea_salt %d, coop_box %d"%[int(inventory().get("sea_salt",0)),int(own().get("coop_box",-1))]):return false
	expect_inv=ints(inventory())
	if not check(int(expect_inv.get("salt_wheel_kit",0))==1 and int(expect_inv.get("salt_rake_kit",0))==1,"both kits in the backpack after taking the compartment %s"%inv_text()):return false
	mark({"mark":"apprentice","inventory":expect_inv,"own":own_core()})
	cover("box_take")
	return true

# ---------------------------------------------------------------- enet smoke

func enet() -> bool:
	var last:Dictionary=plan.get("restart",{}).get("epsilon",{})
	expect_inv=ints(last.get("inventory",{}))
	expect_coins=int(last.get("coins",-1))
	if not check(inv_ok() and region()==Salt.REGION,"ENet snapshot: persisted backpack %s, region beimen"%inv_text()):return false
	if not check(salt().get("repaired")==true and int(record().get("auto_raked",-1))==1 and int(own().get("coop_box",-1))==0,"ENet snapshot carries the salt projection (repaired, own auto_raked 1, coop_box 0)"):return false
	if not await refused("ENet salt_box_take on an empty compartment","salt_box_take",Salt.APPRENTICE_CHEST,"",MSG_BOX_EMPTY_PREFIX,true,true):return false
	final_mark()
	cover("enet_smoke")
	return true

# ---------------------------------------------------------------- fixture seed

func flower_done(world:World,tok:String) -> void:
	var t:Dictionary=Tea.FRESH.duplicate(true)
	t.intro=true;t.potter=true;t.reused=true;t.reuse_count=1
	t.trials={"jar":true,"fiber":true};t.tea_discussed=true;t.comparison_complete=true
	world.state.tea_ceramics.players[tok]=t
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	world.state.flower_nursery.players[tok]=a
	var book:Dictionary=world.state.players[tok].travel_book
	for stop in ["maokong","yingge","tianwei","beimen"]:book.visited[stop]=true

func seed_world(args:Array) -> void:
	if args.size()!=2:
		push_error("SN_SEED_FAIL usage: seed <world.json>")
		quit(2)
		return
	if not read_secrets():
		push_error("SN_SEED_FAIL SN_TOKENS environment missing or invalid")
		quit(2)
		return
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	# SEED chapters: chapter 1 done (transit needs the picnic)
	world.state.board=true
	world.state.picnic_materials={"soup":2,"bread":1}
	world.state.picnic=true
	world.state.chapter_one={"shipped":true,"watered":true,"harvests":{},"starter_claims":{}}
	world.state.community={"table":"39,30"}
	# SEED time: day index 3 (sunny), day 4 sunny as well
	world.state.time=SEED_TIME
	var salted:Array=[]
	for who in SALTED:salted.append(tokens[who])
	salted.append_array(owner_tokens)
	var names:={}
	for who in SALTED:names[tokens[who]]=who
	for i in owner_tokens.size():names[owner_tokens[i]]="owner%d"%i
	for tok in salted:
		world.add_player(tok,str(names[tok]))
		flower_done(world,tok)
	world.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{tokens.alpha:6,tokens.beta:4},"complete":true,"completed_at":0.0}
	# SEED salt_records + gates + lots
	var sp:Dictionary=world.state.salt_pan
	for tok in salted:
		var rec:Dictionary=Salt.RECORD.duplicate(true)
		rec.letter=true;rec.intro=true;rec.raked=1
		sp.players[tok]=rec
	sp.gates[0]=Salt.GATE_NEEDS_EACH.duplicate(true)
	sp.gates[1]=Salt.GATE_NEEDS_EACH.duplicate(true)
	sp.gates[GATE]=GATE_SEED.duplicate(true)
	sp.givers={owner_tokens[0]:true}
	for i in OWNER_COUNT:sp.lots[i].owner=owner_tokens[i]
	sp.lots[A_LOT].owner=tokens.alpha
	# SEED positions + inventories (owners stay at home, offline)
	for who in SALTED:
		var person:Dictionary=world.state.players[tokens[who]]
		person.region=Salt.REGION
		person.travel_epoch=1
		person.x=START[who].x
		person.y=START[who].y
		person.inventory=(SEED_INV[who] as Dictionary).duplicate(true)
		person.coins=int(SEED_COINS[who])
	# geometry checks (reach 3.2 as in World._apply), walk paths
	world.switch_region(Salt.REGION)
	var reach_map:={"alpha":[A_WHEEL,A_RAKE,A_CHEST],"gate":[GATE_CELL,POOL_CELL],"l7":[L7_CELL],"epsilon":[E_CLAIM,E_WHEEL,E_RAKE,Salt.APPRENTICE_CHEST],"bus":[Salt.TRANSFER]}
	var spots:={"alpha":A_STAND,"gate":GATE_STAND,"l7":L7_STAND,"epsilon":E_STAND,"bus":BUS_STAND}
	for spot in spots:
		if not world.can_stand(spots[spot]):problems.append("cannot stand at %s %s"%[spot,str(spots[spot])])
		for c in reach_map[spot]:
			var d:float=(spots[spot] as Vector2).distance_to(Vector2(c)+Vector2(0.5,0.5))
			if d>3.2:problems.append("%s is %.2f from %s"%[spot,d,k(c)])
	var paths:=[[GATE_STAND,Vector2(GATE_STAND.x,31.5),Vector2(L7_STAND.x,31.5),L7_STAND],
		[L7_STAND,Vector2(L7_STAND.x,31.5),Vector2(BUS_STAND.x,31.5),BUS_STAND],
		[Salt.ARRIVAL,BUS_STAND,Vector2(BUS_STAND.x,31.5),Vector2(GATE_STAND.x,31.5),GATE_STAND],
		[A_STAND,Vector2(A_STAND.x,31.5),Vector2(BUS_STAND.x,31.5),BUS_STAND]]
	for path in paths:
		for i in range(1,path.size()):
			var a:Vector2=path[i-1]
			var b:Vector2=path[i]
			var n:=int(ceilf(a.distance_to(b)/0.1))
			for j in n+1:
				var q:Vector2=a.lerp(b,float(j)/float(maxi(n,1)))
				if not world.can_stand(q):
					problems.append("beimen walk blocked at %s"%str(q))
					break
	world.switch_region("home")
	if not world.can_stand(HOME_STAND):problems.append("cannot stand at home %s"%str(HOME_STAND))
	var arrival_home:=Vector2(46.5,30.5)
	var n2:=int(ceilf(arrival_home.distance_to(HOME_STAND)/0.1))
	for j in n2+1:
		if not world.can_stand(arrival_home.lerp(HOME_STAND,float(j)/float(n2))):problems.append("home walk blocked")
	for c in [XIAOLI,HOME_FERRY]:
		if HOME_STAND.distance_to(Vector2(c)+Vector2(0.5,0.5))>3.2:problems.append("home stand too far from %s"%k(c))
	# a hoe-able home cell within reach of HOME_STAND
	var farm:=Vector2i(-1,-1)
	for y in range(28,34):
		for x in range(43,50):
			var c:=Vector2i(x,y)
			if c==Vector2i(HOME_STAND) or HOME_STAND.distance_to(Vector2(c)+Vector2(0.5,0.5))>2.9:continue
			var tile:=k(c)
			if world.water(c) or world.protected(c) or world.resource(c)!="" or world.blocked(c):continue
			var busy:=false
			for layer in ["objects","ground","roofs","crops","forest"]:
				if world.state[layer].has(tile):busy=true
			if busy:continue
			farm=c
			break
		if farm.x>=0:break
	if farm.x<0:problems.append("no hoe-able home cell near %s"%str(HOME_STAND))
	if not world.can_stand(World.SPAWN):problems.append("late joiner spawn blocked")
	if not problems.is_empty():
		for problem in problems:push_error("SN_SEED_FAIL "+problem)
		quit(1)
		return
	if not world.save():
		push_error("SN_SEED_FAIL save: "+str(world.save_error))
		quit(1)
		return
	var reloaded:=World.new()
	var loaded:bool=reloaded.load_world(args[1])
	var ok:bool=loaded and not reloaded.recovered_from_backup and int(reloaded.state.version)==SaveSchema.VERSION and int(SaveSchema.VERSION)==CONTRACT_SAVE
	var phases:={}
	if ok:
		for who in SALTED:
			var tok:String=tokens[who]
			ok=ok and ints(reloaded.state.players[tok].inventory)==ints(SEED_INV[who]) and int(reloaded.state.players[tok].coins)==int(SEED_COINS[who])
			ok=ok and reloaded.player_region(tok)==Salt.REGION
			phases[who]=Salt.phase(reloaded.state,tok)
		ok=ok and not Salt.repaired(reloaded.state) and Salt.free_lots(reloaded.state)==1 and is_equal_approx(float(reloaded.state.time),SEED_TIME)
		ok=ok and Salt.WEATHER.outdoor_id(Salt.WEATHER.day_index(SEED_TIME))=="sunny" and Salt.WEATHER.outdoor_id(Salt.WEATHER.day_index(SEED_TIME)+1.0)=="sunny"
	if not ok:
		push_error("SN_SEED_FAIL seeded save did not reload through SaveSchema as the salt fixture (loaded=%s)"%str(loaded))
		quit(1)
		return
	var out:={"label":SEED_LABEL,"seeded":SEEDED,"seed_version":int(reloaded.state.version),"protocol":int(Session.PROTOCOL),
		"inventories":SEED_INV,"coins":SEED_COINS,"gate_seed":GATE_SEED,"gate":GATE,"time":SEED_TIME,"owners":OWNER_COUNT,
		"a_lot":A_LOT,"race_lot":RACE_LOT,"a_chest":k(A_CHEST),"pool_pan":POOL_PAN,"a_pans":A_PANS,"farm":[farm.x,farm.y],"cap":CAP,
		"phase":phases,"needs":Salt.GATE_NEEDS_EACH,"order":Salt.ORDER,"order_pay":Salt.ORDER_PAY,"yield":Salt.YIELD,"need":Salt.NEED,
		"gate_event":Salt.GATE_EVENT,"start":{"alpha":[A_STAND.x,A_STAND.y],"beta":[GATE_STAND.x,GATE_STAND.y],"delta":[GATE_STAND.x,GATE_STAND.y],"epsilon":[E_STAND.x,E_STAND.y]}}
	print("SN_FIXTURE "+JSON.stringify(out))
	quit(0)
