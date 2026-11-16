extends SceneTree
## Real ENet validation of construction undo (world save schema 18 / network protocol 36).
##
## AUTHORIZED LOCAL FIXTURE: `seed` writes exact test materials and two player
## positions straight into a temporary save. It proves the networked
## build/undo/refund/persistence wiring only; it is NOT evidence of natural play.
##
## Driven by work/house-rooms/network_construction_undo.py. Args (after `--`):
##   seed <world.json> <alpha_token> <beta_token>
##        Writes the fixture save and prints `UNDO_FIXTURE {json}`.
##   <phase> <port> <role> <room_key> <alpha_token> <beta_token> <ref_id> <ref_unix>
##     contest   alpha + beta together on server-1.
##               alpha builds floor F; beta puts a chest on F; alpha's undo of F is
##               denied inside the 30 s window (nothing changes). alpha then
##               build_areas the independent 2-tile floor G, undoes it (both clients
##               see the removal, alpha gets exactly the refund) and repeats the same
##               undo id as a NEW request -> denied, no change. alpha prints
##               `UNDO_MARK {"mark":"g",...}`; beta waits for alpha to leave.
##     reconnect alpha alone on server-1, still within G's 30 s window: same summary id,
##               consumed (available=false), repeat undo denied, no new refund.
##     expiry    alpha alone on a freshly restarted server-2, >30 s after G: undo of G
##               denied with no extra refund after expiry. Then builds floor H, undoes
##               it, prints `UNDO_MARK {"mark":"h",...}` and leaves at once.
##     persist   server-3 (fast restart after server-2's normal stop). alpha first,
##               still inside H's 30 s window: summary still shows H consumed, repeat
##               undo denied, no refund; prints `UNDO_MARK {"mark":"persist_checked"}`
##               and waits for beta. beta then verifies the persisted layers/inventory.
## Every snapshot is checked: no `construction` key (or any other construction key
## than own_construction_undo), summary has exactly the 6 safe fields, and no raw
## profile token appears in any snapshot or notice.
## Output: `UNDO_CHECK ok ...` per check, `UNDO_ENET_PASS ...` or `UNDO_ENET_FAIL ...`.
## All waits have deadlines plus a global watchdog. Times use the real UTC clock
## (Time.get_unix_time_from_system); nothing fakes the server clock.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")

# Clear home land (x46..51, y22..29 has no base resources; see network_auto_roof.gd).
const F:=Vector2i(48,24)                     # alpha floor, beta chest on top
const G0:=Vector2i(49,27)                    # alpha build_area floor G0..G1
const G1:=Vector2i(50,27)
const G_EXTRA:="floor|50|27"
const H:=Vector2i(47,27)                     # alpha floor on server-2
const STAND:={"alpha":Vector2(48.5,26.0),"beta":Vector2(50.5,24.5)}
const TARGETS:={"alpha":[F,G0,G1,H],"beta":[F]}
const PHASES:={"contest":["alpha","beta"],"reconnect":["alpha"],"expiry":["alpha"],"persist":["alpha","beta"]}
const SUMMARY_KEYS:=["available","id","label","reason","region","seconds_left"]
# Floors alpha has paid for (net) at each stage; beta's chest count.
const ALPHA_FLOORS:={"start":4,"f":3,"g":1,"undone":3,"h":2,"final":3}
const BETA_CHESTS:={"start":1,"chest":0}
const WINDOW:=30.0
const REACH:=3.2
const CLEARANCE:=0.8
const WATCHDOG:=60.0
const JOIN_WAIT:=15.0
const ACTION_WAIT:=8.0
const PEER_WAIT:=40.0

var session:Session
var phase:=""
var role:=""
var tokens:={}
var ref_id:=""
var ref_unix:=0.0
var notices:Array=[]
var snapshots:=0
var seen_both:=false
var first:Dictionary={}
var view:Dictionary={}
var violation:=""
var checks:=0
var finished:=false

func _initialize() -> void:
	run.call_deferred()

# ---------------------------------------------------------------- helpers

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

static func hid(token:String) -> String:
	return token.sha256_text().left(16)

static func now() -> float:
	return Time.get_unix_time_from_system()

static func tracked() -> Array:
	var items:={}
	for recipe:Dictionary in [World.BUILD.floor,World.BUILD.chest]:
		for item in recipe:
			if item!="name":items[item]=true
	var out:=items.keys()
	out.sort()
	return out

static func expected(who:String,stage:String) -> Dictionary:
	var out:={}
	for item in tracked():
		if who=="alpha":out[item]=int(World.BUILD.floor.get(item,0))*int(ALPHA_FLOORS[stage])
		else:out[item]=int(World.BUILD.chest.get(item,0))*int(BETA_CHESTS[stage])
	return out

func snap() -> Dictionary:
	if not view.is_empty():return view
	return session.snapshot if session!=null else {}

func who_is(owner:String) -> String:
	for who in tokens:
		if owner==hid(tokens[who]):return who
	return "unknown" if not owner.is_empty() else ""

func population() -> int:
	return snap().get("players",{}).size()

func inventory() -> Dictionary:
	return snap().get("players",{}).get(session.own_id,{}).get("inventory",{})

func others_of(inv:Dictionary) -> Dictionary:
	var out:=inv.duplicate(true)
	for item in tracked():out.erase(item)
	return out

func inv_is(stage:String) -> bool:
	var want:=expected(role,stage)
	var have:=inventory()
	for item in want:
		if int(have.get(item,0))!=int(want[item]):return false
	return true

func inv_text(stage:String="") -> String:
	var parts:=PackedStringArray()
	var have:Dictionary=inventory() if session!=null else {}
	for item in tracked():
		var text:="%s=%d"%[item,int(have.get(item,0))]
		if not stage.is_empty():text+="/want %d"%int(expected(role,stage)[item])
		parts.append(text)
	return " ".join(parts)

func owner_at(p:Vector2i,kind:String,layer:String) -> String:
	var o=snap().get(layer,{}).get(k(p))
	if not o is Dictionary or str(o.get("type",""))!=kind:return ""
	return who_is(str(o.get("owner","")))

func empty_at(p:Vector2i) -> bool:
	for layer in ["ground","objects","roofs"]:
		if snap().get(layer,{}).has(k(p)):return false
	return true

func g_built() -> bool:
	return owner_at(G0,"floor","ground")=="alpha" and owner_at(G1,"floor","ground")=="alpha"

func g_gone() -> bool:
	return empty_at(G0) and empty_at(G1)

## F holds alpha's floor with beta's chest on top.
func contested() -> bool:
	return owner_at(F,"floor","ground")=="alpha" and owner_at(F,"chest","objects")=="beta"

func layout() -> String:
	if session==null:return "no session"
	var parts:=PackedStringArray()
	for p:Vector2i in [F,G0,G1,H]:
		var cell:=PackedStringArray()
		for layer in ["ground","objects","roofs"]:
			var o=snap().get(layer,{}).get(k(p))
			if o is Dictionary:cell.append("%s:%s:%s"%[layer,str(o.get("type","")),who_is(str(o.get("owner","")))])
		parts.append("%s[%s]"%[k(p),",".join(cell)])
	return " ".join(parts)

func undo_info() -> Dictionary:
	var s=snap().get("own_construction_undo",{})
	return s if s is Dictionary else {}

func undo_id() -> String:
	var id=undo_info().get("id","")
	return id if id is String else ""

func undo_available() -> bool:
	var a=undo_info().get("available")
	return typeof(a)==TYPE_BOOL and a

func seconds_left() -> float:
	var s=undo_info().get("seconds_left")
	return float(s) if typeof(s) in [TYPE_INT,TYPE_FLOAT] else -1.0

## A fresh, undoable own record different from `previous`.
func fresh_record(previous:String) -> bool:
	var id:=undo_id()
	return undo_available() and not id.is_empty() and id!=previous and str(undo_info().get("region",""))=="home" \
		and seconds_left()>0.0 and seconds_left()<=WINDOW+0.5

func consumed(id:String) -> bool:
	return undo_id()==id and not undo_available()

func summary_text() -> String:
	return JSON.stringify(undo_info())

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("UNDO_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func until(predicate:Callable,seconds:float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if finished:return false
		if predicate.call():return true
		await create_timer(0.05).timeout
	return not finished and predicate.call()

## Real Session.perform; waits for this action's receipt and then two further
## snapshots so the post-action broadcast has been applied.
func act(action:String,p:Vector2i,extra:String) -> Dictionary:
	var index:=notices.size()
	session.perform(action,p,extra)
	var answered:bool=await until(func():return notices.size()>index,ACTION_WAIT)
	if not answered:return {"ok":false,"message":"<no receipt within %ds>"%int(ACTION_WAIT),"timeout":true}
	var mark:=snapshots
	await until(func():return snapshots>=mark+2,ACTION_WAIT)
	return notices[index]

func denied(result:Dictionary) -> bool:
	return not result.ok and not result.has("timeout")

func within(since:float) -> bool:
	return now()-since<WINDOW

func age(since:float) -> String:
	return "%.1fs"%(now()-since)

func mark(data:Dictionary) -> void:
	print("UNDO_MARK "+JSON.stringify(data))

func _summary_problem(own:Variant) -> String:
	if not own is Dictionary:return "own_construction_undo missing or not a Dictionary"
	var keys:Array=own.keys()
	keys.sort()
	if keys!=SUMMARY_KEYS:return "own_construction_undo fields %s != %s"%[str(keys),str(SUMMARY_KEYS)]
	for field in ["id","label","reason","region"]:
		if not own[field] is String:return "own_construction_undo.%s is not a String"%field
	if typeof(own.available)!=TYPE_BOOL:return "own_construction_undo.available is not a bool"
	if typeof(own.seconds_left) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(own.seconds_left)) or float(own.seconds_left)<0.0:
		return "own_construction_undo.seconds_left is not a finite non-negative number"
	return ""

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
	if first.is_empty():first=data.duplicate(true)
	if violation.is_empty():
		if data.has("construction"):violation="snapshot %d contains raw state.construction"%snapshots
		for field in data.keys():
			if String(field).contains("construction") and field!="own_construction_undo":
				violation="snapshot %d has extra construction field %s"%[snapshots,field]
		var problem:=_summary_problem(data.get("own_construction_undo"))
		if not problem.is_empty():violation="snapshot %d: %s"%[snapshots,problem]
		var text:=JSON.stringify(data)+"|"+id
		for who in tokens:
			if text.contains(tokens[who]):violation="snapshot %d contains raw %s token"%[snapshots,who]
	if data.get("players",{}).size()==2:seen_both=true

func _on_notice(message:String,ok:bool) -> void:
	notices.append({"ok":ok,"message":message})
	for who in tokens:
		if message.contains(tokens[who]) and violation.is_empty():violation="result text contains raw %s token"%who
	print("UNDO_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func finish(ok:bool,step:String) -> void:
	if finished:return
	finished=true
	if ok:print("UNDO_ENET_PASS %s %s checks=%d snapshots=%d notices=%d"%[phase,role,checks,snapshots,notices.size()])
	else:push_error("UNDO_ENET_FAIL %s %s after %d checks: %s | %s | %s | undo=%s"%[phase,role,checks,step,layout(),inv_text(),summary_text() if session!=null else "{}"])
	if session!=null:session.shutdown()
	# Let ENet flush the disconnect so the server sees this player leave promptly.
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

# ---------------------------------------------------------------- entry

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=8 or not PHASES.has(args[0]) or not (args[2] in PHASES[args[0]]) or not args[7].is_valid_float():
		push_error("UNDO_ENET_FAIL usage: <phase> <port> <role> <room_key> <alpha_token> <beta_token> <ref_id> <ref_unix>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	tokens={"alpha":args[4],"beta":args[5]}
	ref_id=args[6] if args[6]!="-" else ""
	ref_unix=float(args[7])
	create_timer(WATCHDOG).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG)))
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=tokens[role]
	session.changed.connect(_on_changed)
	session.notice.connect(_on_notice)
	if session.join("127.0.0.1",int(args[1]),role,args[3])!=OK:
		finish(false,"ENet join request")
		return
	var joined:bool=await until(func():return not session.own_id.is_empty() and snap().get("players",{}).has(session.own_id),JOIN_WAIT)
	if not check(joined,"registered over ENet with protocol %d and the room key"%Session.PROTOCOL):return
	if not check(session.own_id==hid(tokens[role]),"own id is the hashed stable profile token"):return
	match phase:
		"contest":
			if role=="alpha":await contest_alpha()
			else:await contest_beta()
		"reconnect":await reconnect_alpha()
		"expiry":await expiry_alpha()
		"persist":
			if role=="alpha":await persist_alpha()
			else:await persist_beta()
	if finished:return
	if not check(violation.is_empty(),"%d snapshots: no raw construction state, summary has exactly %s, no raw tokens in %d notices"%[snapshots,str(SUMMARY_KEYS),notices.size()]):return
	finish(true,"")

# ---------------------------------------------------------------- phases

func verify_fixture() -> bool:
	view=first
	var ok:=check(empty_at(F) and empty_at(G0) and empty_at(G1) and empty_at(H),"fixture cells start empty: %s"%layout()) \
		and check(inv_is("start"),"%s starts with exact fixture materials: %s"%[role,inv_text("start")])
	view={}
	return ok

func contest_alpha() -> void:
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are connected simultaneously"):return
	if not verify_fixture():return
	var others:=others_of(inventory())
	# --- F: built, then made dependent by beta's chest -> undo denied in-window.
	var r:Dictionary=await act("build",F,"floor")
	var f_unix:=now()
	if not check(r.ok,"alpha builds floor F %s: \"%s\""%[k(F),r.message]):return
	if not check(owner_at(F,"floor","ground")=="alpha" and inv_is("f"),"floor F owned by alpha, paid exactly: %s"%inv_text("f")):return
	# Beta can legitimately place its chest before Alpha processes its own build
	# reply. Capture the record id even when that dependency already invalidated it.
	var recorded:bool=await until(func():return not undo_id().is_empty(),ACTION_WAIT)
	if not check(recorded,"own summary identifies F construction: %s"%summary_text()):return
	var f_id:=undo_id()
	var chest:bool=await until(func():return contested(),PEER_WAIT)
	if not check(chest,"alpha sees beta's chest on its floor F: %s"%layout()):return
	if not check(within(f_unix),"still inside F's 30 s window before undo attempt (age %s)"%age(f_unix)):return
	r=await act("undo_build",F,f_id)
	if not check(denied(r),"undo of F denied after beta's dependent chest: \"%s\""%r.message):return
	if not check(str(r.message).contains("變動") or str(r.message).contains("使用"),"denied for dependency, not missing record or time"):return
	if not check(within(f_unix),"denial happened inside the window, so it was not expiry (age %s)"%age(f_unix)):return
	if not check(contested() and inv_is("f") and others_of(inventory())==others,"denied undo changed nothing: %s %s"%[layout(),inv_text("f")]):return
	# --- G: independent area build, undo succeeds.
	r=await act("build_area",G0,G_EXTRA)
	var g_unix:=now()
	if not check(r.ok,"alpha build_area floor G %s..%s: \"%s\""%[k(G0),k(G1),r.message]):return
	if not check(g_built() and inv_is("g"),"G floors owned by alpha, paid exactly: %s"%inv_text("g")):return
	recorded=await until(func():return fresh_record(f_id),ACTION_WAIT)
	if not check(recorded,"own summary now offers undo of G (new id): %s"%summary_text()):return
	var g_id:=undo_id()
	r=await act("undo_build",G0,g_id)
	if not check(r.ok,"alpha undoes G via Session.perform('undo_build'): \"%s\""%r.message):return
	if not check(within(g_unix),"undo of G completed inside its window (age %s)"%age(g_unix)):return
	var gone:bool=await until(func():return g_gone(),ACTION_WAIT)
	if not check(gone,"G floors removed: %s"%layout()):return
	if not check(inv_is("undone") and others_of(inventory())==others,"alpha refunded exactly %d floors: %s"%[ALPHA_FLOORS.undone-ALPHA_FLOORS.g,inv_text("undone")]):return
	if not check(contested(),"F floor and beta's chest untouched by G's undo: %s"%layout()):return
	var used:bool=await until(func():return consumed(g_id),ACTION_WAIT)
	if not check(used,"summary keeps G's id and marks it consumed: %s"%summary_text()):return
	# --- duplicate: same id as a NEW request (fresh sequence/request id).
	r=await act("undo_build",G0,g_id)
	if not check(denied(r),"repeat undo of G (new request, same id) denied: \"%s\""%r.message):return
	if not check(g_gone() and contested() and inv_is("undone") and others_of(inventory())==others,"repeat undo changed nothing, no second refund: %s %s"%[layout(),inv_text("undone")]):return
	check(within(g_unix),"duplicate denial inside G's window (age %s)"%age(g_unix))
	mark({"mark":"g","id":g_id,"unix":g_unix})

func contest_beta() -> void:
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are connected simultaneously"):return
	if not verify_fixture():return
	var floored:bool=await until(func():return owner_at(F,"floor","ground")=="alpha",PEER_WAIT)
	if not check(floored,"beta sees alpha's floor F"):return
	var r:Dictionary=await act("build",F,"chest")
	if not check(r.ok,"beta puts a chest on alpha's floor F: \"%s\""%r.message):return
	if not check(contested() and inv_is("chest"),"chest owned by beta, paid exactly: %s"%inv_text("chest")):return
	var baseline:=inventory().duplicate(true)
	var built:bool=await until(func():return g_built(),PEER_WAIT)
	if not check(built,"beta sees alpha's G floors: %s"%layout()):return
	var gone:bool=await until(func():return g_gone(),PEER_WAIT)
	if not check(gone,"beta sees alpha's undo remove G: %s"%layout()):return
	if not check(contested() and inventory()==baseline,"beta's chest and inventory unaffected by alpha's undo: %s"%inv_text("chest")):return
	var left:bool=await until(func():return population()==1,PEER_WAIT)
	if not check(left,"alpha disconnected after its duplicate attempt"):return
	check(g_gone() and contested() and inventory()==baseline,"state unchanged after alpha left: %s"%layout())

func reconnect_alpha() -> void:
	var alone:bool=await until(func():return population()==1,PEER_WAIT)
	if not check(alone,"beta is offline (snapshot lists only alpha)"):return
	if not check(within(ref_unix),"reconnected inside G's 30 s window (age %s)"%age(ref_unix)):return
	if not check(consumed(ref_id),"after reconnect the summary shows the same G id, consumed: %s"%summary_text()):return
	if not check(g_gone() and contested() and inv_is("undone"),"reconnect sees G removed, no new refund: %s %s"%[layout(),inv_text("undone")]):return
	var others:=others_of(inventory())
	var r:Dictionary=await act("undo_build",G0,ref_id)
	if not check(denied(r),"undo of consumed G after reconnect denied: \"%s\""%r.message):return
	if not check(within(ref_unix),"reconnect denial inside G's window (age %s)"%age(ref_unix)):return
	check(g_gone() and contested() and inv_is("undone") and others_of(inventory())==others,"no change, no new refund: %s %s"%[layout(),inv_text("undone")])

func expiry_alpha() -> void:
	if not check(not within(ref_unix),"G's 30 s window has expired (age %s)"%age(ref_unix)):return
	if not check(g_gone() and contested() and inv_is("undone"),"restart kept G removed, F+chest and alpha's refunded inventory: %s %s"%[layout(),inv_text("undone")]):return
	if not check(undo_id()!=ref_id or not undo_available(),"expired/consumed G is not offered: %s"%summary_text()):return
	var others:=others_of(inventory())
	var r:Dictionary=await act("undo_build",G0,ref_id)
	if not check(denied(r),"undo of G after expiry denied: \"%s\""%r.message):return
	if not check(g_gone() and contested() and inv_is("undone") and others_of(inventory())==others,"no extra refund after expiry: %s"%inv_text("undone")):return
	r=await act("build",H,"floor")
	var h_unix:=now()
	if not check(r.ok,"alpha builds floor H %s: \"%s\""%[k(H),r.message]):return
	if not check(owner_at(H,"floor","ground")=="alpha" and inv_is("h"),"H owned by alpha, paid exactly: %s"%inv_text("h")):return
	var recorded:bool=await until(func():return fresh_record(ref_id),ACTION_WAIT)
	if not check(recorded,"own summary offers undo of H: %s"%summary_text()):return
	var h_id:=undo_id()
	r=await act("undo_build",H,h_id)
	if not check(r.ok,"alpha undoes H: \"%s\""%r.message):return
	var gone:bool=await until(func():return empty_at(H),ACTION_WAIT)
	if not check(gone and inv_is("undone") and others_of(inventory())==others,"H removed and exactly refunded: %s %s"%[layout(),inv_text("undone")]):return
	var used:bool=await until(func():return consumed(h_id),ACTION_WAIT)
	if not check(used,"summary marks H consumed: %s"%summary_text()):return
	check(within(h_unix),"H build + undo inside its window (age %s)"%age(h_unix))
	mark({"mark":"h","id":h_id,"unix":h_unix})

func persist_alpha() -> void:
	if not check(within(ref_unix),"fast restart: rejoined inside H's 30 s window (age %s)"%age(ref_unix)):return
	if not check(consumed(ref_id),"restart kept H's history as consumed (same id, unavailable): %s"%summary_text()):return
	if not check(empty_at(H) and g_gone() and contested() and inv_is("final"),"restart kept H/G removed, F+chest, no refund change: %s %s"%[layout(),inv_text("final")]):return
	var others:=others_of(inventory())
	var r:Dictionary=await act("undo_build",H,ref_id)
	if not check(denied(r),"undo of H after restart denied: \"%s\""%r.message):return
	var in_window:=within(ref_unix)
	if not check(in_window,"restart denial still inside H's window, so persisted consumption (not expiry) applies (age %s)"%age(ref_unix)):return
	if not check(empty_at(H) and inv_is("final") and others_of(inventory())==others,"no duplicate refund after restart: %s %s"%[layout(),inv_text("final")]):return
	mark({"mark":"persist_checked","age":now()-ref_unix})
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"beta joined the restarted server alongside alpha"):return
	var left:bool=await until(func():return population()==1,PEER_WAIT)
	check(left and empty_at(H) and inv_is("final"),"beta left; alpha state unchanged: %s"%inv_text("final"))

func persist_beta() -> void:
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta online together after restart"):return
	# Joining immediately gives Beta a two-peer snapshot; Alpha's periodic update
	# may not run before Beta exits. A harmless rejected request forces a reliable
	# broadcast to BOTH peers, instead of relying on an arbitrary sleep.
	var sync_result:Dictionary=await act("undo_build",F,"presence-only")
	if not check(denied(sync_result),"presence barrier cannot change construction"):return
	check(contested() and g_gone() and empty_at(H) and inv_is("chest"),"beta sees persisted F floor (alpha) + chest (beta), G/H removed, own inventory exact: %s %s"%[layout(),inv_text("chest")])

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=4:
		push_error("UNDO_SEED_FAIL usage: seed <world.json> <alpha_token> <beta_token>")
		quit(2)
		return
	tokens={"alpha":args[2],"beta":args[3]}
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	for p:Vector2i in [F,G0,G1,H]:
		if not world.is_land(p) or world.water(p) or world.protected(p) or world.blocked(p) or world.resource(p)!="":
			problems.append("cell %s is not buildable home land"%k(p))
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(k(p)):problems.append("cell %s already used in %s"%[k(p),layer])
	for who in ["alpha","beta"]:
		world.add_player(tokens[who],who)
		var person:Dictionary=world.state.players[tokens[who]]
		var spot:Vector2=STAND[who]
		person.x=spot.x
		person.y=spot.y
		var start:=expected(who,"start")
		for item in start:person.inventory[item]=int(start[item])
		if not world.can_stand(spot):problems.append("%s cannot stand at %s"%[who,spot])
		for target:Vector2i in TARGETS[who]:
			var d:=spot.distance_to(Vector2(target)+Vector2(0.5,0.5))
			if d>REACH:problems.append("%s is %.2f from %s (reach %.1f)"%[who,d,k(target),REACH])
		# Beta's chest on F requires nobody standing on it.
		if spot.distance_to(Vector2(F)+Vector2(0.5,0.5))<CLEARANCE:problems.append("%s would occupy chest cell %s"%[who,k(F)])
	if not problems.is_empty():
		for problem in problems:push_error("UNDO_SEED_FAIL "+problem)
		quit(1)
		return
	var fixture:={"f":k(F),"g":[k(G0),k(G1)],"g_extra":G_EXTRA,"h":k(H),"tracked":tracked(),
		"floor_recipe":World.BUILD.floor,"chest_recipe":World.BUILD.chest,
		"start":{"alpha":expected("alpha","start"),"beta":expected("beta","start")},
		"final":{"alpha":expected("alpha","final"),"beta":expected("beta","chest")},
		"seed_version":int(world.state.version)}
	print("UNDO_FIXTURE "+JSON.stringify(fixture))
	quit(0 if world.save() else 1)
