extends SceneTree
## T02 雙人竹長椅: a 2x1 bamboo bench with two independent seats. It reuses the cotton double sofa's
## shared seating, move, rotate, undo, visitor and collision rules (RESIDENT_GOALS.INDEPENDENT_TWO_SEATS).

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Folio=preload("res://scripts/build_folio.gd")
const Goals=World.RESIDENT_GOALS
const KIND:="bamboo_double_bench"
const SOFA:="cotton_double_sofa"
const WIDE_ART:="res://assets/ui-life/bamboo-bench-wide.png"
const LONG_ART:="res://assets/ui-life/bamboo-bench-long.png"
const SIT:=Goals.MASTER_BENCH_SIT
const SEAT:=Goals.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)      ## horizontal: halves at (40,34) and (41,34)
const MOVED:=Vector2i(43,34)
const ROTATED:=Vector2i(47,34)   ## blueprint target; vertical: halves at (47,34) and (47,35)
const OWNER_NAME:="山居木匠"
const GUEST:="bamboo-bench-visitor-ahlian"
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

func modal_has_text(node:Node,text:String)->bool:
	if node is Label and (node as Label).text==text:return true
	for child in node.get_children():
		if modal_has_text(child,text):return true
	return false

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
	print("BAMBOO_BENCH_TESTS checks=%d failures=%d"%[checks,failures])
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

## Let the interpolation (0.1s) finish and a few frames pass so the follow camera has fully settled.
func settle()->void:
	await create_timer(0.3).timeout
	for frame in 3:await process_frame

## The conventional follow camera must stay put while nobody walks: sample it over many frames.
func camera_is_still(label:String)->void:
	await settle()
	var anchor:Vector2=app.view.camera
	var steady:=true
	for frame in 30:
		await process_frame
		if app.view.camera!=anchor:steady=false
	expect(steady,"The camera does not move across 30 frames: "+label)

func has_seat_pose(token:String)->bool:
	return world.state.players[token].has(SEAT)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://bamboo-bench-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="bamboo-bench-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	stand_at(owner,40.5,33.5)
	person.inventory.merge({"bamboo":80,"fiber":40,"wood":40,"cotton_cloth":20},true)
	world.state.time=720.0
	for tile in [SITE,SITE+Vector2i.RIGHT,MOVED,MOVED+Vector2i.RIGHT,ROTATED,ROTATED+Vector2i.DOWN]:
		world.state.removed[World.key(tile)]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(41.5,33.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)

	# --- Contract: constant, recipe, display, shared two-seat group, art, cotton sofa untouched ----
	expect(Goals.BAMBOO_BENCH==KIND,"RESIDENT_GOALS.BAMBOO_BENCH is bamboo_double_bench")
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].get("name")=="雙人竹長椅","The bench has the display name 雙人竹長椅")
	expect(World.BUILD[KIND].get("bamboo")==10 and World.BUILD[KIND].get("fiber")==4 and World.BUILD[KIND].size()==3,"Recipe is exactly 10 bamboo and 4 fiber plus the name")
	expect(KIND in Goals.DOUBLE_BENCHES and KIND in Goals.INDEPENDENT_TWO_SEATS and SOFA in Goals.INDEPENDENT_TWO_SEATS,"Bench and sofa share the independent two-seat group and the double-bench footprint")
	expect(Goals.MASTER_BENCH not in Goals.INDEPENDENT_TWO_SEATS and Goals.STONE_BENCH not in Goals.INDEPENDENT_TWO_SEATS,"The older shared benches keep their own behavior")
	expect(Goals.COTTON_SOFA==SOFA and Goals.COTTON_SOFA_BUSY.begins_with("棉布雙人沙發") and Goals.two_seat_busy(SOFA)==Goals.COTTON_SOFA_BUSY,"The cotton sofa names and busy message are unchanged")
	expect(World.BUILD[SOFA].get("wood")==18 and World.BUILD[SOFA].get("cotton_cloth")==6 and World.BUILD[SOFA].size()==3,"The cotton double sofa recipe is unchanged")
	expect(Goals.two_seat_busy(KIND).begins_with("雙人竹長椅") and Goals.two_seat_busy(KIND)!=Goals.COTTON_SOFA_BUSY,"The bench has its own busy message")
	expect(Folio.PLACEMENT_NOTES.has(KIND) and not str(Folio.PLACEMENT_NOTES[KIND]).is_empty(),"The build folio describes the bench")
	expect(KIND in preload("res://scripts/life_ui_panels.gd").FURNITURE,"The bench is listed under 家具 in the build catalog")
	expect(KIND in World.UNDO_SOLID and KIND in preload("res://scripts/house_rooms.gd").SOLID_OBJECTS,"The bench blocks movement and room checks like the sofa")
	var wide:Texture2D=load(WIDE_ART)
	var long:Texture2D=load(LONG_ART)
	expect(wide!=null and wide.get_size()==Vector2(62,35),"bamboo-bench-wide.png loads at 62x35")
	expect(long!=null and long.get_size()==Vector2(30,58),"bamboo-bench-long.png loads at 30x58")
	expect(app.view.independent_seat_art(KIND,false)==wide and app.view.independent_seat_art(KIND,true)==long,"The world view picks the bamboo art for each orientation")
	expect(app.view.independent_seat_art(SOFA,false)!=wide and app.view.independent_seat_art(SOFA,true)!=long,"The cotton sofa still uses its own art")

	# --- Build: spends exact cost, two cells, second is a bench_end ---------------------------------
	var bamboo:int=person.inventory.bamboo
	var fiber:int=person.inventory.fiber
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the bench for its owner"):
		await finish()
		return
	expect(person.inventory.bamboo==bamboo-10 and person.inventory.fiber==fiber-4,"Building spends 10 bamboo and 4 fiber")
	expect(obj(SITE+Vector2i.RIGHT).get("type")==KIND and obj(SITE+Vector2i.RIGHT).get("bench_end")==true,"The second half is a bench_end of the same bench")
	expect(World.master_bench_anchor(world.state.objects,SITE+Vector2i.RIGHT)==SITE,"Both halves resolve to one anchor")
	expect(world.blocked(SITE) and world.blocked(SITE+Vector2i.RIGHT),"Both halves block walking")

	# Construction undo: refunds both materials and clears both halves; then rebuild.
	var summary:=world.undo_summary(owner)
	if expect(summary.get("available")==true and not str(summary.get("id","")).is_empty(),"Undo is offered for the fresh bench before anyone sits"):
		var undone:=world.act(owner,"undo-bamboo-bench",World.UNDO_ACTION,Vector2i.ZERO,str(summary.id))
		expect(undone.get("ok")==true,"Undo removes the fresh bench: "+str(undone.get("message","")))
		expect(obj().is_empty() and obj(SITE+Vector2i.RIGHT).is_empty(),"Undo clears both halves")
		expect(person.inventory.bamboo==bamboo and person.inventory.fiber==fiber,"Undo returns exactly 10 bamboo and 4 fiber")
		app._perform_build_action("build",SITE,KIND)
		expect(obj().get("type")==KIND and person.inventory.bamboo==bamboo-10 and person.inventory.fiber==fiber-4,"The bench can be rebuilt after undo")
		summary=world.undo_summary(owner)
		expect(summary.get("available")==true,"The rebuilt bench is undoable again")

	# --- Real _interact opens the native seat dialog from BOTH halves ------------------------------
	app._select_tool("hoe")
	app.view.set_process(false)
	focus_camera(SITE)
	await capture("bamboo-bench-empty")
	for half in [0,1]:
		stand_at(owner,40.5+half,33.5)
		app.session._send_snapshot(1)
		app._close_modal()
		app._interact()
		expect(is_instance_valid(app.modal) and app.modal.visible and modal_button("CottonSofaSeat0")!=null and modal_button("CottonSofaSeat1")!=null,"_interact on half %d opens the seat dialog with both seat buttons"%half)
		expect(modal_has_text(app.modal,"雙人竹長椅"),"The dialog is titled 雙人竹長椅 (half %d)"%half)
		expect(modal_button("CottonSofaSeat0").text=="左側・坐下" and modal_button("CottonSofaSeat1").text=="右側・坐下","Both seats read 坐下 on the empty bench (half %d)"%half)
		expect(not has_seat_pose(owner),"Opening the dialog does not sit anyone")
	await capture("bamboo-bench-dialog-empty")

	# --- Owner sits on side 0 through the UI; no camera movement while settled ---------------------
	app._close_modal()
	stand_at(owner,40.5,33.5)
	app.session._send_snapshot(1)
	app.view.set_process(true)
	await settle()
	var before_sit:Vector2=app.view.camera
	var position_before:=Vector2(person.x,person.y)
	app._interact()
	press("CottonSofaSeat0")
	expect(pose(owner)=={"cell":World.key(SITE),"side":0},"Seat0 button sits the owner via MASTER_BENCH_SIT with anchor + side 0")
	expect(Vector2(person.x,person.y)==position_before,"Sitting does not move the player body")
	app.session._send_snapshot(1)
	await camera_is_still("owner seated")
	expect(app.view.camera==before_sit,"Sitting does not shift the follow camera")
	app._interact()
	var own_button:=modal_button("CottonSofaSeat0")
	expect(own_button!=null and own_button.text=="起身","The seated owner's own button is 起身")
	expect(modal_button("CottonSofaSeat1")!=null and modal_button("CottonSofaSeat1").text=="右側・坐下","The other seat stays available while the owner sits")
	await capture("bamboo-bench-owner-ui-seated")
	app._close_modal()
	await capture("bamboo-bench-owner-seated")

	# --- A visitor takes the OTHER half without displacing the owner -------------------------------
	var other_half:=SITE+Vector2i.RIGHT
	expect(world.act(GUEST,"guest-sit-half-1",SIT,other_half).ok,"A visitor sits on the second half via MASTER_BENCH_SIT with that cell")
	expect(pose(GUEST)=={"cell":World.key(SITE),"side":1},"Visitor pose is anchor + side 1")
	expect(pose(owner)=={"cell":World.key(SITE),"side":0},"The owner is not displaced by the visitor")
	app.session.peers[2]=GUEST
	app.session._send_snapshot(1)
	app.session.peers.erase(2)
	var seated:Array=app.session.snapshot.players.values().filter(func(p):return p.get(SEAT,{}).get("cell")==World.key(SITE))
	expect(seated.size()==2 and seated.map(func(p):return int(p.get(SEAT).side)).has(0) and seated.map(func(p):return int(p.get(SEAT).side)).has(1),"The snapshot shows both players, one per side")
	await camera_is_still("owner and visitor seated")
	expect(app.view.camera==before_sit,"A second sitter does not shift the owner's camera")
	app.view.set_process(false)
	app.toast_time=0
	await capture("bamboo-bench-visitor-seen-in-world")
	app._interact()
	expect(modal_button("CottonSofaSeat0")!=null and modal_button("CottonSofaSeat0").text=="起身","With a visitor beside them, the owner's own button is still 起身")
	expect(modal_button("CottonSofaSeat1")!=null and modal_button("CottonSofaSeat1").text=="右側・有人" and modal_button("CottonSofaSeat1").disabled,"The visitor's seat shows 有人 and is disabled for the owner")
	await capture("bamboo-bench-owner-ui-two-seated")
	app._close_modal()

	# --- Full bench, movement and removal denials ---------------------------------------------------
	var third:="bamboo-bench-third-visitor"
	world.add_player(third,"第三位旅客",Vector2(40.5,33.2))
	expect(not world.act(third,"same-seat-0",SIT,SITE).ok and not world.state.players[third].has(SEAT),"The full bench's seat 0 refuses a third person")
	expect(not world.act(third,"same-seat-1",SIT,other_half).ok and not world.state.players[third].has(SEAT),"The full bench's seat 1 refuses a third person")
	expect(not world.act(GUEST,"extra",SIT,SITE,"1").ok and pose(GUEST).side==1,"A sit request carrying an extra argument is refused and changes nothing")
	var inventory_before:=var_to_str(person.inventory)
	var move:=world.act(owner,"busy-move","move_object",SITE,World.key(MOVED))
	expect(not move.ok and move.get("message","")==Goals.BAMBOO_BENCH_BUSY and obj().get("type")==KIND and obj(MOVED).is_empty(),"Owner cannot move an occupied bench")
	move=world.act(owner,"busy-move-half","move_object",other_half,World.key(MOVED))
	expect(not move.ok and obj().get("type")==KIND and obj(MOVED).is_empty(),"Moving by the occupied second half is refused too")
	var remove:=world.act(owner,"busy-remove","remove",SITE)
	expect(not remove.ok and remove.get("message","")==Goals.BAMBOO_BENCH_BUSY and obj().get("type")==KIND,"Owner cannot dismantle an occupied bench")
	remove=world.act(owner,"busy-remove-half","remove",other_half)
	expect(not remove.ok and obj(other_half).get("type")==KIND and var_to_str(person.inventory)==inventory_before,"Removing via the second half is refused without a refund")
	expect(not world.undo_summary(owner).get("available",false),"Construction undo is closed once the bench has been sat on")
	expect(pose(owner).side==0 and pose(GUEST).side==1,"Refused move/remove leaves both people seated")

	# --- Saved poses reload; forged poses are rejected ----------------------------------------------
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

	# --- Leaving: 起身 through the UI, keyboard for the other ---------------------------------------
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

	# --- Movement: moving carries the whole bench; the old cells are released -----------------------
	expect(world.act(owner,"free-move","move_object",SITE,World.key(MOVED)).ok and obj(MOVED).get("type")==KIND and obj().is_empty(),"With nobody seated the owner can move the bench")
	expect(obj(MOVED+Vector2i.RIGHT).get("bench_end")==true and obj(SITE+Vector2i.RIGHT).is_empty(),"The second half moves with it")
	expect(world.act(owner,"move-back","move_object",MOVED,World.key(SITE)).ok and obj().get("type")==KIND,"...and move it back")

	# --- Blueprint: rotate to vertical, keep two separate seats -------------------------------------
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,1)),"雙人竹長椅",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND,"Blueprint captures the bench as one piece"):
		expect(not cut.blueprint.pieces[0].has("settings"),"The horizontal bench has no vertical setting")
		var turned:=Design.rotate(cut.blueprint,1,World.BUILD,World.NAMES)
		if expect(turned.get("ok")==true and turned.blueprint.pieces.size()==1,"One quarter turn rotates the blueprint"):
			expect(turned.blueprint.pieces[0].get("settings",{}).get("vertical")==true and turned.blueprint.width==1 and turned.blueprint.height==2,"The rotated bench is vertical in a 1x2 blueprint")
		stand_at(owner,45.5,33.5)
		var quote:=world.quote_blueprint(owner,cut.blueprint,ROTATED,1)
		if expect(quote.get("ok")==true,"Quote for the rotated placement succeeds: "+str(quote.get("message",""))):
			bamboo=person.inventory.bamboo
			fiber=person.inventory.fiber
			var applied:=world.apply_blueprint(owner,hex32(),cut.blueprint,ROTATED,1,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the rotated blueprint succeeds: "+str(applied.get("message","")))
			expect(person.inventory.bamboo==bamboo-10 and person.inventory.fiber==fiber-4,"The blueprint charges exactly one bench recipe")
			expect(obj(ROTATED).get("type")==KIND and obj(ROTATED).get("bench_vertical")==true,"The placed bench is vertical")
			expect(obj(ROTATED+Vector2i.DOWN).get("bench_end")==true and obj(ROTATED+Vector2i.DOWN).get("bench_vertical")==true,"Its second half sits below the anchor")
			expect(World.master_bench_offset(obj(ROTATED))==Vector2i.DOWN,"The seat offset is DOWN for the vertical bench")
			stand_at(owner,46.5,34.5)
			stand_at(GUEST,46.5,35.5)
			app.session._send_snapshot(1)
			expect(world.act(owner,"v-top",SIT,ROTATED).ok and pose(owner)=={"cell":World.key(ROTATED),"side":0},"The upper half is seat 0 of the vertical bench")
			expect(world.act(GUEST,"v-bottom",SIT,ROTATED+Vector2i.DOWN).ok and pose(GUEST)=={"cell":World.key(ROTATED),"side":1},"The lower half is a separate seat 1")
			stand_at(third,48.5,35.5)
			expect(not world.act(third,"v-same",SIT,ROTATED+Vector2i.DOWN).ok,"A taken vertical seat is refused")
			expect(valid(world.state),"The vertical two-seat state passes save validation")
			focus_camera(ROTATED)
			app.session.peers[2]=GUEST
			app.session._send_snapshot(1)
			app.session.peers.erase(2)
			await capture("bamboo-bench-vertical-two-seated")
			# Real UI on the vertical bench, from the lower half.
			stand_at(owner,46.5,34.5)
			world.act(owner,"v-stand",SIT,ROTATED)
			focus_camera(ROTATED)
			stand_at(owner,46.5,35.5)
			app.session.peers[2]=GUEST
			app.session._send_snapshot(1)
			app.session.peers.erase(2)
			app._interact()
			expect(modal_button("CottonSofaSeat0")!=null and modal_button("CottonSofaSeat1")!=null,"The vertical bench dialog also has two seat buttons")
			expect(modal_button("CottonSofaSeat0").text=="上側・坐下" and modal_button("CottonSofaSeat1").text=="下側・有人","The vertical dialog names the upper and lower seats")
			await capture("bamboo-bench-vertical-dialog")
			app._close_modal()
			world.move_player(GUEST,Vector2.LEFT,0.1)
			expect(world.act(owner,"v-remove","remove",ROTATED+Vector2i.DOWN).ok and obj(ROTATED).is_empty() and obj(ROTATED+Vector2i.DOWN).is_empty(),"Once free, removing by either half dismantles the whole vertical bench")
			expect(person.inventory.bamboo==bamboo and person.inventory.fiber==fiber,"Dismantling refunds 10 bamboo and 4 fiber")

	# --- Clean up the original ---------------------------------------------------------------------
	stand_at(owner,40.5,33.5)
	bamboo=person.inventory.bamboo
	expect(world.act(owner,"final-remove","remove",SITE).ok and obj().is_empty() and obj(SITE+Vector2i.RIGHT).is_empty(),"The free bench can be dismantled in one action")
	expect(person.inventory.bamboo==bamboo+10,"The free bench returns its bamboo")

	# --- Regression: the cotton sofa keeps its own two-seat behavior --------------------------------
	app._perform_build_action("build",SITE,SOFA)
	if expect(obj().get("type")==SOFA,"The cotton double sofa can still be built"):
		stand_at(owner,40.5,33.5)
		stand_at(GUEST,41.5,33.5)
		expect(world.act(owner,"sofa-0",SIT,SITE).ok and world.act(GUEST,"sofa-1",SIT,other_half).ok,"Two people can still sit on the cotton sofa")
		stand_at(third,40.5,33.2)
		expect(not world.act(third,"sofa-3",SIT,SITE).ok,"A third person is still refused on the cotton sofa")
		var sofa_remove:=world.act(owner,"sofa-busy-remove","remove",SITE)
		expect(not sofa_remove.ok and sofa_remove.get("message","")==Goals.COTTON_SOFA_BUSY,"An occupied cotton sofa still reports its own busy message")
		world.move_player(owner,Vector2.UP,0.1)
		world.move_player(GUEST,Vector2.DOWN,0.1)
		expect(world.act(owner,"sofa-final","remove",SITE).ok and obj().is_empty(),"The free cotton sofa can still be dismantled")
	await finish()
