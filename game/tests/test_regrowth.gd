extends SceneTree
const World=preload("res://scripts/world.gd")
var w
var sequence:=0
var checks:=0
var failures:=0
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func act(action:String,p:Vector2i,extra:String="",who:String="alice") -> Dictionary:
	sequence+=1
	return w.act(who,"regrow-%d"%sequence,action,p,extra)
func _initialize() -> void:
	w=World.new()
	w.add_player("alice","米米")
	w.add_player("bob","豆豆")
	var p:Dictionary=w.state.players.alice
	var location:=Vector2i(38,34)
	var k:=World.key(location)
	expect(act("plant_tree",location).ok,"plant in empty ground")
	expect(p.inventory.sapling==1,"one sapling consumed")
	expect(not act("plant_tree",location).ok,"cannot overlap saplings")
	expect(not act("hoe",location).ok,"cannot hoe planted ground")
	expect(not act("build",location,"floor").ok,"cannot build over growing tree")
	expect(not act("axe",location).ok,"young tree does not yield materials")
	expect(not act("remove",location,"","bob").ok,"another player cannot lift sapling")
	expect(act("remove",location).ok and p.inventory.sapling==2,"owner lifts sapling with exact refund")
	expect(not act("remove",location).ok,"cannot duplicate refund")
	expect(act("plant_tree",location).ok,"replant lifted tree")
	w.step(1000,false)
	expect(w.state.forest[k].growth==0,"empty world pauses sapling growth")
	w.step(179,true)
	expect(w.resource(location)=="sapling" and not w.blocked(location),"sapling remains walkable before maturity")
	p.x=38.5;p.y=34.5
	w.step(2,true)
	expect(not w.state.forest[k].mature,"growth cannot trap active player")
	p.x=39.5;p.y=33.5
	w.step(0.1,true)
	expect(w.resource(location)=="tree" and w.blocked(location),"tree matures after player moves clear")
	expect(not act("remove",location).ok,"mature tree uses harvesting rather than refund")
	var before:int=p.inventory.wood
	for i in range(3):expect(act("axe",location).ok,"mature planted tree can be harvested")
	expect(p.inventory.wood==before+6 and p.inventory.sapling==2,"tree yields wood and replacement sapling exactly once")
	expect(not act("axe",location).ok,"felled tree cannot duplicate yield")
	expect(act("plant_tree",location).ok,"same location supports another growth cycle")
	# Original procedural trees also produce replacement saplings.
	var native:=Vector2i.ZERO
	for y in range(15,45):
		for x in range(15,52):
			if World.base_resource(Vector2i(x,y))=="tree" and not w.protected(Vector2i(x,y)):native=Vector2i(x,y);break
		if native!=Vector2i.ZERO:break
	p.x=native.x+1.5;p.y=native.y+0.5
	var old_saplings:int=p.inventory.sapling
	for i in range(3):expect(act("axe",native).ok,"native tree chopped")
	expect(p.inventory.sapling==old_saplings+1,"native tree returns sapling")
	expect(act("plant_tree",native).ok,"can replant original resource tile")
	w.step(181,true)
	expect(w.resource(native)=="tree","planted tree overrides removed procedural marker")
	# Reclaiming empty farmland permits reversible island planning.
	p.x=39.5;p.y=33.5
	var plot:=Vector2i(37,34)
	expect(act("hoe",plot).ok,"open own farmland")
	expect(not act("remove",plot,"","bob").ok,"other player cannot reclaim owned soil")
	expect(act("seed",plot,"radish").ok,"seed plot")
	expect(not act("remove",plot).ok,"growing crops cannot be destroyed by reclaim")
	act("water",plot)
	w.step(91,true)
	act("harvest",plot)
	expect(act("remove",plot).ok,"harvested soil can be restored")
	expect(act("build",plot,"floor").ok,"restored soil allows building")
	expect(not act("plant_tree",plot).ok,"cannot plant on floor")
	p.x=43.5;p.y=31.5
	var coins:int=p.coins
	expect(act("buy",Vector2i(43,29),"sapling").ok and p.coins==coins-20,"merchant replenishes saplings")
	p.coins=0
	expect(not act("buy",Vector2i(43,29),"sapling").ok,"purchase requires funds")
	expect(not act("plant_tree",Vector2i(43,30)).ok,"public path protected")
	p.x=45.5;p.y=33.5
	expect(not act("plant_tree",Vector2i(45,34)).ok,"chicken location protected")
	# Persistence preserves regrowth and rejects malformed forest data.
	var path:="user://regrowth-test-%d.json"%Time.get_ticks_usec()
	w.save_path=path
	expect(w.save(),"save regrowth state")
	var loaded=World.new()
	expect(loaded.load_world(path),"load regrowth state")
	expect(loaded.state.forest.size()==2 and loaded.resource(native)=="tree","regrowth survives reload")
	var malformed:Dictionary=w.state.duplicate(true)
	malformed.forest[k].growth="bad"
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(malformed));f.close()
	expect(not World.new().load_world(path),"malformed growth rejected rather than causing runtime error")
	# Additive migration leaves old farmland usable and introduces empty forest.
	malformed=w.state.duplicate(true)
	malformed.erase("forest")
	f=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(malformed));f.close()
	expect(loaded.load_world(path) and loaded.state.forest.is_empty(),"old world gains forest without resetting progress")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("REGROWTH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
