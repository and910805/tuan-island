extends SceneTree
## Blueprint stage two through the real World (docs/blueprint-integration.md,
## 「第二段：World權威報價與原子套用契約」). Not the pure data module.
##
## API under test (implemented by the core worker):
##   World.quote_blueprint(token, raw, origin:Vector2i, turns=0) -> Dictionary
##   World.apply_blueprint(token, nonce, raw, origin:Vector2i, turns, expected_hash) -> Dictionary
##   World.undo_summary(token) / World.act(token, rid, "undo_build", p, id)
##
## Fixtures are explicitly NOT normal play: inventories, kits, unlocks, other
## owners' devices and positions are written directly. Build sites are found
## algorithmically as naturally clear ground (no resource of any kind, not
## protected, not water, not blocked) away from spawn; resources are never
## removed to make room. Undo clocks use a FakeClock, so nothing waits 30 s.
## Each world saves into one new per-run user:// directory that is removed at
## the end; real saves are never touched. Missing API is a counted failure,
## never a skip.
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")
const TRANSIT=preload("res://scripts/transit.gd")
const SCHEMA=preload("res://scripts/save_schema.gd")
const HISTORY=preload("res://scripts/construction_history.gd")
const WATERWORKS=preload("res://scripts/waterworks.gd")

const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const PARK:=World.SPAWN
const QUOTE_KEYS:=["ok","message","cost","mine_refund","others_refund","other_people","roof_add","roof_remove","pieces","problems","hash","undoable"]
const PROBLEM_KEYS:=["kind","reason","x","y"]
## 3x3 floor interior + 5x5 outline (14 walls, 1 window, 1 door) + 1 bed = 26.
const HOUSE_BASE:={"wood":87,"fiber":12,"stone":1}
## Plus 9 automatic roofs (wood 1, fiber 3 each).
const HOUSE_COST:={"wood":96,"fiber":39,"stone":1}

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=9000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks
	func advance(seconds:float) -> void:
		utc+=seconds
		ticks+=int(round(seconds*1000.0))

var checks:=0
var failures:=0
var serial:=0
var dir:=""
var clock:FakeClock

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	dir="user://test-blueprint-world-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var made:=DirAccess.make_dir_recursive_absolute(dir)==OK
	expect(made,"isolated test directory created")
	if not made:
		print("BLUEPRINT_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	var probe=World.new()
	test_contract_constants(probe)
	var ready:bool=probe.has_method("quote_blueprint") and probe.has_method("apply_blueprint") and probe.has_method("undo_summary")
	expect(ready,"World exposes quote_blueprint / apply_blueprint / undo_summary")
	if ready:
		test_house_quote_apply_reload_undo()
		test_undo_blocked_by_other_player()
		test_insufficient_total_including_roof()
		test_nonce_and_hash()
		test_stale_collision()
		test_stale_price_requote()
		test_save_failure_rollback_and_retry()
		test_terrain_and_resources()
		test_range_and_regions()
		test_locked_and_cross_region_limit()
		test_device_aggregate()
		test_floor_ownership_and_layer_order()
		test_player_collision()
		test_conveyor_settings_and_turns()
		test_style_round_trip()
		test_offline_owner_roof_refund_and_undo()
	cleanup()
	print("BLUEPRINT_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

## Removes only this run's own directory (created above, so every file in it is ours).
func cleanup() -> void:
	expect(not DirAccess.dir_exists_absolute(dir+"/missing-subdir"),"failed save never created the missing directory")
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	expect(DirAccess.remove_absolute(dir)==OK,"isolated test directory removed (fails if anything unexpected remains)")

# ---------------------------------------------------------------- fixtures --

func attach(w,c:FakeClock) -> void:
	w.set("undo_clock_utc",Callable(c,"now_utc"))
	w.set("undo_clock_ticks",Callable(c,"now_ticks"))

func new_world():
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	# Explicit fixture stock, not normal-play balances.
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":100,"fiber":300}
	serial+=1
	w.save_path=dir+"/world-%d.json"%serial
	clock=FakeClock.new()
	attach(w,clock)
	return w

## A fresh process: new World from disk, same fake clock, both players rejoin.
func reload(path:String):
	var loaded=World.new()
	var ok:bool=loaded.load_world(path)
	expect(ok,"saved world reloads: "+path)
	attach(loaded,clock)
	loaded.add_player(A,"Alice")
	loaded.add_player(B,"Bob")
	return loaded

func nonce() -> String:
	serial+=1
	return String.num_int64(serial+0x5000,16).lpad(32,"0")

func piece(kind:String,x:int,y:int) -> Dictionary:
	return {"kind":kind,"x":x,"y":y}

func bp(label:String,width:int,height:int,pieces:Array) -> Dictionary:
	return {"version":1,"name":label,"width":width,"height":height,"pieces":pieces}

func house_raw() -> Dictionary:
	var pieces:=[]
	for y in range(1,4):
		for x in range(1,4):pieces.append(piece("floor",x,y))
	for c in outline(Vector2i(5,5)):
		var kind:="wall"
		if c==Vector2i(2,0):kind="window"
		elif c==Vector2i(2,4):kind="door"
		pieces.append(piece(kind,c.x,c.y))
	pieces.append(piece("bed",1,1))
	return bp("小屋",5,5,pieces)

## Border cells of a w×h rectangle (corners included), local coordinates.
func outline(size:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for y in size.y:
		for x in size.x:
			if x==0 or y==0 or x==size.x-1 or y==size.y-1:out.append(Vector2i(x,y))
	return out

## Cardinal ring around a world rectangle (corners excluded), like room tests.
func ring(o:Vector2i,size:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for x in range(o.x,o.x+size.x):
		out.append(Vector2i(x,o.y-1))
		out.append(Vector2i(x,o.y+size.y))
	for y in range(o.y,o.y+size.y):
		out.append(Vector2i(o.x-1,y))
		out.append(Vector2i(o.x+size.x,y))
	return out

func layer_of(kind:String) -> String:
	if kind in ["floor","path"]:return "ground"
	if kind=="roof":return "roofs"
	return "objects"

func clear_cell(w,c:Vector2i) -> bool:
	if not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":return false
	var k:=World.key(c)
	for f in ["objects","ground","roofs","crops","forest"]:
		if w.state[f].has(k):return false
	return true

func site_ok(w,o:Vector2i,size:Vector2i) -> bool:
	for y in range(o.y,o.y+size.y):
		if not clear_cell(w,Vector2i(o.x-1,y)):return false
		for x in range(o.x,o.x+size.x):
			if not clear_cell(w,Vector2i(x,y)):return false
	return true

## Naturally clear `size` rectangle plus a clear standing column at x-1, at
## least 3 cells away from spawn/park and from every Rect2i in `avoid`.
## Natural resources are never removed to make room.
func find_site(w,region:String,size:Vector2i,avoid:Array=[]) -> Vector2i:
	w.switch_region(region)
	var park:=Vector2i(PARK) if region==HOME else Vector2i(REGIONS.spawn(region))
	var found:=Vector2i(-1,-1)
	for oy in range(2,REGIONS.SIZE.y-size.y-2):
		for ox in range(3,REGIONS.SIZE.x-size.x-2):
			var o:=Vector2i(ox,oy)
			var zone:=Rect2i(o-Vector2i(3,3),size+Vector2i(6,6))
			if zone.has_point(park) or zone.has_point(Vector2i(World.SPAWN)):continue
			var hit:=false
			for r in avoid:
				if zone.intersects(r):
					hit=true
					break
			if hit:continue
			if site_ok(w,o,size):
				found=o
				break
		if found.x>=0:break
	w.switch_region(HOME)
	expect(found.x>=0,"found naturally clear %s site in %s"%[size,region])
	return found

func edge_pred(w,label:String,p:Vector2i) -> bool:
	match label:
		"tree":return w.resource(p)=="tree"
		"rock":return w.resource(p)=="rock"
		"water":return w.water(p) and not w.protected(p)
		"protected":return w.protected(p) and w.is_land(p) and not w.water(p)
	return false

## Home cell c that is clear (as is its standing neighbour c-1) whose right
## neighbour c+1 is the requested obstacle.
func find_edge(w,label:String) -> Vector2i:
	for y in range(1,REGIONS.SIZE.y-1):
		for x in range(2,REGIONS.SIZE.x-1):
			var c:=Vector2i(x,y)
			if Vector2(c).distance_to(PARK)<4.0:continue
			if clear_cell(w,c) and clear_cell(w,c+Vector2i.LEFT) and edge_pred(w,label,c+Vector2i.RIGHT):return c
	expect(false,"found a clear cell next to "+label)
	return Vector2i(-1,-1)

## Standing point in the clear column left of a site, 1.0 from the origin centre.
func stand(o:Vector2i) -> Vector2:
	return Vector2(o.x-0.5,o.y+0.5)

func pose(w,token:String,at:Vector2) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else PARK
		person.x=spot.x
		person.y=spot.y

func leak_free(value,label:String) -> void:
	var text:=var_to_str(value)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks tokens")

func must(w,token:String,action:String,p:Vector2i,extra:String,label:String,at:Vector2) -> Dictionary:
	pose(w,token,at)
	serial+=1
	var r:Dictionary=w.act(token,"req-%d"%serial,action,p,extra)
	expect(r.get("ok",false)==true,label+": "+str(r.get("message","")))
	return r

func full(w) -> String:
	return var_to_str(w.state)

## Everything except the opaque server-only history.
func view(w) -> String:
	var copy:Dictionary=w.state.duplicate(true)
	copy.erase("construction")
	return var_to_str(copy)

func ints(d) -> Dictionary:
	if not d is Dictionary:return {"<invalid>":-1}
	var out:={}
	for k in d:
		var v=d[k]
		if not (v is int or v is float):return {"<invalid>":-1}
		if int(v)!=0:out[str(k)]=int(v)
	return out

func inv(w,token:String) -> Dictionary:
	return ints(w.state.players[token].inventory)

func plus(a:Dictionary,b:Dictionary,sign:int=1) -> Dictionary:
	var out:=ints(a)
	for k in b:
		if k=="name":continue
		out[k]=int(out.get(k,0))+sign*int(b[k])
		if int(out[k])==0:out.erase(k)
	return out

func minus(a:Dictionary,b:Dictionary) -> Dictionary:
	return plus(a,b,-1)

func times(recipe:Dictionary,n:int) -> Dictionary:
	var out:={}
	for k in recipe:
		if k!="name":out[k]=int(recipe[k])*n
	return out

func recipe_total(raw:Dictionary) -> Dictionary:
	var out:={}
	for p in raw.pieces:out=plus(out,World.BUILD[p.kind])
	return out

func builds(w,token:String) -> int:
	return int(w.state.players[token].get("builds",0))

func auto_roofs(w,owner:String) -> int:
	var n:=0
	for roof in w.state.roofs.values():
		if World.is_auto_roof(roof) and roof.get("owner")==owner:n+=1
	return n

func shape(q:Dictionary,label:String) -> void:
	for k in QUOTE_KEYS:expect(q.has(k),label+": quote field "+k)
	expect(q.get("cost") is Dictionary and q.get("mine_refund") is Dictionary and q.get("others_refund") is Dictionary,label+": material fields are dictionaries")
	expect(q.get("hash") is String and q.get("problems") is Array,label+": hash string, problems array")
	if q.get("problems") is Array:
		for p in q.problems:
			var good:bool=p is Dictionary and p.size()==PROBLEM_KEYS.size()
			if good:
				for k in PROBLEM_KEYS:good=good and p.has(k)
			expect(good,label+": problem has exactly x/y/kind/reason: "+str(p))

func quote(w,token:String,raw,origin:Vector2i,turns=0) -> Dictionary:
	var q=w.call("quote_blueprint",token,raw,origin,turns)
	expect(q is Dictionary,"quote returns a Dictionary")
	expect(w._region==HOME,"quote leaves home orientation")
	if not q is Dictionary:return {}
	shape(q,"quote")
	leak_free(q,"quote")
	return q

func apply(w,token:String,n:String,raw,origin:Vector2i,turns,h:String) -> Dictionary:
	var r=w.call("apply_blueprint",token,n,raw,origin,turns,h)
	expect(r is Dictionary,"apply returns a Dictionary")
	expect(w._region==HOME,"apply leaves home orientation")
	if not r is Dictionary:return {}
	leak_free(r,"apply")
	return r

## Rejected apply: ok=false with a reason and the ENTIRE state unchanged.
func refuse_apply(w,token:String,raw,origin:Vector2i,turns,h:String,label:String,n:Variant=null) -> Dictionary:
	if n==null:n=nonce()
	var snap:=full(w)
	var r:=apply(w,token,n,raw,origin,turns,h)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": apply rejected with a reason, got "+str(r))
	expect(full(w)==snap,label+": entire state unchanged")
	return r

func has_problem(q:Dictionary,world_cell:Vector2i,local:Vector2i) -> bool:
	var list=q.get("problems",[])
	if not list is Array:return false
	for p in list:
		if not p is Dictionary:continue
		var at:=Vector2i(int(p.get("x",-99999)),int(p.get("y",-99999)))
		if at==world_cell or at==local:return true
	return false

func summary(w,token:String) -> Dictionary:
	var s=w.call("undo_summary",token)
	expect(s is Dictionary,"undo_summary returns a Dictionary")
	return s if s is Dictionary else {}

func check_house(w,o:Vector2i,owner:String,label:String) -> void:
	for p in house_raw().pieces:
		var c:=o+Vector2i(int(p.x),int(p.y))
		var obj=w.state[layer_of(p.kind)].get(World.key(c))
		expect(obj is Dictionary and obj.get("type")==p.kind and obj.get("owner")==owner,label+": %s at %s"%[p.kind,c])
	var door=w.state.objects.get(World.key(o+Vector2i(2,4)),{})
	expect(door.get("open")==false,label+": door starts closed")
	for y in 5:
		for x in 5:
			var c:=o+Vector2i(x,y)
			var roof=w.state.roofs.get(World.key(c))
			if x>=1 and x<=3 and y>=1 and y<=3:
				expect(World.is_auto_roof(roof) and roof.get("owner")==owner and roof.get("type")=="roof",label+": auto roof over %s"%c)
			else:
				expect(roof==null,label+": no roof on outline %s"%c)

func house_empty(w,o:Vector2i) -> bool:
	for y in 5:
		for x in 5:
			var k:=World.key(o+Vector2i(x,y))
			for f in ["ground","objects","roofs"]:
				if w.state[f].has(k):return false
	return true

func house_world() -> Array:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(5,5))
	if o.x>=0:pose(w,A,stand(o))
	return [w,o]

# ------------------------------------------------------------------- tests --

func test_contract_constants(probe) -> void:
	expect(int(probe.state.version)==26,"fresh world version is 20, got %s"%str(probe.state.version))
	expect(int(SCHEMA.VERSION)==26,"save schema VERSION is 20")
	expect(HISTORY.MAX_BLUEPRINT_BUILDS==768,"MAX_BLUEPRINT_BUILDS is 768")
	expect("blueprint" in HISTORY.ACTIONS,"history whitelists the blueprint action")
	expect(HISTORY.MAX_AREA==49 and World.BASIC_BUILD_AREA==25,"Base area limit stays at 25 and skilled area history permits 49")
	expect(recipe_total(house_raw())==HOUSE_BASE,"fixture house base cost matches current recipes: "+str(recipe_total(house_raw())))
	expect(plus(HOUSE_BASE,times(World.BUILD.roof,9))==HOUSE_COST,"house total = base + 9 roofs")
	expect(house_raw().pieces.size()==26,"fixture house has 26 pieces (> 25 area limit)")

func test_house_quote_apply_reload_undo() -> void:
	var f:=house_world()
	var w=f[0]
	var o:Vector2i=f[1]
	if o.x<0:return
	w.state.players[A].inventory={"wood":200,"stone":10,"fiber":100}
	expect(w.save(),"baseline save written")
	var bytes:=FileAccess.get_file_as_bytes(w.save_path)
	var snap:=full(w)
	var tokens:Dictionary=w.active_tokens.duplicate()
	var q:=quote(w,A,house_raw(),o)
	expect(q.get("ok")==true,"house quote ok: "+str(q.get("message")))
	expect(int(q.get("pieces",-1))==26,"quote counts 26 pieces")
	expect(int(q.get("roof_add",-1))==9 and int(q.get("roof_remove",-1))==0,"quote adds 9 automatic roofs, removes none")
	expect(ints(q.get("cost"))==HOUSE_COST,"quote cost is exact total incl. roofs: "+str(q.get("cost")))
	expect(ints(q.get("mine_refund"))=={} and ints(q.get("others_refund"))=={} and int(q.get("other_people",-1))==0,"no refunds, nobody else involved")
	expect(q.get("problems",[1])==[] and str(q.get("hash","")).length()>0 and q.get("undoable")==true,"no problems, hash present, undoable")
	expect(full(w)==snap,"quote leaves deep state (layers, inventory, receipts, history, committed) unchanged")
	expect(FileAccess.get_file_as_bytes(w.save_path)==bytes,"quote does not save")
	expect(w.active_tokens==tokens,"quote does not touch active_tokens")
	var h:=str(q.get("hash",""))
	var shuffled:=house_raw()
	shuffled.pieces.reverse()
	expect(str(quote(w,A,shuffled,o).get("hash",""))==h,"hash is over the normalised layout (piece order irrelevant)")
	var turned:=quote(w,A,house_raw(),o,2)
	expect(turned.get("ok")==true and str(turned.get("hash",""))!=h,"rotation changes the hash")
	expect(full(w)==snap,"repeated quotes remain read-only")
	var a0:=inv(w,A)
	var b_inv:=inv(w,B)
	var b0:=builds(w,A)
	var c0:=int(w.state.committed)
	var n:=nonce()
	var r:=apply(w,A,n,house_raw(),o,0,h)
	expect(r.get("ok")==true,"house applied: "+str(r.get("message")))
	if r.get("ok")!=true:return
	check_house(w,o,A,"applied house")
	expect(inv(w,A)==minus(a0,HOUSE_COST),"exact charge incl. roofs: "+str(inv(w,A)))
	expect(inv(w,B)==b_inv,"other player untouched")
	expect(builds(w,A)==b0+26,"builds counts every piece once")
	expect(int(w.state.committed)==c0+1,"whole blueprint is one commit")
	var receipt=w.state.players[A].receipts.get("blueprint:"+n)
	expect(receipt is Dictionary and receipt.get("ok")==true,"receipt stored under blueprint:<nonce>")
	if receipt is Dictionary:
		expect(receipt.get("pieces") is int and receipt.get("pieces")==26 and receipt.get("blueprint")==true and not receipt.has("design") and not receipt.has("problems") and not receipt.has("quote") and var_to_str(receipt).length()<2048,"receipt is compact (piece count and marker only, no design / per-cell quote)")
		leak_free(receipt,"receipt")
	# Persisted v19 document passes the real schema and records one blueprint entry.
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	expect(parsed is Dictionary and int(parsed.get("version",0))==SCHEMA.VERSION,"saved document uses current schema")
	if parsed is Dictionary:
		expect(SCHEMA.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved v19 document passes save_schema.validate")
		var entry=parsed.get("construction",{}).get("last",{}).get(A,{})
		expect(entry is Dictionary and entry.get("action")=="blueprint" and int(entry.get("builds",-1))==26 and entry.get("status")=="live","history holds one live blueprint entry with 26 builds")
	# Same nonce, same process: original receipt, nothing changes.
	var snap2:=full(w)
	var again:=apply(w,A,n,house_raw(),o,0,h)
	expect(again==r,"duplicate nonce returns the original receipt")
	var other:=apply(w,A,n,bp("別的",1,1,[piece("floor",0,0)]),o+Vector2i(-1,0),0,"x")
	expect(other.get("ok")==false or other==r,"duplicate nonce with another payload never builds")
	expect(full(w)==snap2,"duplicate nonce changes nothing (no second charge)")
	# Same nonce after a restart.
	var loaded=reload(w.save_path)
	pose(loaded,A,stand(o))
	var lsnap:=full(loaded)
	var replay:=apply(loaded,A,n,house_raw(),o,0,h)
	expect(replay.get("ok")==true,"reloaded duplicate nonce returns the stored receipt")
	expect(full(loaded)==lsnap,"reloaded duplicate nonce changes nothing")
	expect(inv(loaded,A)==minus(a0,HOUSE_COST),"reloaded inventory carries exactly one charge")
	check_house(loaded,o,A,"reloaded house")
	# Undo the entire blueprint (original process) with an exact refund.
	clock.advance(5.0)
	var s:=summary(w,A)
	expect(s.get("available")==true and str(s.get("id","")).length()>0,"blueprint is undoable: "+str(s))
	leak_free(s,"summary")
	pose(w,A,stand(o))
	var u:Dictionary=w.act(A,"undo-house","undo_build",o,str(s.get("id","")))
	expect(u.get("ok")==true,"undo whole blueprint: "+str(u.get("message")))
	expect(house_empty(w,o),"every piece and every auto roof removed")
	expect(inv(w,A)==a0,"exact refund incl. roofs")
	expect(builds(w,A)==b0,"builds reverted by 26")
	expect(w._region==HOME,"home orientation after undo")

func test_undo_blocked_by_other_player() -> void:
	var f:=house_world()
	var w=f[0]
	var o:Vector2i=f[1]
	if o.x<0:return
	var q:=quote(w,A,house_raw(),o)
	var r:=apply(w,A,nonce(),house_raw(),o,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"dependency fixture house applied: "+str(r.get("message")))
	if r.get("ok")!=true:return
	var id:=str(summary(w,A).get("id",""))
	must(w,B,"build",o+Vector2i(3,3),"chair","B puts a chair in A's blueprint house",Vector2(o)+Vector2(2.5,2.5))
	expect(summary(w,A).get("available")!=true,"undo no longer available after another player's dependent build")
	pose(w,A,stand(o))
	var snap:=view(w)
	var u:Dictionary=w.act(A,"undo-dep","undo_build",o,id)
	expect(u.get("ok")==false and str(u.get("message","")).length()>0,"undo refused while B depends on the house")
	expect(view(w)==snap,"refused undo changes nothing")
	check_house(w,o,A,"house after refused undo")

func test_insufficient_total_including_roof() -> void:
	var f:=house_world()
	var w=f[0]
	var o:Vector2i=f[1]
	if o.x<0:return
	w.state.players[A].inventory=HOUSE_BASE.duplicate()
	var q:=quote(w,A,house_raw(),o)
	expect(q.get("ok")==false,"base-only stock cannot cover automatic roofs")
	expect(ints(q.get("cost"))==HOUSE_COST,"failed quote still reports the full total")
	refuse_apply(w,A,house_raw(),o,0,str(q.get("hash","")),"base-only stock")
	var short:=HOUSE_COST.duplicate()
	short.fiber=int(short.fiber)-1
	w.state.players[A].inventory=short
	q=quote(w,A,house_raw(),o)
	expect(q.get("ok")==false,"one fiber short is rejected")
	refuse_apply(w,A,house_raw(),o,0,str(q.get("hash","")),"one fiber short")
	expect(house_empty(w,o),"no partial house")
	w.state.players[A].inventory=HOUSE_COST.duplicate()
	q=quote(w,A,house_raw(),o)
	expect(q.get("ok")==true,"exact stock quotes ok")
	var r:=apply(w,A,nonce(),house_raw(),o,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"exact stock applies: "+str(r.get("message")))
	expect(inv(w,A)=={},"exact stock fully consumed: "+str(inv(w,A)))

func test_nonce_and_hash() -> void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(2,1))
	if o.x<0:return
	pose(w,A,stand(o))
	var raw:=bp("路",2,1,[piece("floor",0,0),piece("floor",1,0)])
	var q:=quote(w,A,raw,o)
	var h:=str(q.get("hash",""))
	expect(q.get("ok")==true and h.length()>0,"small quote ok")
	for bad in ["","0".repeat(31),"0".repeat(33),"A"+"0".repeat(31),"g"+"0".repeat(31)," "+"0".repeat(31),"blueprint:"+"0".repeat(32)]:
		refuse_apply(w,A,raw,o,0,h,"invalid nonce '%s'"%bad,bad)
	if h.is_empty():return
	var n:=nonce()
	var wrong:=h.substr(0,h.length()-1)+("1" if h.right(1)!="1" else "2")
	var r:=refuse_apply(w,A,raw,o,0,wrong,"mismatched hash",n)
	expect(r.get("requote")==true,"mismatched hash asks for requote")
	var fresh=r.get("quote")
	expect(fresh is Dictionary and fresh.get("ok")==true and str(fresh.get("hash",""))==h,"requote carries the current public quote")
	if fresh is Dictionary:shape(fresh,"requote")
	refuse_apply(w,A,raw,o,0,"","empty hash",n)
	r=apply(w,A,n,raw,o,0,h)
	expect(r.get("ok")==true,"rejected attempts did not burn the nonce: "+str(r.get("message")))

func test_stale_collision() -> void:
	var f:=house_world()
	var w=f[0]
	var o:Vector2i=f[1]
	if o.x<0:return
	var q:=quote(w,A,house_raw(),o)
	expect(q.get("ok")==true,"quote before the collision")
	var hit:=o+Vector2i(2,2)
	must(w,B,"build",hit,"wall","B builds inside the quoted footprint",Vector2(o)+Vector2(2.5,3.5))
	pose(w,A,stand(o))
	var r:=refuse_apply(w,A,house_raw(),o,0,str(q.get("hash","")),"stale quote after collision")
	var fresh=r.get("quote")
	if r.get("requote")==true:
		expect(fresh is Dictionary and fresh.get("ok")==false and has_problem(fresh,hit,Vector2i(2,2)),"requote reports the new collision")
	expect(w.state.objects.get(World.key(hit),{}).get("owner")==B,"B's wall kept")

func test_stale_price_requote() -> void:
	var w=new_world()
	var site:=find_site(w,HOME,Vector2i(4,4))
	if site.x<0:return
	var r0:=site+Vector2i(1,1)
	var centre:=Vector2(r0)+Vector2(1,1)
	var door:=Vector2i(r0.x,r0.y-1)
	must(w,A,"build_area",r0,"floor|%d|%d"%[r0.x+1,r0.y+1],"room floor",centre)
	for c in ring(r0,Vector2i(2,2)):
		if c!=door:must(w,A,"build",c,"wall","room wall %s"%c,centre)
	pose(w,A,stand(site))
	var raw:=bp("門",1,1,[piece("door",0,0)])
	var q:=quote(w,A,raw,door)
	expect(q.get("ok")==true and int(q.get("roof_add",-1))==4,"closing door quotes 4 automatic roofs")
	expect(ints(q.get("cost"))==plus(times(World.BUILD.door,1),times(World.BUILD.roof,4)),"door + 4 roofs: "+str(q.get("cost")))
	must(w,A,"remove",Vector2i(r0.x+2,r0.y),"","open the room after quoting",centre)
	pose(w,A,stand(site))
	var n:=nonce()
	var r:=refuse_apply(w,A,raw,door,0,str(q.get("hash","")),"price changed since quote",n)
	expect(r.get("requote")==true,"price change requires requote")
	var fresh=r.get("quote")
	expect(fresh is Dictionary and int(fresh.get("roof_add",-1))==0 and ints(fresh.get("cost"))==ints(times(World.BUILD.door,1)),"requote shows the new roofless price")
	if fresh is Dictionary:
		r=apply(w,A,n,raw,door,0,str(fresh.get("hash","")))
		expect(r.get("ok")==true and auto_roofs(w,A)==0,"apply at the new price builds without roofs: "+str(r.get("message")))

func test_save_failure_rollback_and_retry() -> void:
	var f:=house_world()
	var w=f[0]
	var o:Vector2i=f[1]
	if o.x<0:return
	var q:=quote(w,A,house_raw(),o)
	var h:=str(q.get("hash",""))
	var good:String=w.save_path
	w.save_path=dir+"/missing-subdir/world.json"
	var n:=nonce()
	var r:=refuse_apply(w,A,house_raw(),o,0,h,"save failure",n)
	expect(house_empty(w,o),"save failure leaves no piece behind")
	w.save_path=good
	r=apply(w,A,n,house_raw(),o,0,h)
	expect(r.get("ok")==true,"same nonce succeeds once storage recovers: "+str(r.get("message")))
	check_house(w,o,A,"house after save retry")
	expect(FileAccess.file_exists(good),"recovered save written")

func test_terrain_and_resources() -> void:
	for label in ["tree","rock","water","protected"]:
		var w=new_world()
		var c:=find_edge(w,label)
		if c.x<0:continue
		pose(w,A,stand(c))
		var raw:=bp(label,2,1,[piece("floor",0,0),piece("floor",1,0)])
		var q:=quote(w,A,raw,c)
		expect(q.get("ok")==false,label+": quote rejected")
		expect(has_problem(q,c+Vector2i.RIGHT,Vector2i(1,0)),label+": problem names the bad cell "+str(q.get("problems")))
		refuse_apply(w,A,raw,c,0,str(q.get("hash","")),label)
		var control:=quote(w,A,bp("單",1,1,[piece("floor",0,0)]),c)
		expect(control.get("ok")==true,label+": control without the bad cell is buildable")
	# Crop and sapling occupancy.
	var w2=new_world()
	var o:=find_site(w2,HOME,Vector2i(3,1))
	if o.x<0:return
	w2.state.crops[World.key(o+Vector2i(1,0))]={"kind":"","growth":0.0,"wet":false,"owner":A}
	w2.state.forest[World.key(o+Vector2i(2,0))]={"growth":0.0,"mature":false,"owner":A}
	pose(w2,A,stand(o))
	for x in [1,2]:
		var raw:=bp("田",3,1,[piece("floor",0,0),piece("floor",x,0)])
		var q:=quote(w2,A,raw,o)
		expect(q.get("ok")==false and has_problem(q,o+Vector2i(x,0),Vector2i(x,0)),"farm/sapling cell %d rejected"%x)
		refuse_apply(w2,A,raw,o,0,str(q.get("hash","")),"farm/sapling %d"%x)

func test_range_and_regions() -> void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(1,1))
	if o.x<0:return
	var raw:=bp("單",1,1,[piece("floor",0,0)])
	var centre:=Vector2(o)+Vector2(0.5,0.5)
	pose(w,A,centre+Vector2(-3.3,0))
	var q:=quote(w,A,raw,o)
	expect(q.get("ok")==false,"origin 3.3 away rejected")
	refuse_apply(w,A,raw,o,0,str(q.get("hash","")),"origin out of range")
	pose(w,A,centre+Vector2(-3.1,0))
	expect(quote(w,A,raw,o).get("ok")==true,"origin 3.1 away accepted")
	# Station plaza (TRANSIT.LOCAL) is never a construction site.
	var station:String=TRANSIT.LOCAL[0]
	w.state.players[A].region=station
	var arrival:Vector2=REGIONS.spawn(station)
	var target:=Vector2i(arrival)+Vector2i(1,0)
	w.switch_region(station)
	for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(2,0)]:
		var c:Vector2i=Vector2i(arrival)+d
		if w.is_land(c) and not w.blocked(c):
			target=c
			break
	w.switch_region(HOME)
	pose(w,A,arrival)
	q=quote(w,A,raw,target)
	expect(q.get("ok")==false,"station region rejects blueprints")
	refuse_apply(w,A,raw,target,0,str(q.get("hash","")),"station region")
	# Lanyang: built into Lanyang's layers only.
	w.state.players[A].region=LANYANG
	var l:=find_site(w,LANYANG,Vector2i(2,1))
	if l.x<0:return
	pose(w,A,stand(l))
	var pair:=bp("田埂",2,1,[piece("floor",0,0),piece("floor",1,0)])
	q=quote(w,A,pair,l)
	expect(q.get("ok")==true,"Lanyang quote ok: "+str(q.get("message")))
	var home_ground:=var_to_str(w.state.ground)
	var r:=apply(w,A,nonce(),pair,l,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"Lanyang apply ok: "+str(r.get("message")))
	for x in 2:
		var k:=World.key(l+Vector2i(x,0))
		expect(w.state.regions[LANYANG].ground.get(k,{}).get("owner")==A,"Lanyang floor %d in Lanyang layer"%x)
	expect(var_to_str(w.state.ground)==home_ground,"home layer untouched by Lanyang blueprint")

func test_locked_and_cross_region_limit() -> void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(1,1))
	if o.x<0:return
	pose(w,A,stand(o))
	var sofa:=bp("沙發",1,1,[piece("sofa",0,0)])
	var q:=quote(w,A,sofa,o)
	expect(q.get("ok")==false and has_problem(q,o,Vector2i.ZERO),"locked sofa rejected")
	refuse_apply(w,A,sofa,o,0,str(q.get("hash","")),"locked sofa")
	var stories=w.state.players[A].get("stories",{})
	stories["aru"]=4
	w.state.players[A].inventory["cotton_cloth"]=2
	w.state.players[A]["stories"]=stories
	expect(quote(w,A,sofa,o).get("ok")==true,"sofa allowed after unlocking story")
	w.state.players[A].inventory["waterworks_kit"]=1
	var ww:=bp("水力",1,1,[piece("waterworks",0,0)])
	w.state.mine_depths.unlocked=0
	q=quote(w,A,ww,o)
	expect(q.get("ok")==false,"waterworks locked before mine level 4")
	refuse_apply(w,A,ww,o,0,str(q.get("hash","")),"locked waterworks")
	w.state.mine_depths.unlocked=4
	expect(quote(w,A,ww,o).get("ok")==true,"waterworks allowed after unlock")
	# Fixture: A already owns the world-wide maximum in another region.
	var mine:Dictionary=w.state.regions["mine_1"].objects
	for i in WATERWORKS.LIMIT:
		var device:={"type":"waterworks","owner":A,"items":{}}
		device.merge(WATERWORKS.fresh(),true)
		mine[World.key(Vector2i(10+i,10))]=device
	q=quote(w,A,ww,o)
	expect(q.get("ok")==false,"cross-region waterworks limit enforced")
	refuse_apply(w,A,ww,o,0,str(q.get("hash","")),"cross-region waterworks limit")

func sprinklers(count:int) -> Dictionary:
	var pieces:=[]
	for i in count:pieces.append(piece("sprinkler",i if i<9 else i-9,0 if i<9 else 1))
	return bp("灑水",9,2,pieces)

func test_device_aggregate() -> void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(9,2))
	if o.x<0:return
	w.state.players[A].inventory["sprinkler_kit"]=40
	pose(w,A,stand(o))
	var q:=quote(w,A,sprinklers(17),o)
	expect(q.get("ok")==false,"17 sprinklers in one blueprint exceed the limit of %d"%World.SPRINKLER_LIMIT)
	refuse_apply(w,A,sprinklers(17),o,0,str(q.get("hash","")),"17 sprinklers")
	expect(quote(w,A,sprinklers(16),o).get("ok")==true,"exactly 16 allowed")
	var spare:=find_site(w,HOME,Vector2i(5,2),[Rect2i(o-Vector2i(3,3),Vector2i(15,8))])
	if spare.x<0:return
	for i in 10:
		var c:=spare+Vector2i(i%5,0 if i<5 else 1)
		w.state.objects[World.key(c)]={"type":"sprinkler","owner":A,"items":{},"water":0,"enabled":false,"next_water":0.0,"last_water":-1.0}
	pose(w,A,stand(o))
	q=quote(w,A,sprinklers(7),o)
	expect(q.get("ok")==false,"10 existing + 7 exceeds the aggregate limit")
	refuse_apply(w,A,sprinklers(7),o,0,str(q.get("hash","")),"aggregate sprinklers")
	q=quote(w,A,sprinklers(6),o)
	expect(q.get("ok")==true,"10 existing + 6 reaches the limit exactly")
	var r:=apply(w,A,nonce(),sprinklers(6),o,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"6 sprinklers applied: "+str(r.get("message")))
	var owned:=0
	for obj in w.state.objects.values():
		if obj.get("type")=="sprinkler" and obj.get("owner")==A:owned+=1
	expect(owned==World.SPRINKLER_LIMIT,"A owns exactly the limit")

func test_floor_ownership_and_layer_order() -> void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(4,1))
	if o.x<0:return
	must(w,B,"build",o,"floor","B floor",stand(o))
	must(w,A,"build",o+Vector2i(1,0),"floor","A floor",stand(o))
	pose(w,A,stand(o))
	for kind in ["chair","floor","roof"]:
		var raw:=bp("他人",1,1,[piece(kind,0,0)])
		var q:=quote(w,A,raw,o)
		expect(q.get("ok")==false and has_problem(q,o,Vector2i.ZERO),kind+" on another player's floor rejected")
		refuse_apply(w,A,raw,o,0,str(q.get("hash","")),kind+" on foreign floor")
	var over:=bp("覆寫",2,1,[piece("floor",1,0)])
	var q:=quote(w,A,over,o)
	expect(q.get("ok")==false,"blueprint never overwrites own existing floor")
	refuse_apply(w,A,over,o,0,str(q.get("hash","")),"overwrite own floor")
	var roof_only:=bp("空頂",4,1,[piece("roof",3,0)])
	q=quote(w,A,roof_only,o)
	expect(q.get("ok")==false,"manual roof without floor rejected")
	refuse_apply(w,A,roof_only,o,0,str(q.get("hash","")),"roof without floor")
	# Furniture on own existing floor + new floor/manual roof on one cell.
	var mixed:=bp("混合",3,1,[piece("roof",2,0),piece("chair",1,0),piece("floor",2,0)])
	q=quote(w,A,mixed,o)
	expect(q.get("ok")==true,"chair on own floor and floor+manual roof quote ok: "+str(q.get("message")))
	expect(ints(q.get("cost"))==plus(plus(times(World.BUILD.chair,1),World.BUILD.floor),World.BUILD.roof),"cost excludes the existing floor: "+str(q.get("cost")))
	expect(int(q.get("roof_add",-1))==0,"no automatic roofs for an open layout")
	var own_floor:Dictionary=w.state.ground[World.key(o+Vector2i(1,0))].duplicate(true)
	var r:=apply(w,A,nonce(),mixed,o,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"mixed blueprint applied: "+str(r.get("message")))
	expect(w.state.ground.get(World.key(o+Vector2i(1,0)))==own_floor,"existing floor untouched")
	expect(w.state.objects.get(World.key(o+Vector2i(1,0)),{}).get("type")=="chair","chair placed on own floor")
	var k2:=World.key(o+Vector2i(2,0))
	expect(w.state.ground.get(k2,{}).get("type")=="floor" and w.state.ground.get(k2,{}).get("owner")==A,"new floor laid first")
	var roof=w.state.roofs.get(k2)
	expect(roof is Dictionary and roof.get("owner")==A and not World.is_auto_roof(roof),"manual roof built on the new floor and stays manual")
	expect(w.state.ground[World.key(o)].get("owner")==B,"B's floor untouched")

func test_player_collision() -> void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(1,1))
	if o.x<0:return
	var raw:=bp("牆",1,1,[piece("wall",0,0)])
	var centre:=Vector2(o)+Vector2(0.5,0.5)
	pose(w,A,centre)
	var q:=quote(w,A,raw,o)
	expect(q.get("ok")==false,"actor standing on a solid piece rejected")
	refuse_apply(w,A,raw,o,0,str(q.get("hash","")),"actor collision")
	pose(w,A,stand(o))
	w.state.players[B].x=centre.x
	w.state.players[B].y=centre.y
	q=quote(w,A,raw,o)
	expect(q.get("ok")==false and has_problem(q,o,Vector2i.ZERO),"other active player on a solid piece rejected")
	refuse_apply(w,A,raw,o,0,str(q.get("hash","")),"other player collision")
	pose(w,A,stand(o))
	q=quote(w,A,raw,o)
	expect(q.get("ok")==true,"clear once the player moves")
	expect(apply(w,A,nonce(),raw,o,0,str(q.get("hash",""))).get("ok")==true,"wall applied once clear")

func belt(w,c:Vector2i) -> Dictionary:
	var obj=w.state.objects.get(World.key(c))
	return obj if obj is Dictionary else {}

func test_style_round_trip() -> void:
	var w=new_world()
	var origin:=find_site(w,HOME,Vector2i(2,2))
	if origin.x<0:return
	var source:={"ground":{"0,0":{"type":"floor","owner":A,"style":"coast"},
		"1,0":{"type":"floor","owner":A,"style":"tea_house"}},"objects":{},"roofs":{}}
	var captured:=World.BLUEPRINT_DESIGN.capture(source,A,Rect2i(0,0,2,1),"雙色地板",World.BUILD,World.NAMES)
	expect(captured.ok,"Capture accepts styled ground")
	if not captured.ok:return
	var raw: Dictionary=captured.blueprint
	pose(w,A,stand(origin))
	var priced:=quote(w,A,raw,origin,1)
	expect(priced.ok,"Rotated styled blueprint can be quoted")
	if not priced.ok:return
	var result:=apply(w,A,nonce(),raw,origin,1,str(priced.hash))
	expect(result.ok,"Rotated styled blueprint can be built")
	if not result.ok:return
	var loaded=reload(w.save_path)
	expect(loaded.state.ground.get(World.key(origin),{}).get("style")=="coast","Coast style retained after rotation and reload")
	expect(loaded.state.ground.get(World.key(origin+Vector2i.DOWN),{}).get("style")=="tea_house","Tea style retained after rotation and reload")
	var invalid:=raw.duplicate(true)
	invalid.pieces[0].style="unknown"
	expect(not quote(w,A,invalid,origin).ok,"Unknown blueprint style is rejected")

func test_conveyor_settings_and_turns() -> void:
	var raw:=bp("輸送",2,1,[{"kind":"conveyor","x":0,"y":0,"settings":{"dir":1,"filter":"stone"}},piece("conveyor",1,0)])
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(2,2))
	if o.x<0:return
	w.state.players[A].inventory["conveyor_kit"]=4
	pose(w,A,stand(o))
	var q:=quote(w,A,raw,o)
	expect(q.get("ok")==true and ints(q.get("cost"))=={"conveyor_kit":2},"conveyors quote their kits: "+str(q.get("cost")))
	var r:=apply(w,A,nonce(),raw,o,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"conveyors applied: "+str(r.get("message")))
	var first:=belt(w,o)
	var second:=belt(w,o+Vector2i(1,0))
	expect(first.get("type")=="conveyor" and first.get("owner")==A and int(first.get("dir",-1))==1 and first.get("filter")=="stone","configured belt keeps dir/filter")
	expect(int(second.get("dir",-1))==0 and second.get("filter")=="wood","belt without settings uses game defaults")
	for b in [first,second]:
		expect(b.get("enabled")==false and b.get("items",{"x":1})=={},"belts start stopped and empty")
	# Rotation (new world) and invalid turn values.
	var w2=new_world()
	var o2:=find_site(w2,HOME,Vector2i(2,2))
	if o2.x<0:return
	w2.state.players[A].inventory["conveyor_kit"]=4
	pose(w2,A,stand(o2))
	for t in [4,-1,true,1.5,"1",null]:
		q=quote(w2,A,raw,o2,t)
		expect(q.get("ok")==false,"turns %s rejected"%str(t))
		refuse_apply(w2,A,raw,o2,t,str(q.get("hash","")),"turns %s"%str(t))
	q=quote(w2,A,raw,o2,1)
	expect(q.get("ok")==true,"quarter turn quotes ok")
	r=apply(w2,A,nonce(),raw,o2,1,str(q.get("hash","")))
	expect(r.get("ok")==true,"quarter turn applied: "+str(r.get("message")))
	expect(int(belt(w2,o2).get("dir",-1))==2 and belt(w2,o2).get("filter")=="stone","rotated configured belt dir 1→2")
	expect(int(belt(w2,o2+Vector2i(0,1)).get("dir",-1))==1 and belt(w2,o2+Vector2i(0,1)).get("filter")=="wood","rotated default belt dir 0→1 at (0,1)")
	expect(belt(w2,o2+Vector2i(1,0)).is_empty(),"rotated layout is vertical")

func test_offline_owner_roof_refund_and_undo() -> void:
	var w=new_world()
	var site:=find_site(w,HOME,Vector2i(5,5))
	if site.x<0:return
	var r0:=site+Vector2i(1,1)
	var centre:=Vector2(r0)+Vector2(1.5,1.5)
	var door:=Vector2i(r0.x+1,r0.y-1)
	must(w,A,"build_area",r0,"floor|%d|%d"%[r0.x+2,r0.y+2],"A room floor",centre)
	for c in ring(r0,Vector2i(3,3)):
		if c!=door:must(w,A,"build",c,"wall","A room wall %s"%c,centre)
	var closed:=must(w,B,"build",door,"door","B closes the room and pays roofs",centre)
	expect(int(closed.get("roof_add_count",0))==9 and auto_roofs(w,B)==9,"B paid 9 automatic roofs")
	w.active_tokens.erase(B)  # B goes offline
	var mid:=r0+Vector2i(1,1)
	pose(w,A,Vector2(r0)+Vector2(0.5,0.5))
	var raw:=bp("隔間",1,1,[piece("wall",0,0)])
	var q:=quote(w,A,raw,mid)
	expect(q.get("ok")==true,"interior wall quote ok: "+str(q.get("message")))
	expect(int(q.get("roof_remove",-1))==1 and int(q.get("roof_add",-1))==0,"one auto roof removed under the new wall")
	expect(ints(q.get("cost"))==ints(times(World.BUILD.wall,1)),"A pays only the wall")
	expect(ints(q.get("others_refund"))==ints(times(World.BUILD.roof,1)) and ints(q.get("mine_refund"))=={},"refund goes to the original payer, listed without identity")
	expect(int(q.get("other_people",-1))==1,"one other person affected")
	var a0:=inv(w,A)
	var b0:=inv(w,B)
	var r:=apply(w,A,nonce(),raw,mid,0,str(q.get("hash","")))
	expect(r.get("ok")==true,"interior wall applied with offline payer: "+str(r.get("message")))
	expect(inv(w,B)==plus(b0,World.BUILD.roof),"offline B refunded exactly one roof")
	expect(inv(w,A)==minus(a0,World.BUILD.wall),"A charged only the wall")
	expect(not w.state.roofs.has(World.key(mid)) and auto_roofs(w,B)==8,"other 8 roofs kept with payer B")
	var s:=summary(w,A)
	expect(s.get("available")==true,"interior-wall blueprint undoable: "+str(s))
	var u:Dictionary=w.act(A,"undo-refund","undo_build",mid,str(s.get("id","")))
	expect(u.get("ok")==true,"undo with offline payer: "+str(u.get("message")))
	expect(not w.state.objects.has(World.key(mid)) and auto_roofs(w,B)==9,"wall gone and B's roof restored")
	expect(inv(w,A)==a0 and inv(w,B)==b0,"undo reverses both settlements exactly")
