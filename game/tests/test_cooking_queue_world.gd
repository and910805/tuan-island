extends SceneTree
## T036 stove cooking queue through the real World.act / World.step path
## (not the pure cooking_queue helper). Contract: docs/cooking-queue-integration.json.
##
## Fixture label: LABEL below. All randomness in the fixture (recipe picks, frame
## splits) comes from RandomNumberGenerator seeded with SEED. Job ids themselves
## are server-random (Crypto) and are only compared for shape/uniqueness/order.
##
## Fixtures are explicitly NOT normal play: inventories, stoves, positions,
## regions and some stored historical records are written directly. Every world
## saves into one unique random directory under the OS TEMP folder that is
## deleted afterwards; real player saves are never touched.
const World=preload("res://scripts/world.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const Schema=preload("res://scripts/save_schema.gd")
const REGIONS=preload("res://scripts/regions.gd")
const Collections=preload("res://scripts/collections.gd")

const SEED:=20261114
const LABEL:="cooking-queue-world/seed-20261114"
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const CAP:=1000000000
const TOL:=0.000001
const STOCK:={"minnow":40,"sea_salt":40,"radish":40,"wheat":40,"fiber":40,"lettuce":40,"tomato":40,"potato":40,"carp":40,"carrot":40,"pumpkin":40,"flour":40,"sugar":40,"chime_herb":40,"egg":40,"wood":60,"stone":60,"strawberry":40,"cucumber":40,"sugar_beet":40,"snow_trout":40,"cabbage":40,"star_mushroom":40,"sweet_potato":40,"rice":40,"eggplant":40,"mist_tea":40,"watermelon":40}

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

var checks:=0
var failures:=0
var serial:=0
var dir:=""
var clock:FakeClock

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_environment("TMPDIR")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("cooking-queue-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"Refuse to adopt existing test directory")
		quit(1)
		return
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated TEMP directory created")
	print("COOKING_QUEUE_WORLD fixture=%s"%LABEL)
	var probe=World.new()
	expect(int(probe.state.version)==int(Schema.VERSION),"fresh world follows SaveSchema.VERSION dynamically")
	test_ten_jobs_fifo_large_frame()
	test_ten_jobs_split_frames_match()
	test_competing_claim_and_replay()
	test_cancellation()
	test_claim_output_cap()
	test_legacy_preserved_and_conversion()
	test_legacy_conversion_edges()
	test_move_remove_blocked()
	test_away_region_and_pause()
	test_save_load_roundtrip()
	test_save_failure_rollback()
	test_construction_undo_dependency()
	cleanup()
	print("COOKING_QUEUE_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func cleanup() -> void:
	_remove_tree(dir)

func _remove_tree(path:String) -> void:
	var root_path:=dir.replace("\\","/").simplify_path()
	var target:=path.replace("\\","/").simplify_path()
	if not root_path.is_absolute_path() or (target!=root_path and not target.begins_with(root_path+"/")):
		expect(false,"Cleanup target escaped owned temporary directory")
		return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):_remove_tree(path.path_join(sub))
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

# ---------------------------------------------------------------- fixtures --

func attach(w,c:FakeClock) -> void:
	w.undo_clock_utc=Callable(c,"now_utc")
	w.undo_clock_ticks=Callable(c,"now_ticks")

func new_world():
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	for t in [A,B]:w.state.players[t].inventory=STOCK.duplicate()
	serial+=1
	w.save_path=dir.path_join("world-%d.json"%serial)
	clock=FakeClock.new()
	attach(w,clock)
	return w

func lay(w,region:String,field:String) -> Dictionary:
	return w.state[field] if region==HOME else w.state.regions[region][field]

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

## Legal empty 3x1 site with a two-cell margin, at least `min_dist` from `avoid`.
func find_site(w,region:String,avoid:Vector2i,min_dist:float) -> Vector2i:
	var size:=Vector2i(3,1)
	w.switch_region(region)
	var found:=Vector2i(-1,-1)
	for oy in range(2,58):
		for ox in range(2,78):
			if Vector2(ox,oy).distance_to(Vector2(avoid))<min_dist:continue
			if site_clear(w,Vector2i(ox-2,oy-2),size+Vector2i(4,4)):
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

## Places a plain stove (same shape as a built one) directly; fixture only.
func place_stove(w,region:String=HOME,owner:String=A,avoid:=Vector2i(World.SPAWN),min_dist:=6.0) -> Vector2i:
	var o:=find_site(w,region,avoid,min_dist)
	lay(w,region,"objects")[World.key(o)]={"type":"stove","owner":owner,"items":{}}
	return o

func pose(w,token:String,at:Vector2) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else World.SPAWN
		person.x=spot.x;person.y=spot.y

func near(p:Vector2i) -> Vector2:
	return Vector2(p)+Vector2(1.5,0.8)

func leak_free(value,label:String) -> void:
	var text:=var_to_str(value)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks tokens")

func do(w,token:String,action:String,p:Vector2i,extra:String="",at=null,rid:String="") -> Dictionary:
	pose(w,token,near(p) if at==null else at)
	serial+=1
	if rid=="":rid="req-%d"%serial
	var r:Dictionary=w.act(token,rid,action,p,extra)
	leak_free(r,"result %s %s"%[action,extra])
	expect(w._region==HOME,"home orientation after "+action)
	return r

func must(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null,rid:String="") -> Dictionary:
	var r:=do(w,token,action,p,extra,at,rid)
	expect(r.get("ok",false)==true,label+": "+str(r.get("message","")))
	return r

## Rejected action: ok=false with a message and the whole world state unchanged.
func refuse(w,token:String,action:String,p:Vector2i,extra:String,label:String,contains:String="",at=null) -> Dictionary:
	pose(w,token,near(p) if at==null else at)
	var snap:=var_to_str(w.state)
	serial+=1
	var r:Dictionary=w.act(token,"refuse-%d"%serial,action,p,extra)
	leak_free(r,label)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": rejected with a reason, got "+str(r))
	if contains!="":expect(str(r.get("message","")).contains(contains),label+": message mentions "+contains+", got "+str(r.get("message","")))
	expect(var_to_str(w.state)==snap,label+": world state unchanged")
	expect(w._region==HOME,label+": home orientation")
	return r

func inv(w,token:String) -> Dictionary:
	var out:Dictionary={}
	var src:Dictionary=w.state.players[token].inventory
	for item in src:
		if int(src[item])!=0:out[str(item)]=int(src[item])
	return out

func shifted(base:Dictionary,delta:Dictionary,sign:int) -> Dictionary:
	var out:Dictionary=base.duplicate()
	for item in delta:
		out[item]=int(out.get(item,0))+sign*int(delta[item])
		if int(out[item])==0:out.erase(item)
	return out

func stove(w,p:Vector2i,region:String=HOME) -> Dictionary:
	return lay(w,region,"objects").get(World.key(p),{})

func q(w,p:Vector2i,region:String=HOME) -> Dictionary:
	var c=stove(w,p,region).get("cooking")
	return c if c is Dictionary else {}

func ids_of(list) -> Array:
	var out:=[]
	if list is Array:
		for entry in list:out.append(str(entry.get("id","")))
	return out

func total(c:Dictionary) -> int:
	if c.is_empty():return 0
	return (0 if (c.active as Dictionary).is_empty() else 1)+(c.waiting as Array).size()+(c.ready as Array).size()

func hex32(value) -> bool:
	return value is String and World._is_lower_hex(value,32)

func cooked(w,token:String) -> int:
	return int(w.state.players[token].get("cooked",0))

func close(a:float,b:float) -> bool:
	return absf(a-b)<=TOL

func seeded_picks(person:Dictionary) -> Array:
	var rng:=RandomNumberGenerator.new()
	rng.seed=SEED
	var kinds:Array=World.RECIPES.keys().filter(func(kind:String):return World.has_recipe(person,kind))
	kinds.sort()
	var picks:=[]
	for i in Queue.CAPACITY:picks.append(str(kinds[rng.randi_range(0,kinds.size()-1)]))
	return picks

## Queues ten seeded jobs from A, checks the 11th is refused atomically, then
## rewrites the second job's stored snapshot to differ from today's recipe.
## Returns {w, s, ids, picks, expected(finish times)}.
func ten_job_world(tag:String) -> Dictionary:
	var w=new_world()
	var s:=place_stove(w)
	var person:Dictionary=w.state.players[A]
	var picks:=seeded_picks(person)
	var ids:=[]
	var spent:={}
	var required:Dictionary={}
	for kind:String in picks:
		var ingredients:Dictionary=World.RECIPES[kind].ingredients
		for item:String in ingredients:
			required[item]=int(required.get(item,0))+int(ingredients[item])
	for item:String in required:
		person.inventory[item]=maxi(int(person.inventory.get(item,0)),int(required[item]))
	var inv0:=inv(w,A)
	for i in picks.size():
		var kind:String=picks[i]
		var r:=must(w,A,"queue_cook",s,kind,"%s %s job %d %s"%[LABEL,tag,i,kind])
		expect(hex32(r.get("id")),tag+": job %d returns 32-hex id"%i)
		expect(r.get("kind")==kind,tag+": job %d returns kind"%i)
		expect(r.get("started")==(i==0),tag+": only the first job starts immediately")
		expect(not r.has("owner"),tag+": result carries no owner")
		ids.append(str(r.get("id","")))
		var ingredients:Dictionary=World.RECIPES[kind].ingredients
		for item in ingredients:spent[item]=int(spent.get(item,0))+int(ingredients[item])
	var unique:={}
	for id in ids:unique[id]=true
	expect(unique.size()==Queue.CAPACITY,tag+": ten distinct job ids")
	expect(inv(w,A)==shifted(inv0,spent,-1),tag+": exactly the ten recipes' ingredients charged")
	var c:=q(w,s)
	expect(total(c)==Queue.CAPACITY and str(c.active.id)==ids[0] and ids_of(c.waiting)==ids.slice(1),tag+": FIFO active + nine waiting")
	expect(not stove(w,s).has("job"),tag+": queue stove never carries legacy job")
	refuse(w,A,"queue_cook",s,picks[0],tag+": eleventh queue_cook refused","已滿")
	refuse(w,B,"cook",s,"feed",tag+": ordinary cook on full queue refused","已滿")
	# Historical snapshot: stored cost/yield/duration differ from today's recipe.
	var second:Dictionary=c.waiting[0]
	second.duration=3.0
	second["yield"]=7
	second.ingredients={"wheat":9}
	var expected:=[]
	var t:=0.0
	for i in picks.size():
		t+=3.0 if i==1 else float(World.RECIPES[picks[i]].time)
		expected.append(t)
	return {"w":w,"s":s,"ids":ids,"picks":picks,"expected":expected}

func check_ready_fifo(f:Dictionary,tag:String) -> void:
	var c:=q(f.w,f.s)
	expect((c.active as Dictionary).is_empty() and (c.waiting as Array).is_empty(),tag+": nothing left active or waiting")
	expect(ids_of(c.ready)==f.ids,tag+": ready in exact FIFO submission order")
	var ok_times:bool=(c.ready as Array).size()==f.expected.size()
	if ok_times:
		for i in f.expected.size():
			if not close(float(c.ready[i].completed),float(f.expected[i])):ok_times=false
	expect(ok_times,tag+": completion times follow stored durations (historical 3s job included)")
	expect(int(c.ready[1]["yield"])==7 and c.ready[1].ingredients=={"wheat":9},tag+": historical snapshot preserved into ready")

# ------------------------------------------------------------------- tests --

func test_ten_jobs_fifo_large_frame() -> void:
	var f:=ten_job_world("large")
	var w=f.w
	var s:Vector2i=f.s
	var finish:float=f.expected[f.expected.size()-1]
	expect(w.step(finish+1.0,true),"large: one frame step saved")
	check_ready_fifo(f,"large")
	# Shared claim permission: A and B alternate, oldest first.
	for i in f.ids.size():
		var who:String=A if i%2==0 else B
		var kind:String=f.picks[i]
		var amount:int=7 if i==1 else int(World.RECIPES[kind]["yield"])
		var before:=int(w.state.players[who].inventory.get(kind,0))
		var r:=must(w,who,"claim_cook",s,"","large: claim %d"%i)
		expect(str(r.get("id",""))==f.ids[i] and r.get("kind")==kind,"large: claim %d returns the oldest ready job"%i)
		expect(int(r.get("yield",-1))==amount,"large: claim %d yields stored amount %d"%[i,amount])
		expect(int(w.state.players[who].inventory.get(kind,0))==before+amount,"large: claim %d credited once"%i)
		if Collections.is_meal(kind):expect(w.state.players[who].collection.meals.get(kind,false)==true,"large: claim %d registers meal"%i)
	expect(cooked(w,A)==5 and cooked(w,B)==5,"large: cooked counter +1 per claim, split by claimer")
	expect(total(q(w,s))==0 and stove(w,s).has("cooking"),"large: queue empty but stays queue-enabled")
	refuse(w,A,"claim_cook",s,"","large: nothing left to claim")

func test_ten_jobs_split_frames_match() -> void:
	var f:=ten_job_world("split")
	var w=f.w
	var rng:=RandomNumberGenerator.new()
	rng.seed=SEED+1
	var finish:float=f.expected[f.expected.size()-1]
	var frames:=0
	var monotonic:=true
	while float(w.state.time)<=finish+1.0 and frames<1000:
		expect(w.step(rng.randf_range(0.25,4.0),true),"split: frame saved")
		frames+=1
		var now:=float(w.state.time)
		var due:=0
		for e in f.expected:
			if float(e)<=now:due+=1
		if (q(w,f.s).ready as Array).size()!=due:monotonic=false
	expect(frames>10,"split: many frames used (%d)"%frames)
	expect(monotonic,"split: after every frame ready count equals jobs due by world time")
	check_ready_fifo(f,"split")

func test_competing_claim_and_replay() -> void:
	var w=new_world()
	var s:=place_stove(w)
	var radish0:=int(w.state.players[A].inventory.radish)
	var r1:=must(w,A,"queue_cook",s,"soup","replay: queue soup",null,"q-1")
	var r2:=must(w,A,"queue_cook",s,"soup","replay: same nonce",null,"q-1")
	expect(r1==r2,"replay: same nonce returns the stored receipt")
	expect(total(q(w,s))==1 and int(w.state.players[A].inventory.radish)==radish0-2,"replay: one job, charged once")
	expect(w.step(11.0,true),"replay: finish soup")
	var soupA:=int(w.state.players[A].inventory.get("soup",0))
	var soupB:=int(w.state.players[B].inventory.get("soup",0))
	var ra:=must(w,A,"claim_cook",s,"","compete: A claims first",null,"claim-1")
	var rb:=do(w,B,"claim_cook",s,"",null,"claim-1")
	expect(rb.get("ok",true)==false,"compete: B's claim of the same job fails (other player's nonce is not shared)")
	var ra2:=do(w,A,"claim_cook",s,"",null,"claim-1")
	expect(ra2==ra,"compete: A's replay returns the receipt, not a second claim")
	expect(int(w.state.players[A].inventory.get("soup",0))==soupA+2 and int(w.state.players[B].inventory.get("soup",0))==soupB,"compete: food credited exactly once")
	expect(cooked(w,A)==1 and cooked(w,B)==0,"compete: cooked counter exactly once")
	leak_free(w.state.players[A].receipts,"compete: stored receipts")

func test_cancellation() -> void:
	var w=new_world()
	var s:=place_stove(w)
	var j0:=str(must(w,A,"queue_cook",s,"soup","cancel: A soup").get("id"))
	var j1:=str(must(w,A,"queue_cook",s,"bread","cancel: A bread").get("id"))
	var j2:=str(must(w,B,"queue_cook",s,"feed","cancel: B feed").get("id"))
	var j3:=str(must(w,A,"cook",s,"salad","cancel: A salad via ordinary cook").get("id"))
	expect(hex32(j3) and total(q(w,s))==4,"cancel: ordinary cook on queue stove enqueues")
	refuse(w,B,"cancel_cook",s,"","cancel: B cannot cancel A's active","只有")
	refuse(w,B,"cancel_queued_cook",s,j1,"cancel: B cannot cancel A's waiting","只有")
	refuse(w,A,"cancel_queued_cook",s,"not-a-job-id","cancel: malformed id")
	refuse(w,A,"cancel_queued_cook",s,"0".repeat(32),"cancel: unknown id")
	if j1.to_upper()!=j1:refuse(w,A,"cancel_queued_cook",s,j1.to_upper(),"cancel: id must be exact lowercase")
	# Historical stored ingredients are what gets refunded.
	var waiting:Array=q(w,s).waiting
	for entry in waiting:
		if entry.id==j3:entry.ingredients={"lettuce":5}
	var inv0:=inv(w,A)
	var r:=must(w,A,"cancel_queued_cook",s,j3,"cancel: A cancels own waiting salad")
	expect(str(r.get("id"))==j3 and r.get("kind")=="salad" and r.get("refunded")=={"lettuce":5},"cancel: result metadata id/kind/refund")
	expect(inv(w,A)==shifted(inv0,{"lettuce":5},1),"cancel: exact stored ingredients refunded")
	refuse(w,A,"cancel_queued_cook",s,j3,"cancel: no double refund")
	w.state.players[A].inventory.wheat=CAP-1
	refuse(w,A,"cancel_queued_cook",s,j1,"cancel: refund over item cap refused","上限")
	w.state.players[A].inventory.wheat=40
	# Fixture time jump without a step: the action itself must advance first.
	w.state.time=10.0
	var before_wheat:=int(w.state.players[A].inventory.wheat)
	var rc:=must(w,A,"cancel_cook",s,"","cancel: advance then cancel A's now-active bread")
	expect(str(rc.get("id"))==j1,"cancel: cancel_cook targeted the promoted active job, not finished soup")
	expect(int(w.state.players[A].inventory.wheat)==before_wheat+2,"cancel: bread wheat refunded")
	var c:=q(w,s)
	expect(ids_of(c.ready)==[j0] and str(c.active.id)==j2 and close(float(c.active.started),10.0),"cancel: soup stays ready, B's feed promoted at now")
	refuse(w,A,"cancel_cook",s,"","cancel: active belongs to B")
	refuse(w,A,"cancel_queued_cook",s,j0,"cancel: completed food never cancelled","已完成")
	must(w,B,"cancel_cook",s,"","cancel: B cancels own active feed")
	refuse(w,B,"cancel_cook",s,"","cancel: no active job left")
	var rr:=must(w,B,"claim_cook",s,"","cancel: B claims A's ready soup (shared kitchen)")
	expect(str(rr.get("id"))==j0,"cancel: ready soup survived every cancellation")

func test_claim_output_cap() -> void:
	var w=new_world()
	var s:=place_stove(w)
	must(w,A,"queue_cook",s,"soup","cap: queue soup")
	must(w,A,"queue_cook",s,"bread","cap: queue bread")
	expect(w.step(11.0,true),"cap: soup done")
	w.state.players[A].inventory["soup"]=CAP-1
	var cooked0:=cooked(w,A)
	refuse(w,A,"claim_cook",s,"","cap: claim over output cap refused","上限")
	expect((q(w,s).ready as Array).size()==1 and cooked(w,A)==cooked0,"cap: ready food and progress preserved")
	w.state.players[A].inventory["soup"]=CAP-2
	must(w,A,"claim_cook",s,"","cap: claim exactly at cap")
	expect(int(w.state.players[A].inventory.soup)==CAP,"cap: reached exact cap")
	refuse(w,A,"claim_cook",s,"","cap: bread still cooking","秒")

func test_legacy_preserved_and_conversion() -> void:
	var w=new_world()
	var s:=place_stove(w)
	must(w,A,"cook",s,"soup","legacy: ordinary cook on plain stove")
	var st:=stove(w,s)
	expect(st.has("job") and not st.has("cooking"),"legacy: plain stove keeps single job path")
	refuse(w,A,"cook",s,"bread","legacy: busy single job refuses second cook")
	st.job.ingredients={"radish":3}
	st.job["yield"]=5
	var legacy_ready:=float(st.job.ready)
	refuse(w,A,"queue_cook",s,"nonsense","legacy: invalid recipe, no conversion")
	w.state.players[A].inventory.wheat=1
	refuse(w,A,"queue_cook",s,"bread","legacy: missing ingredients, no conversion","缺少")
	expect(stove(w,s).has("job") and not stove(w,s).has("cooking"),"legacy: still single job after refusals")
	w.state.players[A].inventory.wheat=40
	var r:=must(w,A,"queue_cook",s,"bread","legacy: queue_cook converts")
	st=stove(w,s)
	expect(not st.has("job") and st.has("cooking"),"legacy: job removed only after successful enqueue")
	var c:=q(w,s)
	var imported:Dictionary=c.active
	expect(hex32(imported.get("id")) and imported.id!=r.id,"legacy: imported job got its own random id")
	expect(imported.owner==A and imported.ingredients=={"radish":3} and int(imported["yield"])==5,"legacy: owner and historical snapshot preserved")
	expect(close(float(imported.finish),legacy_ready),"legacy: original deadline preserved")
	expect(ids_of(c.waiting)==[str(r.id)] and r.get("started")==false,"legacy: new job waits behind imported one")
	var rb:=must(w,B,"cook",s,"feed","legacy: ordinary cook now enqueues")
	expect(total(q(w,s))==3 and hex32(rb.get("id")),"legacy: three jobs queued")
	expect(w.step(10.5,true),"legacy: imported job finishes")
	var soup0:=int(w.state.players[B].inventory.get("soup",0))
	var cr:=must(w,B,"claim_cook",s,"","legacy: claim imported")
	expect(str(cr.get("id"))==str(imported.id) and int(w.state.players[B].inventory.get("soup",0))==soup0+5,"legacy: stored yield 5 claimed")

func test_legacy_conversion_edges() -> void:
	# Already-completed legacy job imports straight into ready.
	var w=new_world()
	var s:=place_stove(w)
	must(w,B,"cook",s,"soup","edge: B legacy soup")
	expect(w.step(12.0,true),"edge: time passes (legacy job untouched by ticks)")
	expect(stove(w,s).has("job") and not stove(w,s).has("cooking"),"edge: ticks never convert legacy stoves")
	must(w,A,"queue_cook",s,"bread","edge: A converts completed legacy")
	var c:=q(w,s)
	expect((c.ready as Array).size()==1 and close(float(c.ready[0].completed),10.0) and c.ready[0].owner==B,"edge: completed legacy job imported to ready with owner")
	expect(close(float(c.active.started),12.0),"edge: new job starts now")
	# Unfinished legacy owned by B, converted by A: only B may cancel it.
	var w2=new_world()
	var s2:=place_stove(w2)
	must(w2,B,"cook",s2,"bread","edge: B legacy bread")
	must(w2,A,"queue_cook",s2,"soup","edge: A converts B's job")
	refuse(w2,A,"cancel_cook",s2,"","edge: A cannot cancel B's imported job")
	var wheat0:=int(w2.state.players[B].inventory.wheat)
	must(w2,B,"cancel_cook",s2,"","edge: B cancels own imported job")
	expect(int(w2.state.players[B].inventory.wheat)==wheat0+2,"edge: imported ingredients refunded to B")
	# Malformed legacy record: no conversion, no charge.
	var w3=new_world()
	var s3:=place_stove(w3)
	must(w3,A,"cook",s3,"soup","edge: legacy soup")
	stove(w3,s3).job.extra_field=1
	refuse(w3,A,"queue_cook",s3,"bread","edge: malformed legacy job refuses conversion")
	# Corrupt coexistence of job and cooking: every cooking action refused.
	var w4=new_world()
	var s4:=place_stove(w4)
	must(w4,A,"cook",s4,"soup","edge: legacy soup")
	stove(w4,s4).cooking=Queue.empty_state()
	for action in ["cook","queue_cook","claim_cook","cancel_cook"]:
		refuse(w4,A,action,s4,"bread" if action in ["cook","queue_cook"] else "","edge: job+cooking coexist refuses "+action)
	refuse(w4,A,"remove",s4,"","edge: coexist stove cannot be removed")
	# cancel_queued_cook never touches a legacy stove.
	var w5=new_world()
	var s5:=place_stove(w5)
	must(w5,A,"cook",s5,"soup","edge: legacy soup")
	refuse(w5,A,"cancel_queued_cook",s5,"0".repeat(32),"edge: cancel_queued_cook on legacy stove")
	expect(stove(w5,s5).has("job") and not stove(w5,s5).has("cooking"),"edge: legacy untouched")

func test_move_remove_blocked() -> void:
	var w=new_world()
	var s:=place_stove(w)
	var dest:=s+Vector2i(2,0)
	var dest_text:=World.key(dest)
	must(w,B,"queue_cook",s,"soup","move: B queues on A's stove")
	refuse(w,A,"move_object",s,dest_text,"move: active blocks move")
	refuse(w,A,"remove",s,"","move: active blocks remove")
	expect(w.step(11.0,true),"move: soup ready")
	refuse(w,A,"move_object",s,dest_text,"move: unclaimed ready blocks move")
	refuse(w,A,"remove",s,"","move: unclaimed ready blocks remove")
	must(w,B,"claim_cook",s,"","move: claim")
	must(w,A,"move_object",s,dest_text,"move: empty queue stove moves")
	expect(stove(w,dest).get("cooking")==Queue.empty_state() and not w.state.objects.has(World.key(s)),"move: empty queue moved along")
	var inv0:=inv(w,A)
	must(w,A,"remove",dest,"","move: empty queue stove removed")
	expect(not w.state.objects.has(dest_text) and inv(w,A)==shifted(inv0,{"wood":12,"stone":15},1),"move: build materials refunded")

func test_away_region_and_pause() -> void:
	var w=new_world()
	var home_stove:=place_stove(w,HOME,A)
	var far:=place_stove(w,LANYANG,A,home_stove,8.0)
	expect(lay(w,LANYANG,"objects").has(World.key(far)) and not w.state.objects.has(World.key(far)),"away: lanyang stove only in lanyang layers")
	refuse(w,B,"queue_cook",far,"soup","away: home player cannot reach lanyang stove")
	w.state.players[A].region=LANYANG
	refuse(w,A,"queue_cook",far,"soup","away: out of interaction range",""  ,Vector2(far)+Vector2(8.5,0.5))
	must(w,A,"queue_cook",far,"soup","away: A queues in lanyang")
	expect(total(q(w,far,LANYANG))==1,"away: stored in lanyang stove")
	must(w,B,"queue_cook",home_stove,"bread","away: B queues at home")
	# A leaves lanyang and disconnects; B also disconnects.
	w.state.players[A].region=HOME
	w.active_tokens.clear()
	var snap:=var_to_str(w.state)
	for i in 3:expect(w.step(10.0,false),"away: paused step returns ok")
	expect(var_to_str(w.state)==snap,"away: inactive world fully paused")
	expect(w.step(16.0,true),"away: active world steps with nobody in either region")
	expect((q(w,far,LANYANG).ready as Array).size()==1,"away: lanyang queue progressed with nobody there")
	expect((q(w,home_stove).ready as Array).size()==1,"away: home queue progressed while disconnected")
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),"away: tick completion was saved")
	expect((q(loaded,far,LANYANG).ready as Array).size()==1,"away: saved file holds regional completion")

func test_save_load_roundtrip() -> void:
	var w=new_world()
	var s:=place_stove(w)
	var j0:=str(must(w,A,"queue_cook",s,"soup","save: soup").get("id"))
	var j1:=str(must(w,A,"queue_cook",s,"bread","save: bread").get("id"))
	var j2:=str(must(w,B,"queue_cook",s,"feed","save: feed").get("id"))
	expect(w.step(12.0,true),"save: partial progress saved")
	var path:String=w.save_path
	expect(FileAccess.file_exists(path),"save: file written in TEMP directory")
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(parsed is Dictionary and int(parsed.get("version",0))==int(Schema.VERSION),"save: document at SaveSchema.VERSION")
	if parsed is Dictionary:
		var obj=parsed.objects.get(World.key(s),{})
		expect(obj.has("cooking") and not obj.has("job"),"save: stove persisted with cooking only")
	var loaded=World.new()
	expect(loaded.load_world(path),"save: reload passes real SaveSchema validation")
	attach(loaded,clock)
	loaded.add_player(A,"Alice")
	loaded.add_player(B,"Bob")
	var c:=q(loaded,s)
	expect(ids_of(c.get("ready",[]))==[j0] and str(c.get("active",{}).get("id",""))==j1 and ids_of(c.get("waiting",[]))==[j2],"save: queue order survives reload")
	if not c.is_empty():
		expect(close(float(c.active.finish),float(q(w,s).active.finish)),"save: active deadline survives reload")
	expect(loaded.step(30.0,true),"save: reloaded world continues")
	for who in [B,A,B]:must(loaded,who,"claim_cook",s,"","save: claim after reload")
	expect(cooked(loaded,A)==1 and cooked(loaded,B)==2,"save: cooked counters after reload")
	var again=World.new()
	expect(again.load_world(path) and total(q(again,s))==0 and stove(again,s).has("cooking"),"save: emptied queue persisted")

## Pose, snapshot, act with storage broken: must fail and leave state identical.
func broken_act(w,token:String,action:String,p:Vector2i,extra:String,rid:String,label:String) -> void:
	pose(w,token,near(p))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(token,rid,action,p,extra)
	expect(r.get("ok",true)==false and str(r.get("message","")).contains("保存失敗"),label+": save failure reported, got "+str(r))
	expect(var_to_str(w.state)==snap,label+": entire state rolled back")
	expect(w._region==HOME,label+": home orientation")

func test_save_failure_rollback() -> void:
	var w=new_world()
	var s:=place_stove(w)
	var legacy:=place_stove(w,HOME,A,s,6.0)
	must(w,A,"queue_cook",s,"soup","fail: soup")
	must(w,B,"queue_cook",s,"bread","fail: bread")
	must(w,A,"cook",legacy,"soup","fail: legacy job")
	var good:String=w.save_path
	var bad:=dir.path_join("missing-"+Crypto.new().generate_random_bytes(4).hex_encode()).path_join("world.json")
	w.save_path=bad
	broken_act(w,A,"queue_cook",s,"feed","sf-enqueue","fail: enqueue")
	broken_act(w,A,"queue_cook",legacy,"bread","sf-convert","fail: legacy conversion")
	expect(stove(w,legacy).has("job") and not stove(w,legacy).has("cooking"),"fail: no half conversion after save failure")
	var snap:=var_to_str(w.state)
	expect(w.step(11.0,true)==false,"fail: tick with completion reports save failure")
	expect(var_to_str(w.state)==snap,"fail: tick completion rolled back")
	w.save_path=good
	expect(w.step(11.0,true),"fail: tick succeeds once storage recovers")
	expect((q(w,s).ready as Array).size()==1,"fail: soup ready")
	w.save_path=bad
	broken_act(w,B,"claim_cook",s,"","sf-claim","fail: claim")
	broken_act(w,B,"cancel_cook",s,"","sf-cancel","fail: cancel active")
	var bread_id:=str(q(w,s).active.id)
	broken_act(w,B,"cancel_queued_cook",s,bread_id,"sf-cancel-id","fail: cancel by id")
	w.save_path=good
	must(w,A,"queue_cook",s,"feed","fail: same enqueue nonce succeeds after recovery",null,"sf-enqueue")
	must(w,B,"claim_cook",s,"","fail: same claim nonce succeeds after recovery",null,"sf-claim")
	must(w,B,"cancel_cook",s,"","fail: same cancel nonce succeeds after recovery",null,"sf-cancel")
	must(w,A,"queue_cook",legacy,"bread","fail: conversion succeeds after recovery",null,"sf-convert")
	expect(not stove(w,legacy).has("job") and total(q(w,legacy))==2,"fail: conversion committed whole")

func test_construction_undo_dependency() -> void:
	# Queue use invalidates the builder's undo of the stove.
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(World.SPAWN),6.0)
	must(w,A,"build",o,"stove","undo: A builds stove")
	var s0:Dictionary=w.undo_summary(A)
	expect(s0.get("available")==true,"undo: fresh stove build undoable")
	refuse(w,B,"claim_cook",o,"","undo: failed claim")
	expect(w.undo_summary(A).get("available")==true,"undo: failed action does not invalidate")
	must(w,B,"queue_cook",o,"soup","undo: B queues on new stove")
	expect(w.undo_summary(A).get("available")!=true,"undo: queue use closes A's undo")
	refuse(w,A,"undo_build",o,str(s0.get("id","")),"undo: cannot undo a stove holding queued food")
	expect(total(q(w,o))==1,"undo: queued food intact")
	# Move of an idle queue stove, then queue use / claim invalidates the move.
	expect(w.step(11.0,true),"undo: soup ready")
	must(w,B,"claim_cook",o,"","undo: claim")
	var dest:=o+Vector2i(2,0)
	must(w,A,"move_object",o,World.key(dest),"undo: move idle queue stove")
	var s1:Dictionary=w.undo_summary(A)
	expect(s1.get("available")==true,"undo: idle stove move undoable")
	expect(w.step(5.0,true),"undo: idle tick")
	expect(w.undo_summary(A).get("available")==true,"undo: idle queue tick is not a use")
	must(w,B,"queue_cook",dest,"feed","undo: B queues on moved stove")
	expect(w.undo_summary(A).get("available")!=true,"undo: queue after move closes move undo")
	# Automatic completion marks the stove as used (white-box: tick use map).
	var w2=new_world()
	var s2:=place_stove(w2)
	must(w2,A,"queue_cook",s2,"soup","undo: tick fixture")
	w2._undo_used={}
	expect(w2.step_cooking(float(w2.state.time)+0.5)==false and w2._undo_used.is_empty(),"undo: unfinished tick marks nothing")
	expect(w2.step_cooking(float(w2.state.time)+11.0)==true,"undo: completion reports change")
	expect(w2._undo_used.get(HOME,{}).has(World.key(s2)),"undo: completion marks stove as used")
	w2._undo_used={}
