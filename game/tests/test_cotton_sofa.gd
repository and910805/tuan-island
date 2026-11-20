extends SceneTree

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Goals=World.RESIDENT_GOALS
const KIND:="cotton_double_sofa"
const SIT:=Goals.MASTER_BENCH_SIT
const SEAT:=Goals.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)      ## horizontal: halves at (40,34) and (41,34)
const MOVED:=Vector2i(43,34)
const ROTATED:=Vector2i(47,34)   ## blueprint target; vertical: halves at (47,34) and (47,35)
const OWNER_NAME:="山居木匠"
const GUEST:="cotton-sofa-visitor-ahlian"
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

func press(name:String)->bool:
	var button:=modal_button(name)
	if not expect(button!=null and not button.disabled,"Button is available: "+name):return false
	button.pressed.emit()
	return true

func modal_button(name:String)->Button:
	return app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null

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
	print("COTTON_SOFA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

func pose(token:String)->Dictionary:
	return world.state.players[token].get(SEAT,{})

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func hex32()->String:
	return "%016x%016x"%[Time.get_ticks_usec(),randi()]

func focus_camera(tile:Vector2i)->void:
	app.view.camera=(Vector2(tile)+Vector2(1.0,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://cotton-sofa-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="cotton-sofa-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	stand_at(owner,40.5,33.5)
	person.inventory.merge({"wood":80,"cotton_cloth":40},true)
	world.state.time=720.0
	for tile in [SITE,SITE+Vector2i.RIGHT,MOVED,MOVED+Vector2i.RIGHT,ROTATED,ROTATED+Vector2i.DOWN]:
		world.state.removed[World.key(tile)]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(41.5,33.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)

	# --- Contract: constant, new recipe, old sofa untouched ------------------------------------
	expect(Goals.COTTON_SOFA==KIND,"RESIDENT_GOALS.COTTON_SOFA is cotton_double_sofa")
	expect(World.BUILD.has(KIND) and not str(World.BUILD[KIND].get("name","")).is_empty(),"The double sofa has a display name")
	expect(World.BUILD[KIND].get("wood")==18 and World.BUILD[KIND].get("cotton_cloth")==6 and World.BUILD[KIND].size()==3,"Recipe is exactly 18 wood and 6 cotton cloth plus the name")
	expect(World.BUILD.has("sofa") and World.BUILD.sofa.name=="棉布小沙發" and World.BUILD.sofa.get("wood")==18 and World.BUILD.sofa.get("cotton_cloth")==2 and World.BUILD.sofa.size()==3,"The old 棉布小沙發 recipe is unchanged")
	expect(KIND in Goals.DOUBLE_BENCHES,"The sofa reuses the double-bench footprint and seat machinery")

	# --- Build: spends exact cost, two cells, second is a bench_end ----------------------------
	var wood:int=person.inventory.wood
	var cloth:int=person.inventory.cotton_cloth
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the sofa for its owner"):
		await finish()
		return
	expect(person.inventory.wood==wood-18 and person.inventory.cotton_cloth==cloth-6,"Building spends 18 wood and 6 cotton cloth")
	expect(obj(SITE+Vector2i.RIGHT).get("type")==KIND and obj(SITE+Vector2i.RIGHT).get("bench_end")==true,"The second half is a bench_end of the same sofa")
	expect(World.master_bench_anchor(world.state.objects,SITE+Vector2i.RIGHT)==SITE,"Both halves resolve to one anchor")

	# Construction undo: query ONLY before anyone sits (sitting closes undo via use tracking).
	var summary:=world.undo_summary(owner)
	expect(summary.get("available")==true and not str(summary.get("id","")).is_empty(),"Undo is offered for the fresh sofa before anyone sits")

	# --- Real _interact opens LifeTasks.cotton_sofa from BOTH halves ---------------------------
	app._select_tool("hoe")
	app.view.set_process(false)
	focus_camera(SITE)
	await capture("cotton-sofa-empty")
	for half in [0,1]:
		stand_at(owner,40.5+half,33.5)
		app.session._send_snapshot(1)
		app._close_modal()
		app._interact()
		expect(is_instance_valid(app.modal) and app.modal.visible and modal_button("CottonSofaSeat0")!=null and modal_button("CottonSofaSeat1")!=null,"_interact on half %d opens the cotton sofa dialog with both seat buttons"%half)
		expect(not has_seat_pose(owner),"Opening the dialog does not sit anyone")
	await capture("cotton-sofa-dialog-empty")

	# --- Owner sits on side 0 through the UI; own button then reads 起身 -------------------------
	press("CottonSofaSeat0")
	expect(pose(owner)=={"cell":World.key(SITE),"side":0},"Seat0 button sits the owner via MASTER_BENCH_SIT with anchor + side 0")
	app.session._send_snapshot(1)
	app._interact()
	var own_button:=modal_button("CottonSofaSeat0")
	expect(own_button!=null and own_button.text=="起身","The seated owner's own button is 起身")
	expect(modal_button("CottonSofaSeat1")!=null,"The other seat button is still present while seated")
	await capture("cotton-sofa-owner-ui-seated")
	app._close_modal()
	await capture("cotton-sofa-owner-seated")

	# --- A visitor takes the OTHER half without displacing the owner ---------------------------
	var other_half:=SITE+Vector2i.RIGHT
	expect(world.act(GUEST,"guest-sit-half-1",SIT,other_half).ok,"A visitor sits on the second half via MASTER_BENCH_SIT with that cell")
	expect(pose(GUEST)=={"cell":World.key(SITE),"side":1},"Visitor pose is anchor + side 1")
	expect(pose(owner)=={"cell":World.key(SITE),"side":0},"The owner is not displaced by the visitor")
	app.session.peers[2]=GUEST
	app.session._send_snapshot(1)
	app.session.peers.erase(2)
	var seated:Array=app.session.snapshot.players.values().filter(func(p):return p.get(SEAT,{}).get("cell")==World.key(SITE))
	expect(seated.size()==2 and seated.map(func(p):return int(p.get(SEAT).side)).has(0) and seated.map(func(p):return int(p.get(SEAT).side)).has(1),"The snapshot shows both players, one per side")
	await capture("cotton-sofa-visitor-seen-in-world")
	app._interact()
	expect(modal_button("CottonSofaSeat0")!=null and modal_button("CottonSofaSeat0").text=="起身","With a visitor beside them, the owner's own button is still 起身")
	await capture("cotton-sofa-owner-ui-two-seated")
	app._close_modal()

	# --- Denials: same seat, moving, removing --------------------------------------------------
	var third:="cotton-sofa-third-visitor"
	world.add_player(third,"第三位旅客",Vector2(40.5,33.2))
	expect(not world.act(third,"same-seat-0",SIT,SITE).ok and not world.state.players[third].has(SEAT),"The owner's seat refuses a third person")
	expect(not world.act(third,"same-seat-1",SIT,other_half).ok and not world.state.players[third].has(SEAT),"The visitor's seat refuses a third person")
	expect(not world.act(GUEST,"extra",SIT,SITE,"1").ok and pose(GUEST).side==1,"A sit request carrying an extra argument is refused and changes nothing")
	var inventory_before:=var_to_str(person.inventory)
	var move:=world.act(owner,"busy-move","move_object",SITE,World.key(MOVED))
	expect(not move.ok and not str(move.get("message","")).is_empty() and obj().get("type")==KIND and obj(MOVED).is_empty(),"Owner cannot move an occupied sofa")
	move=world.act(owner,"busy-move-half","move_object",other_half,World.key(MOVED))
	expect(not move.ok and obj().get("type")==KIND and obj(MOVED).is_empty(),"Moving by the occupied second half is refused too")
	var remove:=world.act(owner,"busy-remove","remove",SITE)
	expect(not remove.ok and not str(remove.get("message","")).is_empty() and obj().get("type")==KIND,"Owner cannot dismantle an occupied sofa")
	remove=world.act(owner,"busy-remove-half","remove",other_half)
	expect(not remove.ok and obj(other_half).get("type")==KIND and var_to_str(person.inventory)==inventory_before,"Removing via the second half is refused without a refund")
	expect(pose(owner).side==0 and pose(GUEST).side==1,"Refused move/remove leaves both people seated")

	# --- Saved poses reload; forged poses are rejected -----------------------------------------
	expect(world.save(),"The world saves with two people seated")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND and loaded.state.objects.get(World.key(other_half),{}).get("bench_end")==true,"Reload keeps both halves")
	expect(loaded.state.players[owner].get(SEAT,{})=={"cell":World.key(SITE),"side":0} and loaded.state.players[GUEST].get(SEAT,{})=={"cell":World.key(SITE),"side":1},"Reload keeps both saved poses (anchor + side 0/1)")
	expect(valid(world.state),"The live two-seat state passes save validation")
	var forged:=world.state.duplicate(true)
	forged.players[GUEST][SEAT]={"cell":World.key(SITE),"side":0}
	expect(not valid(forged),"Save validation rejects two people on side 0")
	forged=world.state.duplicate(true)
	forged.players[GUEST][SEAT]={"cell":World.key(SITE),"side":2}
	expect(not valid(forged),"Save validation rejects a third seat index")
	forged=world.state.duplicate(true)
	forged.players[GUEST][SEAT]={"cell":World.key(other_half),"side":1}
	expect(not valid(forged),"Save validation rejects a pose anchored on the bench_end half")

	# --- Leaving: 起身 through the UI, keyboard for the other ----------------------------------
	app._interact()
	press("CottonSofaSeat0")
	expect(not person.has(SEAT) and pose(GUEST).side==1,"Pressing 起身 stands only the owner; the visitor stays")
	expect(world.act(owner,"resit",SIT,SITE).ok and pose(owner).side==0,"The owner can sit on side 0 again")
	world.move_player(owner,Vector2.UP,0.1)
	expect(not person.has(SEAT),"Keyboard movement stands the owner up")
	expect(pose(GUEST).side==1,"The visitor remains seated after the owner's keyboard leave")
	world.move_player(GUEST,Vector2.DOWN,0.1)
	expect(not guest.has(SEAT),"Keyboard movement stands the visitor up")
	expect(not world.state.players[third].has(SEAT),"The refused third person never held a seat")
	stand_at(owner,40.5,33.5)
	stand_at(GUEST,41.5,33.5)
	expect(world.act(GUEST,"guest-side-1",SIT,other_half).ok and pose(GUEST).side==1,"Side 1 is free again after standing")
	world.move_player(GUEST,Vector2.DOWN,0.1)
	expect(world.act(owner,"free-move","move_object",SITE,World.key(MOVED)).ok and obj(MOVED).get("type")==KIND and obj().is_empty(),"With nobody seated the owner can move the sofa")
	expect(world.act(owner,"move-back","move_object",MOVED,World.key(SITE)).ok and obj().get("type")==KIND,"...and move it back")

	# --- Blueprint: rotate to vertical, keep two separate seats --------------------------------
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,1)),"棉布雙人沙發",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND,"Blueprint captures the sofa as one piece"):
		expect(not cut.blueprint.pieces[0].has("settings"),"The horizontal sofa has no vertical setting")
		var turned:=Design.rotate(cut.blueprint,1,World.BUILD,World.NAMES)
		if expect(turned.get("ok")==true and turned.blueprint.pieces.size()==1,"One quarter turn rotates the blueprint"):
			expect(turned.blueprint.pieces[0].get("settings",{}).get("vertical")==true and turned.blueprint.width==1 and turned.blueprint.height==2,"The rotated sofa is vertical in a 1x2 blueprint")
		stand_at(owner,45.5,33.5)
		var quote:=world.quote_blueprint(owner,cut.blueprint,ROTATED,1)
		if expect(quote.get("ok")==true,"Quote for the rotated placement succeeds: "+str(quote.get("message",""))):
			wood=person.inventory.wood
			cloth=person.inventory.cotton_cloth
			var applied:=world.apply_blueprint(owner,hex32(),cut.blueprint,ROTATED,1,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the rotated blueprint succeeds: "+str(applied.get("message","")))
			expect(person.inventory.wood==wood-18 and person.inventory.cotton_cloth==cloth-6,"The blueprint charges exactly one sofa recipe")
			expect(obj(ROTATED).get("type")==KIND and obj(ROTATED).get("bench_vertical")==true,"The placed sofa is vertical")
			expect(obj(ROTATED+Vector2i.DOWN).get("bench_end")==true and obj(ROTATED+Vector2i.DOWN).get("bench_vertical")==true,"Its second half sits below the anchor")
			expect(World.master_bench_offset(obj(ROTATED))==Vector2i.DOWN,"The seat offset is DOWN for the vertical sofa")
			stand_at(owner,46.5,34.5)
			stand_at(GUEST,46.5,35.5)
			app.session._send_snapshot(1)
			expect(world.act(owner,"v-top",SIT,ROTATED).ok and pose(owner)=={"cell":World.key(ROTATED),"side":0},"The upper half is seat 0 of the vertical sofa")
			expect(world.act(GUEST,"v-bottom",SIT,ROTATED+Vector2i.DOWN).ok and pose(GUEST)=={"cell":World.key(ROTATED),"side":1},"The lower half is a separate seat 1")
			stand_at(third,48.5,35.5)
			expect(not world.act(third,"v-same",SIT,ROTATED+Vector2i.DOWN).ok,"A taken vertical seat is refused")
			expect(valid(world.state),"The vertical two-seat state passes save validation")
			focus_camera(ROTATED)
			app.session.peers[2]=GUEST
			app.session._send_snapshot(1)
			app.session.peers.erase(2)
			await capture("cotton-sofa-vertical-two-seated")
			# Real UI on the vertical sofa, from the lower half.
			stand_at(owner,46.5,34.5)
			world.act(owner,"v-stand",SIT,ROTATED)
			focus_camera(ROTATED)
			stand_at(owner,46.5,35.5)
			app.session._send_snapshot(1)
			app._interact()
			expect(modal_button("CottonSofaSeat0")!=null and modal_button("CottonSofaSeat1")!=null,"The vertical sofa dialog also has two seat buttons")
			await capture("cotton-sofa-vertical-dialog")
			app._close_modal()
			world.move_player(GUEST,Vector2.LEFT,0.1)
			expect(world.act(owner,"v-remove","remove",ROTATED+Vector2i.DOWN).ok and obj(ROTATED).is_empty() and obj(ROTATED+Vector2i.DOWN).is_empty(),"Once free, removing by either half dismantles the whole vertical sofa")

	# --- Clean up the original ----------------------------------------------------------------
	stand_at(owner,40.5,33.5)
	expect(world.act(owner,"final-remove","remove",SITE).ok and obj().is_empty() and obj(SITE+Vector2i.RIGHT).is_empty(),"The free sofa can be dismantled in one action")
	await finish()

func has_seat_pose(token:String)->bool:
	return world.state.players[token].has(SEAT)
