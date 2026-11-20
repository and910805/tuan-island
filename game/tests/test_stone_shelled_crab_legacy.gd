extends SceneTree
## 石殼蟹 (B5) reviewer test: COLLISION / LAYOUT and LEGACY-SAVE behaviour through the real
## World / SaveSchema. Every check states the DESIRED behaviour, so a FAIL line is a finding.
##
## Fixtures are DISCLOSED:
##  - players are placed by writing region/x/y; picnic / world_mode / mine_depths are written;
##  - "legacy" content on the three crab cells is written straight into state.regions.mine_5
##    with exactly the shapes the game itself writes (build_area floor, hoe plot), or is a chest
##    built with the real `build` action on a free B5 cell and then moved by the fixture;
##  - saves use isolated files under %TEMP% and are deleted at the end.

const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Crab=preload("res://scripts/stone_shelled_crab.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Layout=preload("res://scripts/mine_layout.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const ALPHA:="crab-legacy-alpha-token"
const BETA:="crab-legacy-beta-token"
const FIELD:="stone_crab"
const MOUTH:=Vector2i(40,24)
const NOOK:=Rect2i(46,27,2,2)
var checks:=0
var failures:=0
var serial:=0
var files:Array=[]
var failed:Array=[]
var notes:Array=[]

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		failed.append(message)
		print("FAIL "+message)

func _initialize() -> void:
	check_layout()
	check_real_walk()
	check_other_floors()
	check_protected_paths()
	check_legacy_occupied()
	check_wedge_on_clear()
	check_wedge_bystander()
	check_legacy_player_on_cart()
	check_schema_gates()
	check_schema_malformed_depths()
	for file in files:
		for suffix in ["",".bak",".tmp",".bak.staged"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	# Repeated at the end so the findings survive a truncated log.
	for note in notes:print("NOTE "+str(note).left(240))
	for message in failed:print("FAILED "+str(message).left(240))
	print("STONE_SHELLED_CRAB_LEGACY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ----------------------------------------------------------------- helpers --

func new_world(mode:String="life",unlocked:int=5,tokens:Array=[ALPHA,BETA]) -> World:
	var w:=World.new()
	var path:String=OS.get_environment("TEMP").path_join("stone-crab-legacy-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	files.append(path)
	w.save_path=path
	w.state["picnic"]=true
	if mode=="adventure":w.state["world_mode"]="adventure"
	w.state["mine_depths"]={"unlocked":unlocked,"ready":{},"pumped":24 if unlocked>=3 else 0,"hoist":unlocked>=6}
	for token:String in tokens:
		w.add_player(token,token.left(12))
		w.active_tokens[token]=true
		place(w,token,Crab.REGION,Vector2i(46,24))
	return w

func place(w:World,token:String,region:String,cell:Vector2i) -> void:
	var player:Dictionary=w.state.players[token]
	player["region"]=region
	player["x"]=cell.x+0.5
	player["y"]=cell.y+0.5

func pos(w:World,token:String) -> Vector2:
	return Vector2(float(w.state.players[token].x),float(w.state.players[token].y))

func act(w:World,token:String,action:String,cell:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"crab-legacy-%d"%serial,action,cell,extra)

func outcome(result:Dictionary) -> String:
	var c=result.get("crab")
	return str(c.get("outcome","<none>")) if c is Dictionary else "<no crab payload>"

func layers(w:World) -> Dictionary:
	return w.state.regions[Crab.REGION]

func tile(cell:Vector2i) -> String:
	return "%d,%d"%[cell.x,cell.y]

func floor_piece(token:String) -> Dictionary:
	return {"type":"floor","owner":token,"items":{}}

func plot(token:String) -> Dictionary:
	return {"kind":"","growth":0.0,"wet":false,"owner":token}

## Runs `probe` with region `region` swapped in, then returns to HOME orientation.
func in_region(w:World,region:String,probe:Callable):
	w.switch_region(region)
	var out=probe.call()
	w.switch_region(World.REGIONS.HOME)
	return out

func stand(w:World,region:String,at:Vector2) -> bool:
	return in_region(w,region,func():return w.can_stand(at))

func centre(cell:Vector2i) -> Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

## Cells reachable from `start` stepping between cell centres with the real can_stand.
func reach(w:World,region:String,start:Vector2i) -> Dictionary:
	return in_region(w,region,func():
		var seen:={}
		if not w.can_stand(centre(start)):return seen
		seen[start]=true
		var queue:Array=[start]
		while not queue.is_empty():
			var at:Vector2i=queue.pop_front()
			for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next:Vector2i=at+step
				if seen.has(next) or not w.can_stand(centre(next)):continue
				seen[next]=true
				queue.append(next)
		return seen)

func walk(w:World,token:String,direction:Vector2,ticks:int,dt:float=1.0/60.0) -> void:
	for tick in ticks:w.move_player(token,direction,dt)

func valid_state(state:Dictionary):
	# Untyped on purpose: an aborted validate() returns null, which must show up as a failure.
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func on_disk(w:World) -> Dictionary:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(w.save_path))
	return parsed if parsed is Dictionary else {}

func reopen(path:String,label:String) -> World:
	var again:=World.new()
	var loaded:=again.load_world(path)
	expect(loaded and not again.recovered_from_backup,"%s: save loads cleanly (error %s)"%[label,str(again.save_error)])
	return again if loaded else null

func write_json(path:String,data:Dictionary) -> void:
	files.append(path)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# ------------------------------------------------------------------ checks --

## Q1: with the cart solid, every other B5 floor cell is still reachable and usable.
func check_layout() -> void:
	var tag:="[layout]"
	var w:=new_world()
	expect(in_region(w,Crab.REGION,func():return w.crab_available()),tag+" fixture: encounter available on B5")
	expect(in_region(w,Crab.REGION,func():return w.blocked(Crab.CART)),tag+" cart cell is solid")
	expect(not in_region(w,Crab.REGION,func():return w.blocked(Crab.CRAB) or w.blocked(Crab.CRAB_REST)),tag+" crab cells are walkable")
	var open:=reach(w,Crab.REGION,MOUTH)
	var hidden:=new_world()
	hidden.state["picnic"]=false
	var before:=reach(hidden,Crab.REGION,MOUTH)
	expect(not in_region(hidden,Crab.REGION,func():return hidden.blocked(Crab.CART)),tag+" picnic=false: cart cell is not solid")
	var lost:Array=[]
	for cell in before:
		if not open.has(cell) and cell!=Crab.CART:lost.append(cell)
	expect(before.has(Crab.CART) and not open.has(Crab.CART) and lost.is_empty(),"%s the solid cart removes exactly its own cell from the walkable set (lost %s; before %d, after %d)"%[tag,str(lost),before.size(),open.size()])
	var bounds:=Layout.bounds(5)
	var unreachable:Array=[]
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var cell:=Vector2i(x,y)
			if not Layout.land(cell,5) or cell==Crab.CART or cell in Mines.NODES:continue
			if not open.has(cell):unreachable.append(cell)
	expect(unreachable.is_empty(),"%s every B5 floor cell except the cart and ore nodes is reachable from the cave mouth (unreachable: %s)"%[tag,str(unreachable)])
	expect(open.has(Survey.POINTS[5]),tag+" survey point (46,24) reachable")
	for y in range(NOOK.position.y,NOOK.end.y):
		for x in range(NOOK.position.x,NOOK.end.x):
			expect(open.has(Vector2i(x,y)),"%s nook cell (%d,%d) reachable"%[tag,x,y])
	for cell in [Mines.UP,Mines.DOWN,Mines.REST,Mines.SERVICE]:
		var beside:=false
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i.ZERO]:
			if open.has(cell+step):beside=true
		expect(beside,"%s %s still has a reachable standing cell"%[tag,str(cell)])
	for target in [Crab.CART,Crab.CRAB,Crab.CRAB_REST]:
		var spots:=0
		for cell in open:
			if Crab.near(centre(cell),target):spots+=1
		expect(spots>=2,"%s %d reachable cell centres are within REACH of %s"%[tag,spots,str(target)])

## Q1: the real mover walks mouth -> survey point -> nook -> crab row and is stopped only by the cart.
func check_real_walk() -> void:
	var tag:="[walk]"
	var w:=new_world("life",5,[ALPHA])
	place(w,ALPHA,Crab.REGION,MOUTH)
	walk(w,ALPHA,Vector2.RIGHT,120)
	expect(pos(w,ALPHA).x>=46.4,"%s mouth -> survey column along y=24 (at %s)"%[tag,str(pos(w,ALPHA))])
	place(w,ALPHA,Crab.REGION,Vector2i(46,24))
	walk(w,ALPHA,Vector2.DOWN,120)
	expect(pos(w,ALPHA).y>=28.0 and NOOK.has_point(Vector2i(pos(w,ALPHA).floor())),"%s survey point -> bottom of the nook (at %s)"%[tag,str(pos(w,ALPHA))])
	walk(w,ALPHA,Vector2.UP,200)
	expect(Vector2i(pos(w,ALPHA).floor())==Crab.CRAB_REST,"%s nook -> crab rest cell (46,22) straight up (at %s)"%[tag,str(pos(w,ALPHA))])
	walk(w,ALPHA,Vector2.LEFT,60)
	var stopped:=pos(w,ALPHA)
	expect(stopped.x>=46.22-0.001 and stopped.x<46.35,"%s walking west on y=22 stops flush against the cart (x=%.3f)"%[tag,stopped.x])
	walk(w,ALPHA,Vector2.DOWN,30)
	walk(w,ALPHA,Vector2.LEFT,32)
	expect(pos(w,ALPHA).x<44.78 and pos(w,ALPHA).x>44.0,"%s the player slides round under the cart to (44,23) (at %s)"%[tag,str(pos(w,ALPHA))])
	walk(w,ALPHA,Vector2.UP,60)
	expect(Vector2i(pos(w,ALPHA).floor()).y<=22 and Crab.near(pos(w,ALPHA),Crab.CART),"%s and up the west side of the cart (at %s)"%[tag,str(pos(w,ALPHA))])
	walk(w,ALPHA,Vector2.RIGHT,60)
	expect(pos(w,ALPHA).x<=44.78+0.001,"%s the cart also stops a walk from the west (x=%.3f)"%[tag,pos(w,ALPHA).x])
	walk(w,ALPHA,Vector2.DOWN,120)
	expect(pos(w,ALPHA).y>24.0,"%s and the player can leave again (at %s)"%[tag,str(pos(w,ALPHA))])

## Q1: B10 / B15 reuse the cave shape but have no cart and no reserved cells.
func check_other_floors() -> void:
	var tag:="[other floors]"
	var w:=new_world("life",15,[ALPHA])
	for region in ["mine_10","mine_15","mine_4","mine_1"]:
		expect(not in_region(w,region,func():return w.blocked(Crab.CART)) or not Layout.land(Crab.CART,Mines.depth_of(region)),"%s %s: (45,22) is not made solid by the encounter"%[tag,region])
		for cell in Crab.footprint():
			var reserved:bool=in_region(w,region,func():return w.protected(cell))
			expect(not reserved,"%s %s: %s is not reserved"%[tag,region,str(cell)])
	for region in ["mine_10","mine_15"]:
		place(w,ALPHA,region,Vector2i(45,23))
		w.state.players[ALPHA].inventory["wood"]=99
		var built:=act(w,ALPHA,"build",Crab.CART,"floor")
		expect(built.get("ok",false)==true,"%s %s: a floor can still be built on (45,22) (got %s)"%[tag,region,str(built.get("message"))])

## Q2: every placement path refuses the three empty cells.
func check_protected_paths() -> void:
	var tag:="[protected]"
	var w:=new_world("life",5,[ALPHA])
	var inv:Dictionary=w.state.players[ALPHA].inventory
	for item in ["wood","stone","plank","fiber","sapling","charcoal","star_mushroom_seed"]:inv[item]=200
	place(w,ALPHA,Crab.REGION,Vector2i(46,23))
	var clean:Dictionary=layers(w).duplicate(true)
	for cell:Vector2i in Crab.footprint():
		for attempt in [["build","floor"],["build","path"],["build","chest"],["build","roof"],["build","lamp"],["build","sign"],["build","water_pipe"],
				["hoe",""],["plant_tree",""],["seed","star_mushroom"],["build_area","floor|%d|%d"%[cell.x,cell.y]],["build_area","floor|%d|%d"%[cell.x,cell.y+1]]]:
			var result:=act(w,ALPHA,attempt[0],cell,attempt[1])
			expect(result.get("ok",true)==false,"%s %s %s on empty %s is refused (got %s)"%[tag,attempt[0],attempt[1],str(cell),str(result.get("message"))])
		# Area started on a free neighbour and dragged over the reserved cell.
		var drag:=act(w,ALPHA,"build_area",cell+Vector2i.DOWN,"floor|%d|%d"%[cell.x,cell.y])
		expect(drag.get("ok",true)==false,"%s build_area dragged from %s over %s is refused (got %s)"%[tag,str(cell+Vector2i.DOWN),str(cell),str(drag.get("message"))])
	expect(layers(w)==clean,tag+" nothing was written to any B5 layer by the refused attempts")
	# Two-cell and four-cell footprints anchored beside the reserved cells.
	for attempt in [[Vector2i(44,22),"workbench"],[Vector2i(46,23),"leaf_mat"],[Vector2i(44,22),"long_bench"]]:
		if not World.BUILD.has(attempt[1]):continue
		var result:=act(w,ALPHA,"build",attempt[0],attempt[1])
		for cell:Vector2i in Crab.footprint():
			expect(not Crab.cell_occupied(layers(w),cell),"%s %s anchored at %s leaves %s empty (result %s)"%[tag,attempt[1],str(attempt[0]),str(cell),str(result.get("message"))])
	# move_object: a real chest beside the row may not be carried onto it.
	var w2:=new_world("life",5,[ALPHA])
	w2.state.players[ALPHA].inventory["wood"]=200
	place(w2,ALPHA,Crab.REGION,Vector2i(46,24))
	var chest:=act(w2,ALPHA,"build",Vector2i(46,23),"chest")
	expect(chest.get("ok",false)==true,"%s fixture: chest built on (46,23) (got %s)"%[tag,str(chest.get("message"))])
	for cell:Vector2i in Crab.footprint():
		var moved:=act(w2,ALPHA,"move_object",Vector2i(46,23),"%d,%d"%[cell.x,cell.y])
		expect(moved.get("ok",true)==false and not layers(w2).objects.has(tile(cell)),"%s move_object onto %s is refused (got %s)"%[tag,str(cell),str(moved.get("message"))])
	# till_area with the public tiller rules must skip the cells too.
	var plan:Dictionary=in_region(w,Crab.REGION,func():return World.TILLER.plan(w,ALPHA,Vector2i(46,23)))
	for cell:Vector2i in Crab.footprint():
		expect(tile(cell) not in plan.get("cells",[]),"%s tiller plan around (46,23) skips %s"%[tag,str(cell)])

## Q2 / Q3c: legacy content on a crab cell hides the encounter, stays usable, and clears normally.
func check_legacy_occupied() -> void:
	var tag:="[legacy occupied]"
	var w:=new_world("life",5,[ALPHA,BETA])
	w.state.players[ALPHA].inventory["wood"]=200
	place(w,ALPHA,Crab.REGION,Vector2i(46,24))
	var built:=act(w,ALPHA,"build",Vector2i(46,23),"chest")
	expect(built.get("ok",false)==true,tag+" fixture: real chest built")
	if not built.get("ok",false):return
	# Fixture: the chest stood on the crab's own cell before the update.
	layers(w).objects[tile(Crab.CRAB)]=layers(w).objects[tile(Vector2i(46,23))]
	layers(w).objects.erase(tile(Vector2i(46,23)))
	layers(w).crops[tile(Crab.CART)]=plot(ALPHA)
	layers(w).ground[tile(Crab.CRAB_REST)]=floor_piece(ALPHA)
	expect(w.save(),tag+" legacy layout saves")
	var disk:=on_disk(w)
	expect(valid_state(disk.duplicate(true))==true,tag+" SaveSchema accepts a chest / plot / floor on the three cells")
	expect(not in_region(w,Crab.REGION,func():return w.crab_available()),tag+" encounter hidden while occupied")
	expect(not in_region(w,Crab.REGION,func():return w.blocked(Crab.CART)),tag+" cart cell not solid while the encounter is hidden (legacy plot walkable)")
	var look:=act(w,ALPHA,"crab_survey",Crab.CRAB)
	expect(look.get("ok",true)==false and outcome(look)=="occupied" and not w.state.players[ALPHA].has(FIELD),"%s crab_survey reports occupied and writes nothing (got %s)"%[tag,outcome(look)])
	# The owner keeps using the legacy content.
	w.state.players[ALPHA].inventory["star_mushroom_seed"]=3
	var store:=act(w,ALPHA,"deposit",Crab.CRAB,"wood")
	expect(store.get("ok",false)==true,"%s deposit into the legacy chest still works (got %s)"%[tag,str(store.get("message"))])
	var take:=act(w,ALPHA,"withdraw",Crab.CRAB,"wood")
	expect(take.get("ok",false)==true,"%s withdraw from the legacy chest still works (got %s)"%[tag,str(take.get("message"))])
	var sow:=act(w,ALPHA,"seed",Crab.CART,"star_mushroom")
	expect(sow.get("ok",false)==true,"%s sowing the legacy plot still works (got %s)"%[tag,str(sow.get("message"))])
	var wet:=act(w,ALPHA,"water",Crab.CART)
	expect(wet.get("ok",false)==true,"%s watering the legacy plot still works (got %s)"%[tag,str(wet.get("message"))])
	layers(w).crops[tile(Crab.CART)]["growth"]=float(World.CROPS.star_mushroom.time)+1.0
	var reap:=act(w,ALPHA,"harvest",Crab.CART)
	expect(reap.get("ok",false)==true,"%s harvesting the legacy plot still works (got %s)"%[tag,str(reap.get("message"))])
	# Clearing: floor, plot, chest.
	for cell in [Crab.CRAB_REST,Crab.CART,Crab.CRAB]:
		var gone:=act(w,ALPHA,"remove",cell)
		expect(gone.get("ok",false)==true,"%s remove on legacy %s works (got %s)"%[tag,str(cell),str(gone.get("message"))])
	expect(Crab.site_clear(layers(w)),tag+" site is clear after the three removals")
	expect(in_region(w,Crab.REGION,func():return w.crab_available() and w.blocked(Crab.CART)),tag+" encounter appears and the cart turns solid once cleared")
	for cell:Vector2i in Crab.footprint():
		expect(in_region(w,Crab.REGION,func():return w.protected(cell)),"%s %s is reserved once empty"%[tag,str(cell)])
	place(w,ALPHA,Crab.REGION,Vector2i(47,23))
	var first:=act(w,ALPHA,"crab_survey",Crab.CRAB)
	expect(first.get("ok",false)==true and outcome(first)=="look","%s crab_survey works after clearing (got %s)"%[tag,outcome(first)])
	expect(valid_state(on_disk(w).duplicate(true))==true,tag+" save after clearing passes SaveSchema")

## Q1 / Q3b: the owner stands on a legacy floor at (45,22) and removes it -> the cart becomes solid
## under their feet. They must still be able to walk off (or be moved out).
func check_wedge_on_clear() -> void:
	var tag:="[wedge owner]"
	var w:=new_world("life",5,[ALPHA])
	layers(w).ground[tile(Crab.CART)]=floor_piece(ALPHA)
	place(w,ALPHA,Crab.REGION,Crab.CART)
	expect(stand(w,Crab.REGION,pos(w,ALPHA)),tag+" fixture: standing on the legacy floor at (45,22) is allowed")
	var gone:=act(w,ALPHA,"remove",Crab.CART)
	expect(gone.get("ok",false)==true,"%s the owner removes the legacy floor while standing on it (got %s)"%[tag,str(gone.get("message"))])
	if not gone.get("ok",false):return
	var start:=pos(w,ALPHA)
	notes.append("%s after remove: pos=%s can_stand=%s cart_blocked=%s"%[tag,str(start),str(stand(w,Crab.REGION,start)),str(in_region(w,Crab.REGION,func():return w.blocked(Crab.CART)))])
	var best:=0.0
	for direction in [Vector2.LEFT,Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2(-1,1),Vector2(1,1)]:
		walk(w,ALPHA,direction,180)
		best=maxf(best,pos(w,ALPHA).distance_to(start))
	expect(best>0.5,"%s the player can walk off the cart cell after it turns solid (moved %.3f tiles in 6 directions x 3 s; pos %s)"%[tag,best,str(pos(w,ALPHA))])
	expect(stand(w,Crab.REGION,pos(w,ALPHA)),"%s the player ends on a standable position (pos %s)"%[tag,str(pos(w,ALPHA))])
	var saved:=act(w,ALPHA,"rescue",Vector2i.ZERO)
	expect(saved.get("ok",false)==true and stand(w,Crab.REGION,pos(w,ALPHA)),"%s escape hatch: `rescue` moves the player to a standable cell (got %s, pos %s)"%[tag,str(saved.get("message")),str(pos(w,ALPHA))])

## Q1: a bystander on the (still walkable) cart cell while someone else clears the last legacy piece.
func check_wedge_bystander() -> void:
	var tag:="[wedge bystander]"
	var w:=new_world("life",5,[ALPHA,BETA])
	layers(w).ground[tile(Crab.CRAB)]=floor_piece(ALPHA)
	place(w,ALPHA,Crab.REGION,Vector2i(47,23))
	place(w,BETA,Crab.REGION,Crab.CART)
	expect(stand(w,Crab.REGION,pos(w,BETA)),tag+" fixture: beta stands on the empty cart cell while the encounter is hidden")
	var gone:=act(w,ALPHA,"remove",Crab.CRAB)
	expect(gone.get("ok",false)==true,"%s alpha removes the last legacy floor (got %s)"%[tag,str(gone.get("message"))])
	if not gone.get("ok",false):return
	var start:=pos(w,BETA)
	var best:=0.0
	for direction in [Vector2.LEFT,Vector2.DOWN,Vector2.RIGHT,Vector2.UP]:
		walk(w,BETA,direction,180)
		best=maxf(best,pos(w,BETA).distance_to(start))
	expect(best>0.5,"%s beta can walk off the cart cell after alpha's removal made it solid (moved %.3f tiles; pos %s)"%[tag,best,str(pos(w,BETA))])

## Q3a/b: a pre-feature save with a player parked exactly on (45,22) loads, and joining relocates them.
func check_legacy_player_on_cart() -> void:
	var tag:="[legacy player]"
	for mode in ["life","adventure"]:
		var w:=new_world(mode,5,[ALPHA,BETA])
		place(w,ALPHA,Crab.REGION,Crab.CART)
		place(w,BETA,Crab.REGION,Crab.CRAB)
		expect(w.save(),"%s %s: fixture saves"%[tag,mode])
		var disk:=on_disk(w)
		expect(not JSON.stringify(disk).contains(FIELD),"%s %s: fixture save carries no stone_crab field"%[tag,mode])
		expect(valid_state(disk.duplicate(true))==true,"%s %s: SaveSchema accepts the pre-feature save"%[tag,mode])
		var again:=reopen(w.save_path,"%s %s"%[tag,mode])
		if again==null:continue
		expect(not again.state.players[ALPHA].has(FIELD),"%s %s: no record appears on load"%[tag,mode])
		again.add_player(ALPHA,"alpha")
		again.add_player(BETA,"beta")
		var a:=pos(again,ALPHA)
		expect(again.player_region(ALPHA)==Crab.REGION and stand(again,Crab.REGION,a) and Vector2i(a.floor())!=Crab.CART,"%s %s: joining moves the player off the now-solid cart cell, still on B5 (pos %s)"%[tag,mode,str(a)])
		expect(pos(again,BETA)==centre(Crab.CRAB),"%s %s: a player parked on the crab cell is left where they were (pos %s)"%[tag,mode,str(pos(again,BETA))])
		var start:=pos(again,ALPHA)
		walk(again,ALPHA,Vector2.RIGHT,60)
		expect(pos(again,ALPHA).distance_to(start)>0.5 or stand(again,Crab.REGION,start+Vector2(-1,0)),"%s %s: the relocated player can move (from %s to %s)"%[tag,mode,str(start),str(pos(again,ALPHA))])
		place(again,ALPHA,Crab.REGION,Vector2i(47,23))
		var look:=act(again,ALPHA,"crab_survey",Crab.CRAB)
		expect(look.get("ok",false)==true and outcome(look)=="look","%s %s: encounter starts fresh on the old save (got %s)"%[tag,mode,outcome(look)])
		if mode=="adventure":
			var wait:=act(again,ALPHA,"crab_shell",Crab.CRAB,"wait")
			expect(wait.get("ok",false)==true and outcome(wait)=="windup","%s adventure: shell wait starts (got %s)"%[tag,outcome(wait)])
			expect(valid_state(on_disk(again).duplicate(true))==true,tag+" adventure: save holding a windup receipt passes SaveSchema")
			expect(not JSON.stringify(on_disk(again).get("players",{}).get(ALPHA,{}).get(FIELD,{})).contains("open_at"),tag+" adventure: the wait cycle is not in the durable record")

## Q3e: the schema gate (picnic + unlocked>=5) versus what the game writes.
func check_schema_gates() -> void:
	var tag:="[schema]"
	var w:=new_world("life",5,[ALPHA])
	place(w,ALPHA,Crab.REGION,Vector2i(47,23))
	var look:=act(w,ALPHA,"crab_survey",Crab.CRAB)
	expect(look.get("ok",false)==true,tag+" fixture: record written by the real action")
	var disk:=on_disk(w)
	expect(valid_state(disk.duplicate(true))==true,tag+" game-written save with a record is valid")
	var raw=disk.get("players",{}).get(ALPHA,{}).get(FIELD)
	expect(raw is Dictionary and raw.size()==2,"%s disk record is {stage,claimed} (got %s)"%[tag,str(raw)])
	var low:Dictionary=disk.duplicate(true)
	low.players[ALPHA]["region"]="home"
	low.players[ALPHA]["x"]=40.5
	low.players[ALPHA]["y"]=30.5
	low.mine_depths["unlocked"]=4
	expect(valid_state(low)==false,tag+" a record with unlocked=4 is rejected")
	var no_record:Dictionary=disk.duplicate(true)
	no_record.players[ALPHA].erase(FIELD)
	no_record.players[ALPHA]["region"]="home"
	no_record.players[ALPHA]["x"]=40.5
	no_record.players[ALPHA]["y"]=30.5
	no_record.mine_depths["unlocked"]=4
	expect(valid_state(no_record)==true,tag+" the same unlocked=4 save without a record is accepted (the rule only bites on the record)")
	var young:Dictionary=disk.duplicate(true)
	young["picnic"]=false
	expect(valid_state(young)==false,tag+" a record with picnic=false is rejected")
	# With unlocked<5 the encounter is hidden and no action can write a record.
	var shallow:=new_world("life",4,[ALPHA])
	place(shallow,ALPHA,Crab.REGION,Vector2i(47,23))
	for action in ["crab_survey","crab_repair","crab_claim"]:
		var cell:Vector2i=Crab.CART if action=="crab_repair" else Crab.CRAB
		var refused:=act(shallow,ALPHA,action,cell)
		expect(refused.get("ok",true)==false and outcome(refused)=="unavailable","%s unlocked=4: %s is unavailable (got %s)"%[tag,action,outcome(refused)])
	expect(not shallow.state.players[ALPHA].has(FIELD) and not in_region(shallow,Crab.REGION,func():return shallow.blocked(Crab.CART)),tag+" unlocked=4: no record, cart not solid")

## Q3: the new schema line reads s.mine_depths.unlocked inside validate_region, which runs BEFORE
## Mines.valid. A corrupt save (record present, mine_depths broken) must be a clean `false`.
## KEEP LAST: if validate() aborts on a script error this is where it shows.
func check_schema_malformed_depths() -> void:
	var tag:="[schema malformed]"
	var w:=new_world("life",5,[ALPHA])
	place(w,ALPHA,Crab.REGION,Vector2i(47,23))
	act(w,ALPHA,"crab_survey",Crab.CRAB)
	var disk:=on_disk(w)
	if disk.is_empty():
		expect(false,tag+" fixture save missing")
		return
	var control:Dictionary=disk.duplicate(true)
	control.players[ALPHA].erase(FIELD)
	control.erase("mine_depths")
	var control_result=valid_state(control)
	expect(control_result is bool and control_result==false,"%s control: no record + mine_depths missing is a clean false (got %s)"%[tag,str(control_result)])
	var cases:={"mine_depths missing":null,"mine_depths is a String":"deep","mine_depths is an Array":[5],"mine_depths lacks unlocked":{"ready":{},"pumped":24,"hoist":false},
		"unlocked is an Array":{"unlocked":[5],"ready":{},"pumped":24,"hoist":false},"unlocked is null":{"unlocked":null,"ready":{},"pumped":24,"hoist":false}}
	for label:String in cases:
		var state:Dictionary=disk.duplicate(true)
		if cases[label]==null:state.erase("mine_depths")
		else:state["mine_depths"]=cases[label]
		var result=valid_state(state)
		notes.append("%s record present + %s -> validate returned %s"%[tag,label,str(result)])
		expect(result is bool and result==false,"%s record present + %s: validate returns a clean false, not an aborted call (got %s)"%[tag,label,str(result)])
