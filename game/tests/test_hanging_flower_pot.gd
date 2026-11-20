extends SceneTree

const World=preload("res://scripts/world.gd")
const Fixtures=World.ROOF_FIXTURES
const KIND:=Fixtures.HANGING_POT
const A:=Vector2i(40,34)
const B:=Vector2i(41,34)
const C:=Vector2i(40,35)
const DOOR:=Vector2i(40,36)
var app
var world:World
var owner:String
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

func act(action:String,at:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"hanger-%d"%serial,action,at,extra)

func build(kind:String,at:Vector2i,actor:="")->bool:
	var result:=act("build",at,kind,actor)
	expect(result.ok,"Build %s at %s: %s"%[kind,at,result.message])
	return result.ok

func move(from:Vector2i,to:Vector2i,actor:="")->Dictionary:
	return act("move_object",from,World.key(to),actor)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	var directory:String=app.arg_value("hanger-preview","")
	var path:="user://hanger-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="hanger-owner"
	if app.session.host(0,"吊掛花盆測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	world.state.time=680.0
	var person:Dictionary=world.state.players[owner]
	person.x=40.5
	person.y=34.5
	person.inventory.merge({"wood":180,"stone":60,"glass":4,"copper_joint":2,"fiber":30,"clay":20},true)
	var ka:=World.key(A)
	var kb:=World.key(B)
	expect(act("build",A,KIND).message==Fixtures.SUPPORT_MESSAGE and person.inventory.clay==20,"Open sky refuses the pot without charging")
	build("floor",A)
	build("roof",A)
	var after_roof_fiber:int=person.inventory.fiber
	build(KIND,A)
	expect(person.inventory.clay==16 and person.inventory.fiber==after_roof_fiber-3,"The original G05 recipe charges four clay and three fiber")
	expect(world.can_stand(Vector2(40.5,34.5)),"Player can stand below the pot")
	expect(not act("build",A,KIND).ok and person.inventory.clay==16,"A second pot never overwrites the one hook")
	expect(move(A,B).message==Fixtures.SUPPORT_MESSAGE and world.has_hanging_pot(ka),"Moving under open sky retains the original pot")
	var blueprint:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(A,Vector2i.ONE),"吊掛屋頂",World.BUILD,World.NAMES)
	expect(blueprint.ok and blueprint.blueprint.pieces.size()==3,"Capture preserves floor, roof, and pot together")
	if blueprint.ok:
		var quote:=world.quote_blueprint(owner,blueprint.blueprint,B)
		expect(quote.ok and quote.cost.clay==4 and quote.cost.fiber==3+int(World.BUILD.roof.fiber),"Quote resolves roof support and covers both recipes")
		if quote.ok:
			var constructed:=world.apply_blueprint(owner,"a".repeat(32),blueprint.blueprint,B,0,quote.hash)
			expect(constructed.ok and world.has_hanging_pot(kb),"Blueprint places the complete roof fixture")
			var undo:String=world.state.construction.last.get(owner,{}).get("id","")
			expect(not undo.is_empty() and act(World.UNDO_ACTION,B,undo).ok and not world.state.roofs.has(kb) and not world.has_hanging_pot(kb),"Undo removes the copied floor, pot and roof together")
		var orphan:Dictionary=blueprint.blueprint.duplicate(true)
		orphan.pieces=orphan.pieces.filter(func(piece):return piece.kind==KIND)
		var denied:=world.quote_blueprint(owner,orphan,C)
		expect(not denied.ok and denied.message==Fixtures.SUPPORT_MESSAGE and denied.problems.size()==1,"Blueprint with no roof reports the exact problem")
	build("floor",B)
	build("roof",B)
	expect(move(A,B).ok and world.has_hanging_pot(kb) and not world.has_hanging_pot(ka),"Move between two own hooks succeeds")
	expect(act("remove",B).ok and world.state.roofs.has(kb),"Removing at the hook takes the pot first")
	var undo_id:String=world.state.construction.last.get(owner,{}).get("id","")
	expect(not undo_id.is_empty() and act(World.UNDO_ACTION,B,undo_id).ok and world.has_hanging_pot(kb),"Undo rehangs the pot on the surviving roof")
	var before_refund_fiber:int=world.state.players[owner].inventory.fiber
	expect(act("remove",B).ok and world.state.players[owner].inventory.clay==20 and world.state.players[owner].inventory.fiber==before_refund_fiber+3,"Removing returns the same recipe once")
	expect(act("remove",B).ok and not world.state.roofs.has(kb),"The roof can now be taken down")
	expect(act("remove",A).ok and not world.state.roofs.has(ka),"Clear the other manual roof")
	build("floor",C)
	build("floor",C+Vector2i.RIGHT)
	for edge in [Vector2i(40,33),Vector2i(41,33),Vector2i(39,34),Vector2i(42,34),Vector2i(39,35),Vector2i(42,35),Vector2i(41,36)]:
		build("window" if edge==Vector2i(41,33) else "wall",edge)
	build("door",DOOR)
	expect(World.is_auto_roof(world.state.roofs.get(ka)),"The closed room has automatic roof tiles")
	build(KIND,A)
	build(KIND,B)
	world.add_player("hanger-visitor","測試訪客")
	var visitor:Dictionary=world.state.players["hanger-visitor"]
	visitor.x=40.5
	visitor.y=34.5
	visitor.inventory.merge({"clay":10,"fiber":10},true)
	expect(not act("remove",A,"","hanger-visitor").ok and not move(A,C,"hanger-visitor").ok,"Visitors cannot remove or relocate the owner’s pot")
	expect(act("build",C,KIND,"hanger-visitor").message==Fixtures.SUPPORT_MESSAGE and visitor.inventory.clay==10,"An empty hook on another owner’s roof is unavailable")
	expect(act("remove",DOOR).message==Fixtures.REMOVE_MESSAGE and world.has_hanging_pot(ka) and world.state.objects.get(World.key(DOOR),{}).get("type")=="door","Opening the roof by removing a door rolls back atomically")
	world.state.players[owner].y=35.5
	app.session._send_snapshot(1)
	var app_view=app.view
	expect(app_view.build_placement_blocks(C,KIND).is_empty(),"Preview recognizes an open owned roof hook")
	expect(not app_view.build_placement_blocks(A,KIND).is_empty(),"Preview marks an occupied roof hook")
	if not directory.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(directory)
		app._build_menu()
		var tab:Button
		for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
			if candidate.text=="星砂溫室":tab=candidate
		expect(tab!=null,"The workshop has the greenhouse collection")
		if tab!=null:
			tab.pressed.emit()
			var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(tab.name).trim_prefix("BuildTab"),true,false) as Button
			expect(slot!=null and slot.is_visible_in_tree(),"The pot has a real selectable catalogue tile")
			if slot!=null:slot.pressed.emit()
		await capture(directory.path_join("workshop.png"))
		app._close_modal()
		app_view.zoom=2.0
		app_view.camera=Vector2(41.0,34.5)*32-Vector2(root.size)/4.0
		await capture(directory.path_join("hung.png"))
		await verify_sway(app_view)
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.has_hanging_pot(ka),"Reload retains the new item and its roof")
	var orphan_save:=world.state.duplicate(true)
	orphan_save.roofs.erase(ka)
	expect(not World.SAVE_SCHEMA.validate(orphan_save,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"An orphan pot cannot enter a loaded world")
	expect(act("remove",A).ok and act("remove",B).ok and act("remove",DOOR).ok and not world.state.roofs.has(ka),"Removing both pots releases the automatic roof for demolition")
	var garden:=Vector2i(38,34)
	expect(act("hoe",garden).ok and act("seed",garden,"radish").ok,"Prepare a real seeded crop")
	build("greenhouse_roof",garden)
	build(KIND,garden)
	var crop_key:=World.key(garden)
	expect(act("water",garden).ok and world.state.crops[crop_key].wet,"The crop under the hanging pot can still be watered")
	expect(act("remove",garden).ok and world.state.crops[crop_key].kind=="radish" and world.has_glass_roof(crop_key),"Removing a hanging pot leaves the planted crop and greenhouse pane intact")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("HANGING_POT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(path:String)->void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(path)==OK,"Capture "+path)

func sample_pot(view,at:float,quiet:bool)->PackedByteArray:
	view.elapsed=at
	view.reduced_motion=quiet
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var corner:Vector2=(view.screen(Vector2(B))+Vector2(2,-11))*view.view_zoom()
	return root.get_texture().get_image().get_region(Rect2i(Vector2i(corner),Vector2i(56,66))).get_data()

func verify_sway(view)->void:
	view.set_process(false)
	var start:PackedByteArray=await sample_pot(view,0.0,false)
	var later:PackedByteArray=await sample_pot(view,1.5,false)
	expect(start!=later,"Native pot pixels move between animation phases")
	start=await sample_pot(view,0.0,true)
	later=await sample_pot(view,1.5,true)
	expect(start==later,"Native pot pixels stay fixed with reduced motion")
