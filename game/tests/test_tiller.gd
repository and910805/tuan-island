extends SceneTree
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
var checks:=0
var failures:=0
var seq:=0
const CENTER:=Vector2i(42,36)

func expect(value:bool,note:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+note)

func fresh():
	var w:=World.new()
	w.add_player("farmer","農夫")
	w.state.players.farmer.x=42.5
	w.state.players.farmer.y=36.5
	w.state.players.farmer.inventory.merge({"tiller":1,"charcoal":5},true)
	return w

func act(w,center:Vector2i=CENTER,id:String="") -> Dictionary:
	seq+=1
	return w.act("farmer",id if not id.is_empty() else "till-%d"%seq,"till_area",center)

func valid(s:Dictionary) -> bool:
	return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func _initialize() -> void:
	var w=fresh()
	expect(w.TILLER.plan(w,"farmer",CENTER).cells.size()==9,"clear 3x3 preview")
	expect(act(w,CENTER,"same-request").ok and w.state.crops.size()==9,"one action tills nine cells")
	expect(w.state.players.farmer.inventory.charcoal==4,"one charcoal for nine cells")
	var saved:Dictionary=w.state.duplicate(true)
	expect(act(w,CENTER,"same-request").ok and w.state==saved,"retry does not consume or mutate twice")
	for crop in w.state.crops.values():expect(crop.owner=="farmer" and crop.kind=="" and not crop.wet,"new cells match original hoe data")
	expect(not act(w).ok and w.state==saved,"cooldown has no mutation")
	w.step(1,true)
	saved=w.state.duplicate(true)
	expect(not act(w).ok and w.state==saved,"all existing fields cost nothing")
	w=fresh()
	w.state.crops["41,35"]={"kind":"radish","owner":"neighbor","wet":true,"growth":20,"remaining":1}
	w.state.forest["42,35"]={"owner":"neighbor","mature":false,"growth":10}
	w.state.objects["43,35"]={"type":"chair","owner":"neighbor","items":{}}
	w.state.ground["41,36"]={"type":"path","owner":"farmer","items":{}}
	w.state.roofs["42,36"]={"type":"roof","owner":"neighbor","items":{}}
	w.state.crops["43,36"]={"kind":"","growth":0,"wet":false,"owner":"neighbor"}
	saved=w.state.duplicate(true)
	var plan:Dictionary=w.TILLER.plan(w,"farmer",CENTER)
	expect(plan.cells.size()==3 and plan.skipped.size()==6,"preview excludes existing terrain and all crops")
	expect(act(w).ok and w.state.players.farmer.inventory.charcoal==4,"partial work consumes one charcoal")
	expect(w.state.crops.size()==5 and w.state.crops["41,35"]==saved.crops["41,35"] and w.state.crops["43,36"]==saved.crops["43,36"],"other player's crop and empty plot unchanged")
	for field in ["forest","objects","ground","roofs"]:expect(w.state[field]==saved[field],field+" untouched")
	w=fresh()
	w.state.players.farmer.inventory.tiller=0
	saved=w.state.duplicate(true)
	expect(not act(w).ok and w.state==saved,"missing machine denied")
	w.state.players.farmer.inventory.tiller=1
	w.state.players.farmer.inventory.charcoal=0
	saved=w.state.duplicate(true)
	expect(not act(w).ok and w.state==saved,"missing fuel denied")
	w=fresh()
	saved=w.state.duplicate(true)
	expect(not act(w,Vector2i(50,36)).ok and w.state==saved,"far center denied")
	w.state.players.farmer.x=42.5
	w.state.players.farmer.y=39.5
	plan=w.TILLER.plan(w,"farmer",CENTER)
	expect(plan.cells.size()<9 and not plan.cells.is_empty(),"each corner independently obeys reach")
	w=fresh()
	w.state.players.farmer.x=40.5;w.state.players.farmer.y=30.5
	plan=w.TILLER.plan(w,"farmer",Vector2i(40,30))
	expect(plan.cells.is_empty(),"public center and neighbors stay protected")
	w.state.players.farmer.x=55.5;w.state.players.farmer.y=36.5
	expect(w.TILLER.plan(w,"farmer",Vector2i(55,36)).cells.is_empty(),"river and public riverbanks not tilled")
	w=fresh()
	w.save_path="user://missing-tiller-directory/world.json"
	saved=w.state.duplicate(true)
	expect(not act(w).ok and w.state==saved,"failed save rolls back fuel, cells, visual event and receipt")
	w.save_path="user://tiller-test-%d.json"%Time.get_ticks_usec()
	expect(act(w).ok,"persistent till succeeds")
	var loaded:=World.new()
	var normalized:Dictionary=w.state.duplicate(true)
	valid(normalized)
	var load_ok:bool=loaded.load_world(w.save_path)
	expect(load_ok and loaded.state.crops==normalized.crops and loaded.state.players.farmer.last_till==w.state.players.farmer.last_till,"reload preserves exact normalized plots and event")
	var original:Dictionary=w.state.duplicate(true)
	for mutation in ["future","duplicate","outside","too_many","bad_type"]:
		var broken:Dictionary=original.duplicate(true)
		var event:Dictionary=broken.players.farmer.last_till
		match mutation:
			"future":event.at=1
			"duplicate":event.cells=["42,36","42,36"]
			"outside":event.cells=["50,36"]
			"too_many":event.cells.append("44,36")
			"bad_type":event.x="42"
		expect(not valid(broken),"invalid visual event rejected: "+mutation)
	original.players.farmer.erase("last_till")
	expect(valid(original),"old save does not require a visual event")
	for path in [w.save_path,w.save_path+".bak"]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	print("TILLER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
