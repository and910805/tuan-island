extends SceneTree
## Real multi-process network regression of the chapter-3 Tianwei cooperative
## flower nursery (protocol 44 / save 25 / release 0.49-dev) over plain loopback
## WebSocket (ws://127.0.0.1:<port>; NOT wss/TLS, NOT cloud, no adverse-network
## model). Every mutation goes client Session.perform -> request_action RPC ->
## SEPARATE dedicated Godot server -> World.act. No client touches a World.
## flower_ship / flower_give are acknowledged by the correlated
## action_completed(sequence); harvest/seed/transit are not correlated in
## Session.CORRELATED_ACTIONS, so for those the requester's own notice plus the
## resulting snapshot are observed (labelled "notice-observed").
##
## SEEDED NETWORK FIXTURE - NOT AN EARNED JOURNEY. The `seed` step is the ONLY
## direct state write (labelled, printed in FN_FIXTURE.seeded):
##   chapter_one     board/picnic/chapter_one shipped+watered, table 39,30
##   tea_unlock      alpha+beta tea_ceramics record = finished comparison
##   flower_records  alpha+beta: letter, intro, planted/harvested/saved x3,
##                   shipped=false (chapter at the ship/garden phase)
##   travel_book     alpha+beta visited home/maokong/yingge/tianwei, epoch 3
##   positions       alpha (28.5,25.0) bed/market midpoint, beta (33.8,25.5)
##                   market/garden stand, both region tianwei
##   inventories     exact flowers/dye/seed reserves + coins (see SEED_INV)
##   garden          shared garden given blue_dye2/orange2/chime1 (alpha 3,
##                   beta 2 contributed), not complete
##   foreign_bed     beta-owned mature bluebell on nursery bed 25,24
## gamma is NOT seeded: it joins fresh after the restart. The saved fixture is
## reloaded through World.load_world (SaveSchema) before the runner continues.
## Tokens come from FN_TOKENS and the room key from FN_ROOM_KEY (environment),
## never from the command line, and are never printed.
##
## Driven by work/flower-network/network_flowers.py. Args after `--`:
##   seed <world.json>                          -> FN_FIXTURE {json}
##   <live|restart> <port> <role> <handoff_dir>
## Barriers: client prints `FN_BARRIER <phase> <role> <name>` and waits for
## <handoff>/go-<phase>-<name>. Missing barrier/result = failure, never a skip.
## Output: FN_CHECK ok ..., FN_COVER <tag> <phase> <role>, FN_MARK {json},
## FN_WS_PASS / FN_WS_FAIL.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")

const CONTRACT_PROTOCOL:=45
const CONTRACT_SAVE:=26
const SEED_LABEL:="SEEDED NETWORK FIXTURE (game/tests/network_flowers.gd seed) - not an earned journey"
const SEEDED:=["chapter_one","tea_unlock","flower_records","travel_book","positions","inventories","garden","foreign_bed"]
const TABLE:=Vector2i(39,30)
const START:={"alpha":Vector2(28.5,25.0),"beta":Vector2(33.8,25.5)}
const GIVE_STAND:=Vector2(34.5,26.5)
const TRANSFER_STAND:=Vector2(13.5,26.5)
const HOME_FERRY:=Vector2i(47,30)
const FOREIGN_BED:=Vector2i(25,24)
const SEED_EPOCH:=3
const SEED_INV:={
	"alpha":{"bluebell":2,"orange_blossom":3,"chime_herb":2,"blue_dye":1,"bluebell_seed":1,"orange_blossom_seed":1,"chime_herb_seed":1},
	"beta":{"bluebell":2,"orange_blossom":3,"chime_herb":2,"blue_dye":2,"bluebell_seed":1,"orange_blossom_seed":1},
}
const SEED_COINS:={"alpha":120,"beta":60}
const SEED_GIVEN:={"blue_dye":2,"orange_blossom":2,"chime_herb":1}
const SEED_CONTRIB:={"alpha":3,"beta":2}
const GARDEN_ITEMS:=["blue_dye","orange_blossom","chime_herb"]
const MSG_FOREIGN_HARVEST:="這是其他島民的育苗床"
const MSG_SHIPPED:="合作訂單已出貨。"
const MSG_GARDEN_DONE:="公共花園已完成。"
const MSG_ROUTE_LOCKED:="請先沿站點依序走訪，再使用轉乘捷徑。"
const MSG_BLOOM:="公共花園開花了！"
const PHASE_ROLES:={"live":["alpha","beta"],"restart":["alpha","beta","gamma"]}
const WATCHDOG:={"live":70.0,"restart":30.0}
const JOIN_WAIT:=15.0
const RESULT_WAIT:=8.0
const PEER_WAIT:=15.0
const BARRIER_WAIT:=45.0
const WALK_WAIT:=15.0
const DROP_WAIT:=2.0
const ACTION_BUDGET:=9
const ACTION_WINDOW_MSEC:=1100

var session:Session
var phase:=""
var role:=""
var roles:Array=[]
var tokens:={}
var handoff:=""
var plan:Dictionary={}
var notices:Array=[]
var sent:Dictionary={}
var completed:Dictionary={}
var sends:Array=[]
var snapshots:=0
var online_max:=0
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

func snap() -> Dictionary:
	return session.snapshot if session!=null else {}

func me() -> Dictionary:
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

func flower() -> Dictionary:
	var f=snap().get("flower_nursery",{})
	return f if f is Dictionary else {}

func garden() -> Dictionary:
	var g=flower().get("garden",{})
	return g if g is Dictionary else {}

func given() -> Dictionary:
	return ints(garden().get("given",{}))

func own_view() -> Dictionary:
	var o=flower().get("own",{})
	return o if o is Dictionary else {}

func own_record() -> Dictionary:
	var r=own_view().get("own_record",{})
	return r if r is Dictionary else {}

func own_given() -> int:
	return int(own_view().get("own_given",-1))

## Kind + public owner only (growth/wet legitimately change with weather).
func crop(c:Vector2i) -> Dictionary:
	var o=snap().get("crops",{}).get(k(c))
	if not o is Dictionary:return {}
	return {"kind":str(o.get("kind","")),"owner":str(o.get("owner",""))}

func garden_summary() -> Dictionary:
	var g:=garden()
	return {"given":given(),"complete":g.get("complete")==true,"completed_at":float(g.get("completed_at",-2.0)),
		"contributor_count":int(g.get("contributor_count",-1)),"keys":(g.keys() as Array).size()}

## Everything a refused request must leave untouched.
func probe_state() -> String:
	return norm({"inv":ints(inventory()),"coins":coins(),"own":own_view(),"garden":garden_summary(),"bed":crop(FOREIGN_BED),"region":region(),"epoch":epoch()})

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
		for r in pop:n+=int(pop[r])
	online_max=maxi(online_max,n)
	var f=data.get("flower_nursery")
	if not f is Dictionary or f.has("players") or not f.get("garden") is Dictionary or f.garden.has("contributors") or not f.get("own") is Dictionary:
		flag("snapshot %d flower_nursery projection carries foreign records or misses own/garden"%snapshots)
	var players=data.get("players",{})
	if players is Dictionary:
		for pid in players:
			var person=players[pid]
			if person is Dictionary and str(pid)!=id:
				for field in ["inventory","coins","receipts","travel_book"]:
					if person.has(field):flag("snapshot %d shows another player's %s"%[snapshots,field])
	for field in ["tea_ceramics"]:
		var t=data.get(field,{})
		if t is Dictionary and t.has("players"):flag("snapshot %d carries all-player %s"%[snapshots,field])

func _on_notice(message:String,ok:bool) -> void:
	notices.append({"ok":ok,"message":message})
	for who in tokens:
		if message.contains(tokens[who]):flag("notice contains raw %s token"%who)
	print("FN_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func _on_completed(sequence:int,action:String,result:Dictionary) -> void:
	var text:=var_to_str(result)
	for who in tokens:
		if text.contains(tokens[who]):flag("action result contains raw %s token"%who)
	if not sent.has(sequence):flag("completion for unsent/replayed sequence %d (%s)"%[sequence,action])
	elif completed.has(sequence):flag("duplicate completion for sequence %d"%sequence)
	completed[sequence]={"action":action,"result":result}
	print("FN_DONE %s %s seq=%d action=%s ok=%s"%[phase,role,sequence,action,str(result.get("ok"))])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("FN_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("FN_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	data["phase"]=phase
	data["role"]=role
	print("FN_MARK "+JSON.stringify(data))

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

func barrier(name:String,quiet:bool=false) -> bool:
	if finished:return false
	print("FN_BARRIER %s %s %s"%[phase,role,name])
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

## NOT correlated (harvest/seed/transit): wait for this requester's next notice
## (the server only notices the actor) and then settle snapshots.
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

func refused(label:String,action:String,p:Vector2i,extra:String,message:String,correlated:bool) -> bool:
	var before:=probe_state()
	var r:Dictionary
	if correlated:r=await act(action,p,extra)
	else:r=await act_notice(action,p,extra)
	if not check(not r.has("timeout") and r.get("ok")==false and str(r.get("message",""))==message,
		"%s: %s refusal '%s' (got '%s')"%[label,"acknowledged" if correlated else "notice-observed",message,str(r.get("message",""))]):return false
	return check(inv_ok() and probe_state()==before,"%s: no debit/credit, record/garden/bed/region unchanged (%s)"%[label,inv_text()])

## Raw replay of an already used request_action sequence (LABELLED: straight to
## the RPC, not Session.perform). Must produce no completion, no notice, no change.
func replay(seq:int,action:String,p:Vector2i,extra:String) -> bool:
	var before:=probe_state()
	var done:=completed.size()
	var notes:=notices.size()
	session.request_action.rpc_id(1,seq,action,p,extra,region(),epoch())
	await create_timer(DROP_WAIT).timeout
	await settle()
	return check(completed.size()==done and notices.size()==notes and inv_ok() and probe_state()==before,
		"replayed request_action %s (same sequence %d) dropped by the server: no acknowledgement/notice, no second debit/credit, garden unchanged"%[action,seq])

## Real movement through Session.input_direction (movement RPC); proportional
## steering so the server-side walk converges on the waypoint.
func walk(points:Array) -> bool:
	for target in points:
		var arrived:=false
		var deadline:=Time.get_ticks_msec()+int(WALK_WAIT*1000)
		while Time.get_ticks_msec()<deadline and not finished:
			var d:Vector2=(target as Vector2)-pos()
			if d.length()<0.2:
				arrived=true
				break
			session.input_direction(d.limit_length(1.0) if d.length()>0.6 else d.normalized()*0.4)
			await create_timer(0.05).timeout
		session.input_direction(Vector2.ZERO)
		if not check(arrived,"walked over the movement RPC to %s (at %s)"%[str(target),str(pos())]):return false
	await create_timer(0.3).timeout
	await settle()
	return not finished

# ---------------------------------------------------------------- entry

func read_secrets() -> bool:
	var data=JSON.parse_string(OS.get_environment("FN_TOKENS"))
	if not data is Dictionary:return false
	for who in ["alpha","beta","gamma"]:
		var t=data.get(who)
		if not t is String or (t as String).length()<12 or (t as String).length()>64:return false
		tokens[who]=t
	return true

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=4 or not PHASE_ROLES.has(args[0]) or not args[2] in PHASE_ROLES[args[0]]:
		push_error("FN_FAIL usage: <live|restart> <port> <role> <handoff_dir>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	roles=PHASE_ROLES[phase]
	handoff=args[3]
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG[phase])))
	if not read_secrets():
		finish(false,"FN_TOKENS environment missing or invalid")
		return
	var room_key:=OS.get_environment("FN_ROOM_KEY")
	if room_key.length()<12:
		finish(false,"FN_ROOM_KEY environment missing")
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
	if not check("flower_ship" in Session.CORRELATED_ACTIONS and "flower_give" in Session.CORRELATED_ACTIONS,"flower_ship/flower_give are correlated (acknowledged by sequence)"):return
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
	var ok:bool
	if phase=="live":ok=await live()
	else:ok=await restart()
	if finished or not ok:
		if not finished:finish(false,"phase stopped without a recorded failure")
		return
	if not check(snapshots>0 and violation.is_empty(),"%d snapshots: no raw token, no foreign inventory/coins/receipts/travel_book, no all-player flower/tea records"%snapshots
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
	if ok:print("FN_WS_PASS %s %s transport=ws checks=%d snapshots=%d notices=%d completions=%d"%[phase,role,checks,snapshots,notices.size(),completed.size()])
	else:push_error("FN_WS_FAIL %s %s transport=ws after %d checks: %s | inv=%s | garden=%s | violation=%s"%[phase,role,checks,step,
		inv_text(),JSON.stringify(garden_summary()) if session!=null else "{}",violation])
	if session!=null:
		if session.multiplayer.multiplayer_peer!=null and not session.shutting_down:session.input_direction(Vector2.ZERO)
		session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

func final_mark(extra:Dictionary={}) -> void:
	var p:=pos()
	var data:={"mark":"final","inventory":ints(inventory()),"coins":coins(),"own":JSON.parse_string(JSON.stringify(own_view())),
		"garden":garden_summary(),"region":region(),"epoch":epoch(),"x":p.x,"y":p.y,"bed":JSON.parse_string(JSON.stringify(crop(FOREIGN_BED)))}
	data.merge(extra)
	mark(data)

# ---------------------------------------------------------------- live

func seeded_record_ok() -> bool:
	var r:=own_record()
	if r.get("letter")!=true or r.get("intro")!=true or r.get("shipped")!=false or r.get("complete")!=false:return false
	for kind in Flower.FLOWERS:
		if not (r.get("planted",{}) as Dictionary).has(kind) or not (r.get("saved",{}) as Dictionary).has(kind) or not (r.get("harvested",{}) as Dictionary).has(kind):return false
	return true

func live() -> bool:
	expect_inv=ints(SEED_INV[role])
	expect_coins=int(SEED_COINS[role])
	if not check(region()=="tianwei","seeded region: play happens in tianwei (region_id %s)"%region()):return false
	if not check(inv_ok(),"exact seeded backpack + coins %s"%inv_text()):return false
	if not check(epoch()==SEED_EPOCH and pos().distance_to(START[role])<0.05,"seeded travel_epoch %d and stand %s (at %s)"%[SEED_EPOCH,str(START[role]),str(pos())]):return false
	if not check(seeded_record_ok() and own_given()==int(SEED_CONTRIB[role]),"own flower record at the ship phase (letter/intro/planted/harvested/saved, not shipped), own_given %d"%own_given()):return false
	var g:=garden_summary()
	if not check(g.given==ints(SEED_GIVEN) and g.complete==false and is_equal_approx(g.completed_at,-1.0) and g.contributor_count==2 and g["keys"]==4,
		"shared garden seeded near completion, token-free projection: %s"%JSON.stringify(g)):return false
	var bed:=crop(FOREIGN_BED)
	if not check(str(bed.get("kind",""))=="bluebell" and str(bed.get("owner",""))==hid(tokens.beta),"foreign nursery bed %s is beta's (public id) mature bluebell"%k(FOREIGN_BED)):return false
	if not check(Flower.ORDER=={"bluebell":2,"orange_blossom":2,"chime_herb":1} and Flower.ORDER_PAY==176 and Flower.RESERVE=={"bluebell_seed":1,"orange_blossom_seed":1,"chime_herb_seed":1}
		and Flower.GARDEN_NEEDS=={"blue_dye":4,"orange_blossom":4,"chime_herb":2},"catalog: order 2/2/1 pays 176, reserve 1 seed each, garden needs 4/4/2"):return false
	mark({"mark":"seeded","garden":g,"own":JSON.parse_string(JSON.stringify(own_view())),"inventory":ints(inventory()),"coins":coins()})
	cover("seeded_view")
	# ---- denials: foreign bed (alpha), reserve rule (beta)
	var go:bool=await barrier("denial")
	if not go:return false
	var fine:bool
	if role=="alpha":
		fine=await refused("harvest beta's nursery bed","harvest",FOREIGN_BED,"",MSG_FOREIGN_HARVEST,false)
		if not fine:return false
		fine=await refused("seed onto beta's nursery bed","seed",FOREIGN_BED,"bluebell",Flower.FOREIGN_PLOT_MESSAGE,false)
		if not fine:return false
		cover("foreign_bed_denied")
	else:
		fine=await refused("ship without the chime_herb_seed reserve","flower_ship",Vector2i(Flower.MARKET),"",Flower.RESERVE_MESSAGE,true)
		if not fine:return false
		cover("reserve_denied")
	# ---- alpha ships the co-op order; replay + repeat dedupe
	go=await barrier("ship")
	if not go:return false
	if role=="alpha":
		var r:Dictionary=await act("flower_ship",Flower.MARKET,"")
		if not check(r.get("ok")==true and str(r.get("message","")).contains("+%d"%Flower.ORDER_PAY),"flower_ship acknowledged: \"%s\""%str(r.get("message",""))):return false
		var seq:=int(r._seq)
		expect_inv=plus(expect_inv,Flower.ORDER,-1)
		expect_coins+=Flower.ORDER_PAY
		if not check(inv_ok(),"exact debit bluebell2/orange2/chime1, coins +176: %s"%inv_text()):return false
		var reserve_ok:=true
		for s in Flower.RESERVE:
			if int(inventory().get(s,0))!=1:reserve_ok=false
		if not check(reserve_ok and own_record().get("shipped")==true,"reserve seeds remain 1 each; own record shipped"):return false
		fine=await replay(seq,"flower_ship",Flower.MARKET,"")
		if not fine:return false
		fine=await refused("second flower_ship with a fresh sequence","flower_ship",Flower.MARKET,"",MSG_SHIPPED,true)
		if not fine:return false
		cover("ship")
		cover("ship_replay_dropped")
		if not await walk([Vector2(28.5,26.5),GIVE_STAND]):return false
	go=await barrier("shipped_seen")
	if not go:return false
	var g2:=garden_summary()
	if not check(g2.given==ints(SEED_GIVEN) and g2.complete==false,"garden still %s before the race"%JSON.stringify(g2.given)):return false
	if not check(inv_ok(),"backpack still exact before the race: %s"%inv_text()):return false
	var reach:float=pos().distance_to(Vector2(Flower.GARDEN_CELL)+Vector2(0.5,0.5))
	if not check(reach<=3.2,"%s stands within reach of the garden (%.2f)"%[role,reach]):return false
	# ---- concurrent garden race
	go=await barrier("race",true)
	if not go:return false
	var before_inv:=ints(inventory())
	var before_own:=own_given()
	var claim:Dictionary=await act("flower_give",Flower.GARDEN_CELL,"")
	if not check(not claim.has("timeout"),"flower_give acknowledged by its sequence: \"%s\""%str(claim.get("message",""))):return false
	var won:bool=claim.get("ok")==true
	var after_inv:=ints(inventory())
	var taken:={}
	for item in before_inv:
		var d:=int(before_inv[item])-int(after_inv.get(item,0))
		if d!=0:taken[item]=d
	for item in after_inv:
		if not before_inv.has(item):taken[item]=-int(after_inv[item])
	var total:=0
	var only_garden:=true
	for item in taken:
		if not item in GARDEN_ITEMS or int(taken[item])<0:only_garden=false
		total+=int(taken[item])
	if won:
		if not check(only_garden and total>0 and own_given()==before_own+total,"race give accepted: took %s (only dye/orange/chime, seeds untouched), own_given %d -> %d"%[JSON.stringify(taken),before_own,own_given()]):return false
	else:
		if not check(str(claim.get("message",""))==MSG_GARDEN_DONE and taken.is_empty() and own_given()==before_own,"race give refused '%s' with nothing taken (got '%s')"%[MSG_GARDEN_DONE,str(claim.get("message",""))]):return false
	expect_inv=after_inv
	mark({"mark":"race","won":won,"message":str(claim.get("message","")),"taken":taken,"bloomed":str(claim.get("message","")).contains(MSG_BLOOM),"seq":int(claim._seq)})
	cover("garden_race")
	fine=await replay(int(claim._seq),"flower_give",Flower.GARDEN_CELL,"")
	if not fine:return false
	cover("give_replay_dropped")
	go=await barrier("race_seen")
	if not go:return false
	var g3:=garden_summary()
	if not check(g3.given==ints(Flower.GARDEN_NEEDS) and g3.complete==true and g3.completed_at>=0.0 and g3.contributor_count==2,
		"%s sees the garden complete with exactly the needs %s: %s"%[role,JSON.stringify(Flower.GARDEN_NEEDS),JSON.stringify(g3)]):return false
	mark({"mark":"garden_seen","garden":g3})
	fine=await refused("give after completion","flower_give",Flower.GARDEN_CELL,"",MSG_GARDEN_DONE,true)
	if not fine:return false
	cover("give_after_complete_denied")
	# ---- region travel through the real transit stations (alpha)
	go=await barrier("travel")
	if not go:return false
	if role=="alpha":
		if not await walk([Vector2(GIVE_STAND.x,26.5),TRANSFER_STAND]):return false
		var e0:=epoch()
		var r:Dictionary=await act_notice("transit",Flower.TRANSFER,"home")
		var home_ok:bool=await until(func():return region()=="home",RESULT_WAIT)
		if not check(r.get("ok")==true and home_ok and epoch()==e0+1 and pos().distance_to(Vector2(46.5,30.5))<1.5,
			"transit tianwei -> home at the 花圃接駁點: \"%s\", region %s, epoch %d, at %s"%[str(r.get("message","")),region(),epoch(),str(pos())]):return false
		if not check(garden_summary()==g3 and inv_ok() and own_record().get("shipped")==true,"home snapshot carries the same world-scoped garden and own record, backpack exact"):return false
		cover("travel_home")
		r=await act_notice("transit",HOME_FERRY,"tianwei")
		var back:bool=await until(func():return region()=="tianwei",RESULT_WAIT)
		if not check(r.get("ok")==true and back and epoch()==e0+2 and pos().distance_to(Flower.ARRIVAL)<1.5,
			"transit home ferry -> tianwei: \"%s\", region %s, epoch %d, at %s"%[str(r.get("message","")),region(),epoch(),str(pos())]):return false
		if not check(garden_summary()==g3 and inv_ok(),"back in tianwei: garden and backpack unchanged"):return false
		cover("travel_back")
	go=await barrier("final")
	if not go:return false
	if not check(inv_ok() and garden_summary()==g3 and region()=="tianwei","final: backpack exact, garden converged, region tianwei"):return false
	final_mark({"won":won})
	return true

# ---------------------------------------------------------------- restart

func read_plan() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("plan-restart.json")))
	if not data is Dictionary:return false
	for who in ["alpha","beta"]:
		var item=data.get(who)
		if not item is Dictionary or not item.get("inventory") is Dictionary or not item.get("own") is Dictionary or not item.get("garden") is Dictionary:return false
	plan=data
	return true

func restart() -> bool:
	var persisted:Dictionary=plan.alpha.garden
	var g:=garden_summary()
	if not check(norm(g)==norm(persisted) and g.complete==true and g.given==ints(Flower.GARDEN_NEEDS),
		"%s sees the persisted complete garden after normal restart: %s"%[role,JSON.stringify(g)]):return false
	if role=="gamma":
		if not check(not plan.has("gamma"),"gamma never joined before (late joiner)"):return false
		expect_inv=ints(inventory())
		expect_coins=coins()
		if not check(norm(own_record())==norm(Flower.FRESH) and own_given()==0,"late joiner gets its own FRESH flower record and own_given 0: %s"%JSON.stringify(own_view())):return false
		if not check(region()=="home","late joiner starts at home"):return false
		cover("late_join")
	else:
		var mine:Dictionary=plan[role]
		expect_inv=ints(mine.inventory)
		expect_coins=int(mine.coins)
		if not check(inv_ok(),"persisted backpack + coins %s == live final"%inv_text()):return false
		if not check(norm(own_view())==norm(mine.own),"persisted own flower record + own_given identical to live final"):return false
		if not check(region()==str(mine.region) and epoch()==int(mine.epoch) and pos().distance_to(Vector2(float(mine.x),float(mine.y)))<0.05,
			"persisted region %s, travel_epoch %d, position %s"%[region(),epoch(),str(pos())]):return false
		if not check(norm(crop(FOREIGN_BED))==norm(mine.bed),"beta's nursery bed persisted unchanged"):return false
		cover("reconnect")
	mark({"mark":"view_restarted","garden":g,"inventory":ints(inventory()),"coins":coins(),"own":JSON.parse_string(JSON.stringify(own_view())),"region":region()})
	var go:bool=await barrier("observed")
	if not go:return false
	if role=="gamma":
		var fine:bool=await refused("late joiner transits toward tianwei without the letter","transit",HOME_FERRY,"tianwei",MSG_ROUTE_LOCKED,false)
		if not fine:return false
		cover("late_join_route_locked")
	elif role=="beta":
		var fine:bool=await refused("give to the persisted complete garden","flower_give",Flower.GARDEN_CELL,"",MSG_GARDEN_DONE,true)
		if not fine:return false
		cover("restart_garden_enforced")
	go=await barrier("final")
	if not go:return false
	if not check(inv_ok() and norm(garden_summary())==norm(persisted),"end of restart: backpack exact, garden unchanged"):return false
	final_mark()
	return true

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=2:
		push_error("FN_SEED_FAIL usage: seed <world.json>")
		quit(2)
		return
	if not read_secrets():
		push_error("FN_SEED_FAIL FN_TOKENS environment missing or invalid")
		quit(2)
		return
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	# SEED chapter_one (finished chapter 1; transit needs the picnic)
	world.state.board=true
	world.state.picnic_materials={"soup":2,"bread":1}
	world.state.picnic=true
	world.state.community={"table":k(TABLE)}
	world.state.chapter_one={"shipped":true,"watered":true,"harvests":{},"starter_claims":{}}
	for who in ["alpha","beta"]:
		var tok:String=tokens[who]
		world.add_player(tok,who)
		# SEED tea_unlock (finished chapter-2 comparison)
		var t:Dictionary=Tea.FRESH.duplicate(true)
		t.intro=true;t.potter=true;t.reused=true;t.reuse_count=1
		t.trials={"jar":true,"fiber":true};t.tea_discussed=true;t.comparison_complete=true
		world.state.tea_ceramics.players[tok]=t
		# SEED flower_records (ship/garden phase)
		var r:Dictionary=Flower.FRESH.duplicate(true)
		r.letter=true;r.intro=true
		for kind in Flower.FLOWERS:
			r.planted[kind]=true
			r.harvested[kind]=2
			r.saved[kind]=true
		world.state.flower_nursery.players[tok]=r
		# SEED travel_book + positions + inventories
		var person:Dictionary=world.state.players[tok]
		for stop in ["maokong","yingge","tianwei"]:person.travel_book.visited[stop]=true
		person.region=Flower.REGION
		person.travel_epoch=SEED_EPOCH
		person.x=START[who].x
		person.y=START[who].y
		person.inventory=(SEED_INV[who] as Dictionary).duplicate(true)
		person.coins=int(SEED_COINS[who])
	# SEED garden near completion
	var gd:Dictionary=world.state.flower_nursery.garden
	gd.given=SEED_GIVEN.duplicate(true)
	gd.contributors={tokens.alpha:int(SEED_CONTRIB.alpha),tokens.beta:int(SEED_CONTRIB.beta)}
	gd.complete=false
	gd.completed_at=-1.0
	# SEED foreign_bed: beta's mature bluebell on a nursery bed
	if not Flower.NURSERY_BEDS.has_point(FOREIGN_BED):problems.append("foreign bed outside the nursery beds")
	world.state.regions[Flower.REGION].crops[k(FOREIGN_BED)]={"kind":"bluebell","growth":float(Flower.CROPS.bluebell.time),"wet":false,"owner":tokens.beta,"remaining":1}
	# geometry checks (reach 3.2 as in World._apply)
	world.switch_region(Flower.REGION)
	var reach:={"alpha":[FOREIGN_BED,Flower.MARKET],"beta":[Flower.MARKET,Flower.GARDEN_CELL],"give":[Flower.GARDEN_CELL],"transfer":[Flower.TRANSFER]}
	var spots:={"alpha":START.alpha,"beta":START.beta,"give":GIVE_STAND,"transfer":TRANSFER_STAND}
	for spot in spots:
		if not world.can_stand(spots[spot]):problems.append("cannot stand at %s %s"%[spot,str(spots[spot])])
		for c in reach[spot]:
			var d:float=(spots[spot] as Vector2).distance_to(Vector2(c)+Vector2(0.5,0.5))
			if d>3.2:problems.append("%s is %.2f from %s"%[spot,d,k(c)])
	for x in range(13,35):
		if not world.can_stand(Vector2(x+0.5,26.5)):problems.append("walk row y=26.5 blocked at x=%d"%x)
	if not world.can_stand(Vector2(28.5,26.5)):problems.append("walk waypoint blocked")
	world.switch_region("home")
	if not world.can_stand(World.SPAWN):problems.append("late joiner spawn blocked")
	if not problems.is_empty():
		for problem in problems:push_error("FN_SEED_FAIL "+problem)
		quit(1)
		return
	if not world.save():
		push_error("FN_SEED_FAIL save: "+str(world.save_error))
		quit(1)
		return
	var reloaded:=World.new()
	var loaded:bool=reloaded.load_world(args[1])
	var ok:bool=loaded and not reloaded.recovered_from_backup and int(reloaded.state.version)==SaveSchema.VERSION and int(SaveSchema.VERSION)==CONTRACT_SAVE
	if ok:
		for who in ["alpha","beta"]:
			var tok:String=tokens[who]
			ok=ok and ints(reloaded.state.players[tok].inventory)==ints(SEED_INV[who]) and int(reloaded.state.players[tok].coins)==int(SEED_COINS[who])
			ok=ok and Flower.phase(reloaded.state,tok)=="ship" and reloaded.player_region(tok)==Flower.REGION
		ok=ok and ints(reloaded.state.flower_nursery.garden.given)==ints(SEED_GIVEN) and reloaded.state.flower_nursery.garden.complete==false
		ok=ok and reloaded.state.regions[Flower.REGION].crops.has(k(FOREIGN_BED))
	if not ok:
		push_error("FN_SEED_FAIL seeded save did not reload through SaveSchema as the ship-phase flower fixture (loaded=%s)"%str(loaded))
		quit(1)
		return
	var out:={"label":SEED_LABEL,"seeded":SEEDED,"seed_version":int(reloaded.state.version),"protocol":int(Session.PROTOCOL),
		"inventories":SEED_INV,"coins":SEED_COINS,"given":SEED_GIVEN,"contributors":SEED_CONTRIB,"epoch":SEED_EPOCH,
		"foreign_bed":k(FOREIGN_BED),"start":{"alpha":[START.alpha.x,START.alpha.y],"beta":[START.beta.x,START.beta.y]},
		"phase":{"alpha":Flower.phase(reloaded.state,tokens.alpha),"beta":Flower.phase(reloaded.state,tokens.beta)},
		"needs":Flower.GARDEN_NEEDS,"order":Flower.ORDER,"order_pay":Flower.ORDER_PAY,"reserve":Flower.RESERVE}
	print("FN_FIXTURE "+JSON.stringify(out))
	quit(0)
