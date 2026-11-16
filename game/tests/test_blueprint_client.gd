extends SceneTree
## Headless state / IO tests for the blueprint client controller
## (docs/blueprint-client-contract.md, 「Controller 與本機保存」).
##
## Under test: res://scripts/blueprint_controller.gd (loaded at runtime so a
## missing script is a counted failure, not a parse error), driven against a
## REAL Session host (peer id 1) and a REAL, isolated World.
##
## Fixture (NOT normal play):
##  * HostSession overrides _ready so user://profile.json is never read or
##    written; physics/world ticking is off so state comparisons stay exact.
##  * HostSession additionally records every quote_blueprint/submit_blueprint
##    call (spy) and can, on explicit request, DROP a submission before it
##    reaches the World (simulated lost transport) or DROP the reply after the
##    World committed (simulated lost result). These are clearly-labelled
##    asynchronous lost / out-of-order cases; everything else goes through the
##    real Session -> World path.
##  * Out-of-order / foreign replies are injected by emitting the real Session
##    signals with fabricated payloads (labelled "injected").
##  * Disconnect is simulated by emitting Session.disconnected_world.
##  * Inventories, positions, travel/epoch changes, own/foreign floors and the
##    automatic roof are written directly into the World.
##  * Blueprint rate limits use a fake blueprint_clock; undo uses fake clocks.
##  * Every library / pending / world path lives in one per-run user:// dir
##    that is removed at the end. No real profile, library or save is touched.
## Missing API and every guard that skips work are counted failures.

const World=preload("res://scripts/world.gd")
const Library=preload("res://scripts/blueprint_library.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const REGIONS=preload("res://scripts/regions.gd")
const CONTROLLER_PATH:="res://scripts/blueprint_controller.gd"

const A:="tok-alice-SECRET-client"
const B:="tok-bob-SECRET-client"
const SCOPE:="test-scope-island-alpha"
const SCOPE2:="test-scope-island-beta"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const PARK:=World.SPAWN
const PENDING_KEYS:=["version","scope","actor","nonce","design","origin","turns","hash","region","epoch"]
const STATE_PROPS:=["mode","entries","captured","auto_roofs_omitted","draft","origin","turns","locked","quote","quote_waiting","status","library_error","pending","pending_error"]
const METHODS:={"setup":3,"dispose":0,"begin_capture":0,"capture_area":2,"save_capture":1,"rename_entry":2,
	"delete_entry":1,"choose":1,"move_origin":1,"pin_origin":1,"reposition":0,"rotate":0,"request_quote":0,
	"confirm":0,"retry_pending":0,"cancel":0}

class HostSession extends "res://scripts/session.gd":
	var fixture_name:="Session"
	## Spy records (fixture): every quote / submit the controller makes.
	var quotes:Array=[]
	var submits:Array=[]
	## Fixture: drop the next N submissions before the World (lost transport).
	var drop_submits:=0
	## Fixture: drop the next N apply replies after the World answered (lost result).
	var drop_results:=0
	## Pending file inspected at submit time.
	var watch_path:=""
	var on_submit:Callable
	func _ready() -> void:
		name=fixture_name
		session_nonce="0123456789abcdef0123456789abcdef"
		set_physics_process(false)
	func quote_blueprint(raw:Variant,origin:Vector2i,turns:Variant=0) -> int:
		var id:int=super.quote_blueprint(raw,origin,turns)
		quotes.append({"id":id,"raw":(raw as Dictionary).duplicate(true) if raw is Dictionary else raw,"origin":origin,"turns":turns})
		return id
	func submit_blueprint(nonce:String,raw:Variant,origin:Vector2i,turns:Variant,expected_hash:String,region:String="",epoch:int=-1) -> void:
		var exists:=not watch_path.is_empty() and FileAccess.file_exists(watch_path)
		submits.append({"nonce":nonce,"raw":(raw as Dictionary).duplicate(true) if raw is Dictionary else raw,"origin":origin,
			"turns":turns,"hash":expected_hash,"region":region,"epoch":epoch,"pending_exists":exists,
			"pending_text":FileAccess.get_file_as_string(watch_path) if exists else ""})
		if on_submit.is_valid():on_submit.call()
		if drop_submits>0:
			drop_submits-=1
			return
		super.submit_blueprint(nonce,raw,origin,turns,expected_hash,region,epoch)
	func _reply_blueprint_result(id:int,nonce:String,result:Dictionary) -> void:
		if drop_results>0:
			drop_results-=1
			return
		super._reply_blueprint_result(id,nonce,result)

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
var dir:=""
var lib:=""
var Controller:Script
var s=null
var w=null
var bclock:Ticks
var uclock:FakeClock
var own:=""
var serial:=0
var applied_events:Array=[]
var feedbacks:Array=[]
var live:Array=[]
var src:=Vector2i(-1,-1)
var sites:Array=[]

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	dir="user://test-blueprint-client-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var made:=DirAccess.make_dir_recursive_absolute(dir)==OK
	expect(made,"isolated test directory created")
	if not made:
		finish()
		return
	lib=dir+"/library.json"
	setup_world()
	if test_contract():
		await test_library()
		await test_corrupt_library()
		await test_placement()
		await test_confirm_success()
		await test_requote()
		await test_save_failure()
		await test_unknown_and_scopes()
		await test_lost_reply_restart()
		await test_delete_failure()
		await test_corrupt_pending()
		await test_foreign_results()
		await test_timeouts()
	cleanup()
	finish()

func finish() -> void:
	print("BLUEPRINT_CLIENT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

# ---------------------------------------------------------------- fixtures --

func settle(frames:int=3) -> void:
	for i in frames:await process_frame

func tick() -> void:
	bclock.ms+=2000

func pending_path(library:String,scope:String) -> String:
	return library+".pending-"+scope.sha256_text().left(16)+".json"

func clear_cell(c:Vector2i) -> bool:
	if not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":return false
	var k:=World.key(c)
	for f in ["objects","ground","roofs","crops","forest"]:
		if w.state[f].has(k):return false
	return true

func site_ok(o:Vector2i,size:Vector2i) -> bool:
	for y in range(o.y,o.y+size.y):
		if not clear_cell(Vector2i(o.x-1,y)):return false
		for x in range(o.x,o.x+size.x):
			if not clear_cell(Vector2i(x,y)):return false
	return true

func zone(o:Vector2i,size:Vector2i) -> Rect2i:
	return Rect2i(o-Vector2i(3,3),size+Vector2i(6,6))

## Naturally clear home rectangle plus a clear standing column at x-1.
func find_site(size:Vector2i,avoid:Array) -> Vector2i:
	for oy in range(2,REGIONS.SIZE.y-size.y-2):
		for ox in range(3,REGIONS.SIZE.x-size.x-2):
			var o:=Vector2i(ox,oy)
			var z:=zone(o,size)
			if z.has_point(Vector2i(PARK)):continue
			var hit:=false
			for r in avoid:
				if z.intersects(r):
					hit=true
					break
			if not hit and site_ok(o,size):return o
	expect(false,"found a naturally clear %s home site"%size)
	return Vector2i(-1,-1)

func stand(o:Vector2i) -> Vector2:
	return Vector2(o.x-0.5,o.y+0.5)

## Fixture: teleport A (direct write) and deliver the real snapshot.
func pose(at:Vector2) -> void:
	var person:Dictionary=w.state.players[A]
	person.x=at.x
	person.y=at.y
	s._send_snapshot(1)

func inv() -> Dictionary:
	var out:={}
	for k in w.state.players[A].inventory:
		if int(w.state.players[A].inventory[k])!=0:out[str(k)]=int(w.state.players[A].inventory[k])
	return out

func minus(a:Dictionary,b:Dictionary) -> Dictionary:
	var out:=a.duplicate()
	for k in b:
		out[k]=int(out.get(k,0))-int(b[k])
		if int(out[k])==0:out.erase(k)
	return out

func has_receipt(n:String) -> bool:
	return w.state.players[A].receipts.has("blueprint:"+n)

func built_at(o:Vector2i) -> bool:
	for y in 2:
		for x in 2:
			var g=w.state.ground.get(World.key(o+Vector2i(x,y)))
			if not (g is Dictionary and g.get("type")=="floor" and g.get("owner")==A):return false
	var bench=w.state.objects.get(World.key(o+Vector2i(1,0)))
	return bench is Dictionary and bench.get("type")=="bench" and bench.get("owner")==A

func normalized(raw) -> Dictionary:
	var r:=Design.validate(raw,World.BUILD,World.NAMES)
	return r.blueprint if r.get("ok")==true else {"<invalid>":true}

func stage_files() -> Array:
	var out:=[]
	for f in DirAccess.get_files_at(dir):
		if f.contains(".stage-"):out.append(f)
	return out

func world_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(w.save_path) if FileAccess.file_exists(w.save_path) else PackedByteArray()

func bytes_of(path:String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func write_text(path:String,text:String) -> bool:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:return false
	f.store_string(text)
	f.close()
	return true

func disk_entries(path:String) -> Array:
	var loaded:=Library.load_library(path,World.BUILD,World.NAMES)
	return loaded.entries if loaded.get("ok")==true else [{"<unreadable>":str(loaded.get("reason"))}]

func entry_id(e) -> String:
	return str(e.get("id","")) if e is Dictionary else ""

func lower_hex(v,length:int) -> bool:
	if not v is String or v.length()!=length:return false
	for ch in v:
		if not "0123456789abcdef".contains(ch):return false
	return true

func setup_world() -> void:
	w=World.new()
	w.save_path=dir+"/world.json"
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	# Explicit fixture stock, not normal-play balances.
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":200,"fiber":300}
	uclock=FakeClock.new()
	w.undo_clock_utc=Callable(uclock,"now_utc")
	w.undo_clock_ticks=Callable(uclock,"now_ticks")
	src=find_site(Vector2i(3,2),[])
	var avoid:Array=[zone(src,Vector2i(3,2))]
	for i in 6:
		var o:=find_site(Vector2i(2,2),avoid)
		sites.append(o)
		avoid.append(zone(o,Vector2i(2,2)))
	if src.x>=0:
		# Fixture layout at src: A's 2x2 floors, A's bench on (1,0), A's automatic
		# roof on (0,1), and B's floor at (2,0) for the foreign-capture check.
		for y in 2:
			for x in 2:w.state.ground[World.key(src+Vector2i(x,y))]={"type":"floor","owner":A,"items":{}}
		w.state.objects[World.key(src+Vector2i(1,0))]={"type":"bench","owner":A,"items":{}}
		w.state.roofs[World.key(src+Vector2i(0,1))]={"type":"roof","owner":A,"auto":true,"items":{}}
		w.state.ground[World.key(src+Vector2i(2,0))]={"type":"floor","owner":B,"items":{}}
	expect(w.save(),"baseline isolated world saved")
	bclock=Ticks.new()
	s=HostSession.new()
	root.add_child(s)
	s.set("blueprint_clock",Callable(bclock,"now"))
	s.world=w
	s._attach_registered(1,A)
	own=A.sha256_text().left(16)
	expect(s.own_id==own,"host snapshot delivered with the public own_id")
	s.watch_path=pending_path(lib,SCOPE)

func make_controller(library:String,scope:String):
	serial+=1
	var c=Controller.new()
	c.name="BlueprintController%d"%serial
	root.add_child(c)
	var watch:=pending_path(library,scope)
	c.connect("applied",func(result):applied_events.append({"result":result,"pending_on_disk":FileAccess.file_exists(watch)}))
	c.connect("feedback",func(message,ok):feedbacks.append([message,ok]))
	c.call("setup",s,library,scope)
	live.append(c)
	return c

func kill(c) -> void:
	if not is_instance_valid(c):return
	c.call("dispose")
	live.erase(c)
	c.free()

func connections_to(c:Object) -> int:
	var n:=0
	for sig in ["blueprint_quoted","blueprint_applied","changed","disconnected_world"]:
		for conn in s.get_signal_connection_list(sig):
			var cb:Callable=conn.callable
			if cb.get_object()==c:n+=1
	return n

func capture_source(c,label:String) -> bool:
	expect(c.call("begin_capture")==true,label+": begin_capture accepted")
	var r=c.call("capture_area",Rect2i(src,Vector2i(2,2)),label)
	var good:bool=r is Dictionary and r.get("ok")==true
	expect(good,label+": own 2x2 capture ok: "+str(r))
	return good

## choose -> move -> pin -> real quote; returns the authoritative World quote.
func placed_quote(c,o:Vector2i,label:String) -> Dictionary:
	pose(stand(o))
	var list:Array=c.entries
	if list.is_empty():
		expect(false,label+": library has an entry to choose")
		return {}
	expect(c.call("choose",entry_id(list[0]))==true,label+": choose accepted")
	c.call("move_origin",o)
	tick()
	c.call("pin_origin",o)
	await settle()
	var direct:Dictionary=w.quote_blueprint(A,c.draft,o,int(c.turns))
	var q:Dictionary=c.quote
	expect(direct.get("ok")==true,label+": fixture site quotes ok in World: "+str(direct.get("message")))
	expect(q.get("ok")==true and q.get("hash")==direct.get("hash"),label+": controller holds the authoritative quote")
	return direct

# ------------------------------------------------------------------- tests --

func test_contract() -> bool:
	if not ResourceLoader.exists(CONTROLLER_PATH):
		expect(false,"blueprint_controller.gd exists at "+CONTROLLER_PATH)
		return false
	Controller=load(CONTROLLER_PATH) as Script
	expect(Controller!=null and Controller.can_instantiate(),"controller script loads and instantiates")
	if Controller==null or not Controller.can_instantiate():return false
	var probe=Controller.new()
	var ok:bool=probe is Node
	expect(ok,"controller extends Node")
	if not ok:return false
	var props:={}
	for p in probe.get_property_list():props[str(p.name)]=true
	for p in STATE_PROPS:
		if not props.has(p):
			expect(false,"controller exposes public state '%s'"%p)
			ok=false
	var sigs:={}
	for sig in probe.get_signal_list():sigs[str(sig.name)]=(sig.args as Array).size()
	for pair in [["changed",0],["feedback",2],["applied",1]]:
		if int(sigs.get(pair[0],-1))!=int(pair[1]):
			expect(false,"signal %s has %d args (got %d)"%[pair[0],pair[1],int(sigs.get(pair[0],-1))])
			ok=false
	var found:={}
	for m in Controller.get_script_method_list():found[str(m.name)]=(m.args as Array).size()
	for m in METHODS:
		if int(found.get(m,-1))!=int(METHODS[m]):
			expect(false,"controller.%s has %d params (got %d; -1 = missing)"%[m,int(METHODS[m]),int(found.get(m,-1))])
			ok=false
	probe.free()
	if ok:expect(true,"controller public API complete")
	return ok

func test_library() -> void:
	var c=make_controller(lib,SCOPE)
	expect(c.mode=="idle" and (c.entries as Array).is_empty() and str(c.library_error)=="","missing library loads empty and idle")
	expect(not FileAccess.file_exists(lib) and not FileAccess.file_exists(pending_path(lib,SCOPE)),"setup writes neither library nor pending")
	# Same session twice: no duplicate connections; dispose unbinds.
	var conns:=connections_to(c)
	expect(conns>=2,"setup binds the Session signals (%d)"%conns)
	c.call("setup",s,lib,SCOPE)
	expect(connections_to(c)==conns,"setup with the same session does not connect twice")
	if src.x<0:
		expect(false,"library test needs the source site")
		return
	pose(stand(src))
	# Own capture: auto roof omitted, nothing written yet.
	expect(c.call("begin_capture")==true and c.mode=="capture","begin_capture enters capture mode")
	var r=c.call("capture_area",Rect2i(src,Vector2i(2,2)),"小屋")
	expect(r is Dictionary and r.get("ok")==true,"own 2x2 capture ok: "+str(r))
	var cap=c.captured
	expect(c.mode=="idle","capture returns to idle")
	expect(cap is Dictionary and int(cap.get("width",0))==2 and int(cap.get("height",0))==2 and (cap.get("pieces",[]) as Array).size()==5,
		"captured 4 floors + bench (auto roof excluded): "+str(cap))
	expect(int(c.auto_roofs_omitted)==1,"one automatic roof reported as omitted")
	expect(normalized(cap)==cap,"captured design is already normalized")
	expect(not var_to_str(cap).contains(own) and not var_to_str(cap).contains("tok-"),"captured design carries no owner/token")
	expect(not FileAccess.file_exists(lib),"capture alone writes nothing to the library")
	# Foreign / empty / oversize captures are refused.
	var cases:={"foreign floor in area":Rect2i(src,Vector2i(3,2)),"only foreign":Rect2i(src+Vector2i(2,0),Vector2i.ONE),
		"empty area":Rect2i(sites[0],Vector2i(2,2)),"17 wide":Rect2i(src,Vector2i(17,1))}
	for label in cases:
		c.call("begin_capture")
		var bad=c.call("capture_area",cases[label],"混合")
		expect(bad is Dictionary and bad.get("ok")==false and str(bad.get("reason",bad.get("message",""))).length()>0,"capture refused: %s"%label)
		var now=c.captured
		expect(not (now is Dictionary and int(now.get("width",0))==3),"%s: foreign layout never becomes captured"%label)
	c.call("cancel")
	# Save / rename / delete on actual disk.
	if not capture_source(c,"save source"):return
	for bad_name in ["   ","藍".repeat(33),"a\nb"]:
		var res=c.call("save_capture",bad_name)
		expect(res is Dictionary and res.get("ok")==false and str(res.get("reason","")).length()>0,"invalid name %s refused with a reason"%bad_name.c_escape())
		expect(not FileAccess.file_exists(lib),"invalid name writes nothing")
	var saved=c.call("save_capture","我的小屋")
	expect(saved is Dictionary and saved.get("ok")==true,"save_capture ok: "+str(saved))
	var disk:=disk_entries(lib)
	expect(disk.size()==1 and (c.entries as Array).size()==1,"one entry on disk and in memory")
	if disk.size()!=1:return
	var id0:=entry_id(disk[0])
	expect(lower_hex(id0,32),"entry ID is 32 lower-case hex")
	expect(str(disk[0].design.name)=="我的小屋" and entry_id(c.entries[0])==id0,"disk and memory agree on ID and name")
	expect(stage_files().is_empty(),"no staged temp files left after save")
	var before:=bytes_of(lib)
	for bad_name in ["","藍".repeat(33)]:
		var res=c.call("rename_entry",id0,bad_name)
		expect(res is Dictionary and res.get("ok")==false and str(res.get("reason","")).length()>0,"rename to invalid name refused")
		expect(bytes_of(lib)==before,"refused rename leaves the file byte-identical")
	var ghost=c.call("rename_entry","f".repeat(32),"幽靈")
	expect(ghost is Dictionary and ghost.get("ok")==false and bytes_of(lib)==before,"rename of unknown ID refused, file unchanged")
	var ren=c.call("rename_entry",id0,"改名小屋")
	disk=disk_entries(lib)
	expect(ren is Dictionary and ren.get("ok")==true and disk.size()==1 and entry_id(disk[0])==id0 and str(disk[0].design.name)=="改名小屋",
		"rename keeps the ID and rewrites the name on disk")
	expect(str((c.entries[0] as Dictionary).design.name)=="改名小屋","rename updates memory")
	# Capacity: 12 entries, then an explicit refusal (no silent overwrite).
	for i in 11:
		if not capture_source(c,"fill %d"%i):return
		var res=c.call("save_capture","第%d份"%(i+2))
		expect(res is Dictionary and res.get("ok")==true,"entry %d saved"%(i+2))
	disk=disk_entries(lib)
	expect(disk.size()==12 and (c.entries as Array).size()==12,"library holds 12 entries")
	var ids:={}
	for e in disk:ids[entry_id(e)]=true
	expect(ids.size()==12,"all 12 IDs distinct")
	before=bytes_of(lib)
	if capture_source(c,"overflow"):
		var over=c.call("save_capture","第13份")
		expect(over is Dictionary and over.get("ok")==false and str(over.get("reason","")).length()>0,"13th entry refused with a reason")
		expect(bytes_of(lib)==before and (c.entries as Array).size()==12,"refused 13th leaves disk and memory unchanged")
	var gone=c.call("delete_entry","e".repeat(32))
	expect(gone is Dictionary and gone.get("ok")==false and bytes_of(lib)==before,"delete of unknown ID refused, file unchanged")
	var last:=entry_id(disk[11])
	var del=c.call("delete_entry",last)
	disk=disk_entries(lib)
	expect(del is Dictionary and del.get("ok")==true and disk.size()==11 and (c.entries as Array).size()==11,"delete removes one entry on disk and in memory")
	var still:=false
	for e in disk:still=still or entry_id(e)==last
	expect(not still and entry_id(disk[0])==id0,"deleted ID gone, first entry kept")
	# Reload from disk in a fresh controller.
	kill(c)
	var again=make_controller(lib,SCOPE)
	expect((again.entries as Array).size()==11 and entry_id(again.entries[0])==id0 and str(again.library_error)=="","fresh controller reloads the saved library")
	kill(again)
	expect(stage_files().is_empty(),"no staged temp files left after library operations")

func test_corrupt_library() -> void:
	var world0:=world_bytes()
	var bad:=dir+"/corrupt-library.json"
	var garbage:="{\"version\":1,\"entries\":[{\"id\":"
	expect(write_text(bad,garbage),"fixture: corrupt library written")
	var original:=bytes_of(bad)
	var c=make_controller(bad,SCOPE2)
	expect(str(c.library_error)!="","corrupt library reports library_error")
	expect((c.entries as Array).is_empty(),"corrupt library exposes no entries")
	if src.x>=0:
		pose(stand(src))
		c.call("begin_capture")
		c.call("capture_area",Rect2i(src,Vector2i(2,2)),"不會保存")
		var res=c.call("save_capture","不會保存")
		expect(res is Dictionary and res.get("ok")==false,"save into a corrupt library refused")
	var ren=c.call("rename_entry","a".repeat(32),"x")
	var del=c.call("delete_entry","a".repeat(32))
	expect(ren is Dictionary and ren.get("ok")==false and del is Dictionary and del.get("ok")==false,"rename/delete refused while locked")
	expect(bytes_of(bad)==original,"corrupt library preserved byte-for-byte")
	kill(c)
	expect(bytes_of(bad)==original,"dispose keeps the corrupt library")
	expect(world_bytes()==world0,"library corruption never touches the World save")
	# Oversized library (> 2 MiB) is preserved too.
	var huge:=dir+"/huge-library.json"
	expect(write_text(huge,"{\"version\":1,\"entries\":[]}"+" ".repeat(Library.MAX_BYTES)),"fixture: oversized library written")
	var huge0:=bytes_of(huge)
	var h=make_controller(huge,SCOPE2)
	expect(str(h.library_error)!="","oversized library reports library_error")
	kill(h)
	expect(bytes_of(huge)==huge0,"oversized library preserved")
	# Save failure into a missing directory: explicit, nothing created.
	var missing:=dir+"/missing-subdir/library.json"
	var m=make_controller(missing,SCOPE2)
	if src.x>=0 and capture_source(m,"missing dir"):
		var res=m.call("save_capture","不會保存")
		expect(res is Dictionary and res.get("ok")==false and str(res.get("reason","")).length()>0,"save into a missing directory fails with a reason")
		expect((m.entries as Array).is_empty(),"failed save leaves memory unchanged")
	kill(m)
	expect(not DirAccess.dir_exists_absolute(dir+"/missing-subdir"),"failed save never created the missing directory")
	DirAccess.remove_absolute(bad)
	DirAccess.remove_absolute(huge)

func test_placement() -> void:
	var o:Vector2i=sites[5]
	var c=make_controller(lib,SCOPE)
	var q0:=(s.quotes as Array).size()
	expect(int(c.call("request_quote"))<=0 and (s.quotes as Array).size()==q0,"request_quote outside placing sends nothing")
	expect(c.call("choose","f".repeat(32))==false and c.mode=="idle","choose of unknown ID refused")
	pose(stand(o))
	var list:Array=c.entries
	if list.is_empty():
		expect(false,"placement needs a library entry")
		return
	expect(c.call("choose",entry_id(list[0]))==true,"choose accepted")
	expect(c.mode=="placing" and int(c.turns)==0 and c.locked==false and (c.quote as Dictionary).is_empty(),"choose: placing, unrotated, unlocked, no quote")
	expect(c.draft==normalized((list[0] as Dictionary).design),"draft is the normalized saved design")
	var player:=stand(o)
	expect(Vector2(c.origin).distance_to(player)<=4.0,"initial origin near the player (%s vs %s)"%[c.origin,player])
	c.call("move_origin",o)
	expect(c.origin==o,"move_origin updates an unlocked origin")
	await settle(6)
	expect((s.quotes as Array).size()==q0,"no automatic per-frame quotes while placing")
	# Pin -> real quote.
	tick()
	c.call("pin_origin",o)
	expect(c.locked==true and c.quote_waiting==true,"pin locks and waits for a quote")
	expect((s.quotes as Array).size()==q0+1,"pin sends exactly one quote")
	if (s.quotes as Array).size()==q0+1:
		var sent:Dictionary=s.quotes[-1]
		expect(sent.origin==o and sent.turns is int and int(sent.turns)==0 and normalized(sent.raw)==c.draft,"quote carries the draft, origin and turns 0")
	await settle()
	var direct:Dictionary=w.quote_blueprint(A,c.draft,o,0)
	var h0:=str(direct.get("hash",""))
	expect(direct.get("ok")==true,"fixture: placement site quotes ok: "+str(direct.get("message")))
	expect(c.quote_waiting==false and c.quote.get("ok")==true and c.quote.get("hash")==h0,"authoritative quote stored")
	c.call("move_origin",o+Vector2i(1,0))
	expect(c.origin==o,"move_origin ignored while locked")
	# Out-of-order: two requests, then a late (injected) reply to the older one.
	tick()
	var id1:=int(c.call("request_quote"))
	expect(int(c.call("request_quote"))==id1,"duplicate pending quote requests coalesce")
	c.call("reposition")
	tick()
	c.call("pin_origin",o)
	var id2:=int(c.call("request_quote"))
	expect(id1>0 and id2>0 and id1!=id2,"each request_quote gets its own ID")
	await settle()
	expect(c.quote.get("hash")==h0,"newest reply kept")
	var forged:={"ok":true,"message":"injected","hash":"ab".repeat(32),"cost":{"wood":1},"pieces":5,"problems":[]}
	s.blueprint_quoted.emit(id1,forged)  # injected late out-of-order reply
	s.blueprint_quoted.emit(id2+777,forged)  # injected reply to an ID never sent
	await settle(1)
	expect(c.quote.get("hash")==h0,"late / unknown quote replies ignored")
	# Rotate before the reply arrives: the stale reply is ignored, no auto submit.
	var submits0:=(s.submits as Array).size()
	tick()
	c.call("request_quote")
	c.call("rotate")
	expect(int(c.turns)==1 and (c.quote as Dictionary).get("hash","")!=h0,"rotate advances turns and clears the quote")
	await settle()
	expect(str((c.quote as Dictionary).get("hash",""))!=h0,"reply for the unrotated draft ignored after rotate")
	expect(c.call("confirm")==false and (s.submits as Array).size()==submits0,"cannot confirm without a current quote")
	for i in 3:c.call("rotate")
	expect(int(c.turns)==0,"four rotations wrap to 0")
	# reposition unlocks and clears.
	c.call("reposition")
	expect(c.locked==false and (c.quote as Dictionary).get("ok")!=true,"reposition unlocks and clears the quote")
	c.call("move_origin",o)
	tick()
	c.call("pin_origin",o)
	await settle()
	expect(c.quote.get("hash")==h0,"re-pinned quote matches")
	# Travel (fixture) while a quote is in flight: preview/quote cancelled, reply ignored.
	var person:Dictionary=w.state.players[A]
	tick()
	c.call("request_quote")
	person.region=LANYANG
	person.travel_epoch=int(person.get("travel_epoch",0))+1
	var spot:Vector2=REGIONS.spawn(LANYANG)
	person.x=spot.x
	person.y=spot.y
	s._send_snapshot(1)
	await settle()
	expect(c.mode=="idle" and (c.quote as Dictionary).get("ok")!=true and c.locked==false,"region change cancels preview and quote")
	expect((s.submits as Array).size()==submits0,"region change never submits")
	person.region=HOME
	person.travel_epoch=int(person.travel_epoch)+1
	pose(stand(o))
	# Epoch-only change on the same region also invalidates.
	expect(c.call("choose",entry_id(list[0]))==true,"choose after returning home")
	c.call("move_origin",o)
	tick()
	c.call("pin_origin",o)
	await settle()
	expect(c.quote.get("ok")==true,"quote ok after returning home")
	person.travel_epoch=int(person.travel_epoch)+1
	s._send_snapshot(1)
	await settle(1)
	expect((c.quote as Dictionary).get("ok")!=true,"epoch change invalidates the quote")
	# Ordinary cancel.
	c.call("choose",entry_id(list[0]))
	expect(c.call("cancel")==true and c.mode=="idle","cancel ends placing")
	expect((s.submits as Array).size()==submits0 and not FileAccess.file_exists(pending_path(lib,SCOPE)),"placement never wrote a pending record or submitted")
	kill(c)

func test_confirm_success() -> void:
	var o:Vector2i=sites[0]
	var c=make_controller(lib,SCOPE)
	var direct:=await placed_quote(c,o,"confirm")
	var path:=pending_path(lib,SCOPE)
	# Confirm is refused while a quote is in flight.
	tick()
	c.call("request_quote")
	var n0:=(s.submits as Array).size()
	expect(c.call("confirm")==false and (s.submits as Array).size()==n0,"confirm refused while quote_waiting")
	await settle()
	expect(c.quote.get("hash")==direct.get("hash"),"requested quote settles")
	expect(not FileAccess.file_exists(path),"no pending file before confirm")
	var inv0:=inv()
	applied_events.clear()
	tick()
	expect(c.call("confirm")==true,"confirm accepted with a current ok quote")
	expect(c.mode=="submitting","confirm enters submitting")
	expect((s.submits as Array).size()==n0+1,"exactly one submission")
	if (s.submits as Array).size()!=n0+1:return
	var rec:Dictionary=s.submits[-1]
	var n:=str(rec.nonce)
	expect(rec.pending_exists,"pending file existed on disk before submit_blueprint")
	expect(lower_hex(n,32),"nonce is 32 lower hex")
	var parsed=JSON.parse_string(str(rec.pending_text))
	expect(parsed is Dictionary,"pending file is a JSON object")
	if parsed is Dictionary:
		var keys:Array=parsed.keys()
		keys.sort()
		var want:Array=PENDING_KEYS.duplicate()
		want.sort()
		expect(keys==want,"pending file has exactly the fixed fields: "+str(keys))
		expect(int(parsed.get("version",0))==1 and parsed.get("scope")==SCOPE and parsed.get("actor")==own and parsed.get("nonce")==n,"pending version/scope/actor/nonce")
		expect(parsed.get("hash")==direct.get("hash") and int(parsed.get("turns",-1))==0 and parsed.get("region")==HOME,"pending hash/turns/region")
		var po=parsed.get("origin")
		expect(po is Dictionary and int(po.get("x",-99999))==o.x and int(po.get("y",-99999))==o.y,"pending origin x/y")
		expect(normalized(parsed.get("design"))==c.draft,"pending design is the draft")
		expect(int(parsed.get("epoch",-1))==int(w.state.players[A].get("travel_epoch",0)),"pending epoch is the current epoch")
	expect(not str(rec.pending_text).contains("tok-") and not str(rec.pending_text).contains("SECRET"),"pending file holds no token")
	expect(str(rec.pending_text).to_utf8_buffer().size()<=262144,"pending file within 256 KiB")
	expect(rec.origin==o and rec.turns is int and int(rec.turns)==0 and rec.hash==direct.get("hash") and normalized(rec.raw)==c.draft,"submission uses the quoted intent")
	expect(stage_files().is_empty(),"pending written atomically (no staged leftovers)")
	expect(c.call("begin_capture")==false and c.call("choose",entry_id(c.entries[0]))==false and c.call("cancel")==false,"submitting blocks capture/choose/cancel")
	await settle()
	expect(applied_events.size()==1 and (applied_events[0].result as Dictionary).get("ok")==true,"applied emitted once with ok")
	if applied_events.size()==1:expect(applied_events[0].pending_on_disk==false,"pending deleted before applied was emitted")
	expect(c.mode=="idle" and (c.pending as Dictionary).is_empty() and not FileAccess.file_exists(path),"success: idle, pending cleared on disk and in memory")
	expect(built_at(o) and has_receipt(n),"real World built the blueprint with a receipt")
	expect(inv()==minus(inv0,direct.get("cost",{})),"charged exactly the quoted cost")
	await settle(4)
	expect((s.submits as Array).size()==n0+1 and c.call("confirm")==false,"no further submission")
	kill(c)

func test_requote() -> void:
	var o:Vector2i=sites[1]
	pose(stand(o))
	var c=make_controller(lib,SCOPE)
	var direct0:=await placed_quote(c,o,"requote")
	uclock.utc=-1.0  # fixture: undo clock unavailable -> undoable false -> new hash
	var direct1:Dictionary=w.quote_blueprint(A,c.draft,o,0)
	expect(direct1.get("ok")==true and direct1.get("hash")!=direct0.get("hash"),"fixture: World quote changed but still ok")
	var n0:=(s.submits as Array).size()
	var inv0:=inv()
	applied_events.clear()
	tick()
	expect(c.call("confirm")==true,"confirm with the old quote accepted locally")
	await settle()
	expect((s.submits as Array).size()==n0+1,"one submission")
	var n1:=str(s.submits[-1].nonce) if (s.submits as Array).size()>n0 else ""
	expect(not has_receipt(n1) and not built_at(o) and inv()==inv0,"requote: nothing built or charged")
	expect(c.quote.get("hash")==direct1.get("hash") and c.quote.get("ok")==true,"controller shows the new requoted price")
	expect(c.mode=="placing","requote returns to placing for an explicit confirm")
	expect(c.quote.get("requote")==true,"new quote is labelled for explicit price reconfirmation")
	expect(applied_events.is_empty(),"requote never emits applied")
	expect((c.pending as Dictionary).is_empty() and not FileAccess.file_exists(pending_path(lib,SCOPE)),"requote ends the old pending record")
	await settle(6)
	expect((s.submits as Array).size()==n0+1,"new price never auto-accepted")
	tick()
	expect(c.call("confirm")==true,"explicit confirm of the new price")
	await settle()
	expect((s.submits as Array).size()==n0+2,"second, explicit submission")
	var n2:=str(s.submits[-1].nonce) if (s.submits as Array).size()==n0+2 else ""
	expect(n2!=n1 and lower_hex(n2,32),"explicit reconfirm uses a new nonce")
	if (s.submits as Array).size()==n0+2:expect(s.submits[-1].hash==direct1.get("hash"),"reconfirm submits the new hash")
	expect(built_at(o) and has_receipt(n2) and inv()==minus(inv0,direct1.get("cost",{})),"built once at the new price")
	expect(c.mode=="idle" and not FileAccess.file_exists(pending_path(lib,SCOPE)),"cleanup after reconfirm")
	uclock.utc=1800000000.0
	kill(c)

func test_save_failure() -> void:
	var o:Vector2i=sites[5]
	var c=make_controller(lib,SCOPE)
	await placed_quote(c,o,"save failure")
	var path:=pending_path(lib,SCOPE)
	# Fixture: a directory occupies the pending path, so the atomic write fails.
	expect(DirAccess.make_dir_absolute(path)==OK,"fixture: directory blocks the pending path")
	var n0:=(s.submits as Array).size()
	var world0:=world_bytes()
	var state0:=var_to_str(w.state)
	feedbacks.clear()
	tick()
	expect(c.call("confirm")==false,"confirm fails when the pending record cannot be saved")
	await settle()
	expect((s.submits as Array).size()==n0,"save failure: nothing sent")
	expect(c.mode!="submitting" and c.mode!="unknown" and (c.pending as Dictionary).is_empty(),"save failure: no in-flight state")
	expect(world_bytes()==world0 and var_to_str(w.state)==state0,"save failure: World untouched")
	var told:=false
	for f in feedbacks:told=told or f[1]==false
	expect(told or str(c.status)!="","save failure is reported to the player")
	expect(DirAccess.remove_absolute(path)==OK,"fixture directory removed")
	expect(stage_files().is_empty(),"failed pending write left no staged file")
	c.call("cancel")
	kill(c)

func test_unknown_and_scopes() -> void:
	var o:Vector2i=sites[2]
	var path:=pending_path(lib,SCOPE)
	var c=make_controller(lib,SCOPE)
	var direct:=await placed_quote(c,o,"unknown")
	var inv0:=inv()
	s.drop_submits=1  # fixture: lost transport, the World never sees it
	var n0:=(s.submits as Array).size()
	tick()
	expect(c.call("confirm")==true,"confirm accepted")
	await settle()
	expect(c.mode=="submitting" and FileAccess.file_exists(path),"no reply: still submitting with the record on disk")
	if (s.submits as Array).size()!=n0+1:
		expect(false,"unknown: one submission recorded")
		return
	var first:Dictionary=s.submits[-1]
	s.disconnected_world.emit()  # fixture: simulated disconnect
	await settle(1)
	expect(c.mode=="unknown","disconnect while submitting -> unknown")
	expect(c.call("cancel")==false and FileAccess.file_exists(path),"unknown cannot be cancelled; record kept")
	expect(c.call("begin_capture")==false and c.call("choose",entry_id(c.entries[0]))==false,"unknown blocks new work")
	expect(not has_receipt(str(first.nonce)) and inv()==inv0,"fixture: World never saw the dropped submission")
	kill(c)
	expect(FileAccess.file_exists(path),"dispose keeps the pending record")
	var record:=bytes_of(path)
	# Another island (scope) never resends this record.
	var other=make_controller(lib,SCOPE2)
	expect((other.pending as Dictionary).is_empty() and other.mode=="idle","other scope sees no pending")
	tick()
	expect(other.call("retry_pending")==false and (s.submits as Array).size()==n0+1,"other scope never resends")
	kill(other)
	expect(bytes_of(path)==record,"other scope leaves the record untouched")
	# A record for a different actor is never resent by this player.
	var parsed=JSON.parse_string(record.get_string_from_utf8())
	if parsed is Dictionary:
		parsed.actor="0123456789abcdef"
		expect(write_text(path,JSON.stringify(parsed)),"fixture: record rewritten with another actor")
		var foreign0:=bytes_of(path)
		var f=make_controller(lib,SCOPE)
		tick()
		expect(f.call("retry_pending")==false and (s.submits as Array).size()==n0+1,"other actor's record never resent")
		kill(f)
		expect(bytes_of(path)==foreign0,"other actor's record preserved")
		var restore:=FileAccess.open(path,FileAccess.WRITE)
		restore.store_buffer(record)
		restore.close()
	else:expect(false,"pending record parses for the actor fixture")
	# Restart in the same scope: same nonce / design / context resent once.
	var r=make_controller(lib,SCOPE)
	expect(r.mode=="unknown" and str((r.pending as Dictionary).get("nonce",""))==str(first.nonce),"restart restores the unknown record")
	applied_events.clear()
	tick()
	expect(r.call("retry_pending")==true,"retry accepted")
	expect((s.submits as Array).size()==n0+2,"retry sends exactly once")
	if (s.submits as Array).size()==n0+2:
		var again:Dictionary=s.submits[-1]
		expect(again.nonce==first.nonce and again.hash==first.hash and again.origin==first.origin and int(again.turns)==int(first.turns),"retry: same nonce/hash/origin/turns")
		expect(again.region==first.region and int(again.epoch)==int(first.epoch),"retry: same region/epoch context")
		expect(normalized(again.raw)==normalized(first.raw),"retry: same design")
	await settle()
	expect(r.mode=="idle" and not FileAccess.file_exists(path) and applied_events.size()==1,"retry success cleans up")
	expect(built_at(o) and inv()==minus(inv0,direct.get("cost",{})),"built and charged once")
	tick()
	expect(r.call("retry_pending")==false and (s.submits as Array).size()==n0+2,"nothing left to retry")
	kill(r)

func test_lost_reply_restart() -> void:
	var o:Vector2i=sites[3]
	var path:=pending_path(lib,SCOPE)
	var c=make_controller(lib,SCOPE)
	var direct:=await placed_quote(c,o,"lost reply")
	var inv0:=inv()
	s.drop_results=1  # fixture: World commits, the reply is lost
	var n0:=(s.submits as Array).size()
	tick()
	expect(c.call("confirm")==true,"confirm accepted")
	await settle()
	if (s.submits as Array).size()!=n0+1:
		expect(false,"lost reply: one submission")
		return
	var n:=str(s.submits[-1].nonce)
	expect(has_receipt(n) and built_at(o),"fixture: World committed before the reply was lost")
	var charged:=inv()
	expect(charged==minus(inv0,direct.get("cost",{})),"charged once by the commit")
	s.disconnected_world.emit()  # fixture: simulated disconnect
	await settle(1)
	expect(c.mode=="unknown" and FileAccess.file_exists(path),"lost reply -> unknown with the record kept")
	kill(c)
	var r=make_controller(lib,SCOPE)
	expect(r.mode=="unknown" and str((r.pending as Dictionary).get("nonce",""))==n,"restart restores the same nonce")
	applied_events.clear()
	tick()
	expect(r.call("retry_pending")==true,"retry accepted")
	await settle()
	expect((s.submits as Array).size()==n0+2 and str(s.submits[-1].nonce)==n,"retry reuses the nonce")
	expect(applied_events.size()==1 and (applied_events[0].result as Dictionary).get("ok")==true,"stored receipt confirms success")
	expect(inv()==charged,"receipt replay never charges again")
	expect(r.mode=="idle" and not FileAccess.file_exists(path),"cleanup after receipt")
	kill(r)

func test_delete_failure() -> void:
	var o:Vector2i=sites[4]
	var path:=pending_path(lib,SCOPE)
	var c=make_controller(lib,SCOPE)
	var direct:=await placed_quote(c,o,"delete failure")
	var inv0:=inv()
	var saved:=[PackedByteArray()]
	# Fixture: once the record is written, swap it for a non-empty directory so the
	# controller's delete after success cannot remove it.
	s.on_submit=func():
		saved[0]=bytes_of(path)
		DirAccess.remove_absolute(path)
		DirAccess.make_dir_absolute(path)
		write_text(path+"/blocker.txt","x")
	var n0:=(s.submits as Array).size()
	applied_events.clear()
	tick()
	expect(c.call("confirm")==true,"confirm accepted")
	await settle()
	s.on_submit=Callable()
	if (s.submits as Array).size()!=n0+1:
		expect(false,"delete failure: one submission")
		return
	var n:=str(s.submits[-1].nonce)
	expect(has_receipt(n) and built_at(o),"World committed")
	expect(applied_events.is_empty(),"applied not emitted while the record cannot be deleted")
	expect(not (c.pending as Dictionary).is_empty() and c.mode!="idle","record kept in memory when deletion fails")
	expect(c.call("begin_capture")==false and c.call("choose",entry_id(c.entries[0]))==false,"undeletable record blocks new work")
	# Restore the original record bytes (fixture) and retry the same nonce.
	DirAccess.remove_absolute(path+"/blocker.txt")
	DirAccess.remove_absolute(path)
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_buffer(saved[0])
	f.close()
	tick()
	expect(c.call("retry_pending")==true,"retry after deletion failure accepted")
	await settle()
	expect((s.submits as Array).size()==n0+2 and str(s.submits[-1].nonce)==n,"retry reuses the nonce")
	expect(applied_events.size()==1 and c.mode=="idle" and not FileAccess.file_exists(path),"retry receipt cleans up")
	expect(inv()==minus(inv0,direct.get("cost",{})),"charged exactly once")
	kill(c)

func test_corrupt_pending() -> void:
	var o:Vector2i=sites[5]
	var path:=pending_path(lib,SCOPE)
	for label in ["garbage","oversized"]:
		var text:="{\"version\":1,\"scope\":" if label=="garbage" else "{\"version\":1}"+" ".repeat(262144+16)
		expect(write_text(path,text),"fixture: %s pending written"%label)
		var original:=bytes_of(path)
		var c=make_controller(lib,SCOPE)
		expect(str(c.pending_error)!="" and str(c.status)!="","%s pending: error and status reported"%label)
		var n0:=(s.submits as Array).size()
		pose(stand(o))
		if c.call("choose",entry_id(c.entries[0]))==true:
			c.call("move_origin",o)
			tick()
			c.call("pin_origin",o)
			await settle()
			tick()
			expect(c.call("confirm")==false,"%s pending: confirm refused"%label)
		else:expect(true,"%s pending: choose refused"%label)
		tick()
		expect(c.call("retry_pending")==false,"%s pending: never resent"%label)
		await settle()
		expect((s.submits as Array).size()==n0,"%s pending: nothing sent"%label)
		expect(bytes_of(path)==original,"%s pending preserved byte-for-byte"%label)
		c.dispose()
		expect(bytes_of(path)==original,"%s pending kept after dispose"%label)
		DirAccess.remove_absolute(path)
		c.setup(s,lib,SCOPE)
		expect(c.pending_error.is_empty() and c.call("begin_capture")==true,"external recovery then same-scope reconnect clears obsolete error")
		c.cancel()
		kill(c)

func test_foreign_results() -> void:
	var c=make_controller(lib,SCOPE)
	applied_events.clear()
	var state0:=var_to_str(w.state)
	s.blueprint_applied.emit("f".repeat(32),{"ok":true,"message":"injected","blueprint":true,"pieces":5,"hash":"ab".repeat(32)})  # injected foreign result
	await settle(1)
	expect(applied_events.is_empty() and c.mode=="idle","foreign nonce result ignored")
	expect(var_to_str(w.state)==state0,"foreign result changes nothing")
	kill(c)

## Deterministic deadline fixture. Real Session/World; quote replies are deferred,
## and one successful apply reply is deliberately dropped by HostSession.
func test_timeouts() -> void:
	var o:=find_site(Vector2i(2,2),[])
	pose(stand(o))
	var c=make_controller(lib,SCOPE)
	c.clock=Callable(bclock,"now")
	expect(c.choose(entry_id(c.entries[0])),"timeout fixture chooses persisted design")
	tick()
	c.pin_origin(o)
	var sent_at:=bclock.ms
	bclock.ms=sent_at+7999
	c._process(0.0)
	expect(c.quote_waiting,"quote still waits just before deadline")
	bclock.ms=sent_at+8000
	c._process(0.0)
	expect(not c.quote_waiting and c.quote.is_empty() and not c.confirm(),"quote timeout cannot authorize construction")
	await settle()
	var direct:Dictionary=w.quote_blueprint(A,c.draft,o,0)
	expect(c.quote.get("ok")==true and c.quote.get("hash")==direct.get("hash"),"late correlated quote remains usable when intent is unchanged")
	tick()
	var old_id:int=c.request_quote()
	bclock.ms+=8000
	c._process(0.0)
	var new_id:int=c.request_quote()
	expect(new_id>0 and new_id!=old_id,"explicit retry after timeout starts a new quote request")
	s.blueprint_quoted.emit(old_id,{"ok":true,"message":"injected late old quote","hash":"f".repeat(64),"cost":{"wood":1}})
	expect(c.quote.is_empty() and c.quote_waiting,"superseded late quote cannot replace new in-flight request")
	await settle()
	expect(c.quote.get("hash")==direct.get("hash"),"new request receives real authoritative quote")
	var inv0:=inv()
	var n0:=(s.submits as Array).size()
	s.drop_results=1
	tick()
	expect(c.confirm(),"confirm sends after valid quote")
	await settle()
	var nonce:=str(s.submits[-1].nonce)
	var path:=pending_path(lib,SCOPE)
	var bytes:=FileAccess.get_file_as_bytes(path)
	expect(c.mode=="submitting" and has_receipt(nonce) and built_at(o),"World committed while injected successful reply was lost")
	var submitted_at:=bclock.ms
	bclock.ms=submitted_at+14999
	c._process(0.0)
	expect(c.mode=="submitting","submission waits until deadline")
	bclock.ms=submitted_at+15000
	c._process(0.0)
	expect(c.mode=="unknown" and c.busy() and not c.cancel(),"deadline keeps unknown submission blocking new work")
	expect(FileAccess.get_file_as_bytes(path)==bytes,"timeout preserves exact pending bytes")
	await settle(6)
	expect((s.submits as Array).size()==n0+1,"timeout never automatically resubmits")
	expect(c.retry_pending(),"player explicitly retries unknown operation")
	await settle()
	expect((s.submits as Array).size()==n0+2 and str(s.submits[-1].nonce)==nonce,"explicit retry uses original nonce")
	expect(c.mode=="idle" and not FileAccess.file_exists(path),"stored receipt clears pending after timed-out result")
	expect(inv()==minus(inv0,direct.cost) and built_at(o),"lost result and timeout charged materials exactly once")
	kill(c)

func cleanup() -> void:
	for c in live.duplicate():kill(c)
	if s!=null:
		s.free()
		s=null
	remove_tree(dir)
	expect(not DirAccess.dir_exists_absolute(dir),"isolated test directory removed")

func remove_tree(path:String) -> void:
	if not path.begins_with("user://test-blueprint-client-"):return
	for sub in DirAccess.get_directories_at(path):remove_tree(path+"/"+sub)
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path+"/"+f)
	DirAccess.remove_absolute(path)
