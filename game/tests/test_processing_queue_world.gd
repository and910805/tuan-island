extends SceneTree
## T036 manual sawmill / charcoal-kiln ten-job processing queues through the
## REAL World.act / World.step / save / load_world path.
## Contract: docs/processing-queue-contract.json (device.processing uses the
## CookingQueue canonical shape active/waiting/ready).
##
## Fixture label: LABEL. Random frame splits come from RandomNumberGenerator
## seeded with SEED; job ids are server-random and compared for shape/order only.
##
## FIXTURE, NOT NORMAL PLAY (disclosed):
##  * inventories (wood/stone) are seeded directly with STOCK;
##  * stations, chests and conveyors are written directly into the object layer
##    with the same shape a real build produces (no kits are spent);
##  * players are teleported next to stations before every action;
##  * world time only moves through explicit World.step(dt, active) calls;
##  * some stored queue/legacy records are rewritten to emulate historical
##    saves whose cost / yield / duration differ from today's recipe;
##  * the save path is temporarily pointed at a missing directory to force
##    save failures.
## Every world saves into one random directory under the OS TEMP folder that is
## deleted afterwards; real player saves are never touched.
const World=preload("res://scripts/world.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const Schema=preload("res://scripts/save_schema.gd")
const REGIONS=preload("res://scripts/regions.gd")

const SEED:=20261114
const LABEL:="processing-queue-world/seed-20261114"
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const CAP:=1000000000
const TOL:=0.000001
const STOCK:={"wood":200,"stone":60}
const RECIPE_OF:={"sawmill":"plank","charcoal_kiln":"charcoal"}

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

var checks:=0
var failures:=0
var serial:=0
var dir:=""

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_environment("TMPDIR")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("processing-queue-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt existing test directory")
		print("PROCESSING_QUEUE_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated TEMP directory created")
	print("PROCESSING_QUEUE_WORLD fixture=%s dir=%s"%[LABEL,dir])
	test_original_recipes()
	for kind in ["sawmill","charcoal_kiln"]:test_ten_job_fifo(kind)
	test_cancel_caps_owner()
	test_legacy_conversion()
	test_auto_rejections()
	test_auto_toggle_blocked_then_allowed()
	test_logistics_preserved()
	test_regional_and_pause()
	test_dedup()
	test_save_reload()
	test_seed_catalog_processing()
	test_loom_processing()
	test_wool_tent_journey()
	test_cotton_sofa_journey()
	test_save_failure_rollback()
	test_move_remove_blocked()
	test_schema_owner_validation()
	_remove_tree(dir)
	expect(not DirAccess.dir_exists_absolute(dir),"isolated TEMP directory removed")
	print("PROCESSING_QUEUE_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func _remove_tree(path:String) -> void:
	var root_path:=dir.replace("\\","/").simplify_path()
	var target:=path.replace("\\","/").simplify_path()
	if not root_path.is_absolute_path() or (target!=root_path and not target.begins_with(root_path+"/")):
		expect(false,"cleanup target escaped owned temporary directory")
		return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):_remove_tree(path.path_join(sub))
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

# ---------------------------------------------------------------- fixtures --

func new_world():
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	for t in [A,B]:w.state.players[t].inventory=STOCK.duplicate()
	serial+=1
	w.save_path=dir.path_join("world-%d.json"%serial)
	var clock:=FakeClock.new()
	w.undo_clock_utc=Callable(clock,"now_utc")
	w.undo_clock_ticks=Callable(clock,"now_ticks")
	return w

func lay(w,region:String) -> Dictionary:
	return w.state.objects if region==HOME else w.state.regions[region].objects

func site_clear(w,a:Vector2i,size:Vector2i) -> bool:
	for y in range(a.y,a.y+size.y):
		for x in range(a.x,a.x+size.x):
			var c:=Vector2i(x,y)
			var k:=World.key(c)
			if not w.is_land(c) or w.water(c) or w.protected(c):return false
			for field in ["objects","ground","roofs","crops","forest"]:
				if w.state[field].has(k):return false
			var had:bool=w.state.removed.has(k)
			w.state.removed[k]=true
			var b:bool=w.blocked(c)
			if not had:w.state.removed.erase(k)
			if b:return false
	return true

## Legal empty 3x1 row (two-cell margin) at least `min_dist` from every `avoid`.
func find_site(w,region:String,avoid:Array) -> Vector2i:
	var size:=Vector2i(3,1)
	w.switch_region(region)
	var found:=Vector2i(-1,-1)
	for oy in range(3,57):
		for ox in range(3,76):
			var far:=true
			for a in avoid:
				if Vector2(ox,oy).distance_to(Vector2(a))<7.0:far=false;break
			if far and site_clear(w,Vector2i(ox-2,oy-2),size+Vector2i(4,4)):
				found=Vector2i(ox,oy);break
		if found.x>=0:break
	if found.x>=0:
		for y in range(found.y-2,found.y+size.y+2):
			for x in range(found.x-2,found.x+size.x+2):
				var c:=Vector2i(x,y)
				if w.resource(c)!="":w.state.removed[World.key(c)]=true
	w.switch_region(HOME)
	expect(found.x>=0,"found a legal empty site in "+region)
	return found

var _used_sites:Array=[]

## Station in the shape `build` produces (items/input_wood/auto_enabled); fixture.
func place(w,kind:String,owner:String=A,region:String=HOME) -> Vector2i:
	var avoid:Array=[Vector2i(World.SPAWN)]+_used_sites
	var o:=find_site(w,region,avoid)
	_used_sites.append(o)
	lay(w,region)[World.key(o)]={"type":kind,"owner":owner,"items":{},"input_wood":0,"auto_enabled":false}
	return o

func fresh_sites() -> void:
	_used_sites=[]

func near(p:Vector2i) -> Vector2:
	return Vector2(p)+Vector2(0.5,1.6)

func pose(w,token:String,at:Vector2) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else World.SPAWN
		person.x=spot.x;person.y=spot.y

func leak_free(value,label:String) -> void:
	var text:=var_to_str(value)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks tokens")

func do(w,token:String,action:String,p:Vector2i,extra:String="",rid:String="") -> Dictionary:
	pose(w,token,near(p))
	serial+=1
	if rid=="":rid="req-%d"%serial
	var r:Dictionary=w.act(token,rid,action,p,extra)
	leak_free(r,"result %s"%action)
	return r

func must(w,token:String,action:String,p:Vector2i,extra:String,label:String,rid:String="") -> Dictionary:
	var r:=do(w,token,action,p,extra,rid)
	expect(r.get("ok",false)==true,label+": "+str(r.get("message","")))
	return r

## Rejected: ok=false with a reason and the whole world state unchanged.
func refuse(w,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	pose(w,token,near(p))
	var snap:=var_to_str(w.state)
	serial+=1
	var r:Dictionary=w.act(token,"refuse-%d"%serial,action,p,extra)
	leak_free(r,label)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": rejected with a reason, got "+str(r))
	expect(var_to_str(w.state)==snap,label+": world state unchanged")
	return r

func dev(w,p:Vector2i,region:String=HOME) -> Dictionary:
	return lay(w,region).get(World.key(p),{})

func q(w,p:Vector2i,region:String=HOME) -> Dictionary:
	var c=dev(w,p,region).get("processing")
	return c if c is Dictionary else {}

func ids_of(list) -> Array:
	var out:=[]
	if list is Array:
		for entry in list:out.append(str(entry.get("id","")))
	return out

func all_ids(c:Dictionary) -> Array:
	if c.is_empty():return []
	var out:=[]
	if not (c.active as Dictionary).is_empty():out.append(str(c.active.id))
	return out+ids_of(c.waiting)+ids_of(c.ready)

func total(c:Dictionary) -> int:
	return all_ids(c).size()

func ready_n(c:Dictionary) -> int:
	return 0 if c.is_empty() else (c.ready as Array).size()

func empty_queue(d:Dictionary) -> bool:
	return not d.has("processing") or total(q_of(d))==0

func q_of(d:Dictionary) -> Dictionary:
	var c=d.get("processing")
	return c if c is Dictionary else {}

func hex32(value) -> bool:
	return value is String and World._is_lower_hex(value,32)

func wood(w,token:String=A) -> int:
	return int(w.state.players[token].inventory.get("wood",0))

func held(w,token:String,item:String) -> int:
	return int(w.state.players[token].inventory.get(item,0))

func close(a:float,b:float) -> bool:
	return absf(a-b)<=TOL

func queue_ids(w,p:Vector2i,kind:String,n:int,label:String,token:String=A) -> Array:
	var out:=[]
	for i in n:
		var before:=all_ids(q(w,p))
		must(w,token,"queue_processing",p,kind,"%s %d"%[label,i])
		var added:=all_ids(q(w,p)).filter(func(id):return not before.has(id))
		expect(added.size()==1 and hex32(added[0] if added.size()==1 else null),"%s %d: exactly one new 32-hex job"%[label,i])
		if added.size()==1:out.append(added[0])
	return out

## Snapshot of the player progress that processing must never touch.
func progress(w,token:String) -> String:
	var person:Dictionary=w.state.players[token]
	return var_to_str([person.get("cooked",0),person.get("collection",{}),person.get("harvests",0),person.get("builds",0)])

# ------------------------------------------------------------------- tests --

func test_original_recipes() -> void:
	var probe=World.new()
	expect(int(probe.state.version)==int(Schema.VERSION),"fresh world follows SaveSchema.VERSION dynamically")
	var plank:Dictionary=World.INDUSTRY.PROCESS.get("plank",{})
	var charcoal:Dictionary=World.INDUSTRY.PROCESS.get("charcoal",{})
	expect(plank.get("station")=="sawmill" and plank.get("ingredients")=={"wood":4} and int(plank.get("yield",0))==2 and close(float(plank.get("time",0)),12.0),"plank recipe unchanged: sawmill, 4 wood -> 2, 12 s")
	expect(charcoal.get("station")=="charcoal_kiln" and charcoal.get("ingredients")=={"wood":4} and int(charcoal.get("yield",0))==2 and close(float(charcoal.get("time",0)),16.0),"charcoal recipe unchanged: kiln, 4 wood -> 2, 16 s")
	expect(Queue.CAPACITY==10,"shared queue capacity is ten")

func test_ten_job_fifo(kind:String) -> void:
	fresh_sites()
	var tag:="fifo %s"%kind
	var recipe:String=RECIPE_OF[kind]
	var other:String=RECIPE_OF["charcoal_kiln" if kind=="sawmill" else "sawmill"]
	var duration:=float(World.INDUSTRY.PROCESS[recipe].time)
	var w=new_world()
	var s:=place(w,kind)
	refuse(w,A,"queue_processing",s,other,tag+": other station's recipe refused")
	refuse(w,A,"queue_processing",s,"soup",tag+": unknown recipe refused")
	refuse(w,B,"queue_processing",s,recipe,tag+": non-owner cannot enqueue")
	var wood0:=wood(w)
	var prog0:=progress(w,A)
	var ids:=queue_ids(w,s,recipe,Queue.CAPACITY,tag+": enqueue")
	expect(ids.size()==Queue.CAPACITY,tag+": ten jobs enqueued")
	expect(wood(w)==wood0-4*Queue.CAPACITY,tag+": each job charged exactly 4 wood from the backpack")
	var c:=q(w,s)
	expect(not c.is_empty() and str(c.active.id)==ids[0] and ids_of(c.waiting)==ids.slice(1),tag+": FIFO active + nine waiting")
	expect(not dev(w,s).has("job") and dev(w,s).get("auto_enabled",false)==false,tag+": no legacy job, auto off")
	var snapshot_ok:=true
	for e in [c.active]+(c.waiting as Array):
		if e.get("owner")!=A or e.get("kind")!=recipe or e.get("ingredients")!={"wood":4} or int(e.get("yield",0))!=2 or not close(float(e.get("duration",0)),duration):snapshot_ok=false
	expect(snapshot_ok,tag+": every record snapshots owner, 4 wood, yield 2, %ds"%int(duration))
	refuse(w,A,"queue_processing",s,recipe,tag+": eleventh job refused (full)")
	# Historical record: stored cost/yield/duration differ from today's recipe.
	var second:Dictionary=c.waiting[0]
	second.duration=5.0
	second["yield"]=7
	second.ingredients={"wood":9}
	var t0:=float(w.state.time)
	var expected:=[]
	var t:=t0
	for i in Queue.CAPACITY:
		t+=5.0 if i==1 else duration
		expected.append(t)
	var rng:=RandomNumberGenerator.new()
	rng.seed=SEED+(1 if kind=="sawmill" else 2)
	var frames:=0
	var counts_ok:=true
	while float(w.state.time)<=float(expected.back())+1.0 and frames<2000:
		expect(w.step(rng.randf_range(0.5,6.0),true),tag+": frame committed")
		frames+=1
		var due:=0
		for e in expected:
			if float(e)<=float(w.state.time):due+=1
		var cc:=q(w,s)
		if ready_n(cc)!=due or total(cc)!=Queue.CAPACITY:counts_ok=false
	print("FIXTURE %s: %s advanced %.3fs of world time in %d World.step frames"%[LABEL,tag,float(w.state.time)-t0,frames])
	expect(counts_ok,tag+": ready count equals jobs due after every frame, total stays 10")
	c=q(w,s)
	expect(ids_of(c.ready)==ids,tag+": ready in exact FIFO order")
	var times_ok:=ready_n(c)==Queue.CAPACITY
	if times_ok:
		for i in Queue.CAPACITY:
			if not close(float(c.ready[i].completed),float(expected[i])):times_ok=false
	expect(times_ok,tag+": completion times follow stored durations (historical 5 s job included)")
	expect(not dev(w,s).has("job") and (dev(w,s).items as Dictionary).values().all(func(v):return int(v)==0),tag+": completion never writes job or automatic output buffer")
	refuse(w,A,"queue_processing",s,recipe,tag+": full with ten ready jobs")
	refuse(w,B,"claim_processing",s,"",tag+": non-owner cannot claim")
	for i in Queue.CAPACITY:
		var amount:=7 if i==1 else 2
		var before:=held(w,A,recipe)
		var rid:="claim-%s-%d"%[kind,i]
		var r:=must(w,A,"claim_processing",s,"",tag+": claim %d"%i,rid)
		expect(held(w,A,recipe)==before+amount,tag+": claim %d credits stored yield %d once"%[i,amount])
		expect(not all_ids(q(w,s)).has(ids[i]) and all_ids(q(w,s))==ids.slice(i+1),tag+": claim %d took the oldest ready job"%i)
		var replay:=do(w,A,"claim_processing",s,"",rid)
		expect(replay==r and held(w,A,recipe)==before+amount,tag+": replayed claim %d returns receipt, no second credit"%i)
		if i==0:
			must(w,A,"queue_processing",s,recipe,tag+": slot freed by claim accepts a new job")
			var added:=all_ids(q(w,s)).filter(func(id):return not ids.has(id))
			expect(total(q(w,s))==Queue.CAPACITY,tag+": back to ten after refill")
			if added.size()==1:
				must(w,A,"cancel_processing_job",s,added[0],tag+": cancel refill job")
	expect(progress(w,A)==prog0,tag+": claims never touch cooked counter / collections / other progress")
	expect(wood(w)==wood0-4*Queue.CAPACITY,tag+": refill+cancel left the wood balance unchanged")
	refuse(w,A,"claim_processing",s,"",tag+": nothing left to claim")
	expect(dev(w,s).has("processing") and total(q(w,s))==0,tag+": empty queue remains on the device")

func test_cancel_caps_owner() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	var j:=queue_ids(w,s,"plank",3,"cancel: enqueue")
	if j.size()!=3:return
	refuse(w,B,"cancel_processing_job",s,j[1],"cancel: non-owner cannot cancel waiting")
	refuse(w,B,"cancel_processing",s,"","cancel: non-owner cannot cancel active")
	refuse(w,A,"cancel_processing_job",s,"not-a-job-id","cancel: malformed id")
	refuse(w,A,"cancel_processing_job",s,"0".repeat(32),"cancel: unknown id")
	refuse(w,A,"cancel_processing_job",s,"","cancel: empty id")
	if j[1].to_upper()!=j[1]:refuse(w,A,"cancel_processing_job",s,j[1].to_upper(),"cancel: id must be exact lowercase")
	# Historical stored ingredients are what gets refunded.
	for entry in q(w,s).waiting:
		if entry.id==j[2]:entry.ingredients={"wood":9}
	var w0:=wood(w)
	must(w,A,"cancel_processing_job",s,j[2],"cancel: exact waiting id")
	expect(wood(w)==w0+9,"cancel: exact stored ingredients refunded (9 wood)")
	expect(all_ids(q(w,s))==[j[0],j[1]],"cancel: only that job removed, order kept")
	refuse(w,A,"cancel_processing_job",s,j[2],"cancel: no double refund")
	w.state.players[A].inventory.wood=CAP-1
	refuse(w,A,"cancel_processing_job",s,j[1],"cancel: refund over item cap refused")
	w.state.players[A].inventory.wood=100
	must(w,A,"cancel_processing_job",s,j[0],"cancel: exact active id")
	expect(wood(w)==104 and str(q(w,s).active.get("id",""))==j[1],"cancel: active refunded and next promoted")
	expect(w.step(13.0,true),"cancel: promoted job completes")
	expect(ids_of(q(w,s).ready)==[j[1]],"cancel: job ready")
	refuse(w,A,"cancel_processing_job",s,j[1],"cancel: ready job never cancellable")
	refuse(w,A,"cancel_processing",s,"","cancel: no active job to cancel")
	w.state.players[A].inventory["plank"]=CAP-1
	refuse(w,A,"claim_processing",s,"","cap: claim over output cap refused")
	expect(ready_n(q(w,s))==1,"cap: ready job preserved")
	w.state.players[A].inventory["plank"]=CAP-2
	must(w,A,"claim_processing",s,"","cap: claim exactly to cap")
	expect(held(w,A,"plank")==CAP,"cap: reached exact cap")
	# Owner-only: B's own device with A as visitor.
	var bs:=place(w,"charcoal_kiln",B)
	refuse(w,A,"queue_processing",bs,"charcoal","owner: visitor cannot enqueue on B's kiln")
	must(w,B,"queue_processing",bs,"charcoal","owner: B enqueues on own kiln")
	var bid:=str(q(w,bs).active.get("id",""))
	refuse(w,A,"cancel_processing_job",bs,bid,"owner: visitor cannot cancel B's job by id")
	refuse(w,A,"toggle_auto_processing",bs,"","owner: visitor cannot toggle")

func test_legacy_conversion() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	must(w,A,"start_processing",s,"plank","legacy: start_processing on untouched station")
	var d:=dev(w,s)
	expect(d.has("job") and not d.has("processing"),"legacy: untouched station keeps the single job path")
	refuse(w,A,"start_processing",s,"plank","legacy: busy single job refuses second start")
	d.job.ingredients={"wood":6}
	d.job["yield"]=3
	var deadline:=float(d.job.ready)
	refuse(w,A,"queue_processing",s,"charcoal","legacy: wrong recipe, no conversion")
	refuse(w,B,"queue_processing",s,"plank","legacy: non-owner, no conversion")
	w.state.players[A].inventory.wood=3
	refuse(w,A,"queue_processing",s,"plank","legacy: missing wood, no conversion")
	expect(dev(w,s).has("job") and not dev(w,s).has("processing") and dev(w,s).job.ingredients=={"wood":6},"legacy: job intact after every rejection")
	w.state.players[A].inventory.wood=50
	must(w,A,"queue_processing",s,"plank","legacy: queue_processing converts")
	d=dev(w,s)
	var c:=q(w,s)
	expect(not d.has("job") and d.has("processing"),"legacy: job removed only by a successful enqueue")
	expect(wood(w)==46,"legacy: only the new job is charged; imported job not recharged")
	var imported:Dictionary=c.get("active",{})
	expect(hex32(imported.get("id")) and imported.get("owner")==A and imported.get("ingredients")=={"wood":6} and int(imported.get("yield",0))==3,"legacy: imported with id, owner and historical snapshot")
	expect(close(float(imported.get("finish",-1)),deadline),"legacy: original deadline preserved")
	expect((c.waiting as Array).size()==1,"legacy: new job waits behind imported one")
	must(w,A,"start_processing",s,"plank","legacy: start_processing on queue device enqueues")
	expect(total(q(w,s))==3 and not dev(w,s).has("job"),"legacy: three queued, still no job field")
	var w1:=wood(w)
	must(w,A,"cancel_processing",s,"","legacy: cancel_processing cancels the active (imported) job")
	expect(wood(w)==w1+6 and not all_ids(q(w,s)).has(str(imported.get("id",""))),"legacy: imported refund is its stored 6 wood")
	# Already completed legacy job imports into ready and claims its stored yield.
	var s2:=place(w,"charcoal_kiln")
	must(w,A,"start_processing",s2,"charcoal","legacy2: start")
	dev(w,s2).job["yield"]=5
	expect(w.step(17.0,true),"legacy2: legacy job finishes by time")
	expect(dev(w,s2).has("job") and not dev(w,s2).has("processing"),"legacy2: ticks never convert legacy stations")
	var w2:=wood(w)
	must(w,A,"queue_processing",s2,"charcoal","legacy2: convert completed job")
	expect(ready_n(q(w,s2))==1 and wood(w)==w2-4,"legacy2: completed legacy job in ready, charged once")
	var ch:=held(w,A,"charcoal")
	must(w,A,"claim_processing",s2,"","legacy2: claim imported")
	expect(held(w,A,"charcoal")==ch+5,"legacy2: stored yield 5 claimed")
	# Untouched legacy cancel keeps old behaviour (no processing field created).
	var s3:=place(w,"sawmill")
	must(w,A,"start_processing",s3,"plank","legacy3: start")
	var w3:=wood(w)
	must(w,A,"cancel_processing",s3,"","legacy3: legacy cancel")
	expect(wood(w)==w3+4 and not dev(w,s3).has("job") and not dev(w,s3).has("processing"),"legacy3: refunded, station stays untouched")
	refuse(w,A,"cancel_processing_job",s3,"0".repeat(32),"legacy3: exact-id cancel on untouched station refused")

func test_auto_rejections() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	must(w,A,"feed_processing",s,"","auto: feed 4 wood into buffer")
	must(w,A,"toggle_auto_processing",s,"","auto: enable")
	refuse(w,A,"queue_processing",s,"plank","auto: auto_enabled rejects queue_processing")
	refuse(w,A,"start_processing",s,"plank","auto: auto_enabled rejects start_processing")
	expect(w.step(2.5,true),"auto: logistics tick")
	expect(dev(w,s).get("job",{}).get("auto",false)==true,"auto: automatic job started from buffer")
	must(w,A,"toggle_auto_processing",s,"","auto: disable while auto job runs")
	refuse(w,A,"queue_processing",s,"plank","auto: running automatic job rejects queue_processing")
	refuse(w,A,"claim_processing",s,"","auto: automatic job is not manually claimable")
	expect(not dev(w,s).has("processing"),"auto: no processing field created by rejections")
	for i in 8:w.step(2.0,true)
	expect(not dev(w,s).has("job") and int(dev(w,s).items.get("plank",0))==2,"auto: automatic output entered its buffer")
	var p0:=held(w,A,"plank")
	must(w,A,"collect_processing_output",s,"","auto: collect output buffer")
	expect(held(w,A,"plank")==p0+2,"auto: collected 2 planks")
	must(w,A,"queue_processing",s,"plank","auto: manual queue allowed once automation is idle and off")

func test_auto_toggle_blocked_then_allowed() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"charcoal_kiln")
	must(w,A,"feed_processing",s,"","toggle: feed buffer before queueing")
	var j:=queue_ids(w,s,"charcoal",2,"toggle: enqueue")
	expect(int(dev(w,s).input_wood)==4,"toggle: manual queue uses backpack only, buffer untouched")
	refuse(w,A,"toggle_auto_processing",s,"","toggle: blocked while active+waiting")
	expect(w.step(33.0,true),"toggle: both jobs complete")
	expect(ready_n(q(w,s))==2 and int(dev(w,s).input_wood)==4 and not dev(w,s).has("job"),"toggle: ready, buffer still untouched, no auto job")
	refuse(w,A,"toggle_auto_processing",s,"","toggle: blocked while ready unclaimed")
	must(w,A,"claim_processing",s,"","toggle: claim 1")
	refuse(w,A,"toggle_auto_processing",s,"","toggle: still blocked with one ready")
	must(w,A,"claim_processing",s,"","toggle: claim 2")
	must(w,A,"toggle_auto_processing",s,"","toggle: empty queue allows enabling automatic mode")
	var d:=dev(w,s)
	expect(d.get("auto_enabled",false)==true and empty_queue(d) and int(d.input_wood)==4 and (d.items as Dictionary).values().all(func(v):return int(v)==0),"toggle: auto on, queue empty/removed, buffer preserved")
	must(w,A,"toggle_auto_processing",s,"","toggle: disable again")
	expect(dev(w,s).get("auto_enabled",true)==false and int(dev(w,s).input_wood)==4,"toggle: back off, buffer preserved")
	# Cancel path empties the queue too.
	var k:=queue_ids(w,s,"charcoal",1,"toggle: enqueue after toggle back")
	refuse(w,A,"toggle_auto_processing",s,"","toggle: blocked by new active job")
	if k.size()==1:must(w,A,"cancel_processing_job",s,k[0],"toggle: cancel the only job")
	must(w,A,"toggle_auto_processing",s,"","toggle: allowed after cancel emptied queue")
	must(w,A,"toggle_auto_processing",s,"","toggle: off")
	expect(j.size()==2,"toggle: fixture ids")

func test_logistics_preserved() -> void:
	fresh_sites()
	var w=new_world()
	# Automatic chain: private chest -> conveyor (east) -> sawmill.
	var o:=place(w,"sawmill")
	var objects:Dictionary=w.state.objects
	objects.erase(World.key(o))
	var chest:=o
	var belt:=o+Vector2i(1,0)
	var mill:=o+Vector2i(2,0)
	objects[World.key(chest)]={"type":"private_chest","owner":A,"items":{"wood":8}}
	objects[World.key(belt)]={"type":"conveyor","owner":A,"dir":1,"enabled":true,"filter":"wood","items":{}}
	objects[World.key(mill)]={"type":"sawmill","owner":A,"items":{},"input_wood":0,"auto_enabled":false}
	must(w,A,"toggle_auto_processing",mill,"","logistics: enable automatic sawmill")
	# Manual chain: private chest -> conveyor -> manual queue kiln.
	var o2:=place(w,"charcoal_kiln")
	objects.erase(World.key(o2))
	var kiln:=o2+Vector2i(2,0)
	objects[World.key(o2)]={"type":"private_chest","owner":A,"items":{"wood":6}}
	objects[World.key(o2+Vector2i(1,0))]={"type":"conveyor","owner":A,"dir":1,"enabled":true,"filter":"wood","items":{}}
	objects[World.key(kiln)]={"type":"charcoal_kiln","owner":A,"items":{},"input_wood":0,"auto_enabled":false}
	var ids:=queue_ids(w,kiln,"charcoal",2,"logistics: manual kiln enqueue")
	var wood0:=wood(w)
	var t0:=float(w.state.time)
	var saw_auto_job:=false
	var kiln_clean:=true
	for i in 30:
		expect(w.step(2.0,true),"logistics: tick %d"%i)
		if dev(w,mill).get("job",{}).get("auto",false):saw_auto_job=true
		var kd:=dev(w,kiln)
		if kd.has("job") or kd.get("auto_enabled",false) or not (kd.items as Dictionary).values().all(func(v):return int(v)==0):kiln_clean=false
	print("FIXTURE %s: logistics advanced %.1fs of world time in 30 World.step frames"%[LABEL,float(w.state.time)-t0])
	var md:=dev(w,mill)
	expect(saw_auto_job,"logistics: conveyor-fed automatic job ran")
	expect(int(md.items.get("plank",0))==4 and int(md.input_wood)==0 and int(dev(w,chest).items.get("wood",0))==0,"logistics: 8 wood -> 4 planks in the automatic output buffer")
	expect(empty_queue(md),"logistics: automatic work never creates manual queue records")
	expect(held(w,A,"plank")==0,"logistics: automatic output never auto-enters the backpack")
	var kd:=dev(w,kiln)
	expect(kiln_clean,"logistics: manual queue station never starts automatic jobs nor fills output buffer")
	expect(int(kd.input_wood)==6,"logistics: conveyor wood buffered on manual station, never consumed by the queue")
	expect(ids_of(q(w,kiln).ready)==ids and total(q(w,kiln))==2,"logistics: exactly the two manual jobs ready, no duplicates")
	expect(wood(w)==wood0 and held(w,A,"charcoal")==0,"logistics: manual outputs only arrive on claim")
	must(w,A,"claim_processing",kiln,"","logistics: claim manual 1")
	must(w,A,"claim_processing",kiln,"","logistics: claim manual 2")
	expect(held(w,A,"charcoal")==4,"logistics: claimed 4 charcoal")
	must(w,A,"unload_processing_input",kiln,"","logistics: unload buffered wood")
	expect(wood(w)==wood0+6 and int(dev(w,kiln).input_wood)==0,"logistics: buffered wood returned")
	must(w,A,"collect_processing_output",mill,"","logistics: collect automatic output")
	expect(held(w,A,"plank")==4,"logistics: collected 4 planks")

func test_regional_and_pause() -> void:
	fresh_sites()
	var w=new_world()
	var home:=place(w,"sawmill")
	var far:=place(w,"charcoal_kiln",A,LANYANG)
	expect(lay(w,LANYANG).has(World.key(far)) and not w.state.objects.has(World.key(far)),"region: kiln only in lanyang layers")
	refuse(w,A,"queue_processing",far,"charcoal","region: home player cannot reach lanyang kiln")
	w.state.players[A].region=LANYANG
	must(w,A,"queue_processing",far,"charcoal","region: queue in lanyang")
	w.state.players[A].region=HOME
	must(w,A,"queue_processing",home,"plank","region: queue at home")
	w.active_tokens.clear()
	var snap:=var_to_str(w.state)
	for i in 3:expect(w.step(10.0,false),"region: inactive step returns ok")
	expect(var_to_str(w.state)==snap,"region: empty world fully paused")
	print("FIXTURE %s: region advanced 17.0s with no tokens in either region"%LABEL)
	expect(w.step(17.0,true),"region: active world step with nobody present/online")
	expect(ready_n(q(w,far,LANYANG))==1,"region: lanyang queue progressed with owner away/offline")
	expect(ready_n(q(w,home))==1,"region: home queue progressed")
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),"region: completion saved")
	expect(ready_n(q(loaded,far,LANYANG))==1,"region: saved file holds regional completion")

func test_dedup() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	var r1:=must(w,A,"queue_processing",s,"plank","dedup: first","nonce-1")
	var r2:=do(w,A,"queue_processing",s,"plank","nonce-1")
	expect(r1==r2,"dedup: same nonce returns stored receipt")
	expect(total(q(w,s))==1 and wood(w)==196,"dedup: one job, charged once")
	var id:=str(q(w,s).active.id)
	var c1:=must(w,A,"cancel_processing_job",s,id,"dedup: cancel","nonce-2")
	var c2:=do(w,A,"cancel_processing_job",s,id,"nonce-2")
	expect(c1==c2 and wood(w)==200,"dedup: cancel replay refunds once")
	leak_free(w.state.players[A].receipts,"dedup: stored receipts")

func test_save_reload() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	var ids:=queue_ids(w,s,"plank",3,"save: enqueue")
	expect(w.step(13.0,true),"save: partial progress saved")
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	expect(parsed is Dictionary and int(parsed.get("version",0))==int(Schema.VERSION),"save: document at SaveSchema.VERSION")
	if parsed is Dictionary:
		var obj=parsed.objects.get(World.key(s),{})
		expect(obj.has("processing") and not obj.has("job"),"save: processing persisted, no job projection")
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),"save: reload passes real SaveSchema validation")
	loaded.add_player(A,"Alice")
	var c:=q(loaded,s)
	expect(ids_of(c.get("ready",[]))==[ids[0]] and str(c.get("active",{}).get("id",""))==ids[1] and ids_of(c.get("waiting",[]))==[ids[2]],"save: order survives reload")
	if not c.is_empty():expect(close(float(c.active.finish),float(q(w,s).active.finish)),"save: active deadline survives")
	expect(loaded.step(30.0,true),"save: reloaded world continues")
	for i in 3:must(loaded,A,"claim_processing",s,"","save: claim %d after reload"%i)
	expect(held(loaded,A,"plank")==6,"save: six planks claimed after reload")
	var again=World.new()
	expect(again.load_world(w.save_path) and total(q(again,s))==0,"save: emptied queue persisted")

func test_seed_catalog_processing() -> void:
	var world:World=new_world()
	var person:Dictionary=world.state.players[A]
	person.harvests=10
	person.inventory.merge({"plank":8,"copper_joint":2,"charcoal":24},true)
	var station:=find_site(world,HOME,[])
	if not must(world,A,"build",station,"seed_maker","Build the seed maker").ok:return
	var planned=JSON.parse_string(FileAccess.get_file_as_string("res://docs/crop-catalog-plan.json"))
	expect(planned is Dictionary and planned.size()==24 and World.CROPS.keys().all(func(id):return planned.has(id)) and World.CROPS.size()==planned.size(),"The live catalog matches all 24 planned crops")
	for id:String in World.CROPS:
		var crop:Dictionary=World.CROPS[id]
		var cost:=int(crop.yield)*int(crop.get("cycles",1))
		var seed:=id+"_seed"
		var previous:=held(world,A,seed)
		var fuel:=held(world,A,"charcoal")
		world.state.players[A].inventory[id]=cost-1
		refuse(world,A,"queue_processing",station,seed,id+": one produce short")
		world.state.players[A].inventory[id]=cost
		var job:=must(world,A,"queue_processing",station,seed,id+": enqueue")
		if not job.ok:return
		expect(held(world,A,id)==0 and held(world,A,"charcoal")==fuel-1,id+": charges full lifetime harvest and one charcoal")
		expect(world.step(World.SEED_MAKER.PROCESS_SECONDS+0.1,true),id+": finishes")
		if id=="mist_tea":
			var loaded:=World.new()
			if not expect_reload_seed(loaded,world.save_path):return
			world=loaded
		must(world,A,"claim_processing",station,"",id+": claim")
		expect(held(world,A,seed)==previous+1,id+": awards exactly one seed")
		refuse(world,A,"claim_processing",station,"",id+": cannot claim twice")

func test_loom_processing() -> void:
	var world:World=new_world()
	world.state.players[A].inventory.merge({"plank":8,"fiber":4,"copper_joint":1,"cotton":3,"wool":2},true)
	var station:=find_site(world,HOME,[])
	if not must(world,A,"build",station,"loom","Build the loom").ok:return
	must(world,A,"queue_processing",station,"cotton_cloth","Queue cotton")
	must(world,A,"queue_processing",station,"wool_cloth","Queue wool")
	expect(held(world,A,"cotton")==0 and held(world,A,"wool")==0,"Both recipes charge their stated materials")
	expect(world.step(120.1,true),"Both cloth jobs finish")
	var reopened:=World.new()
	if not expect_reload_seed(reopened,world.save_path):return
	refuse(reopened,B,"claim_processing",station,"","Visitors cannot take cloth")
	must(reopened,A,"claim_processing",station,"","Claim cotton cloth")
	must(reopened,A,"claim_processing",station,"","Claim wool cloth")
	expect(held(reopened,A,"cotton_cloth")==1 and held(reopened,A,"wool_cloth")==1,"The loom returns one of each cloth")
	refuse(reopened,A,"claim_processing",station,"","Cloth cannot be claimed again")

func test_wool_tent_journey()->void:
	var world:World=new_world()
	var person:Dictionary=world.state.players[A]
	world.state.picnic=true
	person.inventory.merge({"plank":14,"fiber":6,"copper_joint":1,"wheat":1},true)
	person["explored_regions"]={}
	for region in World.REGIONS.ALL.slice(1,15):person.explored_regions[region]=true
	var stove:=find_site(world,HOME,[])
	var loom:=find_site(world,HOME,[stove])
	var tent:=find_site(world,HOME,[stove,loom])
	var sheep:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	var collector:=World.LIVESTOCK.collector_cell("sheep")
	must(world,A,"build",stove,"stove","Build the feed stove")
	must(world,A,"cook",stove,"feed","Mix feed from wheat and fiber")
	expect(world.step(5.1,true),"Feed finishes cooking")
	must(world,A,"claim_cook",stove,"","Collect fresh feed")
	must(world,A,"build",collector,"chest","Install the sheep collector")
	for i in range(4):must(world,A,"livestock_feed",sheep,"sheep","Fill the sheep feeder")
	expect(world.step(8.0*World.LIVESTOCK.DAY,true),"Four sheep production intervals pass")
	expect(held(world,A,"wool")==0 and world.state.objects.get(World.key(collector),{}).get("items",{}).get("wool",0)==4,"Four wool are collected from sheep")
	for i in range(4):must(world,A,"withdraw",collector,"wool","Retrieve earned wool")
	must(world,A,"build",loom,"loom","Build the loom")
	for i in range(2):must(world,A,"queue_processing",loom,"wool_cloth","Weave the earned wool")
	expect(world.step(120.1,true),"Two cloth orders finish")
	var reopened:=World.new()
	if not expect_reload_seed(reopened,world.save_path):return
	for i in range(2):must(reopened,A,"claim_processing",loom,"","Collect the finished cloth")
	expect(held(reopened,A,"wool_cloth")==2,"Two pieces of cloth are ready for construction")
	must(reopened,A,"build",tent,"expedition_tent","Build a tent using the cloth")
	expect(held(reopened,A,"wool_cloth")==0 and reopened.state.objects.get(World.key(tent),{}).get("type")=="expedition_tent","The tent consumes precisely the earned cloth")

func test_cotton_sofa_journey()->void:
	var world:World=new_world()
	var person:Dictionary=world.state.players[A]
	person.inventory.merge({"plank":8,"fiber":4,"copper_joint":1},true)
	var field:=find_site(world,HOME,[])
	var loom:=find_site(world,HOME,[field])
	var sofa:=find_site(world,HOME,[field,loom])
	for index in range(3):
		must(world,A,"buy",Vector2i(43,29),"cotton","Buy cotton seed with starting coins")
		var plot:=field+Vector2i(index,0)
		must(world,A,"hoe",plot,"","Prepare field")
		must(world,A,"seed",plot,"cotton","Plant purchased seed")
		must(world,A,"water",plot,"","Water the cotton")
	expect(world.step(float(World.CROPS.cotton.time)+0.1,true),"Spring cotton matures")
	for index in range(3):
		must(world,A,"harvest",field+Vector2i(index,0),"","Harvest cotton")
	expect(held(world,A,"cotton")==6,"Three plants give enough cotton for two cloth")
	must(world,A,"build",loom,"loom","Build the loom")
	for index in range(2):
		must(world,A,"queue_processing",loom,"cotton_cloth","Queue harvested cotton")
	expect(world.step(120.1,true),"Both cloth orders finish")
	var reopened:=World.new()
	if not expect_reload_seed(reopened,world.save_path):return
	for index in range(2):
		must(reopened,A,"claim_processing",loom,"","Collect cotton cloth")
	refuse(reopened,A,"build",sofa,"sofa","The sofa still requires Aru’s story")
	reopened.state.players[A].stories.aru=4
	must(reopened,A,"build",sofa,"sofa","Build the unlocked cotton sofa")
	expect(held(reopened,A,"cotton_cloth")==0 and reopened.state.objects.get(World.key(sofa),{}).get("type")=="sofa","Place the sofa and spend both woven cloth")

func expect_reload_seed(world:World,path:String)->bool:
	var loaded:=world.load_world(path)
	expect(loaded,"Ready processing order survives primary save reload")
	return loaded

func broken_act(w,token:String,action:String,p:Vector2i,extra:String,rid:String,label:String) -> void:
	pose(w,token,near(p))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(token,rid,action,p,extra)
	expect(r.get("ok",true)==false and str(r.get("message","")).contains("保存失敗"),label+": save failure reported, got "+str(r))
	expect(var_to_str(w.state)==snap,label+": entire state rolled back")

func test_save_failure_rollback() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	var legacy:=place(w,"charcoal_kiln")
	var idle:=place(w,"sawmill")
	var ids:=queue_ids(w,s,"plank",2,"fail: enqueue")
	must(w,A,"start_processing",legacy,"charcoal","fail: legacy job")
	var good:String=w.save_path
	var bad:=dir.path_join("missing-"+Crypto.new().generate_random_bytes(4).hex_encode()).path_join("world.json")
	w.save_path=bad
	broken_act(w,A,"queue_processing",s,"plank","sf-enqueue","fail: enqueue")
	broken_act(w,A,"queue_processing",legacy,"charcoal","sf-convert","fail: legacy conversion")
	expect(dev(w,legacy).has("job") and not dev(w,legacy).has("processing"),"fail: no half conversion")
	broken_act(w,A,"cancel_processing_job",s,ids[1],"sf-cancel-id","fail: cancel by id")
	broken_act(w,A,"toggle_auto_processing",idle,"","sf-toggle","fail: toggle auto")
	var snap:=var_to_str(w.state)
	expect(w.step(13.0,true)==false,"fail: tick with completion reports save failure")
	expect(var_to_str(w.state)==snap,"fail: tick completion rolled back")
	w.save_path=good
	expect(w.step(13.0,true) and ready_n(q(w,s))==1,"fail: tick succeeds after recovery")
	w.save_path=bad
	broken_act(w,A,"claim_processing",s,"","sf-claim","fail: claim")
	w.save_path=good
	must(w,A,"queue_processing",s,"plank","fail: same enqueue nonce succeeds after recovery","sf-enqueue")
	must(w,A,"claim_processing",s,"","fail: same claim nonce succeeds after recovery","sf-claim")
	must(w,A,"cancel_processing_job",s,ids[1],"fail: same cancel nonce succeeds after recovery","sf-cancel-id")
	must(w,A,"queue_processing",legacy,"charcoal","fail: conversion succeeds after recovery","sf-convert")
	expect(not dev(w,legacy).has("job") and total(q(w,legacy))==2,"fail: conversion committed whole")

func test_move_remove_blocked() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	var dest:=World.key(s+Vector2i(1,0))
	must(w,A,"queue_processing",s,"plank","move: queue")
	refuse(w,A,"move_object",s,dest,"move: active blocks move")
	refuse(w,A,"remove",s,"","move: active blocks remove")
	expect(w.step(13.0,true),"move: job ready")
	refuse(w,A,"move_object",s,dest,"move: ready blocks move")
	refuse(w,A,"remove",s,"","move: ready blocks remove")
	must(w,A,"claim_processing",s,"","move: claim")
	must(w,A,"move_object",s,dest,"move: empty queue station moves")
	expect(w.state.objects.has(dest) and not w.state.objects.has(World.key(s)),"move: station relocated")
	var stone0:=held(w,A,"stone")
	must(w,A,"remove",s+Vector2i(1,0),"","move: empty queue station removed")
	expect(not w.state.objects.has(dest) and held(w,A,"sawmill_kit")==1 and held(w,A,"stone")==stone0,"move: kit refunded")

## Real SaveSchema via load_world on mutated copies of a real save.
func test_schema_owner_validation() -> void:
	fresh_sites()
	var w=new_world()
	var s:=place(w,"sawmill")
	queue_ids(w,s,"plank",2,"schema: enqueue")
	var text:=FileAccess.get_file_as_string(w.save_path)
	var k:=World.key(s)
	var cases:={
		"record owner differs from device owner":func(doc):doc.objects[k].processing.waiting[0].owner=B,
		"job coexists with processing":func(doc):doc.objects[k].job={"kind":"plank","owner":A,"ready":1.0,"ingredients":{"wood":4},"yield":2},
		"auto_enabled with processing":func(doc):doc.objects[k].auto_enabled=true,
		"plank queue stored on a charcoal kiln (wrong station)":func(doc):doc.objects[k].type="charcoal_kiln",
	}
	var control=World.new()
	var ok_path:=dir.path_join("schema-ok.json")
	_write(ok_path,text)
	expect(control.load_world(ok_path),"schema: unmodified copy loads")
	for label in cases:
		var doc=JSON.parse_string(text)
		(cases[label] as Callable).call(doc)
		serial+=1
		var path:=dir.path_join("schema-%d.json"%serial)
		_write(path,JSON.stringify(doc))
		var probe=World.new()
		expect(not probe.load_world(path),"schema: rejects "+label)

func _write(path:String,text:String) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(text)
	f.close()
