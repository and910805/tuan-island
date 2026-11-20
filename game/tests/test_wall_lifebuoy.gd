extends SceneTree

const World=preload("res://scripts/world.gd")
const Fixtures=World.WALL_FIXTURES
const KIND:=Fixtures.LIFEBUOY
const HOOK:=Vector2i(41,36)
const NEXT:=Vector2i(42,36)
const WALL:=HOOK+Vector2i.UP
const NEXT_WALL:=NEXT+Vector2i.UP
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
	return world.act(owner if actor.is_empty() else actor,"wall-lifebuoy-%d"%serial,action,cell,extra)

func fixture(cell:Vector2i)->bool:
	return world.state.objects.get(World.key(cell),{}).get("type")==KIND

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("lifebuoy-preview","")
	var path:="user://wall-lifebuoy-test-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="lifebuoy-builder-qa"
	if app.session.host(0,"救生圈牆飾測試",path)!=OK:
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
	person.inventory.merge({"wood":60,"fiber":16,"cotton_cloth":6},true)
	expect(act("build",HOOK,KIND).message==Fixtures.SUPPORT_MESSAGE and not fixture(HOOK) and int(person.inventory.fiber)==16,"Unsupported placement keeps materials untouched")
	expect(act("build",WALL,"wall@coast").ok and world.state.objects[World.key(WALL)].style=="coast","Build a real coast-style wooden wall")
	app.session._send_snapshot(1)
	expect(app.view.build_placement_blocks(HOOK,KIND).is_empty() and app.view.build_placement_blocks(NEXT,KIND).get(NEXT)==Fixtures.SUPPORT_MESSAGE,"Preview consumes the authoritative ownership rule")
	app._build_menu()
	var tab:Button
	for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if candidate.text=="海邊":tab=candidate
	expect(tab!=null,"Coastal workshop opens")
	if tab!=null:
		tab.pressed.emit()
		var button:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(tab.name).trim_prefix("BuildTab"),true,false) as Button
		expect(button!=null and button.is_visible_in_tree(),"New decoration shows on the coastal shelf")
		if button!=null:button.pressed.emit()
	await capture("workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	if place!=null:place.pressed.emit()
	expect(app.building==KIND and app.building_style=="","Choose the bespoke wall fixture through its recipe")
	var before_fiber:=int(person.inventory.fiber)
	var before_cloth:=int(person.inventory.cotton_cloth)
	app._perform_build_action("build",HOOK,KIND)
	expect(fixture(HOOK) and person.inventory.fiber==before_fiber-8 and person.inventory.cotton_cloth==before_cloth-3,"Build attaches the decoration and charges exactly eight fiber and three cloth")
	expect(world.blocked(WALL) and world.can_stand(Vector2(41.5,36.5)) and world.blocked(Vector2i(55,34)),"Passage stays open; wall and water collisions stay in effect")
	expect(not act("build",HOOK,KIND).ok and int(person.inventory.cotton_cloth)==before_cloth-3,"One mount does not overlap an existing one")
	expect(act("remove",WALL).message==Fixtures.REMOVE_MESSAGE,"Wall cannot be demolished before removing the fixture")
	expect(act("move_object",HOOK,World.key(NEXT)).message==Fixtures.SUPPORT_MESSAGE,"Moving to unsupported space is refused")
	world.add_player("lifebuoy-guest","訪客")
	var guest:Dictionary=world.state.players["lifebuoy-guest"]
	guest.x=42.5
	guest.y=37.5
	guest.inventory.wood=30
	expect(act("build",NEXT_WALL,"wall","lifebuoy-guest").ok,"A guest can construct their own wall next door")
	expect(not act("remove",HOOK,"","lifebuoy-guest").ok and act("move_object",HOOK,World.key(NEXT)).message==Fixtures.SUPPORT_MESSAGE,"Visitors cannot take the decoration and the owner cannot hang it on someone else's wall")
	expect(act("remove",NEXT_WALL,"","lifebuoy-guest").ok and act("build",NEXT_WALL,"wall@coast").ok,"Replace the neighboring fixture with the owner's wall")
	expect(act("move_object",HOOK,World.key(NEXT)).ok and fixture(NEXT) and not fixture(HOOK),"Move between valid wall segments")
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.camera=Vector2(41.7,36.0)*32-Vector2(root.size)/4.0
	await capture("mounted")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects[World.key(NEXT)].type==KIND,"Primary save restores the moved decoration")
	var orphan:=world.state.duplicate(true)
	orphan.objects.erase(World.key(NEXT_WALL))
	expect(not World.SAVE_SCHEMA.validate(orphan,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Validator rejects a fixture whose supporting wall is missing")
	var undo:=world.undo_summary(owner)
	expect(act(World.UNDO_ACTION,NEXT,str(undo.get("id",""))).ok and fixture(HOOK) and not fixture(NEXT),"Undo restores the original mount without copying the decoration")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(WALL,Vector2i(1,2)),"海邊牆面",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces.size()==2,"Blueprint captures the wall and its accessory")
	if design.ok:
		var destination:=WALL+Vector2i.LEFT
		var quote:=world.quote_blueprint(owner,design.blueprint,destination)
		expect(quote.ok and quote.cost.fiber==8 and quote.cost.cotton_cloth==3,"Blueprint builds against the matching wall orientation")
		if quote.ok:
			expect(world.apply_blueprint(owner,"c".repeat(32),design.blueprint,destination,0,quote.hash).ok and fixture(destination+Vector2i.DOWN),"Apply creates one new fixture on its copied wall")
	expect(act("remove",HOOK).ok and int(person.inventory.fiber)==before_fiber-8 and int(person.inventory.cotton_cloth)==before_cloth-3,"Removal repays exactly one recipe after blueprint construction")
	expect(act("remove",WALL).ok and not world.state.objects.has(World.key(WALL)),"Original wall is removable again")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WALL_LIFEBUOY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)
