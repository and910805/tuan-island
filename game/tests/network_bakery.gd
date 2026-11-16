extends SceneTree
## Real multi-process network regression of the Q05 bakery (protocol 43 / save
## 24: flour mill, input_wheat buffer, pumpkin_pie) over plain loopback
## WebSocket (ws://127.0.0.1:<port>; NOT wss/TLS, NOT cloud, no adverse-network
## model). Every mutation goes client Session.perform -> request_action RPC ->
## SEPARATE dedicated Godot server -> World.act. No client ever touches a World;
## acknowledgements are the correlated action_completed(sequence) replies, never
## notices.
##
## SEEDED NETWORK FIXTURE - NOT AN EARNED JOURNEY. The `seed` step is the ONLY
## direct state write (labelled, printed in BK_FIXTURE.seeded):
##   picnic          board=true, picnic_materials soup2/bread1, picnic=true
##   table           community.table = 39,30
##   kitchen_site    alpha: stove (41,34) + long_bench (42,36),(43,35)
##   kitchen_opened  public_kitchen = registered on that site with every meal at
##                   its SaveSchema cap and opened=true (schema-valid, reloaded)
##   mill            alpha-owned mill on a naturally clear cell within reach of
##                   both stand positions (searched, deterministic), auto off
##   input_wheat     mill.input_wheat = 4 (buffer; never consumed by manual jobs)
##   chest           shared chest adjacent to the mill, owner alpha, {wheat 1}
##   positions       alpha (39.5,35.5), beta (39.5,33.5) = World.SPAWN
##   inventories     alpha {wheat 3, pumpkin 1, egg 1}; beta {wheat 4}
## The saved fixture is reloaded through World.load_world (SaveSchema) before
## the runner continues. Tokens come from the BK_TOKENS environment variable and
## the room key from BK_ROOM_KEY, never from the command line, and are never
## printed.
##
## Driven by work/bakery-network/network_bakery.py. Args after `--`:
##   seed <world.json>                          -> BK_FIXTURE {json}
##   <live|restart> <port> <role> <handoff_dir>
## Barriers: client prints `BK_BARRIER <phase> <role> <name>` and waits for
## <handoff>/go-<phase>-<name> (written by the runner once every role of the
## phase printed it). Missing barrier/result = failure, never a skip.
##
## live (alpha = mill/kitchen-site owner, beta = guest). The runner starts this
##   server with Godot `--time-scale N` (LABELLED FIXTURE: accelerated world
##   clock on the dedicated server process only; no game code is changed):
##   seeded       exact backpacks, opened kitchen, mill/input_wheat/chest exact,
##                bread/flour/pie catalog values (bread unchanged).
##   guest        beta queue_processing / prepare_material_box / feed_processing
##                on alpha's mill -> refused, nothing debited or changed.
##   owner queue  alpha queue_processing flour (wheat -2), early claim refused
##                ("加工尚未完成"), raw replay of the SAME request_action
##                sequence (labelled; not Session.perform) dropped: no
##                completion, no notice, no second charge; prepare the shared
##                chest and enqueue a sourced flour job (1 backpack + 1 chest).
##   guest claim  beta claim_processing while flour is ready -> refused.
##   claim        alpha claims flour once the 60 world-second job is ready;
##                reports real vs world seconds (accelerated clock evidence).
##   bread        beta queue_cook bread (wheat 2 -> bread 1, 15 s) + claim.
##   pie          alpha queue_cook pumpkin_pie on the shared public stove.
##   race         both claim_cook the ready pie at one barrier: exactly one gets
##                4 pumpkin_pie, the other "石灶現在沒有料理" with no change.
##   final        second (sourced) flour job ready in the public mill queue.
## restart (normal --quit-after stop + restart on the same save, real clock;
##   alpha, beta reconnect, never-seen gamma joins late): exact persisted
##   backpacks, kitchen, mill input_wheat and public queue (ready flour owned by
##   alpha's public id); gamma's claim refused; alpha claims the persisted flour.
## Every snapshot: no raw token, no foreign inventory/receipts.
## Output: BK_CHECK ok ..., BK_COVER <tag> <phase> <role>, BK_MARK {json},
## BK_WS_PASS / BK_WS_FAIL.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const PK=preload("res://scripts/public_kitchen.gd")
const Sources=preload("res://scripts/material_sources.gd")
const Supply=preload("res://scripts/material_supply.gd")

const CONTRACT_PROTOCOL:=45
const CONTRACT_SAVE:=26
const SEED_LABEL:="SEEDED NETWORK FIXTURE (game/tests/network_bakery.gd seed) - not an earned journey"
const SEEDED:=["picnic","table","kitchen_site","kitchen_opened","mill","input_wheat","chest","positions","inventories"]
const TABLE:=Vector2i(39,30)
const STOVE:=Vector2i(41,34)
const SEATS:=[Vector2i(42,36),Vector2i(43,35)]
const STAND:={"alpha":Vector2(39.5,35.5),"beta":Vector2(39.5,33.5)}
const SEED_INV:={"alpha":{"wheat":3,"pumpkin":1,"egg":1},"beta":{"wheat":4}}
const SEED_CHEST:={"wheat":1}
const SEED_INPUT_WHEAT:=4
const FLOUR_TIME:=60.0
const FLOUR_COST:={"wheat":2}
const PIE_TIME:=120.0
const PIE_YIELD:=4
const PIE_COST:={"pumpkin":1,"flour":1,"egg":1}
const BREAD:={"name":"小麥麵包","ingredients":{"wheat":2},"time":15.0,"yield":1}
const NEIGHBOURS:=[Vector2i(0,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1)]
const PHASE_ROLES:={"live":["alpha","beta"],"restart":["alpha","beta","gamma"]}
const WATCHDOG:={"live":55.0,"restart":25.0}
const JOIN_WAIT:=15.0
const RESULT_WAIT:=8.0
const PEER_WAIT:=15.0
const BARRIER_WAIT:=40.0
const FLOUR_WAIT:=25.0
const COOK_WAIT:=30.0
const DROP_WAIT:=2.0
const ACTION_BUDGET:=9
const ACTION_WINDOW_MSEC:=1100
const MSG_NOT_OWN_PROCESSOR:="只能使用自己的加工設備"
const MSG_NOT_OWN_DEVICE:="只能操作自己的設備"
const MSG_STOVE_EMPTY:="石灶現在沒有料理"
const MSG_NOT_READY_PREFIX:="加工尚未完成"

var session:Session
var phase:=""
var role:=""
var roles:Array=[]
var tokens:={}
var handoff:=""
var fixture:Dictionary={}
var plan:Dictionary={}
var notices:Array=[]
var sent:Dictionary={}
var completed:Dictionary={}
var sends:Array=[]
var snapshots:=0
var home_snapshots:=0
var online_max:=0
var violation:=""
var checks:=0
var finished:=false
var expect_inv:Dictionary={}
var mill_cell:=Vector2i(-1,-1)
var chest_cell:=Vector2i(-1,-1)

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

static func plain(a:Variant) -> Array:
	var out:=[]
	if a is Array:
		for v in a:out.append(str(v))
	return out

static func hex(value:Variant,size:int) -> bool:
	if not value is String or (value as String).length()!=size:return false
	for c in (value as String):
		if not "0123456789abcdef".contains(c):return false
	return true

static func norm_kitchen(pk:Variant) -> Dictionary:
	if not pk is Dictionary:return {"<missing>":true}
	var meals:={}
	if pk.get("meals") is Dictionary:
		for m in pk.meals:meals[str(m)]=int(pk.meals[m])
	return {"stove":str(pk.get("stove","<none>")),"seats":plain(pk.get("seats")),"meals":meals,"opened":pk.get("opened")==true,
		"keys":int(pk.get("keys",(pk.keys() as Array).size()))}

static func seeded_kitchen() -> Dictionary:
	var meals:={}
	for m in SaveSchema.KITCHEN_MEALS:meals[str(m)]=int(SaveSchema.KITCHEN_MEALS[m])
	return {"stove":k(STOVE),"seats":[k(SEATS[0]),k(SEATS[1])],"meals":meals,"opened":true,"keys":4}

static func queue_records(q:Variant) -> Array:
	var out:=[]
	if not q is Dictionary:return out
	var a=q.get("active")
	if a is Dictionary and not (a as Dictionary).is_empty():out.append({"lane":"active","rec":a})
	for lane in ["waiting","ready"]:
		var list=q.get(lane)
		if list is Array:
			for e in list:
				if e is Dictionary:out.append({"lane":lane,"rec":e})
	return out

func snap() -> Dictionary:
	return session.snapshot if session!=null else {}

func me() -> Dictionary:
	var p=snap().get("players",{}).get(session.own_id,{})
	return p if p is Dictionary else {}

func inventory() -> Dictionary:
	var inv=me().get("inventory",{})
	return inv if inv is Dictionary else {}

func inv_text() -> String:
	return JSON.stringify(ints(inventory())) if session!=null else "{}"

func inv_ok() -> bool:
	return ints(inventory())==expect_inv

func obj(c:Vector2i) -> Dictionary:
	var o=snap().get("objects",{}).get(k(c))
	return o if o is Dictionary else {}

func world_time() -> float:
	var t=snap().get("time")
	return float(t) if (t is int or t is float) else -1.0

func kitchen() -> Dictionary:
	var pk=snap().get("public_kitchen")
	if not pk is Dictionary:return {"<missing>":true}
	var out:=norm_kitchen(pk)
	out["keys"]=(pk.keys() as Array).size()
	return out

func summarize(records:Array) -> Array:
	var out:=[]
	for item in records:
		var rec:Dictionary=item.rec
		out.append({"lane":str(item.lane),"id":str(rec.get("id","")),"kind":str(rec.get("kind","")),"owner":str(rec.get("owner","")),
			"duration":float(rec.get("duration",0.0)),"ingredients":ints(rec.get("ingredients",{})),"yield":int(rec.get("yield",0))})
	return out

func mill_summary() -> Dictionary:
	var m:=obj(mill_cell)
	return {"type":str(m.get("type","")),"owner":str(m.get("owner","")),"input_wheat":int(m.get("input_wheat",-1)),
		"auto":m.get("auto_enabled")==true,"items":ints(m.get("items",{})),"records":summarize(queue_records(m.get("processing")))}

func mill_records() -> Array:
	return mill_summary().records

func stove_records() -> Array:
	return summarize(queue_records(obj(STOVE).get("cooking")))

func lane_ids(records:Array,lane:String) -> Array:
	var out:=[]
	for r in records:
		if str(r.lane)==lane:out.append(str(r.id))
	return out

func stove_ready() -> bool:
	return not lane_ids(stove_records(),"ready").is_empty()

func single_ready_flour() -> bool:
	var recs:=mill_records()
	return recs.size()==1 and str(recs[0].lane)=="ready"

## Everything a refused request must leave untouched (record ids, not lanes:
## the server clock legitimately moves jobs from active to ready meanwhile).
func probe_state() -> String:
	var mill_ids:=[]
	for r in mill_records():mill_ids.append(str(r.id))
	mill_ids.sort()
	var stove_ids:=[]
	for r in stove_records():stove_ids.append(str(r.id))
	stove_ids.sort()
	return JSON.stringify({"inv":ints(inventory()),"input":int(obj(mill_cell).get("input_wheat",-1)),"mill":mill_ids,
		"auto":obj(mill_cell).get("auto_enabled")==true,"chest":ints(obj(chest_cell).get("items",{})),"kitchen":kitchen(),"stove":stove_ids})

# ---------------------------------------------------------------- signals

func flag(text:String) -> void:
	if violation.is_empty():violation=text

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
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
	notices.append({"ok":ok,"message":message})
	for who in tokens:
		if message.contains(tokens[who]):flag("notice contains raw %s token"%who)
	print("BK_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func _on_completed(sequence:int,action:String,result:Dictionary) -> void:
	var text:=var_to_str(result)
	for who in tokens:
		if text.contains(tokens[who]):flag("action result contains raw %s token"%who)
	if not sent.has(sequence):flag("completion for unsent/replayed sequence %d (%s)"%[sequence,action])
	elif completed.has(sequence):flag("duplicate completion for sequence %d"%sequence)
	completed[sequence]={"action":action,"result":result}
	print("BK_DONE %s %s seq=%d action=%s ok=%s"%[phase,role,sequence,action,str(result.get("ok"))])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("BK_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("BK_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	data["phase"]=phase
	data["role"]=role
	print("BK_MARK "+JSON.stringify(data))

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
	print("BK_BARRIER %s %s %s"%[phase,role,name])
	var path:=handoff.path_join("go-%s-%s"%[phase,name])
	var go:bool=await until(func():return FileAccess.file_exists(path),BARRIER_WAIT)
	if not check(go,"runner released barrier '%s' (every role reached it)"%name):return false
	await settle()
	return not finished

func pace() -> void:
	while not finished:
		var now_ms:=Time.get_ticks_msec()
		while not sends.is_empty() and now_ms-int(sends[0])>ACTION_WINDOW_MSEC:sends.pop_front()
		if sends.size()+1<=ACTION_BUDGET:break
		await create_timer(0.05).timeout
	sends.append(Time.get_ticks_msec())

## Correlated action through Session.perform; waits for action_completed with
## EXACTLY this sequence (the acknowledgement). Returns the result plus "_seq".
func act(action:String,p:Vector2i,extra:String="") -> Dictionary:
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

## A refusal (by acknowledgement) that must leave backpack, mill, chest, stove
## and kitchen untouched.
func refused(label:String,action:String,p:Vector2i,extra:String,message:String) -> bool:
	var before:=probe_state()
	var r:Dictionary=await act(action,p,extra)
	if not check(not r.has("timeout") and r.get("ok")==false and str(r.get("message",""))==message,
		"%s: acknowledged refusal '%s' (got '%s')"%[label,message,str(r.get("message",""))]):return false
	return check(inv_ok() and probe_state()==before,"%s: no debit, mill/chest/stove/kitchen unchanged (inv %s)"%[label,inv_text()])

# ---------------------------------------------------------------- entry

func read_secrets() -> bool:
	var data=JSON.parse_string(OS.get_environment("BK_TOKENS"))
	if not data is Dictionary:return false
	for who in ["alpha","beta","gamma"]:
		var t=data.get(who)
		if not t is String or (t as String).length()<12 or (t as String).length()>64:return false
		tokens[who]=t
	return true

func read_fixture() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("fixture.json")))
	if not data is Dictionary or not data.get("mill") is String or not data.get("chest") is String:return false
	fixture=data
	mill_cell=World.cell(str(data.mill))
	chest_cell=World.cell(str(data.chest))
	return k(mill_cell)==str(data.mill) and k(chest_cell)==str(data.chest)

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=4 or not PHASE_ROLES.has(args[0]) or not args[2] in PHASE_ROLES[args[0]]:
		push_error("BK_FAIL usage: <live|restart> <port> <role> <handoff_dir>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	roles=PHASE_ROLES[phase]
	handoff=args[3]
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG[phase])))
	if not read_secrets():
		finish(false,"BK_TOKENS environment missing or invalid")
		return
	var room_key:=OS.get_environment("BK_ROOM_KEY")
	if room_key.length()<12:
		finish(false,"BK_ROOM_KEY environment missing")
		return
	if not read_fixture():
		finish(false,"handoff fixture.json missing or invalid")
		return
	if phase=="restart" and not read_plan():
		finish(false,"handoff plan-restart.json (live final state) missing or invalid")
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=tokens[role]
	session.changed.connect(_on_changed)
	session.notice.connect(_on_notice)
	session.action_completed.connect(_on_completed)
	if not check(int(Session.PROTOCOL)==CONTRACT_PROTOCOL and int(SaveSchema.VERSION)==CONTRACT_SAVE,
		"Session.PROTOCOL %d / SaveSchema.VERSION %d == contract %d / %d"%[int(Session.PROTOCOL),int(SaveSchema.VERSION),CONTRACT_PROTOCOL,CONTRACT_SAVE]):return
	var needed:=["queue_processing","claim_processing","feed_processing","prepare_material_box","queue_cook","claim_cook"]
	var missing:=needed.filter(func(a):return not a in Session.CORRELATED_ACTIONS)
	if not check(missing.is_empty(),"mill/stove/source actions are correlated (acknowledged by sequence); missing %s"%str(missing)):return
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
	await settle()
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
	if ok:print("BK_WS_PASS %s %s transport=ws checks=%d snapshots=%d notices=%d completions=%d"%[phase,role,checks,snapshots,notices.size(),completed.size()])
	else:push_error("BK_WS_FAIL %s %s transport=ws after %d checks: %s | inv=%s | mill=%s | violation=%s"%[phase,role,checks,step,
		inv_text(),JSON.stringify(mill_summary()) if session!=null else "{}",violation])
	if session!=null:session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

func view_mark(name:String) -> void:
	mark({"mark":"view_"+name,"kitchen":kitchen(),"mill":mill_summary(),"inventory":ints(inventory()),"chest":ints(obj(chest_cell).get("items",{}))})

func final_mark(extra:Dictionary={}) -> void:
	var data:={"mark":"final","inventory":ints(inventory()),"kitchen":kitchen(),"mill":mill_summary(),
		"chest":ints(obj(chest_cell).get("items",{})),"stove_records":stove_records().size()}
	data.merge(extra)
	mark(data)

func mill_seeded_ok() -> bool:
	var m:=mill_summary()
	return m.type=="mill" and m.owner==hid(tokens.alpha) and m.input_wheat==SEED_INPUT_WHEAT and m.auto==false and (m.items as Dictionary).is_empty()

# ---------------------------------------------------------------- live

func live() -> bool:
	expect_inv=ints(SEED_INV[role])
	if not check(inv_ok(),"exact seeded backpack %s"%inv_text()):return false
	if not check(kitchen()==seeded_kitchen() and PK.stage(snap())=="open","seeded public kitchen registered + opened: %s"%JSON.stringify(kitchen())):return false
	if not check(mill_seeded_ok() and mill_records().is_empty(),"seeded mill at %s: alpha's public owner, input_wheat %d, auto off, empty queue: %s"%[k(mill_cell),SEED_INPUT_WHEAT,JSON.stringify(mill_summary())]):return false
	if not check(str(obj(chest_cell).get("type",""))=="chest" and ints(obj(chest_cell).get("items",{}))==ints(SEED_CHEST),"seeded shared chest beside the mill holds %s"%JSON.stringify(SEED_CHEST)):return false
	if not check(stove_records().is_empty() and str(obj(STOVE).get("type",""))=="stove","shared public stove idle"):return false
	var flour=World.processing_recipes("mill").get("flour",{})
	var pie=World.RECIPES.get("pumpkin_pie",{})
	if not check(flour is Dictionary and ints(flour.get("ingredients",{}))==FLOUR_COST and is_equal_approx(float(flour.get("time",0)),FLOUR_TIME) and int(flour.get("yield",0))==1,
		"catalog flour: mill, wheat 2 -> 1 in 60 s"):return false
	if not check(pie is Dictionary and ints(pie.get("ingredients",{}))==PIE_COST and is_equal_approx(float(pie.get("time",0)),PIE_TIME) and int(pie.get("yield",0))==PIE_YIELD,
		"catalog pumpkin_pie: pumpkin/flour/egg -> 4 in 120 s"):return false
	if not check(World.RECIPES.get("bread")==BREAD,"existing bread recipe unchanged: %s"%str(World.RECIPES.get("bread"))):return false
	view_mark("seeded")
	cover("seeded_view")
	# ---- guest denial on the owner's mill
	var go:bool=await barrier("guest_probe")
	if not go:return false
	var fine:bool
	if role=="beta":
		fine=await refused("guest queues flour on alpha's mill","queue_processing",mill_cell,"flour",MSG_NOT_OWN_PROCESSOR)
		if not fine:return false
		fine=await refused("guest prepares the chest at alpha's owner-only mill","prepare_material_box",mill_cell,k(chest_cell),MSG_NOT_OWN_PROCESSOR)
		if not fine:return false
		fine=await refused("guest feeds wheat into alpha's mill","feed_processing",mill_cell,"",MSG_NOT_OWN_DEVICE)
		if not fine:return false
		cover("guest_denied")
	# ---- owner queues, replay probe, sourced enqueue
	go=await barrier("owner_queue")
	if not go:return false
	var q1_id:=""
	var q1_finish:=-1.0
	var q1_ms:=0
	if role=="alpha":
		var r:Dictionary=await act("queue_processing",mill_cell,"flour")
		if not check(r.get("ok")==true and str(r.get("kind",""))=="flour" and hex(r.get("id"),32) and r.get("started")==true,
			"owner queue_processing flour acknowledged and started: %s"%JSON.stringify(r)):return false
		q1_ms=Time.get_ticks_msec()
		q1_id=str(r.id)
		var q1_seq:=int(r._seq)
		expect_inv=plus(expect_inv,FLOUR_COST,-1)
		if not check(inv_ok(),"owner charged exactly wheat 2: %s"%inv_text()):return false
		var m:=obj(mill_cell)
		var active=m.get("processing",{}).get("active",{}) if m.get("processing") is Dictionary else {}
		if not check(active is Dictionary and str(active.get("id",""))==q1_id and str(active.get("owner",""))==hid(tokens.alpha)
			and is_equal_approx(float(active.get("duration",0)),FLOUR_TIME) and is_equal_approx(float(active.get("finish",0))-float(active.get("started",0)),FLOUR_TIME),
			"public mill queue: active job %s owned by alpha's public id, 60 world seconds"%q1_id.left(8)):return false
		q1_finish=float(active.finish)
		if not check(int(m.get("input_wheat",-1))==SEED_INPUT_WHEAT,"manual queue leaves the seeded input_wheat buffer untouched"):return false
		var early:Dictionary=await act("claim_processing",mill_cell,"")
		if not check(early.get("ok")==false and str(early.get("message","")).begins_with(MSG_NOT_READY_PREFIX) and inv_ok(),
			"early claim acknowledged as not ready: \"%s\""%str(early.get("message",""))):return false
		# LABELLED raw replay: same sequence, same action, sent straight to the RPC.
		var before_done:=completed.size()
		var before_notes:=notices.size()
		var before_ids:=mill_records().size()
		var epoch:=int(me().get("travel_epoch",0))
		session.request_action.rpc_id(1,q1_seq,"queue_processing",mill_cell,"flour","home",epoch)
		await create_timer(DROP_WAIT).timeout
		await settle()
		if not check(completed.size()==before_done and notices.size()==before_notes and inv_ok() and mill_records().size()==before_ids,
			"replayed request_action (same sequence %d) dropped by server: no acknowledgement/notice, no second wheat charge, still %d job"%[q1_seq,before_ids]):return false
		cover("replay_no_double_charge")
		cover("owner_queue")
		r=await act("prepare_material_box",mill_cell,k(chest_cell))
		if not check(r.get("ok")==true and str(r.get("source_cell",""))==k(chest_cell) and hex(r.get("source_id"),32),"owner prepares the adjacent shared chest: \"%s\""%str(r.get("message",""))):return false
		var box_id:=str(r.source_id)
		var recipe:Dictionary=World.processing_recipes("mill").flour
		var quote:Dictionary=Supply.plan(recipe.ingredients,inventory(),obj(chest_cell).get("items",{}))
		if not check(quote.get("ok")==true and ints(quote.get("from_backpack",{}))=={"wheat":1} and ints(quote.get("from_chest",{}))=={"wheat":1},
			"client quote: 1 wheat from the backpack + 1 from the chest"):return false
		var digest:=Sources.digest("queue_processing","mill",k(mill_cell),"flour",recipe,k(chest_cell),box_id,quote)
		var wire:=Sources.encode("flour",k(chest_cell),box_id,digest)
		r=await act("queue_processing",mill_cell,wire)
		if not check(r.get("ok")==true and str(r.get("kind",""))=="flour" and hex(r.get("id"),32) and str(r.get("source_cell",""))==k(chest_cell)
			and ints(r.get("from_backpack",{}))=={"wheat":1} and ints(r.get("from_chest",{}))=={"wheat":1},
			"sourced flour enqueue acknowledged with the server's split: %s"%JSON.stringify(r)):return false
		expect_inv=plus(expect_inv,{"wheat":1},-1)
		if not check(inv_ok() and ints(obj(chest_cell).get("items",{})).is_empty() and mill_records().size()==2,
			"sourced job debited backpack 1 + chest 1 wheat exactly; mill queue holds 2 jobs"):return false
		cover("box_sourcing")
	go=await barrier("queued_seen")
	if not go:return false
	var seen:=mill_records()
	var owners_ok:=seen.size()==2
	for rec in seen:
		if str(rec.owner)!=hid(tokens.alpha) or str(rec.kind)!="flour" or ints(rec.ingredients)!=FLOUR_COST or int(rec["yield"])!=1:owners_ok=false
	if not check(owners_ok and int(obj(mill_cell).get("input_wheat",-1))==SEED_INPUT_WHEAT,"%s sees the public mill queue: 2 flour jobs by alpha's public id, wheat 2 each"%role):return false
	if not check(inv_ok(),"backpack still exact: %s"%inv_text()):return false
	# ---- owner waits for the first job (accelerated server clock)
	if role=="alpha":
		var ready:bool=await until(func():return lane_ids(mill_records(),"ready").has(q1_id),FLOUR_WAIT)
		if not check(ready,"first flour job ready within %ds real time"%int(FLOUR_WAIT)):return false
	go=await barrier("flour_ready")
	if not go:return false
	if role=="beta":
		if not check(not lane_ids(mill_records(),"ready").is_empty(),"guest sees ready flour in alpha's public queue"):return false
		fine=await refused("guest claims alpha's ready flour","claim_processing",mill_cell,"",MSG_NOT_OWN_PROCESSOR)
		if not fine:return false
		cover("guest_claim_denied")
	go=await barrier("owner_claim")
	if not go:return false
	if role=="alpha":
		var t_before:=world_time()
		var r:Dictionary=await act("claim_processing",mill_cell,"")
		if not check(r.get("ok")==true and str(r.get("kind",""))=="flour" and int(r.get("yield",0))==1 and str(r.get("id",""))==q1_id,
			"owner claims the first flour job (+1): %s"%JSON.stringify(r)):return false
		var real_s:=float(Time.get_ticks_msec()-q1_ms)/1000.0
		var t_after:=world_time()
		expect_inv=plus(expect_inv,{"flour":1})
		if not check(inv_ok(),"owner backpack after claim: %s"%inv_text()):return false
		if not check(t_before>=q1_finish and t_after>=q1_finish,"claim at world time %.2f >= job finish %.2f (60 world seconds after start)"%[t_before,q1_finish]):return false
		mark({"mark":"accelerated","world_duration":FLOUR_TIME,"finish":q1_finish,"claim_world_time":t_before,"real_seconds":real_s})
		cover("owner_claim_after_60")
	# ---- existing bread through the shared stove (guest)
	go=await barrier("bread")
	if not go:return false
	if role=="beta":
		var r:Dictionary=await act("queue_cook",STOVE,"bread")
		if not check(r.get("ok")==true and str(r.get("kind",""))=="bread","guest queue_cook bread on the shared stove: \"%s\""%str(r.get("message",""))):return false
		expect_inv=plus(expect_inv,BREAD.ingredients,-1)
		if not check(inv_ok(),"bread charged exactly wheat 2: %s"%inv_text()):return false
		var ready:bool=await until(stove_ready,COOK_WAIT)
		if not check(ready,"bread ready within %ds"%int(COOK_WAIT)):return false
		r=await act("claim_cook",STOVE,"")
		if not check(r.get("ok")==true and str(r.get("kind",""))=="bread" and int(r.get("yield",0))==1,"guest claims 1 bread: %s"%JSON.stringify(r)):return false
		expect_inv=plus(expect_inv,{"bread":1})
		if not check(inv_ok() and stove_records().is_empty(),"bread unchanged end to end; stove idle; backpack %s"%inv_text()):return false
		cover("bread_unchanged")
	# ---- pie on the shared public stove
	go=await barrier("pie_queue")
	if not go:return false
	if role=="alpha":
		var r:Dictionary=await act("queue_cook",STOVE,"pumpkin_pie")
		if not check(r.get("ok")==true and str(r.get("kind",""))=="pumpkin_pie" and r.get("started")==true,"owner queue_cook pumpkin_pie on the public stove: \"%s\""%str(r.get("message",""))):return false
		expect_inv=plus(expect_inv,PIE_COST,-1)
		if not check(inv_ok(),"pie charged exactly pumpkin/flour/egg: %s"%inv_text()):return false
		var recs:=stove_records()
		if not check(recs.size()==1 and str(recs[0].kind)=="pumpkin_pie" and int(recs[0]["yield"])==PIE_YIELD and is_equal_approx(float(recs[0].duration),PIE_TIME)
			and ints(recs[0].ingredients)==PIE_COST and str(recs[0].owner)==hid(tokens.alpha),"public stove record: pie, yield 4, 120 s, alpha's public id"):return false
		cover("pie_queued")
	var pie_ready:bool=await until(stove_ready,COOK_WAIT)
	if not check(pie_ready,"%s sees the pie ready on the shared stove within %ds"%[role,int(COOK_WAIT)]):return false
	go=await barrier("pie_race")
	if not go:return false
	var claim:Dictionary=await act("claim_cook",STOVE,"")
	var won:bool=claim.get("ok")==true
	if won:
		if not check(str(claim.get("kind",""))=="pumpkin_pie" and int(claim.get("yield",0))==PIE_YIELD,"race won: exactly %d pumpkin_pie: %s"%[PIE_YIELD,JSON.stringify(claim)]):return false
		expect_inv=plus(expect_inv,{"pumpkin_pie":PIE_YIELD})
	else:
		if not check(not claim.has("timeout") and str(claim.get("message",""))==MSG_STOVE_EMPTY,"race lost: acknowledged '%s' (got '%s')"%[MSG_STOVE_EMPTY,str(claim.get("message",""))]):return false
	if not check(inv_ok(),"race outcome reflected exactly in my backpack: %s"%inv_text()):return false
	mark({"mark":"pie_race","won":won,"message":str(claim.get("message",""))})
	cover("pie_race")
	go=await barrier("race_seen")
	if not go:return false
	if not check(stove_records().is_empty() and inv_ok(),"stove empty after the single successful claim; backpack %s"%inv_text()):return false
	# ---- second (sourced) flour job completes and stays in the public queue
	if role=="alpha":
		var second:bool=await until(single_ready_flour,FLOUR_WAIT)
		if not check(second,"second (sourced) flour job ready in the mill queue"):return false
	go=await barrier("final")
	if not go:return false
	var recs2:=mill_records()
	if not check(recs2.size()==1 and str(recs2[0].lane)=="ready" and str(recs2[0].owner)==hid(tokens.alpha) and mill_seeded_ok(),
		"final mill: input_wheat %d, one ready flour by alpha's public id: %s"%[SEED_INPUT_WHEAT,JSON.stringify(mill_summary())]):return false
	if not check(kitchen()==seeded_kitchen() and inv_ok(),"final kitchen unchanged and backpack exact"):return false
	final_mark({"won":won})
	return true

# ---------------------------------------------------------------- restart

func read_plan() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("plan-restart.json")))
	if not data is Dictionary:return false
	for who in ["alpha","beta"]:
		var item=data.get(who)
		if not item is Dictionary or not item.get("inventory") is Dictionary or not item.get("mill") is Dictionary:return false
	plan=data
	return true

func restart() -> bool:
	var persisted:Dictionary=plan.alpha.mill
	var m:=mill_summary()
	var recs:Array=m.records
	if not check(kitchen()==seeded_kitchen() and PK.stage(snap())=="open","kitchen after normal restart still opened: %s"%JSON.stringify(kitchen())):return false
	if not check(mill_seeded_ok() and recs.size()==1 and str(recs[0].lane)=="ready" and str(recs[0].kind)=="flour" and str(recs[0].owner)==hid(tokens.alpha),
		"%s sees the persisted mill: input_wheat %d, one ready flour in the public queue: %s"%[role,SEED_INPUT_WHEAT,JSON.stringify(m)]):return false
	if not check(JSON.stringify(recs)==JSON.stringify(persisted.records) or (recs.size()==1 and str(recs[0].id)==str(persisted.records[0].id)),
		"public queue record identical to the live final (id %s)"%str(recs[0].id).left(8)):return false
	if not check(stove_records().is_empty() and ints(obj(chest_cell).get("items",{})).is_empty(),"stove idle and chest empty after restart"):return false
	if role=="gamma":
		if not check(not plan.has("gamma"),"gamma never joined before (late joiner)"):return false
		expect_inv=ints(inventory())
		cover("late_join")
	else:
		expect_inv=ints(plan[role].inventory)
		if not check(inv_ok(),"persisted backpack %s == live final"%inv_text()):return false
		cover("reconnect")
	view_mark("restarted")
	var go:bool=await barrier("observed")
	if not go:return false
	if role=="gamma":
		var fine:bool=await refused("late joiner claims alpha's persisted flour","claim_processing",mill_cell,"",MSG_NOT_OWN_PROCESSOR)
		if not fine:return false
		cover("late_join_denied")
	go=await barrier("gamma_probe")
	if not go:return false
	if role=="alpha":
		var r:Dictionary=await act("claim_processing",mill_cell,"")
		if not check(r.get("ok")==true and str(r.get("kind",""))=="flour" and int(r.get("yield",0))==1,"owner claims the persisted flour after restart: %s"%JSON.stringify(r)):return false
		expect_inv=plus(expect_inv,{"flour":1})
		if not check(inv_ok(),"owner backpack %s"%inv_text()):return false
		cover("restart_claim")
	go=await barrier("final")
	if not go:return false
	if not check(mill_records().is_empty() and mill_seeded_ok() and kitchen()==seeded_kitchen() and inv_ok(),
		"end of restart: mill queue empty, input_wheat %d, kitchen opened, backpack exact"%SEED_INPUT_WHEAT):return false
	final_mark()
	return true

# ---------------------------------------------------------------- fixture seed

func clear_cell(world,c:Vector2i) -> bool:
	if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c)!="" or c==TABLE:return false
	for layer in ["objects","ground","roofs","crops","forest"]:
		if world.state[layer].has(k(c)):return false
	return true

## Deterministic search for a naturally clear mill cell within 3.0 of both
## stand positions, plus a clear cardinal neighbour for the shared chest.
func find_mill_site(world,taken:Array) -> Array:
	var stand_cells:=[]
	for spot in [STAND.alpha,STAND.beta,World.SPAWN]:stand_cells.append(Vector2i(floori(spot.x),floori(spot.y)))
	var mid:Vector2=(STAND.alpha+STAND.beta)*0.5
	var best:Array=[]
	var best_score:=INF
	for y in range(29,41):
		for x in range(34,46):
			var c:=Vector2i(x,y)
			if c in taken or c in stand_cells or not clear_cell(world,c):continue
			var centre:=Vector2(c)+Vector2(0.5,0.5)
			if centre.distance_to(STAND.alpha)>3.0 or centre.distance_to(STAND.beta)>3.0:continue
			for off in NEIGHBOURS:
				var n:Vector2i=c+off
				if n in taken or n in stand_cells or not clear_cell(world,n):continue
				var score:=centre.distance_to(mid)
				if score<best_score-0.0001:
					best_score=score
					best=[c,n]
	return best

func seed_world(args:Array) -> void:
	if args.size()!=2:
		push_error("BK_SEED_FAIL usage: seed <world.json>")
		quit(2)
		return
	if not read_secrets():
		push_error("BK_SEED_FAIL BK_TOKENS environment missing or invalid")
		quit(2)
		return
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	# SEED picnic + table
	world.state.board=true
	world.state.picnic_materials={"soup":2,"bread":1}
	world.state.picnic=true
	world.state.community={"table":k(TABLE)}
	# SEED kitchen_site (alpha's stove + two long benches)
	var site:Array=[STOVE]+SEATS
	for c in site:
		if not clear_cell(world,c):problems.append("kitchen cell %s is not clear home land"%k(c))
	if problems.is_empty():
		world.state.objects[k(STOVE)]={"type":"stove","owner":tokens.alpha,"items":{}}
		for seat in SEATS:world.state.objects[k(seat)]={"type":"long_bench","owner":tokens.alpha,"items":{}}
	# SEED positions + inventories
	for who in ["alpha","beta"]:
		world.add_player(tokens[who],who)
		var person:Dictionary=world.state.players[tokens[who]]
		person.x=STAND[who].x
		person.y=STAND[who].y
		person.inventory=(SEED_INV[who] as Dictionary).duplicate(true)
	# SEED mill + input_wheat + chest
	var found:=find_mill_site(world,site)
	if found.size()!=2:
		problems.append("no clear mill + adjacent chest site within reach of both stands")
	else:
		mill_cell=found[0]
		chest_cell=found[1]
		world.state.objects[k(mill_cell)]={"type":"mill","owner":tokens.alpha,"items":{},"input_wheat":SEED_INPUT_WHEAT,"auto_enabled":false}
		world.state.objects[k(chest_cell)]={"type":"chest","owner":tokens.alpha,"items":SEED_CHEST.duplicate(true)}
	# SEED kitchen_opened: registered site with every meal at its schema cap.
	var meals:={}
	for meal in SaveSchema.KITCHEN_MEALS:meals[meal]=int(SaveSchema.KITCHEN_MEALS[meal])
	world.state.public_kitchen={"stove":k(STOVE),"seats":[k(SEATS[0]),k(SEATS[1])],"meals":meals,"opened":true}
	for who in ["alpha","beta"]:
		if not world.can_stand(STAND[who]):problems.append("%s cannot stand at %s"%[who,STAND[who]])
		var targets:=[STOVE]
		if found.size()==2:targets.append(mill_cell)
		for c in targets:
			var d:float=STAND[who].distance_to(Vector2(c)+Vector2(0.5,0.5))
			if d>3.0:problems.append("%s is %.2f from %s"%[who,d,k(c)])
	if not world.can_stand(World.SPAWN):problems.append("late joiner spawn blocked")
	if not problems.is_empty():
		for problem in problems:push_error("BK_SEED_FAIL "+problem)
		quit(1)
		return
	if not world.save():
		push_error("BK_SEED_FAIL save: "+str(world.save_error))
		quit(1)
		return
	var reloaded:=World.new()
	var loaded:bool=reloaded.load_world(args[1])
	var ok:bool=loaded and not reloaded.recovered_from_backup and int(reloaded.state.version)==SaveSchema.VERSION and int(SaveSchema.VERSION)==CONTRACT_SAVE
	ok=ok and PK.stage(reloaded.state)=="open" and reloaded.kitchen_opened()
	var mill_obj=reloaded.state.objects.get(k(mill_cell),{})
	ok=ok and mill_obj is Dictionary and mill_obj.get("type")=="mill" and mill_obj.get("owner")==tokens.alpha and int(mill_obj.get("input_wheat",-1))==SEED_INPUT_WHEAT and mill_obj.get("auto_enabled")==false
	var chest_obj=reloaded.state.objects.get(k(chest_cell),{})
	ok=ok and chest_obj is Dictionary and chest_obj.get("type")=="chest" and ints(chest_obj.get("items",{}))==ints(SEED_CHEST)
	for who in ["alpha","beta"]:
		if ints(reloaded.state.players[tokens[who]].inventory)!=ints(SEED_INV[who]):ok=false
	if not ok:
		push_error("BK_SEED_FAIL seeded save did not reload through SaveSchema as an opened kitchen + mill/input_wheat + chest + exact inventories")
		quit(1)
		return
	var out:={"label":SEED_LABEL,"seeded":SEEDED,"seed_version":int(reloaded.state.version),"protocol":int(Session.PROTOCOL),
		"table":k(TABLE),"stove":k(STOVE),"seats":[k(SEATS[0]),k(SEATS[1])],"mill":k(mill_cell),"chest":k(chest_cell),
		"stand":{"alpha":[STAND.alpha.x,STAND.alpha.y],"beta":[STAND.beta.x,STAND.beta.y]},
		"inventories":SEED_INV,"chest_items":SEED_CHEST,"input_wheat":SEED_INPUT_WHEAT,"kitchen":seeded_kitchen()}
	print("BK_FIXTURE "+JSON.stringify(out))
	quit(0)
