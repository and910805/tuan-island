extends SceneTree
## Real ENet or loopback WebSocket validation of blueprint quote/apply (save
## schema 19 / protocol 37), docs/blueprint-integration.md 「第三段傳輸 API 固定介面」.
## Transport is the optional 8th argument: `enet` (default, unchanged) or `ws`
## (plain ws://127.0.0.1:<port> through the existing Session.join; NOT wss/TLS,
## NOT a cloud deployment). The joined peer class is asserted, never assumed.
##
## AUTHORIZED LOCAL FIXTURE: `seed` writes exact test materials, two player
## positions and the picnic flag (travel gate) straight into a temporary save.
## It proves the networked quote/submit/receipt wiring only; it is NOT evidence
## of natural play. Nothing fakes the server clock: rate limits and the 30 s undo
## window are exercised with real timers / the real UTC clock.
##
## Layouts (local coordinates; house = 4x4 box, corners empty):
##   house  2x2 floors (1..2,1..2), 7 walls + 1 door on the cardinal ring, chest
##          on floor (2,1)  -> 13 pieces + 4 automatic roofs over the floors.
##   floors 2x1 floors (U case, no roof).
##   Site C (48,22) contested house, site D (48,26) loser's new quote, site U (46,22).
##
## Driven by work/house-rooms/network_blueprint.py. Args (after `--`):
##   seed <world.json> <alpha_token> <beta_token>
##        Writes the fixture save and prints `BP_FIXTURE {json}`.
##   <phase> <port> <role> <room_key> <alpha_token> <beta_token> <handoff_dir> [enet|ws]
##     contest   alpha + beta together on server-live. Both quote the SAME house at
##               C and print BP_MARK quoted; the runner then creates
##               <handoff_dir>/go-contest and both submit at once. Exactly one
##               wins; the loser gets requote with no partial layout and no charge,
##               re-quotes at D and applies (exact cost). Both retry their own nonce
##               (receipt, no charge). alpha additionally: immediate second retry is
##               rate limited (apply 1500 ms); 3-quote burst -> third rate limited
##               (2 quotes/s); U floors apply -> same-nonce repeat -> undo inside the
##               real 30 s window (exact refund) -> same nonce again (no rebuild);
##               walks to the exit, travels to lanyang, retries its house nonce with
##               the OLD home context (stored receipt) and a fresh nonce with the old
##               context (stale_context), then travels home.
##     reconnect new processes on the same server: both retry persisted nonces.
##     restart   after a normal server stop + restart on the same save: same retries;
##               beta's read-only quote of occupied C is rejected with problems.
## Every snapshot is observed: in home, each site is either completely empty or the
## complete layout (pieces + auto roofs, one owner) - never partial; no raw profile
## token appears in any snapshot, notice, quote or apply result; results carry only
## public fields. Output: BP_CHECK ok ..., BP_COVER <tag>, BP_MARK {json},
## BP_ENET_PASS / BP_ENET_FAIL (enet) or BP_WS_PASS / BP_WS_FAIL (ws).
## Missing API or an unknown transport is a counted failure, never a skip.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")

const SITE_C:=Vector2i(48,22)
const SITE_D:=Vector2i(48,26)
const SITE_U:=Vector2i(46,22)
const RING:=[Vector2i(1,0),Vector2i(2,0),Vector2i(0,1),Vector2i(3,1),Vector2i(0,2),Vector2i(3,2),Vector2i(1,3),Vector2i(2,3)]
const DOOR:=Vector2i(0,2)
const CHEST:=Vector2i(2,1)
const HOUSE_NAME:="測試小屋"
const FLOOR_NAME:="門前地板"
const STAND:={"alpha":Vector2(47.0,24.0),"beta":Vector2(47.0,25.0)}
const WALK_X:=47.0
const WALK_TO_Y:=27.6
const LAYERS:=["ground","objects","roofs"]
const QUOTE_KEYS:=["cost","hash","message","mine_refund","ok","other_people","others_refund","pieces","problems","roof_add","roof_remove","undoable"]
const PROBLEM_KEYS:=["kind","reason","x","y"]
const FORBIDDEN:=["sim","commit","owner","players","receipts","state","design","inventories","inventory","plan","cells","roof_cells","token","tokens","construction","objects","ground","roofs"]
const PHASES:={"contest":["alpha","beta"],"reconnect":["alpha","beta"],"restart":["alpha","beta"]}
const WATCHDOG:={"contest":90.0,"reconnect":45.0,"restart":45.0}
const MIN_PROTOCOL:=37
const JOIN_WAIT:=15.0
const RESULT_WAIT:=8.0
const PEER_WAIT:=60.0
const WALK_WAIT:=8.0
const APPLY_GAP_MSEC:=1700     # contract: 1 apply / 1500 ms per peer
const QUOTE_WINDOW_MSEC:=1150  # contract: 2 quotes / s per peer
const UNDO_WINDOW:=30.0
const MAX_PROBLEMS:=32
const CLEARANCE:=0.8
const TRANSPORTS:={"enet":"ENET","ws":"WS"}
const TRANSPORT_NAMES:={"enet":"ENet","ws":"loopback WebSocket (ws://, no TLS)"}

var session:Session
var phase:=""
var role:=""
var transport:="enet"
var tokens:={}
var handoff:=""
var specs:Dictionary={}
var tracked:Array=[]
var plan:Dictionary={}
var notices:Array=[]
var quotes:={}
var sent_ids:={}
var applies:={}
var quote_sends:Array=[]
var last_apply:=-1000000
var snapshots:=0
var home_snapshots:=0
var seen_both:=false
var site_owner:={}
var site_seen:={}
var violation:=""
var checks:=0
var finished:=false

func _initialize() -> void:
	specs=build_specs()
	tracked=tracked_items()
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

static func floor_raw() -> Dictionary:
	return {"version":1,"name":FLOOR_NAME,"width":2,"height":1,"pieces":[{"kind":"floor","x":0,"y":0},{"kind":"floor","x":1,"y":0}]}

## Interior floors of the closed house become automatic roofs.
static func roof_count(raw:Dictionary) -> int:
	var n:=0
	for p:Dictionary in raw.pieces:
		if str(p.kind)=="floor":n+=1
	return n

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

static func minus(a:Dictionary,b:Dictionary) -> Dictionary:
	return plus(a,b,-1)

## Exact gross cost from the CURRENT recipes (World.BUILD), base + auto roofs.
static func design_cost(raw:Dictionary,roofs:int) -> Dictionary:
	var out:={}
	for p:Dictionary in raw.pieces:out=plus(out,World.BUILD[str(p.kind)])
	for i in roofs:out=plus(out,World.BUILD.roof)
	return out

static func house_cost() -> Dictionary:
	return design_cost(house_raw(),roof_count(house_raw()))

static func floor_cost() -> Dictionary:
	return design_cost(floor_raw(),0)

## Enough for two houses (so the race loser never fails for money) plus U.
static func start_inventory() -> Dictionary:
	return plus(plus(house_cost(),house_cost()),floor_cost())

## Each player ends with exactly one house; U is built and undone (net zero).
static func final_inventory() -> Dictionary:
	return minus(start_inventory(),house_cost())

static func tracked_items() -> Array:
	var items:={}
	for item in plus(house_cost(),floor_cost()):items[item]=true
	var out:=items.keys()
	out.sort()
	return out

static func site_spec(raw:Dictionary,origin:Vector2i,roofed:bool) -> Dictionary:
	var cells:={}
	for y in int(raw.height):
		for x in int(raw.width):cells[k(origin+Vector2i(x,y))]={}
	for p:Dictionary in raw.pieces:
		var want:Dictionary=cells[k(origin+Vector2i(int(p.x),int(p.y)))]
		want[layer_of(str(p.kind))]=str(p.kind)
		if roofed and str(p.kind)=="floor":want["roofs"]="roof"
	return {"raw":raw,"origin":origin,"roofs":roof_count(raw) if roofed else 0,"cells":cells}

static func build_specs() -> Dictionary:
	return {"C":site_spec(house_raw(),SITE_C,true),"D":site_spec(house_raw(),SITE_D,true),"U":site_spec(floor_raw(),SITE_U,false)}

static func online_of(data:Dictionary) -> int:
	var pop=data.get("region_population",{})
	var n:=0
	if pop is Dictionary:
		for region in pop:n+=int(pop[region])
	return n

static func hid(token:String) -> String:
	return token.sha256_text().left(16)

static func now() -> float:
	return Time.get_unix_time_from_system()

static func new_nonce() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

# ---------------------------------------------------------------- observation

func snap() -> Dictionary:
	return session.snapshot if session!=null else {}

func other() -> String:
	return "beta" if role=="alpha" else "alpha"

func who_is(owner:String) -> String:
	for who in tokens:
		if owner==hid(tokens[who]):return who
	return "unknown" if not owner.is_empty() else ""

func me() -> Dictionary:
	var p=snap().get("players",{}).get(session.own_id,{})
	return p if p is Dictionary else {}

func inventory() -> Dictionary:
	var inv=me().get("inventory",{})
	return inv if inv is Dictionary else {}

func inv_text() -> String:
	return JSON.stringify(ints(inventory())) if session!=null else "{}"

func my_pos() -> Vector2:
	return Vector2(float(me().get("x",0.0)),float(me().get("y",0.0)))

func own_epoch() -> int:
	return int(me().get("travel_epoch",-1))

func region() -> String:
	return str(snap().get("region_id",""))

func online() -> int:
	return online_of(snap())

## "empty" | "complete:<who>" | "partial: <detail>" for one site in a home snapshot.
func site_state(data:Dictionary,site:String) -> String:
	var cells:Dictionary=specs[site].cells
	var any:=false
	var exact:=true
	var owners:={}
	var detail:=""
	for key in cells:
		var want:Dictionary=cells[key]
		for layer in LAYERS:
			var source=data.get(layer,{})
			var o=source.get(key) if source is Dictionary else null
			var have:=""
			if o is Dictionary:have=str(o.get("type","?"))
			var wanted:=str(want.get(layer,""))
			if have!="":any=true
			if have!=wanted:
				exact=false
				if detail.is_empty():detail="%s %s has '%s' (complete layout wants '%s')"%[key,layer,have,wanted]
			elif have!="":
				owners[str(o.get("owner",""))]=true
				if layer=="roofs" and o.has("auto") and o.get("auto")!=true:
					exact=false
					if detail.is_empty():detail="%s roof is not automatic"%key
	if not any:return "empty"
	if exact and owners.size()==1:return "complete:"+who_is(str(owners.keys()[0]))
	if exact:detail="mixed owners %s"%str(owners.keys().map(func(o):return who_is(str(o))))
	return "partial: "+detail

func site_states() -> Dictionary:
	var out:={}
	if region()!="home":return out
	for site in specs:out[site]=site_state(snap(),site)
	return out

func sites_text() -> String:
	if session==null:return "no session"
	if region()!="home":return "(in %s)"%region()
	return JSON.stringify(site_states())

func all_empty() -> bool:
	for site in specs:
		if site_state(snap(),site)!="empty":return false
	return true

func undo_info() -> Dictionary:
	var s=snap().get("own_construction_undo",{})
	return s if s is Dictionary else {}

func undo_id() -> String:
	var id=undo_info().get("id","")
	return id if id is String else ""

func undo_available() -> bool:
	var a=undo_info().get("available")
	return typeof(a)==TYPE_BOOL and a

func fresh_record(previous:String) -> bool:
	var id:=undo_id()
	return undo_available() and not id.is_empty() and id!=previous and str(undo_info().get("region",""))=="home"

func within(since:float) -> bool:
	return now()-since<UNDO_WINDOW

func age(since:float) -> String:
	return "%.1fs"%(now()-since)

func brief(result:Variant) -> String:
	if not result is Dictionary:return str(result)
	var out:={}
	for field in ["ok","message","requote","rate_limited","stale_context","timeout","roof_add","pieces","cost","hash","undoable"]:
		if result.has(field):out[field]=result[field]
	if result.has("hash"):out["hash"]=str(result.hash).left(12)
	var problems=result.get("problems")
	if problems is Array:out["problems"]=problems.size()
	var nested=result.get("quote")
	if nested is Dictionary:out["quote"]={"ok":nested.get("ok"),"problems":(nested.get("problems") as Array).size() if nested.get("problems") is Array else -1}
	return JSON.stringify(out)

func problems_inside(list:Variant,site:String) -> bool:
	if not list is Array or (list as Array).is_empty():return false
	for p in list:
		if not p is Dictionary or not specs[site].cells.has(k(Vector2i(int(p.get("x",-99999)),int(p.get("y",-99999))))):return false
	return true

# ---------------------------------------------------------------- public-field guards

func scan_forbidden(value:Variant,path:String) -> String:
	if value is Dictionary:
		for key in value:
			var name:=str(key)
			if name in FORBIDDEN:return "%s.%s is a private field"%[path,name]
			if name=="blueprint" and typeof(value[key])!=TYPE_BOOL:return "%s.blueprint is not a bool marker"%path
			var inner:=scan_forbidden(value[key],path+"."+name)
			if inner!="":return inner
	elif value is Array:
		for i in (value as Array).size():
			var inner:=scan_forbidden(value[i],"%s[%d]"%[path,i])
			if inner!="":return inner
	return ""

func materials_problem(value:Variant,label:String) -> String:
	if not value is Dictionary:return label+" is not a Dictionary"
	for item in value:
		if not World.NAMES.has(str(item)):return "%s has unknown item %s"%[label,str(item)]
		if typeof(value[item])!=TYPE_INT or int(value[item])<=0:return "%s.%s is not a positive int"%[label,str(item)]
	return ""

func quote_problem(q:Dictionary,label:String) -> String:
	for key in QUOTE_KEYS:
		if not q.has(key):return "%s missing %s"%[label,key]
	for field in ["cost","mine_refund","others_refund"]:
		var bad:=materials_problem(q[field],label+"."+field)
		if bad!="":return bad
	if typeof(q.ok)!=TYPE_BOOL or not q.message is String or not q.hash is String:return label+" ok/message/hash types"
	if not q.problems is Array or (q.problems as Array).size()>MAX_PROBLEMS:return label+".problems not an Array of <=32"
	for p in q.problems:
		if not p is Dictionary:return label+" problem is not a Dictionary"
		var keys:Array=(p as Dictionary).keys()
		keys.sort()
		if keys!=PROBLEM_KEYS:return "%s problem fields %s != %s"%[label,str(keys),str(PROBLEM_KEYS)]
		if typeof(p.x)!=TYPE_INT or typeof(p.y)!=TYPE_INT or not p.kind is String or not p.reason is String:return label+" problem field types"
	return ""

func result_problem(result:Dictionary,kind:String) -> String:
	var text:=var_to_str(result)
	for who in tokens:
		if text.contains(tokens[who]):return "contains raw %s token"%who
	var hidden:=scan_forbidden(result,kind)
	if hidden!="":return hidden
	if typeof(result.get("ok"))!=TYPE_BOOL or not result.get("message") is String:return kind+" ok/message types"
	if result.get("rate_limited")==true or result.get("stale_context")==true:
		return "" if result.ok==false else kind+" limited/stale result claims ok"
	if kind=="quote":return quote_problem(result,"quote")
	if result.has("cost"):
		var bad:=materials_problem(result.cost,"result.cost")
		if bad!="":return bad
	if result.has("quote"):
		if not result.quote is Dictionary:return "result.quote is not a Dictionary"
		return quote_problem(result.quote,"result.quote")
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
	for site in specs:
		var state:=site_state(data,site)
		if state.begins_with("partial") and violation.is_empty():violation="snapshot %d site %s: %s"%[snapshots,site,state]
		if state.begins_with("complete:"):
			var who:=state.trim_prefix("complete:")
			if site_owner.has(site) and site_owner[site]!=who and violation.is_empty():
				violation="site %s changed owner %s -> %s"%[site,site_owner[site],who]
			site_owner[site]=who
		var seen:Dictionary=site_seen.get(site,{})
		seen[state]=int(seen.get(state,0))+1
		site_seen[site]=seen

func _on_notice(message:String,ok:bool) -> void:
	notices.append({"ok":ok,"message":message})
	for who in tokens:
		if message.contains(tokens[who]) and violation.is_empty():violation="notice contains raw %s token"%who
	print("BP_NOTICE %s %s ok=%s: %s"%[phase,role,str(ok),message])

func _on_quoted(request_id:int,result:Dictionary) -> void:
	if quotes.has(request_id) and violation.is_empty():violation="quote reply %d delivered twice"%request_id
	if not sent_ids.has(request_id) and violation.is_empty():violation="quote reply for unknown request %d"%request_id
	quotes[request_id]=result.duplicate(true)
	var bad:=result_problem(result,"quote")
	if bad!="" and violation.is_empty():violation="quote %d: %s"%[request_id,bad]
	print("BP_QUOTE %s %s id=%d %s"%[phase,role,request_id,brief(result)])

func _on_applied(nonce:String,result:Dictionary) -> void:
	if not applies.has(nonce):applies[nonce]=[]
	# Contract: the snapshot is sent before the result, so record what this
	# client already sees at the moment the result arrives.
	(applies[nonce] as Array).append({"result":result.duplicate(true),"layout":site_states()})
	var bad:=result_problem(result,"apply")
	if bad!="" and violation.is_empty():violation="apply %s: %s"%[nonce.left(8),bad]
	print("BP_APPLY %s %s nonce=%s %s"%[phase,role,nonce.left(8),brief(result)])

# ---------------------------------------------------------------- plumbing

func check(ok:bool,label:String) -> bool:
	checks+=1
	if ok:print("BP_CHECK ok %s %s: %s"%[phase,role,label])
	else:finish(false,label)
	return ok

func cover(tag:String) -> void:
	print("BP_COVER %s %s %s"%[tag,phase,role])

func mark(data:Dictionary) -> void:
	print("BP_MARK "+JSON.stringify(data))

func until(predicate:Callable,seconds:float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if finished:return false
		if predicate.call():return true
		await create_timer(0.05).timeout
	return not finished and predicate.call()

## Two further snapshots so any post-request broadcast has been applied.
func settle() -> void:
	var seen:=snapshots
	await until(func():return snapshots>=seen+2,RESULT_WAIT)

func act(action:String,p:Vector2i,extra:String) -> Dictionary:
	var index:=notices.size()
	session.perform(action,p,extra)
	var answered:bool=await until(func():return notices.size()>index,RESULT_WAIT)
	if not answered:return {"ok":false,"message":"<no notice within %ds>"%int(RESULT_WAIT),"timeout":true}
	await settle()
	return notices[index]

func pace_quote(allowed:int=2) -> void:
	while not finished:
		var now_ms:=Time.get_ticks_msec()
		var recent:=0
		for t in quote_sends:
			if now_ms-int(t)<QUOTE_WINDOW_MSEC:recent+=1
		if recent<allowed:return
		await create_timer(0.05).timeout

func pace_apply() -> void:
	var wait:=APPLY_GAP_MSEC-(Time.get_ticks_msec()-last_apply)
	if wait>0:await create_timer(float(wait)/1000.0).timeout

func send_quote(raw:Dictionary,origin:Vector2i) -> int:
	quote_sends.append(Time.get_ticks_msec())
	var id=session.call("quote_blueprint",raw,origin,0)
	if typeof(id)!=TYPE_INT or int(id)<1 or int(id)>1000000000:return -1
	if sent_ids.has(id) and violation.is_empty():violation="quote_blueprint reused request id %d"%id
	sent_ids[id]=true
	return id

func quote(raw:Dictionary,origin:Vector2i) -> Dictionary:
	await pace_quote()
	var id:=send_quote(raw,origin)
	if id<1:return {"ok":false,"message":"<quote_blueprint returned no valid request id>","timeout":true}
	var got:bool=await until(func():return quotes.has(id),RESULT_WAIT)
	if not got:return {"ok":false,"message":"<no quote reply within %ds>"%int(RESULT_WAIT),"timeout":true}
	return quotes[id]

func send_apply(nonce:String,raw:Dictionary,origin:Vector2i,hash:String,ctx_region:String,ctx_epoch:int) -> void:
	last_apply=Time.get_ticks_msec()
	session.call("submit_blueprint",nonce,raw,origin,0,hash,ctx_region,ctx_epoch)

func apply_count(nonce:String) -> int:
	return (applies.get(nonce,[]) as Array).size()

## Returns {result, layout(at arrival)}.
func submit(nonce:String,raw:Dictionary,origin:Vector2i,hash:String,ctx_region:String="",ctx_epoch:int=-1,paced:bool=true) -> Dictionary:
	if paced:await pace_apply()
	var index:=apply_count(nonce)
	send_apply(nonce,raw,origin,hash,ctx_region,ctx_epoch)
	var got:bool=await until(func():return apply_count(nonce)>index,RESULT_WAIT)
	if not got:return {"result":{"ok":false,"message":"<no blueprint result within %ds>"%int(RESULT_WAIT),"timeout":true},"layout":{}}
	return applies[nonce][index]

func origin_of(site:String) -> Vector2i:
	return specs[site].origin

func exact_quote(q:Dictionary,site:String) -> bool:
	var raw:Dictionary=specs[site].raw
	var roofs:int=specs[site].roofs
	var want:=design_cost(raw,roofs)
	return check(q.get("ok")==true and ints(q.get("cost"))==want and int(q.get("roof_add",-1))==roofs and int(q.get("roof_remove",-1))==0 \
		and ints(q.get("mine_refund"))=={} and ints(q.get("others_refund"))=={} and int(q.get("other_people",-1))==0 \
		and int(q.get("pieces",-1))==(raw.pieces as Array).size() and q.get("problems")==[] and str(q.get("hash","")).length()==64,
		"quote %s ok with exact cost %s (recipes + %d auto roofs, no refunds): %s"%[site,JSON.stringify(want),roofs,brief(q)])

## Same nonce again: answered from the receipt (ok, same hash), no charge, no layout change.
func retry_same(nonce:String,raw:Dictionary,origin:Vector2i,hash:String,label:String,ctx_region:String="",ctx_epoch:int=-1) -> Dictionary:
	var inv0:=ints(inventory())
	var states0:=site_states()
	var target:=""
	for site in specs:
		if origin_of(site)==origin:target=site
	if not check(not target.is_empty(),label+": retry has a known target site"):return {}
	var e:Dictionary=await submit(nonce,raw,origin,hash,ctx_region,ctx_epoch)
	var r:Dictionary=e.result
	if not check(not r.has("timeout") and r.get("rate_limited")!=true and r.get("stale_context")!=true,"%s: same-nonce retry answered (not limited/stale): %s"%[label,brief(r)]):return {}
	if not check(r.get("ok")==true and str(r.get("hash",hash))==hash,"%s: retry returns the original successful receipt (same hash): %s"%[label,brief(r)]):return {}
	if not check(ints(r.get("cost"))==design_cost(raw,int(specs[target].roofs)) and int(r.get("pieces",-1))==raw.pieces.size(),label+": receipt retains exact cost and piece count, including after JSON reload"):return {}
	await settle()
	# The other player may legitimately finish their separate house while this
	# retry is in flight. Observe global atomicity continuously, but compare this
	# request's target here rather than requiring the entire world to stand still.
	if not check(ints(inventory())==inv0 and site_states().get(target)==states0.get(target),"%s: no second charge, target layout unchanged: %s %s"%[label,inv_text(),sites_text()]):return {}
	cover("same_nonce_no_charge")
	return r

# ---------------------------------------------------------------- entry

func api_missing() -> PackedStringArray:
	var out:=PackedStringArray()
	for method in ["quote_blueprint","submit_blueprint"]:
		if not session.has_method(method):out.append(method+"()")
	for sig in ["blueprint_quoted","blueprint_applied"]:
		if not session.has_signal(sig):out.append("signal "+sig)
	return out

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0 and args[0]=="seed":
		seed_world(args)
		return
	if not (args.size() in [7,8]) or not PHASES.has(args[0]) or not (args[2] in PHASES[args[0]]) \
		or (args.size()==8 and not TRANSPORTS.has(args[7])):
		push_error("BP_FAIL usage: <phase> <port> <role> <room_key> <alpha_token> <beta_token> <handoff_dir> [enet|ws]")
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
	if not check(int(Session.PROTOCOL)>=MIN_PROTOCOL,"Session.PROTOCOL=%d (blueprint transport needs >= %d)"%[int(Session.PROTOCOL),MIN_PROTOCOL]):return
	var missing:=api_missing()
	if not check(missing.is_empty(),"Session exposes the fixed blueprint transport API"+("" if missing.is_empty() else " - missing "+", ".join(missing))):return
	session.connect("blueprint_quoted",_on_quoted)
	session.connect("blueprint_applied",_on_applied)
	var port:=int(args[1])
	var address:="127.0.0.1" if transport=="enet" else "ws://127.0.0.1:%d"%port
	var joined_err:=session.join(address,port,role,args[3])
	if not check(joined_err==OK,"%s join request to %s accepted by Session.join (err %d)"%[TRANSPORT_NAMES[transport],address,joined_err]):return
	if not check(peer_matches(),"client multiplayer peer is %s"%peer_class()):return
	var joined:bool=await until(func():return not session.own_id.is_empty() and snap().get("players",{}).has(session.own_id),JOIN_WAIT)
	if not check(joined and peer_matches(),"registered over %s with protocol %d and the room key (peer %s)"%[TRANSPORT_NAMES[transport],Session.PROTOCOL,peer_class()]):return
	cover("transport_verified")
	if not check(session.own_id==hid(tokens[role]),"own id is the hashed stable profile token"):return
	match phase:
		"contest":await contest()
		_:await persisted()
	if finished:return
	if not check(home_snapshots>0 and violation.is_empty(),"%d snapshots (%d in home): every C/D/U layout was empty or complete (states %s); no raw tokens in snapshots/%d notices/%d quotes/%d applies; only public result fields"%[snapshots,home_snapshots,JSON.stringify(site_seen),notices.size(),quotes.size(),applies.size()] + ("" if violation.is_empty() else " -- "+violation)):return
	cover("observer_zero_or_complete")
	cover("tokens_absent")
	finish(true,"")

## Real class of the live peer; the transport is asserted, not inferred from args.
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
	if ok:print("BP_%s_PASS %s %s transport=%s checks=%d snapshots=%d home=%d quotes=%d applies=%d notices=%d"%[tag,phase,role,transport,checks,snapshots,home_snapshots,quotes.size(),applies.size(),notices.size()])
	else:push_error("BP_%s_FAIL %s %s transport=%s after %d checks: %s | sites=%s | inv=%s | violation=%s"%[tag,phase,role,transport,checks,step,sites_text(),inv_text(),violation])
	if session!=null:session.shutdown()
	for _frame in 8:await process_frame
	quit(0 if ok else 1)

# ---------------------------------------------------------------- contest phase

func contest() -> void:
	var both:bool=await until(func():return seen_both,PEER_WAIT)
	if not check(both,"alpha and beta are online together"):return
	if not check(region()=="home" and all_empty(),"fixture sites start empty: %s"%sites_text()):return
	if not check(ints(inventory())==ints(start_inventory()),"%s starts with exact fixture materials %s"%[role,inv_text()]):return
	var raw:=house_raw()
	var inv0:=ints(inventory())
	var cost:=house_cost()
	var q:Dictionary=await quote(raw,SITE_C)
	if not exact_quote(q,"C"):return
	await settle()
	if not check(all_empty() and ints(inventory())==inv0,"quote is read-only (sites empty, inventory unchanged)"):return
	cover("contest_both_quoted")
	mark({"mark":"quoted","role":role})
	var go_path:=handoff.path_join("go-contest")
	var go:bool=await until(func():return FileAccess.file_exists(go_path),PEER_WAIT)
	if not check(go,"runner released both clients only after both held an ok quote for C"):return
	var nonce:=new_nonce()
	var e:Dictionary=await submit(nonce,raw,SITE_C,str(q.hash),"",-1,false)
	var r:Dictionary=e.result
	if not check(not r.has("timeout") and r.get("rate_limited")!=true and r.get("stale_context")!=true,"contest submit answered on its merits: %s"%brief(r)):return
	var won:bool=r.get("ok")==true
	var house:={}
	if won:
		if not check(str(e.layout.get("C",""))=="complete:"+role,"winner already saw complete C in a snapshot when the result arrived: %s"%JSON.stringify(e.layout)):return
		cover("snapshot_before_result")
		if not check(str(r.get("hash",q.hash))==str(q.hash) and (not r.has("cost") or ints(r.cost)==cost),"winner result echoes the quoted hash/cost"):return
		if not check(ints(inventory())==minus(inv0,cost),"winner charged exactly %s once: %s"%[JSON.stringify(cost),inv_text()]):return
		cover("exact_cost")
		house={"site":"C","nonce":nonce,"hash":str(q.hash)}
	else:
		if not check(r.get("ok")==false and r.get("requote")==true,"loser rejected with requote (hash changed under it): %s"%brief(r)):return
		var nq=r.get("quote")
		if not check(nq is Dictionary and nq.get("ok")==false and problems_inside(nq.get("problems"),"C"),"requote shows blocked C cells (absolute coords inside C): %s"%brief(nq)):return
		var taken:bool=await until(func():return site_state(snap(),"C")=="complete:"+other(),PEER_WAIT)
		if not check(taken,"loser sees C complete and owned only by %s: %s"%[other(),sites_text()]):return
		await settle()
		if not check(ints(inventory())==inv0 and site_state(snap(),"D")=="empty","rejected apply: no partial layout, nothing charged: %s"%inv_text()):return
		cover("loser_no_partial")
		var q2:Dictionary=await quote(raw,SITE_D)
		if not exact_quote(q2,"D"):return
		var n2:=new_nonce()
		var e2:Dictionary=await submit(n2,raw,SITE_D,str(q2.hash))
		var r2:Dictionary=e2.result
		if not check(r2.get("ok")==true,"loser applies its new quote at D: %s"%brief(r2)):return
		if not check(str(e2.layout.get("D",""))=="complete:"+role,"snapshot showed complete D before the result: %s"%JSON.stringify(e2.layout)):return
		cover("snapshot_before_result")
		if not check(ints(inventory())==minus(inv0,cost),"D charged exactly %s once: %s"%[JSON.stringify(cost),inv_text()]):return
		cover("exact_cost")
		cover("newquote_success")
		house={"site":"D","nonce":n2,"hash":str(q2.hash)}
	mark({"mark":"contest","role":role,"won":won,"lost_nonce":"" if won else nonce})
	mark({"mark":"house","role":role,"site":house.site,"nonce":house.nonce,"hash":house.hash})
	var again:Dictionary=await retry_same(house.nonce,raw,origin_of(house.site),house.hash,"live retry of %s"%house.site)
	if again.is_empty():return
	if role=="alpha":
		await alpha_extras(house)
		if finished:return
		var rest:bool=await until(func():return site_state(snap(),"C").begins_with("complete:") and site_state(snap(),"D").begins_with("complete:"),PEER_WAIT)
		check(rest and site_state(snap(),house.site)=="complete:alpha" and site_state(snap(),"U")=="empty" and ints(inventory())==ints(final_inventory()),
			"alpha leaves with C/D complete (one each), U empty, exact final materials: %s %s"%[sites_text(),inv_text()])
	else:
		var left:bool=await until(func():return online()==1,PEER_WAIT)
		if not check(left,"alpha finished its cases and disconnected"):return
		var other_site:String="D" if house.site=="C" else "C"
		check(site_state(snap(),house.site)=="complete:beta" and site_state(snap(),other_site)=="complete:alpha" and site_state(snap(),"U")=="empty" \
			and ints(inventory())==ints(final_inventory()),"beta sees final C/D owners, U empty; exact final materials: %s %s"%[sites_text(),inv_text()])

func alpha_extras(house:Dictionary) -> void:
	var raw:=house_raw()
	var origin:=origin_of(house.site)
	# --- apply rate limit: an immediate second retry of the same nonce.
	var inv0:=ints(inventory())
	var states0:=site_states()
	var count:=apply_count(house.nonce)
	send_apply(house.nonce,raw,origin,house.hash,"",-1)
	var got:bool=await until(func():return apply_count(house.nonce)>count,RESULT_WAIT)
	if not check(got,"immediate second retry answered"):return
	var limited:Dictionary=applies[house.nonce][count].result
	if not check(limited.get("ok")==false and limited.get("rate_limited")==true,"second submit inside 1500 ms is rate limited: %s"%brief(limited)):return
	await settle()
	if not check(ints(inventory())==inv0 and site_states()==states0,"rate-limited submit changed nothing"):return
	cover("apply_rate_limited")
	# --- quote rate limit: three quotes in one frame after a quiet second.
	await pace_quote(1)
	var ids:Array=[]
	for i in 3:ids.append(send_quote(raw,origin))
	if not check(ids.all(func(id):return int(id)>0) and {ids[0]:1,ids[1]:1,ids[2]:1}.size()==3,"three distinct request ids %s"%str(ids)):return
	var all_back:bool=await until(func():return ids.all(func(id):return quotes.has(id)),RESULT_WAIT)
	if not check(all_back,"every burst quote got a reply (no silent drop)"):return
	var a:Dictionary=quotes[ids[0]]
	var b:Dictionary=quotes[ids[1]]
	var c:Dictionary=quotes[ids[2]]
	if not check(a.get("rate_limited")!=true and b.get("rate_limited")!=true and c.get("rate_limited")==true and c.get("ok")==false,
		"2 quotes/s: first two answered, third rate limited: %s | %s | %s"%[brief(a),brief(b),brief(c)]):return
	if not check(a.get("ok")==false and problems_inside(a.get("problems"),house.site),"re-quoting the occupied own site is rejected read-only with problems inside it"):return
	cover("quote_rate_limited")
	cover("readonly_quote_rejected")
	# --- U: apply, same-nonce repeat, undo inside the real 30 s window, nonce again.
	var fr:=floor_raw()
	var fcost:=floor_cost()
	var qu:Dictionary=await quote(fr,SITE_U)
	if not exact_quote(qu,"U"):return
	if not check(qu.get("undoable")==true,"U quote is undoable"):return
	var prev_id:=undo_id()
	var inv_u:=ints(inventory())
	var nu:=new_nonce()
	var eu:Dictionary=await submit(nu,fr,SITE_U,str(qu.hash))
	var u_unix:=now()
	if not check(eu.result.get("ok")==true and str(eu.layout.get("U",""))=="complete:alpha","U applied, snapshot complete before result: %s %s"%[brief(eu.result),JSON.stringify(eu.layout)]):return
	if not check(ints(inventory())==minus(inv_u,fcost),"U charged exactly %s: %s"%[JSON.stringify(fcost),inv_text()]):return
	var recorded:bool=await until(func():return fresh_record(prev_id),RESULT_WAIT)
	if not check(recorded,"own summary offers undo of U: %s"%JSON.stringify(undo_info())):return
	var u_id:=undo_id()
	var rep:Dictionary=await retry_same(nu,fr,SITE_U,str(qu.hash),"U repeat before undo")
	if rep.is_empty():return
	if not check(undo_id()==u_id and undo_available() and within(u_unix),"repeat made no new record; still inside window (age %s)"%age(u_unix)):return
	var ur:Dictionary=await act("undo_build",SITE_U,u_id)
	if not check(ur.get("ok")==true,"alpha undoes the U blueprint: \"%s\""%str(ur.get("message"))):return
	var gone:bool=await until(func():return site_state(snap(),"U")=="empty",RESULT_WAIT)
	if not check(gone and ints(inventory())==inv_u and within(u_unix),"U removed with exact refund inside the real 30 s window (age %s): %s"%[age(u_unix),inv_text()]):return
	cover("undo_after_repeat")
	var post:Dictionary=await retry_same(nu,fr,SITE_U,str(qu.hash),"U nonce after undo (no rebuild)")
	if post.is_empty():return
	mark({"mark":"undo","nonce":nu,"hash":str(qu.hash)})
	# --- walk to the home exit, travel, retry with the old context.
	var walked:bool=await walk_down()
	var exit:Vector2i=REGIONS.exit_cell(REGIONS.HOME)
	var dist:=my_pos().distance_to(Vector2(exit)+Vector2(0.5,0.5))
	if not check(walked and dist<=3.1,"alpha walked to the home exit (%.2f away, pos %s)"%[dist,str(my_pos())]):return
	var old_epoch:=own_epoch()
	var inv_t:=ints(inventory())
	var tr:Dictionary=await act("travel",exit,REGIONS.LANYANG)
	if not check(tr.get("ok")==true,"travel home -> lanyang: \"%s\""%str(tr.get("message"))):return
	var moved:bool=await until(func():return region()==REGIONS.LANYANG and own_epoch()==old_epoch+1,RESULT_WAIT)
	if not check(moved,"snapshot now lanyang with travel_epoch %d -> %d"%[old_epoch,own_epoch()]):return
	var tr_retry:Dictionary=await retry_same(house.nonce,raw,origin,house.hash,"after travel with old home context",REGIONS.HOME,old_epoch)
	if tr_retry.is_empty():return
	cover("travel_receipt")
	var stale:=new_nonce()
	var es:Dictionary=await submit(stale,raw,origin,house.hash,REGIONS.HOME,old_epoch)
	if not check(es.result.get("ok")==false and es.result.get("stale_context")==true and es.result.get("rate_limited")!=true,"fresh nonce with the old context is stale_context: %s"%brief(es.result)):return
	await settle()
	if not check(ints(inventory())==inv_t,"stale submit charged nothing"):return
	cover("stale_context")
	mark({"mark":"stale","nonce":stale})
	var back:Dictionary=await act("travel",REGIONS.exit_cell(REGIONS.LANYANG),REGIONS.HOME)
	if not check(back.get("ok")==true,"travel lanyang -> home: \"%s\""%str(back.get("message"))):return
	var home:bool=await until(func():return region()=="home",RESULT_WAIT)
	check(home and ints(inventory())==inv_t and site_state(snap(),house.site)=="complete:alpha" and site_state(snap(),"U")=="empty",
		"back home: own house intact, U still empty, materials unchanged: %s %s"%[sites_text(),inv_text()])

## Real movement input (Session.input_direction), straight down the clear x=47 column.
func walk_down() -> bool:
	var deadline:=Time.get_ticks_msec()+int(WALK_WAIT*1000)
	while Time.get_ticks_msec()<deadline and not finished and my_pos().y<WALK_TO_Y:
		session.input_direction(Vector2.DOWN)
		await create_timer(0.05).timeout
	for i in 4:
		session.input_direction(Vector2.ZERO)
		await create_timer(0.05).timeout
	var last:=my_pos()
	var stable:=0
	while stable<3 and Time.get_ticks_msec()<deadline+3000 and not finished:
		var seen:=snapshots
		await until(func():return snapshots>seen,1.0)
		var at:=my_pos()
		stable=stable+1 if at.distance_to(last)<0.001 else 0
		last=at
	return my_pos().y>=WALK_TO_Y and stable>=3

# ---------------------------------------------------------------- reconnect / restart

func read_plan() -> bool:
	var data=JSON.parse_string(FileAccess.get_file_as_string(handoff.path_join("plan.json")))
	if not data is Dictionary:return false
	for who in ["alpha","beta"]:
		var item=data.get(who)
		if not item is Dictionary or not str(item.get("site","")) in ["C","D"] or str(item.get("nonce","")).length()!=32 or str(item.get("hash","")).length()!=64:return false
	var u=data.get("undo")
	if not u is Dictionary or str(u.get("nonce","")).length()!=32 or str(u.get("hash","")).length()!=64:return false
	if data.alpha.site==data.beta.site:return false
	plan=data
	return true

func persisted() -> void:
	if not check(read_plan(),"handoff plan (persisted nonces/hashes from the contest phase) is valid"):return
	await settle()
	var want:={str(plan.alpha.site):"complete:alpha",str(plan.beta.site):"complete:beta","U":"empty"}
	if not check(region()=="home" and site_states()==want,"%s: persisted layouts %s (want %s)"%[phase,sites_text(),JSON.stringify(want)]):return
	if not check(ints(inventory())==ints(final_inventory()),"%s: exact persisted materials %s"%[phase,inv_text()]):return
	var mine:Dictionary=plan[role]
	var r:Dictionary=await retry_same(str(mine.nonce),house_raw(),origin_of(str(mine.site)),str(mine.hash),"%s retry of %s"%[phase,mine.site])
	if r.is_empty():return
	if role=="alpha":
		var u:Dictionary=plan.undo
		var r2:Dictionary=await retry_same(str(u.nonce),floor_raw(),SITE_U,str(u.hash),"%s retry of undone U nonce"%phase)
		if r2.is_empty():return
	if role=="beta" and phase=="restart":
		var inv0:=ints(inventory())
		var states0:=site_states()
		var q:Dictionary=await quote(house_raw(),SITE_C)
		if not check(not q.has("timeout") and q.get("rate_limited")!=true and q.get("ok")==false and problems_inside(q.get("problems"),"C"),"quote of occupied C after restart rejected with problems inside C: %s"%brief(q)):return
		await settle()
		if not check(ints(inventory())==inv0 and site_states()==states0,"rejected quote changed nothing"):return
		cover("readonly_quote_rejected")
	cover("reconnect_retry" if phase=="reconnect" else "restart_retry")

# ---------------------------------------------------------------- fixture seed

func seed_world(args:Array) -> void:
	if args.size()!=4:
		push_error("BP_SEED_FAIL usage: seed <world.json> <alpha_token> <beta_token>")
		quit(2)
		return
	tokens={"alpha":args[2],"beta":args[3]}
	var world:=World.new()
	world.save_path=args[1]
	world.state.picnic=true   # explicit fixture: unlocks the walking travel gate
	var problems:=PackedStringArray()
	var cells:={}
	for site in specs:
		for key in specs[site].cells:cells[key]=true
	for y in range(23,30):
		for x in [46,47]:cells[k(Vector2i(x,y))]=true   # stands + alpha's walk column
	for key in cells:
		var c:=World.cell(key)
		if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c)!="":
			problems.append("cell %s is not clear buildable home land"%key)
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(key):problems.append("cell %s already used in %s"%[key,layer])
	var reach:=float(World.BLUEPRINT_RANGE)
	var solids:Array=[]
	for site in specs:
		for key in specs[site].cells:
			if str(specs[site].cells[key].get("objects",""))!="":solids.append(Vector2(World.cell(key))+Vector2(0.5,0.5))
	var start:=start_inventory()
	for who in ["alpha","beta"]:
		world.add_player(tokens[who],who)
		var person:Dictionary=world.state.players[tokens[who]]
		var spot:Vector2=STAND[who]
		person.x=spot.x
		person.y=spot.y
		person.inventory=start.duplicate(true)
		if not world.can_stand(spot):problems.append("%s cannot stand at %s"%[who,spot])
		var targets:Array=["C","D"]+(["U"] if who=="alpha" else [])
		for site in targets:
			var d:=spot.distance_to(Vector2(origin_of(site))+Vector2(0.5,0.5))
			if d>reach-0.05:problems.append("%s is %.2f from %s origin (blueprint range %.1f)"%[who,d,site,reach])
		for solid:Vector2 in solids:
			if spot.distance_to(solid)<CLEARANCE+0.1:problems.append("%s stands within clearance of %s"%[who,solid])
	var walk_y:=24.0
	while walk_y<=29.0:
		var at:=Vector2(WALK_X,walk_y)
		if not world.can_stand(at):problems.append("walk column blocked at %s"%at)
		for solid:Vector2 in solids:
			if at.distance_to(solid)<CLEARANCE+0.1:problems.append("walk column %s within clearance of %s"%[at,solid])
		walk_y+=0.25
	var exit:=Vector2(REGIONS.exit_cell(REGIONS.HOME))+Vector2(0.5,0.5)
	for end_y in [WALK_TO_Y,29.0]:
		if Vector2(WALK_X,end_y).distance_to(exit)>3.1:problems.append("walk end y=%.1f is too far from the exit"%end_y)
	if not problems.is_empty():
		for problem in problems:push_error("BP_SEED_FAIL "+problem)
		quit(1)
		return
	var sites:={}
	for site in specs:
		var o:Vector2i=specs[site].origin
		sites[site]={"origin":[o.x,o.y],"cells":specs[site].cells,"roofs":specs[site].roofs,"pieces":(specs[site].raw.pieces as Array).size()}
	var fixture:={"sites":sites,"house_cost":house_cost(),"floor_cost":floor_cost(),"start":start,"final":final_inventory(),
		"tracked":tracked,"seed_version":int(world.state.version),"protocol":int(Session.PROTOCOL),"picnic":true,
		"stand":{"alpha":[STAND.alpha.x,STAND.alpha.y],"beta":[STAND.beta.x,STAND.beta.y]},"names":[HOUSE_NAME,FLOOR_NAME]}
	print("BP_FIXTURE "+JSON.stringify(fixture))
	quit(0 if world.save() else 1)
