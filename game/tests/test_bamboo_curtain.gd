extends SceneTree
## T04 半透竹簾 focused test. Works on native windows and with --headless.
## Optional screenshots (native only): -- --qa-dir=<folder> [--qa-size=1024]

const World=preload("res://scripts/world.gd")
const Fixtures=World.WALL_FIXTURES
const CurtainArt=preload("res://scripts/bamboo_curtain_art.gd")
const RoofVisibility=preload("res://scripts/roof_visibility.gd")
const KIND:=Fixtures.BAMBOO_CURTAIN
const ASSET:="res://assets/ui-life/bamboo-curtain.png"
const HOOK:=Vector2i(41,36)
const NEXT:=Vector2i(42,36)
const WINDOW:=HOOK+Vector2i.UP
const NEXT_WINDOW:=NEXT+Vector2i.UP
const PLAIN:=Vector2i(43,36)
const PLAIN_WALL:=PLAIN+Vector2i.UP
var app
var world:World
var owner:String
var output:String
var serial:=0
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(action:String,cell:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"bamboo-curtain-%d"%serial,action,cell,extra)

func curtain(cell:Vector2i)->bool:
	return world.state.objects.get(World.key(cell),{}).get("type")==KIND

func has_type(cell:Vector2i,kind:String)->bool:
	return world.state.objects.get(World.key(cell),{}).get("type")==kind

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	var path:="user://bamboo-curtain-test-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="bamboo-curtain-builder-qa"
	if app.session.host(0,"半透竹簾測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	world.state.time=740.0
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=37.5
	person.inventory.merge({"wood":160,"stone":30,"fiber":40,"bamboo":40,"glass":12},true)
	var base_bamboo:=int(person.inventory.bamboo)
	var base_fiber:=int(person.inventory.fiber)

	# --- asset (art is delivered separately; this pins the agreed contract)
	expect(ResourceLoader.exists(ASSET),"Curtain sprite exists at the agreed path")
	var texture:=load(ASSET) as Texture2D
	expect(texture!=null and texture.get_size()==Vector2(28,24),"Curtain sprite is 28x24")
	if texture!=null:
		var image:=texture.get_image()
		var clear:=0
		var solid:=0
		for y in image.get_height():
			for x in image.get_width():
				var a:=image.get_pixel(x,y).a
				if a<0.01:clear+=1
				elif a>0.5:solid+=1
		expect(clear>0 and solid>0,"Curtain sprite is a woven mix of transparent gaps and bamboo")

	# --- recipe and constants
	expect(KIND=="bamboo_curtain" and KIND in Fixtures.KINDS and Fixtures.support_type(KIND)=="window" and Fixtures.support_type(Fixtures.LIFEBUOY)=="wall","Curtain hangs on windows; other fixtures keep walls")
	var recipe:Dictionary=World.BUILD[KIND]
	expect(recipe.name=="半透竹簾" and recipe.bamboo==6 and recipe.fiber==2 and recipe.size()==3,"Recipe is bamboo 6 and fiber 2")
	expect(not KIND in World.UNDO_SOLID,"Curtain never blocks walking")

	# --- support validation
	var refused:=act("build",HOOK,KIND)
	expect(refused.message==Fixtures.CURTAIN_SUPPORT_MESSAGE and not curtain(HOOK) and int(person.inventory.bamboo)==base_bamboo and int(person.inventory.fiber)==base_fiber,"Open ground is refused without charging materials")
	expect(act("build",PLAIN_WALL,"wall").ok,"Build an ordinary wall")
	expect(act("build",PLAIN,KIND).message==Fixtures.CURTAIN_SUPPORT_MESSAGE and not curtain(PLAIN),"An ordinary wall does not carry a curtain")
	expect(act("remove",PLAIN_WALL).ok,"Remove the ordinary wall again")
	expect(act("build",WINDOW,"window").ok and has_type(WINDOW,"window"),"Build the owner window")
	var window_undo:=world.undo_summary(owner)
	app.session._send_snapshot(1)
	expect(app.view.build_placement_blocks(HOOK,KIND).is_empty() and app.view.build_placement_blocks(NEXT,KIND).get(NEXT)==Fixtures.CURTAIN_SUPPORT_MESSAGE,"Preview consumes the same window rule")
	expect(Fixtures.has_support(world.state.objects,HOOK,owner,KIND) and not Fixtures.has_support(world.state.objects,HOOK,owner),"Window supports the curtain, not the default wall rule")

	# --- folio / thumbnail
	app._build_menu()
	var slot:Button
	for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
		candidate.pressed.emit()
		var found:Array=app.modal.find_children("BuildSlot_"+KIND+"_*","Button",true,false)
		if not found.is_empty():
			slot=found[0]
			break
	expect(slot!=null and slot.is_visible_in_tree(),"Curtain shows on a workshop shelf")
	if slot!=null:slot.pressed.emit()
	await capture("workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	if place!=null:place.pressed.emit()
	expect(app.building==KIND,"Choose the curtain through its recipe")

	# --- placement transaction
	app._perform_build_action("build",HOOK,KIND)
	expect(curtain(HOOK) and has_type(WINDOW,"window"),"Curtain and window coexist")
	expect(int(person.inventory.bamboo)==base_bamboo-6 and int(person.inventory.fiber)==base_fiber-2,"Build charges exactly bamboo 6 and fiber 2")
	expect(world.blocked(WINDOW) and world.can_stand(Vector2(41.5,36.5)),"Window still blocks; the curtain cell stays walkable")
	var again:=act("build",HOOK,KIND)
	expect(not again.ok and int(person.inventory.bamboo)==base_bamboo-6,"One curtain per window and no second charge")

	# --- support cannot be removed or moved out from under it
	expect(act("remove",WINDOW).message==Fixtures.CURTAIN_REMOVE_MESSAGE and has_type(WINDOW,"window"),"Window cannot be dismantled while the curtain hangs on it")
	expect(act("move_object",HOOK,World.key(NEXT)).message==Fixtures.CURTAIN_SUPPORT_MESSAGE and curtain(HOOK),"Moving to unsupported space is refused")
	expect(act("move_object",WINDOW,World.key(NEXT_WINDOW)).message=="牆門窗請拆除後重新建造，材料會退回","Windows themselves still cannot be moved")
	world.add_player("curtain-guest","訪客")
	var guest:Dictionary=world.state.players["curtain-guest"]
	guest.x=42.5
	guest.y=37.5
	guest.inventory.merge({"wood":30,"stone":5,"glass":2},true)
	expect(act("build",NEXT_WINDOW,"window","curtain-guest").ok,"A guest builds their own window next door")
	expect(act("move_object",HOOK,World.key(NEXT)).message==Fixtures.CURTAIN_SUPPORT_MESSAGE and curtain(HOOK),"The owner cannot hang the curtain on someone else's window")
	expect(not act("remove",HOOK,"","curtain-guest").ok and curtain(HOOK),"Visitors cannot take the curtain down")
	expect(act("remove",NEXT_WINDOW,"","curtain-guest").ok and act("build",NEXT_WINDOW,"window").ok,"Replace the neighbouring window with the owner's")
	var move_before:=world.undo_summary(owner)
	expect(act("move_object",HOOK,World.key(NEXT)).ok and curtain(NEXT) and not curtain(HOOK),"Move between valid windows")
	expect(int(person.inventory.bamboo)==base_bamboo-6 and int(person.inventory.fiber)==base_fiber-2,"Move costs nothing and copies nothing")
	expect(act("remove",NEXT_WINDOW).message==Fixtures.CURTAIN_REMOVE_MESSAGE,"The new window is protected too")

	# --- view
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.camera=Vector2(41.9,36.0)*32-Vector2(root.size)/4.0
	await capture("mounted")

	# --- save / load
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects[World.key(NEXT)].type==KIND,"Primary save restores the moved curtain")
	expect(valid(world.state.duplicate(true)),"Mounted layout validates")
	var orphan:=world.state.duplicate(true)
	orphan.objects.erase(World.key(NEXT_WINDOW))
	expect(not valid(orphan),"Validator rejects a curtain whose window is missing")
	var on_wall:=world.state.duplicate(true)
	on_wall.objects[World.key(NEXT_WINDOW)].type="wall"
	expect(not valid(on_wall),"Validator rejects a curtain hanging on an ordinary wall")
	var stolen:=world.state.duplicate(true)
	stolen.objects[World.key(NEXT_WINDOW)].owner="curtain-guest"
	expect(not valid(stolen),"Validator rejects a curtain on someone else's window")
	var stuffed:=world.state.duplicate(true)
	stuffed.objects[World.key(NEXT)].items={"wood":1}
	expect(not valid(stuffed),"Validator rejects curtain contents")

	# --- undo
	var undo:=world.undo_summary(owner)
	expect(undo.get("id","")!=move_before.get("id","") and act(World.UNDO_ACTION,HOOK,str(undo.get("id",""))).ok and curtain(HOOK) and not curtain(NEXT),"Undo restores the original mount")
	var unsafe:=act(World.UNDO_ACTION,WINDOW,str(window_undo.get("id","")))
	expect(not unsafe.ok and has_type(WINDOW,"window") and curtain(HOOK),"Undoing the window while the curtain hangs is refused")

	# --- blueprint
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(WINDOW,Vector2i(1,2)),"竹簾窗",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces.size()==2,"Blueprint captures the window and its curtain")
	var bamboo_before:=int(person.inventory.bamboo)
	if design.ok:
		var destination:=WINDOW+Vector2i.LEFT
		var quote:=world.quote_blueprint(owner,design.blueprint,destination)
		expect(quote.ok and quote.cost.bamboo==6 and quote.cost.fiber==2,"Blueprint quotes the curtain recipe once")
		if quote.ok:
			expect(world.apply_blueprint(owner,"b".repeat(32),design.blueprint,destination,0,quote.hash).ok and curtain(destination+Vector2i.DOWN) and has_type(destination,"window"),"Apply builds the window first and hangs the curtain on it")
			expect(int(person.inventory.bamboo)==bamboo_before-6,"Blueprint charges the curtain once")
			expect(act("remove",destination+Vector2i.DOWN).ok and int(person.inventory.bamboo)==bamboo_before,"Dismantle repays the blueprint curtain")
			expect(act("remove",destination).ok,"Its window is removable once the curtain is down")

	# --- roof-linked opacity (pure rule; same snapshots the renderer reads)
	var snap:=world.state.duplicate(true)
	snap.roofs={}
	for cell:Vector2i in [WINDOW,HOOK,HOOK+Vector2i.DOWN,HOOK+Vector2i.DOWN*2,HOOK+Vector2i.RIGHT,HOOK+Vector2i.RIGHT+Vector2i.DOWN]:
		snap.roofs[World.key(cell)]={"type":"roof","owner":owner}
	snap.players[owner].x=41.5
	snap.players[owner].y=37.5
	var inside:=RoofVisibility.faded(snap,owner)
	expect(inside.has(World.key(HOOK)) and CurtainArt.alpha(inside,HOOK)==CurtainArt.INDOOR_ALPHA,"Cutaway room: the curtain turns translucent")
	snap.players[owner].x=48.5
	snap.players[owner].y=40.5
	var outside:=RoofVisibility.faded(snap,owner)
	expect(not outside.has(World.key(HOOK)) and CurtainArt.alpha(outside,HOOK)==CurtainArt.OUTDOOR_ALPHA,"Roof closed: the curtain keeps its full weave")
	expect(CurtainArt.alpha({World.key(WINDOW):true},HOOK)==CurtainArt.INDOOR_ALPHA and CurtainArt.alpha({},HOOK)==CurtainArt.OUTDOOR_ALPHA,"Either its cell or its window being cut away counts as indoors")
	expect(CurtainArt.INDOOR_ALPHA<CurtainArt.OUTDOOR_ALPHA and CurtainArt.INDOOR_ALPHA>0.16,"Indoor opacity sits between the faded roof and full weave")

	# --- renderer reads the real world view state (drawing needs a rendering server)
	var native:=DisplayServer.get_name()!="headless"
	if native:
		var live_data:Dictionary=app.view.data
		var live_player:String=app.view.player_id
		snap.players[owner].x=41.5
		snap.players[owner].y=37.5
		app.view.data=snap
		app.view.player_id=owner
		app.view.queue_redraw()
		await process_frame
		await process_frame
		expect(app.view.roof_faded.has(World.key(HOOK)) and CurtainArt.alpha(app.view.roof_faded,HOOK)==CurtainArt.INDOOR_ALPHA,"World view exposes the live cutaway state to the curtain")
		await capture("cutaway")
		snap.players[owner].x=48.5
		snap.players[owner].y=40.5
		app.view.queue_redraw()
		await process_frame
		await process_frame
		expect(not app.view.roof_faded.has(World.key(HOOK)),"World view roof closed again when the player leaves")
		await capture("roofed")
		app.view.data=live_data
		app.view.player_id=live_player

	# --- cleanup of the placed mounts
	expect(act("remove",HOOK).ok and int(person.inventory.bamboo)==base_bamboo and int(person.inventory.fiber)==base_fiber,"Dismantle repays exactly one recipe")
	expect(act("remove",WINDOW).ok and not world.state.objects.has(World.key(WINDOW)),"Window is removable once the curtain is gone")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BAMBOO_CURTAIN_TESTS display=%s checks=%d failures=%d"%[DisplayServer.get_name(),checks,failures])
	quit(int(failures>0))

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join("bamboo-curtain-"+name+".png"))==OK,"Capture "+name)
