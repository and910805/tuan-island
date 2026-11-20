extends SceneTree

const World=preload("res://scripts/world.gd")
const Rooms=preload("res://scripts/house_rooms.gd")
const KIND:="garden_basin"
const PLOT:=Vector2i(38,34)
const MOVED:=Vector2i(37,34)
var app
var world:World
var scope:String
var directory:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func capture(name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Captured "+name)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	directory=app.arg_value("basin-preview","")
	root.size=Vector2i(1024,640)
	var path:="user://basin-test-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="garden-basin-qa"
	if app.session.host(0,"園藝測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	scope=app.session.peers[1]
	var player:Dictionary=world.state.players[scope]
	player.x=World.SPAWN.x
	player.y=World.SPAWN.y
	player.inventory.clay=8
	player.inventory.stone=4
	app.session._send_snapshot(1)
	var sprite:=preload("res://assets/ui-life/garden-basin.png")
	check(sprite.get_size()==Vector2(32,32) and sprite.get_image().detect_alpha()!=Image.ALPHA_NONE,"Game uses a transparent 32px texture")
	app._build_menu()
	var style:Button
	for button:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if button.text=="星砂溫室":style=button
	check(style!=null,"Greenhouse furniture has a visible workshop page")
	if style!=null:style.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_garden_basin_"+str(style.name).trim_prefix("BuildTab"),true,false) as Button if style!=null else null
	check(slot!=null and slot.is_visible_in_tree(),"Basin selectable on the greenhouse shelf")
	if slot!=null:slot.pressed.emit()
	app._layout_preview()
	await process_frame
	await process_frame
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	check(place!=null and not place.disabled,"Real workshop displays the new recipe")
	await capture("garden-basin-workshop")
	root.size=Vector2i(1280,800)
	app._layout_preview()
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()) and app.modal.get_global_rect().encloses(place.get_global_rect()),"Greenhouse workshop fits a 1280×800 viewport")
	await capture("garden-basin-workshop-1280")
	if place!=null and not place.disabled:place.pressed.emit()
	check(app.selected=="build" and app.building==KIND,"Choosing the water basin selects ordinary construction")
	var id:=World.key(PLOT)
	var guest:="basin-test-guest"
	world.add_player(guest,"鄰居",Vector2(PLOT)+Vector2(0.5,0.5))
	check(not world.act(scope,"occupied-basin","build",PLOT,KIND).ok and player.inventory.clay==8,"Building avoids occupied plots without taking materials")
	world.state.players[guest].x=40.5
	world.state.players[guest].y=36.5
	app.session.perform("build",PLOT,app.building)
	check(world.state.objects.get(id,{}).get("type")==KIND and player.inventory.clay==0 and player.inventory.stone==0,"Build consumes exactly 8 clay and 4 stone")
	check(world.blocked(PLOT) and not world.water(PLOT) and Rooms.SOLID_OBJECTS.has(KIND),"A basin blocks a tile and does not turn into map water")
	check(not world.act(scope,"basin-fish","fish_start",PLOT).ok and player.get("fishing",{}).is_empty(),"The decoration is never a fishing spot")
	check(not world.act(guest,"guest-remove-basin","remove",PLOT).ok and world.state.objects.has(id),"Unrelated visitor cannot dismantle the basin")
	app.view.zoom=2.0
	app.view.show_target=false
	app.view.camera=Vector2(38.5,34.5)*32-Vector2(root.size)/4.0
	app.view.queue_redraw()
	await capture("garden-basin-placed")
	var loaded:=World.new()
	check(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(id,{}).get("type")==KIND,"Existing save format reloads the basin from the primary file")
	var destination:=World.key(MOVED)
	app.session.perform("move_object",PLOT,destination)
	check(not world.state.objects.has(id) and world.state.objects.get(destination,{}).get("type")==KIND and player.inventory.clay==0,"Move transfers the basin without a second crafting payment")
	app.session.perform("remove",MOVED)
	check(not world.state.objects.has(destination) and player.inventory.clay==8 and player.inventory.stone==4,"Dismantling restores the recipe exactly once")
	app.session.shutdown()
	for suffix:String in ["", ".bak", ".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("GARDEN_BASIN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
