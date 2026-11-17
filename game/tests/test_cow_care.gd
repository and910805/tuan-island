extends SceneTree
const World=preload("res://scripts/world.gd")
const Care=World.COW_CARE
const Follow=preload("res://scripts/cow_follow_view.gd")
const Schema=preload("res://scripts/save_schema.gd")
const SITE:=Vector2i(48,35)
const ONE:="cow-care-one"
const TWO:="cow-care-two"
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func valid(data:Dictionary)->bool:
	return Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
func _initialize()->void:
	var world:=World.new()
	for token in [ONE,TWO]:
		world.add_player(token,"照料者")
		world.state.players[token].x=48.5
		world.state.players[token].y=37.5
	expect(not world.act(ONE,"locked","livestock_pet",SITE,"cow").ok,"Existing picnic gate retained")
	world.state.picnic=true
	var bag:Dictionary=world.state.players[ONE].inventory.duplicate(true)
	expect(world.act(ONE,"pet","livestock_pet",SITE,"cow").ok,"Original pet action starts care response")
	expect(Care.active_actor(world.state,world.active_tokens)==ONE and world.state.livestock.cow.bond==1,"Shared actor and one bond")
	expect(world.state.players[ONE].inventory==bag and world.state.livestock.cow.ready==0,"No milk, feed or inventory reward invented")
	expect(world.act(ONE,"pet","livestock_pet",SITE,"cow").ok and world.state.livestock.cow.bond==1,"Receipt replay does not add care")
	expect(not world.act(TWO,"race","livestock_pet",SITE,"cow").ok and Care.active_actor(world.state)==ONE,"Shared cooldown prevents stealing follow")
	expect(valid(world.state.duplicate(true)),"Optional cow marker is valid save data")
	for invalid in [false,2,{},"unknown"]:
		var bad:=world.state.duplicate(true)
		bad.livestock.cow[Care.FIELD]=invalid
		expect(not valid(bad),"Invalid care actor rejected")
	var saved:="user://cow-care-%d.json"%OS.get_process_id()
	world.save_path=saved
	expect(world.save(),"Save during care")
	var loaded:=World.new()
	expect(loaded.load_world(saved) and Care.active_actor(loaded.state).is_empty(),"Restart returns cow to original station")
	expect(loaded.state.livestock.cow.bond==1 and loaded.state.livestock.cow.last_pet==world.state.livestock.cow.last_pet,"Reload retains real bond and cooldown")
	var tick_before:=world.state.duplicate(true)
	world.save_path=OS.get_environment("TEMP")
	expect(not world.step(Care.SECONDS+0.1,true) and world.state==tick_before,"Failed tick rolls back timeout and every care field")
	world.save_path=saved
	var snapshot:=world.state.duplicate(true)
	snapshot.region_id="home"
	# Presentation baseline before a new care, then a true follow marker arrives.
	var before:=snapshot.duplicate(true)
	Care.clear(before)
	var follow:=Follow.new()
	follow.observe(before)
	follow.observe(snapshot)
	var copy:=snapshot.duplicate(true)
	for frame in 10:follow.advance(0.1)
	expect(follow.position.distance_to(Follow.HOME)>0.5 and follow.position.distance_to(Follow.HOME)<=Follow.RADIUS,"Cow slowly approaches within ranch radius")
	expect(follow.walking_frame(false)>=0 and follow.walking_frame(true)==-1,"Walking legs respect quiet mode")
	expect(snapshot==copy,"Following never changes snapshot, crops or inventory")
	var middle:=follow.position
	follow.observe(snapshot)
	expect(follow.position==middle,"Duplicate snapshot does not reset walking")
	var joined:=Follow.new()
	joined.observe(snapshot)
	expect(joined.position==joined.destination,"First snapshot uses current placement without replaying travel")
	var far:=snapshot.duplicate(true)
	far.players[ONE].y=44.5
	follow.observe(far)
	for frame in 40:follow.advance(0.1)
	expect(follow.position.is_equal_approx(Follow.HOME),"Walking too far returns cow to station")
	snapshot.objects["48,36"]={"type":"wall","owner":ONE}
	follow.observe(snapshot)
	for frame in 20:follow.advance(0.1)
	expect(follow.position.is_equal_approx(Follow.HOME) and follow.status.contains("障礙"),"Wall blocks short follow route")
	snapshot.objects["48,36"]={"type":"door","owner":ONE,"open":false}
	follow.observe(snapshot)
	expect(follow.destination==Follow.HOME,"Closed door blocks cow")
	snapshot.objects.erase("48,36")
	snapshot.ground["48,36"]={"type":"floor","owner":TWO,"owner_visit":true}
	follow.observe(snapshot)
	expect(follow.destination==Follow.HOME,"Cow cannot enter visit-restricted private floor")
	snapshot.ground.erase("48,36")
	follow.observe(snapshot)
	follow.advance(0.4)
	snapshot.objects["48,36"]={"type":"wall","owner":ONE}
	follow.observe(snapshot)
	var blocked:=follow.position
	follow.advance(2.0)
	expect(follow.position==blocked,"Mid-route wall stops walking rather than crossing")
	expect(world.step(Care.SECONDS+0.1,true) and not world.state.livestock.cow.has(Care.FIELD),"Actual world tick expires care marker")
	expect(world.act(TWO,"still-cool","livestock_pet",SITE,"cow").ok==false,"Care duration does not shorten original cooldown")
	world.step(12.0,true)
	expect(world.act(TWO,"next","livestock_pet",SITE,"cow").ok and Care.active_actor(world.state)==TWO,"Friend can care after original cooldown")
	world.active_tokens.erase(TWO)
	expect(world.step(0.1,true) and not world.state.livestock.cow.has(Care.FIELD),"Offline actor clears in atomic tick")
	world.active_tokens[TWO]=true
	world.step(30.1,true)
	var rollback:=world.state.duplicate(true)
	world.save_path=OS.get_environment("TEMP")
	expect(not world.act(TWO,"save-failed","livestock_pet",SITE,"cow").ok and world.state==rollback,"Failed save rolls back care, bond and receipt")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(saved+suffix):DirAccess.remove_absolute(saved+suffix)
	print("COW_CARE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
