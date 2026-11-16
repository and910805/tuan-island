extends SceneTree
## Real two-client network regression of the T036 stove cooking queue
## (protocol 38 / save 20) through Session.perform -> request_action RPC ->
## World.act on a SEPARATE dedicated Godot server. Transport is the 8th arg:
## `ws` (plain ws://127.0.0.1:<port>, NOT wss/TLS, NOT cloud) or `enet`.
## The live peer class is asserted, never assumed.
##
## AUTHORIZED SEEDED LOCAL FIXTURE - NOT HUMAN / NATURAL PLAY. `seed` writes a
## temporary save with: world time T0, four stoves (S shared queue stove, H with
## a seeded historical queue record, L1/L2 with legacy single `job` records that
## carry old ingredients {radish:3} / yield 5), exact backpack materials and
## fixed positions next to all four stoves. Everything after the seed goes only
## through the network: no client touches a World.
##
## Driven by work/cooking-queue/network_cooking_queue.py. Args (after `--`):
##   seed <world.json> <alpha_token> <beta_token>     -> prints CQ_FIXTURE {json}
##   <phase> <port> <role> <room_key> <alpha_token> <beta_token> <handoff_dir> [ws|enet]
## Ordering between the two clients uses runner barriers: a client prints
## `CQ_BARRIER <phase> <role> <name>` and waits for <handoff>/go-<phase>-<name>,
## which the runner creates only after BOTH clients printed the same barrier.
##
## contest (server-live, both clients):
##   race         both send 6 queue_cook at S in one burst -> exactly 10 accepted
##                in total (capacity), rejected ones say full; exact charge per
##                accepted job, own record count == own accepted count.
##   overflow     one more queue_cook each: full, no charge.
##   ready-cap    after the first job completes (ready >= 1, total still 10) a
##                further queue_cook is still full: capacity includes ready.
##   cancel rules foreign exact ID -> owner-only refusal; malformed / unknown ID
##                -> not found; ready ID -> completed food is never refunded.
##   own cancel   exact own waiting ID -> stored ingredients refunded exactly.
##   refill+replay one queue_cook (charged once), then the SAME Session sequence
##                is sent again through Session.perform (counter rewound): the
##                server's per-peer sequence gate drops it (no notice, no charge,
##                no record).
##   drain        each cancels all of its own active/waiting jobs by exact ID.
##   claim race   both send ready+1 claim_cook at once -> runner checks total
##                successes == ready count; yields/cooked/collections exact.
##   history      H's seeded record (ingredients radish 3, yield 5, duration 4,
##                started T0-1) completes at started+4 (stored duration, not the
##                current 10 s) and alpha's claim yields the stored 5.
##   legacy L1    unfinished legacy job owned by beta: alpha's queue_cook converts
##                it once (deadline kept, owner beta, old ingredients/yield),
##                alpha is charged only its own bread; alpha cannot cancel the
##                imported job; beta cancels it by exact ID and gets the OLD
##                ingredients back; alpha's job is promoted.
##   legacy L2    completed legacy job owned by alpha: beta's queue_cook imports
##                it straight to ready (completed = old deadline); beta claims the
##                stored yield 5.
##   final        alpha then beta enqueue at S; final state mark for persistence.
## reconnect (fresh client processes, same server): persisted inventories,
##   counters, collections and every record (ids, owners, ingredients, yield,
##   duration, legal lane transitions) unchanged, no record re-imported; beta
##   cancels its persisted waiting job, alpha enqueues one more.
## restart (after a normal server stop + restart on the same save): same
##   persistence checks; alpha cancels the reconnect job by exact ID, beta
##   claims its feed from L2 (feed is not a meal: collections unchanged).
## Every snapshot: no raw profile token anywhere, no construction history, every
## active/waiting/ready record and every (legacy or derived) job owner is the
## public 16-hex actor id, never more than 10 records per stove.
## Output: CQ_CHECK ok ..., CQ_COVER <tag> <phase> <role>, CQ_MARK {json},
## CQ_<ENET|WS>_PASS / CQ_<ENET|WS>_FAIL. Missing API is a failure, never a skip.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const Collections=preload("res://scripts/collections.gd")

const T0:=1000.0
const STOVES:={"S":Vector2i(48,24),"H":Vector2i(48,26),"L1":Vector2i(50,24),"L2":Vector2i(50,26)}
const STAND:={"alpha":Vector2(49.5,25.2),"beta":Vector2(49.5,25.8)}
const KIND:={"alpha":"bread","beta":"soup"}
const START:={"wheat":60,"radish":40,"fiber":20}
const HIST_KIND:="soup"
const HIST_INGREDIENTS:={"radish":3}
const HIST_YIELD:=5
const H_STARTED:=999.0
const H_DURATION:=4.0
const L1_READY:=1600.0
const L2_READY:=995.0
const RACE_SENDS:=6
const LANES:=["active","waiting","ready"]
const BASE_KEYS:=["id","kind","owner","ingredients","yield","recipe_version","duration"]
const LANE_EXTRA:={"active":["started","finish"],"waiting":[],"ready":["completed"]}
const LANE_NEXT:={"active":["active","ready"],"waiting":["waiting","active","ready"],"ready":["ready"]}
const PHASES:={"contest":["alpha","beta"],"reconnect":["alpha","beta"],"restart":["alpha","beta"]}
const WATCHDOG:={"contest":110.0,"reconnect":45.0,"restart":50.0}
const MIN_PROTOCOL:=38
const JOIN_WAIT:=15.0
const RESULT_WAIT:=8.0
const PEER_WAIT:=30.0
const BARRIER_WAIT:=70.0
const READY_WAIT:=35.0
const REPLAY_WAIT:=2.5
const ACTION_BUDGET:=9        # server allows 12 actions / 1000 ms per peer
const ACTION_WINDOW_MSEC:=1100
const TOL:=0.01
const TRANSPORTS:={"enet":"ENET","ws":"WS"}
const TRANSPORT_NAMES:={"enet":"ENet","ws":"loopback WebSocket (ws://, no TLS)"}
# Exact substrings of the real World / CookingQueue messages (runner prechecks them).
const MSG_FULL:="排程已滿"
const MSG_OWNER:="只有投入食材的人可以取消"
const MSG_NOT_FOUND:="找不到這份料理"
const MSG_DONE:="料理已完成，無法取消"
const MSG_EMPTY:="石灶現在沒有料理"
const MSG_CANCELLED:="已取消，食材完整退回"
const MSG_CLAIM:="完成了！"

var session:Session
var phase:=""
var role:=""
var transport:="ws"
var tokens:={}
var handoff:=""
var plan:Dictionary={}
var notices:Array=[]
var sends:Array=[]
var snapshots:=0
var home_snapshots:=0
var seen_both:=false
var violation:=""
var lanes_seen:={}
var max_total:=0
var checks:=0
var finished:=false
var expect_inv:Dictionary={}
var enqueued:Array=[]
var cancelled:Array=[]
var claims:=0
var cooked_start:=0
var meals_expected:Array=[]
var last_enqueued:=""

func _initialize() -> void:
	run.call_deferred()

# ---------------------------------------------------------------- helpers

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

static func hid(token:String) -> String:
	return token.sha256_text().left(16)

static func hex(value:Variant,length:int) -> bool:
	if not value is String or (value as String).length()!=length:return false
	for c in (value as String):
		if not "0123456789abcdef".contains(c):return false
	return true

static func ints(d:Variant) -> Dictionary:
	if not d is Dictionary:return {"<invalid>":-1}
	var out:={}
	for item in d:
		var v=d[item]
		if not (v is int or v is float):return {"<invalid>":-1}
		if int(v)!=0:out[str(item)]=int(v)
	return out

static func plus(a:Dictionary,b:Dictionary,sign:int=1) -> Dictionary:
	var out:=ints(a)
	for item in b:
		out[str(item)]=int(out.get(str(item),0))+sign*int(b[item])
		if int(out[str(item)])==0:out.erase(str(item))
	return out

static func cost(kind:String) -> Dictionary:
	return ints(World.RECIPES[kind].ingredients)

static func close(a:Variant,b:float) -> bool:
	return (a is float or a is int) and absf(float(a)-b)<=TOL

static func online_of(data:Dictionary) -> int:
	var pop=data.get("region_population",{})
	var n:=0
	if pop is Dictionary:
		for region in pop:n+=int(pop[region])
	return n

func snap() -> Dictionary:
	return session.snapshot if session!=null else {}

func other() -> String:
	return "beta" if role=="alpha" else "alpha"

func me_hid() -> String:
	return hid(tokens[role])

func other_hid() -> String:
	return hid(tokens[other()])

func me() -> Dictionary:
	var p=snap().get("players",{}).get(session.own_id,{})
	return p if p is Dictionary else {}

func inventory() -> Dictionary:
	var inv=me().get("inventory",{})
	return inv if inv is Dictionary else {}

func inv_text() -> String:
	return JSON.stringify(ints(inventory())) if session!=null else "{}"

func cooked() -> int:
	return int(me().get("cooked",0))

func meals() -> Array:
	var c=me().get("collection",{})
	var m=c.get("meals",{}) if c is Dictionary else {}
	var out:=[]
	if m is Dictionary:
		for item in m:
			if m[item]==true:out.append(str(item))
	out.sort()
	return out

func region() -> String:
	return str(snap().get("region_id",""))

func world_time() -> float:
	return float(snap().get("time",0.0))

func obj_at(name:String) -> Dictionary:
	var objects=snap().get("objects",{})
	var o=objects.get(k(STOVES[name])) if objects is Dictionary else null
	return o if o is Dictionary else {}

func queue_of(name:String) -> Dictionary:
	var c=obj_at(name).get("cooking")
	return c if c is Dictionary else {}

func lane_records(name:String,lane:String) -> Array:
	var q:=queue_of(name)
	if q.is_empty():return []
	var v=q.get(lane)
	if lane=="active":return [v] if v is Dictionary and not (v as Dictionary).is_empty() else []
	return v if v is Array else []

func all_records(name:String) -> Array:
	var out:=[]
	for lane in LANES:
		for rec in lane_records(name,lane):out.append({"lane":lane,"rec":rec})
	return out

func ids_of(name:String,owner:String="",lanes:Array=LANES) -> Array:
	var out:=[]
	for e in all_records(name):
		if not e.lane in lanes:continue
		if owner.is_empty() or str(e.rec.get("owner",""))==owner:out.append(str(e.rec.get("id","")))
	return out

func locate(name:String,id:String) -> Dictionary:
	for e in all_records(name):
		if str(e.rec.get("id",""))==id:return e
	return {}

func total(name:String) -> int:
	return all_records(name).size()

static func same_set(a:Array,b:Array) -> bool:
	var x:=a.duplicate()
	var y:=b.duplicate()
	x.sort()
	y.sort()
	return x==y

func queue_text(name:String) -> String:
	var parts:=PackedStringArray()
	for lane in LANES:
		var items:=PackedStringArray()
		for rec in lane_records(name,lane):
			var who:="me" if str(rec.get("owner",""))==me_hid() else ("other" if str(rec.get("owner",""))==other_hid() else "?")
			items.append("%s:%s:%s"%[str(rec.get("id","")).left(6),str(rec.get("kind","")),who])
		parts.append("%s=[%s]"%[lane,",".join(items)])
	return "%s{%s}"%[name," ".join(parts)]

func records_view() -> Dictionary:
	var out:={}
	for name in STOVES:
		var list:=[]
		for e in all_records(name):
			var r:Dictionary=e.rec
			var item:={"id":str(r.get("id","")),"lane":e.lane,"owner":str(r.get("owner","")),"kind":str(r.get("kind","")),
				"ingredients":ints(r.get("ingredients")),"yield":int(r.get("yield",0)),"duration":float(r.get("duration",0.0))}
			if r.has("completed"):item["completed"]=float(r.completed)
			if r.has("finish"):item["finish"]=float(r.finish)
			list.append(item)
		out[name]=list
	return out

func historical_records() -> int:
	var n:=0
	for name in STOVES:
		for e in all_records(name):
			if ints(e.rec.get("ingredients"))==HIST_INGREDIENTS and int(e.rec.get("yield",0))==HIST_YIELD:n+=1
	return n

## "" when a record has exactly the lane's public shape and a redacted owner.
func record_problem(rec:Variant,lane:String) -> String:
	if not rec is Dictionary:return "%s record is not a Dictionary"%lane
	var want:Array=BASE_KEYS+LANE_EXTRA[lane]
	var keys:Array=(rec as Dictionary).keys()
	if keys.size()!=want.size():return "%s record keys %s"%[lane,str(keys)]
	for key in keys:
		if not str(key) in want:return "%s record has field %s"%[lane,str(key)]
	if not hex(rec.id,Queue.ID_LENGTH):return "%s record id is not 32 lowercase hex"%lane
	if not owner_public(rec.owner):return "%s record owner is not a public actor id"%lane
	if not World.RECIPES.has(str(rec.kind)):return "%s record kind %s"%[lane,str(rec.kind)]
	return ""

func owner_public(owner:Variant) -> bool:
	return owner is String and hex(owner,16) and (owner==hid(tokens.alpha) or owner==hid(tokens.beta))

func stove_problem(o:Dictionary) -> String:
	if o.has("job"):
		var job=o.job
		if not job is Dictionary or not owner_public(job.get("owner")):return "job owner is not redacted"
	if not o.has("cooking"):return ""
	var q=o.cooking
	if not q is Dictionary or q.size()!=3 or not q.get("active") is Dictionary or not q.get("waiting") is Array or not q.get("ready") is Array:
		return "cooking shape %s"%str(q)
	var n:=0
	for lane in LANES:
		var list:Array=[]
		if lane=="active":
			if not (q.active as Dictionary).is_empty():list.append(q.active)
		else:
			list=q[lane]
		for rec in list:
			var bad:=record_problem(rec,lane)
			if bad!="":return bad
			lanes_seen[lane]=int(lanes_seen.get(lane,0))+1
			n+=1
	max_total=maxi(max_total,n)
	if n>Queue.CAPACITY:return "%d records exceed capacity %d"%[n,Queue.CAPACITY]
	return ""

# ---------------------------------------------------------------- signals

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
	var text:=var_to_str(data)+"|"+id
	for who in tokens:
		if text.contains(tokens[who]) and violation.is_empty():violation="snapshot %d contains raw %s token"%[snapshots,who]
	if data.has("construction") and violation.is_empty():violation="snapshot %d contains raw construction history"%snapshots
	if online_of(data)==2:seen_both=true
	if str(data.get("region_id",""))!="home":return
	home_snapshots+=1
	var objects=data.get("objects",{})
	if not objects is Dictionary:return
	for key in objects:
		var o=objects[key]
		if not o is Dictionary or str(o.get("type",""))!="stove":continue
		var bad:=stove_problem(o)
		if bad!="" and violation.is_empty():violation="snapshot %d stove %s: %s"%[snapshots,str(key),bad]

func _on_notice(message:String,ok:bool) -> void:
	notices.append({"ok":ok,"message":message})
	for who in tokens:
		if message.contains(tokens[who]) and violation.is_empty():violation="notice contains raw %s token"%who
	print("CQ_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("CQ_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("CQ_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	data["phase"]=phase
	data["role"]=role
	print("CQ_MARK "+JSON.stringify(data))

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
	print("CQ_BARRIER %s %s %s"%[phase,role,name])
	var path:=handoff.path_join("go-%s-%s"%[phase,name])
	var go:bool=await until(func():return FileAccess.file_exists(path),BARRIER_WAIT)
	if not check(go,"runner released barrier '%s' (both clients reached it)"%name):return false
	await settle()
	return not finished

## Client-side pacing below the server's 12 actions/s limit, so no result is
## ever the generic rate-limit refusal.
func pace(n:int) -> void:
	while not finished:
		var now_ms:=Time.get_ticks_msec()
		while not sends.is_empty() and now_ms-int(sends[0])>ACTION_WINDOW_MSEC:sends.pop_front()
		if sends.size()+n<=ACTION_BUDGET:break
		await create_timer(0.05).timeout
	for _i in n:sends.append(Time.get_ticks_msec())

## Sends n identical actions through Session.perform (request_action RPC) in one
## frame. Notices arrive in request order on the reliable channel.
func burst(action:String,stove:String,extra:String,n:int) -> Array:
	await pace(n)
	var index:=notices.size()
	for _i in n:session.perform(action,STOVES[stove],extra)
	var got:bool=await until(func():return notices.size()>=index+n,RESULT_WAIT)
	if not got:return []
	await settle()
	return notices.slice(index,index+n)

func act(action:String,stove:String,extra:String="") -> Dictionary:
	var out:Array=await burst(action,stove,extra,1)
	if out.size()!=1:return {"ok":false,"message":"<no notice within %ds>"%int(RESULT_WAIT),"timeout":true}
	return out[0]

func inv_ok() -> bool:
	return ints(inventory())==expect_inv

func claim_of(message:String) -> Dictionary:
	for kind in World.RECIPES:
		var prefix:="%s%s +"%[MSG_CLAIM,str(World.RECIPES[kind].name)]
		if message.begins_with(prefix) and message.trim_prefix(prefix).is_valid_int():
			return {"kind":str(kind),"yield":int(message.trim_prefix(prefix))}
	return {}

func record_claim(c:Dictionary) -> void:
	expect_inv=plus(expect_inv,{c.kind:int(c["yield"])})
	claims+=1
	if Collections.is_meal(c.kind) and not c.kind in meals_expected:
		meals_expected.append(c.kind)
		meals_expected.sort()

func counters_ok(label:String) -> bool:
	if not check(inv_ok(),"%s: inventory exactly %s (have %s)"%[label,JSON.stringify(expect_inv),inv_text()]):return false
	if not check(cooked()==cooked_start+claims,"%s: cooked counter %d == %d + %d own claims"%[label,cooked(),cooked_start,claims]):return false
	return check(meals()==meals_expected,"%s: meal collection %s == %s"%[label,str(meals()),str(meals_expected)])

## Expected refusal: ok=false, message substring, own inventory unchanged.
func refuse(action:String,stove:String,extra:String,contains:String,label:String) -> bool:
	var r:Dictionary=await act(action,stove,extra)
	if not check(not r.has("timeout") and r.ok==false and str(r.message).contains(contains),"%s: refused with '%s': \"%s\""%[label,contains,str(r.message)]):return false
	return check(inv_ok(),"%s: nothing charged or refunded %s"%[label,inv_text()])

## Successful queue_cook: exact charge, exactly one new own record at the stove.
func enqueue(stove:String,kind:String,label:String) -> String:
	var before:=ids_of(stove,me_hid())
	var r:Dictionary=await act("queue_cook",stove,kind)
	if not check(r.ok==true,"%s: queue_cook %s at %s accepted: \"%s\""%[label,kind,stove,str(r.message)]):return ""
	expect_inv=plus(expect_inv,cost(kind),-1)
	var fresh:=[]
	for id in ids_of(stove,me_hid()):
		if not id in before:fresh.append(id)
	if not check(fresh.size()==1,"%s: exactly one new own record at %s %s"%[label,stove,queue_text(stove)]):return ""
	if not check(inv_ok(),"%s: charged exactly %s once: %s"%[label,JSON.stringify(cost(kind)),inv_text()]):return ""
	enqueued.append(fresh[0])
	last_enqueued=fresh[0]
	return fresh[0]

## Owner cancel of an exact ID: the stored ingredients come back exactly.
func cancel_own(stove:String,id:String,label:String) -> bool:
	var e:=locate(stove,id)
	if not check(not e.is_empty() and e.lane!="ready" and str(e.rec.owner)==me_hid(),"%s: %s is my unfinished record at %s"%[label,id.left(8),stove]):return false
	var refund:=ints(e.rec.ingredients)
	var r:Dictionary=await act("cancel_queued_cook",stove,id)
	if not check(r.ok==true and str(r.message).contains(MSG_CANCELLED),"%s: exact-ID cancel accepted: \"%s\""%[label,str(r.message)]):return false
	expect_inv=plus(expect_inv,refund)
	cancelled.append(id)
	return check(locate(stove,id).is_empty() and inv_ok(),"%s: record gone, refunded exactly %s: %s"%[label,JSON.stringify(refund),inv_text()])

# ---------------------------------------------------------------- entry

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if not (args.size() in [7,8]) or not PHASES.has(args[0]) or not (args[2] in PHASES[args[0]]) \
		or (args.size()==8 and not TRANSPORTS.has(args[7])):
		push_error("CQ_FAIL usage: <phase> <port> <role> <room_key> <alpha_token> <beta_token> <handoff_dir> [ws|enet]")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	if args.size()==8:transport=args[7]
	tokens={"alpha":args[4],"beta":args[5]}
	handoff=args[6]
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG[phase])))
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=tokens[role]
	session.changed.connect(_on_changed)
	session.notice.connect(_on_notice)
	if not check(int(Session.PROTOCOL)>=MIN_PROTOCOL,"Session.PROTOCOL=%d (cooking queue needs >= %d)"%[int(Session.PROTOCOL),MIN_PROTOCOL]):return
	if not check(session.has_method("perform") and session.has_method("request_action") and "counter" in session,"Session exposes perform/request_action/counter"):return
	var port:=int(args[1])
	var address:="127.0.0.1" if transport=="enet" else "ws://127.0.0.1:%d"%port
	var joined_err:=session.join(address,port,role,args[3])
	if not check(joined_err==OK,"%s join to %s accepted by Session.join (err %d)"%[TRANSPORT_NAMES[transport],address,joined_err]):return
	if not check(peer_matches(),"client multiplayer peer is %s"%peer_class()):return
	var joined:bool=await until(func():return not session.own_id.is_empty() and snap().get("players",{}).has(session.own_id),JOIN_WAIT)
	if not check(joined and peer_matches(),"registered over %s with protocol %d and the room key (peer %s)"%[TRANSPORT_NAMES[transport],Session.PROTOCOL,peer_class()]):return
	cover("transport_verified")
	if not check(session.own_id==me_hid(),"own id is the hashed profile token"):return
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are online together"):return
	await settle()
	if not check(region()=="home","both play in home"):return
	match phase:
		"contest":await contest()
		_:await persisted()
	if finished:return
	if not check(home_snapshots>0 and violation.is_empty(),"%d snapshots (%d home): no raw tokens / construction history, every record and job owner redacted to a public id, max %d records per stove; lanes seen %s"%[snapshots,home_snapshots,max_total,JSON.stringify(lanes_seen)]+("" if violation.is_empty() else " -- "+violation)):return
	cover("tokens_absent")
	if phase=="contest":
		if not check(int(lanes_seen.get("active",0))>0 and int(lanes_seen.get("waiting",0))>0 and int(lanes_seen.get("ready",0))>0,"redaction observed on non-empty active, waiting and ready lanes"):return
		cover("owners_redacted")
	finish(true,"")

func peer_class() -> String:
	var link:MultiplayerPeer=null
	if session!=null and session.is_inside_tree():link=session.multiplayer.multiplayer_peer
	if link is WebSocketMultiplayerPeer:return "WebSocketMultiplayerPeer"
	if link is ENetMultiplayerPeer:return "ENetMultiplayerPeer"
	return "none" if link==null else link.get_class()

func peer_matches() -> bool:
	return peer_class()==("ENetMultiplayerPeer" if transport=="enet" else "WebSocketMultiplayerPeer")

func finish(ok:bool,step:String) -> void:
	if finished:return
	finished=true
	var tag:String=TRANSPORTS[transport]
	if ok:print("CQ_%s_PASS %s %s transport=%s checks=%d snapshots=%d home=%d notices=%d"%[tag,phase,role,transport,checks,snapshots,home_snapshots,notices.size()])
	else:
		var view:="no session"
		if session!=null:
			var parts:=PackedStringArray()
			for name in STOVES:parts.append(queue_text(name))
			view=" ".join(parts)
		push_error("CQ_%s_FAIL %s %s transport=%s after %d checks: %s | %s | inv=%s | violation=%s"%[tag,phase,role,transport,checks,step,view,inv_text(),violation])
	if session!=null:session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

# ---------------------------------------------------------------- contest

func initial_checks() -> bool:
	expect_inv=ints(START)
	cooked_start=0
	meals_expected=[]
	if not check(inv_ok() and cooked()==0 and meals().is_empty(),"%s starts with exact fixture materials %s, cooked 0, no meals"%[role,inv_text()]):return false
	var s:=obj_at("S")
	if not check(str(s.get("type",""))=="stove" and not s.has("cooking") and not s.has("job"),"S is a plain idle stove"):return false
	for name in ["L1","L2"]:
		var o:=obj_at(name)
		var job=o.get("job")
		var owner:=hid(tokens.beta if name=="L1" else tokens.alpha)
		if not check(not o.has("cooking") and job is Dictionary and str(job.get("owner"))==owner and str(job.get("kind"))==HIST_KIND \
			and ints(job.get("ingredients"))==HIST_INGREDIENTS and int(job.get("yield",0))==HIST_YIELD \
			and close(job.get("ready"),L1_READY if name=="L1" else L2_READY),"%s carries the seeded legacy job (owner redacted, old ingredients/yield/deadline): %s"%[name,JSON.stringify(job)]):return false
	var h:=all_records("H")
	if not check(h.size()==1 and str(h[0].rec.owner)==hid(tokens.alpha) and ints(h[0].rec.ingredients)==HIST_INGREDIENTS \
		and int(h[0].rec["yield"])==HIST_YIELD and close(h[0].rec.duration,H_DURATION),"H carries the seeded historical queue record: %s"%queue_text("H")):return false
	return check(ints(HIST_INGREDIENTS)!=cost(HIST_KIND) and HIST_YIELD!=int(World.RECIPES[HIST_KIND]["yield"]) and H_DURATION!=float(World.RECIPES[HIST_KIND].time),
		"historical snapshot differs from today's %s recipe (so refunds/yields prove stored values)"%HIST_KIND)

func contest() -> void:
	if not initial_checks():return
	var kind:String=KIND[role]
	# ---- race for the 10 slots.
	var go:bool=await barrier("race")
	if not go:return
	var results:Array=await burst("queue_cook","S",kind,RACE_SENDS)
	if not check(results.size()==RACE_SENDS,"all %d racing queue_cook requests answered"%RACE_SENDS):return
	var oks:=0
	for r in results:
		if r.ok==true:oks+=1
		elif not check(str(r.message).contains(MSG_FULL),"race rejection is the capacity refusal: \"%s\""%str(r.message)):return
	expect_inv=plus(expect_inv,cost(kind),-oks)
	var mine:=ids_of("S",me_hid())
	if not check(mine.size()==oks and inv_ok(),"race: %d accepted == %d own records, charged exactly %d x %s: %s"%[oks,mine.size(),oks,JSON.stringify(cost(kind)),inv_text()]):return
	enqueued.append_array(mine)
	cover("race_exact_charge")
	mark({"mark":"race","ok":oks,"full":RACE_SENDS-oks,"ids":mine})
	go=await barrier("raced")
	if not go:return
	if not check(total("S")==Queue.CAPACITY and ids_of("S",other_hid()).size()==Queue.CAPACITY-oks,"S holds exactly %d records (%d mine): %s"%[Queue.CAPACITY,oks,queue_text("S")]):return
	var ok:bool=await refuse("queue_cook","S",kind,MSG_FULL,"overflow at 10")
	if not ok:return
	if not check(total("S")==Queue.CAPACITY and same_set(ids_of("S",me_hid()),mine),"overflow added no record"):return
	cover("overflow_no_charge")
	# ---- capacity counts ready food.
	var has_ready:bool=await until(func():return lane_records("S","ready").size()>=1,READY_WAIT)
	if not check(has_ready and total("S")==Queue.CAPACITY,"first job completed into ready, total still 10: %s"%queue_text("S")):return
	ok=await refuse("queue_cook","S",kind,MSG_FULL,"full with ready food")
	if not ok:return
	cover("capacity_includes_ready")
	go=await barrier("cancel_rules")
	if not go:return
	# ---- cancellation rules.
	var foreign:=ids_of("S",other_hid(),["active","waiting"])
	if not check(not foreign.is_empty(),"%s has an unfinished record to target"%other()):return
	var target:String=foreign.back()
	ok=await refuse("cancel_queued_cook","S",target,MSG_OWNER,"cancel %s's exact ID"%other())
	if not ok:return
	if not check(not locate("S",target).is_empty(),"foreign record still queued"):return
	cover("owner_only_cancel")
	ok=await refuse("cancel_queued_cook","S","NOT-A-JOB-ID",MSG_NOT_FOUND,"malformed ID")
	if not ok:return
	ok=await refuse("cancel_queued_cook","S",Crypto.new().generate_random_bytes(16).hex_encode(),MSG_NOT_FOUND,"unknown 32-hex ID")
	if not ok:return
	cover("bad_id_rejected")
	var ready_ids:=ids_of("S","",["ready"])
	if not check(not ready_ids.is_empty(),"a ready record exists"):return
	ok=await refuse("cancel_queued_cook","S",ready_ids[0],MSG_DONE,"cancel completed food")
	if not ok:return
	if not check(locate("S",ready_ids[0]).get("lane","")=="ready","completed food stays ready"):return
	cover("cancel_ready_rejected")
	go=await barrier("own_cancel")
	if not go:return
	var own_waiting:=ids_of("S",me_hid(),["waiting"])
	if not check(not own_waiting.is_empty(),"I have a waiting record: %s"%queue_text("S")):return
	ok=await cancel_own("S",own_waiting.back(),"own waiting cancel")
	if not ok:return
	cover("exact_cancel_refund")
	go=await barrier("refill")
	if not go:return
	# ---- refill one slot, then replay the very same Session sequence.
	var fresh:String=await enqueue("S",kind,"refill")
	if fresh.is_empty():return
	var accepted_seq:int=int(session.counter)
	var own_ids:=ids_of("S",me_hid())
	var index:=notices.size()
	session.counter=accepted_seq-1
	await pace(1)
	var replay_seq:int=session.perform("queue_cook",STOVES.S,kind)
	if not check(replay_seq==accepted_seq,"replayed the accepted request's sequence %d via Session.perform"%accepted_seq):return
	await create_timer(REPLAY_WAIT).timeout
	await settle()
	if not check(notices.size()==index and inv_ok() and same_set(ids_of("S",me_hid()),own_ids),"replayed sequence %d dropped: no notice, no second charge, no new record"%accepted_seq):return
	cover("sequence_replay_dropped")
	go=await barrier("drain")
	if not go:return
	# ---- drain own unfinished jobs by exact ID.
	for _attempt in 16:
		var left:=ids_of("S",me_hid(),["active","waiting"])
		if left.is_empty():break
		var id:String=left.back()
		var e:=locate("S",id)
		var refund:=ints(e.rec.ingredients)
		var r:Dictionary=await act("cancel_queued_cook","S",id)
		if r.ok==true:
			expect_inv=plus(expect_inv,refund)
			cancelled.append(id)
		elif not check(str(r.message).contains(MSG_DONE),"drain cancel either refunds or meets just-completed food: \"%s\""%str(r.message)):return
	if not check(ids_of("S",me_hid(),["active","waiting"]).is_empty() and inv_ok(),"drained own unfinished jobs with exact refunds: %s"%inv_text()):return
	cover("drain_refund")
	go=await barrier("drained")
	if not go:return
	var idle:bool=await until(func():return lane_records("S","active").is_empty() and lane_records("S","waiting").is_empty(),RESULT_WAIT)
	var ready_now:=ids_of("S","",["ready"])
	if not check(idle and not ready_now.is_empty(),"S holds only ready food: %s"%queue_text("S")):return
	mark({"mark":"ready","ready":ready_now.size(),"ids":ready_now})
	go=await barrier("claim")
	if not go:return
	# ---- both claim at once; each ready record may be claimed only once.
	var claim_results:Array=await burst("claim_cook","S","",ready_now.size()+1)
	if not check(claim_results.size()==ready_now.size()+1,"all claim requests answered"):return
	var won:=0
	for r in claim_results:
		if r.ok==true:
			var c:=claim_of(str(r.message))
			if not check(not c.is_empty() and int(c["yield"])==int(World.RECIPES[c.kind]["yield"]),"claim message names a recipe and its yield: \"%s\""%str(r.message)):return
			record_claim(c)
			won+=1
		elif not check(str(r.message).contains(MSG_EMPTY),"surplus claim finds nothing: \"%s\""%str(r.message)):return
	if not counters_ok("shared claim"):return
	var emptied:bool=await until(func():return total("S")==0,RESULT_WAIT)
	if not check(emptied,"every ready record left S exactly once: %s"%queue_text("S")):return
	mark({"mark":"claim","claimed":won,"ready":ready_now.size(),"ids":ready_now})
	cover("claim_once")
	go=await barrier("history")
	if not go:return
	# ---- seeded historical record finished with its stored duration.
	var h_ready:bool=await until(func():return lane_records("H","ready").size()==1,READY_WAIT)
	if not check(h_ready,"H record completed: %s"%queue_text("H")):return
	var hr:Dictionary=lane_records("H","ready")[0]
	if not check(str(hr.owner)==hid(tokens.alpha) and str(hr.kind)==HIST_KIND and ints(hr.ingredients)==HIST_INGREDIENTS and int(hr["yield"])==HIST_YIELD \
		and close(hr.duration,H_DURATION) and close(hr.completed,H_STARTED+H_DURATION),
		"H completed at stored started+duration %.1f (not +%.0f), stored ingredients/yield kept: %s"%[H_STARTED+H_DURATION,float(World.RECIPES[HIST_KIND].time),JSON.stringify(hr)]):return
	go=await barrier("history_claim")
	if not go:return
	if role=="alpha":
		var r:Dictionary=await act("claim_cook","H")
		var c:=claim_of(str(r.get("message","")))
		if not check(r.ok==true and c.get("kind")==HIST_KIND and int(c.get("yield",0))==HIST_YIELD,"claim of H yields the stored %d %s: \"%s\""%[HIST_YIELD,HIST_KIND,str(r.message)]):return
		record_claim(c)
		if not counters_ok("history claim"):return
		if not check(total("H")==0,"H empty after its single claim"):return
		cover("historical_record")
	go=await barrier("legacy1")
	if not go:return
	# ---- legacy L1 (unfinished, beta's): alpha converts, cannot cancel.
	if role=="alpha":
		var before_time:=world_time()
		var bid:String=await enqueue("L1","bread","legacy L1 conversion")
		if bid.is_empty():return
		var act_l1:=lane_records("L1","active")
		if not check(act_l1.size()==1 and ids_of("L1","",["waiting"])==[bid],"L1: imported job active, my bread waiting: %s"%queue_text("L1")):return
		var imp:Dictionary=act_l1[0]
		if not check(str(imp.owner)==hid(tokens.beta) and str(imp.kind)==HIST_KIND and ints(imp.ingredients)==HIST_INGREDIENTS and int(imp["yield"])==HIST_YIELD \
			and close(imp.finish,L1_READY) and close(imp.duration,float(imp.finish)-float(imp.started)) and float(imp.started)>=T0 and float(imp.started)<=world_time()+TOL \
			and float(imp.started)>=before_time-TOL,
			"L1 import keeps owner beta, deadline %.0f, old ingredients/yield; duration = finish - bounded start: %s"%[L1_READY,JSON.stringify(imp)]):return
		var derived=obj_at("L1").get("job")
		if not check(derived is Dictionary and str(derived.get("owner"))==hid(tokens.beta) and close(derived.get("ready"),L1_READY),"derived display job projects the imported record (owner redacted)"):return
		ok=await refuse("cancel_queued_cook","L1",str(imp.id),MSG_OWNER,"cancel beta's imported legacy job")
		if not ok:return
		cover("legacy_unfinished_import")
		mark({"mark":"legacy1","imported":str(imp.id),"bread":bid})
	go=await barrier("legacy1_owner")
	if not go:return
	if role=="beta":
		var mine_l1:=ids_of("L1",me_hid())
		if not check(mine_l1.size()==1 and ints(locate("L1",mine_l1[0]).rec.ingredients)==HIST_INGREDIENTS,"exactly one imported record owned by me at L1: %s"%queue_text("L1")):return
		ok=await cancel_own("L1",mine_l1[0],"legacy owner cancel (old ingredients)")
		if not ok:return
		if not check(lane_records("L1","active").size()==1 and str(lane_records("L1","active")[0].owner)==hid(tokens.alpha) and lane_records("L1","waiting").is_empty(),
			"alpha's bread promoted at L1: %s"%queue_text("L1")):return
		cover("legacy_owner_refund")
	go=await barrier("legacy2")
	if not go:return
	# ---- legacy L2 (completed, alpha's): beta converts straight into ready and claims.
	if role=="beta":
		var fid:String=await enqueue("L2","feed","legacy L2 conversion")
		if fid.is_empty():return
		var rd:=lane_records("L2","ready")
		if not check(not rd.is_empty() and str(rd[0].owner)==hid(tokens.alpha) and ints(rd[0].ingredients)==HIST_INGREDIENTS and int(rd[0]["yield"])==HIST_YIELD \
			and close(rd[0].completed,L2_READY) and locate("L2",fid).get("lane","") in ["active","ready"],
			"completed legacy job imported directly into ready (completed %.0f, owner alpha), my feed behind it: %s"%[L2_READY,queue_text("L2")]):return
		var imported_id:=str(rd[0].id)
		var r:Dictionary=await act("claim_cook","L2")
		var c:=claim_of(str(r.get("message","")))
		if not check(r.ok==true and c.get("kind")==HIST_KIND and int(c.get("yield",0))==HIST_YIELD,"claim of the imported L2 food yields the stored %d: \"%s\""%[HIST_YIELD,str(r.message)]):return
		record_claim(c)
		if not counters_ok("legacy L2 claim"):return
		if not check(locate("L2",imported_id).is_empty() and ids_of("L2")==[fid],"L2 now holds only my feed"):return
		cover("legacy_completed_import")
	go=await barrier("legacy_done")
	if not go:return
	if not check(historical_records()==0,"no historical/imported record remains anywhere (each converted once, then settled)"):return
	if not counters_ok("after legacy"):return
	cover("collections_counter")
	# ---- leave work queued for persistence: alpha first, then beta waits behind.
	go=await barrier("final_alpha")
	if not go:return
	if role=="alpha":
		var aid:String=await enqueue("S","bread","final alpha")
		if aid.is_empty():return
	go=await barrier("final_beta")
	if not go:return
	if role=="beta":
		var sid:String=await enqueue("S","soup","final beta")
		if sid.is_empty():return
		if not check(locate("S",sid).get("lane","")=="waiting","beta's final job waits behind alpha's bread"):return
	go=await barrier("final")
	if not go:return
	final_mark()

func final_mark() -> void:
	mark({"mark":"final","inventory":ints(inventory()),"cooked":cooked(),"meals":meals(),"claims":claims,
		"enqueued":enqueued,"cancelled":cancelled,"last_enqueued":last_enqueued,"records":records_view(),"time":world_time()})

# ---------------------------------------------------------------- reconnect / restart

func read_plan() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("plan-%s.json"%phase)))
	if not data is Dictionary:return false
	for who in ["alpha","beta"]:
		var item=data.get(who)
		if not item is Dictionary or not item.get("inventory") is Dictionary or not item.get("records") is Dictionary or not item.get("meals") is Array:return false
	plan=data
	return true

func persisted_problem(previous:Dictionary) -> String:
	for name in STOVES:
		var before=previous.get(name,[])
		if not before is Array:return "%s missing from plan"%name
		var want:={}
		for item in before:want[str(item.id)]=item
		var have:={}
		for e in all_records(name):have[str(e.rec.id)]=e
		var a:=want.keys()
		var b:=have.keys()
		a.sort()
		b.sort()
		if a!=b:return "%s ids %s != persisted %s"%[name,str(b),str(a)]
		for id in want:
			var w:Dictionary=want[id]
			var e:Dictionary=have[id]
			var r:Dictionary=e.rec
			if str(r.owner)!=str(w.owner) or str(r.kind)!=str(w.kind) or ints(r.ingredients)!=ints(w.ingredients) \
				or int(r["yield"])!=int(w["yield"]) or not close(r.duration,float(w.duration)):return "%s record %s fields changed"%[name,id.left(8)]
			if not e.lane in LANE_NEXT[str(w.lane)]:return "%s record %s went %s -> %s"%[name,id.left(8),str(w.lane),e.lane]
			if w.has("completed") and not close(r.get("completed"),float(w.completed)):return "%s ready %s completion moved"%[name,id.left(8)]
			if w.has("finish") and r.has("finish") and not close(r.finish,float(w.finish)):return "%s active %s deadline moved"%[name,id.left(8)]
	return ""

func persisted() -> void:
	if not check(read_plan(),"handoff plan-%s.json (previous phase's final state) is valid"%phase):return
	var mine:Dictionary=plan[role]
	expect_inv=ints(mine.inventory)
	cooked_start=int(mine.cooked)
	meals_expected=[]
	for m in mine.meals:meals_expected.append(str(m))
	meals_expected.sort()
	if not counters_ok("%s persisted"%phase):return
	var bad:=persisted_problem(mine.records)
	if not check(bad.is_empty(),"%s: every queued record persisted (ids, redacted owners, ingredients, yield, duration, legal lanes): %s"%[phase,bad]):return
	if not check(historical_records()==0 and obj_at("L1").has("cooking") and obj_at("L2").has("cooking"),"%s: legacy stoves stay converted, nothing re-imported"%phase):return
	cover("%s_persisted"%phase)
	# Observe both reconnect snapshots before either client mutates shared jobs.
	# Otherwise the faster beta can cancel while alpha is still checking IDs.
	var observed:bool=await barrier("persisted_observed")
	if not observed:return
	if phase=="reconnect":
		if role=="beta":
			var cancelled_ok:bool=await cancel_own("S",str(mine.last_enqueued),"reconnect cancel of persisted waiting job")
			if not cancelled_ok:return
			cover("reconnect_cancel")
		else:
			var rid:String=await enqueue("S","bread","reconnect enqueue")
			if rid.is_empty():return
			cover("reconnect_enqueue")
	else:
		if role=="alpha":
			var restart_ok:bool=await cancel_own("S",str(mine.last_enqueued),"restart cancel of the reconnect job")
			if not restart_ok:return
			cover("restart_cancel")
		else:
			var fed:bool=await until(func():return not ids_of("L2",me_hid(),["ready"]).is_empty(),READY_WAIT)
			if not check(fed,"my L2 feed is ready: %s"%queue_text("L2")):return
			var r:Dictionary=await act("claim_cook","L2")
			var c:=claim_of(str(r.get("message","")))
			if not check(r.ok==true and c.get("kind")=="feed" and int(c.get("yield",0))==int(World.RECIPES.feed["yield"]),"claim my feed after restart: \"%s\""%str(r.message)):return
			record_claim(c)
			if not counters_ok("restart feed claim (feed is no meal)"):return
			cover("restart_claim")
	if not counters_ok("%s end"%phase):return
	var go:bool=await barrier("final")
	if not go:return
	final_mark()

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=4:
		push_error("CQ_SEED_FAIL usage: seed <world.json> <alpha_token> <beta_token>")
		quit(2)
		return
	tokens={"alpha":args[2],"beta":args[3]}
	var world:=World.new()
	world.save_path=args[1]
	world.state.time=T0
	var problems:=PackedStringArray()
	var cells:={}
	for name in STOVES:cells[k(STOVES[name])]=true
	for who in STAND:cells[k(Vector2i(floori(STAND[who].x),floori(STAND[who].y)))]=true
	for key in cells:
		var c:=World.cell(key)
		if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c)!="":
			problems.append("cell %s is not clear home land"%key)
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(key):problems.append("cell %s already used in %s"%[key,layer])
	var crypto:=Crypto.new()
	var h_id:=crypto.generate_random_bytes(16).hex_encode()
	for name in STOVES:
		world.state.objects[k(STOVES[name])]={"type":"stove","owner":tokens.beta if name=="L1" else tokens.alpha,"items":{}}
	world.state.objects[k(STOVES.L1)].job={"kind":HIST_KIND,"ready":L1_READY,"owner":tokens.beta,"ingredients":HIST_INGREDIENTS.duplicate(),"yield":HIST_YIELD,"recipe_version":1}
	world.state.objects[k(STOVES.L2)].job={"kind":HIST_KIND,"ready":L2_READY,"owner":tokens.alpha,"ingredients":HIST_INGREDIENTS.duplicate(),"yield":HIST_YIELD,"recipe_version":1}
	var h_queue:={"active":{"id":h_id,"kind":HIST_KIND,"owner":tokens.alpha,"ingredients":HIST_INGREDIENTS.duplicate(),"yield":HIST_YIELD,
		"recipe_version":Queue.RECIPE_VERSION,"duration":H_DURATION,"started":H_STARTED,"finish":H_STARTED+H_DURATION},"waiting":[],"ready":[]}
	if not Queue.validate(h_queue,World.RECIPES,T0):problems.append("seeded H queue fails CookingQueue.validate")
	world.state.objects[k(STOVES.H)].cooking=h_queue
	for who in ["alpha","beta"]:
		world.add_player(tokens[who],who)
		var person:Dictionary=world.state.players[tokens[who]]
		var spot:Vector2=STAND[who]
		person.x=spot.x
		person.y=spot.y
		person.inventory=START.duplicate(true)
		if not world.can_stand(spot):problems.append("%s cannot stand at %s"%[who,spot])
		for name in STOVES:
			var d:=spot.distance_to(Vector2(STOVES[name])+Vector2(0.5,0.5))
			if d>3.0:problems.append("%s is %.2f from stove %s (interaction range 3.2)"%[who,d,name])
	if not problems.is_empty():
		for problem in problems:push_error("CQ_SEED_FAIL "+problem)
		quit(1)
		return
	if not world.save():
		push_error("CQ_SEED_FAIL save: "+world.save_error)
		quit(1)
		return
	# Round trip through the real loader/SaveSchema before any server uses it.
	var check_world:=World.new()
	var loaded:=check_world.load_world(args[1])
	var objects:Dictionary=check_world.state.objects if loaded else {}
	var reload_ok:bool=loaded and not check_world.recovered_from_backup and int(check_world.state.version)==SaveSchema.VERSION \
		and objects.get(k(STOVES.L1),{}).has("job") and not objects.get(k(STOVES.L1),{}).has("cooking") \
		and objects.get(k(STOVES.L2),{}).has("job") and objects.get(k(STOVES.H),{}).has("cooking") \
		and not objects.get(k(STOVES.S),{}).has("cooking") and absf(float(check_world.state.time)-T0)<TOL
	if not reload_ok:
		push_error("CQ_SEED_FAIL seeded save did not reload through SaveSchema with legacy jobs and the H queue intact")
		quit(1)
		return
	var stoves:={}
	for name in STOVES:stoves[name]=[STOVES[name].x,STOVES[name].y]
	var fixture:={"seed_version":int(check_world.state.version),"protocol":int(Session.PROTOCOL),"capacity":Queue.CAPACITY,
		"t0":T0,"stoves":stoves,"start":START,"kinds":KIND,"history":{"kind":HIST_KIND,"ingredients":HIST_INGREDIENTS,"yield":HIST_YIELD,
		"duration":H_DURATION,"started":H_STARTED,"l1_ready":L1_READY,"l2_ready":L2_READY},"h_id":h_id,
		"stand":{"alpha":[STAND.alpha.x,STAND.alpha.y],"beta":[STAND.beta.x,STAND.beta.y]}}
	print("CQ_FIXTURE "+JSON.stringify(fixture))
	quit(0)
