extends SceneTree
## Real two-client network regression of T036 explicit material sourcing
## (current protocol / save version, game/docs/material-source-contract.json) over plain
## loopback WebSocket (ws://127.0.0.1:<port>; NOT wss/TLS, NOT cloud, no
## adverse-network injection). Every action goes client Session.perform ->
## request_action RPC -> SEPARATE dedicated Godot server -> World.act. No client
## touches a World; nothing here mocks an RPC or a World.
##
## AUTHORIZED SEEDED LOCAL FIXTURE - NOT HUMAN / NATURAL PLAY. `seed` writes a
## temporary current-schema file: a bench B(48,24), a shared chest C(49,24) adjacent to
## B and to stove S(50,24), private chests PA(48,25) (alpha) / PB(48,23) (beta)
## adjacent to B, an unrelated shared chest X(46,26) that is never prepared,
## fixed stand positions and exact backpack/chest contents. NO box_id is
## seeded anywhere: identities appear only through prepare_material_box.
## Restocking after the race uses the real `withdraw` / `deposit` actions.
##
## Driven by work/material-source/network_material_source.py. Args after `--`:
##   seed <world.json> <alpha_token> <beta_token>       -> prints MS_FIXTURE {json}
##   <phase> <port> <role> <room_key> <alpha_token> <beta_token> <handoff_dir>
## Barriers: a client prints `MS_BARRIER <phase> <role> <name>` and waits (with
## timeout) for <handoff>/go-<phase>-<name>, created by the runner only after
## BOTH clients printed it. A missing barrier/result is a failure, never a skip.
##
## contest (server-live):
##   initial      exact fixture backpack, no box_id on any chest (lazy identity),
##                MaterialSources.candidates: other player's private chest is not
##                offered; alpha: plain (no '|') craft extra > 32 is dropped by
##                Session (no completion, no notice, no charge).
##   probe        alpha prepare on PB and forced sourced craft with PB + guessed
##                id -> exactly the private refusal, result keys {ok,message}.
##   private      beta: refused prepare assigned no id. Both prepare own private
##                chest concurrently; id visible to owner only.
##   private_seen alpha retries with beta's REAL PB id (test-harness relay file
##                simulating a leaked id) -> same refusal, nothing moves.
##   shared       both prepare C concurrently -> one id for both.
##   bench race   same snapshot preview/digest on both (stone from backpack,
##                wood 4 from C which holds 6); both send sourced craft at once:
##                exactly one commits, the other gets 材料不足 with no charge; C
##                ends at wood 2, never negative.
##   restock      the loser withdraws wood from its own private chest and
##                deposits it into C (authorized real actions), deposits one
##                stone (changes the split), replays the old quote -> requote
##                with the new split and no mutation, then a fresh snapshot
##                preview + new confirmation commits.
##   stove race   same for queue_cook soup (radish 2 of 3 in C): one record,
##                loser refused; winner cancels by exact ID -> refund to its
##                backpack (not the chest) exactly once; second cancel not found.
## restart (after a NORMAL server stop + restart on the same save): persisted
##   identities, contents and inventories; prepare on C is idempotent; alpha
##   commits from its own private chest with the persisted id; beta's prepare and
##   forced craft with alpha's real persisted PA id are refused.
## Every snapshot: no raw profile token, no other player's inventory, foreign
## private chest locked with no items/box_id, no negative count, no known foreign
## private id anywhere. Output: MS_CHECK ok ..., MS_COVER <tag> <phase> <role>,
## MS_MARK {json}, MS_WS_PASS / MS_WS_FAIL.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const Sources=preload("res://scripts/material_sources.gd")
const Supply=preload("res://scripts/material_supply.gd")

const CONTRACT_PROTOCOL:=45
const CONTRACT_SAVE:=26
const BENCH:=Vector2i(48,24)
const CHEST:=Vector2i(49,24)
const STOVE:=Vector2i(50,24)
const PRIVATE:={"alpha":Vector2i(48,25),"beta":Vector2i(48,23)}
const SPARE:=Vector2i(46,26)
const STAND:={"alpha":Vector2(49.5,25.5),"beta":Vector2(49.5,23.5)}
const START:={"stone":8,"copper_ore":2}
const CHEST_START:={"wood":6,"radish":3}
const PRIVATE_START:={"wood":10}
const SPARE_START:={"stone":1}
const BENCH_RECIPE:="kiln_kit"
const BENCH_COST:={"stone":8,"wood":4}
const STOVE_RECIPE:="soup"
const STOVE_COST:={"radish":2}
const OWN_RECIPE:="copper_joint"
const OWN_COST:={"copper_ore":2,"wood":1}
const RESTOCK:=4
const PHASES:=["contest","restart"]
const ROLES:=["alpha","beta"]
const WATCHDOG:={"contest":100.0,"restart":55.0}
const JOIN_WAIT:=15.0
const RESULT_WAIT:=8.0
const PEER_WAIT:=30.0
const BARRIER_WAIT:=60.0
const DROP_WAIT:=2.0
const ACTION_BUDGET:=9        # server allows 12 actions / 1000 ms per peer
const ACTION_WINDOW_MSEC:=1100
const MSG_SHORT:="材料不足，還缺"
const MSG_CANCELLED:="已取消，食材完整退回"
const MSG_NOT_FOUND:="找不到這份料理"

var session:Session
var phase:=""
var role:=""
var tokens:={}
var handoff:=""
var plan:Dictionary={}
var notices:Array=[]
var sent:Dictionary={}
var completed:Dictionary={}
var sends:Array=[]
var snapshots:=0
var home_snapshots:=0
var seen_both:=false
var violation:=""
var checks:=0
var finished:=false
var expect_inv:Dictionary={}
var foreign_ids:Array=[]
var chest_id:=""
var private_id:=""
var sourced_ok:=0
var prepared_ok:=0
var bench_won:=false
var stove_won:=false

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

static func rand_hex(length:int) -> String:
	return Crypto.new().generate_random_bytes(length>>1).hex_encode()

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

static func counts_ok(d:Variant) -> bool:
	if not d is Dictionary:return false
	for item in d:
		var v=d[item]
		if not (v is int or v is float) or float(v)<0.0:return false
	return true

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

func objects() -> Dictionary:
	var o=snap().get("objects",{})
	return o if o is Dictionary else {}

func obj(cell:Vector2i) -> Dictionary:
	var o=objects().get(k(cell))
	return o if o is Dictionary else {}

func items_of(cell:Vector2i) -> Dictionary:
	return ints(obj(cell).get("items",{}))

func cells_of(list:Array) -> Array:
	var out:=[]
	for c in list:out.append(str(c.get("cell","")))
	return out

func candidate_id(station:Vector2i,box:Vector2i) -> String:
	for c in Sources.candidates(objects(),session.own_id,station):
		if str(c.cell)==k(box):return str(c.id)
	return "<not a candidate>"

func stove_records() -> Array:
	var out:=[]
	var q=obj(STOVE).get("cooking")
	if not q is Dictionary:return out
	var a=q.get("active")
	if a is Dictionary and not (a as Dictionary).is_empty():out.append(a)
	for lane in ["waiting","ready"]:
		var list=q.get(lane)
		if list is Array:out.append_array(list)
	return out

func own_stove_ids() -> Array:
	var out:=[]
	for rec in stove_records():
		if rec is Dictionary and str(rec.get("owner",""))==me_hid():out.append(str(rec.get("id","")))
	return out

func find_record(id:String) -> Dictionary:
	for rec in stove_records():
		if rec is Dictionary and str(rec.get("id",""))==id:return rec
	return {}

## Client-side preview exactly as the station UI computes it: candidates from
## the CURRENT snapshot, MaterialSupply.plan(backpack first), canonical digest.
func preview(action:String,station:Vector2i,recipe_id:String,box:Vector2i) -> Dictionary:
	var station_obj:=obj(station)
	if station_obj.is_empty():return {"ok":false,"why":"no station in snapshot"}
	var id:=candidate_id(station,box)
	if not hex(id,Sources.ID_LENGTH):return {"ok":false,"why":"box %s candidate id '%s'"%[k(box),id.left(8)]}
	var catalog:Dictionary=World.CRAFT if action=="craft" else World.RECIPES
	var recipe:Dictionary=catalog[recipe_id]
	var p:Dictionary=Supply.plan(recipe.ingredients,inventory(),obj(box).get("items",{}))
	if not p.ok:return {"ok":false,"why":"plan: %s %s"%[str(p.get("message","")),JSON.stringify(p.get("missing",{}))]}
	var digest:=Sources.digest(action,str(station_obj.get("type","")),k(station),recipe_id,recipe,k(box),id,p)
	return {"ok":true,"id":id,"digest":digest,"wire":Sources.encode(recipe_id,k(box),id,digest),
		"from_backpack":ints(p.from_backpack),"from_chest":ints(p.from_chest)}

func wire_ok(wire:String) -> bool:
	return wire.length()>Session.PLAIN_EXTRA_MAX and wire.length()<=Session.SOURCED_EXTRA_MAX and Session.sourced_extra_valid(wire)

# ---------------------------------------------------------------- signals

func flag(text:String) -> void:
	if violation.is_empty():violation=text

func _on_changed(data:Dictionary,id:String) -> void:
	snapshots+=1
	var text:=var_to_str(data)+"|"+id
	for who in tokens:
		if text.contains(tokens[who]):flag("snapshot %d contains raw %s token"%[snapshots,who])
	for foreign in foreign_ids:
		if text.contains(foreign):flag("snapshot %d contains another player's private box id"%snapshots)
	if online_of(data)==2:seen_both=true
	if str(data.get("region_id",""))!="home":return
	home_snapshots+=1
	var players=data.get("players",{})
	if players is Dictionary:
		for pid in players:
			var person=players[pid]
			if not person is Dictionary:continue
			if str(pid)!=id and (person.has("inventory") or person.has("receipts")):flag("snapshot %d shows another player's inventory/receipts"%snapshots)
			if str(pid)==id and not counts_ok(person.get("inventory",{})):flag("snapshot %d: own inventory has a negative/malformed count"%snapshots)
	var objs=data.get("objects",{})
	if not objs is Dictionary:return
	for key in objs:
		var o=objs[key]
		if not o is Dictionary:continue
		var t:=str(o.get("type",""))
		if o.has("box_id") and not t in ["chest","private_chest"]:flag("snapshot %d: box_id on %s %s"%[snapshots,t,str(key)])
		if t in ["chest","private_chest"] and not counts_ok(o.get("items",{})):flag("snapshot %d: box %s has a negative/malformed count"%[snapshots,str(key)])
		if t=="private_chest" and str(o.get("owner",""))!=id:
			var items=o.get("items",{})
			if o.has("box_id") or not (items is Dictionary and (items as Dictionary).is_empty()) or o.get("locked")!=true:
				flag("snapshot %d: foreign private chest %s exposes box_id/items or is not locked"%[snapshots,str(key)])

func _on_notice(message:String,ok:bool) -> void:
	notices.append({"ok":ok,"message":message})
	for who in tokens:
		if message.contains(tokens[who]):flag("notice contains raw %s token"%who)
	for foreign in foreign_ids:
		if message.contains(foreign):flag("notice contains another player's private box id")
	print("MS_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func _on_completed(sequence:int,action:String,result:Dictionary) -> void:
	var text:=var_to_str(result)
	for who in tokens:
		if text.contains(tokens[who]):flag("action result contains raw %s token"%who)
	for foreign in foreign_ids:
		if text.contains(foreign):flag("action result contains another player's private box id")
	if not sent.has(sequence):flag("completion for unsent/dropped sequence %d (%s)"%[sequence,action])
	elif completed.has(sequence):flag("duplicate completion for sequence %d"%sequence)
	completed[sequence]={"action":action,"result":result}
	print("MS_DONE %s %s seq=%d action=%s ok=%s requote=%s"%[phase,role,sequence,action,str(result.get("ok")),str(result.get("requote",false))])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("MS_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("MS_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	data["phase"]=phase
	data["role"]=role
	print("MS_MARK "+JSON.stringify(data))

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
	print("MS_BARRIER %s %s %s"%[phase,role,name])
	var path:=handoff.path_join("go-%s-%s"%[phase,name])
	var go:bool=await until(func():return FileAccess.file_exists(path),BARRIER_WAIT)
	if not check(go,"runner released barrier '%s' within %ds (both clients reached it)"%[name,int(BARRIER_WAIT)]):return false
	await settle()
	return not finished

func pace(n:int) -> void:
	while not finished:
		var now_ms:=Time.get_ticks_msec()
		while not sends.is_empty() and now_ms-int(sends[0])>ACTION_WINDOW_MSEC:sends.pop_front()
		if sends.size()+n<=ACTION_BUDGET:break
		await create_timer(0.05).timeout
	for _i in n:sends.append(Time.get_ticks_msec())

## Correlated action: waits for action_completed carrying EXACTLY this
## Session sequence and asserts the echoed action name. Notices are not acks.
func act(action:String,p:Vector2i,extra:String="") -> Dictionary:
	await pace(1)
	var seq:int=session.perform(action,p,extra)
	if seq<=0:return {"ok":false,"message":"<perform refused locally>","timeout":true}
	sent[seq]=action
	var got:bool=await until(func():return completed.has(seq),RESULT_WAIT)
	if not got:return {"ok":false,"message":"<no correlated completion for sequence %d within %ds>"%[seq,int(RESULT_WAIT)],"timeout":true}
	var entry:Dictionary=completed[seq]
	if not check(str(entry.action)==action,"sequence %d completed with the same action '%s' (got '%s')"%[seq,action,str(entry.action)]):
		return {"ok":false,"message":"<action mismatch>","timeout":true}
	await settle()
	return entry.result

## Non-correlated chest actions (deposit/withdraw): result is the next own notice.
func act_notice(action:String,p:Vector2i,extra:String) -> Dictionary:
	await pace(1)
	var index:=notices.size()
	session.perform(action,p,extra)
	var got:bool=await until(func():return notices.size()>index,RESULT_WAIT)
	if not got:return {"ok":false,"message":"<no notice within %ds>"%int(RESULT_WAIT),"timeout":true}
	await settle()
	return notices[index]

func refuse_private(label:String,action:String,p:Vector2i,extra:String) -> bool:
	var before_private:=items_of(PRIVATE[role])
	var before_chest:=items_of(CHEST)
	var r:Dictionary=await act(action,p,extra)
	var keys:Array=r.keys()
	keys.sort()
	if not check(not r.has("timeout") and r.get("ok")==false and str(r.get("message",""))==Sources.MSG_PRIVATE and keys==["message","ok"],
		"%s: refused with exactly '%s' and only {ok,message} (keys %s)"%[label,Sources.MSG_PRIVATE,str(keys)]):return false
	return check(inv_ok() and items_of(PRIVATE[role])==before_private and items_of(CHEST)==before_chest,"%s: nothing charged or moved: %s"%[label,inv_text()])

func moves(count:int,action:String,cell:Vector2i,item:String,prefix:String) -> bool:
	for i in count:
		var n:Dictionary=await act_notice(action,cell,item)
		if not check(n.get("ok")==true and str(n.get("message","")).begins_with(prefix),"%s %s %d/%d at %s: \"%s\""%[action,item,i+1,count,k(cell),str(n.get("message",""))]):return false
	return true

# ---------------------------------------------------------------- entry

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=7 or not args[0] in PHASES or not args[2] in ROLES:
		push_error("MS_FAIL usage: <contest|restart> <port> <alpha|beta> <room_key> <alpha_token> <beta_token> <handoff_dir>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	tokens={"alpha":args[4],"beta":args[5]}
	handoff=args[6]
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG[phase])))
	if phase=="restart":
		if not read_plan():
			finish(false,"handoff plan-restart.json (contest final state) missing or invalid")
			return
		foreign_ids.append(str(plan[other()].own_private.id))
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	session.profile.token=tokens[role]
	session.changed.connect(_on_changed)
	session.notice.connect(_on_notice)
	session.action_completed.connect(_on_completed)
	if not check(int(Session.PROTOCOL)==CONTRACT_PROTOCOL and int(SaveSchema.VERSION)==CONTRACT_SAVE,"Session.PROTOCOL %d / SaveSchema.VERSION %d == contract %d / %d"%[int(Session.PROTOCOL),int(SaveSchema.VERSION),CONTRACT_PROTOCOL,CONTRACT_SAVE]):return
	if not check(Sources.PREPARE_ACTION in Session.CORRELATED_ACTIONS and "craft" in Session.CORRELATED_ACTIONS and "queue_cook" in Session.CORRELATED_ACTIONS,"craft/queue_cook/prepare_material_box are correlated actions"):return
	var port:=int(args[1])
	var address:="ws://127.0.0.1:%d"%port
	var err:=session.join(address,port,role,args[3])
	if not check(err==OK,"loopback WebSocket join to %s accepted by Session.join (err %d)"%[address,err]):return
	var joined:bool=await until(func():return not session.own_id.is_empty() and snap().get("players",{}).has(session.own_id),JOIN_WAIT)
	if not check(joined and peer_class()=="WebSocketMultiplayerPeer","registered over plain ws:// with protocol %d and the room key (peer %s)"%[Session.PROTOCOL,peer_class()]):return
	cover("transport_verified")
	if not check(session.own_id==me_hid(),"own id is the hashed profile token"):return
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are online together"):return
	await settle()
	if not check(str(snap().get("region_id",""))=="home","both play in home"):return
	var ok:bool
	if phase=="contest":ok=await contest()
	else:ok=await restart()
	if finished or not ok:
		if not finished:finish(false,"phase stopped without a recorded failure")
		return
	if not check(home_snapshots>0 and violation.is_empty(),"%d snapshots (%d home): no raw token, no foreign inventory, foreign private chests locked without items/box_id, no negative counts, no foreign private id"%[snapshots,home_snapshots]+("" if violation.is_empty() else " -- "+violation)):return
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
	if ok:print("MS_WS_PASS %s %s transport=ws checks=%d snapshots=%d home=%d notices=%d completions=%d"%[phase,role,checks,snapshots,home_snapshots,notices.size(),completed.size()])
	else:
		var view:="no session"
		if session!=null:view="chest=%s own_private=%s stove_records=%d"%[JSON.stringify(items_of(CHEST)),JSON.stringify(items_of(PRIVATE[role])),stove_records().size()]
		push_error("MS_WS_FAIL %s %s transport=ws after %d checks: %s | %s | inv=%s | violation=%s"%[phase,role,checks,step,view,inv_text(),violation])
	if session!=null:session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

func final_mark() -> void:
	mark({"mark":"final","inventory":ints(inventory()),
		"chest":{"id":str(obj(CHEST).get("box_id","")),"items":items_of(CHEST)},
		"own_private":{"cell":k(PRIVATE[role]),"id":str(obj(PRIVATE[role]).get("box_id","")),"items":items_of(PRIVATE[role])},
		"spare":{"items":items_of(SPARE),"has_id":obj(SPARE).has("box_id")},
		"stove_records":stove_records().size(),"sourced_ok":sourced_ok,"prepared_ok":prepared_ok})

# ---------------------------------------------------------------- contest

func contest() -> bool:
	expect_inv=ints(START)
	if not check(inv_ok(),"starts with exact fixture backpack %s"%inv_text()):return false
	if not check(ints(World.CRAFT[BENCH_RECIPE].ingredients)==ints(BENCH_COST) and ints(World.RECIPES[STOVE_RECIPE].ingredients)==ints(STOVE_COST) \
		and ints(World.CRAFT[OWN_RECIPE].ingredients)==ints(OWN_COST),"live recipes match the fixture arithmetic (%s / %s / %s)"%[BENCH_RECIPE,STOVE_RECIPE,OWN_RECIPE]):return false
	for cell in [CHEST,PRIVATE.alpha,PRIVATE.beta,SPARE]:
		if not check(str(obj(cell).get("type","")) in ["chest","private_chest"] and not obj(cell).has("box_id"),"box %s present with NO box_id (identity is lazy)"%k(cell)):return false
	if not check(items_of(CHEST)==ints(CHEST_START) and items_of(SPARE)==ints(SPARE_START) and items_of(PRIVATE[role])==ints(PRIVATE_START),
		"fixture contents: shared %s, spare %s, own private %s"%[JSON.stringify(items_of(CHEST)),JSON.stringify(items_of(SPARE)),JSON.stringify(items_of(PRIVATE[role]))]):return false
	cover("no_eager_ids")
	var bench_cells:=cells_of(Sources.candidates(objects(),session.own_id,BENCH))
	var want:=[k(CHEST),k(PRIVATE.alpha)] if role=="alpha" else [k(PRIVATE.beta),k(CHEST)]
	if not check(bench_cells==want,"bench candidates %s == %s (shared + own private only, y/x order)"%[str(bench_cells),str(want)]):return false
	if not check(cells_of(Sources.candidates(objects(),session.own_id,STOVE))==[k(CHEST)],"stove candidates are only the shared chest"):return false
	cover("private_not_selectable")
	if role=="alpha":
		await pace(1)
		var idx:=notices.size()
		var done_before:=completed.size()
		var long_plain:="x".repeat(Session.PLAIN_EXTRA_MAX+8)
		session.perform("craft",BENCH,long_plain)
		await create_timer(DROP_WAIT).timeout
		if not check(notices.size()==idx and completed.size()==done_before and inv_ok(),"plain craft extra of %d chars (no '|', > %d) dropped by Session: no completion, no notice, no charge"%[long_plain.length(),Session.PLAIN_EXTRA_MAX]):return false
		cover("plain_extra_bound")
	# ---- probe: alpha against beta's private chest before it has an id.
	var go:bool=await barrier("probe")
	if not go:return false
	if role=="alpha":
		var ok:bool=await refuse_private("prepare beta's private chest","prepare_material_box",BENCH,k(PRIVATE.beta))
		if not ok:return false
		var forged:=Sources.encode(BENCH_RECIPE,k(PRIVATE.beta),rand_hex(32),rand_hex(16))
		if not check(wire_ok(forged),"forged sourced wire is well-formed (%d chars)"%forged.length()):return false
		ok=await refuse_private("forced craft from beta's private chest with a guessed id","craft",BENCH,forged)
		if not ok:return false
		cover("private_probe_refused")
	go=await barrier("private")
	if not go:return false
	if role=="beta":
		if not check(not obj(PRIVATE.beta).has("box_id") and items_of(PRIVATE.beta)==ints(PRIVATE_START),"alpha's refused prepare assigned no id and moved nothing"):return false
		cover("failed_prepare_no_id")
	var r:Dictionary=await act("prepare_material_box",BENCH,k(PRIVATE[role]))
	if not check(r.get("ok")==true and str(r.get("source_cell",""))==k(PRIVATE[role]) and hex(r.get("source_id"),32),"prepare own private chest: \"%s\""%str(r.get("message",""))):return false
	private_id=str(r.source_id)
	prepared_ok+=1
	if not check(str(obj(PRIVATE[role]).get("box_id",""))==private_id and items_of(PRIVATE[role])==ints(PRIVATE_START) and inv_ok(),"own private id %s… visible to me, nothing moved"%private_id.left(8)):return false
	if role=="beta":
		var leak:=FileAccess.open(handoff.path_join("leak-contest-beta.txt"),FileAccess.WRITE)
		if not check(leak!=null,"wrote harness relay of my private id (simulated leak)"):return false
		leak.store_string(private_id)
		leak.close()
	go=await barrier("private_seen")
	if not go:return false
	var theirs:=obj(PRIVATE[other()])
	if not check(str(theirs.get("type",""))=="private_chest" and not theirs.has("box_id") and items_of(PRIVATE[other()]).is_empty() and theirs.get("locked")==true,
		"%s's prepared private chest shows me no box_id and no items (locked)"%other()):return false
	if not check(candidate_id(BENCH,PRIVATE[other()])=="<not a candidate>","%s's private chest is still not a candidate"%other()):return false
	cover("private_id_owner_only")
	if role=="alpha":
		var leaked:=FileAccess.get_file_as_string(handoff.path_join("leak-contest-beta.txt")).strip_edges()
		if not check(hex(leaked,32),"read beta's real private id from the harness relay"):return false
		foreign_ids.append(leaked)
		var recipe:Dictionary=World.CRAFT[BENCH_RECIPE]
		var fake:Dictionary=Supply.plan(recipe.ingredients,inventory(),PRIVATE_START)
		var dg:=Sources.digest("craft","bench",k(BENCH),BENCH_RECIPE,recipe,k(PRIVATE.beta),leaked,fake)
		var ok:bool=await refuse_private("forced craft with beta's REAL private id and a plausible digest","craft",BENCH,Sources.encode(BENCH_RECIPE,k(PRIVATE.beta),leaked,dg))
		if not ok:return false
		cover("leaked_id_refused")
	# ---- shared chest: concurrent prepare yields one id.
	go=await barrier("shared_prepare")
	if not go:return false
	if role=="beta":
		if not check(str(obj(PRIVATE.beta).get("box_id",""))==private_id and items_of(PRIVATE.beta)==ints(PRIVATE_START),"forced attempts changed nothing in my private chest"):return false
	r=await act("prepare_material_box",BENCH,k(CHEST))
	if not check(r.get("ok")==true and str(r.get("source_cell",""))==k(CHEST) and hex(r.get("source_id"),32),"prepare shared chest: \"%s\""%str(r.get("message",""))):return false
	chest_id=str(r.source_id)
	prepared_ok+=1
	mark({"mark":"shared_prepare","id":chest_id})
	go=await barrier("shared_prepared")
	if not go:return false
	if not check(str(obj(CHEST).get("box_id",""))==chest_id and chest_id!=private_id and items_of(CHEST)==ints(CHEST_START) and inv_ok(),"after both concurrent prepares the shared id is still the one I received; nothing moved"):return false
	cover("shared_prepare_same_id")
	# ---- bench race for limited wood.
	var pv:=preview("craft",BENCH,BENCH_RECIPE,CHEST)
	if not check(pv.ok and pv.from_backpack==ints({"stone":8}) and pv.from_chest==ints({"wood":4}) and pv.id==chest_id,"bench preview: backpack stone 8, chest wood 4: %s"%JSON.stringify(pv)):return false
	if not check(wire_ok(pv.wire),"sourced wire %d chars > %d, <= %d, grammar valid"%[str(pv.wire).length(),Session.PLAIN_EXTRA_MAX,Session.SOURCED_EXTRA_MAX]):return false
	mark({"mark":"bench_quote","digest":pv.digest})
	go=await barrier("bench_race")
	if not go:return false
	r=await act("craft",BENCH,pv.wire)
	bench_won=r.get("ok")==true
	if bench_won:
		if not check(ints(r.get("from_backpack"))==pv.from_backpack and ints(r.get("from_chest"))==pv.from_chest and str(r.get("source_cell",""))==k(CHEST) and str(r.get("source_id",""))==chest_id,
			"bench race won: committed exactly the confirmed split: \"%s\""%str(r.message)):return false
		expect_inv=plus(plus(expect_inv,pv.from_backpack,-1),{BENCH_RECIPE:int(World.CRAFT[BENCH_RECIPE]["yield"])})
		if not check(inv_ok(),"winner backpack exact %s"%inv_text()):return false
		sourced_ok+=1
	else:
		if not check(not r.has("timeout") and str(r.get("message","")).begins_with(MSG_SHORT) and r.get("requote",false)==false and not r.has("source_id") and inv_ok(),
			"bench race lost: refused '材料不足' with no charge: \"%s\" %s"%[str(r.get("message","")),inv_text()]):return false
	cover("bench_race")
	mark({"mark":"bench_race","won":bench_won,"digest":pv.digest})
	go=await barrier("bench_raced")
	if not go:return false
	if not check(items_of(CHEST)==ints({"wood":2,"radish":3}),"shared chest debited exactly once: %s (wood 6-4, never negative)"%JSON.stringify(items_of(CHEST))):return false
	if not bench_won:
		var stale_wire:String=pv.wire
		var ok:bool=await moves(RESTOCK,"withdraw",PRIVATE[role],"wood","已取出")
		if not ok:return false
		expect_inv=plus(expect_inv,{"wood":RESTOCK})
		if not check(inv_ok() and items_of(PRIVATE[role])==plus(PRIVATE_START,{"wood":RESTOCK},-1),"withdrew %d wood from my private chest"%RESTOCK):return false
		ok=await moves(RESTOCK,"deposit",CHEST,"wood","已存入")
		if not ok:return false
		expect_inv=plus(expect_inv,{"wood":RESTOCK},-1)
		if not check(inv_ok() and items_of(CHEST)==ints({"wood":2+RESTOCK,"radish":3}),"authorized deposit restocked shared chest: %s"%JSON.stringify(items_of(CHEST))):return false
		cover("authorized_restock")
		ok=await moves(1,"deposit",CHEST,"stone","已存入")
		if not ok:return false
		expect_inv=plus(expect_inv,{"stone":1},-1)
		var chest_before:=items_of(CHEST)
		r=await act("craft",BENCH,stale_wire)
		if not check(r.get("ok")==false and r.get("requote")==true and str(r.get("message",""))==Sources.MSG_STALE and ints(r.get("from_backpack"))==ints({"stone":7}) \
			and ints(r.get("from_chest"))==ints({"stone":1,"wood":4}) and inv_ok() and items_of(CHEST)==chest_before,
			"stale quote (split changed) rejected with requote + current split, no mutation: %s"%JSON.stringify(r)):return false
		cover("stale_requote")
		var fresh:=preview("craft",BENCH,BENCH_RECIPE,CHEST)
		if not check(fresh.ok and fresh.from_backpack==ints({"stone":7}) and fresh.from_chest==ints({"stone":1,"wood":4}) and fresh.digest!=pv.digest and wire_ok(fresh.wire),
			"fresh snapshot preview: backpack stone 7, chest stone 1 + wood 4, new digest"):return false
		r=await act("craft",BENCH,fresh.wire)
		if not check(r.get("ok")==true and ints(r.get("from_backpack"))==fresh.from_backpack and ints(r.get("from_chest"))==fresh.from_chest and str(r.get("source_id",""))==chest_id,
			"new confirmation commits the fresh split: \"%s\""%str(r.get("message",""))):return false
		expect_inv=plus(plus(expect_inv,fresh.from_backpack,-1),{BENCH_RECIPE:int(World.CRAFT[BENCH_RECIPE]["yield"])})
		sourced_ok+=1
		if not check(inv_ok() and items_of(CHEST)==ints({"wood":2,"radish":3}),"exact debit after fresh confirmation: inv %s chest %s"%[inv_text(),JSON.stringify(items_of(CHEST))]):return false
		cover("restock_fresh_quote")
	go=await barrier("bench_done")
	if not go:return false
	var own_private_want:=PRIVATE_START if bench_won else plus(PRIVATE_START,{"wood":RESTOCK},-1)
	if not check(items_of(CHEST)==ints({"wood":2,"radish":3}) and inv_ok() and items_of(PRIVATE[role])==ints(own_private_want),"bench settled: shared %s, own private %s"%[JSON.stringify(items_of(CHEST)),JSON.stringify(items_of(PRIVATE[role]))]):return false
	# ---- stove race for limited radish, then cancel refund to submitter.
	go=await barrier("stove_quote")
	if not go:return false
	var sv:=preview("queue_cook",STOVE,STOVE_RECIPE,CHEST)
	if not check(sv.ok and sv.from_backpack.is_empty() and sv.from_chest==ints(STOVE_COST) and sv.id==chest_id and wire_ok(sv.wire) and stove_records().is_empty(),"stove preview: chest radish 2, nothing from backpack: %s"%JSON.stringify(sv)):return false
	mark({"mark":"stove_quote","digest":sv.digest})
	go=await barrier("stove_race")
	if not go:return false
	var before_ids:=own_stove_ids()
	r=await act("queue_cook",STOVE,sv.wire)
	stove_won=r.get("ok")==true
	var job:=""
	if stove_won:
		var fresh_ids:=[]
		for id in own_stove_ids():
			if not id in before_ids:fresh_ids.append(id)
		if not check(fresh_ids.size()==1 and ints(r.get("from_chest"))==ints(STOVE_COST) and ints(r.get("from_backpack")).is_empty() and str(r.get("source_id",""))==chest_id,
			"stove race won: one own record, split chest radish 2: \"%s\""%str(r.get("message",""))):return false
		job=str(fresh_ids[0])
		if not check(ints(find_record(job).get("ingredients"))==ints(STOVE_COST) and inv_ok(),"record stores full ingredients; backpack unchanged %s"%inv_text()):return false
		sourced_ok+=1
	else:
		if not check(not r.has("timeout") and str(r.get("message","")).begins_with(MSG_SHORT) and r.get("requote",false)==false and own_stove_ids().is_empty() and inv_ok(),
			"stove race lost: '材料不足', no record, no charge: \"%s\""%str(r.get("message",""))):return false
	cover("stove_race")
	mark({"mark":"stove_race","won":stove_won,"digest":sv.digest})
	go=await barrier("stove_raced")
	if not go:return false
	if not check(items_of(CHEST)==ints({"wood":2,"radish":1}) and stove_records().size()==1,"stove: one record, chest radish 3-2=1: %s"%JSON.stringify(items_of(CHEST))):return false
	if stove_won:
		r=await act("cancel_queued_cook",STOVE,job)
		if not check(r.get("ok")==true and str(r.get("message","")).contains(MSG_CANCELLED),"exact-ID cancel of my sourced job: \"%s\""%str(r.get("message",""))):return false
		expect_inv=plus(expect_inv,STOVE_COST)
		if not check(inv_ok() and items_of(CHEST)==ints({"wood":2,"radish":1}) and stove_records().is_empty(),"refund went to my backpack %s, not the chest %s"%[inv_text(),JSON.stringify(items_of(CHEST))]):return false
		r=await act("cancel_queued_cook",STOVE,job)
		if not check(r.get("ok")==false and str(r.get("message","")).contains(MSG_NOT_FOUND) and inv_ok(),"second cancel of the same ID not found, no second refund: \"%s\""%str(r.get("message",""))):return false
		cover("stove_cancel_refund_once")
	go=await barrier("stove_done")
	if not go:return false
	if not check(stove_records().is_empty() and items_of(CHEST)==ints({"wood":2,"radish":1}) and inv_ok(),"stove settled, shared chest %s"%JSON.stringify(items_of(CHEST))):return false
	go=await barrier("final")
	if not go:return false
	final_mark()
	return true

# ---------------------------------------------------------------- restart

func read_plan() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("plan-restart.json")))
	if not data is Dictionary:return false
	for who in ROLES:
		var item=data.get(who)
		if not item is Dictionary or not item.get("inventory") is Dictionary or not item.get("chest") is Dictionary or not item.get("own_private") is Dictionary:return false
		if not hex(item.own_private.get("id"),32) or not hex(item.chest.get("id"),32):return false
	plan=data
	return true

func restart() -> bool:
	var mine:Dictionary=plan[role]
	expect_inv=ints(mine.inventory)
	chest_id=str(mine.chest.id)
	private_id=str(mine.own_private.id)
	if not check(inv_ok(),"persisted backpack %s"%inv_text()):return false
	if not check(str(obj(CHEST).get("box_id",""))==chest_id and items_of(CHEST)==ints(mine.chest.items),"shared chest id %s… and contents %s persisted"%[chest_id.left(8),JSON.stringify(items_of(CHEST))]):return false
	if not check(str(obj(PRIVATE[role]).get("box_id",""))==private_id and items_of(PRIVATE[role])==ints(mine.own_private.items),"own private id %s… and contents persisted"%private_id.left(8)):return false
	var theirs:=obj(PRIVATE[other()])
	if not check(not theirs.has("box_id") and items_of(PRIVATE[other()]).is_empty() and theirs.get("locked")==true,"%s's private chest still hidden after restart"%other()):return false
	if not check(not obj(SPARE).has("box_id") and items_of(SPARE)==ints(SPARE_START),"never-prepared spare chest still has no box_id"):return false
	if not check(stove_records().is_empty(),"stove has no leftover record"):return false
	if not check(candidate_id(BENCH,CHEST)==chest_id and candidate_id(BENCH,PRIVATE[role])==private_id and candidate_id(BENCH,PRIVATE[other()])=="<not a candidate>","candidates carry persisted ids, foreign private excluded"):return false
	cover("restart_persisted")
	var go:bool=await barrier("observed")
	if not go:return false
	var r:Dictionary=await act("prepare_material_box",BENCH,k(CHEST))
	if not check(r.get("ok")==true and str(r.get("source_id",""))==chest_id and str(obj(CHEST).get("box_id",""))==chest_id and inv_ok(),"prepare after restart is idempotent (same id, nothing moved)"):return false
	prepared_ok+=1
	cover("restart_prepare_same_id")
	if role=="alpha":
		var pv:=preview("craft",BENCH,OWN_RECIPE,PRIVATE.alpha)
		if not check(pv.ok and pv.from_backpack==ints({"copper_ore":2}) and pv.from_chest==ints({"wood":1}) and pv.id==private_id and wire_ok(pv.wire),"own private preview: backpack copper_ore 2, chest wood 1: %s"%JSON.stringify(pv)):return false
		r=await act("craft",BENCH,pv.wire)
		if not check(r.get("ok")==true and ints(r.get("from_backpack"))==pv.from_backpack and ints(r.get("from_chest"))==pv.from_chest and str(r.get("source_id",""))==private_id,
			"commit from own private chest with persisted id: \"%s\""%str(r.get("message",""))):return false
		expect_inv=plus(plus(expect_inv,pv.from_backpack,-1),{OWN_RECIPE:int(World.CRAFT[OWN_RECIPE]["yield"])})
		sourced_ok+=1
		if not check(inv_ok() and items_of(PRIVATE.alpha)==plus(mine.own_private.items,{"wood":1},-1),"exact debit: inv %s, private %s"%[inv_text(),JSON.stringify(items_of(PRIVATE.alpha))]):return false
		cover("restart_own_private_commit")
	else:
		var ok:bool=await refuse_private("prepare alpha's private chest after restart","prepare_material_box",BENCH,k(PRIVATE.alpha))
		if not ok:return false
		var leaked:=str(plan.alpha.own_private.id)
		var recipe:Dictionary=World.CRAFT[OWN_RECIPE]
		var fake:Dictionary=Supply.plan(recipe.ingredients,inventory(),plan.alpha.own_private.items)
		if not check(fake.ok,"plausible forged split computable"):return false
		var dg:=Sources.digest("craft","bench",k(BENCH),OWN_RECIPE,recipe,k(PRIVATE.alpha),leaked,fake)
		ok=await refuse_private("forced craft with alpha's REAL persisted private id","craft",BENCH,Sources.encode(OWN_RECIPE,k(PRIVATE.alpha),leaked,dg))
		if not ok:return false
		cover("leaked_id_refused")
	go=await barrier("after")
	if not go:return false
	if not check(inv_ok() and items_of(CHEST)==ints(mine.chest.items) and not obj(PRIVATE[other()]).has("box_id"),"after restart actions: shared chest unchanged, foreign private still hidden"):return false
	go=await barrier("final")
	if not go:return false
	final_mark()
	return true

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=4:
		push_error("MS_SEED_FAIL usage: seed <world.json> <alpha_token> <beta_token>")
		quit(2)
		return
	tokens={"alpha":args[2],"beta":args[3]}
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	var layout:={k(BENCH):{"type":"bench","owner":tokens.alpha,"items":{}},
		k(CHEST):{"type":"chest","owner":tokens.alpha,"items":CHEST_START.duplicate()},
		k(STOVE):{"type":"stove","owner":tokens.beta,"items":{}},
		k(PRIVATE.alpha):{"type":"private_chest","owner":tokens.alpha,"items":PRIVATE_START.duplicate()},
		k(PRIVATE.beta):{"type":"private_chest","owner":tokens.beta,"items":PRIVATE_START.duplicate()},
		k(SPARE):{"type":"chest","owner":tokens.beta,"items":SPARE_START.duplicate()}}
	var cells:={}
	for key in layout:cells[key]=true
	for who in STAND:cells[k(Vector2i(floori(STAND[who].x),floori(STAND[who].y)))]=true
	for key in cells:
		var c:=World.cell(key)
		if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c)!="":
			problems.append("cell %s is not clear home land"%key)
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(key):problems.append("cell %s already used in %s"%[key,layer])
	for key in layout:world.state.objects[key]=layout[key]
	for who in ROLES:
		world.add_player(tokens[who],who)
		var person:Dictionary=world.state.players[tokens[who]]
		var spot:Vector2=STAND[who]
		person.x=spot.x
		person.y=spot.y
		person.inventory=START.duplicate(true)
		if not world.can_stand(spot):problems.append("%s cannot stand at %s"%[who,spot])
		for cell in [BENCH,CHEST,STOVE,PRIVATE[who]]:
			var d:=spot.distance_to(Vector2(cell)+Vector2(0.5,0.5))
			if d>3.0:problems.append("%s is %.2f from %s (interaction range 3.2)"%[who,d,k(cell)])
	if not problems.is_empty():
		for problem in problems:push_error("MS_SEED_FAIL "+problem)
		quit(1)
		return
	if not world.save():
		push_error("MS_SEED_FAIL save: "+world.save_error)
		quit(1)
		return
	var reloaded:=World.new()
	var loaded:=reloaded.load_world(args[1])
	var objs:Dictionary=reloaded.state.objects if loaded else {}
	var ok:bool=loaded and not reloaded.recovered_from_backup and int(reloaded.state.version)==SaveSchema.VERSION
	for key in layout:
		var o=objs.get(key)
		if not o is Dictionary or str(o.get("type",""))!=str(layout[key].type) or o.has("box_id") or ints(o.get("items",{}))!=ints(layout[key].items):ok=false
	if not ok:
		push_error("MS_SEED_FAIL seeded save did not reload through SaveSchema with the exact layout and no box_id")
		quit(1)
		return
	var fixture:={"seed_version":int(reloaded.state.version),"protocol":int(Session.PROTOCOL),
		"cells":{"bench":k(BENCH),"chest":k(CHEST),"stove":k(STOVE),"private_alpha":k(PRIVATE.alpha),"private_beta":k(PRIVATE.beta),"spare":k(SPARE)},
		"start":START,"chest_start":CHEST_START,"private_start":PRIVATE_START,"spare_start":SPARE_START,
		"recipes":{"bench":BENCH_RECIPE,"stove":STOVE_RECIPE,"own":OWN_RECIPE},"restock":RESTOCK,
		"stand":{"alpha":[STAND.alpha.x,STAND.alpha.y],"beta":[STAND.beta.x,STAND.beta.y]}}
	print("MS_FIXTURE "+JSON.stringify(fixture))
	quit(0)
