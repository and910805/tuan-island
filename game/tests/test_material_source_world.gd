extends SceneTree
## T036 material sources (docs/material-source-contract.json) through the REAL
## World.act / World.step / save / load_world path: prepare_material_box plus
## sourced craft / cook / queue_cook / start_processing / queue_processing whose
## extra is built with MaterialSources.encode + MaterialSources.digest over the
## exact split returned by MaterialSupply.plan (the same split a client shows).
##
## Fixture label: LABEL. FIXTURE, NOT NORMAL PLAY (disclosed):
##  * inventories and chest contents are written directly (synthetic resources);
##  * benches, stoves, sawmills, kilns and most chests are written directly into
##    the home object layer in the shape a real build produces (no kits spent);
##    a few chests are built / moved / removed through real World.act instead;
##  * stations sit on legal, empty, cleared 7x7 home sites found by scanning
##    is_land / water / protected / blocked (original World invariants);
##  * players are teleported next to the station before every action;
##  * world time only moves through explicit World.step(dt, true) calls and the
##    undo clocks are injected fakes;
##  * the race test sets the shared chest stock to one radish directly;
##  * save failure uses a REAL unwritable path (a directory that does not exist);
##  * one real save is relabelled version 21 to emulate an old save.
## Every world saves into one random directory under the OS TEMP folder that is
## deleted afterwards; real player saves are never touched.
const World=preload("res://scripts/world.gd")
const Sources=preload("res://scripts/material_sources.gd")
const Supply=preload("res://scripts/material_supply.gd")
const Schema=preload("res://scripts/save_schema.gd")
const REGIONS=preload("res://scripts/regions.gd")

const LABEL:="material-source-world/fixture-20261114"
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const HOME:=REGIONS.HOME
const CAP:=1000000000
const UP:=Vector2i(0,-1)
const DOWN:=Vector2i(0,1)
const LEFT:=Vector2i(-1,0)
const RIGHT:=Vector2i(1,0)
const KIT:="sawmill_kit" # bench recipe used throughout: wood 8 + stone 4 -> 1

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

var checks:=0
var failures:=0
var serial:=0
var dir:=""
var used:Array=[]
var here:=Vector2.ZERO
var clocks:Array=[] # keeps injected clocks alive (Callables do not own them)

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_environment("TMPDIR")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("material-source-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt existing test directory")
		print("MATERIAL_SOURCE_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated TEMP directory created")
	print("MATERIAL_SOURCE_WORLD fixture=%s dir=%s"%[LABEL,dir])
	test_helper_contract()
	test_bench_shared()
	test_stove_shared()
	test_processing_owner_only()
	test_private_and_adjacency()
	test_move_replace()
	test_stale_and_wire()
	test_cap_overflow()
	test_save_failure()
	test_save_reload_lazy()
	test_undo_remote_chest()
	_remove_tree(dir)
	expect(not DirAccess.dir_exists_absolute(dir),"isolated TEMP directory removed")
	print("MATERIAL_SOURCE_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
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

func _write(path:String,text:String) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(text)
	f.close()

# ---------------------------------------------------------------- fixtures --

func attach(w) -> void:
	var clock:=FakeClock.new()
	clocks.append(clock)
	w.undo_clock_utc=Callable(clock,"now_utc")
	w.undo_clock_ticks=Callable(clock,"now_ticks")

## FIXTURE: two members with EMPTY backpacks; each test seeds exact stock.
func new_world():
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	for t in [A,B]:w.state.players[t].inventory={}
	serial+=1
	w.save_path=dir.path_join("world-%d.json"%serial)
	attach(w)
	used=[]
	return w

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

## Legal empty 7x7 home square centred on the returned cell, far from spawn and
## from every site already used in this world. Natural resources are cleared.
func find_site(w) -> Vector2i:
	var found:=Vector2i(-1,-1)
	for oy in range(5,55):
		for ox in range(5,75):
			var c:=Vector2i(ox,oy)
			if Vector2(c).distance_to(World.SPAWN)<9.0:continue
			var far:=true
			for u in used:
				if Vector2(c).distance_to(Vector2(u))<9.0:far=false;break
			if far and site_clear(w,c-Vector2i(3,3),Vector2i(7,7)):
				found=c
				break
		if found.x>=0:break
	expect(found.x>=0,"fixture: found a legal empty 7x7 home site")
	if found.x>=0:
		used.append(found)
		for y in range(found.y-3,found.y+4):
			for x in range(found.x-3,found.x+4):
				var c:=Vector2i(x,y)
				if w.resource(c)!="":w.state.removed[World.key(c)]=true
	return found

## FIXTURE: station written in the shape `build` produces; actor stands nearby.
func layout(w,kind:String,owner:String=A) -> Vector2i:
	var o:=find_site(w)
	var d:={"type":kind,"owner":owner,"items":{}}
	if kind in ["sawmill","charcoal_kiln"]:d.merge({"input_wood":0,"auto_enabled":false})
	w.state.objects[World.key(o)]=d
	go(o)
	return o

## FIXTURE: chest written directly (never carries a box_id).
func put_box(w,c:Vector2i,kind:String,owner:String,stock_items:Dictionary) -> void:
	w.state.objects[World.key(c)]={"type":kind,"owner":owner,"items":stock_items.duplicate()}

## Standing spot: cell station+(1,1), within reach of the station, every
## cardinal neighbour and station+(2,0/1), never on a neighbour's footprint.
func go(o:Vector2i) -> void:
	here=Vector2(o)+Vector2(1.5,1.6)

func set_inv(w,token:String,inv:Dictionary) -> void:
	w.state.players[token].inventory=inv.duplicate()

func obj(w,c:Vector2i) -> Dictionary:
	return w.state.objects.get(World.key(c),{})

func items(w,c:Vector2i) -> Dictionary:
	return obj(w,c).get("items",{})

func stock(w,c:Vector2i,item:String) -> int:
	return int(items(w,c).get(item,0))

func bid(w,c:Vector2i) -> String:
	return str(obj(w,c).get("box_id",""))

func held(w,token:String,item:String) -> int:
	return int(w.state.players[token].inventory.get(item,0))

func hex32(value) -> bool:
	return value is String and World._is_lower_hex(value,32)

func avail(w,token:String=A) -> bool:
	return w.undo_summary(token).get("available")==true

func queue_of(w,c:Vector2i,field:String) -> Dictionary:
	var q=obj(w,c).get(field)
	return q if q is Dictionary else {}

func ids_of(list) -> Array:
	var out:=[]
	if list is Array:
		for entry in list:out.append(str(entry.get("id","")))
	return out

func all_ids(q:Dictionary) -> Array:
	if q.is_empty():return []
	var out:=[]
	if not (q.active as Dictionary).is_empty():out.append(str(q.active.id))
	return out+ids_of(q.waiting)+ids_of(q.ready)

func pose(w,token:String) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=here if t==token else World.SPAWN
		person.x=spot.x;person.y=spot.y

func leak_free(value,label:String) -> void:
	var text:=var_to_str(value)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks tokens")

func do(w,token:String,action:String,p:Vector2i,extra:String="",rid:String="") -> Dictionary:
	pose(w,token)
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
	pose(w,token)
	var snap:=var_to_str(w.state)
	serial+=1
	var r:Dictionary=w.act(token,"refuse-%d"%serial,action,p,extra)
	leak_free(r,label)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": rejected with a reason, got "+str(r))
	expect(var_to_str(w.state)==snap,label+": world state unchanged")
	return r

func broken_act(w,token:String,action:String,p:Vector2i,extra:String,rid:String,label:String) -> void:
	pose(w,token)
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(token,rid,action,p,extra)
	expect(r.get("ok",true)==false and str(r.get("message","")).contains("保存失敗"),label+": save failure reported, got "+str(r))
	expect(var_to_str(w.state)==snap,label+": entire state rolled back (stock, queue, box_id, receipt)")

func recipe_def(action:String,recipe_id:String) -> Dictionary:
	match action:
		"craft":return World.CRAFT.get(recipe_id,{})
		"cook","queue_cook":return World.RECIPES.get(recipe_id,{})
	return World.INDUSTRY.PROCESS.get(recipe_id,{})

## What a client displays and confirms: MaterialSupply.plan over the actor's
## live backpack and the chosen chest, digested and encoded for the wire.
## `id` overrides the chest id (null = the chest's current box_id or "").
func quote(w,token:String,action:String,station:Vector2i,recipe_id:String,box:Vector2i,id=null) -> Dictionary:
	var chest_id:String=bid(w,box) if id==null else str(id)
	var def:=recipe_def(action,recipe_id)
	var plan:Dictionary=Supply.plan(def.get("ingredients",{}),w.state.players[token].inventory,items(w,box))
	var alloc:={"from_backpack":plan.get("from_backpack",{}),"from_chest":plan.get("from_chest",{})}
	var kind:=str(obj(w,station).get("type",""))
	var d:String=Sources.digest(action,kind,World.key(station),recipe_id,def,World.key(box),chest_id,alloc)
	return {"plan":plan,"digest":d,"id":chest_id,"extra":Sources.encode(recipe_id,World.key(box),chest_id,d)}

func prep(w,token:String,station:Vector2i,box:Vector2i,label:String,rid:String="") -> String:
	var r:=must(w,token,"prepare_material_box",station,World.key(box),label,rid)
	var id:=bid(w,box)
	expect(hex32(id) and r.get("source_cell")==World.key(box) and r.get("source_id")==id,label+": result names source_cell and the chest's 32-hex box_id")
	return id

func sourced_meta(r:Dictionary,box:Vector2i,q:Dictionary,label:String) -> void:
	expect(r.get("source_cell")==World.key(box) and r.get("source_id")==q.id,label+": result names source_cell/source_id")
	expect(r.get("from_backpack")==q.plan.get("from_backpack") and r.get("from_chest")==q.plan.get("from_chest"),label+": result reports the exact confirmed split")

# ------------------------------------------------------------------- tests --

func test_helper_contract() -> void:
	expect(int(Schema.MATERIAL_SOURCE_VERSION)==22,"schema: MATERIAL_SOURCE_VERSION literal 22")
	var probe=World.new()
	expect(int(probe.state.version)==int(Schema.VERSION) and int(Schema.VERSION)>=22,"fresh world at SaveSchema.VERSION (>=22)")
	expect(World.CRAFT[KIT].ingredients=={"wood":8,"stone":4},"premise: bench sawmill_kit = wood 8 + stone 4")
	expect(World.RECIPES.soup.ingredients=={"radish":2},"premise: stove soup = radish 2")
	expect(World.INDUSTRY.PROCESS.plank.ingredients=={"wood":4} and World.INDUSTRY.PROCESS.charcoal.ingredients=={"wood":4},"premise: plank/charcoal = wood 4")
	var id1:="0123456789abcdef0123456789abcdef"
	var id2:="fedcba9876543210fedcba9876543210"
	var def:Dictionary=World.CRAFT[KIT]
	var alloc:={"from_backpack":{"wood":5,"stone":4},"from_chest":{"wood":3}}
	var d1:String=Sources.digest("craft","bench","20,20",KIT,def,"21,20",id1,alloc)
	expect(World._is_lower_hex(d1,16),"digest: 16 lowercase hex")
	expect(Sources.digest("craft","bench","20,20",KIT,def.duplicate(true),"21,20",id1,alloc.duplicate(true))==d1,"digest: deterministic")
	var reordered:={"from_chest":{"wood":3},"from_backpack":{"stone":4,"wood":5}}
	expect(Sources.digest("craft","bench","20,20",KIT,def,"21,20",id1,reordered)==d1,"digest: independent of insertion order")
	var zeros:={"from_backpack":{"wood":5,"stone":4,"fiber":0},"from_chest":{"wood":3,"stone":0}}
	expect(Sources.digest("craft","bench","20,20",KIT,def,"21,20",id1,zeros)==d1,"digest: only positive debits count")
	var def2:=def.duplicate(true)
	def2["yield"]=2
	var variants:={
		"chest id":Sources.digest("craft","bench","20,20",KIT,def,"21,20",id2,alloc),
		"chest cell":Sources.digest("craft","bench","20,20",KIT,def,"19,20",id1,alloc),
		"station cell":Sources.digest("craft","bench","20,21",KIT,def,"21,20",id1,alloc),
		"station kind":Sources.digest("craft","stove","20,20",KIT,def,"21,20",id1,alloc),
		"split":Sources.digest("craft","bench","20,20",KIT,def,"21,20",id1,{"from_backpack":{"wood":4,"stone":4},"from_chest":{"wood":4}}),
		"recipe id":Sources.digest("craft","bench","20,20","kiln_kit",def,"21,20",id1,alloc),
		"recipe definition":Sources.digest("craft","bench","20,20",KIT,def2,"21,20",id1,alloc),
		"action":Sources.digest("queue_cook","bench","20,20",KIT,def,"21,20",id1,alloc),
	}
	for label in variants:expect(variants[label]!=d1,"digest: changes with "+label)
	var soup:Dictionary=World.RECIPES.soup
	var sa:={"from_backpack":{"radish":1},"from_chest":{"radish":1}}
	expect(Sources.digest("cook","stove","20,20","soup",soup,"21,20",id1,sa)==Sources.digest("queue_cook","stove","20,20","soup",soup,"21,20",id1,sa),"digest: cook normalised to queue_cook")
	var plank:Dictionary=World.INDUSTRY.PROCESS.plank
	var pa:={"from_backpack":{"wood":2},"from_chest":{"wood":2}}
	expect(Sources.digest("start_processing","sawmill","20,20","plank",plank,"21,20",id1,pa)==Sources.digest("queue_processing","sawmill","20,20","plank",plank,"21,20",id1,pa),"digest: start_processing normalised to queue_processing")
	expect(Sources.encode(KIT,"21,20",id1,d1)==KIT+"|21,20|"+id1+"|"+d1,"encode: recipe|box_cell|box_id|digest")
	var longest:=0
	for catalog in [World.CRAFT,World.RECIPES,World.INDUSTRY.PROCESS]:
		for rid in catalog:longest=maxi(longest,Sources.encode(rid,"79,59",id1,d1).to_ascii_buffer().size())
	expect(longest<=96,"encode: every real recipe fits the 96-byte wire bound")
	# Synthetic object layer (FIXTURE dictionary, not a World).
	var objs:={
		"20,20":{"type":"bench","owner":A,"items":{}},
		"20,19":{"type":"chest","owner":B,"items":{}},
		"19,20":{"type":"private_chest","owner":A,"items":{},"box_id":id1},
		"21,20":{"type":"private_chest","owner":B,"items":{}},
		"20,21":{"type":"chest","owner":A,"items":{},"box_id":id2},
		"21,21":{"type":"chest","owner":A,"items":{}},
		"22,20":{"type":"chest","owner":A,"items":{}},
		"18,20":{"type":"bed","owner":A,"items":{}},
	}
	var frozen:=var_to_str(objs)
	var ca:Array=Sources.candidates(objs,A,Vector2i(20,20))
	expect(ca==[{"cell":"20,19","type":"chest","id":""},{"cell":"19,20","type":"private_chest","id":id1},{"cell":"20,21","type":"chest","id":id2}],"candidates(A): cardinal shared + own private, y/x order, missing id empty; got "+str(ca))
	var cb:Array=Sources.candidates(objs,B,Vector2i(20,20))
	expect(cb==[{"cell":"20,19","type":"chest","id":""},{"cell":"21,20","type":"private_chest","id":""},{"cell":"20,21","type":"chest","id":id2}],"candidates(B): foreign private excluded, own private included; got "+str(cb))
	expect(var_to_str(objs)==frozen,"candidates: pure, never mutates the layer")

func test_bench_shared() -> void:
	var t:="bench"
	var w=new_world()
	var o:=layout(w,"bench",A)
	var e:=o+RIGHT
	put_box(w,e,"chest",A,{"wood":10})
	expect(not obj(w,e).has("box_id"),t+": fixture chest starts without box_id")
	set_inv(w,B,{"stone":4})
	refuse(w,B,"craft",o,KIT,t+": plain recipe stays backpack-only next to a stocked chest")
	set_inv(w,B,{"wood":8,"stone":4})
	must(w,B,"craft",o,KIT,t+": plain recipe still crafts from the backpack")
	expect(held(w,B,"wood")==0 and held(w,B,KIT)==1 and stock(w,e,"wood")==10 and not obj(w,e).has("box_id"),t+": plain craft never touches the chest or its identity")
	set_inv(w,B,{"wood":5,"stone":4})
	refuse(w,B,"craft",o,quote(w,B,"craft",o,KIT,e).extra,t+": sourced call on an unprepared chest (empty id) refused")
	var r1:=must(w,B,"prepare_material_box",o,World.key(e),t+": member B prepares A's shared chest at A's bench","prep-bench")
	var id:=bid(w,e)
	expect(hex32(id) and r1.get("source_cell")==World.key(e) and r1.get("source_id")==id,t+": prepare assigns and returns a lowercase 32-hex box_id")
	expect(do(w,B,"prepare_material_box",o,World.key(e),"prep-bench")==r1,t+": prepare receipt replay identical")
	var r2:=must(w,A,"prepare_material_box",o,World.key(e),t+": owner prepares again")
	expect(bid(w,e)==id and r2.get("source_id")==id and stock(w,e,"wood")==10,t+": prepare is idempotent, keeps the existing id")
	var q:=quote(w,B,"craft",o,KIT,e)
	expect(q.plan.get("ok")==true and q.plan.get("from_backpack")=={"wood":5,"stone":4} and q.plan.get("from_chest")=={"wood":3},t+": plan backpack first, chest only the shortage")
	var r:=must(w,B,"craft",o,q.extra,t+": B sourced craft (mixed split)","craft-bench")
	expect(held(w,B,"wood")==0 and held(w,B,"stone")==0 and held(w,B,KIT)==1,t+": B paid its backpack share, received the kit")
	expect(stock(w,e,"wood")==7,t+": chest debited exactly its 3 wood share")
	sourced_meta(r,e,q,t+": B craft")
	var replay:=do(w,B,"craft",o,q.extra,"craft-bench")
	expect(replay==r and held(w,B,KIT)==1 and stock(w,e,"wood")==7,t+": submit twice -> receipt replay, debited once")
	set_inv(w,A,{"wood":8,"stone":4})
	var qa:=quote(w,A,"craft",o,KIT,e)
	expect(qa.plan.get("ok")==true and (qa.plan.get("from_chest",{"x":1}) as Dictionary).is_empty(),t+": backpack covers recipe -> empty chest share")
	must(w,A,"craft",o,qa.extra,t+": owner A sourced craft")
	expect(held(w,A,"wood")==0 and held(w,A,KIT)==1 and stock(w,e,"wood")==7,t+": chest untouched when the backpack covers everything")
	set_inv(w,B,{"stone":4})
	var qm:=quote(w,B,"craft",o,KIT,e)
	expect(qm.plan.get("ok")==false and qm.plan.get("missing")=={"wood":1},t+": plan reports the exact shortage")
	refuse(w,B,"craft",o,qm.extra,t+": missing material refused, nothing charged")
	set_inv(w,B,{"wood":5,"stone":4,KIT:CAP})
	refuse(w,B,"craft",o,quote(w,B,"craft",o,KIT,e).extra,t+": output at item cap refused before any debit")

func test_stove_shared() -> void:
	var t:="stove"
	var w=new_world()
	var o:=layout(w,"stove",A)
	var west:=o+LEFT
	put_box(w,west,"chest",B,{"radish":5})
	set_inv(w,A,{"radish":1})
	prep(w,A,o,west,t+": stove owner A prepares member B's shared chest")
	var q:=quote(w,A,"cook",o,"soup",west)
	expect(q.digest==quote(w,A,"queue_cook",o,"soup",west).digest,t+": cook quote digest equals queue_cook digest")
	var r:=must(w,A,"cook",o,q.extra,t+": sourced cook")
	expect(obj(w,o).has("cooking") and not obj(w,o).has("job"),t+": sourced cook uses the queue path, never a legacy job")
	expect(held(w,A,"radish")==0 and stock(w,west,"radish")==4,t+": A paid 1, chest paid 1")
	sourced_meta(r,west,q,t+": cook")
	var c:=queue_of(w,o,"cooking")
	expect(c.get("active",{}).get("ingredients")=={"radish":2},t+": queued record stores the full recipe cost")
	set_inv(w,B,{})
	var qb:=quote(w,B,"queue_cook",o,"soup",west)
	expect(qb.plan.get("from_chest")=={"radish":2} and (qb.plan.get("from_backpack",{"x":1}) as Dictionary).is_empty(),t+": B's split is chest only")
	must(w,B,"queue_cook",o,qb.extra,t+": B queues on A's stove from the shared chest")
	c=queue_of(w,o,"cooking")
	expect(stock(w,west,"radish")==2 and all_ids(c).size()==2,t+": chest paid 2, two jobs queued")
	var b_job:=str(ids_of(c.get("waiting",[])).front()) if ids_of(c.get("waiting",[])).size()==1 else ""
	var rc:=must(w,A,"cancel_cook",o,"",t+": A cancels its active sourced job")
	expect(held(w,A,"radish")==2 and stock(w,west,"radish")==2 and rc.get("refunded")=={"radish":2},t+": full stored cost refunded to submitter backpack, chest unchanged")
	expect(w.step(11.0,true),t+": B's job completes")
	expect(ids_of(queue_of(w,o,"cooking").get("ready",[]))==[b_job],t+": B's job ready")
	refuse(w,B,"cancel_queued_cook",o,b_job,t+": ready sourced job cannot be cancelled")
	refuse(w,B,"cancel_cook",o,"",t+": nothing active to cancel once ready")
	must(w,A,"claim_cook",o,"",t+": any member claims")
	expect(held(w,A,"soup")==2 and stock(w,west,"radish")==2,t+": claim credits the claimer, chest unchanged")
	print("FIXTURE %s: stove race sets shared chest radish=1, A and B hold 1 each"%LABEL)
	items(w,west)["radish"]=1
	set_inv(w,A,{"radish":1})
	set_inv(w,B,{"radish":1})
	var ra:=quote(w,A,"queue_cook",o,"soup",west)
	var rb:=quote(w,B,"queue_cook",o,"soup",west)
	expect(ra.plan.get("from_chest")=={"radish":1} and rb.plan.get("from_chest")=={"radish":1},t+": both quotes count on the last shared radish")
	must(w,A,"queue_cook",o,ra.extra,t+": A wins the shared stock race")
	refuse(w,B,"queue_cook",o,rb.extra,t+": B's quote over drained shared stock rejected")
	expect(held(w,B,"radish")==1 and stock(w,west,"radish")==0,t+": loser keeps its backpack, chest not over-drawn")
	expect(quote(w,B,"queue_cook",o,"soup",west).plan.get("ok")==false,t+": B's requote shows the shortage")
	var o2:=layout(w,"stove",B)
	put_box(w,o2+UP,"chest",B,{"radish":9})
	set_inv(w,B,{"radish":2})
	must(w,B,"cook",o2,"soup",t+": plain cook on an untouched stove")
	expect(obj(w,o2).has("job") and not obj(w,o2).has("cooking") and held(w,B,"radish")==0 and stock(w,o2+UP,"radish")==9 and not obj(w,o2+UP).has("box_id"),t+": plain cook keeps the legacy job, backpack only")

func test_processing_owner_only() -> void:
	var t:="sawmill"
	var w=new_world()
	var s:=layout(w,"sawmill",A)
	var n:=s+UP
	put_box(w,n,"chest",A,{"wood":100})
	refuse(w,B,"prepare_material_box",s,World.key(n),t+": non-owner cannot prepare at A's sawmill")
	expect(not obj(w,n).has("box_id"),t+": station ownership checked before identity assignment")
	prep(w,A,s,n,t+": owner prepares")
	set_inv(w,B,{"wood":4})
	refuse(w,B,"queue_processing",s,quote(w,B,"queue_processing",s,"plank",n).extra,t+": non-owner sourced queue refused even with valid id/digest")
	set_inv(w,A,{"wood":2})
	var q:=quote(w,A,"start_processing",s,"plank",n)
	expect(q.digest==quote(w,A,"queue_processing",s,"plank",n).digest,t+": start_processing digest normalised")
	var r:=must(w,A,"start_processing",s,q.extra,t+": sourced start_processing")
	expect(obj(w,s).has("processing") and not obj(w,s).has("job"),t+": sourced start uses the queue path, never a legacy job")
	expect(held(w,A,"wood")==0 and stock(w,n,"wood")==98,t+": A paid 2, chest paid 2")
	sourced_meta(r,n,q,t+": start")
	var first:=all_ids(queue_of(w,s,"processing"))
	var ok_all:=true
	for i in 9:
		var qi:=quote(w,A,"queue_processing",s,"plank",n)
		if do(w,A,"queue_processing",s,qi.extra).get("ok")!=true:ok_all=false
	expect(ok_all,t+": nine more sourced jobs accepted")
	var p:=queue_of(w,s,"processing")
	expect(all_ids(p).size()==10 and stock(w,n,"wood")==62 and held(w,A,"wood")==0,t+": ten jobs, 36 more wood from the chest")
	refuse(w,A,"queue_processing",s,quote(w,A,"queue_processing",s,"plank",n).extra,t+": eleventh sourced job refused (queue full), chest unchanged")
	var last:=str(ids_of(p.waiting).back())
	var rc:=must(w,A,"cancel_processing_job",s,last,t+": cancel a waiting sourced job")
	expect(held(w,A,"wood")==4 and stock(w,n,"wood")==62 and rc.get("refunded")=={"wood":4},t+": full stored cost to A's backpack, chest unchanged")
	expect(w.step(12.5,true),t+": first job completes")
	var ready:=ids_of(queue_of(w,s,"processing").get("ready",[]))
	expect(first.size()==1 and ready==first,t+": first sourced job ready")
	if ready.size()==1:refuse(w,A,"cancel_processing_job",s,ready[0],t+": ready job cannot be cancelled")
	var k:=layout(w,"charcoal_kiln",A)
	var kd:=k+DOWN
	put_box(w,kd,"private_chest",A,{"wood":3})
	prep(w,A,k,kd,"kiln: owner explicitly prepares own private chest")
	set_inv(w,A,{"wood":1})
	must(w,A,"queue_processing",k,quote(w,A,"queue_processing",k,"charcoal",kd).extra,"kiln: sourced charcoal")
	expect(held(w,A,"wood")==0 and stock(w,kd,"wood")==0 and queue_of(w,k,"processing").get("active",{}).get("kind")=="charcoal","kiln: 1 from backpack + 3 from own private chest")
	set_inv(w,B,{"wood":4})
	refuse(w,B,"queue_processing",k,quote(w,B,"queue_processing",k,"charcoal",kd).extra,"kiln: non-owner refused")
	var bs:=layout(w,"sawmill",B)
	var bl:=bs+LEFT
	put_box(w,bl,"chest",A,{"wood":8})
	prep(w,B,bs,bl,"own station: B prepares A's shared chest at B's sawmill")
	set_inv(w,B,{})
	must(w,B,"queue_processing",bs,quote(w,B,"queue_processing",bs,"plank",bl).extra,"own station: B queues from A's shared chest")
	expect(stock(w,bl,"wood")==4 and queue_of(w,bs,"processing").get("active",{}).get("owner")==B,"own station: shared chest paid, job owned by B")

func test_private_and_adjacency() -> void:
	var t:="access"
	var w=new_world()
	var o:=layout(w,"bench",A)
	var full:={"wood":8,"stone":4}
	var n:=o+UP
	var e:=o+RIGHT
	var s:=o+DOWN
	var wb:=o+LEFT
	var diag:=o+Vector2i(-1,-1)
	var far:=o+Vector2i(2,0)
	put_box(w,n,"private_chest",A,full)
	put_box(w,e,"chest",A,full)
	put_box(w,s,"private_chest",B,full)
	put_box(w,diag,"chest",A,full)
	put_box(w,far,"chest",A,full)
	w.state.objects[World.key(wb)]={"type":"bed","owner":A,"items":{}}
	expect(Sources.candidates(w.state.objects,A,o)==[{"cell":World.key(n),"type":"private_chest","id":""},{"cell":World.key(e),"type":"chest","id":""}],t+": live candidates(A) cardinal only, own private + shared")
	expect(Sources.candidates(w.state.objects,B,o)==[{"cell":World.key(e),"type":"chest","id":""},{"cell":World.key(s),"type":"private_chest","id":""}],t+": live candidates(B)")
	var idn:=prep(w,A,o,n,t+": A explicitly prepares own private chest")
	var rb:=refuse(w,B,"prepare_material_box",o,World.key(n),t+": B cannot prepare A's private chest")
	expect(not var_to_str(rb).contains(idn),t+": refusal never reveals the private box_id")
	refuse(w,A,"prepare_material_box",o,World.key(s),t+": A cannot prepare B's private chest")
	for c in [diag,far]:
		refuse(w,A,"prepare_material_box",o,World.key(c),t+": non-cardinal-adjacent chest %s refused"%World.key(c-o))
	refuse(w,A,"prepare_material_box",o,World.key(wb),t+": adjacent non-box object refused")
	refuse(w,A,"prepare_material_box",e,World.key(o),t+": prepare on a non-station cell refused")
	refuse(w,A,"prepare_material_box",o,"not-a-cell",t+": malformed box cell refused")
	here=Vector2(o)+Vector2(6.5,0.5)
	refuse(w,A,"prepare_material_box",o,World.key(e),t+": actor out of station reach refused")
	go(o)
	var none:=true
	for c in [s,diag,far,e]:
		if obj(w,c).has("box_id"):none=false
	expect(none,t+": rejected prepares assigned no identity")
	var ide:=prep(w,A,o,e,t+": A prepares shared chest")
	var ids:=prep(w,B,o,s,t+": B prepares own private chest")
	expect(idn!=ide and ide!=ids and idn!=ids,t+": every prepared box has a distinct id")
	set_inv(w,A,{})
	refuse(w,A,"craft",o,KIT,t+": own private chest never auto-selected by plain craft")
	set_inv(w,B,{})
	refuse(w,B,"craft",o,quote(w,B,"craft",o,KIT,n).extra,t+": foreign private chest refused even with its leaked id")
	var qn:=quote(w,A,"craft",o,KIT,n)
	must(w,A,"craft",o,qn.extra,t+": A crafts from own explicitly selected private chest")
	expect(stock(w,n,"wood")==0 and stock(w,n,"stone")==0 and held(w,A,KIT)==1,t+": selected private chest paid everything")
	var untouched:=true
	for c in [e,s,diag,far]:
		if items(w,c)!=full:untouched=false
	expect(untouched,t+": only the one selected chest was debited")
	var qe:=quote(w,A,"craft",o,KIT,e)
	refuse(w,A,"craft",o,qe.extra+"|"+World.key(s)+"|"+ids,t+": two boxes in one request refused")
	refuse(w,A,"craft",o,Sources.encode(KIT,World.key(e),ids,qe.digest),t+": cell/id mismatch refused")
	refuse(w,A,"craft",o,quote(w,A,"craft",o,KIT,e,ids).extra,t+": another box's id never adopted, even with a matching digest")
	var aside:=o+Vector2i(2,1)
	must(w,A,"move_object",e,World.key(aside),t+": A moves the shared chest out of adjacency")
	expect(bid(w,aside)==ide,t+": moved chest keeps its id")
	refuse(w,A,"craft",o,quote(w,A,"craft",o,KIT,aside).extra,t+": moved non-adjacent chest refused")
	refuse(w,A,"craft",o,qe.extra,t+": quote naming the vacated cell refused")
	refuse(w,A,"prepare_material_box",o,World.key(aside),t+": prepare of the moved non-adjacent chest refused")

func test_move_replace() -> void:
	var t:="move"
	var w=new_world()
	var o:=layout(w,"bench",A)
	var e:=o+RIGHT
	var s:=o+DOWN
	var n:=o+UP
	put_box(w,e,"chest",A,{"wood":10})
	var id:=prep(w,A,o,e,t+": prepare")
	set_inv(w,A,{"wood":5,"stone":4})
	var old:=quote(w,A,"craft",o,KIT,e)
	must(w,A,"move_object",e,World.key(s),t+": owner moves the prepared chest to another cardinal side")
	expect(bid(w,s)==id and not w.state.objects.has(World.key(e)) and stock(w,s,"wood")==10,t+": id and items travel with the chest")
	refuse(w,A,"craft",o,old.extra,t+": quote naming the old cell refused")
	var q:=quote(w,A,"craft",o,KIT,s)
	must(w,A,"craft",o,q.extra,t+": sourced craft at the new cell")
	expect(stock(w,s,"wood")==7 and held(w,A,KIT)==1,t+": moved chest paid its share")
	var emptied:=true
	for i in 7:
		if do(w,A,"withdraw",s,"wood").get("ok")!=true:emptied=false
	expect(emptied and stock(w,s,"wood")==0 and held(w,A,"wood")==7,t+": chest emptied through real withdraws")
	must(w,A,"remove",s,"",t+": remove the empty chest")
	expect(not w.state.objects.has(World.key(s)) and held(w,A,"wood")==27,t+": removed, build cost refunded")
	must(w,A,"build",s,"chest",t+": real build of a replacement chest on the same cell")
	expect(obj(w,s).get("type")=="chest" and not obj(w,s).has("box_id"),t+": newly built chest has no box_id")
	set_inv(w,A,{"wood":5,"stone":4})
	items(w,s)["wood"]=10
	print("FIXTURE %s: replacement chest stocked with 10 wood directly"%LABEL)
	refuse(w,A,"craft",o,quote(w,A,"craft",o,KIT,s,id).extra,t+": replacement chest never adopts the old id")
	var id2:=prep(w,A,o,s,t+": prepare replacement")
	expect(id2!=id,t+": replacement receives a fresh id")
	put_box(w,n,"chest",B,{})
	var id3:=prep(w,B,o,n,t+": B prepares another chest")
	expect(id3!=id and id3!=id2,t+": ids unique across live boxes")

func test_stale_and_wire() -> void:
	var t:="stale"
	var w=new_world()
	var o:=layout(w,"bench",A)
	var e:=o+RIGHT
	put_box(w,e,"chest",A,{"wood":10})
	var id:=prep(w,A,o,e,t+": prepare")
	set_inv(w,A,{"wood":5,"stone":4})
	var q:=quote(w,A,"craft",o,KIT,e)
	must(w,A,"withdraw",e,"wood",t+": A withdraws 1 wood (split becomes 6/2)")
	var r:=refuse(w,A,"craft",o,q.extra,t+": changed split rejected")
	expect(r.get("requote")==true,t+": stale split asks for requote")
	must(w,A,"deposit",e,"wood",t+": A deposits it back (split 5/3 again)")
	set_inv(w,B,{"wood":1,"fiber":1})
	must(w,B,"deposit",e,"fiber",t+": B adds unrelated fiber")
	must(w,B,"deposit",e,"wood",t+": B adds wood beyond the confirmed share")
	expect(stock(w,e,"wood")==11 and stock(w,e,"fiber")==1,t+": chest now 11 wood + 1 fiber")
	var rc:=must(w,A,"craft",o,q.extra,t+": unrelated stock change, same exact split accepted","stale-ok")
	expect(stock(w,e,"wood")==8 and stock(w,e,"fiber")==1 and held(w,A,"wood")==0 and held(w,A,KIT)==1,t+": exactly the confirmed split debited")
	expect(do(w,A,"craft",o,q.extra,"stale-ok")==rc and stock(w,e,"wood")==8 and held(w,A,KIT)==1,t+": replay returns receipt, no second debit")
	# Restock only the test ingredients; retain the kit earned above.
	set_inv(w,A,{"wood":5,"stone":4,KIT:1})
	var q2:=quote(w,A,"craft",o,KIT,e)
	var flipped:String=str(q2.digest).left(15)+("0" if str(q2.digest).right(1)!="0" else "1")
	var r2:=refuse(w,A,"craft",o,Sources.encode(KIT,World.key(e),id,flipped),t+": tampered digest rejected")
	expect(r2.get("requote")==true,t+": digest mismatch asks for requote")
	refuse(w,A,"craft",o,Sources.encode(KIT,World.key(e),id,quote(w,A,"queue_cook",o,"soup",e).digest),t+": digest of another recipe/action rejected")
	refuse(w,A,"craft",o,Sources.encode(KIT,World.key(e),id.to_upper(),q2.digest),t+": uppercase box id rejected")
	refuse(w,A,"craft",o,KIT+"|"+World.key(e)+"|"+id,t+": three-field payload rejected")
	refuse(w,A,"craft",o,q2.extra+"0".repeat(40),t+": oversized payload / long digest rejected")
	refuse(w,A,"craft",o,Sources.encode("no_such_recipe",World.key(e),id,q2.digest),t+": unknown recipe rejected")
	refuse(w,A,"queue_cook",o,quote(w,A,"queue_cook",o,"soup",e).extra,t+": sourced cook at a bench rejected")
	refuse(w,A,"queue_processing",o,quote(w,A,"queue_processing",o,"plank",e).extra,t+": sourced processing at a bench rejected")
	expect(stock(w,e,"wood")==8 and held(w,A,"wood")==5 and held(w,A,KIT)==1,t+": every wire rejection left stock untouched")

func test_cap_overflow() -> void:
	var t:="cap"
	var w=new_world()
	var s:=layout(w,"sawmill",A)
	var e:=s+RIGHT
	put_box(w,e,"chest",A,{"wood":CAP})
	prep(w,A,s,e,t+": prepare a chest holding exactly the item cap")
	set_inv(w,A,{"wood":2})
	var q:=quote(w,A,"queue_processing",s,"plank",e)
	expect(q.plan.get("ok")==true and q.plan.get("from_chest")=={"wood":2} and int(q.plan.get("supplied_inventory",{}).get("wood",-1))==4,t+": top-up covers only the shortage")
	must(w,A,"queue_processing",s,q.extra,t+": sourced queue from a capped chest")
	expect(held(w,A,"wood")==0 and stock(w,e,"wood")==CAP-2,t+": chest paid 2, backpack 2")
	var job:=str(queue_of(w,s,"processing").get("active",{}).get("id",""))
	print("FIXTURE %s: backpack wood set to CAP-1 to force refund overflow"%LABEL)
	w.state.players[A].inventory["wood"]=CAP-1
	refuse(w,A,"cancel_processing_job",s,job,t+": refund that would overflow the backpack refused")
	w.state.players[A].inventory["wood"]=CAP-4
	must(w,A,"cancel_processing_job",s,job,t+": refund to exactly the cap")
	expect(held(w,A,"wood")==CAP and stock(w,e,"wood")==CAP-2,t+": full refund to backpack, never spilled back into the chest")
	var q2:=quote(w,A,"queue_processing",s,"plank",e)
	expect(q2.plan.get("ok")==true and (q2.plan.get("from_chest",{"x":1}) as Dictionary).is_empty(),t+": capped backpack covers it, chest share empty")
	must(w,A,"queue_processing",s,q2.extra,t+": capped backpack + capped chest never overflow")
	expect(held(w,A,"wood")==CAP-4 and stock(w,e,"wood")==CAP-2,t+": only the backpack paid")

func test_save_failure() -> void:
	var t:="savefail"
	var w=new_world()
	var o:=layout(w,"stove",A)
	var wb:=o+LEFT
	put_box(w,wb,"chest",A,{"radish":4})
	set_inv(w,A,{"radish":1})
	var good:String=w.save_path
	var bad:=dir.path_join("missing-"+Crypto.new().generate_random_bytes(4).hex_encode()).path_join("world.json")
	expect(not DirAccess.dir_exists_absolute(bad.get_base_dir()),t+": real unwritable path (parent directory absent)")
	w.save_path=bad
	broken_act(w,A,"prepare_material_box",o,World.key(wb),"sf-prep",t+": prepare")
	expect(not obj(w,wb).has("box_id"),t+": no id survives a failed save")
	w.save_path=good
	var id:=prep(w,A,o,wb,t+": fresh prepare after recovery")
	var q:=quote(w,A,"queue_cook",o,"soup",wb)
	w.save_path=bad
	broken_act(w,A,"queue_cook",o,q.extra,"sf-cook",t+": sourced queue_cook")
	broken_act(w,A,"cook",o,q.extra,"sf-cook2",t+": sourced cook")
	expect(held(w,A,"radish")==1 and stock(w,wb,"radish")==4 and not obj(w,wb).is_empty() and not obj(w,o).has("cooking"),t+": backpack, chest and stove all rolled back")
	w.save_path=good
	must(w,A,"queue_cook",o,q.extra,t+": same request id commits after recovery","sf-cook")
	expect(held(w,A,"radish")==0 and stock(w,wb,"radish")==3 and all_ids(queue_of(w,o,"cooking")).size()==1,t+": committed once with the confirmed split")
	var loaded=World.new()
	expect(loaded.load_world(good) and bid(loaded,wb)==id and stock(loaded,wb,"radish")==3,t+": disk holds only the committed state")

func test_save_reload_lazy() -> void:
	var t:="reload"
	var w=new_world()
	var o:=layout(w,"bench",A)
	var e:=o+RIGHT
	var untouched:=o+UP
	put_box(w,e,"chest",A,{"wood":10})
	put_box(w,untouched,"private_chest",A,{"wood":1})
	var s:=layout(w,"sawmill",A)
	var sn:=s+DOWN
	put_box(w,sn,"chest",B,{"wood":20})
	go(o)
	set_inv(w,A,{"wood":1})
	must(w,A,"deposit",e,"wood",t+": plain deposit commits a save")
	var text:=FileAccess.get_file_as_string(w.save_path)
	var doc=JSON.parse_string(text)
	expect(doc is Dictionary and int(doc.get("version",0))==int(Schema.VERSION) and not text.contains("box_id"),t+": no chest was given an id eagerly")
	# Old save: the same real document relabelled version 21 (FIXTURE).
	doc.version=21;doc.erase("public_kitchen")
	doc.erase("flower_nursery")
	doc.regions.erase("tianwei")
	doc.erase("salt_pan")
	doc.regions.erase("beimen")
	var old_path:=dir.path_join("old-v21.json")
	_write(old_path,JSON.stringify(doc))
	var old=World.new()
	expect(old.load_world(old_path),"old: v21 save without box_id loads")
	expect(int(old.state.version)==int(Schema.VERSION),"old: stamped to the current version")
	var clean:=true
	for c in [e,untouched,sn]:
		if obj(old,c).has("box_id"):clean=false
	expect(clean,"old: load injects no box_id")
	var forged=JSON.parse_string(text)
	forged.version=21;forged.erase("public_kitchen")
	forged.erase("flower_nursery")
	forged.regions.erase("tianwei")
	forged.erase("salt_pan")
	forged.regions.erase("beimen")
	forged.objects[World.key(e)]["box_id"]="ab".repeat(16)
	var forged_path:=dir.path_join("old-v21-forged.json")
	_write(forged_path,JSON.stringify(forged))
	expect(not World.new().load_world(forged_path),"old: v21 save carrying box_id rejected")
	attach(old)
	old.add_player(A,"Alice")
	old.add_player(B,"Bob")
	prep(old,A,o,e,"old: explicit prepare after old load")
	expect(not obj(old,untouched).has("box_id") and not obj(old,sn).has("box_id"),"old: only the explicitly prepared chest got an id")
	# Current world: prepare + sourced work, then a real save/reload.
	var ide:=prep(w,A,o,e,t+": prepare bench chest")
	set_inv(w,A,{"wood":5,"stone":4})
	must(w,A,"craft",o,quote(w,A,"craft",o,KIT,e).extra,t+": sourced craft before reload")
	go(s)
	var ids:=prep(w,A,s,sn,t+": A prepares B's shared chest at A's sawmill")
	set_inv(w,A,{})
	for i in 2:must(w,A,"queue_processing",s,quote(w,A,"queue_processing",s,"plank",sn).extra,t+": sourced plank %d"%i)
	var jobs:=all_ids(queue_of(w,s,"processing"))
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),t+": real SaveSchema validation passes")
	attach(loaded)
	loaded.add_player(A,"Alice")
	loaded.add_player(B,"Bob")
	expect(bid(loaded,e)==ide and bid(loaded,sn)==ids and not obj(loaded,untouched).has("box_id"),t+": box ids persisted; unprepared chest still has none")
	expect(stock(loaded,e,"wood")==8 and stock(loaded,sn,"wood")==12 and jobs.size()==2 and all_ids(queue_of(loaded,s,"processing"))==jobs,t+": stock and queue order persisted")
	must(loaded,A,"queue_processing",s,quote(loaded,A,"queue_processing",s,"plank",sn).extra,t+": persisted id works after reload")
	expect(stock(loaded,sn,"wood")==8 and all_ids(queue_of(loaded,s,"processing")).size()==3,t+": third job charged to the chest")
	refuse(loaded,A,"queue_processing",s,quote(loaded,A,"queue_processing",s,"plank",sn,ide).extra,t+": another box's id at this cell refused")
	var again=World.new()
	expect(again.load_world(w.save_path) and all_ids(queue_of(again,s,"processing")).size()==3 and bid(again,sn)==ids and not obj(again,untouched).has("box_id"),t+": second cycle persisted, still lazy")

func test_undo_remote_chest() -> void:
	var t:="undo"
	var w=new_world()
	var o:=layout(w,"bench",B)
	var e:=o+RIGHT
	var s:=o+DOWN
	set_inv(w,A,{"wood":28,"stone":4})
	must(w,A,"build",e,"chest",t+": A builds a chest beside B's bench")
	expect(avail(w),t+": fresh chest build undoable")
	refuse(w,B,"prepare_material_box",o,World.key(o+Vector2i(2,0)),t+": failed prepare of an empty cell")
	expect(avail(w),t+": failed prepare does not invalidate")
	must(w,B,"prepare_material_box",o,World.key(e),t+": B prepares A's new chest")
	expect(not avail(w),t+": prepare of the remote chest closes A's build undo")
	var id:=bid(w,e)
	must(w,A,"move_object",e,World.key(s),t+": A moves the prepared chest")
	expect(avail(w) and bid(w,s)==id,t+": move undoable, id kept")
	var box_snap:=var_to_str(obj(w,s))
	must(w,A,"prepare_material_box",o,World.key(s),t+": idempotent prepare of the moved chest")
	expect(var_to_str(obj(w,s))==box_snap,t+": idempotent prepare leaves the chest byte-identical")
	expect(not avail(w),t+": remote chest marked used even without mutation")
	must(w,A,"move_object",s,World.key(e),t+": move back")
	expect(avail(w),t+": second move undoable")
	box_snap=var_to_str(obj(w,e))
	var q:=quote(w,A,"craft",o,KIT,e)
	expect(q.plan.get("ok")==true and (q.plan.get("from_chest",{"x":1}) as Dictionary).is_empty(),t+": backpack covers the craft")
	must(w,A,"craft",o,q.extra,t+": sourced craft naming the chest")
	expect(var_to_str(obj(w,e))==box_snap and not avail(w),t+": sourced commit marks the remote chest used even with an empty chest share")
