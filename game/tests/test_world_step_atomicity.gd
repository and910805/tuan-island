extends SceneTree
## World.step tick atomicity when SaltPan.step rejects (root review item 3).
## Runs the REAL World (act/step/save/load_world) against either the baseline
## snapshot or the staged project; the same file is used for both so the
## baseline run reproduces the defect and the staged run proves the fix.
##
## FAULT-INJECTION FIXTURE, NOT NORMAL GAMEPLAY (each write is labelled):
##  * FAULT: salt_pan.pans[3].s="mud" -- an invalid pan state that valid() would
##    reject on load. It exists only to force SaltPan.step ok:false
##    deterministically; MAX_EVENTS(4096) is not reached here and no claim is
##    made that it is reachable under valid caps.
##  * FIXTURE: chapters 2/3 finished, letter + intro + beimen visited for A
##    (copied from test_salt_pan_world's flower_done/garden_done fixtures);
##  * FIXTURE: gates repaired with A as giver (normally earned by donations)
##    and brine pans hand-flooded 0.001 short of NEED so a salt event is due
##    inside the next 30 s (normally reached by hand flooding + evaporation).
##    The seeded salt state is checked schema-valid with SaltPan.valid().
##  * FIXTURE: an injected undo UTC clock so the live undo record would expire
##    inside the failing tick (proves undo history is rolled back too).
## Earned through act(): hoe/seed/water a crop, build a chest (live undo entry).
## Saves go to one fresh random dir under TEMP; cleanup removes only that dir.
const World=preload("res://scripts/world.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Regions=preload("res://scripts/regions.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const A:="tok-atomic-alice"
const CROP:=Vector2i(38,34)

var checks:=0
var failures:=0
var serial:=0
var dir:=""
var utc_now:=0.0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	else:
		print("ok   "+message)

func probe(label:String,value) -> void:
	print("PROBE %s=%s"%[label,str(value)])

func act(w,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(A,"atomic-%d"%serial,action,p,extra)

func _initialize() -> void:call_deferred("run")

func file_bytes(path:String) -> String:
	if not FileAccess.file_exists(path):return "<missing>"
	return FileAccess.get_file_as_bytes(path).hex_encode().sha256_text()

func listing() -> String:
	var names:=Array(DirAccess.get_files_at(dir))
	names.sort()
	return ",".join(names)

func flower_done(w,token:String) -> void:
	var tea:Dictionary=Tea.FRESH.duplicate(true) # FIXTURE finished chapter-2 comparison
	tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1
	tea.trials={"jar":true,"fiber":true};tea.tea_discussed=true;tea.comparison_complete=true
	w.state.tea_ceramics.players[token]=tea
	var a:Dictionary=Flower.FRESH.duplicate(true) # FIXTURE finished chapter 3
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	w.state.flower_nursery.players[token]=a
	w.state.players[token].travel_book.visited[Flower.REGION]=true
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{token:10},"complete":true,"completed_at":0.0} # FIXTURE (one contributor gave all 10)

## FIXTURE: a hand-flooded brine pan whose salt is due within the next tick.
func due_pan(w) -> Dictionary:
	return {"s":"brine","p":Salt.NEED-0.001,"t":float(w.state.time),"f":"hand"}

func crop_growth(w) -> float:
	return float(w.state.crops[World.key(CROP)].growth)

func seed_static_geometry(layer:Dictionary,cell:Vector2i)->void:
	# Valid construction records exist in both the home and a stored region.
	var tile:=World.key(cell)
	layer.ground[tile]={"type":"floor","owner":A,"items":{}}
	layer.roofs[tile]={"type":"roof","owner":A,"items":{}}
	layer.edges[tile+",N"]={"type":"edge_door","owner":A,"open":true}

func same_static_geometry(first:Dictionary,second:Dictionary)->bool:
	return first.ground==second.ground and first.roofs==second.roofs and first.edges==second.edges

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():
		expect(false,"TEMP must be set (isolated)")
		finish()
		return
	dir=base.path_join("world-atomic-"+Crypto.new().generate_random_bytes(8).hex_encode())
	DirAccess.make_dir_recursive_absolute(dir)
	var w=World.new()
	w.save_path=dir.path_join("world.json")
	w.undo_clock_utc=func(): return utc_now
	utc_now=1.9e9
	w.add_player(A,"阿原")
	probe("has_step_error_field",w.get("step_error")!=null)

	# --- earned setup through act()
	expect(act(w,"hoe",CROP).ok,"till a plot")
	expect(act(w,"seed",CROP,"wheat").ok,"sow wheat (120 s, stays immature for the whole test)")
	expect(act(w,"water",CROP).ok,"water wheat")
	var s:Dictionary=w.state.salt_pan
	for g in 3:s.gates[g]=Salt.GATE_NEEDS_EACH.duplicate(true) # FIXTURE gates repaired
	s.givers[A]=true # FIXTURE A donated
	flower_done(w,A)
	w.state.players[A].travel_book.visited[Salt.REGION]=true # FIXTURE beimen visited
	var record:Dictionary=Salt.RECORD.duplicate(true)
	record.letter=true;record.intro=true # FIXTURE A holds the letter and met the salt worker
	s.players[A]=record
	s.repaired_at=0.0 # FIXTURE
	expect(Salt.valid(w.state.duplicate(true)),"seeded salt state is schema-valid")
	var adv:Dictionary=Salt.advance(Salt.NEED-0.001,float(w.state.time),float(w.state.time)+30.0)
	expect(adv.ok and adv.salt,"day-0 weather evaporates: the due pan turns to salt within 30 s")
	w.state.players[A].inventory.wood=40 # FIXTURE wood stock for one chest (20) + deposit
	var chest_cell:=Vector2i(-1,-1)
	for c in [Vector2i(36,34),Vector2i(36,33),Vector2i(37,35),Vector2i(36,35),Vector2i(37,36),Vector2i(39,36)]:
		if act(w,"build",c,"chest").ok:
			chest_cell=c
			break
	expect(chest_cell.x>=0,"build a chest near spawn (live undo entry)")
	expect(act(w,"deposit",chest_cell,"wood").ok,"deposit wood in the chest")
	# The deposit "uses" the chest and closes its undo record; a later wall
	# becomes the actor's live last construction.
	var wall_ok:=false
	for c in [Vector2i(34,36),Vector2i(35,36),Vector2i(34,35),Vector2i(35,37),Vector2i(36,37),Vector2i(40,36)]:
		if c!=chest_cell and act(w,"build",c,"wall").ok:
			wall_ok=true
			break
	expect(wall_ok,"build a wall (live undo entry)")
	var entry:Dictionary=w.state.construction.last.get(A,{})
	expect(entry.get("status","")=="live","undo entry is live")
	seed_static_geometry(w.state,Vector2i(35,34))
	seed_static_geometry(w.state.regions[Regions.LANYANG],Vector2i(26,20))
	expect(w.save(),"initial durable save")
	expect(World.new().load_world(w.save_path),"seeded fixture save is schema-valid on reload")
	if failures>0:
		print("setup failed; aborting before the tick checks")
		finish()
		return
	var path:String=w.save_path

	# --- 1. inactive tick: paused, nothing advances, nothing saved
	var s0:Dictionary=w.state.duplicate(true)
	var f0:=file_bytes(path)
	expect(w.step(30.0,false)==true,"inactive tick returns true")
	expect(w.state==s0 and float(w.state.time)==float(s0.time),"inactive tick: state and time unchanged")
	expect(file_bytes(path)==f0,"inactive tick: no save")

	# --- 2. successful active tick (salt event due)
	w.state.salt_pan.pans[0]=due_pan(w) # FIXTURE due salt event
	expect(Salt.valid(w.state.duplicate(true)),"due pan fixture is schema-valid")
	var t1:=float(w.state.time)
	var c1:=int(w.state.committed)
	var g1:=crop_growth(w)
	expect(w.step(30.0,true)==true,"active tick succeeds")
	expect(float(w.state.time)==t1+30.0,"active tick advances time by 30")
	expect(int(w.state.committed)==c1+1,"active tick commits once")
	expect(crop_growth(w)>g1,"watered crop grows during the tick")
	expect(w.state.salt_pan.pans[0].s=="salt","salt event simulated in the tick")
	expect(file_bytes(path)!=f0,"active tick saved durably")
	var saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(saved is Dictionary and float(saved.time)==t1+30.0 and int(saved.committed)==c1+1,"saved file holds the new tick")
	expect(same_static_geometry(w.state,s0) and same_static_geometry(w.state.regions[Regions.LANYANG],s0.regions[Regions.LANYANG]),"active tick preserves populated building layers in both regions")
	expect(w.get("step_error") in [null,""],"no step_error after success")

	# --- 3. rejected salt tick, entry region HOME
	w.state.salt_pan.pans[1]=due_pan(w) # FIXTURE another due event
	var saved_pan:Dictionary=w.state.salt_pan.pans[3].duplicate(true)
	w.state.salt_pan.pans[3].s="mud" # FAULT injection: invalid pan forces SaltPan.step ok:false
	utc_now=float(entry.created_utc)+3600.0*24.0 # FIXTURE: undo would expire in this tick
	var s1:Dictionary=w.state.duplicate(true)
	var j1:=JSON.stringify(w.state)
	var f1:=file_bytes(path)
	var l1:=listing()
	var ticks1:Dictionary=w._undo_ticks_at.duplicate(true)
	var active1:Dictionary=w.active_tokens.duplicate(true)
	var r:bool=w.step(30.0,true)
	probe("rejected_home.returned",r)
	probe("rejected_home.time_delta",float(w.state.time)-float(s1.time))
	probe("rejected_home.committed_delta",int(w.state.committed)-int(s1.committed))
	probe("rejected_home.undo_status",w.state.construction.last.get(A,{}).get("status",""))
	probe("rejected_home.save_changed",file_bytes(path)!=f1)
	probe("rejected_home.step_error",w.get("step_error"))
	expect(r==false,"rejected salt tick returns false")
	expect(w.state==s1,"rejected tick: full deep state equality")
	expect(JSON.stringify(w.state)==j1,"rejected tick: identical serialisation (key order)")
	expect(float(w.state.time)==float(s1.time) and int(w.state.committed)==int(s1.committed),"rejected tick: time and committed unchanged")
	expect(w.state.salt_pan==s1.salt_pan and w.state.salt_pan.pans[1].s=="brine","rejected tick: salt_pan untouched (due event not applied)")
	expect(w.state.players[A].inventory==s1.players[A].inventory,"rejected tick: inventory unchanged")
	expect(w.state.objects[World.key(chest_cell)]==s1.objects[World.key(chest_cell)],"rejected tick: chest unchanged")
	expect(crop_growth(w)==float(s1.crops[World.key(CROP)].growth),"rejected tick: crop growth rolled back")
	expect(w.state.construction.last[A].get("status","")=="live","rejected tick: undo entry still live (expiry rolled back)")
	expect(w.state.regions==s1.regions,"rejected tick: every region layer unchanged")
	expect(w._region==Regions.HOME,"rejected tick: HOME projection active")
	expect(w._undo_used.is_empty(),"rejected tick: undo scratch cleared")
	expect(w._undo_ticks_at==ticks1,"rejected tick: undo monotonic ticks unchanged")
	expect(w.active_tokens==active1,"rejected tick: active tokens unchanged")
	expect(file_bytes(path)==f1 and listing()==l1,"rejected tick: no durable save, no tmp file")
	expect(w.get("step_error")=="salt_step_rejected","rejected tick: step_error names the salt rejection")

	# --- 4. rejected salt tick, entered while a regional projection is loaded
	var home_view:Dictionary=w.state.duplicate(true)
	w.switch_region(Salt.REGION)
	r=w.step(30.0,true)
	probe("rejected_beimen.returned",r)
	probe("rejected_beimen.region_after",w._region)
	expect(r==false,"rejected tick from beimen projection returns false")
	expect(w._region==Regions.HOME and w.state==home_view,"rejected tick: consistent HOME projection equal to the pre-tick world")
	w.switch_region(Salt.REGION)
	expect(w.state.objects==home_view.regions[Salt.REGION].objects,"beimen layers load back intact")
	w.switch_region(Regions.HOME)
	expect(w.state==home_view,"switching back restores HOME layers")
	expect(file_bytes(path)==f1,"still no durable save")

	# --- 5. repair the injected fault: the next normal tick works
	w.state.salt_pan.pans[3]=saved_pan # undo FAULT injection
	r=w.step(30.0,true)
	expect(r==true,"repaired world: tick succeeds")
	expect(float(w.state.time)==float(s1.time)+30.0,"repaired tick advances exactly 30 from the pre-failure time")
	expect(int(w.state.committed)==int(s1.committed)+1,"repaired tick commits once")
	expect(w.state.salt_pan.pans[1].s=="salt","repaired tick simulates the due salt event")
	expect(w.state.construction.last[A].get("status","")=="expired","repaired tick observes the undo expiry")
	expect(crop_growth(w)>float(s1.crops[World.key(CROP)].growth),"repaired tick grows the crop")
	expect(file_bytes(path)!=f1,"repaired tick saved durably")
	var loaded=World.new()
	expect(loaded.load_world(path),"repaired save reloads (schema valid)")
	expect(float(loaded.state.time)==float(w.state.time) and int(loaded.state.committed)==int(w.state.committed),"reloaded time/committed match")
	expect(same_static_geometry(loaded.state,s0) and same_static_geometry(loaded.state.regions[Regions.LANYANG],s0.regions[Regions.LANYANG]),"reloaded floor, roof and open door match both original regions")

	# --- 6. save-failure rollback still works
	expect(act(w,"water",CROP).ok,"water again")
	w.state.salt_pan.pans[2]=due_pan(w) # FIXTURE: the tick has a salt change to save
	var s3:Dictionary=w.state.duplicate(true)
	w.save_path=dir.path_join("missing").path_join("x").path_join("world.json")
	r=w.step(30.0,true)
	probe("save_fail.returned",r)
	probe("save_fail.step_error",w.get("step_error"))
	expect(r==false and w.state==s3 and w._region==Regions.HOME,"save failure rolls back the tick")
	expect(w.get("step_error")=="save_failed","save failure is distinguishable from a salt rejection")
	w.save_path=path
	expect(w.step(30.0,true) and w.state.salt_pan.pans[2].s=="salt","tick works again after the save path is fixed")
	expect(World.new().load_world(path),"final save reloads")
	finish()

func finish() -> void:
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	print("WORLD_STEP_ATOMICITY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
