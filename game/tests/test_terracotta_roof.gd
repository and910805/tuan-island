extends SceneTree
## C16 磚瓦: clay kiln -> 紅陶屋瓦 (roof_tile) -> 紅陶瓦屋頂 (terracotta_roof), through the real
## World.act path: queued kiln production, single and area placement, re-tiling of manual
## and automatic thatch, removal refund, construction undo, auto-roof coexistence, room
## fade, save reload and schema rejection. Headless; no drawing is asserted here.

const World=preload("res://scripts/world.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")
const RoofVisibility=preload("res://scripts/roof_visibility.gd")
const SceneMusic=preload("res://scripts/scene_music.gd")
const Art=preload("res://scripts/terracotta_roof_art.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const Terracotta=World.TERRACOTTA_ROOF
const KIND:=Terracotta.KIND
const TILE:=Terracotta.TILE
const KILN:=World.INDUSTRY.CLAY_KILN
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const HOME:=World.REGIONS.HOME
const PARK:=World.SPAWN

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

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
	dir="user://test-terracotta-roof-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated test directory created")
	test_contract()
	test_kiln_to_roof()
	test_retile_own_room()
	test_retile_other_payer()
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	DirAccess.remove_absolute(dir)
	print("TERRACOTTA_ROOF_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ---------------------------------------------------------------- fixtures --

func new_world():
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	# Explicit fixture stock, not normal-play balances. No roof tiles: those are fired below.
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":100,"fiber":300,"clay":40,"charcoal":10}
	serial+=1
	w.save_path=dir+"/world-%d.json"%serial
	clock=FakeClock.new()
	w.set("undo_clock_utc",Callable(clock,"now_utc"))
	w.set("undo_clock_ticks",Callable(clock,"now_ticks"))
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

## Legal empty home site: interior `size` at the returned origin plus a two-cell margin.
func find_site(w,size:Vector2i) -> Vector2i:
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
	expect(found.x>=0,"found a legal empty home site")
	return found

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

func do(w,token:String,action:String,p:Vector2i,extra:String="",at=null) -> Dictionary:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:Vector2=(Vector2(p)+Vector2(1.5,0.8) if at==null else at) if t==token else PARK
		person.x=spot.x;person.y=spot.y
	serial+=1
	var r:Dictionary=w.act(token,"req-%d"%serial,action,p,extra)
	expect(w._region==HOME,"home orientation after "+action)
	return r

func must(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null) -> Dictionary:
	var r:=do(w,token,action,p,extra,at)
	expect(r.get("ok",false)==true,label+": "+str(r.get("message","")))
	return r

## Rejected action: ok=false and neither layers nor inventories move.
func refuse(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null) -> Dictionary:
	var before:=view(w)
	var r:=do(w,token,action,p,extra,at)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": refused with a message")
	expect(view(w)==before,label+": layers and inventories unchanged")
	return r

func view(w) -> String:
	var inventories:={}
	for t in w.state.players:inventories[t]=inv(w,t)
	return var_to_str([w.state.ground,w.state.objects,w.state.roofs,inventories])

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

func times(recipe:Dictionary,count:int) -> Dictionary:
	var out:={}
	for item in recipe:
		if item!="name":out[item]=int(recipe[item])*count
	return out

func roof(w,c:Vector2i) -> Dictionary:
	return w.state.roofs.get(World.key(c),{})

func kinds(w,cells:Array,kind:String,auto:bool) -> int:
	var n:=0
	for c in cells:
		var entry:Dictionary=roof(w,c)
		if entry.get("type","")==kind and (entry.get("auto",false)==true)==auto:n+=1
	return n

func undo_last(w,token:String,p:Vector2i,label:String) -> Dictionary:
	var s:Dictionary=w.undo_summary(token)
	expect(s.get("available")==true,label+": undo available "+str(s))
	return do(w,token,"undo_build",p,str(s.get("id","")))

## Floor by `floor_owner`, ring walls and a closing door by `wall_owner`: a sealed 3x3 room.
func sealed_room(w,o:Vector2i,floor_owner:String,wall_owner:String) -> Vector2i:
	var size:=Vector2i(3,3)
	var door:=Vector2i(o.x+1,o.y+size.y)
	must(w,floor_owner,"build_area",o,"floor|%d|%d"%[o.x+2,o.y+2],"room floor",Vector2(o)+Vector2(1.5,1.5))
	for c in ring(o,size):
		if c!=door:must(w,wall_owner,"build",c,"wall","room wall %s"%c)
	must(w,wall_owner,"build",door,"door","closing door")
	expect(kinds(w,interior(o,size),"roof",true)==9,"closing the room thatches all nine cells automatically")
	return door

# ------------------------------------------------------------------- tests --

func test_contract() -> void:
	var process:Dictionary=World.INDUSTRY.PROCESS
	expect(process.has(TILE) and process[TILE].station==KILN,"the tile is a clay kiln recipe")
	var brick:Dictionary=process.fired_brick
	expect(process[TILE].ingredients==brick.ingredients and process[TILE].time==brick.time and process[TILE].yield==brick.yield,
		"a tile batch costs exactly what a brick batch costs")
	expect(brick=={"station":KILN,"ingredients":{"clay":3,"charcoal":1},"time":75.0,"yield":2}
		and process.flower_pot=={"station":KILN,"ingredients":{"clay":4,"charcoal":1},"time":60.0,"yield":1},
		"existing brick and pot recipes are untouched")
	expect(World.BUILD.clay_kiln=={"name":"陶窯","stone":30,"clay":10},"the kiln itself keeps its C16 cost")
	expect(World.BUILD.roof=={"name":"草編屋頂","wood":1,"fiber":3},"the thatch roof keeps its cost")
	expect(World.BUILD[KIND]=={"name":Terracotta.NAME,TILE:1},"one fired tile roofs one cell and nothing else is charged")
	expect(World.NAMES.get(TILE)==Terracotta.TILE_NAME and not World.OTHER_SALES.has(TILE),"the tile is a named, unpriced material")
	expect(KIND in World.BLUEPRINT_DESIGN.ROOF_KINDS and KIND not in World.AUTO_ROOF_BUILDS,"terracotta is a roofs-layer kind outside room topology")
	expect(World.Village.unlocked({},KIND) and World.Village.unlocked({},KILN),"neither the kiln nor the roof has a story gate")
	var icon:Texture2D=ItemArt.icon(TILE)
	expect(icon!=null and icon.get_size()==Vector2(32,32),"the tile has a 32px inventory icon")
	expect(icon.resource_path=="res://assets/ui-inventory/terracotta-roof-tile.png",
		"the kiln and inventory share the original 32 px sprite")
	expect(Art.ROOF_OFFSET==RoofVisibility.ROOF_OFFSET and Art.ROOF_SIZE==RoofVisibility.ROOF_SIZE,"the roof is drawn in the rect the fade maths assumes")
	expect(Art.ROOF_SURFACE.get_size()==Art.ROOF_SIZE and Art.ROOF_SURFACE.get_image().detect_alpha()==Image.ALPHA_NONE,
		"the roof surface fills one 32px world cell before the player fade is applied")

func test_kiln_to_roof() -> void:
	var w=new_world()
	var site:=find_site(w,Vector2i(2,2))
	var stance:=Vector2(site)+Vector2(1.5,2.5)
	refuse(w,A,"build",site,KIND,"terracotta on bare ground")
	must(w,A,"build",site,KILN,"build the clay kiln",stance)
	var stocked:=inv(w,A)
	expect(not stocked.has(TILE),"no tile exists before firing")
	must(w,A,"queue_processing",site,TILE,"queue first tile batch",stance)
	must(w,A,"queue_processing",site,TILE,"queue second tile batch",stance)
	expect(inv(w,A)==shifted(stocked,{"clay":6,"charcoal":2},-1),"two batches spend six clay and two charcoal")
	refuse(w,A,"claim_processing",site,"","claim before the kiln is done",stance)
	var checkpoint=World.new()
	expect(checkpoint.load_world(w.save_path),"a save with a queued tile batch reloads")
	var record:Dictionary=checkpoint.state.objects.get(World.key(site),{}).get("processing",{})
	expect(str(record).contains(TILE),"the queued tile order survives the reload")
	expect(w.step(150.5,true),"advance the kiln clock past both batches")
	for i in 2:
		if int(inv(w,A).get(TILE,0))<4:must(w,A,"claim_processing",site,"","claim tile batch %d"%i,stance)
	expect(int(inv(w,A).get(TILE,0))==4,"two batches yield four tiles")
	# Placement on the builder's own floor.
	var o:=find_site(w,Vector2i(3,3))
	var cells:=interior(o,Vector2i(3,3))
	must(w,A,"build_area",o,"floor|%d|%d"%[o.x+2,o.y+2],"lay a floor",Vector2(o)+Vector2(1.5,1.5))
	w.state.players[B].inventory[TILE]=5 # fixture: Bob holds tiles so only ownership can stop him
	refuse(w,B,"build",o,KIND,"terracotta on another player's floor")
	refuse(w,B,"build_area",o,"%s|%d|%d"%[KIND,o.x+1,o.y],"area terracotta on another player's floor",Vector2(o)+Vector2(1.5,1.5))
	var before:=inv(w,A)
	must(w,A,"build",o,KIND,"lay the first terracotta cell")
	expect(roof(w,o)=={"type":KIND,"owner":A,"items":{}},"a manual terracotta entry on the roofs layer")
	expect(inv(w,A)==shifted(before,{TILE:1},-1),"one tile charged")
	expect(refuse(w,A,"build",o,KIND,"terracotta over terracotta").message==Terracotta.MSG_OCCUPIED,"already-tiled message")
	expect(refuse(w,A,"build",o,"roof","thatch over terracotta").message=="這裡已經有屋頂","thatch still refuses any existing roof")
	var undone:=undo_last(w,A,o,"single cell")
	expect(undone.get("ok",false)==true and roof(w,o).is_empty() and inv(w,A)==before,"undo lifts the cell and returns the tile: "+str(undone.get("message","")))
	# Hold-and-drag area over three cells, then dismantle one.
	must(w,A,"build_area",o,"%s|%d|%d"%[KIND,o.x+2,o.y],"area terracotta row",Vector2(o)+Vector2(1.5,1.5))
	expect(kinds(w,cells,KIND,false)==3 and inv(w,A)==shifted(before,{TILE:3},-1),"three cells for three tiles")
	expect(refuse(w,A,"build_area",Vector2i(o.x,o.y+1),"%s|%d|%d"%[KIND,o.x+2,o.y+1],"area with one tile for three cells",Vector2(o)+Vector2(1.5,1.5)).message.contains(Terracotta.TILE_NAME),
		"the shortage message names the tile")
	expect(refuse(w,A,"build_area",o,"%s|%d|%d"%[KIND,o.x+2,o.y+1],"area overlapping terracotta",Vector2(o)+Vector2(1.5,1.5)).message==Terracotta.MSG_AREA,"area never stacks terracotta")
	must(w,A,"remove",Vector2i(o.x+2,o.y),"","dismantle one terracotta cell")
	expect(roof(w,Vector2i(o.x+2,o.y)).is_empty() and w.state.ground.has(World.key(Vector2i(o.x+2,o.y))) and inv(w,A)==shifted(before,{TILE:2},-1),
		"dismantling targets the roof, keeps the floor and refunds the tile")
	# Display-side rules read from the same snapshot shape the client gets.
	var person:={"x":o.x+0.5,"y":o.y+0.5}
	var snapshot:={"players":{A:person},"roofs":w.state.roofs,"objects":w.state.objects,"ground":w.state.ground,"edges":w.state.edges}
	var faded:Dictionary=RoofVisibility.faded(snapshot,A)
	expect(faded.has(World.key(o)) and faded.has(World.key(Vector2i(o.x+1,o.y))),"standing under the tiles fades the connected terracotta cells")
	expect(SceneMusic.indoor_track(snapshot,HOME,person)=="house_interior","a terracotta roof counts as a house interior")
	var captured:Dictionary=World.BLUEPRINT_DESIGN.capture(snapshot,A,Rect2i(o,Vector2i(3,3)),"瓦屋",World.BUILD,World.NAMES)
	var tiled:=0
	if captured.get("ok",false):
		for piece in captured.blueprint.pieces:
			if piece.kind==KIND:tiled+=1
	expect(tiled==2,"a blueprint captures the terracotta cells as roof pieces: "+str(captured.get("message","")))
	# Save, reload, and schema rejection of malformed terracotta entries.
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),"a save holding tiles and a terracotta roof reloads")
	expect(loaded.state.roofs.get(World.key(o),{}).get("type","")==KIND and int(loaded.state.players[A].inventory.get(TILE,0))==int(inv(w,A).get(TILE,0)),
		"roof cells and tile stock survive the reload")
	var text:=FileAccess.get_file_as_string(w.save_path)
	expect(validates(text,func(_s:Dictionary):pass),"control: the untampered JSON round trip validates")
	expect(not validates(text,func(s:Dictionary):s.roofs[World.key(o)]["auto"]=true),"a terracotta roof can never be an automatic roof")
	expect(not validates(text,func(s:Dictionary):
		s.objects[World.key(o)]=s.roofs[World.key(o)]
		s.roofs.erase(World.key(o))),"a terracotta roof is refused on the objects layer")
	expect(not validates(text,func(s:Dictionary):s.roofs[World.key(o)]["type"]="roof_tile"),"the item id is not a roof kind")

func validates(text:String,tamper:Callable) -> bool:
	var parsed=JSON.parse_string(text)
	if not parsed is Dictionary:return false
	tamper.call(parsed)
	return SaveSchema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func test_retile_own_room() -> void:
	var w=new_world()
	w.state.players[A].inventory[TILE]=12 # fixture stock; firing is covered by test_kiln_to_roof
	var o:=find_site(w,Vector2i(3,3))
	var cells:=interior(o,Vector2i(3,3))
	var centre:=Vector2(o)+Vector2(1.5,1.5)
	var door:=sealed_room(w,o,A,A)
	var thatched:Dictionary=w.state.roofs.duplicate(true)
	var before:=inv(w,A)
	must(w,A,"build_area",o,"%s|%d|%d"%[KIND,o.x+2,o.y+2],"re-tile the whole sealed room",centre)
	expect(kinds(w,cells,KIND,false)==9 and kinds(w,cells,"roof",true)==0,"all nine thatch cells became manual terracotta")
	expect(inv(w,A)==shifted(shifted(before,{TILE:9},-1),times(World.BUILD.roof,9),1),"nine tiles charged, nine cells of thatch refunded")
	var undone:=undo_last(w,A,o,"re-tiled room")
	expect(undone.get("ok",false)==true,"undo the re-tiling: "+str(undone.get("message","")))
	expect(var_to_str(w.state.roofs)==var_to_str(thatched) and inv(w,A)==before,"undo restores the exact automatic thatch and both stocks")
	must(w,A,"build",o,KIND,"re-tile one cell")
	expect(roof(w,o)=={"type":KIND,"owner":A,"items":{}} and inv(w,A)==shifted(shifted(before,{TILE:1},-1),World.BUILD.roof,1),
		"single re-tile: one tile in, one thatch cell back")
	# The automatic planner keeps its own thatch and never touches the manual tiles.
	var sealed:=inv(w,A)
	must(w,A,"remove",door,"","open the room")
	expect(kinds(w,cells,"roof",true)==0 and kinds(w,cells,KIND,false)==1,"opening the room lifts the eight automatic cells and keeps the tiled one")
	expect(inv(w,A)==shifted(shifted(sealed,times(World.BUILD.roof,8),1),World.BUILD.door,1),"only thatch and the door are refunded")
	must(w,A,"build",door,"door","close the room again")
	expect(kinds(w,cells,"roof",true)==8 and kinds(w,cells,KIND,false)==1 and inv(w,A)==sealed,"re-closing thatches only the eight untiled cells")
	# A hanging pot keeps its support across a re-tile by its own owner.
	var hook:=Vector2i(o.x+1,o.y+1)
	w.state.players[A].inventory["clay"]=40
	must(w,A,"build",hook,World.ROOF_FIXTURES.HANGING_POT,"hang a pot under the thatch")
	must(w,A,"build",hook,KIND,"re-tile above the owner's own pot")
	expect(World.ROOF_FIXTURES.supported(roof(w,hook),A) and w.state.objects.get(World.key(hook),{}).get("type","")==World.ROOF_FIXTURES.HANGING_POT,
		"the pot still hangs from the owner's terracotta roof")
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),"a mixed thatch/terracotta room with a hanging pot reloads")
	expect(var_to_str(JSON.parse_string(JSON.stringify(w.state.roofs)))==var_to_str(JSON.parse_string(JSON.stringify(loaded.state.roofs))),"roofs layer identical after reload")

func test_retile_other_payer() -> void:
	var w=new_world()
	w.state.players[A].inventory[TILE]=4
	w.state.players[B].inventory[TILE]=4
	var o:=find_site(w,Vector2i(3,3))
	sealed_room(w,o,A,B)
	var auto_entry:Dictionary=roof(w,o).duplicate(true)
	expect(auto_entry.get("owner","")==B and auto_entry.get("auto",false)==true,"Bob closed the room, so Bob paid the automatic thatch")
	refuse(w,B,"build",o,KIND,"the payer cannot tile a floor that is not theirs")
	var a0:=inv(w,A)
	var b0:=inv(w,B)
	must(w,A,"build",o,KIND,"the floor owner re-tiles a cell Bob thatched")
	expect(roof(w,o)=={"type":KIND,"owner":A,"items":{}},"the cell is now Alice's terracotta")
	expect(inv(w,A)==shifted(a0,{TILE:1},-1) and inv(w,B)==shifted(b0,World.BUILD.roof,1),"Alice pays one tile; the thatch returns to Bob, who paid for it")
	var undone:=undo_last(w,A,o,"cross-payer re-tile")
	expect(undone.get("ok",false)==true,"undo the cross-payer re-tile: "+str(undone.get("message","")))
	expect(roof(w,o)==auto_entry and inv(w,A)==a0 and inv(w,B)==b0,"undo restores Bob's automatic cell and both inventories")
	# A refund that cannot fit stops the whole re-tile before anything is charged.
	w.state.players[B].inventory["fiber"]=999999999
	expect(refuse(w,A,"build",o,KIND,"payer inventory full").message==Terracotta.MSG_FULL,"full payer inventory message")
