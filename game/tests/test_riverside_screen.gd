extends SceneTree
## T08 河岸屏風 focused test. Works on native windows and with --headless.
## Optional screenshots (native only): -- --qa-dir=<folder> [--qa-size=1024]
##
## Contract pinned here:
##   - 2x1 by default (1x2 vertical), 竹材10 + 布料4, id Industry.RIVERSIDE_SCREEN.
##   - Deployed: both tiles block. Folded: both tiles pass.
##   - Deploying (build / blueprint / move / unfold / undo-restore) is refused while ANY active
##     player's foot box touches either tile, including a body that only clips a tile corner.
##   - Owner-only fold switch, usable from either end; folded flag survives move, undo and save.
##   - Blueprints capture geometry only and always build the screen unfolded.

const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const KIND:=I.RIVERSIDE_SCREEN
const FIELD:=I.RIVERSIDE_FOLDED_FIELD
const Panels=preload("res://scripts/life_ui_panels.gd")
const Folio=preload("res://scripts/build_folio.gd")
const ART_WIDE:="res://assets/ui-life/riverside-screen-wide.png"
const ART_LONG:="res://assets/ui-life/riverside-screen-long.png"
const ART_FOLDED:="res://assets/ui-life/riverside-screen-folded.png"
## The test yard (cleared below): x 40..44, y 34..37.
const HOME:=Vector2i(40,35)
const DEST:=Vector2i(43,35)
const LANE:=Vector2i(41,34)
const OWNER_PARK:=Vector2(42.5,36.8)
const GUEST_PARK:=Vector2(44.5,37.5)
const GUEST_NEAR:=Vector2(41.5,36.6)
var app
var world:World
var owner:String
var guest:="riverside-guest"
var path:String
var output:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(actor:String,verb:String,tile:Vector2i,extra:="")->Dictionary:
	serial+=1
	return world.act(actor,"riverside-%d"%serial,verb,tile,extra)

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("RIVERSIDE_SCREEN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ---------------------------------------------------------------- helpers --

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func bag(item:String)->int:
	return int(world.state.players[owner].inventory.get(item,0))

func put(token:String,at:Vector2)->void:
	world.state.players[token].x=at.x
	world.state.players[token].y=at.y

func centre(tile:Vector2i)->Vector2:
	return Vector2(tile)+Vector2(0.5,0.5)

func tiles(anchor:Vector2i,vertical:bool)->Array:
	var out:Array=[]
	for offset:Vector2i in I.station_cells(KIND,vertical):out.append(anchor+offset)
	return out

func all_blocked(list:Array,expected:bool)->bool:
	for tile:Vector2i in list:
		if world.blocked(tile)!=expected:return false
	return true

func all_stand(list:Array,expected:bool)->bool:
	for tile:Vector2i in list:
		if world.can_stand(centre(tile))!=expected:return false
	return true

func folded_state(list:Array,expected:bool)->bool:
	for tile:Vector2i in list:
		var piece:Dictionary=world.state.objects.get(World.key(tile),{})
		if piece.get("type")!=KIND or I.is_folded_screen(piece)!=expected:return false
	return true

func empty(list:Array)->bool:
	for tile:Vector2i in list:
		if world.state.objects.has(World.key(tile)):return false
	return true

func well_formed(list:Array,vertical:bool)->bool:
	for index in list.size():
		var piece:Dictionary=world.state.objects.get(World.key(list[index]),{})
		if piece.get("type")!=KIND or piece.get("owner")!=owner or int(piece.get(I.square_part_field(KIND),-1))!=index or I.is_vertical(piece)!=vertical:return false
	return true

## Clears every screen and refills the owner so each scenario starts from the same yard.
func fresh()->void:
	for k:String in world.state.objects.keys():
		if world.state.objects[k].get("type") in [KIND,I.FABRIC_SCREEN]:world.state.objects.erase(k)
	var inventory:Dictionary=world.state.players[owner].inventory
	inventory.bamboo=24
	inventory.cotton_cloth=12
	inventory.hardwood=20
	put(owner,OWNER_PARK)
	put(guest,GUEST_PARK)

func place(anchor:Vector2i,vertical:bool)->Dictionary:
	if not vertical:return act(owner,"build",anchor,KIND)
	# Vertical screens come from rotated blueprints in play; this is the same builder call.
	return world._build_piece(owner,anchor,KIND,true,false,true,true)

func fold(tile:Vector2i,actor:="")->Dictionary:
	return act(owner if actor.is_empty() else actor,I.RIVERSIDE_FOLD,tile)

func reload_ok(list:Array,folded:bool)->bool:
	var saved:=World.new()
	if not saved.load_world(path) or saved.recovered_from_backup:return false
	for tile:Vector2i in list:
		var piece:Dictionary=saved.state.objects.get(World.key(tile),{})
		if piece.get("type")!=KIND or I.is_folded_screen(piece)!=folded or saved.blocked(tile)==folded:return false
	return true

func walk(token:String,direction:Vector2,steps:int)->void:
	for step in steps:world.move_player(token,direction,0.05)

# -------------------------------------------------------------- scenarios --

func scenario(vertical:bool)->void:
	var tag:="vertical" if vertical else "horizontal"
	var step_offset:=Vector2i.DOWN if vertical else Vector2i.RIGHT
	expect(I.station_cells(KIND,vertical)==[Vector2i.ZERO,step_offset],tag+": the screen is a two-cell piece")
	var home_tiles:=tiles(HOME,vertical)
	var dest_tiles:=tiles(DEST,vertical)
	var first:Vector2i=home_tiles[0]
	var end:Vector2i=home_tiles[1]
	var dest_end:Vector2i=dest_tiles[1]
	# Foot-box positions whose centre is 0.85 tile away (the legacy 0.8 test misses them) yet
	# whose box still overlaps one screen tile by a sliver.
	var clip_home:=Vector2(end)+Vector2(1.1,1.1)
	var clip_dest:=Vector2(DEST)+Vector2(-0.1,-0.1)
	var me:Dictionary=world.state.players[owner]
	var other:Dictionary=world.state.players[guest]

	# --- deploy refused while a body touches either tile
	fresh()
	expect(Industry_hits(clip_dest,dest_tiles) and clip_dest.distance_to(centre(DEST))>0.8,tag+": fixture clip position is a true corner clip the old check misses")
	put(guest,clip_dest)
	var denied:=place(DEST,vertical)
	expect(not denied.ok and denied.message==I.RIVERSIDE_OCCUPIED and empty(dest_tiles) and bag("bamboo")==24 and bag("cotton_cloth")==12,tag+": a guest clipping a tile corner blocks deploying and nothing is charged")
	put(guest,centre(DEST))
	expect(not place(DEST,vertical).ok and empty(dest_tiles),tag+": a guest standing on the tile blocks deploying")
	put(guest,centre(dest_end))
	expect(not place(DEST,vertical).ok and empty(dest_tiles),tag+": a guest on the far tile blocks deploying")
	put(guest,GUEST_PARK)
	put(owner,clip_dest)
	var self_denied:=place(DEST,vertical)
	expect(not self_denied.ok and self_denied.message==I.RIVERSIDE_OCCUPIED and empty(dest_tiles),tag+": the builder's own foot box blocks deploying too")
	put(owner,OWNER_PARK)

	# --- deploy
	var built:=place(HOME,vertical)
	expect(built.ok and bag("bamboo")==14 and bag("cotton_cloth")==8,tag+": build costs 竹材10 and 布料4 once for both tiles")
	expect(well_formed(home_tiles,vertical) and folded_state(home_tiles,false),tag+": both tiles are one unfolded screen with matching parts")
	expect(all_blocked(home_tiles,true) and all_stand(home_tiles,false),tag+": a deployed screen blocks both tiles")
	expect(world.station_anchor(world.state.objects,end)==HOME,tag+": the far tile resolves to the same screen")

	# --- owner-only, in range
	put(guest,GUEST_NEAR)
	var theirs:=fold(end,guest)
	expect(not theirs.ok and theirs.message==I.RIVERSIDE_NOT_OWNER and folded_state(home_tiles,false) and all_blocked(home_tiles,true),tag+": a guest cannot fold the owner's screen")
	put(guest,GUEST_PARK)
	put(owner,Vector2(46.5,37.5))
	expect(not fold(first).ok and folded_state(home_tiles,false),tag+": folding needs the owner within reach")
	put(owner,OWNER_PARK)

	# --- fold / unfold from both ends
	expect(fold(first).ok and folded_state(home_tiles,true),tag+": the first end folds the whole screen")
	expect(all_blocked(home_tiles,false) and all_stand(home_tiles,true),tag+": a folded screen passes on both tiles")
	expect(fold(end).ok and folded_state(home_tiles,false) and all_blocked(home_tiles,true),tag+": the far end unfolds it")
	expect(fold(end).ok and folded_state(home_tiles,true) and all_blocked(home_tiles,false),tag+": the far end folds it")
	expect(bag("bamboo")==14 and bag("cotton_cloth")==8,tag+": folding is free")

	# --- never unfold onto a body (no accidental trap)
	put(guest,centre(end))
	var onto_far:=fold(first)
	expect(not onto_far.ok and onto_far.message==I.RIVERSIDE_OCCUPIED and folded_state(home_tiles,true) and world.can_stand(centre(end)),tag+": a guest on the far tile keeps the screen folded")
	put(guest,centre(first))
	expect(not fold(end).ok and folded_state(home_tiles,true),tag+": a guest on the first tile keeps it folded")
	put(guest,clip_home)
	expect(not fold(first).ok and folded_state(home_tiles,true) and Industry_hits(clip_home,home_tiles),tag+": a corner-clipping guest keeps it folded")
	put(guest,GUEST_PARK)
	put(owner,centre(first))
	expect(not fold(first).ok and folded_state(home_tiles,true),tag+": the owner standing on the screen cannot unfold it either")
	put(owner,OWNER_PARK)
	expect(fold(first).ok and folded_state(home_tiles,false) and all_blocked(home_tiles,true) and well_formed(home_tiles,vertical),tag+": unfolds once everyone is clear")

	# --- move: refused onto a body, free otherwise, state travels
	put(guest,clip_dest)
	var move_denied:=act(owner,"move_object",end,World.key(DEST))
	expect(not move_denied.ok and move_denied.message==I.RIVERSIDE_OCCUPIED and empty(dest_tiles) and all_blocked(home_tiles,true),tag+": moving a deployed screen onto a clipped corner is refused")
	put(guest,centre(dest_end))
	expect(not act(owner,"move_object",first,World.key(DEST)).ok and empty(dest_tiles) and folded_state(home_tiles,false),tag+": moving onto a standing guest is refused")
	put(guest,GUEST_PARK)
	expect(act(owner,"move_object",end,World.key(DEST)).ok,tag+": the screen moves from its far tile")
	expect(empty(home_tiles) and all_blocked(home_tiles,false) and well_formed(dest_tiles,vertical) and folded_state(dest_tiles,false) and all_blocked(dest_tiles,true),tag+": the move carries the whole deployed screen")
	expect(bag("bamboo")==14 and bag("cotton_cloth")==8,tag+": moving costs nothing")
	expect(fold(dest_end).ok and act(owner,"move_object",dest_end,World.key(HOME)).ok,tag+": a folded screen can be moved")
	expect(empty(dest_tiles) and folded_state(home_tiles,true) and well_formed(home_tiles,vertical) and all_blocked(home_tiles,false) and all_stand(home_tiles,true),tag+": the folded state stays after a move")

	# --- save / reload keeps the state, both folded and deployed
	expect(reload_ok(home_tiles,true),tag+": the primary save restores the folded, walkable screen")
	expect(fold(first).ok and reload_ok(home_tiles,false),tag+": the primary save restores the deployed, solid screen")
	expect(fold(first).ok and reload_ok(home_tiles,true),tag+": the primary save restores it folded again")

	# --- dismantle refunds one recipe from either tile
	expect(act(owner,"remove",end).ok and empty(home_tiles) and bag("bamboo")==24 and bag("cotton_cloth")==12,tag+": dismantling returns a single recipe")

	# --- undo never walls a player in
	undo_scenarios(vertical,tag,home_tiles,dest_tiles,first,end,clip_home)
	me.x=OWNER_PARK.x
	other.x=GUEST_PARK.x

func Industry_hits(pos:Vector2,list:Array)->bool:
	return I.foot_box_hits(pos,list)

func undo_scenarios(vertical:bool,tag:String,home_tiles:Array,dest_tiles:Array,first:Vector2i,end:Vector2i,clip_home:Vector2)->void:
	# Undo of a build (history exists only for act-driven builds).
	if not vertical:
		fresh()
		expect(place(HOME,vertical).ok,tag+": undo fixture builds")
		var built_undo:=world.undo_summary(owner)
		expect(bool(built_undo.get("available",false)) and act(owner,World.UNDO_ACTION,first,str(built_undo.get("id",""))).ok and empty(home_tiles) and bag("bamboo")==24,tag+": undoing a build removes the screen and refunds")

	# A deployed screen removed, then someone steps onto its tiles: restoring it would trap them.
	fresh()
	place(HOME,vertical)
	expect(act(owner,"remove",end).ok and empty(home_tiles) and bag("bamboo")==24,tag+": remove fixture")
	var removal:=world.undo_summary(owner)
	var removal_id:=str(removal.get("id",""))
	expect(bool(removal.get("available",false)),tag+": the removal can be undone")
	put(guest,centre(first))
	var blocked_undo:=act(owner,World.UNDO_ACTION,first,removal_id)
	expect(not blocked_undo.ok and blocked_undo.message==World.UNDO_MSG_OCCUPIED and empty(home_tiles) and world.can_stand(centre(first)),tag+": undo will not restore a solid screen onto a standing guest")
	put(guest,clip_home)
	expect(not act(owner,World.UNDO_ACTION,first,removal_id).ok and empty(home_tiles),tag+": undo will not restore a solid screen onto a corner-clipping guest")
	put(guest,GUEST_PARK)
	put(owner,centre(end))
	expect(not act(owner,World.UNDO_ACTION,first,removal_id).ok and empty(home_tiles),tag+": the actor's own foot box also blocks the restore")
	put(owner,OWNER_PARK)
	expect(act(owner,World.UNDO_ACTION,first,removal_id).ok and well_formed(home_tiles,vertical) and folded_state(home_tiles,false) and all_blocked(home_tiles,true) and bag("bamboo")==14,tag+": once clear, undo restores the solid screen")

	# A FOLDED screen is walkable, so its restore may land on a standing guest.
	fresh()
	place(HOME,vertical)
	expect(fold(first).ok and act(owner,"remove",first).ok and empty(home_tiles),tag+": folded remove fixture")
	var folded_removal:=world.undo_summary(owner)
	put(guest,centre(end))
	var folded_undo:=act(owner,World.UNDO_ACTION,first,str(folded_removal.get("id","")))
	expect(folded_undo.ok and folded_state(home_tiles,true) and all_blocked(home_tiles,false) and world.can_stand(centre(end)),tag+": undo restores a folded screen even under a guest, who stays free to walk")
	put(guest,GUEST_PARK)

	# Moving a deployed screen away, standing on its old tiles, then undoing the move.
	fresh()
	place(HOME,vertical)
	expect(act(owner,"move_object",end,World.key(DEST)).ok and folded_state(dest_tiles,false),tag+": move fixture")
	var move_record:=world.undo_summary(owner)
	var move_id:=str(move_record.get("id",""))
	put(guest,centre(first))
	var move_back:=act(owner,World.UNDO_ACTION,first,move_id)
	expect(not move_back.ok and move_back.message==World.UNDO_MSG_OCCUPIED and folded_state(dest_tiles,false) and empty(home_tiles),tag+": undoing a move will not drop the solid screen on a guest")
	put(guest,GUEST_PARK)
	expect(act(owner,World.UNDO_ACTION,first,move_id).ok and folded_state(home_tiles,false) and all_blocked(home_tiles,true) and empty(dest_tiles),tag+": once clear, undoing the move restores the solid screen")

	# Folded + moved + undone stays folded (and so cannot trap anyone).
	fresh()
	place(HOME,vertical)
	expect(fold(first).ok and act(owner,"move_object",first,World.key(DEST)).ok,tag+": folded move fixture")
	var folded_move:=world.undo_summary(owner)
	put(guest,centre(first))
	expect(act(owner,World.UNDO_ACTION,first,str(folded_move.get("id",""))).ok and folded_state(home_tiles,true) and all_blocked(home_tiles,false) and world.can_stand(centre(first)),tag+": undoing a folded move keeps it folded and walkable")
	put(guest,GUEST_PARK)

func walk_scenario(vertical:bool)->void:
	var tag:="vertical" if vertical else "horizontal"
	var lane_tiles:=tiles(LANE,vertical)
	fresh()
	expect(place(LANE,vertical).ok,tag+": walk fixture builds")
	var other:Dictionary=world.state.players[guest]
	put(guest,Vector2(40.3,34.5))
	walk(guest,Vector2.RIGHT,60)
	expect(float(other.x)<float(LANE.x),tag+": a deployed screen stops a walking player")
	expect(fold(LANE).ok,tag+": walk fixture folds")
	walk(guest,Vector2.RIGHT,60)
	expect(float(other.x)>float(LANE.x)+1.9,tag+": a folded screen lets the player walk straight through")
	put(guest,centre(LANE))
	expect(not fold(LANE).ok and folded_state(lane_tiles,true),tag+": unfolding on a player inside it is refused")
	var inside_x:=float(other.x)
	walk(guest,Vector2.RIGHT,10)
	expect(float(other.x)>inside_x and world.can_stand(Vector2(other.x,other.y)),tag+": the player inside can still walk out")
	put(guest,GUEST_PARK)

func schema_scenario()->void:
	fresh()
	expect(place(LANE,false).ok and fold(LANE).ok,"schema fixture")
	var tile_keys:=[]
	for tile:Vector2i in tiles(LANE,false):tile_keys.append(World.key(tile))
	expect(valid(world.state.duplicate(true)),"A folded screen validates")
	var mismatch:=world.state.duplicate(true)
	mismatch.objects[tile_keys[1]].erase(FIELD)
	expect(not valid(mismatch),"Validator rejects a screen whose two tiles disagree about folding")
	var untrue:=world.state.duplicate(true)
	for k:String in tile_keys:untrue.objects[k][FIELD]=false
	expect(not valid(untrue),"Validator rejects a stored 'folded:false' flag")
	var wrong_type:=world.state.duplicate(true)
	for k:String in tile_keys:wrong_type.objects[k][FIELD]="yes"
	expect(not valid(wrong_type),"Validator rejects a non-boolean folded flag")
	var bad_vertical:=world.state.duplicate(true)
	bad_vertical.objects[tile_keys[0]].riverside_screen_vertical="yes"
	expect(not valid(bad_vertical),"Validator rejects a non-boolean vertical flag")
	fresh()
	expect(act(owner,"build",LANE,I.FABRIC_SCREEN).ok and valid(world.state.duplicate(true)),"A plain fabric screen still validates")
	var borrowed:=world.state.duplicate(true)
	for tile:Vector2i in tiles(LANE,false):borrowed.objects[World.key(tile)][FIELD]=true
	expect(not valid(borrowed),"Validator rejects the folded flag on another furniture type")

func blueprint_scenario()->void:
	fresh()
	expect(place(LANE,false).ok and fold(LANE).ok,"blueprint fixture")
	var rect:=Rect2i(LANE,Vector2i(2,1))
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,rect,"河岸屏風",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"Capturing a folded screen records geometry only")
	fresh()
	expect(place(LANE,true).ok and fold(LANE).ok,"vertical blueprint fixture")
	var tall:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(LANE,Vector2i(1,2)),"河岸屏風直",World.BUILD,World.NAMES)
	expect(tall.ok and tall.blueprint.pieces==[{"kind":KIND,"x":0,"y":0,"settings":{"vertical":true}}],"A vertical folded screen records only its orientation")
	if not design.ok or not tall.ok:return
	fresh()
	var site:=DEST
	var quote:=world.quote_blueprint(owner,design.blueprint,site,0)
	expect(quote.ok and quote.cost.bamboo==10 and quote.cost.cotton_cloth==4,"The blueprint quotes one recipe")
	put(guest,Vector2(site)+Vector2(-0.1,-0.1))
	expect(not world.quote_blueprint(owner,design.blueprint,site,0).ok,"A blueprint will not quote onto a clipping foot box")
	put(guest,GUEST_PARK)
	if quote.ok:
		var laid:=world.apply_blueprint(owner,"d".repeat(32),design.blueprint,site,0,quote.hash)
		var wide:Dictionary=world.state.objects.get(World.key(site),{})
		expect(laid.ok and wide.get("type")==KIND and not I.is_vertical(wide) and folded_state(tiles(site,false),false) and all_blocked(tiles(site,false),true),"The blueprint builds the screen unfolded and solid")
	fresh()
	var turned:=world.quote_blueprint(owner,design.blueprint,HOME,1)
	expect(turned.ok,"A quarter turn quotes a vertical screen")
	if turned.ok:
		var laid_turn:=world.apply_blueprint(owner,"e".repeat(32),design.blueprint,HOME,1,turned.hash)
		var anchor:=Vector2i(-1000,-1000)
		for k:String in world.state.objects:
			var piece:Dictionary=world.state.objects[k]
			if piece.get("type")==KIND and I.square_part(piece)==0:anchor=World.cell(k)
		var rotated:Dictionary=world.state.objects.get(World.key(anchor),{})
		expect(laid_turn.ok and I.is_vertical(rotated) and well_formed(tiles(anchor,true),true) and folded_state(tiles(anchor,true),false),"A turned plan builds the vertical screen unfolded")
	fresh()
	var upright:=world.quote_blueprint(owner,tall.blueprint,HOME,0)
	if upright.ok:
		var laid_tall:=world.apply_blueprint(owner,"f".repeat(32),tall.blueprint,HOME,0,upright.hash)
		expect(laid_tall.ok and well_formed(tiles(HOME,true),true) and folded_state(tiles(HOME,true),false) and all_blocked(tiles(HOME,true),true),"A vertical plan builds the screen unfolded and solid")
	else:expect(false,"A vertical plan quotes")

func regression_scenario()->void:
	fresh()
	expect(World.BUILD[KIND]=={"name":"河岸屏風","bamboo":10,"cotton_cloth":4},"The recipe is 竹材10 + 布料4")
	expect(World.BUILD[I.FABRIC_SCREEN]=={"name":"織布屏風","hardwood":10,"cotton_cloth":5} and World.BUILD[I.BEACH_CHAIR]=={"name":"折疊沙灘椅","wood":8,"cotton_cloth":4},"Neighbouring recipes are unchanged")
	expect(KIND=="riverside_screen" and KIND in I.TWO_CELL_STATIONS and KIND in I.ORIENTABLE_FOOTPRINTS and KIND in World.UNDO_SOLID,"The id is registered as a two-cell solid piece")
	var fabric:=act(owner,"build",HOME,I.FABRIC_SCREEN)
	var fabric_tiles:=[HOME,HOME+Vector2i.RIGHT]
	expect(fabric.ok and all_blocked(fabric_tiles,true),"The inn fabric screen still blocks both tiles")
	expect(not act(owner,I.RIVERSIDE_FOLD,HOME).ok and all_blocked(fabric_tiles,true),"The fold switch does nothing to a fabric screen")
	expect(not I.is_folded_passage(world.state.objects[World.key(HOME)]),"A fabric screen is never a passage")
	var chair_part:={"type":I.BEACH_CHAIR,"beach_chair_part":1,"beach_chair_folded":true}
	var chair_head:={"type":I.BEACH_CHAIR,"beach_chair_part":0,"beach_chair_folded":true}
	expect(I.is_folded_passage(chair_part) and not I.is_folded_passage(chair_head),"The folded chair footrest is still the only passable chair tile")
	expect(I.is_folded_passage({"type":I.FOREST_ARCH,"forest_arch_part":1}) and not I.is_folded_passage({"type":I.FOREST_ARCH,"forest_arch_part":0}),"Arch passages are unchanged")
	expect(not I.is_folded_screen({"type":KIND}) and I.is_folded_screen({"type":KIND,FIELD:true}) and not I.is_folded_screen({"type":I.FABRIC_SCREEN,FIELD:true}),"Only a riverside screen carrying the flag counts as folded")
	expect(not I.foot_box_hits(Vector2(42.5,42.5),[Vector2i(40,40)]) and I.foot_box_hits(Vector2(40.9,40.9),[Vector2i(41,41)]),"foot_box_hits matches the can_stand corner rule")

func assets_and_ui()->void:
	for entry:Array in [[ART_WIDE,Vector2(62,48)],[ART_LONG,Vector2(30,78)],[ART_FOLDED,Vector2(18,34)]]:
		var present:bool=ResourceLoader.exists(entry[0])
		expect(present,"Sprite exists: "+str(entry[0]))
		if present:
			var texture:Texture2D=load(entry[0])
			expect(texture!=null and texture.get_size()==entry[1],"Sprite size %s: %s"%[str(entry[1]),str(entry[0])])
	expect(app.view.RIVERSIDE_WIDE.resource_path==ART_WIDE and app.view.RIVERSIDE_LONG.resource_path==ART_LONG and app.view.RIVERSIDE_FOLDED.resource_path==ART_FOLDED,"The view renders the agreed sprite paths")
	expect(KIND in Panels.FURNITURE and KIND in Folio.TEA_COLLECTION and Folio.PLACEMENT_NOTES.has(KIND),"The furniture catalog, tea tab and placement note list the screen")

func build_menu_scenario()->void:
	fresh()
	app.session._send_snapshot(1)
	app._build_menu()
	var tea:Button
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="茶屋":tea=entry
	expect(tea!=null,"The tea house tab exists")
	if tea:tea.pressed.emit()
	var suffix:=str(tea.name).trim_prefix("BuildTab") if tea else ""
	var recipe:=app.modal.find_child("BuildSlot_"+KIND+"_"+suffix,true,false) as Button if tea else null
	expect(recipe!=null and recipe.is_visible_in_tree(),"The tea tab shows the riverside screen")
	if recipe:recipe.pressed.emit()
	var place_button:=app.modal.find_child("BuildPlace",true,false) as Button
	if place_button:place_button.pressed.emit()
	expect(app.building==KIND and app.view.build_placement_offsets(KIND)==[Vector2i.ZERO,Vector2i.RIGHT],"The build selector previews a 2x1 screen")
	expect(app.view.build_placement_blocks(DEST,KIND).is_empty(),"The preview marks free ground as buildable")
	app._perform_build_action("build",HOME,KIND)
	expect(world.state.objects.get(World.key(HOME),{}).get("type")==KIND and all_blocked(tiles(HOME,false),true),"The normal build flow places the screen")
	app.session._send_snapshot(1)
	var occupied:Dictionary=app.view.build_placement_blocks(HOME,KIND)
	expect(occupied.has(HOME) and occupied.has(HOME+Vector2i.RIGHT),"The preview marks both tiles of an existing screen as taken")
	app._close_modal()

func menu_scenario()->void:
	fresh()
	expect(place(HOME,false).ok,"menu fixture")
	app.session._send_snapshot(1)
	app._riverside_screen_menu(HOME+Vector2i.RIGHT)
	var toggle:=app.modal.find_child("RiversideScreenFold",true,false) as Button
	expect(toggle!=null and toggle.text=="收起屏風","The owner's card, opened from the far tile, offers folding")
	await capture("screen-controls")
	if toggle:toggle.pressed.emit()
	expect(folded_state(tiles(HOME,false),true) and all_blocked(tiles(HOME,false),false),"The card's switch folds the screen")
	app.session._send_snapshot(1)
	app._riverside_screen_menu(HOME)
	toggle=app.modal.find_child("RiversideScreenFold",true,false) as Button
	expect(toggle!=null and toggle.text=="展開屏風","A folded screen offers unfolding")
	if toggle:toggle.pressed.emit()
	expect(folded_state(tiles(HOME,false),false) and all_blocked(tiles(HOME,false),true),"The card's switch unfolds it again")
	app._close_modal()

func gallery()->void:
	for vertical in [false,true]:
		var tag:="vertical" if vertical else "horizontal"
		fresh()
		place(HOME,vertical)
		app.session._send_snapshot(1)
		app.view.queue_redraw()
		await process_frame
		await capture(tag+"-deployed")
		fold(HOME)
		app.session._send_snapshot(1)
		app.view.queue_redraw()
		await process_frame
		await capture(tag+"-folded")

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://riverside-screen-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="riverside-screen-owner"
	if app.session.host(0,"河岸屏風測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	world.add_player(guest,"旅客")
	world.state.time=720.0
	for x in range(40,45):
		for y in range(34,38):world.state.removed[World.key(Vector2i(x,y))]=true
	fresh()
	app.session._send_snapshot(1)

	assets_and_ui()
	regression_scenario()
	for vertical in [false,true]:
		scenario(vertical)
		walk_scenario(vertical)
	schema_scenario()
	blueprint_scenario()
	build_menu_scenario()
	await menu_scenario()
	await gallery()
	finish()
