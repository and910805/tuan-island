extends SceneTree
## T10 竹編躺椅: a 1x2 (blueprint-rotatable to 2x1) single reclining seat. Reclining reuses the existing
## resident seat pose (RESIDENT_GOALS.MASTER_BENCH_SEAT, side 0): no free energy, no clock change, no bed.
## Native screenshots: --qa-size=1024 and --qa-dir=<folder>.

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Folio=preload("res://scripts/build_folio.gd")
const Industry=preload("res://scripts/industry.gd")
const Goals=World.RESIDENT_GOALS
const KIND:="bamboo_lounger"
const REST:="bamboo_lounger_rest"
const SEAT:=Goals.MASTER_BENCH_SEAT
const LONG_ART:="res://assets/ui-life/bamboo-lounger-long.png"
const WIDE_ART:="res://assets/ui-life/bamboo-lounger-wide.png"
const SITE:=Vector2i(40,34)      ## default vertical: halves at (40,34) and (40,35)
const MOVED:=Vector2i(43,34)     ## halves at (43,34) and (43,35)
const ROTATED:=Vector2i(44,35)   ## blueprint target; horizontal: halves at (44,35) and (45,35)
const OWNER_NAME:="躺椅屋主"
const GUEST:="bamboo-lounger-visitor"
const GUEST_NAME:="路過的阿蓮"
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
	print("BAMBOO_LOUNGER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

func pose(token:String)->Dictionary:
	return world.state.players[token].get(SEAT,{})

func rest(token:String,tile:Vector2i,id:String)->Dictionary:
	return world.act(token,id,REST,tile)

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func hex32()->String:
	return "%016x%016x"%[Time.get_ticks_usec(),randi()]

func focus_camera(tile:Vector2i)->void:
	app.view.camera=(Vector2(tile)+Vector2(1.0,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func publish()->void:
	app.session.peers[2]=GUEST
	app.session._send_snapshot(1)
	app.session.peers.erase(2)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://bamboo-lounger-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="bamboo-lounger-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	stand_at(owner,41.5,33.5)
	person.inventory.merge({"bamboo":80,"cotton_cloth":20},true)
	world.state.time=720.0
	for tile:Vector2i in [SITE,SITE+Vector2i.DOWN,MOVED,MOVED+Vector2i.DOWN,ROTATED,ROTATED+Vector2i.RIGHT]:
		world.state.removed[World.key(tile)]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(41.5,33.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)

	# --- Contract: id, recipe, footprint, collision, catalog, art -----------------------------------
	expect(Industry.BAMBOO_LOUNGER==KIND and Industry.LOUNGER_REST==REST,"Industry.BAMBOO_LOUNGER is bamboo_lounger")
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].get("name")=="竹編躺椅","The lounger has the display name 竹編躺椅")
	expect(World.BUILD[KIND].get("bamboo")==14 and World.BUILD[KIND].get("cotton_cloth")==3 and World.BUILD[KIND].size()==3,"Recipe is exactly 14 bamboo and 3 cotton cloth plus the name")
	expect(Industry.station_cells(KIND,true)==[Vector2i.ZERO,Vector2i.DOWN] and Industry.station_cells(KIND,false)==[Vector2i.ZERO,Vector2i.RIGHT],"Footprint is 1x2, or 2x1 when rotated")
	expect(KIND in Industry.ORIENTABLE_FOOTPRINTS and Industry.vertical_field(KIND)=="bamboo_lounger_vertical" and Industry.square_part_field(KIND)=="bamboo_lounger_part","The lounger is an orientable two-part footprint")
	expect(KIND in World.UNDO_SOLID and KIND in preload("res://scripts/house_rooms.gd").SOLID_OBJECTS,"It blocks movement and room checks")
	expect(Folio.TEA_COLLECTION.has(KIND) and Folio.TEA_COLLECTION[Folio.TEA_COLLECTION.size()-3]==KIND,"It follows the chime in the tea catalog (the T11 shelf and T12 pavilion close it)")
	expect(Folio.PLACEMENT_NOTES.has(KIND) and not str(Folio.PLACEMENT_NOTES[KIND]).is_empty(),"The build folio describes the lounger")
	expect(KIND in preload("res://scripts/life_ui_panels.gd").FURNITURE,"It is listed under 家具")
	var long:Texture2D=load(LONG_ART)
	var wide:Texture2D=load(WIDE_ART)
	expect(long!=null and long.get_size()==Vector2(30,64),"bamboo-lounger-long.png loads at 30x64")
	expect(wide!=null and wide.get_size()==Vector2(62,32),"bamboo-lounger-wide.png loads at 62x32")

	# --- Build: exact cost, default 1x2, both halves; construction undo -----------------------------
	var bamboo:int=person.inventory.bamboo
	var cloth:int=person.inventory.cotton_cloth
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"A real build action places the lounger for its owner"):
		await finish()
		return
	expect(person.inventory.bamboo==bamboo-14 and person.inventory.cotton_cloth==cloth-3,"Building spends 14 bamboo and 3 cotton cloth")
	expect(obj().get("bamboo_lounger_part")==0 and obj().get("bamboo_lounger_vertical")==true,"The anchor is part 0 and defaults to vertical (1x2)")
	expect(obj(SITE+Vector2i.DOWN).get("bamboo_lounger_part")==1 and obj(SITE+Vector2i.DOWN).get("type")==KIND,"The second half sits below")
	expect(World.station_anchor(world.state.objects,SITE+Vector2i.DOWN)==SITE,"Both halves resolve to one anchor")
	expect(world.blocked(SITE) and world.blocked(SITE+Vector2i.DOWN),"Both halves block walking")
	expect(valid(world.state),"The fresh state passes save validation")
	var summary:=world.undo_summary(owner)
	var undo_id:String=str(summary.get("id",""))
	if expect(summary.get("available")==true and not undo_id.is_empty(),"Undo is offered for the fresh lounger"):
		var undone:=world.act(owner,"undo-lounger",World.UNDO_ACTION,Vector2i.ZERO,undo_id)
		expect(undone.get("ok")==true and obj().is_empty() and obj(SITE+Vector2i.DOWN).is_empty(),"Undo clears both halves")
		expect(person.inventory.bamboo==bamboo and person.inventory.cotton_cloth==cloth,"Undo returns exactly the materials")
		app._perform_build_action("build",SITE,KIND)
		expect(obj().get("type")==KIND,"The lounger can be rebuilt after undo")
		undo_id=str(world.undo_summary(owner).get("id",""))
	app._select_tool("hoe")
	app.view.set_process(false)
	focus_camera(SITE)
	await capture("bamboo-lounger-empty")

	# --- Owner reclines: only the seat pose changes ---------------------------------------------------
	var energy:=int(person.mine_energy)
	var clock:=float(world.state.time)
	var bag:=var_to_str(person.inventory)
	var object_count: int = world.state.objects.size()
	var position_before:=Vector2(person.x,person.y)
	app.session._send_snapshot(1)
	app._interact()
	expect(pose(owner)=={"cell":World.key(SITE),"side":0},"Real _interact reclines the owner on seat 0 of the anchor")
	expect(Vector2(person.x,person.y)==position_before,"Reclining does not move the body")
	expect(int(person.mine_energy)==energy and float(world.state.time)==clock,"Reclining restores no energy and does not pass the clock")
	expect(var_to_str(person.inventory)==bag and world.state.objects.size()==object_count,"Reclining gives and spawns nothing")
	expect(not person.has(Industry.HOME_REST_FIELD) and not world.act(owner,"lounger-bed",Industry.CEDAR_BED,SITE).ok,"It is not a bed or a rest-place setting")
	app.session._send_snapshot(1)
	await capture("bamboo-lounger-owner-reclining")
	expect(app.view.occupied_loungers.has(World.key(SITE)),"The world view knows the lounger is occupied")

	# --- Guest: one at a time, either half, busy and owner-only guards ---------------------------------
	expect(not rest(GUEST,SITE+Vector2i.DOWN,"guest-busy").ok and not guest.has(SEAT),"A guest cannot recline on an occupied lounger (other half)")
	expect(rest(GUEST,SITE+Vector2i.DOWN,"guest-busy-2").get("message","")==Industry.LOUNGER_BUSY,"The refusal uses the lounger busy message")
	var move:=world.act(owner,"busy-move","move_object",SITE,World.key(MOVED))
	expect(not move.ok and move.get("message","")==Industry.LOUNGER_BUSY and obj().get("type")==KIND and obj(MOVED).is_empty(),"The owner cannot move an occupied lounger")
	var remove:=world.act(owner,"busy-remove","remove",SITE)
	expect(not remove.ok and remove.get("message","")==Industry.LOUNGER_BUSY and obj().get("type")==KIND,"The owner cannot dismantle an occupied lounger")
	remove=world.act(owner,"busy-remove-half","remove",SITE+Vector2i.DOWN)
	expect(not remove.ok and obj(SITE+Vector2i.DOWN).get("type")==KIND and var_to_str(person.inventory)==bag,"Removing by the second half is refused without a refund")
	if not undo_id.is_empty():
		var busy_undo:=world.act(owner,"busy-undo",World.UNDO_ACTION,Vector2i.ZERO,undo_id)
		expect(not busy_undo.ok and obj().get("type")==KIND and person.inventory.bamboo==bamboo-14,"Construction undo is refused while the lounger is occupied")
	expect(valid(world.state),"The occupied state passes save validation")

	# --- Save and reload keep the pose; forged poses are rejected ---------------------------------------
	expect(world.save(),"The world saves while someone reclines")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND and loaded.state.players[owner].get(SEAT,{})=={"cell":World.key(SITE),"side":0},"Reload keeps the lounger and the reclining pose")
	var forged:=world.state.duplicate(true)
	forged.players[GUEST][SEAT]={"cell":World.key(SITE),"side":0}
	expect(not valid(forged),"Validation rejects two people on one lounger")
	forged=world.state.duplicate(true)
	forged.players[owner][SEAT]={"cell":World.key(SITE),"side":1}
	expect(not valid(forged),"Validation rejects a second seat index")
	forged=world.state.duplicate(true)
	forged.players[owner][SEAT]={"cell":World.key(SITE+Vector2i.DOWN),"side":0}
	expect(not valid(forged),"Validation rejects a pose anchored on the second half")

	# --- Leaving: interact again, or simply move -------------------------------------------------------
	app._interact()
	expect(not person.has(SEAT),"Pressing interact again stands the owner up")
	expect(rest(owner,SITE+Vector2i.DOWN,"owner-again").ok and pose(owner).cell==World.key(SITE),"The other half also reclines onto the same anchor")
	world.move_player(owner,Vector2.UP,0.1)
	expect(not person.has(SEAT),"Keyboard movement stands the owner up")

	# --- Guest may recline when free, then cannot move or remove the owner's lounger --------------------
	expect(rest(GUEST,SITE,"guest-rest").ok and pose(GUEST)=={"cell":World.key(SITE),"side":0},"A guest can recline when nobody else is")
	expect(not rest(owner,SITE,"owner-busy").ok and not person.has(SEAT),"The owner is refused while the guest reclines")
	publish()
	await capture("bamboo-lounger-guest-reclining")
	world.move_player(GUEST,Vector2.UP,0.1)
	expect(not guest.has(SEAT),"The guest stands up by moving")
	var guest_move:=world.act(GUEST,"guest-move","move_object",SITE,World.key(MOVED))
	expect(not guest_move.ok and obj().get("type")==KIND and obj(MOVED).is_empty(),"A guest cannot move the owner's lounger")
	var guest_remove:=world.act(GUEST,"guest-remove","remove",SITE)
	expect(not guest_remove.ok and obj().get("type")==KIND,"A guest cannot dismantle the owner's lounger")

	# --- Owner moves the free lounger; both halves travel ----------------------------------------------
	stand_at(owner,41.5,33.5)
	expect(world.act(owner,"free-move","move_object",SITE,World.key(MOVED)).ok and obj(MOVED).get("type")==KIND,"With nobody reclining the owner can move the lounger")
	expect(obj(MOVED+Vector2i.DOWN).get("bamboo_lounger_part")==1 and obj(SITE).is_empty() and obj(SITE+Vector2i.DOWN).is_empty(),"The second half moves with it and the old cells are released")
	expect(world.act(owner,"move-back","move_object",MOVED,World.key(SITE)).ok and obj().get("type")==KIND,"...and the owner can move it back")

	# --- Blueprint: capture vertical, rotate into 2x1, recline on the second half ---------------------------
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(1,2)),"竹編躺椅",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND,"The blueprint captures the lounger as one piece"):
		expect(cut.blueprint.pieces[0].get("settings",{}).get("vertical")==true and cut.blueprint.width==1 and cut.blueprint.height==2,"The captured piece is vertical in a 1x2 blueprint")
		var turned:=Design.rotate(cut.blueprint,1,World.BUILD,World.NAMES)
		if expect(turned.get("ok")==true and turned.blueprint.pieces.size()==1,"One quarter turn rotates the blueprint"):
			expect(turned.blueprint.width==2 and turned.blueprint.height==1 and not turned.blueprint.pieces[0].get("settings",{}).get("vertical",false),"The rotated lounger is horizontal in a 2x1 blueprint")
		stand_at(owner,44.5,33.5)
		var quote:=world.quote_blueprint(owner,cut.blueprint,ROTATED,1)
		if expect(quote.get("ok")==true,"Quote for the rotated placement succeeds: "+str(quote.get("message",""))):
			bamboo=person.inventory.bamboo
			cloth=person.inventory.cotton_cloth
			var applied:=world.apply_blueprint(owner,hex32(),cut.blueprint,ROTATED,1,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the rotated blueprint succeeds: "+str(applied.get("message","")))
			expect(person.inventory.bamboo==bamboo-14 and person.inventory.cotton_cloth==cloth-3,"The blueprint charges exactly one lounger recipe")
			expect(obj(ROTATED).get("type")==KIND and not Industry.is_vertical(obj(ROTATED)),"The placed lounger is horizontal")
			expect(obj(ROTATED+Vector2i.RIGHT).get("bamboo_lounger_part")==1 and world.blocked(ROTATED) and world.blocked(ROTATED+Vector2i.RIGHT),"Its second half is to the right and both halves block")
			expect(valid(world.state),"The rotated state passes save validation")
			stand_at(owner,44.5,34.5)
			expect(rest(owner,ROTATED+Vector2i.RIGHT,"h-rest").ok and pose(owner)=={"cell":World.key(ROTATED),"side":0},"Reclining by the right half uses the anchor and side 0")
			focus_camera(ROTATED)
			app.session._send_snapshot(1)
			await capture("bamboo-lounger-horizontal-reclining")
			expect(not world.act(owner,"h-remove","remove",ROTATED).ok and obj(ROTATED).get("type")==KIND,"The occupied horizontal lounger cannot be dismantled")
			world.move_player(owner,Vector2.UP,0.1)
			var refund_bamboo:int=person.inventory.bamboo
			expect(world.act(owner,"h-free-remove","remove",ROTATED+Vector2i.RIGHT).ok and obj(ROTATED).is_empty() and obj(ROTATED+Vector2i.RIGHT).is_empty(),"Once free, removing by either half dismantles the whole lounger")
			expect(person.inventory.bamboo==refund_bamboo+14,"Dismantling refunds the bamboo")

	# --- Clean up the original ---------------------------------------------------------------------------
	stand_at(owner,41.5,33.5)
	expect(world.act(owner,"final-remove","remove",SITE).ok and obj().is_empty() and obj(SITE+Vector2i.DOWN).is_empty(),"The free lounger can be dismantled in one action")
	await finish()
