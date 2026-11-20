extends SceneTree
## Construction undo through the real World.act / World.undo_summary path
## (not the pure construction_undo module). Contract: docs/construction-undo-integration.md.
##
## API under test (implemented by the core worker):
##   World.undo_summary(token) -> {id,label,available,reason,seconds_left,region}
##   World.act(token, request_id, "undo_build", p, summary.id)
##   World.undo_clock_utc   : Callable -> float UTC seconds
##   World.undo_clock_ticks : Callable -> int monotonic msec
## Every World gets both clocks pointed at a mutable FakeClock, so nothing waits 30 s.
##
## History internals are opaque: nothing here reads state.construction. Rejection
## snapshots exclude only that key; save-failure snapshots compare the whole state.
## Fixtures are explicitly NOT normal play: inventories, kits and positions are
## written directly. Each world saves into a unique per-run user:// directory that
## is deleted afterwards; real player saves are never touched.
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")

const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const PARK:=World.SPAWN
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const WINDOW:=30.0
const ARU_CELL:=Vector2i(38,29)
const STALL_CELL:=Vector2i(43,29)

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
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
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	dir="user://test-construction-undo-world-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated test directory created")
	var probe=World.new()
	expect(int(probe.state.version)==preload("res://scripts/save_schema.gd").VERSION,"fresh world version is 20, got %s"%str(probe.state.version))
	expect(probe.has_method("undo_summary"),"World exposes undo_summary(token)")
	expect(has_prop(probe,"undo_clock_utc") and has_prop(probe,"undo_clock_ticks"),"World exposes undo_clock_utc / undo_clock_ticks")
	test_no_record()
	test_build_preserves_later_harvest()
	test_build_area()
	test_remove()
	test_move()
	test_actor_and_region()
	test_expiry_boundaries()
	test_failed_keeps_and_new_replaces()
	test_double_undo_and_reload()
	test_save_failure()
	test_reload_window()
	test_dependency_friend_chest_on_floor()
	test_dependency_chest_aba()
	test_dependency_door_aba()
	test_cached_watch_detects_in_place_edit()
	test_far_friend_build_does_not_block()
	test_preview_validation_tracks_unrelated_changes()
	test_occupied_restore()
	test_paused_inactive()
	test_auto_roof_closure()
	test_multi_owner_reverse()
	test_machine_idle_vs_used()
	test_pipe_network()
	test_quest_and_shop()
	test_clock_fraction_and_cache()
	test_registered_freight_target()
	test_auto_freight_target_use()
	cleanup()
	print("CONSTRUCTION_UNDO_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func test_clock_fraction_and_cache()->void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(1,1))
	clock.utc+=0.00075
	must(w,A,"build",o,"floor","fractional creation time")
	expect(summary(w,A).available,"creation never rounds into future and rejects immediate undo")
	for i in 20:
		must(w,A,"remove",o,"","bounded clock cache remove")
		must(w,A,"build",o,"floor","bounded clock cache build")
	expect(w._undo_ticks_at.size()<=w.state.players.size(),"clock anchors bounded by current player histories")
	expect(w._undo_watch_memos.size()<=w.state.players.size(),"watched comparisons bounded by current player histories")

func test_registered_freight_target()->void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(2,1))
	var destination:=o+Vector2i.RIGHT
	w.state.mine_depths.unlocked=5
	w.state.mine_freight.jobs[A]=World.MINE_FREIGHT.draft()
	must(w,A,"build",o,"private_chest","freight target chest")
	# Already registered by a prior shipment; selecting it again changes only
	# the freight job, not the chest. It still is a dependency of its last move.
	w.state.objects[World.key(o)].freight_id="0123456789abcdef0123456789abcdef"
	must(w,A,"move_object",o,World.key(destination),"move registered chest",Vector2(o)+Vector2(0.5,1.8))
	var id:=open_id(summary(w,A),HOME,"registered chest move")
	var chest:Dictionary=w.state.objects[World.key(destination)].duplicate(true)
	w.state.players[A].region="mine_4"
	must(w,A,"freight_target",World.MINE_FREIGHT.LOAD_CELL,World.key(destination),"select existing registered target")
	expect(w.state.objects[World.key(destination)]==chest,"selection leaves actual chest unchanged")
	w.state.players[A].region=HOME
	pose(w,A,near(destination))
	expect(not summary(w,A).available,"cross-region freight use invalidates chest move")
	var result:=undo(w,A,id,destination)
	expect(not result.ok,"cannot undo a chest move after selecting it as freight destination")
	expect(w.state.objects.has(World.key(destination)),"delivery target stays put")

func test_auto_freight_target_use()->void:
	for mode in ["config","tick"]:
		var w=new_world()
		var o:=find_site(w,HOME,Vector2i(2,1))
		var destination:=o+Vector2i.RIGHT
		var source:=find_site(w,"mine_4",Vector2i(1,1))
		w.state.mine_depths.unlocked=5
		w.state.regions.mine_4.objects[World.key(source)]={"type":"private_chest","owner":A,"items":{"copper_ore":4},"freight_id":"1123456789abcdef0123456789abcdef"}
		must(w,A,"build",o,"private_chest","auto freight target")
		w.state.objects[World.key(o)].freight_id="0123456789abcdef0123456789abcdef"
		var route:={"region":"mine_4","source":{"cell":World.key(source),"id":"1123456789abcdef0123456789abcdef"},"target":{"cell":World.key(destination),"id":"0123456789abcdef0123456789abcdef"},"item":"copper_ore","reserve":0,"batch":1,"enabled":true}
		if mode=="tick":w.state.mine_auto_freight.routes[A]=route
		must(w,A,"move_object",o,World.key(destination),"move auto freight target",Vector2(o)+Vector2(0.5,1.8))
		var id:=open_id(summary(w,A),HOME,"auto freight move")
		var chest:Dictionary=w.state.objects[World.key(destination)].duplicate(true)
		if mode=="config":
			w.state.players[A].region="mine_4"
			var config:=JSON.stringify({"source":World.key(source),"target":World.key(destination),"item":"copper_ore","reserve":0,"batch":1})
			must(w,A,"mine_auto_config",World.MINE_FREIGHT.LOAD_CELL,config,"configure registered endpoints")
			w.state.players[A].region=HOME
		else:
			expect(w.step(0.1,true),"automatic dispatch step saves")
			expect(w.state.mine_freight.jobs.get(A,{}).get("status")=="transit","automatic dispatch actually occurred")
		expect(w.state.objects[World.key(destination)]==chest,"freight use leaves destination contents unchanged")
		pose(w,A,near(destination))
		expect(not summary(w,A).available,"automatic freight "+mode+" invalidates last target move")
		expect(not undo(w,A,id,destination).ok,"automatic freight target cannot be undone after "+mode)

func cleanup() -> void:
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	DirAccess.remove_absolute(dir)

# ---------------------------------------------------------------- fixtures --

func has_prop(obj,prop:String) -> bool:
	for entry in obj.get_property_list():
		if str(entry.name)==prop:return true
	return false

## Counts as a failed check (never a skip) when the feature is missing.
func require(w,label:String) -> bool:
	var ready:bool=w.has_method("undo_summary") and has_prop(w,"undo_clock_utc") and has_prop(w,"undo_clock_ticks")
	expect(ready,label+": undo API present on World")
	return ready

func attach(w,c:FakeClock) -> void:
	if has_prop(w,"undo_clock_utc"):w.set("undo_clock_utc",Callable(c,"now_utc"))
	if has_prop(w,"undo_clock_ticks"):w.set("undo_clock_ticks",Callable(c,"now_ticks"))

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

## Reload from disk as a fresh process would: new World, clocks injected after load.
func reload(path:String,c:FakeClock):
	var loaded=World.new()
	var ok:bool=loaded.load_world(path)
	expect(ok,"saved world reloads: "+path)
	attach(loaded,c)
	if ok:loaded.add_player(A,"Alice")
	return loaded

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

## Legal empty site: interior `size` at the returned origin plus a two-cell margin.
## Natural resources in the margin are cleared. Optionally at least `min_dist` from `avoid`.
func find_site(w,region:String,size:Vector2i,avoid:=Vector2i(-1000,-1000),min_dist:=0.0) -> Vector2i:
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

func find_resource(w,kind:String) -> Vector2i:
	for y in range(2,58):
		for x in range(2,78):
			var c:=Vector2i(x,y)
			if w.resource(c)==kind and not w.protected(c):return c
	expect(false,"found a home "+kind)
	return Vector2i(-1,-1)

func interior(o:Vector2i,size:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for y in range(o.y,o.y+size.y):
		for x in range(o.x,o.x+size.x):out.append(Vector2i(x,y))
	return out

func ring(o:Vector2i,size:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for x in range(o.x,o.x+size.x):
		out.append(Vector2i(x,o.y-1));out.append(Vector2i(x,o.y+size.y))
	for y in range(o.y,o.y+size.y):
		out.append(Vector2i(o.x-1,y));out.append(Vector2i(o.x+size.x,y))
	return out

func pose(w,token:String,at:Vector2) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else PARK
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

func must(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null) -> Dictionary:
	var r:=do(w,token,action,p,extra,at)
	expect(r.get("ok",false)==true,label+": "+str(r.get("message","")))
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
		if item=="name":continue
		out[item]=int(out.get(item,0))+sign*int(delta[item])
		if int(out[item])==0:out.erase(item)
	return out

func builds(w,token:String) -> int:
	return int(w.state.players[token].builds)

func auto_count(w,region:String) -> int:
	var n:=0
	for roof in lay(w,region,"roofs").values():
		if roof.get("auto",false)==true:n+=1
	return n

## Everything except the opaque history key.
func view(w) -> String:
	var copy:Dictionary=w.state.duplicate(true)
	copy.erase("construction")
	return var_to_str(copy)

func summary(w,token:String) -> Dictionary:
	var s=w.call("undo_summary",token)
	expect(s is Dictionary,"undo_summary returns a Dictionary")
	if not (s is Dictionary):return {}
	leak_free(s,"summary")
	for field in ["id","label","available","reason","seconds_left","region"]:
		expect(s.has(field),"summary has field "+field)
	return s

func left(s:Dictionary) -> float:
	var v=s.get("seconds_left",-1)
	return float(v) if (v is int or v is float) else -1.0

func open_id(s:Dictionary,region:String,label:String) -> String:
	expect(s.get("available")==true,label+": undo available "+str(s))
	expect(str(s.get("id","")).length()>0,label+": summary id present")
	expect(s.get("label") is String and str(s.get("label","")).length()>0,label+": summary label present")
	expect(str(s.get("region",""))==region,label+": summary region "+region+" got "+str(s.get("region")))
	expect(left(s)>0.0 and left(s)<=WINDOW,label+": seconds_left in (0,30] got "+str(s.get("seconds_left")))
	return str(s.get("id",""))

func closed(s:Dictionary,label:String,needs_reason:bool=true) -> void:
	expect(s.get("available")!=true,label+": undo not available "+str(s))
	if needs_reason:expect(str(s.get("reason","")).length()>0,label+": summary explains why")

func undo(w,token:String,id:String,p:Vector2i,rid:String="",at=null) -> Dictionary:
	pose(w,token,near(p) if at==null else at)
	serial+=1
	if rid=="":rid="undo-%d"%serial
	var r:Dictionary=w.act(token,rid,"undo_build",p,id)
	leak_free(r,"undo result")
	expect(w._region==HOME,"home orientation after undo")
	return r

## Rejected undo: ok=false with a message, and nothing outside the opaque history changes
## (layers, inventories, builds, coins, receipts, committed counter).
func refuse(w,token:String,id:String,p:Vector2i,label:String,at=null) -> Dictionary:
	pose(w,token,near(p) if at==null else at)
	var snap:=view(w)
	serial+=1
	var r:Dictionary=w.act(token,"refuse-%d"%serial,"undo_build",p,id)
	leak_free(r,label)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": undo rejected with a reason, got "+str(r))
	expect(view(w)==snap,label+": world unchanged")
	expect(w._region==HOME,label+": home orientation")
	return r

func prepare_room(w,o:Vector2i,size:Vector2i,door:Vector2i,floor_owner:String,wall_owner:String) -> void:
	var end:=o+size-Vector2i.ONE
	must(w,floor_owner,"build_area",o,"floor|%d|%d"%[end.x,end.y],"room floor",Vector2(o)+Vector2(size)*0.5)
	for c in ring(o,size):
		if c!=door:must(w,wall_owner,"build",c,"wall","room wall %s"%c)
	expect(auto_count(w,HOME)==0,"no auto roof before closure")

# ------------------------------------------------------------------- tests --

func test_no_record() -> void:
	var w=new_world()
	if not require(w,"no record"):return
	closed(summary(w,A),"fresh player",false)
	refuse(w,A,"no-such-record",Vector2i(30,30),"undo with no record")
	refuse(w,A,"",Vector2i(30,30),"undo with empty id")

func test_build_preserves_later_harvest() -> void:
	var w=new_world()
	if not require(w,"single build"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	var tree:=find_resource(w,"tree")
	var inv0:=inv(w,A)
	var b0:=builds(w,A)
	must(w,A,"build",o,"wall","wall built")
	expect(inv(w,A)==shifted(inv0,World.BUILD.wall,-1),"wall charged its recipe")
	var id:=open_id(summary(w,A),HOME,"after wall")
	closed(summary(w,B),"other player sees no undo for A's wall",false)
	for i in 3:must(w,A,"axe",tree,"","chop %d"%i)
	var farmer:Dictionary=w.state.players[A]
	farmer.x=tree.x+0.5
	farmer.y=tree.y+0.5
	expect(w.step(1.0,true),"collect the fallen wood before checking inventory")
	var inv1:=inv(w,A)
	expect(int(inv1.wood)==int(inv0.wood)-3+6,"tree wood gained after build")
	clock.advance(5.0)
	var s:=summary(w,A)
	expect(str(s.get("id",""))==id and s.get("available")==true,"unrelated harvest keeps the record")
	expect(left(s)>=24.0 and left(s)<=25.001,"seconds_left counts down by real clock: "+str(s.get("seconds_left")))
	var committed:=int(w.state.committed)
	var r:=undo(w,A,id,o)
	expect(r.get("ok",false)==true,"undo wall: "+str(r.get("message","")))
	expect(not w.state.objects.has(World.key(o)),"wall gone")
	expect(inv(w,A)==shifted(inv1,World.BUILD.wall,1),"exact recipe refunded onto current inventory")
	expect(int(inv(w,A).wood)==int(inv0.wood)+6 and int(inv(w,A).get("resin",0))==int(inv0.get("resin",0))+1,"later harvested materials kept")
	expect(w.state.removed.has(World.key(tree)),"chopped tree stays chopped")
	expect(builds(w,A)==b0,"builds stat reverted")
	expect(int(w.state.committed)==committed+1,"undo is one commit")
	closed(summary(w,A),"after undo",false)

func test_build_area() -> void:
	var w=new_world()
	if not require(w,"build_area"):return
	var o:=find_site(w,HOME,Vector2i(2,2))
	var centre:=Vector2(o)+Vector2(1,1)
	var inv0:=inv(w,A)
	var b0:=builds(w,A)
	must(w,A,"build_area",o,"floor|%d|%d"%[o.x+1,o.y+1],"floor area",centre)
	expect(builds(w,A)==b0+4,"area counts 4 builds")
	var id:=open_id(summary(w,A),HOME,"after area")
	var r:=undo(w,A,id,o,"",centre)
	expect(r.get("ok",false)==true,"undo area: "+str(r.get("message","")))
	for c in interior(o,Vector2i(2,2)):expect(not w.state.ground.has(World.key(c)),"floor %s removed"%c)
	expect(inv(w,A)==inv0,"all 4 floors refunded exactly")
	expect(builds(w,A)==b0,"area builds stat reverted")

func test_remove() -> void:
	var w=new_world()
	if not require(w,"remove"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"table","table built")
	var original:Dictionary=w.state.objects[World.key(o)].duplicate(true)
	var b1:=builds(w,A)
	must(w,A,"remove",o,"","table removed")
	var inv1:=inv(w,A)
	var id:=open_id(summary(w,A),HOME,"after remove")
	var r:=undo(w,A,id,o)
	expect(r.get("ok",false)==true,"undo remove: "+str(r.get("message","")))
	expect(w.state.objects.get(World.key(o))==original,"table restored with owner and contents")
	expect(inv(w,A)==shifted(inv1,World.BUILD.table,-1),"removal refund charged back exactly")
	expect(builds(w,A)==b1,"remove/undo-remove leave builds unchanged")

func test_move() -> void:
	var w=new_world()
	if not require(w,"move"):return
	var o:=find_site(w,HOME,Vector2i(2,1))
	var to:=o+Vector2i(1,0)
	must(w,A,"build",o,"chair","chair built")
	var chair:Dictionary=w.state.objects[World.key(o)].duplicate(true)
	must(w,A,"move_object",o,"%d,%d"%[to.x,to.y],"chair moved")
	var inv1:=inv(w,A)
	var b1:=builds(w,A)
	var id:=open_id(summary(w,A),HOME,"after move")
	var r:=undo(w,A,id,to)
	expect(r.get("ok",false)==true,"undo move: "+str(r.get("message","")))
	expect(w.state.objects.get(World.key(o))==chair and not w.state.objects.has(World.key(to)),"chair back at origin")
	expect(inv(w,A)==inv1 and builds(w,A)==b1,"move undo costs and refunds nothing")

func test_actor_and_region() -> void:
	var w=new_world()
	if not require(w,"actor/region"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"wall","home wall")
	var id:=open_id(summary(w,A),HOME,"home wall")
	refuse(w,B,id,o,"other actor uses A's id")
	refuse(w,A,id+"-forged",o,"forged id")
	w.state.players[A].region=LANYANG
	refuse(w,A,id,o,"home record from Lanyang")
	w.state.players[A].region=HOME
	expect(str(summary(w,A).get("id",""))==id,"rejections do not consume the record")
	var r:=undo(w,A,id,o)
	expect(r.get("ok",false)==true and not w.state.objects.has(World.key(o)),"own undo in own region: "+str(r.get("message","")))
	# Record made in Lanyang.
	w.state.players[A].region=LANYANG
	var l:=find_site(w,LANYANG,Vector2i(1,1))
	var inv0:=inv(w,A)
	must(w,A,"build",l,"wall","Lanyang wall")
	var lid:=open_id(summary(w,A),LANYANG,"Lanyang wall")
	w.state.players[A].region=HOME
	refuse(w,A,lid,l,"Lanyang record from home")
	w.state.players[A].region=LANYANG
	r=undo(w,A,lid,l)
	expect(r.get("ok",false)==true,"undo in Lanyang: "+str(r.get("message","")))
	expect(not lay(w,LANYANG,"objects").has(World.key(l)),"Lanyang wall removed from Lanyang layer")
	expect(inv(w,A)==inv0,"Lanyang refund exact")
	expect(not is_same(w.state.objects,w.state.regions[LANYANG].objects),"layers not aliased")

func one_wall(label:String) -> Array:
	var w=new_world()
	var o:=Vector2i(-1,-1)
	var id:=""
	if require(w,label):
		o=find_site(w,HOME,Vector2i(1,1))
		must(w,A,"build",o,"wall",label+" wall")
		id=open_id(summary(w,A),HOME,label)
	return [w,o,id]

func test_expiry_boundaries() -> void:
	var f:=one_wall("29.999 s")
	if f[2]!="":
		clock.advance(29.999)
		var s:=summary(f[0],A)
		expect(s.get("available")==true and left(s)>=0.0 and left(s)<=1.0,"29.999 s still available: "+str(s))
		var r:=undo(f[0],A,f[2],f[1])
		expect(r.get("ok",false)==true and not f[0].state.objects.has(World.key(f[1])),"undo at 29.999 s: "+str(r.get("message","")))
	f=one_wall("30.001 s")
	if f[2]!="":
		clock.advance(30.001)
		closed(summary(f[0],A),"30.001 s expired")
		refuse(f[0],A,f[2],f[1],"undo at 30.001 s")
		expect(f[0].state.objects.has(World.key(f[1])),"expired wall stays")
	f=one_wall("UTC rollback")
	if f[2]!="":
		clock.ticks+=1000
		clock.utc-=5.0
		closed(summary(f[0],A),"UTC before creation")
		refuse(f[0],A,f[2],f[1],"undo after UTC rollback")
	f=one_wall("monotonic")
	if f[2]!="":
		clock.utc+=1.0
		clock.ticks+=30001
		closed(summary(f[0],A),"monotonic 30.001 s elapsed")
		refuse(f[0],A,f[2],f[1],"undo when monotonic clock expired")

func test_failed_keeps_and_new_replaces() -> void:
	var w=new_world()
	if not require(w,"replace"):return
	var o:=find_site(w,HOME,Vector2i(3,1))
	var second:=o+Vector2i(2,0)
	must(w,A,"build",o,"wall","first wall")
	var id1:=open_id(summary(w,A),HOME,"first wall")
	var r:=do(w,A,"build",o,"chest")
	expect(r.get("ok",true)==false,"build on occupied cell fails")
	r=do(w,A,"build_area",o,"floor|%d|%d"%[o.x+1,o.y],Vector2(o)+Vector2(1,0.5))
	expect(r.get("ok",true)==false,"area over the wall fails")
	var saved:int=int(w.state.players[A].inventory.wood)
	w.state.players[A].inventory.wood=1
	r=do(w,A,"build",second,"wall")
	expect(r.get("ok",true)==false,"build without materials fails")
	w.state.players[A].inventory.wood=saved
	r=do(w,B,"remove",o)
	expect(r.get("ok",true)==false,"friend cannot remove the wall")
	expect(str(summary(w,A).get("id",""))==id1,"failed and canceled actions keep the last record")
	must(w,A,"build",second,"wall","second wall")
	var id2:=open_id(summary(w,A),HOME,"second wall")
	expect(id2!=id1,"new build replaces the record id")
	refuse(w,A,id1,o,"superseded record")
	r=undo(w,A,id2,second)
	expect(r.get("ok",false)==true,"undo newest: "+str(r.get("message","")))
	expect(not w.state.objects.has(World.key(second)) and w.state.objects.has(World.key(o)),"only the newest build reverted")
	closed(summary(w,A),"no fallback to older build",false)
	refuse(w,A,id1,o,"older record after undo")

func test_double_undo_and_reload() -> void:
	var w=new_world()
	if not require(w,"double undo"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"wall","wall")
	var id:=open_id(summary(w,A),HOME,"wall")
	var first:=undo(w,A,id,o,"undo-once")
	expect(first.get("ok",false)==true,"first undo: "+str(first.get("message","")))
	var after:=inv(w,A)
	pose(w,A,near(o))
	var snap:=var_to_str(w.state)
	var again:Dictionary=w.act(A,"undo-once","undo_build",o,id)
	expect(again==first,"same request returns the original receipt")
	expect(var_to_str(w.state)==snap,"same request changes nothing")
	refuse(w,A,id,o,"new request for an undone record")
	expect(inv(w,A)==after,"no duplicate refund")
	closed(summary(w,A),"undone record",false)
	var loaded=reload(w.save_path,clock)
	if loaded.state.players.is_empty():return
	expect(not loaded.state.objects.has(World.key(o)),"reloaded: wall still undone")
	expect(inv(loaded,A)==after,"reloaded: inventory carries the single refund")
	closed(summary(loaded,A),"reloaded undone record",false)
	pose(loaded,A,near(o))
	var lsnap:=view(loaded)
	var replay:Dictionary=loaded.act(A,"undo-once","undo_build",o,id)
	expect(replay.get("ok",false)==true,"reloaded same request still returns its receipt")
	expect(view(loaded)==lsnap,"reloaded same request changes nothing")
	refuse(loaded,A,id,o,"reloaded new request")

func test_save_failure() -> void:
	var w=new_world()
	if not require(w,"save failure"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"wall","wall")
	var id:=open_id(summary(w,A),HOME,"wall")
	var good:String=w.save_path
	w.save_path=dir+"/missing-subdir/world.json"
	pose(w,A,near(o))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(A,"undo-save","undo_build",o,id)
	expect(r.get("ok",true)==false and str(r.get("message","")).contains("保存失敗"),"save failure reported: "+str(r))
	expect(var_to_str(w.state)==snap,"save failure: entire state unchanged including history")
	expect(w._region==HOME,"save failure: home orientation")
	expect(str(summary(w,A).get("id",""))==id and summary(w,A).get("available")==true,"record still available after save failure")
	w.save_path=good
	r=w.act(A,"undo-save","undo_build",o,id)
	expect(r.get("ok",false)==true and not w.state.objects.has(World.key(o)),"same request succeeds once storage recovers")

func test_reload_window() -> void:
	var w=new_world()
	if not require(w,"reload within"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	var inv0:=inv(w,A)
	must(w,A,"build",o,"wall","wall before restart")
	var id:=open_id(summary(w,A),HOME,"before restart")
	var restarted:=FakeClock.new()
	restarted.utc=clock.utc+10.0
	restarted.ticks=1200  # new process: unrelated monotonic origin
	var loaded=reload(w.save_path,restarted)
	if loaded.state.players.is_empty():return
	expect(int(loaded.state.version)==preload("res://scripts/save_schema.gd").VERSION,"saved version 20")
	var s:=summary(loaded,A)
	expect(str(s.get("id",""))==id,"record id survives reload")
	open_id(s,HOME,"reload at +10 s")
	expect(left(s)>=19.0 and left(s)<=20.001,"offline time counts: "+str(s.get("seconds_left")))
	var r:=undo(loaded,A,id,o)
	expect(r.get("ok",false)==true,"undo after reload within 30 s: "+str(r.get("message","")))
	expect(not loaded.state.objects.has(World.key(o)) and inv(loaded,A)==inv0,"reloaded undo removes wall and refunds")
	# Expired while offline.
	var w2=new_world()
	var o2:=find_site(w2,HOME,Vector2i(1,1))
	must(w2,A,"build",o2,"wall","wall before long restart")
	var id2:=open_id(summary(w2,A),HOME,"before long restart")
	var late:=FakeClock.new()
	late.utc=clock.utc+30.5
	late.ticks=1200
	var loaded2=reload(w2.save_path,late)
	if loaded2.state.players.is_empty():return
	closed(summary(loaded2,A),"reload after 30.5 s")
	refuse(loaded2,A,id2,o2,"undo after reload past expiry")
	expect(loaded2.state.objects.has(World.key(o2)),"expired wall stays after reload")

func test_dependency_friend_chest_on_floor() -> void:
	var w=new_world()
	if not require(w,"friend chest"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"floor","A floor")
	var id:=open_id(summary(w,A),HOME,"A floor")
	must(w,B,"build",o,"chest","B chest on A's floor",Vector2(o)+Vector2(1.6,1.6))
	refuse(w,A,id,o,"floor under friend's chest")
	expect(w.state.objects.has(World.key(o)) and w.state.ground.has(World.key(o)),"chest and floor intact")

func test_dependency_chest_aba() -> void:
	var w=new_world()
	if not require(w,"chest ABA"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"chest","chest")
	var id:=open_id(summary(w,A),HOME,"chest")
	must(w,A,"deposit",o,"wood","deposit")
	must(w,A,"withdraw",o,"wood","withdraw")
	expect(int(w.state.objects[World.key(o)].items.get("wood",0))==0,"chest emptied again")
	refuse(w,A,id,o,"chest used then emptied")

func test_dependency_door_aba() -> void:
	var w=new_world()
	if not require(w,"door ABA"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"door","door")
	var original:Dictionary=w.state.objects[World.key(o)].duplicate(true)
	var id:=open_id(summary(w,A),HOME,"door")
	must(w,A,"door",o,"","open")
	must(w,A,"door",o,"","close")
	expect(w.state.objects[World.key(o)]==original,"door content identical after open/close (true ABA)")
	refuse(w,A,id,o,"door opened and closed")

func test_cached_watch_detects_in_place_edit() -> void:
	var w=new_world()
	var site:=find_site(w,HOME,Vector2i.ONE)
	must(w,A,"build",site,"door","door watched across ticks")
	expect(summary(w,A).available and summary(w,A).available,"repeated previews allow the unchanged door undo")
	w.state.objects[World.key(site)].open=true
	expect(not summary(w,A).available,"a watched row changed in place invalidates the preview")
	expect(w.step(0.016,true),"periodic observation records the change")
	w.state.objects[World.key(site)].open=false
	expect(not summary(w,A).available,"putting the old value back does not resurrect an invalidated record")

func test_far_friend_build_does_not_block() -> void:
	var w=new_world()
	if not require(w,"far friend"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"wall","A wall")
	var id:=open_id(summary(w,A),HOME,"A wall")
	var far:=find_site(w,HOME,Vector2i(1,1),o,12.0)
	var b0:=inv(w,B)
	must(w,B,"build",far,"wall","far B wall")
	var b1:=inv(w,B)
	var inv0:=inv(w,A)
	var r:=undo(w,A,id,o)
	expect(r.get("ok",false)==true,"far friend build does not block: "+str(r.get("message","")))
	expect(w.state.objects.get(World.key(far),{}).get("owner")==B,"friend's wall kept")
	expect(inv(w,B)==b1 and b1==shifted(b0,World.BUILD.wall,-1),"friend inventory untouched by A's undo")
	expect(inv(w,A)==shifted(inv0,World.BUILD.wall,1),"A refunded")

func test_occupied_restore() -> void:
	var w=new_world()
	if not require(w,"occupied"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"table","table")
	must(w,A,"remove",o,"","table removed")
	var id:=open_id(summary(w,A),HOME,"remove")
	pose(w,A,near(o))
	var bob:Dictionary=w.state.players[B]
	bob.x=o.x+0.5;bob.y=o.y+0.5
	expect(not summary(w,A).available,"preview checks live player positions even when layer validation is reused")
	var snap:=view(w)
	var r:Dictionary=w.act(A,"occupied-1","undo_build",o,id)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,"restore onto standing player rejected: "+str(r))
	expect(view(w)==snap,"occupied: world unchanged")
	expect(not w.state.objects.has(World.key(o)),"player not trapped")
	r=undo(w,A,id,o,"occupied-1")
	expect(r.get("ok",false)==true and w.state.objects.has(World.key(o)),"same request succeeds once the cell is clear: "+str(r.get("message","")))

func test_preview_validation_tracks_unrelated_changes() -> void:
	var w=new_world()
	var site:=find_site(w,HOME,Vector2i.ONE)
	var far:=find_site(w,HOME,Vector2i.ONE,site,12.0)
	must(w,B,"build",far,"wall","far wall")
	must(w,A,"build",site,"floor","floor to undo")
	var first:=summary(w,A)
	expect(first.available,"healthy map permits the undo preview")
	var other:=summary(w,B)
	expect(other.available and other.id!=first.id,"second resident sees only their own undo proposal")
	expect(summary(w,A)==first,"switching residents preserves the first proposal")
	var wall:Dictionary=w.state.objects[World.key(far)]
	wall.owner="missing-owner"
	expect(not summary(w,A).available,"preview rejects an invalid unrelated row changed in place")
	wall.owner=B
	expect(summary(w,A).available,"validating the restored owner reopens the preview")
	var stock:Dictionary=w.state.players[B].inventory
	var saved:Variant=stock.wood
	stock.wood="invalid"
	expect(not summary(w,A).available,"preview detects an in-place inventory shape change")
	stock.wood=saved
	expect(summary(w,A).available,"valid inventory reopens the preview")
	var edge_id:=World.EDGE_GRID.key(far,World.EDGE_GRID.SIDE_N,World.SIZE)
	var edge:Dictionary={"type":"edge_door","owner":B,"open":false}
	w.state.edges[edge_id]=edge
	expect(summary(w,A).available,"a valid distant edge preserves undo")
	edge.open=0
	expect(not summary(w,A).available,"preview rejects a distant edge changed to an invalid value type")
	edge.open=false
	expect(summary(w,A).available,"restoring the edge value type reopens the preview")

func test_paused_inactive() -> void:
	var w=new_world()
	if not require(w,"paused"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"wall","wall")
	var id:=open_id(summary(w,A),HOME,"wall")
	w.active_tokens.clear()
	var time0:=float(w.state.time)
	for i in 4:w.step(10.0,false)
	expect(float(w.state.time)==time0,"inactive world time paused")
	clock.advance(30.5)
	w.add_player(A,"Alice")
	closed(summary(w,A),"paused world does not extend expiry")
	refuse(w,A,id,o,"undo after pause and reconnect")

func test_auto_roof_closure() -> void:
	var w=new_world()
	if not require(w,"auto roof closure"):return
	var size:=Vector2i(2,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x,o.y-1)
	prepare_room(w,o,size,door,A,A)
	var inv0:=inv(w,A)
	var b0:=builds(w,A)
	var r:=must(w,A,"build",door,"door","closing door")
	expect(int(r.get("roof_add_count",0))==4 and auto_count(w,HOME)==4,"closure adds 4 auto roofs")
	var id:=open_id(summary(w,A),HOME,"closure")
	r=undo(w,A,id,door)
	expect(r.get("ok",false)==true,"undo closure: "+str(r.get("message","")))
	expect(not w.state.objects.has(World.key(door)),"door removed")
	expect(auto_count(w,HOME)==0,"auto roofs removed with the door")
	for c in interior(o,size):expect(not w.state.roofs.has(World.key(c)),"no roof left at %s"%c)
	expect(inv(w,A)==inv0,"door and roof costs refunded exactly")
	expect(builds(w,A)==b0,"builds reverted")

func test_multi_owner_reverse() -> void:
	var w=new_world()
	if not require(w,"multi-owner"):return
	var size:=Vector2i(2,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x+1,o.y-1)
	var wall:=Vector2i(o.x-1,o.y)
	prepare_room(w,o,size,door,A,A)
	var r:=must(w,B,"build",door,"door","B closes A's room")
	expect(int(r.get("roof_add_count",0))==4,"B pays 4 roofs")
	var roofs:Dictionary=w.state.roofs.duplicate(true)
	for c in interior(o,size):expect(roofs.get(World.key(c),{}).get("owner")==B,"roof %s paid by B"%c)
	var original_wall:Dictionary=w.state.objects[World.key(wall)].duplicate(true)
	r=must(w,A,"remove",wall,"","A opens the room")
	expect(int(r.get("roof_remove_count",0))==4,"opening refunds 4 roofs")
	var a1:=inv(w,A)
	var b1:=inv(w,B)
	var id:=open_id(summary(w,A),HOME,"opening")
	# B spent the refunded fiber; A's plenty must not cover it.
	w.state.players[B].inventory.fiber=int(World.BUILD.roof.fiber)*4-1
	refuse(w,A,id,wall,"payer B short, no borrowing from A")
	expect(auto_count(w,HOME)==0 and not w.state.objects.has(World.key(wall)),"nothing partially restored")
	w.state.players[B].inventory.fiber=int(b1.fiber)
	r=undo(w,A,id,wall)
	expect(r.get("ok",false)==true,"undo opening: "+str(r.get("message","")))
	expect(w.state.objects.get(World.key(wall))==original_wall,"wall restored")
	expect(w.state.roofs==roofs,"roofs restored with original payer B")
	expect(inv(w,A)==shifted(a1,World.BUILD.wall,-1),"A charged only the wall")
	var four:Dictionary={"wood":int(World.BUILD.roof.wood)*4,"fiber":int(World.BUILD.roof.fiber)*4}
	expect(inv(w,B)==shifted(b1,four,-1),"B returns exactly the 4 roof refunds")

func test_machine_idle_vs_used() -> void:
	var w=new_world()
	if not require(w,"idle machine"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	w.state.players[A].inventory.sawmill_kit=1
	var inv0:=inv(w,A)
	must(w,A,"build",o,"sawmill","idle sawmill")
	var id:=open_id(summary(w,A),HOME,"idle sawmill")
	var r:=undo(w,A,id,o)
	expect(r.get("ok",false)==true and not w.state.objects.has(World.key(o)),"idle machine undone: "+str(r.get("message","")))
	expect(inv(w,A)==inv0,"sawmill kit refunded")
	var w2=new_world()
	var o2:=find_site(w2,HOME,Vector2i(1,1))
	w2.state.players[A].inventory.sawmill_kit=1
	must(w2,A,"build",o2,"sawmill","used sawmill")
	var device:Dictionary=w2.state.objects[World.key(o2)].duplicate(true)
	var id2:=open_id(summary(w2,A),HOME,"used sawmill")
	must(w2,A,"start_processing",o2,"plank","start processing")
	must(w2,A,"cancel_processing",o2,"","cancel processing")
	expect(w2.state.objects[World.key(o2)]==device,"sawmill content identical after start/cancel (true ABA)")
	refuse(w2,A,id2,o2,"machine used then idle")

func pipe_world(flow:bool) -> Array:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(3,1))
	var tank:=o
	var pipe:=o+Vector2i(1,0)
	var sprinkler:=o+Vector2i(2,0)
	w.state.players[A].inventory.merge({"tank_kit":1,"pipe_kit":1,"sprinkler_kit":1},true)
	must(w,A,"build",tank,"water_tank","tank")
	if flow:must(w,A,"refill_tank",tank,"","tank filled")
	must(w,A,"build",sprinkler,"sprinkler","sprinkler",Vector2(sprinkler)+Vector2(0.5,1.6))
	must(w,A,"toggle_sprinkler",sprinkler,"","sprinkler on",Vector2(sprinkler)+Vector2(0.5,1.6))
	var before:=inv(w,A)
	must(w,A,"build",pipe,"water_pipe","connecting pipe",Vector2(pipe)+Vector2(0.5,1.6))
	var id:=open_id(summary(w,A),HOME,"pipe")
	expect(w.step(1.0,true),"network step saved")
	return [w,pipe,id,before,sprinkler]

func test_pipe_network() -> void:
	var probe=new_world()
	if not require(probe,"pipe network"):return
	var f:=pipe_world(true)
	var w=f[0]
	expect(int(w.state.objects[World.key(f[4])].water)>0,"water flowed through the new pipe")
	refuse(w,A,f[2],f[1],"pipe in a network that carried water")
	expect(w.state.objects.has(World.key(f[1])),"used pipe stays")
	f=pipe_world(false)
	w=f[0]
	expect(int(w.state.objects[World.key(f[4])].water)==0,"idle network carried nothing")
	var r:=undo(w,A,f[2],f[1],"",Vector2(f[1])+Vector2(0.5,1.6))
	expect(r.get("ok",false)==true,"idle network pipe undone: "+str(r.get("message","")))
	expect(not w.state.objects.has(World.key(f[1])) and inv(w,A)==f[3],"pipe removed, kit refunded")

func test_quest_and_shop() -> void:
	var w=new_world()
	if not require(w,"quest use"):return
	var o:=find_site(w,HOME,Vector2i(1,1))
	must(w,A,"build",o,"bed","bed")
	var id:=open_id(summary(w,A),HOME,"bed")
	var coins:=int(w.state.players[A].coins)
	must(w,A,"quest",ARU_CELL,"aru:0","Aru quest needs own bed")
	expect(int(w.state.players[A].coins)==coins+60,"quest paid")
	refuse(w,A,id,o,"bed already used for a quest")
	expect(w.state.objects.has(World.key(o)),"quest bed stays")
	var w2=new_world()
	var o2:=find_site(w2,HOME,Vector2i(1,1))
	var inv0:=inv(w2,A)
	must(w2,A,"build",o2,"bed","bed before shopping")
	var id2:=open_id(summary(w2,A),HOME,"bed before shopping")
	var coins2:=int(w2.state.players[A].coins)
	must(w2,A,"buy",STALL_CELL,"radish","unrelated seed purchase")
	var r:=undo(w2,A,id2,o2)
	expect(r.get("ok",false)==true,"unrelated shop purchase does not block: "+str(r.get("message","")))
	expect(int(w2.state.players[A].coins)==coins2-int(World.CROPS.radish.seed_price),"purchase coins kept")
	expect(inv(w2,A)==shifted(inv0,{"radish_seed":1},1),"bed refunded, bought seed kept")
