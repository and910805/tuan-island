extends SceneTree

## T03 靛藍坐墊: a one-tile ground seat that reuses the 矮背木椅 seat and busy rules.
## Run natively or headless; pass --qa-size=1024 (else 1280) and optionally --qa-dir=<folder>.

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Industry=preload("res://scripts/industry.gd")
const Goals=World.RESIDENT_GOALS
const KIND:=Industry.INDIGO_CUSHION
const NAME:="靛藍坐墊"
const CHAIR_KIND:="chair"
const SIT:=Goals.MASTER_BENCH_SIT
const SEAT:=Goals.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,34)
const UNDO_A:=Vector2i(44,34)
const UNDO_B:=Vector2i(46,34)
const CHAIR:=Vector2i(40,37)
const OWNER_NAME:="靛藍坐墊屋主"
const GUEST:="indigo-cushion-visitor-ahlian"
const GUEST_NAME:="路過的阿蓮"
const FAR:="indigo-cushion-visitor-far-ahmei"
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.3).timeout
	app.view.queue_redraw()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.25).timeout
	for suffix in ["",".bak",".writer-lock",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INDIGO_CUSHION_TESTS size=%s checks=%d failures=%d"%[str(root.size),checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func ground(tile:=SITE)->Dictionary:
	return world.state.ground.get(World.key(tile),{})

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

## Everything a seat must NOT touch: the whole player record minus pose/position.
func stats_of(token:String)->Dictionary:
	var copy:Dictionary=world.state.players[token].duplicate(true)
	for field in [SEAT,"x","y","fishing","receipts"]:copy.erase(field)
	return copy

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://indigo-cushion-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="indigo-cushion-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	stand_at(owner,40.5,33.5)
	person.inventory.merge({"wood":40,"fiber":40,"stone":40,"cotton_cloth":10,"blue_dye":4},true)
	world.state.time=720.0
	for tile in [SITE,MOVED,UNDO_A,UNDO_B,CHAIR]:world.state.removed[World.key(tile)]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(41.5,33.5))
	world.add_player(FAR,"遠方的阿美",Vector2(48.5,40.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)
	expect(valid(world.state),"A world with no cushion (an old world) passes save validation")

	# --- Recipe: exact cost, new id, passable ----------------------------------------------------
	expect(KIND=="indigo_cushion","Industry.INDIGO_CUSHION is the indigo_cushion id")
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].name==NAME,"The cushion is displayed as 靛藍坐墊")
	expect(World.BUILD[KIND].get("cotton_cloth")==3 and World.BUILD[KIND].get("blue_dye")==1 and World.BUILD[KIND].size()==3,"Cost is exactly 3 cotton cloth and 1 blue dye plus the name")
	expect(World.BUILD.has(CHAIR_KIND) and World.BUILD[CHAIR_KIND].get("wood")==6 and World.BUILD[CHAIR_KIND].size()==2,"The wooden chair recipe is unchanged")
	expect(not KIND in World.UNDO_SOLID,"The cushion is not a solid object")
	if app.view.INDIGO_CUSHION_ART:expect(app.view.INDIGO_CUSHION_ART.get_size()==Vector2(28,22),"The cushion art is 28x22 pixels")

	# --- Transaction safety: failed builds change nothing ------------------------------------------
	var saved_inventory:Dictionary=person.inventory.duplicate(true)
	person.inventory.blue_dye=0
	var no_dye:=world.act(owner,"no-dye","build",SITE,KIND)
	expect(not no_dye.ok and obj().is_empty() and person.inventory.cotton_cloth==saved_inventory.cotton_cloth,"Without blue dye the build fails and spends nothing")
	person.inventory.blue_dye=saved_inventory.blue_dye
	person.inventory.cotton_cloth=2
	var no_cloth:=world.act(owner,"no-cloth","build",SITE,KIND)
	expect(not no_cloth.ok and obj().is_empty() and person.inventory.blue_dye==saved_inventory.blue_dye,"Without enough cloth the build fails and spends nothing")
	person.inventory.cotton_cloth=saved_inventory.cotton_cloth
	var floor_before:=var_to_str(world.state.ground)

	# --- Real build on a normal floor --------------------------------------------------------------
	expect(world.act(owner,"floor","build",SITE,"floor").ok and ground().get("type")=="floor","A normal floor is laid first")
	var floor_record:=var_to_str(ground())
	var cloth:=int(person.inventory.cotton_cloth)
	var dye:=int(person.inventory.blue_dye)
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the cushion for its owner"):
		await finish()
		return
	expect(person.inventory.cotton_cloth==cloth-3 and person.inventory.blue_dye==dye-1,"Building spends exactly 3 cotton cloth and 1 blue dye")
	expect(var_to_str(ground())==floor_record,"The normal floor underneath is untouched by the cushion")
	expect(not world.blocked(SITE) and world.can_stand(Vector2(SITE)+Vector2(0.5,0.5)),"The cushion tile stays passable")
	expect(not world.act(owner,"double","build",SITE,KIND).ok and person.inventory.cotton_cloth==cloth-3,"A second cushion on the same tile is refused without charge")
	expect(valid(world.state),"A fresh cushion on a floor passes save validation")

	# --- Original chair is unaffected ----------------------------------------------------------------
	stand_at(owner,40.5,36.5)
	var wood:=int(person.inventory.wood)
	expect(world.act(owner,"chair","build",CHAIR,CHAIR_KIND).ok and obj(CHAIR).get("type")==CHAIR_KIND and person.inventory.wood==wood-6,"The wooden chair still builds for 6 wood")
	stand_at(owner,40.5,33.5)

	# --- Real interaction: sit with no stat or resource change ---------------------------------------
	app._select_tool("hoe")
	app.view.set_process(false)
	app.view.camera=(Vector2(SITE)+Vector2(0.5,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	var before:=stats_of(owner)
	var objects_before:=var_to_str(world.state.objects)
	app.session._send_snapshot(1)
	expect(app.view.interaction_focus()==World.key(SITE),"The cushion gets the nearby interaction prompt")
	await capture("indigo-cushion-empty")
	app._interact()
	expect(person.get(SEAT,{})=={"cell":World.key(SITE),"side":0},"app._interact sits via MASTER_BENCH_SIT with the MASTER_BENCH_SEAT pose")
	expect(not is_instance_valid(app.modal) or not app.modal.visible,"Sitting opens no dialog")
	expect(stats_of(owner)==before and var_to_str(world.state.objects)==objects_before,"Sitting changes no stat, inventory, coin or object")
	app.session._send_snapshot(1)
	expect(app.view.interaction_focus()==World.key(SITE),"A seated player keeps the stand-up prompt")
	await capture("indigo-cushion-owner-seated")
	expect(valid(world.state),"The live occupied-cushion state passes save validation")

	# --- Co-op: one seat, but other players walk straight through the occupied tile --------------------
	expect(not world.act(GUEST,"busy",SIT,SITE).ok and not guest.has(SEAT),"Only one person fits on the cushion")
	expect(not world.act(FAR,"far",SIT,SITE).ok and not world.state.players[FAR].has(SEAT),"Sitting needs the player to be near the cushion")
	expect(not world.act(GUEST,"extra",SIT,SITE,"1").ok and not guest.has(SEAT),"A sit request with a bogus side/extra is refused")
	expect(not world.act(GUEST,"empty-tile",SIT,Vector2i(41,35)).ok and not guest.has(SEAT),"Sitting on a tile with no seat is refused")
	expect(world.can_stand(Vector2(SITE)+Vector2(0.5,0.5)),"The occupied cushion square can still be stood on")
	stand_at(GUEST,40.5,33.2)
	var start_y:float=guest.y
	for step in 24:world.move_player(GUEST,Vector2.DOWN,0.1)
	expect(float(guest.y)>float(SITE.y)+1.0 and float(guest.y)>start_y+1.5,"Another character walks across the occupied tile")
	expect(absf(float(guest.x)-40.5)<0.01 and not guest.has(SEAT),"The walker was neither blocked nor seated")
	expect(person.get(SEAT,{}).get("cell")==World.key(SITE),"The owner stays seated while someone walks through")
	stand_at(GUEST,40.74,34.88)
	app.session.peers[2]=GUEST
	app.session._send_snapshot(1)
	app.session.peers.erase(2)
	app.toast_time=0
	await capture("indigo-cushion-walker-on-seated")
	stand_at(GUEST,41.5,33.5)
	expect(person.inventory.cotton_cloth==cloth-3 and person.inventory.blue_dye==dye-1,"Walking through changes no resource")

	# --- Busy rules: move, dismantle and undo are blocked while seated -------------------------------
	cloth=int(person.inventory.cotton_cloth)
	dye=int(person.inventory.blue_dye)
	var move:=world.act(owner,"busy-move","move_object",SITE,World.key(MOVED))
	expect(not move.ok and str(move.get("message",""))==Industry.INDIGO_CUSHION_BUSY and obj().get("type")==KIND and obj(MOVED).is_empty(),"Cannot move an occupied cushion")
	var remove:=world.act(owner,"busy-remove","remove",SITE)
	expect(not remove.ok and str(remove.get("message",""))==Industry.INDIGO_CUSHION_BUSY and obj().get("type")==KIND,"Cannot dismantle an occupied cushion")
	expect(person.inventory.cotton_cloth==cloth and person.inventory.blue_dye==dye and ground().get("type")=="floor","A refused move/remove refunds nothing and keeps the floor")
	var guest_move:=world.act(GUEST,"guest-busy-remove","remove",SITE)
	expect(not guest_move.ok and obj().get("type")==KIND,"A visitor cannot dismantle it while it is occupied either")

	# --- Original chair remains valid next to an occupied cushion --------------------------------------
	stand_at(GUEST,40.5,36.5)
	expect(world.act(GUEST,"chair-sit",SIT,CHAIR).ok and guest.get(SEAT,{}).get("cell")==World.key(CHAIR),"A visitor sits on the original chair")
	expect(valid(world.state),"A seated cushion and a seated chair validate together")
	stand_at(owner,40.5,36.0)
	var chair_remove:=world.act(owner,"chair-busy","remove",CHAIR)
	expect(not chair_remove.ok and str(chair_remove.get("message",""))==Industry.WOOD_CHAIR_BUSY and obj(CHAIR).get("type")==CHAIR_KIND,"The chair keeps its own busy message")
	stand_at(owner,40.5,33.5)
	expect(person.get(SEAT,{}).get("cell")==World.key(SITE),"The cushion occupant is unaffected by the chair")

	# --- Saved occupied cushion compatibility -----------------------------------------------------------
	expect(world.save(),"The world saves with the cushion and chair occupied")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND and loaded.state.players[owner].get(SEAT,{}).get("cell")==World.key(SITE),"Reload keeps the cushion and the occupied pose")
	expect(loaded.state.ground.get(World.key(SITE),{}).get("type")=="floor","Reload keeps the floor under the cushion")
	var forged:=world.state.duplicate(true)
	forged.players[FAR][SEAT]={"cell":World.key(SITE),"side":0}
	expect(not valid(forged),"Save validation rejects two occupants on one cushion")
	forged=world.state.duplicate(true)
	forged.players[owner][SEAT]={"cell":World.key(SITE),"side":1}
	expect(not valid(forged),"Save validation rejects a second seat index on a one-seat cushion")
	forged=world.state.duplicate(true)
	forged.players[owner][SEAT]={"cell":World.key(Vector2i(41,35)),"side":0}
	expect(not valid(forged),"Save validation rejects a pose on a tile with no seat")
	world.act(GUEST,"chair-stand",SIT,CHAIR)
	expect(not guest.has(SEAT),"The chair visitor stands up")

	# --- Blueprint capture keeps the cushion; floor stays a separate layer -------------------------------
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"靛藍坐墊",World.BUILD,World.NAMES)
	var kinds:Array=[]
	if cut.ok:
		for piece in cut.blueprint.pieces:kinds.append(piece.kind)
	expect(cut.ok and KIND in kinds and "floor" in kinds,"Blueprint captures both the cushion and its floor")

	# --- A disconnected visitor no longer reserves the seat ----------------------------------------------
	world.act(owner,"stand-by-action",SIT,SITE)
	expect(not person.has(SEAT),"The sit action toggles the owner back up")
	stand_at(GUEST,41.5,33.5)
	expect(world.act(GUEST,"guest-sit",SIT,SITE).ok and guest.get(SEAT,{}).get("cell")==World.key(SITE),"A visitor (not the owner) may sit")
	world.active_tokens.erase(GUEST)
	var moved:=world.act(owner,"after-leave-move","move_object",SITE,World.key(MOVED))
	if expect(moved.ok and obj(MOVED).get("type")==KIND and obj().is_empty(),"A cushion whose visitor left can be moved"):
		expect(ground().get("type")=="floor" and ground(MOVED).is_empty(),"Moving the cushion leaves the floor in place")
		expect(world.act(owner,"back","move_object",MOVED,World.key(SITE)).ok and obj().get("type")==KIND,"...and moved back")
	expect(not guest.has(SEAT),"Moving clears the disconnected visitor's old pose")
	world.active_tokens[GUEST]=true

	# --- Keyboard movement releases; interacting again releases ------------------------------------------------
	stand_at(owner,40.5,33.5)
	app.session._send_snapshot(1)
	app._interact()
	expect(person.get(SEAT,{}).get("cell")==World.key(SITE),"Owner sits again")
	world.move_player(owner,Vector2.UP,0.1)
	expect(not person.has(SEAT),"Keyboard movement stands the owner up")
	app.session._send_snapshot(1)
	app._interact()
	app._interact()
	expect(not person.has(SEAT),"Interacting again releases the seat")

	# --- Undo that would replace an occupied cushion is blocked ------------------------------------------------
	stand_at(owner,45.5,33.5)
	stand_at(GUEST,45.5,33.5)
	expect(world.act(owner,"undo-build","build",UNDO_A,KIND).ok,"Build the cushion that will be undone")
	expect(world.act(owner,"undo-move","move_object",UNDO_A,World.key(UNDO_B)).ok and obj(UNDO_B).get("type")==KIND,"Move it so the undo would restore the old tile")
	var summary:=world.undo_summary(owner)
	expect(summary.get("available")==true and not str(summary.get("id","")).is_empty(),"Undo is offered for the move")
	var undo:=world.act(owner,"undo-free",World.UNDO_ACTION,Vector2i.ZERO,str(summary.get("id","")))
	expect(undo.ok and obj(UNDO_A).get("type")==KIND and obj(UNDO_B).is_empty(),"The unused move can be undone: "+str(undo.get("message","")))
	expect(world.act(owner,"undo-move-again","move_object",UNDO_A,World.key(UNDO_B)).ok,"A new move creates its own undo record")
	summary=world.undo_summary(owner)
	expect(world.act(GUEST,"undo-sit",SIT,UNDO_B).ok and guest.get(SEAT,{}).get("cell")==World.key(UNDO_B),"A visitor sits on the moved cushion")
	undo=world.act(owner,"undo-busy",World.UNDO_ACTION,Vector2i.ZERO,str(summary.get("id","")))
	expect(not undo.ok and obj(UNDO_B).get("type")==KIND and obj(UNDO_A).is_empty() and guest.get(SEAT,{}).get("cell")==World.key(UNDO_B),"Undo is refused while seated and nothing changes")
	world.move_player(GUEST,Vector2.DOWN,0.1)
	expect(not guest.has(SEAT),"Walking releases the visitor")
	expect(not world.undo_summary(owner).get("available",false),"Using the furniture closes its move's undo record")
	expect(valid(world.state),"The state is valid after undo and the next move")

	# --- Dismantle refunds the full cost and keeps the floor ---------------------------------------------------------
	cloth=int(person.inventory.cotton_cloth)
	dye=int(person.inventory.blue_dye)
	expect(world.act(owner,"final-remove-undo","remove",UNDO_B).ok and obj(UNDO_B).is_empty(),"The free moved cushion can be dismantled")
	stand_at(owner,40.5,33.5)
	expect(world.act(owner,"final-remove-main","remove",SITE).ok and obj().is_empty(),"The free cushion can be dismantled")
	expect(person.inventory.cotton_cloth==cloth+6 and person.inventory.blue_dye==dye+2,"Dismantling refunds the original cost each time")
	expect(var_to_str(ground())==floor_record,"The normal floor survives dismantling")
	expect(valid(world.state),"The final state passes save validation")
	expect(floor_before!=var_to_str(world.state.ground),"(sanity) the floor fixture really changed the ground")
	await finish()
