extends SceneTree
## T042 public kitchen through the real World.act / World.step / save / load
## path. Contract (authoritative): docs/public-kitchen-contract.json.
##
## API under test (core/helper may still be in progress; missing pieces count
## as FAILED checks, never skips):
##   World.act(token, rid, "kitchen_register", stove_cell, "seat|seat")
##   World.act(token, rid, "kitchen_contribute", stove_cell, "")
##   World.state.public_kitchen  {stove, seats, meals{soup,bread,salad}, opened}
##   res://scripts/public_kitchen.gd  static events(state) (read-only replay)
##
## Fixture label: LABEL. Seeded values (surplus meals, request-id tag) come from
## RandomNumberGenerator seeded with SEED.
##
## Every object in the site (stoves, long benches, chair, lamp, walls) is placed,
## removed and cooked on through World.act; the board and picnic are completed
## through the real donate / picnic actions. Explicit FIXTURE writes (not normal
## play) are limited to, and labelled where they happen:
##   - backpack stock (building materials, radish, prepared soup/bread/salad);
##   - players' aru story stage = 2 (Village.unlocked gate for long_bench);
##   - player positions (pose) and one Lanyang-projection position;
##   - FakeClock injection for construction-undo windows;
##   - edited copies of a real save file for the legacy-version load checks.
## Every world saves into one fresh random directory under TEMP; cleanup only
## removes files inside that directory, which this run created.
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Community=preload("res://scripts/community.gd")
const REGIONS=preload("res://scripts/regions.gd")

const HELPER_PATH:="res://scripts/public_kitchen.gd"
const CONTRACT_PATH:="res://docs/public-kitchen-contract.json"
const SEED:=20261114
const LABEL:="public-kitchen-world/seed-20261114"
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const C:="tok-chen-SECRET"
const D:="tok-dara-SECRET"
const HOME:=REGIONS.HOME
const LANYANG:=REGIONS.LANYANG
const BOARD:=Vector2i(40,29)
const TABLE:=Vector2i(39,30)
# Site layout (all on the resource-free ferry plaza, outside protected cells).
const STOVE:=Vector2i(42,34)          # A, 5.0 from table
const SEAT1:=Vector2i(40,34)          # A long_bench, 2 from stove
const SEAT2:=Vector2i(44,34)          # A long_bench, 2 from stove (built last)
const SEAT3:=Vector2i(44,36)          # A long_bench, 2.83 from stove
const CHAIR:=Vector2i(41,36)          # A chair (not a long_bench), 2.24 from stove
const FAR_SEAT:=Vector2i(36,34)       # A long_bench, 6 from stove
const FAR_STOVE:=Vector2i(45,37)      # A stove, 9.22 from table (>8)
const FAR_STOVE_SEAT:=Vector2i(43,37) # A long_bench, 2 from FAR_STOVE
const B_STOVE:=Vector2i(36,31)        # B stove
const B_BENCH:=Vector2i(42,36)        # B long_bench, 2 from STOVE
const B_LAMP:=Vector2i(37,36)         # B lamp, B's last unrelated construction
const WALLS:=[Vector2i(41,34),Vector2i(43,34),Vector2i(42,33),Vector2i(42,35)]
const PARK:=Vector2(36.5,36.5)
const NAMES:={A:"Alice",B:"Bob",C:"Chen",D:"Dara"}

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

var checks:=0
var failures:=0
var serial:=0
var dir:=""
var tag:=""
var clock:FakeClock
var rng:=RandomNumberGenerator.new()
var req:Dictionary={}
var fresh_pk:Dictionary={}

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	rng.seed=SEED
	tag="%08x"%rng.randi()
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_environment("TMPDIR")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("public-kitchen-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt an existing test directory")
		print("PUBLIC_KITCHEN_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated TEMP directory created")
	print("PUBLIC_KITCHEN_WORLD fixture=%s"%LABEL)
	load_contract()
	test_fresh_and_helper()
	test_pre_picnic()
	test_main_flow()
	cleanup()
	print("PUBLIC_KITCHEN_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

# ------------------------------------------------------------------ setup --

func load_contract() -> void:
	var parser:=JSON.new()
	var parsed_ok:=parser.parse(FileAccess.get_file_as_string(CONTRACT_PATH))==OK and parser.data is Dictionary
	expect(parsed_ok,"contract JSON readable")
	var data:Dictionary=parser.data if parsed_ok else {}
	var raw_req=data.get("requirements",{})
	for meal in ["soup","bread","salad"]:
		req[meal]=int(raw_req.get(meal,-1)) if raw_req is Dictionary else -1
	expect(req=={"soup":4,"bread":2,"salad":2},"contract requirements soup4/bread2/salad2: "+str(req))
	expect(req==Schema.KITCHEN_MEALS,"SaveSchema meal caps follow the contract")
	expect(int(data.get("save_version",-1))==int(Schema.VERSION),"contract save_version matches SaveSchema.VERSION")
	var meals:={}
	for meal in req:meals[meal]=0
	fresh_pk={"stove":"","seats":[],"meals":meals,"opened":false}
	var raw_state=data.get("state",{}).get("public_kitchen",{}) if data.get("state") is Dictionary else {}
	var contract_fresh:={}
	if raw_state is Dictionary and raw_state.get("meals") is Dictionary:
		var cm:={}
		for meal in raw_state.meals:cm[str(meal)]=int(raw_state.meals[meal])
		contract_fresh={"stove":raw_state.get("stove"),"seats":raw_state.get("seats"),"meals":cm,"opened":raw_state.get("opened")}
	expect(contract_fresh==fresh_pk,"contract fresh public_kitchen shape parsed")

func cleanup() -> void:
	_remove_tree(dir)

func _remove_tree(path:String) -> void:
	var root_path:=dir.replace("\\","/").simplify_path()
	var target:=path.replace("\\","/").simplify_path()
	if not root_path.is_absolute_path() or (target!=root_path and not target.begins_with(root_path+"/")):
		expect(false,"cleanup target escaped the owned temporary directory")
		return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):_remove_tree(path.path_join(sub))
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

func attach(w,c:FakeClock) -> void:
	w.undo_clock_utc=Callable(c,"now_utc")
	w.undo_clock_ticks=Callable(c,"now_ticks")

func new_world():
	var w=World.new()
	for t in [A,B,C]:w.add_player(t,NAMES[t])
	for t in [A,B,C]:
		# FIXTURE: explicit backpack stock (not normal-play balances).
		w.state.players[t].inventory={"wood":500,"stone":200,"fiber":120,"radish":12}
	for t in [A,B]:
		# FIXTURE: aru story stage 2 unlocks the long_bench pattern (Village.unlocked).
		var stories=w.state.players[t].get("stories",{})
		stories["aru"]=maxi(2,int(stories.get("aru",0)))
		w.state.players[t]["stories"]=stories
	# FIXTURE: prepared meals for the real picnic action (2 soup + 1 bread).
	w.state.players[A].inventory["soup"]=2
	w.state.players[A].inventory["bread"]=1
	serial+=1
	w.save_path=dir.path_join("world-%d.json"%serial)
	clock=FakeClock.new()
	attach(w,clock)
	return w

func helper():
	if not ResourceLoader.exists(HELPER_PATH):return null
	var s=load(HELPER_PATH)
	return s if s is Script else null

func script_has(s,method:String) -> bool:
	if s==null:return false
	for m in s.get_script_method_list():
		if str(m.get("name",""))==method:return true
	return false

func reserved() -> Array:
	var out:Array=[STOVE,SEAT1,SEAT2,SEAT3,CHAIR,FAR_SEAT,FAR_STOVE,FAR_STOVE_SEAT,B_STOVE,B_BENCH,B_LAMP,BOARD]
	out.append_array(WALLS)
	out.append_array(Community.CANDIDATES)
	return out

## Closest standable HOME position 1..2.9 tiles from `target`, never on a site cell.
func stand_near(w,target:Vector2i) -> Vector2:
	var best:=Vector2.ZERO
	var best_d:=INF
	var skip:=reserved()
	var centre:=Vector2(target)+Vector2(0.5,0.5)
	for dy in range(-3,4):
		for dx in range(-3,4):
			var c:=target+Vector2i(dx,dy)
			if c in skip:continue
			var pos:=Vector2(c)+Vector2(0.5,0.5)
			var d:=pos.distance_to(centre)
			if d<0.99 or d>2.9 or not w.can_stand(pos):continue
			if d<best_d:
				best=pos
				best_d=d
	expect(best_d<INF,"fixture: standable spot near "+World.key(target))
	return best

func pose(w,token:String,at:Vector2) -> void:
	# FIXTURE: positions written directly; everyone else waits at PARK.
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else PARK
		person.x=spot.x
		person.y=spot.y

func next_rid() -> String:
	serial+=1
	return "pk-%s-%d"%[tag,serial]

func leak_free(value,label:String) -> void:
	var text:=var_to_str(value)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks player tokens")

func act(w,token:String,action:String,p:Vector2i,extra:String="",at=null,rid:String="") -> Dictionary:
	pose(w,token,stand_near(w,p) if at==null else at)
	if rid=="":rid=next_rid()
	var r:Dictionary=w.act(token,rid,action,p,extra)
	leak_free(r,"result %s %s"%[action,extra])
	expect(w._region==HOME,"home orientation after "+action)
	return r

func must(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null) -> Dictionary:
	var r:=act(w,token,action,p,extra,at)
	expect(r.get("ok",false)==true,label+": "+str(r.get("message","")))
	return r

## Rejected action: ok=false with a reason and the whole world state unchanged.
func refuse(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null) -> Dictionary:
	pose(w,token,stand_near(w,p) if at==null else at)
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(token,next_rid(),action,p,extra)
	leak_free(r,label)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": rejected with a reason, got "+str(r))
	expect(var_to_str(w.state)==snap,label+": world state unchanged")
	expect(w._region==HOME,label+": home orientation")
	return r

func pk(w) -> Dictionary:
	var v=w.state.get("public_kitchen")
	return v if v is Dictionary else {}

func expected_pk(stove:String,seats:Array,meals:Dictionary,opened:bool) -> Dictionary:
	return {"stove":stove,"seats":seats,"meals":meals,"opened":opened}

func inv(w,token:String) -> Dictionary:
	var out:={}
	var src:Dictionary=w.state.players[token].inventory
	for item in src:
		if int(src[item])!=0:out[str(item)]=int(src[item])
	return out

func diff(before:Dictionary,after:Dictionary) -> Dictionary:
	var out:={}
	var keys:=before.keys()
	for k in after:
		if not k in keys:keys.append(k)
	for k in keys:
		var d:=int(after.get(k,0))-int(before.get(k,0))
		if d!=0:out[str(k)]=d
	return out

func layers(w) -> String:
	return var_to_str([w.state.objects,w.state.ground,w.state.roofs,w.state.crops,w.state.forest])

func summary(w,token:String) -> Dictionary:
	var s=w.undo_summary(token)
	expect(s is Dictionary,"undo_summary returns a Dictionary")
	return s if s is Dictionary else {}

## Helper events(state); every read must leave the state byte-identical.
func events_of(state:Dictionary,label:String) -> Array:
	var h=helper()
	if not script_has(h,"events"):
		expect(false,label+": public_kitchen.gd exposes static events(state)")
		return []
	var before:=var_to_str(state)
	var ev=h.call("events",state)
	expect(var_to_str(state)==before,label+": reading events never mutates state")
	expect(ev is Array,label+": events(state) returns an Array")
	leak_free(ev,label+" events")
	return ev if ev is Array else []

func is_prefix(old:Array,new:Array,label:String) -> void:
	var same:=new.size()>=old.size()
	if same:
		for i in old.size():
			if new[i]!=old[i]:same=false
	expect(same,label+": earlier events stay immutable (prefix)")

# ------------------------------------------------------------------ tests --

func test_fresh_and_helper() -> void:
	var w=World.new()
	expect(int(w.state.version)==int(Schema.VERSION),"fresh world follows SaveSchema.VERSION")
	expect(pk(w)==fresh_pk,"fresh world carries the exact unregistered public_kitchen: "+str(w.state.get("public_kitchen")))
	expect(pk(w)==Schema.public_kitchen_fresh(),"fresh world equals SaveSchema.public_kitchen_fresh()")
	var h=helper()
	expect(h!=null,"helper script "+HELPER_PATH+" loads")
	if h!=null:
		var src:=FileAccess.get_file_as_string(HELPER_PATH)
		expect(not src.contains("res://scripts/world.gd"),"helper does not preload World")
		for m in ["fresh","valid","registered","stage","site_cells","candidate_stoves","candidate_seats","events","perform"]:
			expect(script_has(h,m),"helper exposes "+m)
		if script_has(h,"fresh"):expect(h.call("fresh")==fresh_pk,"helper fresh() matches contract")

func test_pre_picnic() -> void:
	var w=new_world()
	must(w,A,"donate",BOARD,"","pre-picnic: board via real donate")
	for spec in [[STOVE,"stove"],[SEAT1,"long_bench"],[SEAT2,"long_bench"]]:
		must(w,A,"build",spec[0],spec[1],"pre-picnic build "+spec[1])
	expect(not w.state.picnic and Community.table_cell(w.state)==Community.NO_CELL,"pre-picnic: no shared table yet")
	refuse(w,A,"kitchen_register",STOVE,"40,34|44,34","register before picnic/shared table")
	refuse(w,A,"kitchen_contribute",STOVE,"","contribute before picnic")
	expect(pk(w)==fresh_pk,"pre-picnic: kitchen stays fresh")

func test_main_flow() -> void:
	var w=new_world()
	must(w,A,"donate",BOARD,"","board via real donate")
	expect(w.state.board==true,"board repaired")
	var ev0:=events_of(w.state,"before picnic")
	must(w,A,"picnic",BOARD,"","picnic via real act")
	var table:=Community.table_cell(w.state)
	expect(table==TABLE,"shared table at %s, got %s"%[World.key(TABLE),World.key(table)])
	expect((STOVE-table).length_squared()<=64 and (FAR_STOVE-table).length_squared()>64,"fixture geometry: stove in 8, far stove beyond 8")
	var ev1:=events_of(w.state,"after picnic")
	expect(ev1.size()>=1,"picnic invitation unlocked after picnic")
	is_prefix(ev0,ev1,"after picnic")
	for spec in [[A,STOVE,"stove"],[A,SEAT1,"long_bench"],[A,SEAT3,"long_bench"],[A,CHAIR,"chair"],[A,FAR_SEAT,"long_bench"],[A,FAR_STOVE,"stove"],[A,FAR_STOVE_SEAT,"long_bench"],[B,B_STOVE,"stove"],[B,B_BENCH,"long_bench"]]:
		must(w,spec[0],"build",spec[1],spec[2],"build %s at %s"%[spec[2],World.key(spec[1])])
		var o=w.state.objects.get(World.key(spec[1]),{})
		expect(o.get("type")==spec[2] and o.get("owner")==spec[0],"built %s owned by builder"%World.key(spec[1]))
	expect(pk(w)==fresh_pk,"building alone never registers")
	refuse(w,A,"kitchen_contribute",STOVE,"","contribute before registration")
	var good:="40,34|44,36"
	# ownership / identity
	refuse(w,C,"kitchen_register",STOVE,good,"member owning nothing registers A's stove")
	refuse(w,B,"kitchen_register",STOVE,good,"B registers A's stove and seats")
	refuse(w,A,"kitchen_register",STOVE,"40,34|42,36","seat owned by another member")
	refuse(w,A,"kitchen_register",STOVE,"40,34|41,36","chair is not a long_bench")
	refuse(w,A,"kitchen_register",SEAT1,good,"p is a bench, not a stove")
	refuse(w,A,"kitchen_register",CHAIR,good,"p is a chair, not a stove")
	# range
	refuse(w,A,"kitchen_register",STOVE,"36,34|40,34","seat beyond 3 tiles of stove")
	refuse(w,A,"kitchen_register",FAR_STOVE,"43,37|44,36","stove beyond 8 tiles of shared table")
	# canonical extra
	for bad in ["40,34|40,34","44,36|40,34","40,34","40,34|44,36|41,36","40,34|","","40,34;44,36","40,34 | 44,36"," 40,34|44,36","40,34|44,36 ","40,34|044,36","-1,34|40,34","40,34|+44,36","40.0,34|44,36","40,34|44,３６","1000000000000,34|1000000000000,36"]:
		refuse(w,A,"kitchen_register",STOVE,bad,"non-canonical seat extra '%s'"%bad)
	# reach
	refuse(w,A,"kitchen_register",STOVE,good,"actor out of reach",PARK)
	# blocked cardinal path: A walls the stove in through real builds, then removes them.
	for c in WALLS:must(w,A,"build",c,"wall","wall around stove at "+World.key(c))
	refuse(w,A,"kitchen_register",STOVE,good,"stove has no passable cardinal access")
	for c in WALLS:must(w,A,"remove",c,"","remove wall at "+World.key(c))
	for c in WALLS:expect(not w.state.objects.has(World.key(c)),"wall removed at "+World.key(c))
	# busy stove regardless of job owner
	must(w,B,"cook",STOVE,"soup","B cooks on A's stove")
	expect(w.state.objects[World.key(STOVE)].has("job"),"stove has an active job")
	refuse(w,A,"kitchen_register",STOVE,good,"stove busy with another member's job")
	must(w,B,"cancel_cook",STOVE,"","B cancels own job")
	must(w,A,"cook",STOVE,"soup","A cooks soup")
	expect(w.step(float(World.RECIPES.soup.time)+1.0,true),"world step to finish soup")
	refuse(w,A,"kitchen_register",STOVE,good,"stove holds finished unclaimed output")
	must(w,A,"claim_cook",STOVE,"","A claims soup")
	var stove_obj:Dictionary=w.state.objects[World.key(STOVE)]
	expect(not stove_obj.has("job") and not stove_obj.has("cooking"),"stove idle again (no job/cooking record)")
	region_reject(w)
	# Final constructions: B's unrelated lamp, then A's last seat.
	must(w,B,"build",B_LAMP,"lamp","B unrelated lamp")
	must(w,A,"build",SEAT2,"long_bench","A builds second seat last")
	var a_sum:=summary(w,A)
	var a_id:=str(a_sum.get("id",""))
	expect(a_sum.get("available")==true and a_id!="","A's seat build is undoable before donation: "+str(a_sum))
	var b_sum:=summary(w,B)
	expect(b_sum.get("available")==true,"B's lamp is undoable before donation: "+str(b_sum))
	expect(w.save(),"pre-registration save")
	var legacy_text:=FileAccess.get_file_as_string(w.save_path)
	# save failure then success with the same request id
	var extra:="40,34|44,34"
	var rid:=next_rid()
	var good_path:String=w.save_path
	var missing:=dir.path_join("missing-subdir")
	w.save_path=missing.path_join("world.json")
	pose(w,A,stand_near(w,STOVE))
	var snap:=var_to_str(w.state)
	var r:Dictionary=w.act(A,rid,"kitchen_register",STOVE,extra)
	expect(r.get("ok",true)==false and str(r.get("message","")).contains("保存失敗"),"register save failure reported: "+str(r))
	expect(var_to_str(w.state)==snap,"register save failure rolls back everything")
	expect(summary(w,A).get("available")==true,"undo still open after failed registration")
	expect(not DirAccess.dir_exists_absolute(missing),"failed save created nothing outside test files")
	w.save_path=good_path
	var layer_snap:=layers(w)
	var inv_a:=inv(w,A)
	var coins_a:=int(w.state.players[A].coins)
	var reg:Dictionary=w.act(A,rid,"kitchen_register",STOVE,extra)
	leak_free(reg,"register result")
	expect(reg.get("ok",false)==true,"A registers stove + two seats: "+str(reg.get("message","")))
	var meals0:Dictionary=fresh_pk.meals.duplicate()
	var registered:=expected_pk("42,34",["40,34","44,34"],meals0,false)
	expect(pk(w)==registered,"public_kitchen records exactly stove and sorted seats: "+str(w.state.get("public_kitchen")))
	leak_free(pk(w),"public_kitchen")
	expect(layers(w)==layer_snap,"registration places/moves/overwrites nothing")
	expect(inv(w,A)==inv_a and int(w.state.players[A].coins)==coins_a,"registration costs and rewards nothing")
	var parser:=JSON.new()
	var saved_ok:=parser.parse(FileAccess.get_file_as_string(good_path))==OK and parser.data is Dictionary
	var saved_pk=parser.data.get("public_kitchen",{}) if saved_ok else {}
	expect(saved_pk is Dictionary and saved_pk.get("stove")=="42,34" and saved_pk.get("seats")==["40,34","44,34"],"registration persisted in the same save")
	var ev2:=events_of(w.state,"after registration")
	expect(ev2.size()>ev1.size(),"registration event unlocked")
	is_prefix(ev1,ev2,"after registration")
	for c in [STOVE,SEAT1,SEAT2]:expect(w.protected(c),"donated cell protected at HOME: "+World.key(c))
	for c in [SEAT3,CHAIR,FAR_STOVE]:expect(not w.protected(c),"undonated cell stays unprotected: "+World.key(c))
	w.switch_region(LANYANG)
	for c in [STOVE,SEAT1,SEAT2]:expect(w.protected(c)==REGIONS.protected(c,LANYANG),"protection is HOME only (Lanyang projection) "+World.key(c))
	w.switch_region(HOME)
	# replay
	pose(w,A,stand_near(w,STOVE))
	snap=var_to_str(w.state)
	expect(w.act(A,rid,"kitchen_register",STOVE,extra)==reg,"replayed request returns the stored receipt")
	expect(var_to_str(w.state)==snap,"replay mutates nothing")
	refuse(w,A,"kitchen_register",STOVE,extra,"second registration (one per world)")
	refuse(w,A,"kitchen_register",STOVE,good,"re-registration with other seats")
	refuse(w,B,"kitchen_register",B_STOVE,good,"another member cannot register a second kitchen")
	# undo / remove / move protection
	var after_sum:=summary(w,A)
	expect(after_sum.get("available")!=true and str(after_sum.get("reason","")).length()>0,"donation closes A's earlier construction undo: "+str(after_sum))
	refuse(w,A,"undo_build",SEAT2,a_id,"undo of donated seat build")
	expect(w.state.objects.get(World.key(SEAT2),{}).get("type")=="long_bench","donated seat still in place")
	var b_after:=summary(w,B)
	expect(b_after.get("available")==b_sum.get("available") and b_after.get("id")==b_sum.get("id"),"unrelated foreign undo record untouched")
	for c in [STOVE,SEAT1,SEAT2]:
		refuse(w,A,"remove",c,"","owner removes donated "+World.key(c))
		var dest:=Vector2i(c.x,33)
		refuse(w,A,"move_object",c,World.key(dest),"owner moves donated "+World.key(c),Vector2(c)+Vector2(0.5,-1.5))
		refuse(w,B,"remove",c,"","other member removes donated "+World.key(c))
	must(w,A,"remove",FAR_SEAT,"","undonated own bench still removable")
	expect(not w.state.objects.has(World.key(FAR_SEAT)),"undonated bench removed")
	var rid_full:=contributions(w)
	var ev3:=events_of(w.state,"after opening")
	expect(ev3.size()>ev2.size(),"opening event unlocked")
	is_prefix(ev2,ev3,"after opening")
	# cooking by other members at the public stove still uses existing actions
	var kitchen_snap:=var_to_str(pk(w))
	must(w,B,"cook",STOVE,"soup","B cooks at the public stove")
	expect(w.step(float(World.RECIPES.soup.time)+1.0,true),"world step to finish public soup")
	var c_soup:=int(w.state.players[C].inventory.get("soup",0))
	must(w,C,"claim_cook",STOVE,"","C claims at the public stove")
	expect(int(w.state.players[C].inventory.get("soup",0))==c_soup+int(World.RECIPES.soup["yield"]),"claim gives the normal recipe yield")
	must(w,C,"queue_cook",STOVE,"soup","C queues at the public stove")
	expect(var_to_str(pk(w))==kitchen_snap,"cooking never changes the kitchen record")
	refuse(w,A,"remove",STOVE,"","owner removes public stove while cooking")
	# reload + late joiner
	expect(w.save(),"save before reload")
	var w2=World.new()
	expect(w2.load_world(good_path),"registered, opened kitchen with active queue reloads")
	attach(w2,clock)
	expect(var_to_str(pk(w2))==var_to_str(pk(w)),"public_kitchen identical after reload")
	w2.add_player(D,NAMES[D])
	var snap2:=var_to_str(w2.state)
	var late:=events_of(w2.state,"late joiner after reload")
	expect(late==ev3 and late.size()>0,"late joiner sees the same events including opening")
	for i in 4:expect(events_of(w2.state,"repeat read %d"%i)==late,"repeated reading %d stable"%i)
	expect(var_to_str(w2.state)==snap2,"repeated reading leaves the reloaded world untouched")
	# FIXTURE: late joiner carries meals, but the kitchen is already full.
	w2.state.players[D].inventory["soup"]=2
	refuse(w2,D,"kitchen_contribute",STOVE,"","late joiner contributes after opening")
	refuse(w2,A,"remove",STOVE,"","donated stove still protected after reload")
	expect(w2.protected(STOVE) and w2.protected(SEAT1) and w2.protected(SEAT2),"protection survives reload")
	pose(w2,B,stand_near(w2,STOVE))
	snap2=var_to_str(w2.state)
	var replay:Dictionary=w2.act(B,rid_full,"kitchen_contribute",STOVE,"")
	expect(replay.get("ok")==true and str(replay.get("message",""))!="","persisted receipt replays after reload: "+str(replay))
	expect(var_to_str(w2.state)==snap2,"replay after reload mutates nothing")
	must(w2,C,"cancel_cook",STOVE,"","queued public stove job survives reload and cancels")
	test_legacy(legacy_text)

## Region check: A really travels to Lanyang, then tries to register home cells.
func region_reject(w) -> void:
	must(w,A,"travel",REGIONS.exit_cell(HOME),LANYANG,"A travels to Lanyang")
	if w.player_region(A)!=LANYANG:
		expect(false,"A is in Lanyang for the region check")
		return
	var arrival:=Vector2(w.state.players[A].x,w.state.players[A].y)
	# FIXTURE: Lanyang position within reach of the home stove coordinates, so only the region differs.
	refuse(w,A,"kitchen_register",STOVE,"40,34|44,36","register home stove from Lanyang",Vector2(STOVE)+Vector2(0.5,-1.5))
	must(w,A,"travel",REGIONS.exit_cell(LANYANG),HOME,"A travels home",arrival)
	expect(w.player_region(A)==HOME,"A back home")

## Partial / no-op / replay / save-failure / full contributions. Returns B's rid.
func contributions(w) -> String:
	var es:=rng.randi_range(0,3)
	var eb:=rng.randi_range(0,3)
	var ec:=rng.randi_range(0,3)
	# FIXTURE: prepared meals already in backpacks (contract: donate EXISTING meals).
	var ia:Dictionary=w.state.players[A].inventory
	ia["soup"]=3;ia["bread"]=1;ia["salad"]=0;ia["carrot_soup"]=2
	var ib:Dictionary=w.state.players[B].inventory
	ib["soup"]=1+es;ib["bread"]=1+eb;ib["salad"]=2+ec
	var ic:Dictionary=w.state.players[C].inventory
	ic["soup"]=0;ic["bread"]=0;ic["salad"]=0
	refuse(w,A,"kitchen_contribute",SEAT1,"","contribute at a seat, not the stove")
	refuse(w,A,"kitchen_contribute",FAR_STOVE,"","contribute at an unregistered stove")
	refuse(w,A,"kitchen_contribute",STOVE,"soup","contribute with non-empty extra")
	refuse(w,A,"kitchen_contribute",STOVE,"","contributor out of reach",PARK)
	refuse(w,C,"kitchen_contribute",STOVE,"","member with no soup/bread/salad")
	# partial
	var rid_a:=next_rid()
	pose(w,A,stand_near(w,STOVE))
	var before_a:=inv(w,A)
	var before_b:=inv(w,B)
	var before_c:=inv(w,C)
	var coins:=[int(w.state.players[A].coins),int(w.state.players[B].coins)]
	var obj_snap:=layers(w)
	var ra:Dictionary=w.act(A,rid_a,"kitchen_contribute",STOVE,"")
	leak_free(ra,"partial contribution")
	expect(ra.get("ok",false)==true,"partial contribution accepted: "+str(ra.get("message","")))
	expect(pk(w).get("meals")=={"soup":3,"bread":1,"salad":0} and pk(w).get("opened")==false,"partial meals recorded, still closed: "+str(pk(w)))
	expect(diff(before_a,inv(w,A))=={"soup":-3,"bread":-1},"A gives min(backpack,need) only; no reward/item creation: "+str(diff(before_a,inv(w,A))))
	expect(inv(w,B)==before_b and inv(w,C)==before_c,"other backpacks untouched")
	expect(int(w.state.players[A].coins)==coins[0],"no coin reward")
	expect(layers(w)==obj_snap,"contribution changes no objects")
	pose(w,A,stand_near(w,STOVE))
	var snap:=var_to_str(w.state)
	expect(w.act(A,rid_a,"kitchen_contribute",STOVE,"")==ra,"partial replay returns stored receipt")
	expect(var_to_str(w.state)==snap,"partial replay mutates nothing")
	refuse(w,A,"kitchen_contribute",STOVE,"","A has nothing left that is still needed")
	# full, after a save failure with the same request id
	var rid_b:=next_rid()
	var good_path:String=w.save_path
	w.save_path=dir.path_join("missing-subdir").path_join("world.json")
	pose(w,B,stand_near(w,STOVE))
	snap=var_to_str(w.state)
	var rf:Dictionary=w.act(B,rid_b,"kitchen_contribute",STOVE,"")
	expect(rf.get("ok",true)==false and str(rf.get("message","")).contains("保存失敗"),"contribution save failure reported")
	expect(var_to_str(w.state)==snap,"contribution save failure rolls back meals, flag and inventory")
	w.save_path=good_path
	before_b=inv(w,B)
	var rb:Dictionary=w.act(B,rid_b,"kitchen_contribute",STOVE,"")
	expect(rb.get("ok",false)==true,"B completes the kitchen: "+str(rb.get("message","")))
	expect(pk(w).get("meals")==req and pk(w).get("opened")==true,"opened exactly when all needs filled: "+str(pk(w)))
	expect((w.island_project_mask() & 16)!=0,"Kitchen opening appears in island news")
	expect(diff(before_b,inv(w,B))=={"soup":-1,"bread":-1,"salad":-2},"B gives only outstanding need, keeps surplus %d/%d/%d"%[es,eb,ec])
	expect(int(w.state.players[B].coins)==coins[1],"no coin reward on completion")
	pose(w,B,stand_near(w,STOVE))
	snap=var_to_str(w.state)
	expect(w.act(B,rid_b,"kitchen_contribute",STOVE,"")==rb,"full replay returns stored receipt")
	expect(var_to_str(w.state)==snap,"full replay mutates nothing")
	# FIXTURE: C now holds a soup, but nothing is outstanding.
	w.state.players[C].inventory["soup"]=1
	refuse(w,C,"kitchen_contribute",STOVE,"","contribution after opening")
	for c in [STOVE,SEAT1,SEAT2]:refuse(w,A,"remove",c,"","donated object still protected after opening "+World.key(c))
	return rid_b

## Legacy saves: copies of a real version-23 save edited to an older version.
func test_legacy(text:String) -> void:
	var parser:=JSON.new()
	var ok:=parser.parse(text)==OK and parser.data is Dictionary
	expect(ok,"legacy: captured save parses")
	if not ok:return
	var older:=int(Schema.PUBLIC_KITCHEN_VERSION)-1
	var without:Dictionary=(parser.data as Dictionary).duplicate(true)
	# FIXTURE: legacy save without the field (picnic, table, stove, seats all eligible).
	without.erase("public_kitchen")
	without.version=older
	without.erase("flower_nursery")
	without.regions.erase("tianwei")
	without.erase("salt_pan")
	without.regions.erase("beimen")
	var p1:=dir.path_join("legacy-without.json")
	write_text(p1,JSON.stringify(without))
	var w=World.new()
	expect(w.load_world(p1),"legacy save without public_kitchen loads")
	expect(pk(w)==fresh_pk,"legacy save gets fresh kitchen only, no auto-donation: "+str(w.state.get("public_kitchen")))
	expect(not w.protected(STOVE) and not w.protected(SEAT1),"legacy load protects nothing")
	var carrying:Dictionary=(parser.data as Dictionary).duplicate(true)
	# FIXTURE: older version carrying the field = unknown forward state.
	carrying.public_kitchen=fresh_pk.duplicate(true)
	carrying.version=older
	carrying.erase("flower_nursery")
	carrying.regions.erase("tianwei")
	carrying.erase("salt_pan")
	carrying.regions.erase("beimen")
	var p2:=dir.path_join("legacy-carrying.json")
	write_text(p2,JSON.stringify(carrying))
	expect(not World.new().load_world(p2),"older save carrying public_kitchen rejected")

func write_text(path:String,text:String) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	expect(f!=null,"fixture file writable: "+path.get_file())
	if f==null:return
	f.store_string(text)
	f.close()
