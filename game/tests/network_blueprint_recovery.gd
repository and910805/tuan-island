extends SceneTree
## Durable BlueprintController pending recovery across a REAL client process
## termination and a REAL server restart (save schema 19 / protocol 37).
##
## AUTHORIZED LOCAL FIXTURE: only `seed` writes exact test materials, one player
## position and one personal-library entry straight into temporary files. This
## proves pending-record recovery wiring only; it is NOT evidence of natural play.
##
## Driven by work/house-rooms/network_blueprint_recovery.py. The real Session
## networking (WebSocket by default, ENet optional) and the real
## BlueprintController (game/scripts/blueprint_controller.gd) are used; this
## script only plays the player: choose -> pin -> confirm, later retry_pending.
## Nothing here resubmits automatically and nothing fakes a server result.
##
## Args (after `--`):
##   seed <world.json> <token> <library_path>
##        Writes the fixture world + personal library, prints `BPR_FIXTURE {json}`.
##   <phase> <transport> <port> <room_key> <token> <library_path> <handoff_dir>
##     submit   Against the fault-injection server
##              (tests/network_blueprint_recovery_server.gd). Real quote, then
##              Controller.confirm(): the pending file must exist on disk before the
##              submit RPC is sent. The server commits + saves, sends snapshots, and
##              DELIBERATELY DROPS the first successful apply reply (labelled
##              injected lost reply). This client sees the complete house in a
##              snapshot but never a result, prints BPR_MARK committed_unacked and
##              then waits, doing nothing, until the runner terminates the process.
##     recover  Fresh process against the RESTARTED unmodified server (main.gd
##              --server). Loads the same personal library / scope / pending file;
##              mode must be "unknown" with no automatic resend. One explicit
##              retry_pending() must return the original receipt, clear the file,
##              and leave materials charged exactly once and the house complete.
## Output: BPR_CHECK ok ..., BPR_MARK {json}, BPR_PASS / BPR_FAIL. Raw profile
## tokens are never printed.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Controller=preload("res://scripts/blueprint_controller.gd")
const Pending=preload("res://scripts/blueprint_pending.gd")
const Library=preload("res://scripts/blueprint_library.gd")

const CONTRACT_PROTOCOL:=42
const CONTRACT_SAVE:=23
const SITE:=Vector2i(48,22)
const STAND:=Vector2(47.0,24.0)
const RING:=[Vector2i(1,0),Vector2i(2,0),Vector2i(0,1),Vector2i(3,1),Vector2i(0,2),Vector2i(3,2),Vector2i(1,3),Vector2i(2,3)]
const DOOR:=Vector2i(0,2)
const CHEST:=Vector2i(2,1)
const HOUSE_NAME:="復原測試小屋"
const LAYERS:=["ground","objects","roofs"]
const CLEARANCE:=0.8
const JOIN_WAIT:=15.0
const RESULT_WAIT:=10.0
const QUIET_WAIT:=3.0
const WATCHDOG:={"submit":60.0,"recover":45.0}

var session:Session
var ctrl:Controller
var phase:=""
var transport:=""
var port:=0
var room_key:=""
var token:=""
var library_path:=""
var handoff:=""
var checks:=0
var finished:=false
var violation:=""
var snapshots:=0
var replies:Array=[]        # raw Session.blueprint_applied deliveries {nonce, result}
var ctrl_applied:Array=[]   # Controller.applied emissions
var pre_send:={}            # captured at the first transition to "submitting"

func _initialize() -> void:
	run.call_deferred()

# ---------------------------------------------------------------- fixture data

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

static func layer_of(kind:String) -> String:
	if kind in ["floor","path"]:return "ground"
	if kind=="roof":return "roofs"
	return "objects"

static func house_raw() -> Dictionary:
	var pieces:=[]
	for y in range(1,3):
		for x in range(1,3):pieces.append({"kind":"floor","x":x,"y":y})
	for c:Vector2i in RING:pieces.append({"kind":"door" if c==DOOR else "wall","x":c.x,"y":c.y})
	pieces.append({"kind":"chest","x":CHEST.x,"y":CHEST.y})
	return {"version":1,"name":HOUSE_NAME,"width":4,"height":4,"pieces":pieces}

static func roof_count() -> int:
	var n:=0
	for p:Dictionary in house_raw().pieces:
		if str(p.kind)=="floor":n+=1
	return n

static func piece_count() -> int:
	return (house_raw().pieces as Array).size()

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
		if item=="name":continue
		out[str(item)]=int(out.get(str(item),0))+sign*int(b[item])
		if int(out[str(item)])==0:out.erase(str(item))
	return out

## Exact gross cost from the CURRENT recipes (World.BUILD): pieces + auto roofs.
static func house_cost() -> Dictionary:
	var out:={}
	for p:Dictionary in house_raw().pieces:out=plus(out,World.BUILD[str(p.kind)])
	for i in roof_count():out=plus(out,World.BUILD.roof)
	return out

## Two houses' worth, so an accidental second charge would succeed and be visible.
static func start_inventory() -> Dictionary:
	return plus(house_cost(),house_cost())

static func final_inventory() -> Dictionary:
	return plus(start_inventory(),house_cost(),-1)

static func site_cells() -> Dictionary:
	var raw:=house_raw()
	var cells:={}
	for y in int(raw.height):
		for x in int(raw.width):cells[k(SITE+Vector2i(x,y))]={}
	for p:Dictionary in raw.pieces:
		var want:Dictionary=cells[k(SITE+Vector2i(int(p.x),int(p.y)))]
		want[layer_of(str(p.kind))]=str(p.kind)
		if str(p.kind)=="floor":want["roofs"]="roof"
	return cells

## Order/number-format independent fingerprint of a design (no secrets in it).
static func design_fp(design:Variant) -> String:
	if not design is Dictionary:return ""
	var parts:=[]
	for p in design.get("pieces",[]):
		if p is Dictionary:parts.append("%s,%d,%d"%[str(p.get("kind","")),int(p.get("x",0)),int(p.get("y",0))])
	parts.sort()
	return ("%s|%d|%d|%s"%[str(design.get("name","")),int(design.get("width",0)),int(design.get("height",0)),";".join(parts)]).sha256_text()

static func hid(value:String) -> String:
	return value.sha256_text().left(16)

# ---------------------------------------------------------------- observation

func snap() -> Dictionary:
	return session.snapshot if session!=null else {}

func me() -> Dictionary:
	var p=snap().get("players",{}).get(session.own_id,{}) if session!=null else {}
	return p if p is Dictionary else {}

func inventory() -> Dictionary:
	var inv=me().get("inventory",{})
	return inv if inv is Dictionary else {}

func inv_text() -> String:
	return JSON.stringify(ints(inventory())) if session!=null else "{}"

func own_epoch() -> int:
	return int(me().get("travel_epoch",-1))

## "empty" | "complete" (every cell exact, owned by me, auto roofs) | "partial: ..."
func site_state(data:Dictionary) -> String:
	var cells:=site_cells()
	var any:=false
	var detail:=""
	for key in cells:
		var want:Dictionary=cells[key]
		for layer in LAYERS:
			var source=data.get(layer,{})
			var o=source.get(key) if source is Dictionary else null
			var have:=str(o.get("type","?")) if o is Dictionary else ""
			var wanted:=str(want.get(layer,""))
			if have!="":any=true
			if have!=wanted:
				if detail.is_empty():detail="%s %s has '%s' want '%s'"%[key,layer,have,wanted]
			elif have!="" and (str(o.get("owner",""))!=hid(token) or (layer=="roofs" and o.has("auto") and o.get("auto")!=true)):
				if detail.is_empty():detail="%s %s owner/auto mismatch"%[key,layer]
	if not any:return "empty"
	return "complete" if detail.is_empty() else "partial: "+detail

func site_now() -> String:
	return site_state(snap())

func scope() -> String:
	# Mirrors Main._blueprint_address_scope for the address this client joins.
	if transport=="websocket":return "join:ws://127.0.0.1:%d|0"%port
	return "join:127.0.0.1|%d"%port

# ---------------------------------------------------------------- signals

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
	if (var_to_str(data)+"|"+id).contains(token) and violation.is_empty():violation="snapshot %d contains the raw profile token"%snapshots
	if data.has("construction") and violation.is_empty():violation="snapshot %d contains raw construction history"%snapshots
	if str(data.get("region_id",""))=="home":
		var state:=site_state(data)
		if state.begins_with("partial") and violation.is_empty():violation="snapshot %d shows a partial house: %s"%[snapshots,state]

func _on_applied(nonce:String,result:Dictionary) -> void:
	replies.append({"nonce":nonce,"result":result.duplicate(true)})
	if var_to_str(result).contains(token) and violation.is_empty():violation="apply result contains the raw profile token"
	print("BPR_APPLY %s nonce=%s ok=%s hash=%s"%[phase,nonce.left(8),str(result.get("ok")),str(result.get("hash","")).left(12)])

func _on_ctrl_changed() -> void:
	if ctrl==null or not pre_send.is_empty() or ctrl.mode!="submitting":return
	# Controller.confirm() emits `changed` after writing the pending file and
	# BEFORE calling Session.submit_blueprint, so this is the pre-send disk state.
	var path:=ctrl.pending_path()
	pre_send={"file":FileAccess.file_exists(path),"replies":replies.size(),
		"record":Pending.load_pending(path,scope(),World.BUILD,World.NAMES)}

func _on_ctrl_applied(result:Dictionary) -> void:
	ctrl_applied.append(result.duplicate(true))

func _on_ctrl_feedback(message:String,ok:bool) -> void:
	print("BPR_FEEDBACK %s ok=%s: %s"%[phase,str(ok),message])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("BPR_CHECK ok %s: %s"%[phase,label])
	else:finish(false,label)
	return ok

func mark(data:Dictionary) -> void:
	print("BPR_MARK "+JSON.stringify(data))

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

func finish(ok:bool,step:String) -> void:
	if finished:return
	finished=true
	if ok:print("BPR_PASS %s checks=%d snapshots=%d replies=%d"%[phase,checks,snapshots,replies.size()])
	else:push_error("BPR_FAIL %s after %d checks: %s | site=%s | inv=%s | mode=%s | violation=%s"%[phase,checks,step,
		site_now() if session!=null else "-",inv_text(),ctrl.mode if ctrl!=null else "-",violation])
	if ctrl!=null:ctrl.dispose()
	if session!=null:session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

# ---------------------------------------------------------------- entry

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=7 or not WATCHDOG.has(args[0]) or not args[1] in ["websocket","enet"]:
		push_error("BPR_FAIL usage: <submit|recover> <websocket|enet> <port> <room_key> <token> <library_path> <handoff_dir>")
		quit(2)
		return
	phase=args[0]
	transport=args[1]
	port=int(args[2])
	room_key=args[3]
	token=args[4]
	library_path=args[5]
	handoff=args[6]
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: %s exceeded %ds%s"%[phase,int(WATCHDOG[phase]),
		" (runner should have terminated this process)" if phase=="submit" else ""]))
	if not check(int(Session.PROTOCOL)==CONTRACT_PROTOCOL,"Session.PROTOCOL=%d (contract %d)"%[int(Session.PROTOCOL),CONTRACT_PROTOCOL]):return
	if not await connect_world():return
	match phase:
		"submit":await submit_phase()
		"recover":await recover_phase()

func connect_world() -> bool:
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	# Session._ready wrote a random profile into the runner's isolated APPDATA;
	# the fixture identity replaces it in memory only.
	session.profile.token=token
	session.changed.connect(_on_changed)
	session.blueprint_applied.connect(_on_applied)
	var address:="ws://127.0.0.1:%d"%port if transport=="websocket" else "127.0.0.1"
	if not check(session.join(address,port,"solo",room_key)==OK,"%s join request to 127.0.0.1:%d"%[transport,port]):return false
	var joined:bool=await until(func():return session.blueprint_welcomed and session.own_id==hid(token) and not me().is_empty(),JOIN_WAIT)
	if not check(joined,"registered and welcomed over %s (own id = hashed profile token)"%transport):return false
	ctrl=Controller.new()
	ctrl.name="Blueprints"
	island.add_child(ctrl)
	ctrl.changed.connect(_on_ctrl_changed)
	ctrl.applied.connect(_on_ctrl_applied)
	ctrl.feedback.connect(_on_ctrl_feedback)
	# Same call Main._blueprint_setup makes after connected_world.
	ctrl.setup(session,library_path,scope())
	var expected:=library_path+".pending-"+scope().sha256_text().left(16)+".json"
	return check(ctrl.pending_path()==expected,"Controller pending path is library + scope hash: %s"%expected.get_file())

# ---------------------------------------------------------------- submit phase

func submit_phase() -> void:
	var path:=ctrl.pending_path()
	if not check(ctrl.library_error.is_empty() and ctrl.entries.size()==1 and design_fp(ctrl.entries[0].design)==design_fp(house_raw()),
		"personal library loaded with the one fixture design"):return
	if not check(ctrl.mode=="idle" and ctrl.pending.is_empty() and ctrl.pending_error.is_empty() and not FileAccess.file_exists(path),
		"no pending record before confirm (mode %s)"%ctrl.mode):return
	await settle()
	if not check(site_now()=="empty" and ints(inventory())==start_inventory(),"site empty, exact seeded materials %s"%inv_text()):return
	var entry_id:=str(ctrl.entries[0].id)
	if not check(ctrl.choose(entry_id) and ctrl.mode=="placing","Controller.choose(entry) -> placing"):return
	if not check(ctrl.pin_origin(SITE) and ctrl.locked and ctrl.origin==SITE and ctrl.turns==0,"Controller.pin_origin(%s) locks and requests a quote"%k(SITE)):return
	var quoted:bool=await until(func():return not ctrl.quote_waiting and not ctrl.quote.is_empty(),RESULT_WAIT)
	var q:Dictionary=ctrl.quote
	if not check(quoted and q.get("ok")==true and ints(q.get("cost"))==house_cost() and int(q.get("roof_add",-1))==roof_count()
		and int(q.get("pieces",-1))==piece_count() and q.get("problems")==[] and Pending.lower_hex(q.get("hash"),64),
		"real authoritative quote ok, exact cost %s (+%d auto roofs): ok=%s cost=%s"%[JSON.stringify(house_cost()),roof_count(),str(q.get("ok")),JSON.stringify(q.get("cost"))]):return
	await settle()
	if not check(site_now()=="empty" and ints(inventory())==start_inventory(),"quote is read-only"):return
	var epoch:=own_epoch()
	if not check(ctrl.confirm(),"player confirms (Controller.confirm accepted the quote)"):return
	if not check(pre_send.get("file")==true and int(pre_send.get("replies",-1))==0 and (pre_send.get("record",{}) as Dictionary).get("ok")==true
		and (pre_send.record as Dictionary).get("missing")==false,"durable pending file existed BEFORE the submit RPC was sent"):return
	var loaded:Dictionary=Pending.load_pending(path,scope(),World.BUILD,World.NAMES)
	var rec:Dictionary=ctrl.pending.duplicate(true)
	if not check(loaded.get("ok")==true and loaded.get("missing")==false and loaded.record==rec and pre_send.record.record==rec,
		"pending file round-trips to Controller.pending"):return
	if not check(ctrl.mode=="submitting" and str(rec.actor)==session.own_id and str(rec.hash)==str(q.hash) and int(rec.origin.x)==SITE.x
		and int(rec.origin.y)==SITE.y and int(rec.turns)==0 and str(rec.region)=="home" and int(rec.epoch)==epoch and str(rec.scope)==scope()
		and Pending.lower_hex(rec.nonce,32) and design_fp(rec.design)==design_fp(house_raw()),
		"pending holds the fixed intent (nonce, quoted hash, origin, turns, home/epoch %d, scope, design)"%epoch):return
	if not check(not FileAccess.get_file_as_string(path).contains(token),"pending file holds no raw profile token"):return
	mark({"mark":"submitted","nonce":str(rec.nonce),"hash":str(rec.hash),"origin":[SITE.x,SITE.y],"turns":0,"region":str(rec.region),
		"epoch":int(rec.epoch),"actor":str(rec.actor),"scope":scope(),"design_fp":design_fp(rec.design),"entry_id":entry_id,
		"pending_path":path,"cost":house_cost(),"pieces":piece_count()})
	var built:bool=await until(func():return site_now()=="complete",RESULT_WAIT)
	if not check(built,"World commit is visible: snapshot shows the complete house"):return
	await settle()
	await settle()
	if not check(replies.is_empty() and ctrl_applied.is_empty(),"no apply result reached this client (reply lost before the client saw it)"):return
	if not check(ctrl.mode in ["submitting","unknown"] and ctrl.pending==rec and FileAccess.file_exists(path) and ctrl.busy(),
		"Controller still holds the pending record (mode %s), file on disk"%ctrl.mode):return
	if not check(ints(inventory())==final_inventory(),"snapshot shows exactly one charge: %s"%inv_text()):return
	if not check(violation.is_empty(),"%d snapshots: never partial, no raw token"%snapshots):return
	mark({"mark":"committed_unacked","nonce":str(rec.nonce),"mode":ctrl.mode,"replies":replies.size(),"snapshots":snapshots})
	print("BPR_AWAIT_TERMINATION submit: idle until the runner terminates this process (no retry, no further requests)")
	while not finished:
		await create_timer(0.1).timeout
		if not replies.is_empty():
			finish(false,"an apply result arrived after the injected lost reply")
			return
		if not FileAccess.file_exists(path):
			finish(false,"pending file disappeared while the result was unknown")
			return

# ---------------------------------------------------------------- recover phase

func read_intent() -> Dictionary:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("intent.json")))
	if not data is Dictionary:return {}
	for key in ["nonce","hash","actor","scope","design_fp","entry_id","pending_path","region"]:
		if not data.get(key) is String:return {}
	if not Pending.lower_hex(data.nonce,32) or not Pending.lower_hex(data.hash,64):return {}
	if not data.get("origin") is Array or (data.origin as Array).size()!=2:return {}
	for key in ["turns","epoch"]:
		if not (data.get(key) is int or data.get(key) is float):return {}
	return data

func recover_phase() -> void:
	var intent:=read_intent()
	if not check(not intent.is_empty(),"runner intent metadata (handoff/intent.json) is valid"):return
	var path:=ctrl.pending_path()
	if not check(path==str(intent.pending_path) and str(intent.scope)==scope() and FileAccess.file_exists(path),
		"same library + scope resolve to the surviving pending file"):return
	if not check(ctrl.library_error.is_empty() and ctrl.entries.size()==1 and str(ctrl.entries[0].id)==str(intent.entry_id)
		and design_fp(ctrl.entries[0].design)==str(intent.design_fp),"same personal library reloaded in the new process"):return
	var rec:Dictionary=ctrl.pending.duplicate(true)
	if not check(ctrl.pending_error.is_empty() and not rec.is_empty() and str(rec.nonce)==str(intent.nonce) and str(rec.hash)==str(intent.hash)
		and str(rec.actor)==str(intent.actor) and str(rec.actor)==session.own_id and str(rec.scope)==scope() and int(rec.origin.x)==int(intent.origin[0])
		and int(rec.origin.y)==int(intent.origin[1]) and int(rec.turns)==int(intent.turns) and str(rec.region)==str(intent.region)
		and int(rec.epoch)==int(intent.epoch) and design_fp(rec.design)==str(intent.design_fp),
		"pending record reloaded with the original nonce/intent/context/hash"):return
	if not check(ctrl.mode=="unknown" and ctrl.busy(),"mode is unknown after load (mode %s)"%ctrl.mode):return
	await settle()
	if not check(ctrl.mode=="unknown" and site_now()=="complete" and ints(inventory())==final_inventory(),
		"restarted world kept the committed house and one charge before any retry: %s %s"%[site_now(),inv_text()]):return
	if not check(not ctrl.choose(str(intent.entry_id)) and ctrl.mode=="unknown" and ctrl.draft.is_empty(),
		"new construction refused while the pending result is unknown"):return
	await create_timer(QUIET_WAIT).timeout
	if not check(replies.is_empty() and ctrl.mode=="unknown" and FileAccess.file_exists(path) and ints(inventory())==final_inventory(),
		"no automatic resend in %.0fs after load/connect"%QUIET_WAIT):return
	if not check(ctrl.retry_pending() and ctrl.mode=="submitting","player presses retry (Controller.retry_pending, same nonce)"):return
	var answered:bool=await until(func():return not replies.is_empty() and ctrl.mode!="submitting",RESULT_WAIT)
	if not check(answered and replies.size()==1 and ctrl_applied.size()==1,"exactly one result for the explicit retry (replies %d)"%replies.size()):return
	var r:Dictionary=replies[0].result
	if not check(str(replies[0].nonce)==str(intent.nonce) and r.get("ok")==true and str(r.get("hash",""))==str(intent.hash)
		and ints(r.get("cost"))==house_cost() and int(r.get("pieces",-1))==piece_count() and r.get("rate_limited")!=true,
		"retry returned the ORIGINAL receipt (same nonce/hash, exact cost, %d pieces)"%piece_count()):return
	if not check(ctrl.mode=="idle" and ctrl.pending.is_empty() and ctrl.pending_error.is_empty() and not FileAccess.file_exists(path),
		"Controller cleared the pending file and returned to idle"):return
	await settle()
	await create_timer(QUIET_WAIT).timeout
	if not check(replies.size()==1 and not FileAccess.file_exists(path) and ctrl.pending.is_empty() and ctrl.mode=="idle",
		"pending not recreated and nothing resubmitted in %.0fs"%QUIET_WAIT):return
	if not check(ints(inventory())==final_inventory() and site_now()=="complete","exact materials charged once, complete house preserved: %s"%inv_text()):return
	ctrl.setup(session,library_path,scope())
	if not check(ctrl.pending.is_empty() and ctrl.pending_error.is_empty() and ctrl.mode=="idle" and not FileAccess.file_exists(path),
		"re-running setup for the same scope finds no pending record"):return
	if not check(ctrl.choose(str(intent.entry_id)) and ctrl.mode=="placing" and ctrl.cancel() and ctrl.mode=="idle" and replies.size()==1,
		"construction unblocked (choose then cancel; nothing submitted)"):return
	if not check(violation.is_empty(),"%d snapshots: never partial, no raw token"%snapshots):return
	mark({"mark":"recovered","nonce":str(intent.nonce),"replies":replies.size()})
	finish(true,"")

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=4:
		push_error("BPR_SEED_FAIL usage: seed <world.json> <token> <library_path>")
		quit(2)
		return
	token=args[2]
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	var cells:=site_cells()
	var solids:Array=[]
	for key in cells:
		var c:=World.cell(key)
		if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c)!="":
			problems.append("cell %s is not clear buildable home land"%key)
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(key):problems.append("cell %s already used in %s"%[key,layer])
		if str(cells[key].get("objects",""))!="":solids.append(Vector2(c)+Vector2(0.5,0.5))
	world.add_player(token,"solo")
	var person:Dictionary=world.state.players[token]
	person.x=STAND.x
	person.y=STAND.y
	person.inventory=start_inventory().duplicate(true)
	if not world.can_stand(STAND):problems.append("player cannot stand at %s"%STAND)
	if STAND.distance_to(Vector2(SITE)+Vector2(0.5,0.5))>float(World.BLUEPRINT_RANGE)-0.05:problems.append("stand is out of blueprint range")
	for solid:Vector2 in solids:
		if STAND.distance_to(solid)<CLEARANCE+0.1:problems.append("stand within clearance of %s"%solid)
	var entry_id:=Crypto.new().generate_random_bytes(16).hex_encode()
	var lib:Dictionary=Library.save_library(args[3],[{"id":entry_id,"design":house_raw()}],World.BUILD,World.NAMES)
	if lib.get("ok")!=true:problems.append("library not saved: "+str(lib.get("reason","")))
	if not problems.is_empty():
		for problem in problems:push_error("BPR_SEED_FAIL "+problem)
		quit(1)
		return
	print("BPR_FIXTURE "+JSON.stringify({"site":[SITE.x,SITE.y],"cells":cells,"cost":house_cost(),"start":start_inventory(),
		"final":final_inventory(),"pieces":piece_count(),"roofs":roof_count(),"entry_id":entry_id,"design_fp":design_fp(house_raw()),
		"seed_version":int(world.state.version),"protocol":int(Session.PROTOCOL)}))
	quit(0 if world.save() else 1)
