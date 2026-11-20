extends SceneTree

const World=preload("res://scripts/world.gd")
const Oar=World.OAR_SIGN
const SITE:=Vector2i(40,34)
const NEXT:=Vector2i(41,34)
const TARGET:=Vector2i(46,30)
const WATER:=Vector2i(55,34)
var app
var world:World
var owner:String
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

func act(action:String,tile:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"oar-%d"%serial,action,tile,extra)

func marker(tile:Vector2i)->Vector2i:
	return Oar.cell(world.state.objects.get(World.key(tile),{}).get(Oar.FIELD))

func click_map(map:Control,tile:Vector2i)->void:
	var click:=InputEventMouseButton.new()
	click.position=map.oar_point(tile)
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	map._gui_input(click)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("oar-sign-preview","")
	var path:="user://wooden-oar-sign-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="wooden-oar-sign-owner"
	if app.session.host(0,"木槳路標測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	world.state.time=720.0
	var person:Dictionary=world.state.players[owner]
	person.x=40.5
	person.y=33.5
	person.inventory.merge({"wood":28,"hardwood":8},true)
	app.session._send_snapshot(1)
	app._build_menu()
	var shelf:Button
	for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if candidate.text=="海邊":shelf=candidate
	expect(shelf!=null,"The normal workshop offers the coastal shelf")
	if shelf!=null:
		shelf.pressed.emit()
		var recipe:=app.modal.find_child("BuildSlot_"+Oar.KIND+"_"+str(shelf.name).trim_prefix("BuildTab"),true,false) as Button
		expect(recipe!=null and recipe.is_visible_in_tree(),"The coastal shelf displays the oar sign")
		if recipe!=null:recipe.pressed.emit()
	var build:=app.modal.find_child("BuildPlace",true,false) as Button
	if build!=null:build.pressed.emit()
	expect(app.building==Oar.KIND,"Select the bespoke sign recipe")
	app._perform_build_action("build",SITE,Oar.KIND)
	expect(world.state.objects.get(World.key(SITE),{}).get("type")==Oar.KIND and not world.blocked(SITE) and person.inventory.wood==20 and person.inventory.hardwood==6,"Build a passable one-tile sign with the exact recipe")
	app._interact()
	var map:Control=app.map_view
	var confirm:=app.modal.find_child("OarTargetConfirm",true,false) as Button if map!=null else null
	expect(map!=null and confirm!=null and confirm.disabled,"Normal game interaction opens the map with an uncommitted target")
	if map!=null and confirm!=null:
		app._layout_preview()
		await process_frame
		if DisplayServer.get_name()=="headless":
			map.oar_base=Vector2.ZERO
			map.oar_cells=Rect2i(Vector2i.ZERO,World.SIZE)
			map.oar_scale=7.0
		else:await RenderingServer.frame_post_draw
		click_map(map,WATER)
		expect(confirm.disabled and map.oar_candidate==Oar.NO_CELL,"Clicking a river tile leaves the pin unset")
		click_map(map,TARGET)
		expect(not confirm.disabled and map.oar_candidate==TARGET and marker(SITE)==Oar.NO_CELL,"Selecting real map coordinates previews a point without writing it")
		expect(map.oar_pin_pulse==1.0,"An accepted destination starts one pulse")
		var key:=InputEventAction.new()
		key.action="ui_left"
		key.pressed=true
		map._gui_input(key)
		expect(map.oar_candidate==TARGET+Vector2i.LEFT,"Arrow keys move the provisional pin by one cell")
		click_map(map,TARGET)
		await capture("map-target")
		var settle_deadline:=Time.get_ticks_msec()+2000
		await create_timer(0.34).timeout
		while map.oar_pin_pulse!=0.0 and Time.get_ticks_msec()<settle_deadline:await process_frame
		expect(map.oar_pin_pulse==0.0,"The destination pin settles to its static state")
		map.reduced_motion=true
		click_map(map,TARGET+Vector2i.LEFT)
		expect(map.oar_pin_pulse==0.0,"Reduced motion still selects a cell without firing a pulse")
		click_map(map,TARGET)
		confirm.pressed.emit()
	else:
		expect(act(Oar.ACTION,SITE,World.key(TARGET)).ok,"Fallback exercises the world rules")
	expect(marker(SITE)==TARGET and Oar.direction_name(SITE,TARGET)=="東北" and Oar.direction(SITE,TARGET)==Vector2i(1,-1),"The saved pin gives the expected northeast arrow")
	expect(person.x==40.5 and person.y==33.5 and person.region=="home" and int(person.travel_epoch)==0,"The selection never moves or transports the player")
	await capture("island-arrow")
	expect(not act(Oar.ACTION,SITE,"80,80").ok and not act(Oar.ACTION,SITE,"046,30").ok and not act(Oar.ACTION,SITE,World.key(WATER)).ok and marker(SITE)==TARGET,"Server rejects invalid or water targets")
	world.add_player("oar-visitor","路標訪客")
	var guest:Dictionary=world.state.players["oar-visitor"]
	guest.x=41.5
	guest.y=33.5
	expect(not act(Oar.ACTION,SITE,"41,32","oar-visitor").ok and marker(SITE)==TARGET,"Visitors cannot overwrite somebody else's route hint")
	var original_id:String=app.session.own_id
	app.session.own_id="oar-visitor".sha256_text().left(16)
	app._map_menu(Callable(),"",SITE)
	expect(app.modal.find_child("OarTargetConfirm",true,false)==null and app.map_view.oar_focus==SITE and app.map_view.oar_world==null,"Visitor map is read-only")
	app._close_modal()
	app.session.own_id=original_id
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and Oar.cell(loaded.state.objects[World.key(SITE)][Oar.FIELD])==TARGET,"Primary save restores the selected target")
	var invalid:=world.state.duplicate(true)
	invalid.objects[World.key(SITE)][Oar.FIELD]="80,0"
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validation rejects out-of-map destinations")
	var copy:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(SITE,Vector2i.ONE),"木槳路標",World.BUILD,World.NAMES)
	expect(copy.ok and copy.blueprint.pieces.size()==1 and not copy.blueprint.pieces[0].has(Oar.FIELD),"Blueprint carries the sign without its location-specific pin")
	expect(act("move_object",SITE,World.key(NEXT)).ok and marker(NEXT)==TARGET and marker(SITE)==Oar.NO_CELL,"Moving the sign preserves the absolute destination")
	app.session._send_snapshot(1)
	app._map_menu(Callable(),"",NEXT)
	var clear:=app.modal.find_child("OarTargetClear",true,false) as Button
	expect(clear!=null and not clear.disabled,"The current map displays a working Clear control")
	if clear!=null:clear.pressed.emit()
	expect(marker(NEXT)==Oar.NO_CELL and int(person.travel_epoch)==0,"Clearing the sign removes only the destination")
	expect(act("remove",NEXT).ok and int(person.inventory.wood)==28 and int(person.inventory.hardwood)==8,"Remove refunds the recipe")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WOODEN_OAR_SIGN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)
