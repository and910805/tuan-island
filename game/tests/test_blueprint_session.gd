extends SceneTree
## Blueprint stage three transport through a real Session host (peer id 1)
## and a real, isolated World (docs/blueprint-integration.md,
## 「第三段傳輸 API 固定介面」). Not the World or data-module tests.
##
## API under test (implemented concurrently by the Session worker / Root):
##   signals blueprint_quoted(request_id, result) / blueprint_applied(nonce, result)
##   quote_blueprint(raw, origin, turns=0) -> int ; submit_blueprint(nonce, raw,
##   origin, turns, expected_hash, region="", epoch=-1)
##   _handle_blueprint_quote(id, request_id, design_json, origin, turns, region, epoch)
##   _handle_blueprint_apply(id, nonce, design_json, origin, turns, expected_hash, region, epoch)
##   request_blueprint_quote / request_blueprint_apply (any_peer, reliable, ch 2)
##   receive_blueprint_quote / receive_blueprint_result (authority, reliable, ch 3)
##   blueprint_clock:Callable, _blueprint_now()->int ; World.blueprint_receipt(token, nonce)
##
## Fixture: HostSession overrides _ready so user://profile.json is never read or
## written, transport signals are not connected and the world is never ticked
## (state comparisons stay exact). The World saves into one per-run user://
## directory that is removed at the end; no real save is touched. Inventories,
## positions, the travel move and foreign floors are written directly and are
## NOT normal play. Blueprint rate limits use a fake blueprint_clock; undo uses
## fake clocks. Peer 2 is an explicit server-side fixture without transport;
## real remote registration/welcome is covered by ENet tests, not this fixture.
## Its replies cannot be captured (only "no state change / nothing at host").
## Missing API and every guard that skips work are counted failures.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")
const Membership=preload("res://scripts/world_membership.gd")

const A:="tok-alice-SECRET-session"
const B:="tok-bob-SECRET-session"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const PARK:=World.SPAWN
const JSON_LIMIT:=131072
const QUOTE_KEYS:=["ok","message","cost","mine_refund","others_refund","other_people","roof_add","roof_remove","pieces","problems","hash","undoable"]
const APPLY_KEYS:=["ok","message","blueprint","pieces","roof_add","roof_remove","cost","hash"]
const TRANSPORT_KEYS:=["requote","quote","stale_context","rate_limited"]
const FORBIDDEN:=["sim","commit","owner","players","receipts","design","state","token","inventory","inventories","plan","cells","roof_cells","width","height","version","settings"]
const LEGACY_PEER_DICTS:=["peers","directions","sequences","rates","pending","last_movement","identities","identity_requests","identity_rejected"]

class HostSession extends "res://scripts/session.gd":
	var fixture_name:="Session"
	func _ready() -> void:
		name=fixture_name
		session_nonce="0123456789abcdef0123456789abcdef"
		set_physics_process(false)

class Ticks extends RefCounted:
	var ms:int=7000000
	func now() -> int:return ms

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=9000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

var checks:=0
var failures:=0
var serial:=0
var rid:=100
var dir:=""
var s=null
var w=null
var bclock:Ticks
var uclock:FakeClock
var events:Array=[]
var site1:=Vector2i(-1,-1)
var site2:=Vector2i(-1,-1)
var site3:=Vector2i(-1,-1)
var site4:=Vector2i(-1,-1)
var site5:=Vector2i(-1,-1)

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	dir="user://test-blueprint-session-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var made:=DirAccess.make_dir_recursive_absolute(dir)==OK
	expect(made,"isolated test directory created")
	if not made:
		finish()
		return
	setup()
	test_contract()
	await test_wrappers()
	await test_json()
	await test_turns()
	await test_bounds()
	await test_gates()
	await test_stale()
	await test_rates()
	await test_forged()
	await test_problems()
	await test_apply_and_receipts()
	await test_save_failure()
	test_normal_action()
	await test_request_id_top()
	test_peer_cleanup()
	await test_no_world()
	cleanup()
	finish()

func finish() -> void:
	print("BLUEPRINT_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func cleanup() -> void:
	if s!=null:
		s.free()
		s=null
	expect(not DirAccess.dir_exists_absolute(dir+"/missing-subdir"),"failed save never created the missing directory")
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	expect(DirAccess.remove_absolute(dir)==OK,"isolated test directory removed")

# ---------------------------------------------------------------- fixtures --

func settle() -> void:
	await process_frame
	await process_frame

func next_rid() -> int:
	rid+=1
	return rid

func nonce() -> String:
	serial+=1
	return String.num_int64(serial+0x7100,16).lpad(32,"0")

func pair_raw() -> Dictionary:
	return {"version":1,"name":"小徑","width":2,"height":1,"pieces":[{"kind":"floor","x":0,"y":0},{"kind":"floor","x":1,"y":0}]}

func single_raw() -> Dictionary:
	return {"version":1,"name":"單格","width":1,"height":1,"pieces":[{"kind":"floor","x":0,"y":0}]}

func clear_cell(c:Vector2i,allow_natural_resources:=false) -> bool:
	if not w.is_land(c) or w.water(c) or w.protected(c):return false
	var resource:String=w.resource(c)
	if resource.is_empty() and w.blocked(c):return false
	if not resource.is_empty() and not allow_natural_resources:return false
	var k:=World.key(c)
	for f in ["objects","ground","roofs","crops","forest"]:
		if w.state[f].has(k):return false
	return true

func site_ok(o:Vector2i,size:Vector2i,allow_natural_resources:bool) -> bool:
	for y in range(o.y,o.y+size.y):
		if not clear_cell(Vector2i(o.x-1,y)):return false
		for x in range(o.x,o.x+size.x):
			if not clear_cell(Vector2i(x,y),allow_natural_resources):return false
	return true

func zone(o:Vector2i,size:Vector2i) -> Rect2i:
	return Rect2i(o-Vector2i(3,3),size+Vector2i(6,6))

## Find a usable home rectangle and a clear standing column, away from spawn
## and other tests. Only the synthetic conflict test allows resources inside.
func find_site(size:Vector2i,avoid:Array,allow_natural_resources:=false) -> Vector2i:
	for oy in range(2,REGIONS.SIZE.y-size.y-2):
		for ox in range(3,REGIONS.SIZE.x-size.x-2):
			var o:=Vector2i(ox,oy)
			var z:=zone(o,size)
			if z.has_point(Vector2i(PARK)):continue
			var hit:=false
			for r in avoid:
				var rect:Rect2i=r
				if z.intersects(rect):
					hit=true
					break
			if not hit and site_ok(o,size,allow_natural_resources):return o
	expect(false,"found a usable %s home site"%size)
	return Vector2i(-1,-1)

func stand(o:Vector2i) -> Vector2:
	return Vector2(o.x-0.5,o.y+0.5)

func pose(at:Vector2) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==A else PARK
		person.x=spot.x
		person.y=spot.y

func ctx() -> Array:
	return [str(w.player_region(A)),int(w.state.players[A].get("travel_epoch",0))]

func ints(d) -> Dictionary:
	if not d is Dictionary:return {"<invalid>":-1}
	var out:={}
	for k in d:
		var v=d[k]
		if not (v is int or v is float):return {"<invalid>":-1}
		if int(v)!=0:out[str(k)]=int(v)
	return out

func minus(a:Dictionary,b:Dictionary) -> Dictionary:
	var out:=ints(a)
	for k in b:
		var left:int=int(out.get(k,0))
		var right:int=int(b[k])
		out[k]=left-right
		if int(out[k])==0:out.erase(k)
	return out

func inv() -> Dictionary:
	return ints(w.state.players[A].inventory)

func has_receipt(token:String,n:String) -> bool:
	return w.state.players[token].receipts.has("blueprint:"+n)

func floors_at(o:Vector2i,count:int,owner:String) -> bool:
	for x in count:
		var g=w.state.ground.get(World.key(o+Vector2i(x,0)))
		if not (g is Dictionary and g.get("type")=="floor" and g.get("owner")==owner):return false
	return true

## World state, save bytes and the normal-action bookkeeping.
func fp() -> Array:
	var bytes:=PackedByteArray()
	if FileAccess.file_exists(w.save_path):bytes=FileAccess.get_file_as_bytes(w.save_path)
	return [var_to_str(w.state),bytes,var_to_str([s.sequences,s.rates,s.counter,w.active_tokens,w._region])]

func same(before:Array,label:String) -> void:
	var now:=fp()
	expect(now[0]==before[0],label+": world state unchanged")
	expect(now[1]==before[1],label+": save file unchanged")
	expect(now[2]==before[2],label+": action sequences/rates/counter/active tokens/orientation unchanged")

func capture(sess,sink:Array) -> void:
	if sess.has_signal("blueprint_quoted"):
		sess.connect("blueprint_quoted",func(request_id,result):sink.append(["quote",request_id,result]))
	else:expect(false,"Session declares signal blueprint_quoted")
	if sess.has_signal("blueprint_applied"):
		sess.connect("blueprint_applied",func(n,result):sink.append(["apply",n,result]))
	else:expect(false,"Session declares signal blueprint_applied")
	sess.connect("changed",func(data,_pid):sink.append(["state",null,data]))

func replies(kind:String,sink:Variant=null) -> Array:
	var source:Array=events if sink==null else sink
	var out:=[]
	for e in source:
		if e[0]==kind:out.append(e)
	return out

func blueprint_replies(sink:Variant=null) -> Array:
	return replies("quote",sink)+replies("apply",sink)

func hq(id:int,request_id:int,json:String,origin:Vector2i,turns:Variant,region:String,epoch:int,advance:bool=true) -> Array:
	if not s.has_method("_handle_blueprint_quote"):
		expect(false,"Session._handle_blueprint_quote exists")
		return []
	if advance:bclock.ms+=2000
	events.clear()
	s.call("_handle_blueprint_quote",id,request_id,json,origin,turns,region,epoch)
	await settle()
	return replies("quote")

func ha(id:int,n:String,json:String,origin:Vector2i,turns:Variant,h:String,region:String,epoch:int,advance:bool=true) -> Array:
	if not s.has_method("_handle_blueprint_apply"):
		expect(false,"Session._handle_blueprint_apply exists")
		return []
	if advance:bclock.ms+=2000
	events.clear()
	s.call("_handle_blueprint_apply",id,n,json,origin,turns,h,region,epoch)
	await settle()
	return replies("apply")

func one(got:Array,label:String) -> Dictionary:
	expect(got.size()==1,label+": exactly one reply (got %d)"%got.size())
	if got.is_empty():return {}
	var r=got[0][2]
	if not r is Dictionary:
		expect(false,label+": reply is a Dictionary")
		return {}
	check_result(r,label)
	return r

## Replies are optional, but any reply must be a non-success.
func only_failures(got:Array,label:String) -> void:
	expect(got.size()<=1,label+": at most one reply")
	for e in got:
		var r=e[2]
		expect(r is Dictionary and r.get("ok")==false,label+": any reply is ok:false")
		if r is Dictionary:check_result(r,label)

func check_result(r:Dictionary,label:String,allowed:Array=[],nested:bool=false) -> void:
	var keys:Array=allowed if not allowed.is_empty() else QUOTE_KEYS+APPLY_KEYS+TRANSPORT_KEYS
	expect(r.get("ok") is bool,label+": ok is a bool")
	expect(r.get("message") is String and (nested or str(r.get("message")).length()>0),label+": has a message")
	for k in r:expect(str(k) in keys,label+": field '%s' is whitelisted"%str(k))
	forbidden_scan(r,label)
	var text:=var_to_str(r)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks tokens")
	for f in ["cost","mine_refund","others_refund"]:
		if r.has(f):materials(r[f],label+" "+f)
	if r.has("problems"):
		var list=r.problems
		expect(list is Array and list.size()<=32,label+": problems is an Array of at most 32")
		if list is Array:
			for p in list:
				var good:bool=p is Dictionary and p.size()==4 and p.get("x") is int and p.get("y") is int and p.get("kind") is String and p.get("reason") is String
				expect(good,label+": problem has exactly int x/y, kind, reason: "+str(p))
	if r.has("pieces"):expect(r.pieces is int,label+": pieces is a count, never the design")
	if r.has("quote"):
		expect(r.quote is Dictionary,label+": nested quote is a Dictionary")
		if r.quote is Dictionary:check_result(r.quote,label+" quote",QUOTE_KEYS,true)

func materials(v,label:String) -> void:
	if not v is Dictionary:
		expect(false,label+" is a Dictionary")
		return
	for k in v:
		expect(World.NAMES.has(k) and v[k] is int and int(v[k])>0,label+": %s is a known material with a positive int"%str(k))

func forbidden_scan(v,label:String) -> void:
	if v is Dictionary:
		for k in v:
			if str(k) in FORBIDDEN:expect(false,label+": private field '%s' never forwarded"%str(k))
			forbidden_scan(v[k],label)
	elif v is Array:
		for e in v:forbidden_scan(e,label)

func empty_callable(v) -> bool:
	if not v is Callable:return false
	var c:Callable=v
	return c.is_null()

func method_args(script:Script,method:String) -> int:
	for m in script.get_script_method_list():
		if m.name==method:return (m.args as Array).size()
	return -1

func dicts_with(id:int) -> Array:
	var out:=[]
	for prop in s.get_property_list():
		if (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE)==0:continue
		var v=s.get(prop.name)
		if v is Dictionary:
			var d:Dictionary=v
			if d.has(id):out.append(str(prop.name))
	return out

func setup() -> void:
	w=World.new()
	w.save_path=dir+"/world.json"
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	# Explicit fixture stock, not normal-play balances.
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":100,"fiber":300}
	uclock=FakeClock.new()
	w.undo_clock_utc=Callable(uclock,"now_utc")
	w.undo_clock_ticks=Callable(uclock,"now_ticks")
	site1=find_site(Vector2i(2,1),[])
	site2=find_site(Vector2i(2,1),[zone(site1,Vector2i(2,1))])
	site3=find_site(Vector2i(1,1),[zone(site1,Vector2i(2,1)),zone(site2,Vector2i(2,1))])
	site4=find_site(Vector2i(10,4),[zone(site1,Vector2i(2,1)),zone(site2,Vector2i(2,1)),zone(site3,Vector2i.ONE)],true)
	site5=find_site(Vector2i(1,1),[zone(site1,Vector2i(2,1)),zone(site2,Vector2i(2,1)),zone(site3,Vector2i.ONE),zone(site4,Vector2i(10,4))])
	expect(w.save(),"baseline isolated save written")
	bclock=Ticks.new()
	s=HostSession.new()
	root.add_child(s)
	capture(s,events)
	expect(empty_callable(s.get("blueprint_clock")),"blueprint_clock defaults to an empty Callable")
	if s.has_method("_blueprint_now"):
		var real:int=int(s.call("_blueprint_now"))
		expect(absi(real-Time.get_ticks_msec())<5000,"default _blueprint_now uses monotonic ticks")
	else:expect(false,"Session._blueprint_now exists")
	s.set("blueprint_clock",Callable(bclock,"now"))
	if s.has_method("_blueprint_now"):
		expect(int(s.call("_blueprint_now"))==bclock.ms,"_blueprint_now uses the injected blueprint_clock")
		bclock.ms+=123
		expect(int(s.call("_blueprint_now"))==bclock.ms,"_blueprint_now follows the fake clock")
	s.world=w
	s._attach_registered(1,A)
	attach_remote_fixture()
	expect(s.peers.get(1)==A and s.peers.get(2)==B,"host id1=A and remote id2=B attached")
	expect(s.own_id==A.sha256_text().left(16) and s.snapshot.get("region_id")==HOME,"host snapshot delivered at attach")

# ------------------------------------------------------------------- tests --

func test_contract() -> void:
	expect(int(Session.PROTOCOL)>=39,"the protocol supports blueprint RPCs")
	for sig in s.get_signal_list():
		if sig.name in ["blueprint_quoted","blueprint_applied"]:
			expect((sig.args as Array).size()==2,"signal %s has two arguments"%sig.name)
	var expected:={"quote_blueprint":3,"submit_blueprint":7,"_handle_blueprint_quote":7,"_handle_blueprint_apply":8,
		"request_blueprint_quote":6,"request_blueprint_apply":7,"_blueprint_now":0}
	for m in expected:
		var n:=method_args(Session,m)
		expect(n==int(expected[m]),"Session.%s has %d parameters (got %d; -1 = missing)"%[m,int(expected[m]),n])
	for m in ["receive_blueprint_quote","receive_blueprint_result"]:
		expect(method_args(Session,m)>=0,"Session.%s exists"%m)
	expect(method_args(World,"blueprint_receipt")==2,"World.blueprint_receipt(token, nonce) exists (Root)")
	var script_res:Script=Session
	if not script_res.has_method("get_rpc_config"):
		expect(false,"Script.get_rpc_config available to verify RPC annotations")
		return
	var cfg=script_res.call("get_rpc_config")
	expect(cfg is Dictionary,"Session RPC config is a Dictionary")
	if not cfg is Dictionary:return
	for m in ["request_blueprint_quote","request_blueprint_apply"]:
		var c=cfg.get(m)
		expect(c is Dictionary and int(c.get("rpc_mode",-1))==MultiplayerAPI.RPC_MODE_ANY_PEER and int(c.get("transfer_mode",-1))==MultiplayerPeer.TRANSFER_MODE_RELIABLE and int(c.get("channel",-1))==2 and c.get("call_local",true)==false,
			"%s is any_peer, call_remote, reliable, channel 2: %s"%[m,str(c)])
	for m in ["receive_blueprint_quote","receive_blueprint_result","receive_state","receive_action_completed"]:
		var c=cfg.get(m)
		expect(c is Dictionary and int(c.get("rpc_mode",-1))==MultiplayerAPI.RPC_MODE_AUTHORITY and int(c.get("transfer_mode",-1))==MultiplayerPeer.TRANSFER_MODE_RELIABLE and int(c.get("channel",-1))==3,
			"%s is authority, reliable, channel 3 (snapshot and result share one ordered channel): %s"%[m,str(c)])

func test_wrappers() -> void:
	if site1.x<0:
		expect(false,"wrapper test needs site1")
		return
	if not (s.has_method("quote_blueprint") and s.has_method("submit_blueprint")):
		expect(false,"public quote_blueprint / submit_blueprint exist")
		return
	pose(stand(site1))
	var raw:=pair_raw()
	var direct0:Dictionary=w.quote_blueprint(A,raw,site1,0)
	var direct1:Dictionary=w.quote_blueprint(A,raw,site1,1)
	expect(direct0.get("ok")==true,"direct World quote at site1 ok: "+str(direct0.get("message")))
	var counter0:int=int(s.counter)
	var seq0:int=int(s.sequences.get(1,-1))
	var before:=fp()
	bclock.ms+=5000
	events.clear()
	var id1=s.call("quote_blueprint",raw,site1,0)
	var id2=s.call("quote_blueprint",raw,site1,1)
	expect(id1 is int and id2 is int,"quote_blueprint returns an int request ID")
	if not (id1 is int and id2 is int):return
	expect(int(id1)>=1 and int(id1)<=1000000000 and int(id2)>int(id1),"request IDs are in 1..1e9 and increase (%d, %d)"%[int(id1),int(id2)])
	expect(blueprint_replies().is_empty(),"host wrapper results are deferred: nothing emitted before the caller holds the IDs")
	await settle()
	var got:=replies("quote")
	expect(got.size()==2,"two wrapper quotes, two replies (got %d)"%got.size())
	if got.size()==2:
		expect(got[0][1]==id1 and got[1][1]==id2,"replies arrive in request-ID order")
		var r0:Dictionary=got[0][2] if got[0][2] is Dictionary else {}
		var r1:Dictionary=got[1][2] if got[1][2] is Dictionary else {}
		check_result(r0,"wrapper quote turns 0")
		check_result(r1,"wrapper quote turns 1")
		expect(r0.get("ok")==true and r0.get("hash")==direct0.get("hash") and ints(r0.get("cost"))==ints(direct0.get("cost")) and r0.get("pieces")==direct0.get("pieces"),"wrapper quote equals the authoritative World quote")
		expect(r1.get("hash")==direct1.get("hash") and r1.get("hash")!=r0.get("hash"),"turns forwarded exactly once (hash = World quote with turns 1)")
		expect(r0.get("rate_limited",false)==false and r1.get("rate_limited",false)==false,"two quotes in one second are allowed")
	expect(int(s.counter)==counter0 and int(s.sequences.get(1,-1))==seq0,"blueprint request IDs never use the action sequence")
	same(before,"wrapper quotes")
	var h:=str(direct0.get("hash",""))
	var n:=nonce()
	var inv0:=inv()
	bclock.ms+=2000
	events.clear()
	var state0:=var_to_str(w.state)
	s.call("submit_blueprint",n,raw,site1,0,h)
	expect(blueprint_replies().is_empty() and var_to_str(w.state)==state0,"host submit is deferred: nothing built or emitted synchronously")
	await settle()
	var applied:=replies("apply")
	var r:=one(applied,"wrapper submit")
	if not applied.is_empty():expect(applied[0][1]==n,"apply reply carries the submitted nonce")
	expect(r.get("ok")==true,"wrapper submit (region/epoch captured from own snapshot) builds: "+str(r.get("message")))
	expect(floors_at(site1,2,A),"both floors built at site1")
	expect(inv()==minus(inv0,ints(direct0.get("cost"))),"charged exactly the quoted cost")
	expect(has_receipt(A,n),"receipt stored under blueprint:<nonce>")
	expect(int(s.counter)==counter0 and int(s.sequences.get(1,-1))==seq0,"submit never uses the action sequence")

func test_json() -> void:
	if site2.x<0:
		expect(false,"JSON test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var raw:=pair_raw()
	var base:=JSON.stringify(raw)
	var direct:Dictionary=w.quote_blueprint(A,raw,site2,0)
	var q:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1]),"baseline JSON quote")
	expect(q.get("ok")==true and q.get("hash")==direct.get("hash"),"baseline JSON quote ok and equal to World")
	var extra:=pair_raw()
	extra["extra"]=1
	var zero:=pair_raw()
	zero.width=0
	var boolean:=pair_raw()
	boolean.pieces[0].x=true
	var cases:={"empty":"","whitespace":"   ","malformed":"{\"version\":1,","trailing garbage":base+"}",
		"array":"[]","wrapped in array":"["+base+"]","number":"42","string":JSON.stringify(base),"null":"null",
		"bool":"true","unknown field":JSON.stringify(extra),"zero width":JSON.stringify(zero),"bool coordinate":JSON.stringify(boolean)}
	for label in cases:
		var before:=fp()
		var id:=next_rid()
		var got:Array=await hq(1,id,str(cases[label]),site2,0,c[0],c[1])
		var r:=one(got,"json "+label)
		expect(r.get("ok")==false,"json %s rejected"%label)
		if not got.is_empty():expect(got[0][1]==id,"json %s reply carries its request ID"%label)
		same(before,"json "+label)
	var pad:=base+" ".repeat(JSON_LIMIT-base.to_utf8_buffer().size())
	expect(pad.to_utf8_buffer().size()==JSON_LIMIT,"padded design is exactly 128 KiB")
	var at:=one(await hq(1,next_rid(),pad,site2,0,c[0],c[1]),"exactly 128 KiB")
	expect(at.get("ok")==true and at.get("hash")==direct.get("hash"),"exactly 128 KiB (valid JSON whitespace) is accepted")
	var cjk:="藍".repeat(int(float(JSON_LIMIT)/3.0)+1)
	expect(cjk.length()<JSON_LIMIT and cjk.to_utf8_buffer().size()>JSON_LIMIT,"CJK payload is under the char limit but over the byte limit")
	var oversized:={"one byte over":pad+" ","CJK bytes over":cjk,"512 KiB":" ".repeat(JSON_LIMIT*4)+base}
	for label in oversized:
		var before:=fp()
		var r:=one(await hq(1,next_rid(),str(oversized[label]),site2,0,c[0],c[1]),"oversized "+label)
		expect(r.get("ok")==false,"oversized %s rejected"%label)
		same(before,"oversized "+label)
	var before_apply:=fp()
	var n:=nonce()
	var ra:=one(await ha(1,n,pad+" ",site2,0,str(direct.get("hash","")),c[0],c[1]),"oversized apply")
	expect(ra.get("ok")==false and not has_receipt(A,n),"oversized apply rejected without a receipt")
	same(before_apply,"oversized apply")
	n=nonce()
	ra=one(await ha(1,n,"[]",site2,0,str(direct.get("hash","")),c[0],c[1]),"non-Dictionary apply")
	expect(ra.get("ok")==false and not has_receipt(A,n),"non-Dictionary apply rejected without a receipt")
	same(before_apply,"non-Dictionary apply")

func test_turns() -> void:
	if site2.x<0:
		expect(false,"turns test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var raw:=pair_raw()
	var base:=JSON.stringify(raw)
	for t in 4:
		var direct:Dictionary=w.quote_blueprint(A,raw,site2,t)
		var r:=one(await hq(1,next_rid(),base,site2,t,c[0],c[1]),"turns %d"%t)
		expect(r.get("hash")==direct.get("hash") and r.get("ok")==direct.get("ok"),"turns %d forwarded unchanged (matches World)"%t)
	var h:=str(w.quote_blueprint(A,raw,site2,0).get("hash",""))
	for t in [true,false,1.5,0.5,4,-1,"1",null,Vector2i(1,0)]:
		var before:=fp()
		var r:=one(await hq(1,next_rid(),base,site2,t,c[0],c[1]),"turns %s"%var_to_str(t))
		expect(r.get("ok")==false,"turns %s rejected"%var_to_str(t))
		same(before,"quote turns "+var_to_str(t))
		var n:=nonce()
		var ra:=one(await ha(1,n,base,site2,t,h,c[0],c[1]),"apply turns %s"%var_to_str(t))
		expect(ra.get("ok")==false and not has_receipt(A,n),"apply turns %s rejected without a receipt"%var_to_str(t))
		same(before,"apply turns "+var_to_str(t))

func test_bounds() -> void:
	if site2.x<0:
		expect(false,"bounds test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var base:=JSON.stringify(pair_raw())
	var h:=str(w.quote_blueprint(A,pair_raw(),site2,0).get("hash",""))
	for bad in [0,-1,1000000001,-2147483648]:
		var before:=fp()
		var got:Array=await hq(1,bad,base,site2,0,c[0],c[1])
		only_failures(got,"request ID %d"%bad)
		same(before,"request ID %d"%bad)
	for origin in [Vector2i(5000000,0),Vector2i(0,-5000000),Vector2i(10001,10001)]:
		var before:=fp()
		var r:=one(await hq(1,next_rid(),base,origin,0,c[0],c[1]),"origin %s"%origin)
		expect(r.get("ok")==false,"origin %s rejected"%origin)
		var n:=nonce()
		var ra:=one(await ha(1,n,base,origin,0,h,c[0],c[1]),"apply origin %s"%origin)
		expect(ra.get("ok")==false and not has_receipt(A,n),"apply origin %s rejected"%origin)
		same(before,"origin %s"%origin)

func test_gates() -> void:
	if site2.x<0:
		expect(false,"gate test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var base:=JSON.stringify(pair_raw())
	var h:=str(w.quote_blueprint(A,pair_raw(),site2,0).get("hash",""))
	var before:=fp()
	# Unknown peer and a remote peer: nothing may surface at the host.
	var got:Array=await hq(7,next_rid(),base,site2,0,c[0],c[1])
	expect(blueprint_replies().is_empty(),"unknown peer: no reply surfaces at the host")
	got=await ha(7,nonce(),base,site2,0,h,c[0],c[1])
	expect(blueprint_replies().is_empty(),"unknown peer apply: no reply surfaces at the host")
	same(before,"unknown peer")
	got=await hq(2,next_rid(),base,site2,0,HOME,0)
	expect(blueprint_replies().is_empty(),"peer 2 quote is answered to peer 2, never at the host")
	same(before,"remote peer quote")
	# accepting=false: identified caller gets an explicit failure.
	s.accepting=false
	var n:=nonce()
	var r:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1]),"not accepting quote")
	expect(r.get("ok")==false,"not accepting: quote refused")
	r=one(await ha(1,n,base,site2,0,h,c[0],c[1]),"not accepting apply")
	expect(r.get("ok")==false and not has_receipt(A,n),"not accepting: apply refused without receipt")
	same(before,"not accepting")
	s.accepting=true
	# Identity gate (membership world without a valid claim for peer 1).
	s.membership=Membership.new()
	expect(not s.identity_allows_play(1),"fixture: peer 1 has no valid identity")
	n=nonce()
	only_failures(await hq(1,next_rid(),base,site2,0,c[0],c[1]),"unauthenticated quote")
	only_failures(await ha(1,n,base,site2,0,h,c[0],c[1]),"unauthenticated apply")
	expect(not has_receipt(A,n),"unauthenticated apply leaves no receipt")
	same(before,"unauthenticated")
	s.membership=null
	# Admission recovery freeze.
	s.freeze_admission_writes()
	n=nonce()
	only_failures(await hq(1,next_rid(),base,site2,0,c[0],c[1]),"admission freeze quote")
	only_failures(await ha(1,n,base,site2,0,h,c[0],c[1]),"admission freeze apply")
	expect(not has_receipt(A,n),"admission freeze apply leaves no receipt")
	same(before,"admission freeze")
	s.admission_recovery_required=false
	s.accepting=true
	r=one(await hq(1,next_rid(),base,site2,0,c[0],c[1]),"after gates reopen")
	expect(r.get("ok")==true,"quotes work again once gates reopen: "+str(r.get("message")))

func test_stale() -> void:
	if site2.x<0:
		expect(false,"stale test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var region:String=c[0]
	var epoch:int=c[1]
	var base:=JSON.stringify(pair_raw())
	var h:=str(w.quote_blueprint(A,pair_raw(),site2,0).get("hash",""))
	var cases:=[[LANYANG,epoch,"other region"],[region,epoch+1,"epoch ahead"],[region,epoch-1,"epoch behind"],[region,-1,"epoch -1"],["",epoch,"empty region"],["nowhere",epoch,"unknown region"]]
	for item in cases:
		var label:String=item[2]
		var before:=fp()
		var r:=one(await hq(1,next_rid(),base,site2,0,str(item[0]),int(item[1])),"stale quote "+label)
		expect(r.get("ok")==false and r.get("stale_context")==true,"stale quote (%s) replies stale_context"%label)
		var n:=nonce()
		var ra:=one(await ha(1,n,base,site2,0,h,str(item[0]),int(item[1])),"stale apply "+label)
		expect(ra.get("ok")==false and ra.get("stale_context")==true and not has_receipt(A,n),"stale apply (%s) replies stale_context, no receipt"%label)
		same(before,"stale "+label)

func forged(h:String) -> String:
	if h.length()!=64:return "ab".repeat(32)
	return h.substr(0,63)+("1" if h.right(1)!="1" else "2")

func test_rates() -> void:
	if site2.x<0:
		expect(false,"rate test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var base:=JSON.stringify(pair_raw())
	var h:=str(w.quote_blueprint(A,pair_raw(),site2,0).get("hash",""))
	var before:=fp()
	bclock.ms+=10000
	var r1:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1],false),"rate quote 1")
	var r2:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1],false),"rate quote 2")
	expect(r1.get("ok")==true and r2.get("ok")==true and not r1.get("rate_limited",false) and not r2.get("rate_limited",false),"two quotes in the same instant pass")
	var r3:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1],false),"rate quote 3")
	expect(r3.get("ok")==false and r3.get("rate_limited")==true,"third quote within a second is rate_limited")
	# Apply has its own limiter: the exhausted quote window does not block it.
	var ra:=one(await ha(1,nonce(),base,site2,0,forged(h),c[0],c[1],false),"rate apply 1")
	expect(not ra.get("rate_limited",false) and ra.get("requote")==true,"apply passes while quotes are exhausted (forged hash -> requote)")
	var rb:=one(await ha(1,nonce(),base,site2,0,forged(h),c[0],c[1],false),"rate apply 2")
	expect(rb.get("ok")==false and rb.get("rate_limited")==true,"second apply in the same instant is rate_limited")
	bclock.ms+=1100
	var r4:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1],false),"rate quote after 1.1 s")
	expect(r4.get("ok")==true and not r4.get("rate_limited",false),"quote window recovers after one second while apply is still limited")
	var rc:=one(await ha(1,nonce(),base,site2,0,forged(h),c[0],c[1],false),"rate apply after 1.1 s")
	expect(rc.get("rate_limited")==true,"apply still limited 1100 ms later")
	bclock.ms+=500
	var rd:=one(await ha(1,nonce(),base,site2,0,forged(h),c[0],c[1],false),"rate apply after 1.6 s")
	expect(not rd.get("rate_limited",false) and rd.get("requote")==true,"apply allowed again after 1500 ms")
	same(before,"rate limits")
	# Normal-action limiter state never throttles blueprints (and vice versa via fp()).
	var saved:Array=(s.rates[1] as Array).duplicate()
	var full:Array=[]
	for i in 12:full.append(Time.get_ticks_msec())
	s.rates[1]=full
	var rq:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1]),"quote while action limiter is full")
	expect(rq.get("ok")==true and not rq.get("rate_limited",false),"a full normal-action limiter does not throttle blueprint quotes")
	expect((s.rates[1] as Array).size()==12,"blueprint quote did not append to the normal-action limiter")
	s.rates[1]=saved

func test_forged() -> void:
	if site2.x<0:
		expect(false,"forgery test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var base:=JSON.stringify(pair_raw())
	var h:=str(w.quote_blueprint(A,pair_raw(),site2,0).get("hash",""))
	expect(h.length()==64,"site2 quote has a 64-hex hash")
	var z:="0".repeat(31)
	for bad in ["",z,z+"00","A"+z,"g"+z,"blueprint:"+z+"0"," "+z,z+"\n"]:
		var before:=fp()
		only_failures(await ha(1,bad,base,site2,0,h,c[0],c[1]),"forged nonce '%s'"%bad.c_escape())
		same(before,"forged nonce '%s'"%bad.c_escape())
	for bad in ["","abc",h.to_upper(),h.left(63),h+"0","g"+h.right(63)]:
		if bad==h:continue
		var before:=fp()
		var n:=nonce()
		var r:=one(await ha(1,n,base,site2,0,bad,c[0],c[1]),"malformed hash")
		expect(r.get("ok")==false and not has_receipt(A,n),"malformed hash '%s' refused"%bad.left(12))
		same(before,"malformed hash")
	var before2:=fp()
	var n2:=nonce()
	var r2:=one(await ha(1,n2,base,site2,0,forged(h),c[0],c[1]),"forged hash")
	expect(r2.get("ok")==false and r2.get("requote")==true,"well-formed but forged hash asks for requote")
	var fresh=r2.get("quote")
	expect(fresh is Dictionary and fresh.get("hash")==h and fresh.get("ok")==true,"requote carries the current public quote")
	expect(not has_receipt(A,n2),"forged hash stores no receipt")
	var other:=str(w.quote_blueprint(A,pair_raw(),site2,2).get("hash",""))
	var r3:=one(await ha(1,nonce(),base,site2,0,other,c[0],c[1]),"hash of another rotation")
	expect(r3.get("ok")==false and r3.get("requote")==true,"hash quoted for another rotation is not accepted")
	same(before2,"forged hashes")

func test_problems() -> void:
	if site4.x<0:
		expect(false,"problem-cap test needs site4")
		return
	var saved:Dictionary=w.state.duplicate(true)
	# Fixture: prepare the land and put 40 floors under B's ownership.
	var pieces:=[]
	for y in 4:
		for x in 10:
			var cell:=site4+Vector2i(x,y)
			var tile:=World.key(cell)
			if not w.resource(cell).is_empty():w.state.removed[tile]=true
			w.state.ground[tile]={"type":"floor","owner":B}
			pieces.append({"kind":"floor","x":x,"y":y})
	var raw:={"version":1,"name":"大地板","width":10,"height":4,"pieces":pieces}
	pose(stand(site4))
	var c:=ctx()
	var direct:Dictionary=w.quote_blueprint(A,raw,site4,0)
	var before:=fp()
	var r:=one(await hq(1,next_rid(),JSON.stringify(raw),site4,0,c[0],c[1]),"40 problems")
	expect(r.get("ok")==false and r.get("problems") is Array and (r.get("problems") as Array).size()==32,"40 bad cells reported as at most 32 problems")
	expect(r.get("problems")==direct.get("problems"),"forwarded problems equal World's (absolute world coordinates)")
	if r.get("problems") is Array:
		var inside:=true
		for p in r.problems:
			if p is Dictionary and not Rect2i(site4,Vector2i(10,4)).has_point(Vector2i(int(p.get("x",-1)),int(p.get("y",-1)))):inside=false
		expect(inside,"problem coordinates are absolute cells inside the footprint")
	same(before,"problem quote")
	w.state=saved

func snapshot_has_floor(data,o:Vector2i) -> bool:
	if not data is Dictionary or not data.get("ground") is Dictionary:return false
	var g=data.ground.get(World.key(o))
	return g is Dictionary and g.get("type")=="floor" and g.get("owner")==A.sha256_text().left(16)

func test_apply_and_receipts() -> void:
	if site2.x<0:
		expect(false,"apply test needs site2")
		return
	pose(stand(site2))
	expect(w.save(),"pre-apply baseline saved")
	var c:=ctx()
	var raw:=pair_raw()
	var base:=JSON.stringify(raw)
	var q:=one(await hq(1,next_rid(),base,site2,0,c[0],c[1]),"apply quote")
	expect(q.get("ok")==true,"site2 quote ok: "+str(q.get("message")))
	var h:=str(q.get("hash",""))
	var n:=nonce()
	var inv0:=inv()
	var builds0:=int(w.state.players[A].get("builds",0))
	var committed0:=int(w.state.committed)
	var bytes0:=FileAccess.get_file_as_bytes(w.save_path)
	var got:Array=await ha(1,n,base,site2,0,h,c[0],c[1])
	var r:=one(got,"apply")
	if not got.is_empty():expect(got[0][1]==n,"apply reply carries the nonce")
	expect(r.get("ok")==true and r.get("hash")==h and r.get("pieces")==2 and ints(r.get("cost"))==ints(q.get("cost")),"apply succeeds with the quoted hash and cost: "+str(r.get("message")))
	if r.get("ok")!=true:return
	var idx_apply:=-1
	for i in events.size():
		if events[i][0]=="apply":
			idx_apply=i
			break
	var idx_state:=-1
	for i in range(maxi(idx_apply,0)):
		if events[i][0]=="state" and snapshot_has_floor(events[i][2],site2):idx_state=i
	expect(idx_apply>=0 and idx_state>=0 and idx_state<idx_apply,"snapshot showing the new floors is delivered before the blueprint result")
	var snap_text:=var_to_str(s.snapshot)
	expect(not snap_text.contains("SECRET") and not snap_text.contains("blueprint:"+n),"snapshot carries no token and no receipt")
	expect(floors_at(site2,2,A),"both floors built atomically")
	expect(inv()==minus(inv0,ints(q.get("cost"))),"inventory charged exactly once")
	expect(int(w.state.players[A].get("builds",0))==builds0+2 and int(w.state.committed)==committed0+1,"one commit, two builds")
	expect(has_receipt(A,n) and FileAccess.get_file_as_bytes(w.save_path)!=bytes0,"receipt stored and saved")
	var disk=World.new()
	expect(disk.load_world(w.save_path),"saved world reloads")
	expect(disk.state.players.get(A,{}).get("receipts",{}).has("blueprint:"+n) and disk.state.ground.has(World.key(site2+Vector2i(1,0))),"receipt and floors persisted")
	# World.blueprint_receipt (Root).
	if w.has_method("blueprint_receipt"):
		var region0:String=w._region
		var state0:=var_to_str(w.state)
		var got_receipt=w.call("blueprint_receipt",A,n)
		expect(got_receipt is Dictionary and got_receipt.get("ok")==true and got_receipt.get("hash")==h,"blueprint_receipt returns the stored receipt")
		if got_receipt is Dictionary:
			got_receipt["ok"]=false
			expect(w.state.players[A].receipts["blueprint:"+n].get("ok")==true,"blueprint_receipt returns a safe copy")
		for bad in [[B,n],[A,"f".repeat(32)],[A,"A"+n.substr(1)],[A,"blueprint:"+n],["tok-nobody",n],[A,""]]:
			var res=w.call("blueprint_receipt",bad[0],bad[1])
			expect(res is Dictionary and (res as Dictionary).is_empty(),"blueprint_receipt %s is {}"%str(bad[1]).left(16))
		expect(var_to_str(w.state)==state0 and w._region==region0,"blueprint_receipt is read-only and keeps orientation")
	else:expect(false,"World.blueprint_receipt exists (Root)")
	# Same-nonce replay: rate-bounded, then the stored receipt, never a rebuild.
	var before:=fp()
	var limited:=one(await ha(1,n,base,site2,0,h,c[0],c[1],false),"immediate replay")
	expect(limited.get("rate_limited")==true,"immediate receipt replay is still rate-bounded")
	var replay:=one(await ha(1,n,base,site2,0,h,c[0],c[1]),"replay")
	expect(replay.get("ok")==true and replay.get("hash")==h and replay.get("pieces")==2,"replay returns the stored receipt")
	same(before,"same-nonce replay")
	# Travel (fixture): A moved to Lanyang with a new epoch.
	var person:Dictionary=w.state.players[A]
	person.region=LANYANG
	person.travel_epoch=int(person.travel_epoch)+1
	var spot:Vector2=REGIONS.spawn(LANYANG)
	person.x=spot.x
	person.y=spot.y
	expect(w.save(),"travel fixture saved")
	s._send_snapshot(1)
	var moved:=ctx()
	before=fp()
	var after_travel:=one(await ha(1,n,base,site2,0,h,c[0],c[1]),"replay after travel")
	expect(after_travel.get("ok")==true and after_travel.get("hash")==h and not after_travel.get("stale_context",false),"committed nonce answers with its receipt after travel (old context)")
	var fresh_old:=one(await ha(1,nonce(),base,site2,0,h,c[0],c[1]),"new nonce old context")
	expect(fresh_old.get("ok")==false and fresh_old.get("stale_context")==true,"a new nonce with the old context is stale")
	var n3:=nonce()
	var fresh_new:=one(await ha(1,n3,base,site2,0,h,moved[0],moved[1]),"new nonce in Lanyang")
	expect(fresh_new.get("ok")==false and not has_receipt(A,n3),"new nonce in another region is fully revalidated and refused")
	same(before,"after travel")
	# Peer 2 reusing A's nonce never sees or reuses A's receipt.
	var a_receipt:=var_to_str(w.state.players[A].receipts["blueprint:"+n])
	var other:Array=await ha(2,n,base,site2,0,h,HOME,0)
	expect(other.is_empty() and blueprint_replies().is_empty(),"peer 2 result is never delivered at the host")
	expect(not has_receipt(B,n) and var_to_str(w.state.players[A].receipts["blueprint:"+n])==a_receipt,"peer 2 cannot build with or alter A's receipt")
	same(before,"peer 2 with A's nonce")
	# Return home (fixture).
	person.region=HOME
	person.travel_epoch=int(person.travel_epoch)+1
	expect(w.save(),"return fixture saved")
	s._send_snapshot(1)

func test_save_failure() -> void:
	if site3.x<0:
		expect(false,"save-failure test needs site3")
		return
	pose(stand(site3))
	var c:=ctx()
	var base:=JSON.stringify(single_raw())
	var q:=one(await hq(1,next_rid(),base,site3,0,c[0],c[1]),"save-failure quote")
	expect(q.get("ok")==true,"site3 quote ok: "+str(q.get("message")))
	var good:String=w.save_path
	var good_bytes:=FileAccess.get_file_as_bytes(good)
	w.save_path=dir+"/missing-subdir/world.json"
	var before:=fp()
	var n1:=nonce()
	var r:=one(await ha(1,n1,base,site3,0,str(q.get("hash","")),c[0],c[1]),"save failure apply")
	expect(r.get("ok")==false and not r.get("rate_limited",false) and not r.get("stale_context",false),"storage failure is an explicit apply failure")
	same(before,"save failure")
	expect(not has_receipt(A,n1) and FileAccess.get_file_as_bytes(good)==good_bytes,"no receipt, real save untouched")
	w.save_path=good
	var q2:=one(await hq(1,next_rid(),base,site3,0,c[0],c[1]),"requote after storage recovers")
	var n2:=nonce()
	var r2:=one(await ha(1,n2,base,site3,0,str(q2.get("hash","")),c[0],c[1]),"retry with new nonce")
	expect(r2.get("ok")==true and floors_at(site3,1,A),"new nonce succeeds after storage recovers (accepting=%s): %s"%[str(s.accepting),str(r2.get("message"))])
	expect(not has_receipt(A,n1),"failed nonce never gained a receipt")

func test_normal_action() -> void:
	if site5.x<0:
		expect(false,"normal-action test needs site5")
		return
	pose(stand(site5))
	var seq0:int=int(s.sequences.get(1,0))
	var id:int=int(s.perform("build",site5,"floor"))
	expect(int(s.sequences.get(1,-1))==id and id>seq0,"normal action uses its own sequence after blueprint traffic")
	expect(floors_at(site5,1,A),"ordinary build still works after blueprint traffic")

func test_request_id_top() -> void:
	if site2.x<0:
		expect(false,"request ID boundary test needs site2")
		return
	pose(stand(site2))
	var c:=ctx()
	var got:Array=await hq(1,1000000000,JSON.stringify(pair_raw()),site2,0,c[0],c[1])
	var r:=one(got,"request ID 1e9")
	if not got.is_empty():expect(got[0][1]==1000000000,"request ID 1e9 echoed")
	expect(r.has("ok") and not r.get("rate_limited",false),"request ID 1e9 is accepted (result: %s)"%str(r.get("message")))

func attach_remote_fixture() -> void:
	# No welcome RPC to a nonexistent connection: explicitly seed an already
	# registered peer for handler/cleanup tests, then initialize the real limiter.
	s.peers[2]=B
	s.directions[2]=Vector2.ZERO
	s.last_movement[2]=0
	s.sequences[2]=0
	s.rates[2]=[]
	s.pending.erase(2)
	s._blueprint_attach(2)

func test_peer_cleanup() -> void:
	var with2:=dicts_with(2)
	expect("peers" in with2,"peer 2 attached before cleanup")
	var extra:=[]
	for pname in with2:
		if pname not in LEGACY_PEER_DICTS:extra.append(pname)
	expect(not extra.is_empty(),"attach initialised per-peer blueprint state for peer 2 (dicts: %s)"%str(with2))
	s._peer_left(2)
	expect(dicts_with(2).is_empty(),"peer departure clears every per-peer Dictionary (left: %s)"%str(dicts_with(2)))
	var with1:=dicts_with(1)
	for pname in extra:expect(pname in with1,"host's own %s entry kept"%str(pname))
	expect(not w.active_tokens.has(B),"departed token inactive")
	w.add_player(B,"Bob")
	attach_remote_fixture()
	var again:=dicts_with(2)
	for pname in extra:expect(pname in again,"rejoin re-initialises %s"%str(pname))
	s._peer_left(2)
	expect(dicts_with(2).is_empty(),"second departure clears again")

func test_no_world() -> void:
	var sink:Array=[]
	var lone=HostSession.new()
	lone.fixture_name="SessionNoWorld"
	root.add_child(lone)
	capture(lone,sink)
	lone.set("blueprint_clock",Callable(bclock,"now"))
	var main_state:=var_to_str(w.state)
	var base:=JSON.stringify(pair_raw())
	if lone.has_method("_handle_blueprint_quote") and lone.has_method("_handle_blueprint_apply"):
		bclock.ms+=2000
		lone.call("_handle_blueprint_quote",1,5,base,site2,0,HOME,0)
		lone.call("_handle_blueprint_apply",1,nonce(),base,site2,0,"0".repeat(64),HOME,0)
		await settle()
		for e in blueprint_replies(sink):expect(e[2] is Dictionary and e[2].get("ok")==false,"no-world handler never reports success")
	else:expect(false,"no-world session exposes the handlers")
	expect(var_to_str(w.state)==main_state,"no-world session never reaches another World")
	var enet:=ENetMultiplayerPeer.new()
	var err:=enet.create_client("127.0.0.1",9)
	expect(err==OK,"fixture: unconnected loopback ENet client created")
	if err==OK and lone.has_method("quote_blueprint") and lone.has_method("submit_blueprint"):
		var mp:MultiplayerAPI=lone.multiplayer
		mp.multiplayer_peer=enet
		expect(enet.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED,"fixture: client is not connected")
		sink.clear()
		var id=lone.call("quote_blueprint",pair_raw(),site2,0)
		lone.call("submit_blueprint",nonce(),pair_raw(),site2,0,"0".repeat(64))
		await settle()
		expect(id is int,"disconnected quote_blueprint still returns an int")
		var quotes:=replies("quote",sink)
		if id is int and int(id)>0:
			expect(quotes.size()==1 and quotes[0][1]==id and quotes[0][2] is Dictionary and quotes[0][2].get("ok")==false,"disconnected quote with an ID gets an explicit failure (no endless wait)")
		for e in blueprint_replies(sink):expect(e[2] is Dictionary and e[2].get("ok")==false,"disconnected client never reports success")
		mp.multiplayer_peer=OfflineMultiplayerPeer.new()
		enet.close()
	elif err==OK:
		expect(false,"no-world session exposes the public wrappers")
		enet.close()
	expect(var_to_str(w.state)==main_state,"disconnected client never changes the host World")
	lone.free()
