extends SceneTree
## Real multi-process network regression of the T042 public kitchen (protocol
## 41 / save 23, docs/public-kitchen-contract.json) over plain loopback
## WebSocket (ws://127.0.0.1:<port>; NOT wss/TLS, NOT cloud, no adverse-network
## model). Every mutation goes client Session.perform -> request_action RPC ->
## SEPARATE dedicated Godot server -> World.act. No client touches a World.
##
## AUTHORIZED SEEDED LOCAL FIXTURE - NOT AN EARNED JOURNEY. The `seed` step is
## the ONLY direct state write and is limited to, labelled:
##   picnic   board=true, picnic_materials 2/1, picnic=true
##   table    community.table = 39,30
##   Aru      stories.aru >= 2 for alpha/beta (long_bench unlock in normal play)
##   objects  alpha: stove SA(41,34) + long_bench (42,36),(43,35)
##            beta:  stove SB(37,34) + long_bench (35,35),(36,36)
##   positions alpha (39.5,35.5), beta (39.5,33.5) - both within 3.2 of SA and SB
##   food     each backpack exactly {soup 2, bread 1, salad 2, radish 2}
## public_kitchen stays fresh() in the seed; registration, contributions,
## cooking and claims happen only through Session.perform.
##
## Driven by work/public-kitchen/network_public_kitchen.py. Args after `--`:
##   seed <world.json> <alpha_token> <beta_token>        -> PK_FIXTURE {json}
##   <live|restart> <port> <role> <room_key> <alpha> <beta> <gamma> <handoff_dir>
## Barriers: client prints `PK_BARRIER <phase> <role> <name>` and waits for
## <handoff>/go-<phase>-<name> (written by the runner once every role of the
## phase printed it). Missing barrier/result = failure, never a skip.
##
## live (alpha, beta):
##   initial    exact food backpacks, kitchen fresh, events [invitation],
##              candidate_stoves = own stove only.
##   ownership  beta registers alpha's stove+seats -> "只能捐出自己蓋的小石灶。";
##              alpha registers own stove with beta's seats -> "只能捐出自己蓋的長椅。";
##              contribute before registration -> "公共廚房還沒有登記。". No change.
##   race       both register their OWN valid site at the same barrier: exactly
##              one ok, the other "渡口已經有公共廚房了…". Donated stove keeps the
##              donor's (hashed) owner; loser site untouched.
##   permanence donor `remove` of donated stove -> MSG_LOCKED.
##   partial    guest (non-donor) contributes first: exactly soup2 bread1 salad2.
##   guest cook guest queue_cook soup on the PUBLIC stove, claims (+2 soup).
##   replay     guest re-sends its contribute RPC with the SAME sequence (raw
##              Session.request_action.rpc_id, labelled; not Session.perform):
##              the server drops it - no completion, no debit though the guest
##              now holds soup that is still needed.
##   complete   donor contributes: exactly soup2 bread1 (salad kept); opened.
##   repeats    both contribute again via Session.perform -> refused, no debit.
## restart (normal server stop + restart on the same save; alpha, beta and a
##   never-seen gamma = late joiner): exact persisted kitchen/backpacks, same
##   events for all three, donated stove still locked, contribute refused.
## Every snapshot: no raw token, no foreign inventory, public_kitchen has exactly
## the 4 contract keys and contains no player id/token.
## Output: PK_CHECK ok ..., PK_COVER <tag> <phase> <role>, PK_MARK {json},
## PK_WS_PASS / PK_WS_FAIL.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const PK=preload("res://scripts/public_kitchen.gd")

const CONTRACT_PROTOCOL:=42
const CONTRACT_SAVE:=23
const TABLE:=Vector2i(39,30)
const SITE:={"alpha":{"stove":Vector2i(41,34),"seats":[Vector2i(42,36),Vector2i(43,35)]},
	"beta":{"stove":Vector2i(37,34),"seats":[Vector2i(35,35),Vector2i(36,36)]}}
const STAND:={"alpha":Vector2(39.5,35.5),"beta":Vector2(39.5,33.5)}
const FOOD:={"soup":2,"bread":1,"salad":2,"radish":2}
const PHASE_ROLES:={"live":["alpha","beta"],"restart":["alpha","beta","gamma"]}
const WATCHDOG:={"live":60.0,"restart":35.0}
const JOIN_WAIT:=15.0
const RESULT_WAIT:=8.0
const PEER_WAIT:=20.0
const BARRIER_WAIT:=40.0
const COOK_WAIT:=25.0
const DROP_WAIT:=2.0
const ACTION_BUDGET:=9
const ACTION_WINDOW_MSEC:=1100
const MSG_OWN_STOVE:="只能捐出自己蓋的小石灶。"
const MSG_OWN_SEAT:="只能捐出自己蓋的長椅。"
const MSG_UNREGISTERED:="公共廚房還沒有登記。"
const MSG_ALREADY:="渡口已經有公共廚房了，不需要再捐一次。"
const MSG_OPENED:="公共廚房已經開張了，謝謝大家！"

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
var home_snapshots:=0
var online_max:=0
var violation:=""
var checks:=0
var finished:=false
var expect_inv:Dictionary={}
var donor:=""

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

static func plus(a:Dictionary,b:Dictionary,sign:int=1) -> Dictionary:
	var out:=ints(a)
	for item in b:
		out[str(item)]=int(out.get(str(item),0))+sign*int(b[item])
		if int(out[str(item)])==0:out.erase(str(item))
	return out

## Untyped copy (typed Array[String] results compare reliably against literals).
static func plain(a:Variant) -> Array:
	var out:=[]
	if a is Array:
		for v in a:out.append(str(v))
	return out

## Kitchen dictionary in comparable form (JSON round trips turn ints into floats).
static func norm_kitchen(pk:Variant) -> Dictionary:
	if not pk is Dictionary:return {"<missing>":true}
	var meals:={}
	if pk.get("meals") is Dictionary:
		for m in pk.meals:meals[str(m)]=int(pk.meals[m])
	return {"stove":str(pk.get("stove","<none>")),"seats":plain(pk.get("seats")),"meals":meals,"opened":pk.get("opened")==true,
		"keys":int(pk.get("keys",(pk.keys() as Array).size()))}

static func seats_extra(owner:String) -> String:
	return PK.seat_extra(SITE[owner].seats[0],SITE[owner].seats[1])

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

func obj(cell:Vector2i) -> Dictionary:
	var o=snap().get("objects",{}).get(k(cell))
	return o if o is Dictionary else {}

## Public kitchen exactly as received, normalised to plain JSON types.
func kitchen() -> Dictionary:
	var pk=snap().get("public_kitchen")
	if not pk is Dictionary:return {"<missing>":true}
	var out:=norm_kitchen(pk)
	out["keys"]=(pk.keys() as Array).size()
	return out

func stove_ready() -> bool:
	var q=obj(stove_cell()).get("cooking")
	return q is Dictionary and q.get("ready") is Array and not (q.ready as Array).is_empty()

func want_kitchen(stove:String,seats:Array,meals:Dictionary,opened:bool) -> Dictionary:
	return {"stove":stove,"seats":seats,"meals":meals,"opened":opened,"keys":4}

func event_ids() -> Array:
	var out:=[]
	for e in PK.events(snap()):out.append(str(e.get("id","")))
	return out

func stove_cell() -> Vector2i:
	return SITE[donor].stove

func other() -> String:
	return "beta" if role=="alpha" else "alpha"

func guest() -> String:
	return "beta" if donor=="alpha" else "alpha"

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
	var pk=data.get("public_kitchen")
	if not pk is Dictionary or (pk.keys() as Array).size()!=4 or not (pk.has("stove") and pk.has("seats") and pk.has("meals") and pk.has("opened")):
		flag("snapshot %d: public_kitchen missing or not exactly {stove,seats,meals,opened}"%snapshots)
	else:
		var pk_text:=var_to_str(pk)
		for who in tokens:
			if pk_text.contains(hid(tokens[who])):flag("snapshot %d: public_kitchen carries a player id"%snapshots)
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
	print("PK_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func _on_completed(sequence:int,action:String,result:Dictionary) -> void:
	var text:=var_to_str(result)
	for who in tokens:
		if text.contains(tokens[who]):flag("action result contains raw %s token"%who)
	if not sent.has(sequence):flag("completion for unsent/replayed sequence %d (%s)"%[sequence,action])
	elif completed.has(sequence):flag("duplicate completion for sequence %d"%sequence)
	completed[sequence]={"action":action,"result":result}
	print("PK_DONE %s %s seq=%d action=%s ok=%s"%[phase,role,sequence,action,str(result.get("ok"))])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("PK_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("PK_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	data["phase"]=phase
	data["role"]=role
	print("PK_MARK "+JSON.stringify(data))

func view_mark(name:String) -> void:
	mark({"mark":"view_"+name,"kitchen":kitchen(),"events":event_ids()})

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
	print("PK_BARRIER %s %s %s"%[phase,role,name])
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
## EXACTLY this sequence. Returns the result plus "_seq".
func act(action:String,p:Vector2i,extra:String="") -> Dictionary:
	await pace()
	var seq:int=session.perform(action,p,extra)
	if seq<=0:return {"ok":false,"message":"<perform refused locally>","timeout":true}
	sent[seq]=action
	var got:bool=await until(func():return completed.has(seq),RESULT_WAIT)
	if not got:return {"ok":false,"message":"<no correlated completion for sequence %d>"%seq,"timeout":true}
	var entry:Dictionary=completed[seq]
	if not check(str(entry.action)==action,"sequence %d completed as '%s'"%[seq,action]):return {"ok":false,"timeout":true}
	await settle()
	var r:Dictionary=(entry.result as Dictionary).duplicate()
	r["_seq"]=seq
	return r

## Non-correlated action (e.g. remove) through Session.perform: the result is
## the next own notice, which Session._action always sends to the requester.
func act_notice(action:String,p:Vector2i,extra:String="") -> Dictionary:
	await pace()
	var index:=notices.size()
	session.perform(action,p,extra)
	var got:bool=await until(func():return notices.size()>index,RESULT_WAIT)
	if not got:return {"ok":false,"message":"<no notice within %ds>"%int(RESULT_WAIT),"timeout":true}
	await settle()
	return notices[index]

## A refusal that must leave kitchen and own backpack untouched.
func refused(label:String,action:String,p:Vector2i,extra:String,message:String) -> bool:
	var before:=kitchen()
	var r:Dictionary=await act(action,p,extra)
	if not check(not r.has("timeout") and r.get("ok")==false and str(r.get("message",""))==message,
		"%s: refused '%s' (got '%s')"%[label,message,str(r.get("message",""))]):return false
	return check(inv_ok() and kitchen()==before,"%s: no debit, kitchen unchanged (inv %s)"%[label,inv_text()])

# ---------------------------------------------------------------- entry

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if args.size()!=8 or not PHASE_ROLES.has(args[0]) or not args[2] in PHASE_ROLES[args[0]]:
		push_error("PK_FAIL usage: <live|restart> <port> <role> <room_key> <alpha> <beta> <gamma> <handoff_dir>")
		quit(2)
		return
	phase=args[0]
	role=args[2]
	roles=PHASE_ROLES[phase]
	tokens={"alpha":args[4],"beta":args[5],"gamma":args[6]}
	handoff=args[7]
	create_timer(float(WATCHDOG[phase])).timeout.connect(func():finish(false,"watchdog: phase exceeded %ds"%int(WATCHDOG[phase])))
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
	if not check(int(Session.PROTOCOL)==CONTRACT_PROTOCOL and int(SaveSchema.VERSION)==CONTRACT_SAVE and int(PK.VERSION)==CONTRACT_SAVE,
		"Session.PROTOCOL %d / SaveSchema.VERSION %d == contract %d / %d"%[int(Session.PROTOCOL),int(SaveSchema.VERSION),CONTRACT_PROTOCOL,CONTRACT_SAVE]):return
	if not check(Session.KITCHEN_REGISTER in Session.CORRELATED_ACTIONS and Session.KITCHEN_CONTRIBUTE in Session.CORRELATED_ACTIONS and "queue_cook" in Session.CORRELATED_ACTIONS,
		"kitchen_register / kitchen_contribute / queue_cook are correlated actions"):return
	var port:=int(args[1])
	var address:="ws://127.0.0.1:%d"%port
	var err:=session.join(address,port,role,args[3])
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
	if not check(home_snapshots>0 and violation.is_empty(),"%d snapshots: no raw token, no foreign inventory, public_kitchen exactly 4 keys without player ids"%snapshots
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
	if ok:print("PK_WS_PASS %s %s transport=ws checks=%d snapshots=%d notices=%d completions=%d"%[phase,role,checks,snapshots,notices.size(),completed.size()])
	else:push_error("PK_WS_FAIL %s %s transport=ws after %d checks: %s | kitchen=%s | inv=%s | violation=%s"%[phase,role,checks,step,
		JSON.stringify(kitchen()) if session!=null else "{}",inv_text(),violation])
	if session!=null:session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

func final_mark() -> void:
	mark({"mark":"final","inventory":ints(inventory()),"kitchen":kitchen(),"events":event_ids(),"donor":donor})

# ---------------------------------------------------------------- live

func live() -> bool:
	expect_inv=ints(FOOD)
	var fresh:=want_kitchen("",[],{"soup":0,"bread":0,"salad":0},false)
	if not check(inv_ok(),"exact seeded food backpack %s"%inv_text()):return false
	if not check(kitchen()==fresh and PK.stage(snap())=="register","kitchen fresh and stage 'register': %s"%JSON.stringify(kitchen())):return false
	if not check(event_ids()==["kitchen_invitation"],"events before registration: %s"%str(event_ids())):return false
	var mine:Vector2i=SITE[role].stove
	if not check(plain(PK.candidate_stoves(snap(),session.own_id))==[k(mine)],"UI candidate_stoves(snapshot, own public id) == only my stove %s"%k(mine)):return false
	if not check(plain(PK.candidate_seats(snap(),session.own_id,mine))==[k(SITE[role].seats[0]),k(SITE[role].seats[1])],"UI candidate_seats == my two long benches"):return false
	if not check(str(obj(mine).get("owner",""))==session.own_id and str(obj(SITE[other()].stove).get("owner",""))==hid(tokens[other()]),
		"snapshot: own stove owner is my public id, the other stove is %s's"%other()):return false
	view_mark("fresh")
	# ---- ownership probes (refused, nothing changes)
	var go:bool=await barrier("ownership")
	if not go:return false
	var fine:bool
	if role=="beta":
		fine=await refused("beta registers alpha's stove + seats","kitchen_register",SITE.alpha.stove,seats_extra("alpha"),MSG_OWN_STOVE)
	else:
		fine=await refused("alpha registers own stove with beta's seats","kitchen_register",SITE.alpha.stove,seats_extra("beta"),MSG_OWN_SEAT)
	if not fine:return false
	fine=await refused("contribute before registration","kitchen_contribute",mine,"",MSG_UNREGISTERED)
	if not fine:return false
	cover("ownership_refused")
	# ---- registration race: both own a valid candidate site
	go=await barrier("register_race")
	if not go:return false
	var r:Dictionary=await act("kitchen_register",mine,seats_extra(role))
	var won:bool=r.get("ok")==true
	if won:
		if not check(str(r.get("stove",""))==k(mine) and plain(r.get("seats"))==[k(SITE[role].seats[0]),k(SITE[role].seats[1])],"registration won: result names my stove and sorted seats: \"%s\""%str(r.get("message",""))):return false
	else:
		if not check(not r.has("timeout") and str(r.get("message",""))==MSG_ALREADY,"registration lost: refused '%s' (got '%s')"%[MSG_ALREADY,str(r.get("message",""))]):return false
	if not check(inv_ok(),"registration costs/rewards nothing: %s"%inv_text()):return false
	mark({"mark":"register_race","won":won})
	cover("register_race")
	go=await barrier("registered")
	if not go:return false
	var pk:=kitchen()
	donor="alpha" if pk.stove==k(SITE.alpha.stove) else ("beta" if pk.stove==k(SITE.beta.stove) else "")
	if not check(donor!="" and (donor==role)==won,"exactly the race winner's site is registered (donor %s, I won=%s)"%[donor,str(won)]):return false
	var seats:Array=[k(SITE[donor].seats[0]),k(SITE[donor].seats[1])]
	if not check(pk==want_kitchen(k(SITE[donor].stove),seats,{"soup":0,"bread":0,"salad":0},false),"shared kitchen exact after registration: %s"%JSON.stringify(pk)):return false
	if not check(str(obj(stove_cell()).get("owner",""))==hid(tokens[donor]) and str(obj(SITE[guest()].stove).get("owner",""))==hid(tokens[guest()])
		and str(obj(SITE[guest()].seats[0]).get("type",""))=="long_bench","donated stove keeps donor's public owner; loser's site untouched"):return false
	if not check(event_ids()==["kitchen_invitation","kitchen_registration"],"events after registration: %s"%str(event_ids())):return false
	view_mark("registered")
	if role==donor:
		var before:=kitchen()
		r=await act_notice("remove",stove_cell(),"")
		if not check(r.get("ok")==false and str(r.get("message",""))==PK.MSG_LOCKED and kitchen()==before and str(obj(stove_cell()).get("type",""))=="stove",
			"donor cannot remove the donated stove: \"%s\""%str(r.get("message",""))):return false
		cover("donated_locked")
	# ---- partial contribution by the guest (non-donor)
	go=await barrier("partial")
	if not go:return false
	var contribute_seq:=0
	if role==guest():
		r=await act("kitchen_contribute",stove_cell(),"")
		if not check(r.get("ok")==true and ints(r.get("contributed"))==ints({"soup":2,"bread":1,"salad":2}) and r.get("opened")==false,
			"guest partial contribution exactly soup2 bread1 salad2: %s"%JSON.stringify(r)):return false
		contribute_seq=int(r._seq)
		expect_inv=plus(expect_inv,{"soup":2,"bread":1,"salad":2},-1)
		if not check(inv_ok(),"guest backpack debited exactly: %s"%inv_text()):return false
		cover("partial_contribution")
	go=await barrier("partial_seen")
	if not go:return false
	if not check(kitchen()==want_kitchen(k(stove_cell()),seats,{"soup":2,"bread":1,"salad":2},false) and inv_ok(),"both see partial kitchen %s; my backpack %s"%[JSON.stringify(kitchen()),inv_text()]):return false
	view_mark("partial")
	# ---- guest cooks on the public stove, then replays the old contribute RPC
	if role==guest():
		r=await act("queue_cook",stove_cell(),"soup")
		if not check(r.get("ok")==true and str(r.get("kind",""))=="soup","guest queue_cook soup on the donated public stove: \"%s\""%str(r.get("message",""))):return false
		expect_inv=plus(expect_inv,World.RECIPES.soup.ingredients,-1)
		if not check(inv_ok(),"guest paid exactly the soup ingredients: %s"%inv_text()):return false
		var ready:bool=await until(stove_ready,COOK_WAIT)
		if not check(ready,"public stove soup ready within %ds"%int(COOK_WAIT)):return false
		r=await act("claim_cook",stove_cell(),"")
		var gain:=int(World.RECIPES.soup["yield"])
		if not check(r.get("ok")==true and int(r.get("yield",0))==gain,"guest claims %d soup from the public stove"%gain):return false
		expect_inv=plus(expect_inv,{"soup":gain})
		if not check(inv_ok() and kitchen().meals=={"soup":2,"bread":1,"salad":2},"cooking left the kitchen record unchanged; backpack %s"%inv_text()):return false
		cover("guest_cook")
		# LABELLED raw replay: same sequence, same action, sent straight to the RPC.
		var before_done:=completed.size()
		var before_notes:=notices.size()
		var epoch:=int(me().get("travel_epoch",0))
		session.request_action.rpc_id(1,contribute_seq,"kitchen_contribute",stove_cell(),"","home",epoch)
		await create_timer(DROP_WAIT).timeout
		await settle()
		if not check(completed.size()==before_done and notices.size()==before_notes and inv_ok() and kitchen().meals=={"soup":2,"bread":1,"salad":2},
			"replayed contribute RPC (sequence %d) dropped by server: no completion/notice, still holding needed soup %s"%[contribute_seq,inv_text()]):return false
		cover("replay_no_double_debit")
	# ---- donor completes
	go=await barrier("complete")
	if not go:return false
	if role==donor:
		r=await act("kitchen_contribute",stove_cell(),"")
		if not check(r.get("ok")==true and ints(r.get("contributed"))==ints({"soup":2,"bread":1}) and r.get("opened")==true,
			"donor completes with exactly the outstanding soup2 bread1: %s"%JSON.stringify(r)):return false
		expect_inv=plus(expect_inv,{"soup":2,"bread":1},-1)
		if not check(inv_ok(),"donor keeps its salad: %s"%inv_text()):return false
		cover("completion")
	go=await barrier("opened")
	if not go:return false
	var full:=want_kitchen(k(stove_cell()),seats,{"soup":4,"bread":2,"salad":2},true)
	if not check(kitchen()==full and PK.stage(snap())=="open","both see the opened kitchen %s"%JSON.stringify(kitchen())):return false
	if not check(event_ids()==["kitchen_invitation","kitchen_registration","kitchen_opening"],"events after opening: %s"%str(event_ids())):return false
	view_mark("opened")
	fine=await refused("repeat contribute after opening","kitchen_contribute",stove_cell(),"",MSG_OPENED)
	if not fine:return false
	fine=await refused("repeat registration of my own site","kitchen_register",mine,seats_extra(role),MSG_ALREADY)
	if not fine:return false
	cover("repeat_refused")
	go=await barrier("final")
	if not go:return false
	final_mark()
	return true

# ---------------------------------------------------------------- restart

func read_plan() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("plan-restart.json")))
	if not data is Dictionary:return false
	for who in ["alpha","beta"]:
		var item=data.get(who)
		if not item is Dictionary or not item.get("inventory") is Dictionary or not item.get("kitchen") is Dictionary or not item.get("events") is Array:return false
	if not str(data.alpha.get("donor","")) in ["alpha","beta"]:return false
	plan=data
	return true

func restart() -> bool:
	donor=str(plan.alpha.donor)
	var persisted:=norm_kitchen(plan.alpha.kitchen)
	if not check(persisted.opened==true and kitchen()==persisted,"kitchen after normal restart == live final: %s"%JSON.stringify(kitchen())):return false
	if not check(event_ids()==plain(plan.alpha.events),"events replayed after restart: %s"%str(event_ids())):return false
	if not check(str(obj(stove_cell()).get("owner",""))==hid(tokens[donor]),"donated stove still owned (publicly) by the donor"):return false
	if role=="gamma":
		if not check(not plan.has("gamma"),"gamma never joined before (late joiner)"):return false
		expect_inv=ints(inventory())
		cover("late_join")
	else:
		expect_inv=ints(plan[role].inventory)
		if not check(inv_ok(),"persisted backpack %s"%inv_text()):return false
		cover("reconnect")
	view_mark("restarted")
	var go:bool=await barrier("observed")
	if not go:return false
	if role==donor:
		var r:Dictionary=await act_notice("remove",stove_cell(),"")
		if not check(r.get("ok")==false and str(r.get("message",""))==PK.MSG_LOCKED and str(obj(stove_cell()).get("type",""))=="stove","donated stove still locked after restart"):return false
	else:
		var fine:bool=await refused("%s contributes after restart"%role,"kitchen_contribute",stove_cell(),"",MSG_OPENED)
		if not fine:return false
	go=await barrier("final")
	if not go:return false
	if not check(kitchen()==persisted and inv_ok(),"kitchen and backpack unchanged at end of restart phase"):return false
	final_mark()
	return true

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=4:
		push_error("PK_SEED_FAIL usage: seed <world.json> <alpha_token> <beta_token>")
		quit(2)
		return
	tokens={"alpha":args[2],"beta":args[3]}
	var world:=World.new()
	world.save_path=args[1]
	var problems:=PackedStringArray()
	# SEED picnic + table
	world.state.board=true
	world.state.picnic_materials={"soup":2,"bread":1}
	world.state.picnic=true
	world.state.community={"table":k(TABLE)}
	# SEED objects
	var layout:={}
	for who in ["alpha","beta"]:
		layout[k(SITE[who].stove)]={"type":"stove","owner":tokens[who],"items":{}}
		for seat in SITE[who].seats:layout[k(seat)]={"type":"long_bench","owner":tokens[who],"items":{}}
	for key in layout:
		var c:=World.cell(key)
		if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c)!="" or c==TABLE:
			problems.append("cell %s is not clear home land"%key)
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(key):problems.append("cell %s already used in %s"%[key,layer])
	for key in layout:world.state.objects[key]=layout[key]
	# SEED Aru, positions, food
	for who in ["alpha","beta"]:
		world.add_player(tokens[who],who)
		var person:Dictionary=world.state.players[tokens[who]]
		var stories=person.get("stories",{})
		if stories is Dictionary:
			stories["aru"]=maxi(2,int(stories.get("aru",0)))
			person["stories"]=stories
		person.x=STAND[who].x
		person.y=STAND[who].y
		person.inventory=FOOD.duplicate(true)
		if not world.can_stand(STAND[who]):problems.append("%s cannot stand at %s"%[who,STAND[who]])
		for site in ["alpha","beta"]:
			var d:float=STAND[who].distance_to(Vector2(SITE[site].stove)+Vector2(0.5,0.5))
			if d>3.0:problems.append("%s is %.2f from stove %s"%[who,d,k(SITE[site].stove)])
	if not problems.is_empty():
		for problem in problems:push_error("PK_SEED_FAIL "+problem)
		quit(1)
		return
	if not world.save():
		push_error("PK_SEED_FAIL save: "+world.save_error)
		quit(1)
		return
	var reloaded:=World.new()
	var loaded:=reloaded.load_world(args[1])
	var ok:bool=loaded and not reloaded.recovered_from_backup and int(reloaded.state.version)==SaveSchema.VERSION
	ok=ok and reloaded.state.get("public_kitchen")==SaveSchema.public_kitchen_fresh() and PK.stage(reloaded.state)=="register"
	for who in ["alpha","beta"]:
		if plain(PK.candidate_stoves(reloaded.state,tokens[who]))!=[k(SITE[who].stove)]:ok=false
		if plain(PK.candidate_seats(reloaded.state,tokens[who],SITE[who].stove))!=[k(SITE[who].seats[0]),k(SITE[who].seats[1])]:ok=false
	if not ok:
		push_error("PK_SEED_FAIL seeded save did not reload through SaveSchema as fresh kitchen + one candidate site per member")
		quit(1)
		return
	var fixture:={"seed_version":int(reloaded.state.version),"protocol":int(Session.PROTOCOL),"table":k(TABLE),
		"sites":{"alpha":{"stove":k(SITE.alpha.stove),"seats":[k(SITE.alpha.seats[0]),k(SITE.alpha.seats[1])]},
			"beta":{"stove":k(SITE.beta.stove),"seats":[k(SITE.beta.seats[0]),k(SITE.beta.seats[1])]}},
		"food":FOOD,"stand":{"alpha":[STAND.alpha.x,STAND.alpha.y],"beta":[STAND.beta.x,STAND.beta.y]},
		"seeded":["picnic","table","Aru","objects","positions","food"]}
	print("PK_FIXTURE "+JSON.stringify(fixture))
	quit(0)
