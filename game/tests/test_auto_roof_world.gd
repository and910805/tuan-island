extends SceneTree
## Live automatic roofs through the real World.act transaction path.
## Uses only fresh in-memory worlds whose save_path is inside a unique
## per-run user:// directory that is deleted afterwards; never touches player saves.
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")

# Token-like ids; the "SECRET" marker must never leak into results/messages.
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const PARK:=World.SPAWN
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const ROOF_WOOD:=1
const ROOF_FIBER:=3

var checks:=0
var failures:=0
var serial:=0
var dir:=""

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	dir="user://test-auto-roof-world-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated test directory created")
	var recipe:Dictionary=World.BUILD.roof
	expect(int(recipe.wood)==ROOF_WOOD and int(recipe.fiber)==ROOF_FIBER,"roof recipe unchanged (wood 1 / fiber 3)")
	expect(int(World.new().state.version)==preload("res://scripts/save_schema.gd").VERSION,"fresh world version is 20")
	test_closure_no_bed()
	test_insufficient_materials()
	test_multi_owner_refund()
	test_skip_auto_roof_and_guards()
	test_manual_roof_preserved()
	test_save_failure_rollback()
	test_non_home_region()
	test_unrelated_actions()
	cleanup()
	print("AUTO_ROOF_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func cleanup() -> void:
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	DirAccess.remove_absolute(dir)

# ---------------------------------------------------------------- fixtures --

func new_world():
	var w:=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":100,"fiber":300}
	serial+=1
	w.save_path=dir+"/world-%d.json"%serial
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

## Legal empty site in `region`: interior `size` at the returned origin, plus the
## wall ring and one spare cell beyond it. Natural resources there are cleared.
func find_site(w,region:String,size:Vector2i) -> Vector2i:
	w.switch_region(region)
	var found:=Vector2i(-1,-1)
	for oy in range(2,58):
		for ox in range(2,78):
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

func interior(o:Vector2i,size:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for y in range(o.y,o.y+size.y):
		for x in range(o.x,o.x+size.x):out.append(Vector2i(x,y))
	return out

## Cardinal boundary of a rectangle (corners are not needed to seal it).
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

func do(w,token:String,action:String,p:Vector2i,extra:String="",at=null,rid:String="") -> Dictionary:
	pose(w,token,near(p) if at==null else at)
	serial+=1
	if rid=="":rid="req-%d"%serial
	var r:Dictionary=w.act(token,rid,action,p,extra)
	expect(not var_to_str(r).contains("SECRET") and not var_to_str(r).contains("tok-"),"result never leaks tokens: %s %s"%[action,extra])
	expect(w._region==HOME,"world returns to home orientation after "+action)
	return r

func auto_count(w,region:String) -> int:
	var n:=0
	for roof in lay(w,region,"roofs").values():
		if roof.get("auto",false)==true:n+=1
	return n

func inv(w,token:String) -> Dictionary:
	return w.state.players[token].inventory.duplicate(true)

func no_roof_fields(r:Dictionary,label:String) -> void:
	expect(not r.has("roof_add_count") and not r.has("roof_remove_count"),label+": no roof change reported")

## Floors (build_area) + every ring wall except `door`; asserts nothing roofs early.
func prepare_room(w,region:String,o:Vector2i,size:Vector2i,door:Vector2i,floor_owner:String,wall_owner:String,skip:Array=[]) -> void:
	var end:=o+size-Vector2i.ONE
	var r:=do(w,floor_owner,"build_area",o,"floor|%d|%d"%[end.x,end.y],Vector2(o)+Vector2(size)*0.5)
	expect(r.ok,"floor area built: "+str(r.message))
	no_roof_fields(r,"open floor")
	for c in ring(o,size):
		if c==door or c in skip:continue
		r=do(w,wall_owner,"build",c,"wall")
		expect(r.ok,"wall built at %s: %s"%[c,r.message])
		no_roof_fields(r,"unsealed wall")
	expect(auto_count(w,region)==0,"no auto roof before closure")

func attempt_unchanged(w,token:String,action:String,p:Vector2i,extra:String,needle:String,label:String) -> void:
	pose(w,token,near(p))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(token,"blocked-%d"%serial,action,p,extra)
	serial+=1
	expect(not r.ok and str(r.message).contains(needle),label+": rejected with '"+needle+"' got "+str(r.message))
	expect(var_to_str(w.state)==snap,label+": world exactly unchanged")
	expect(w._region==HOME,label+": home orientation")

# ------------------------------------------------------------------- tests --

func test_closure_no_bed() -> void:
	var w=new_world()
	var size:=Vector2i(2,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x,o.y-1)
	prepare_room(w,HOME,o,size,door,A,A)
	var before:=inv(w,A)
	var builds:=int(w.state.players[A].builds)
	var committed:=int(w.state.committed)
	pose(w,A,near(door))
	var r:Dictionary=w.act(A,"close-1","build",door,"door")
	expect(r.ok,"closing door succeeds: "+str(r.message))
	expect(int(r.get("roof_add_count",0))==4 and int(r.get("roof_remove_count",-1))==0,"result reports 4 added, 0 removed")
	expect(str(r.message).contains("自動蓋上屋頂 4 格") and str(r.message).contains("木材 −4") and str(r.message).contains("纖維 −12"),"Chinese cost summary: "+str(r.message))
	expect(not r.has("add") and not r.has("refunds") and not r.has("cost"),"no internal plan in result")
	var after:=inv(w,A)
	expect(int(after.wood)==int(before.wood)-6-4*ROOF_WOOD,"door + roof wood charged once")
	expect(int(after.fiber)==int(before.fiber)-2-4*ROOF_FIBER,"door + roof fiber charged once")
	expect(int(after.stone)==int(before.stone),"stone untouched")
	expect(int(w.state.players[A].builds)==builds+1,"auto roofs do not count as builds")
	expect(int(w.state.committed)==committed+1,"one commit")
	for c in interior(o,size):
		expect(w.state.roofs.get(World.key(c))=={"type":"roof","owner":A,"items":{},"auto":true},"auto roof over interior %s"%c)
	for c in ring(o,size):expect(not w.state.roofs.has(World.key(c)),"no roof over boundary %s"%c)
	var beds:Array=w.state.objects.values().filter(func(obj):return obj.type=="bed")
	expect(beds.is_empty(),"room sealed without any bed")
	# Retry of the same request: original result, no second charge.
	var snap:=var_to_str(w.state)
	var again:Dictionary=w.act(A,"close-1","build",door,"door")
	expect(again==r,"duplicate request returns the original result")
	expect(var_to_str(w.state)==snap,"duplicate request changes nothing")
	# Persisted with the auto flag (requires schema 17 acceptance).
	expect(FileAccess.file_exists(w.save_path),"transaction saved")
	var loaded:=World.new()
	var ok:bool=loaded.load_world(w.save_path)
	expect(ok,"saved world with auto roofs reloads")
	if ok:
		expect(int(loaded.state.version)==preload("res://scripts/save_schema.gd").VERSION,"saved version 20")
		for c in interior(o,size):
			var roof=loaded.state.roofs.get(World.key(c),{})
			expect(roof.get("auto")==true and roof.get("owner")==A,"reloaded auto roof %s"%c)

func test_insufficient_materials() -> void:
	var w=new_world()
	var size:=Vector2i(2,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x+1,o.y+2)
	prepare_room(w,HOME,o,size,door,A,A)
	w.state.players[A].inventory.fiber=2+4*ROOF_FIBER-1
	pose(w,A,near(door))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(A,"short-1","build",door,"door")
	expect(not r.ok and str(r.message).contains("屋頂材料不足"),"insufficient roof materials rejects whole build: "+str(r.message))
	expect(var_to_str(w.state)==snap,"insufficient: state exactly unchanged (no door, builds, receipt, commit)")
	expect(w._region==HOME,"insufficient: home orientation")
	w.state.players[A].inventory.fiber=2+4*ROOF_FIBER
	r=w.act(A,"short-1","build",door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==4,"same request id succeeds once affordable")
	expect(int(w.state.players[A].inventory.fiber)==0,"exactly enough fiber consumed")

func test_multi_owner_refund() -> void:
	var w=new_world()
	var o:=find_site(w,HOME,Vector2i(5,2))
	var size:=Vector2i(2,2)
	var right:=o+Vector2i(3,0)
	var left_door:=Vector2i(o.x,o.y-1)
	var right_door:=Vector2i(right.x+1,o.y-1)
	var r:=do(w,A,"build_area",o,"floor|%d|%d"%[o.x+1,o.y+1],Vector2(o)+Vector2(1,1))
	expect(r.ok,"A floors left room")
	r=do(w,B,"build_area",right,"floor|%d|%d"%[right.x+1,right.y+1],Vector2(right)+Vector2(1,1))
	expect(r.ok,"B floors right room")
	var walls:Array[Vector2i]=[]
	for c in ring(o,size)+ring(right,size):
		if c not in walls and c!=left_door and c!=right_door:walls.append(c)
	for c in walls:
		r=do(w,A,"build",c,"wall")
		expect(r.ok,"A wall %s"%c)
	expect(auto_count(w,HOME)==0,"no roofs before doors")
	var a0:=inv(w,A)
	var b0:=inv(w,B)
	r=do(w,B,"build",left_door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==4,"B closes A's room and pays its roofs")
	for c in interior(o,size):expect(w.state.roofs[World.key(c)].owner==B,"left roof payer is B")
	expect(int(inv(w,B).wood)==int(b0.wood)-6-4 and int(inv(w,B).fiber)==int(b0.fiber)-2-12,"B charged door + 4 roofs")
	expect(inv(w,A)==a0,"floor/wall owner A not charged")
	r=do(w,A,"build",right_door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==4,"A closes B's room")
	for c in interior(right,size):expect(w.state.roofs[World.key(c)].owner==A,"right roof payer is A")
	attempt_unchanged(w,B,"remove",Vector2i(o.x+2,o.y),"","只能拆除自己放置的物件","B cannot remove A's wall")
	# B goes offline (persistent character only).
	w.active_tokens.erase(B)
	var a1:=inv(w,A)
	var b1:=inv(w,B)
	r=do(w,A,"remove",Vector2i(o.x+2,o.y))
	expect(r.ok,"A removes shared wall: "+str(r.message))
	expect(int(r.get("roof_remove_count",0))==8 and int(r.get("roof_add_count",-1))==0,"both rooms opened, 8 roofs removed")
	expect(str(r.message).contains("另有 1 位原出資者") and str(r.message).contains("退回你"),"refund summary without identities: "+str(r.message))
	expect(auto_count(w,HOME)==0,"all auto roofs removed")
	expect(int(inv(w,A).wood)==int(a1.wood)+3+4 and int(inv(w,A).fiber)==int(a1.fiber)+12,"A: wall refund + own 4 roofs")
	expect(int(inv(w,B).wood)==int(b1.wood)+4 and int(inv(w,B).fiber)==int(b1.fiber)+12,"offline B refunded own 4 roofs")
	expect(int(inv(w,B).stone)==int(b1.stone),"B other items untouched")

func test_skip_auto_roof_and_guards() -> void:
	var w=new_world()
	var size:=Vector2i(3,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x+1,o.y-1)
	prepare_room(w,HOME,o,size,door,A,A)
	var r:=do(w,A,"build",door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==6,"3x2 room roofed")
	var bed:=Vector2i(o.x,o.y)
	var chest:=Vector2i(o.x+1,o.y)
	var stove:=Vector2i(o.x+2,o.y)
	var spare:=Vector2i(o.x,o.y+1)
	var a0:=inv(w,A)
	r=do(w,A,"build",bed,"bed")
	expect(r.ok,"bed under auto roof")
	no_roof_fields(r,"furniture build")
	expect(int(inv(w,A).wood)==int(a0.wood)-15 and int(inv(w,A).fiber)==int(a0.fiber)-10,"bed charged only its own recipe")
	expect(do(w,A,"build",chest,"chest").ok,"chest built")
	expect(do(w,A,"deposit",chest,"wood").ok,"wood stored in chest")
	expect(do(w,A,"build",stove,"stove").ok,"stove built")
	w.state.players[A].inventory.radish=2
	expect(do(w,A,"cook",stove,"soup").ok,"stove busy cooking")
	expect(auto_count(w,HOME)==6,"furniture never re-roofs")
	attempt_unchanged(w,B,"remove",bed,"","只能拆除自己放置的物件","other player cannot remove bed under auto roof")
	attempt_unchanged(w,B,"remove",spare,"","只能拆除自己放置的物件","other player cannot remove floor under auto roof")
	attempt_unchanged(w,A,"remove",chest,"","箱子還有物品","non-empty chest preserved")
	attempt_unchanged(w,A,"remove",stove,"","設備仍在工作","busy stove preserved")
	var a1:=inv(w,A)
	r=do(w,A,"remove",bed)
	expect(r.ok,"remove skips auto roof and takes the bed")
	no_roof_fields(r,"bed removal")
	expect(w.state.roofs.get(World.key(bed),{}).get("auto")==true,"auto roof stays over removed bed")
	expect(not w.state.objects.has(World.key(bed)),"bed gone")
	expect(int(inv(w,A).wood)==int(a1.wood)+15 and int(inv(w,A).fiber)==int(a1.fiber)+10,"bed refund only")
	var a2:=inv(w,A)
	r=do(w,A,"remove",bed)
	expect(r.ok and not w.state.ground.has(World.key(bed)),"next remove takes floor under auto roof: "+str(r.message))
	expect(int(r.get("roof_remove_count",0))==6,"room opened, its 6 auto roofs removed")
	expect(auto_count(w,HOME)==0 and not w.state.roofs.has(World.key(bed)),"no orphan roof left over removed floor")
	expect(int(inv(w,A).wood)==int(a2.wood)+2+6 and int(inv(w,A).fiber)==int(a2.fiber)+18,"floor refund + roof refunds to payer")
	expect(int(w.state.objects[World.key(chest)].items.get("wood",0))==1,"chest contents intact")
	expect(w.state.objects[World.key(stove)].has("job"),"stove job intact")

func test_manual_roof_preserved() -> void:
	var w=new_world()
	var size:=Vector2i(2,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x-1,o.y)
	var manual:=Vector2i(o.x+1,o.y+1)
	var r:=do(w,A,"build_area",o,"floor|%d|%d"%[o.x+1,o.y+1],Vector2(o)+Vector2(1,1))
	expect(r.ok,"floors")
	r=do(w,A,"build",manual,"roof")
	expect(r.ok and w.state.roofs[World.key(manual)].get("auto")==null,"manual roof built (no auto flag)")
	for c in ring(o,size):
		if c!=door:expect(do(w,A,"build",c,"wall").ok,"wall %s"%c)
	r=do(w,A,"build",door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==3,"closure fills only the 3 roofless cells")
	expect(not w.state.roofs[World.key(manual)].has("auto"),"manual roof kept as manual")
	var a0:=inv(w,A)
	var builds:=int(w.state.players[A].builds)
	r=do(w,A,"remove",manual)
	expect(r.ok and int(r.get("roof_add_count",0))==0,"manual removal never silently regenerates or charges roofs")
	expect(not w.state.roofs.has(World.key(manual)),"manual roof stays removed while other auto roofs remain")
	var refunded:Dictionary=a0.duplicate(true)
	for item in World.BUILD.roof:
		if item!="name":refunded[item]=int(refunded.get(item,0))+int(World.BUILD.roof[item])
	expect(inv(w,A)==refunded,"manual roof returns its full original recipe")
	expect(int(w.state.players[A].builds)==builds,"builds unchanged")

func test_save_failure_rollback() -> void:
	var w=new_world()
	var size:=Vector2i(2,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x+2,o.y+1)
	prepare_room(w,HOME,o,size,door,A,A)
	var good:String=w.save_path
	w.save_path=dir+"/missing-subdir/world.json"
	pose(w,A,near(door))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(A,"save-1","build",door,"door")
	expect(not r.ok and str(r.message).contains("保存失敗"),"save failure reported")
	expect(var_to_str(w.state)==snap,"save failure: no door, roofs, charges, receipt, builds, commit")
	expect(w._region==HOME,"save failure: home orientation")
	w.save_path=good
	r=w.act(A,"save-1","build",door,"door")
	expect(r.ok and auto_count(w,HOME)==4,"retry after storage recovers")

func test_non_home_region() -> void:
	var w=new_world()
	w.state.players[A].region=LANYANG
	var size:=Vector2i(2,2)
	var o:=find_site(w,LANYANG,size)
	var door:=Vector2i(o.x,o.y+2)
	prepare_room(w,LANYANG,o,size,door,A,A)
	var floor_key:=World.key(o)
	expect(lay(w,LANYANG,"ground").has(floor_key) and not w.state.ground.has(floor_key),"floors live in Lanyang layers")
	w.state.players[A].inventory.wood=6+4*ROOF_WOOD-1
	pose(w,A,near(door))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(A,"lan-1","build",door,"door")
	expect(not r.ok and str(r.message).contains("屋頂材料不足"),"Lanyang shortfall rejected")
	expect(var_to_str(w.state)==snap,"Lanyang shortfall: exactly unchanged")
	expect(w._region==HOME and not is_same(w.state.roofs,w.state.regions[LANYANG].roofs) and not is_same(w.state.ground,w.state.regions[LANYANG].ground),"layers not aliased after rollback")
	expect(lay(w,LANYANG,"ground").has(floor_key) and not w.state.ground.has(floor_key),"rollback keeps region layers in place")
	w.state.players[A].inventory.wood=6+4*ROOF_WOOD
	var good:String=w.save_path
	w.save_path=dir+"/missing-lanyang/world.json"
	snap=var_to_str(w.state)
	r=w.act(A,"lan-1","build",door,"door")
	expect(not r.ok and str(r.message).contains("保存失敗"),"Lanyang save failure")
	expect(var_to_str(w.state)==snap and w._region==HOME,"Lanyang save failure: unchanged, home orientation")
	w.save_path=good
	r=w.act(A,"lan-1","build",door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==4,"Lanyang room roofed")
	expect(auto_count(w,LANYANG)==4 and auto_count(w,HOME)==0,"roofs written to Lanyang only")
	expect(int(w.state.players[A].inventory.wood)==0,"exact wood used")
	w.state.players[A].inventory.wood=100
	r=do(w,A,"remove",Vector2i(o.x-1,o.y))
	expect(r.ok and int(r.get("roof_remove_count",0))==4,"Lanyang wall removal refunds roofs")
	expect(auto_count(w,LANYANG)==0,"Lanyang roofs gone")

func test_unrelated_actions() -> void:
	var w=new_world()
	var size:=Vector2i(2,2)
	var o:=find_site(w,HOME,size)
	var door:=Vector2i(o.x+1,o.y-1)
	# Legacy sealed room written directly (as from an old save): no roofs.
	for c in interior(o,size):w.state.ground[World.key(c)]={"type":"floor","owner":A,"items":{}}
	for c in ring(o,size):
		w.state.objects[World.key(c)]={"type":"wall","owner":A,"items":{}} if c!=door else {"type":"door","owner":A,"items":{},"open":false}
	var bed:=Vector2i(o.x,o.y)
	var r:=do(w,A,"build",bed,"bed")
	expect(r.ok,"bed in legacy room");no_roof_fields(r,"bed")
	r=do(w,A,"move_object",bed,"%d,%d"%[o.x+1,o.y+1],Vector2(o)+Vector2(-0.5,2.5))
	expect(r.ok,"bed moved: "+str(r.message));no_roof_fields(r,"move")
	r=do(w,A,"door",door)
	expect(r.ok,"door opened");no_roof_fields(r,"door open")
	r=do(w,A,"door",door)
	expect(r.ok,"door closed");no_roof_fields(r,"door close")
	r=do(w,A,"build",Vector2i(o.x-2,o.y),"path")
	expect(r.ok,"path beside room");no_roof_fields(r,"path")
	r=do(w,A,"build_area",Vector2i(o.x,o.y+3),"path|%d|%d"%[o.x+1,o.y+3],Vector2(o)+Vector2(1,3.5))
	expect(r.ok,"path area");no_roof_fields(r,"path area")
	r=do(w,A,"hoe",Vector2i(o.x+3,o.y+3))
	expect(r.ok,"hoe");no_roof_fields(r,"hoe")
	var a0:=inv(w,A)
	r=do(w,A,"build",Vector2i(o.x-2,o.y+1),"floor")
	expect(r.ok,"floor outside wall");no_roof_fields(r,"floor elsewhere")
	expect(int(inv(w,A).wood)==int(a0.wood)-2 and int(inv(w,A).fiber)==int(a0.fiber),"floor elsewhere charges floor only")
	expect(auto_count(w,HOME)==0 and w.state.roofs.is_empty(),"untouched legacy room not batch-roofed")
	r=do(w,A,"remove",door)
	expect(r.ok,"door removed");no_roof_fields(r,"opening")
	r=do(w,A,"build",door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==4,"rebuilding the door touches the room and roofs it")
