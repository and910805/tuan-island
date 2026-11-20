extends SceneTree

const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS
const Kind:=Goals.GARDEN_CHAIR
const Seat:=Goals.MASTER_BENCH_SEAT
const Sit:=Goals.MASTER_BENCH_SIT
const PLOT:=Vector2i(38,34)
const MOVED:=Vector2i(40,34)
const VISITOR:="copper-chair-guest"
var app
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func capture(image_name:String)->void:
	var directory:String=app.arg_value("chair-preview","")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(image_name+".png"))==OK,"Saved "+image_name)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	var path:="user://copper-garden-chair-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="copper-chair-owner"
	if app.session.host(0,"庭園椅驗收",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	var world:World=app.session.world
	world.state.time=540.0
	var owner:String=app.session.peers[1]
	var host:Dictionary=world.state.players[owner]
	host.x=38.5
	host.y=33.5
	host.inventory.copper_ingot=3
	host.inventory.wood=4
	world.add_player(VISITOR,"鄰居",Vector2(40.5,33.5))
	var guest:Dictionary=world.state.players[VISITOR]
	app.session._send_snapshot(1)
	app._build_menu()
	var greenhouse:Button
	for tab:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if tab.text=="星砂溫室":greenhouse=tab
	expect(greenhouse!=null,"The greenhouse has a workshop shelf")
	if greenhouse!=null:
		greenhouse.pressed.emit()
		var tile_name:="BuildSlot_"+Kind+"_"+str(greenhouse.name).trim_prefix("BuildTab")
		var slot:=app.modal.find_child(tile_name,true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The chair has a visible workshop tile")
		if slot!=null:slot.pressed.emit()
		app._layout_preview()
		await capture("garden-chair-workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"The chair recipe is ready with the stated materials")
	if place!=null:place.pressed.emit()
	expect(app.building==Kind and app.selected=="build","The workshop selects the real construction tool")
	app.session.perform("build",PLOT,Kind)
	var key:=World.key(PLOT)
	expect(world.state.objects.get(key,{}).get("type")==Kind and world.blocked(PLOT),"Construction occupies one solid tile")
	expect(host.inventory.copper_ingot==0 and host.inventory.wood==0,"The recipe consumes exactly 3 copper and 4 wood")
	app.view.zoom=2.0
	app.view.show_target=false
	app.view.camera=Vector2(39,33.5)*32-Vector2(root.size)/4.0
	app.view.queue_redraw()
	await capture("garden-chair-placed")
	app._interact()
	expect(host.get(Seat)=={"cell":key,"side":0},"The real interact control lets the host sit")
	expect(not world.act(VISITOR,"chair-in-use",Sit,PLOT).ok and not guest.has(Seat),"A visitor cannot take an occupied garden chair")
	var loaded:=World.new()
	var valid_main:=loaded.load_world(path) and not loaded.recovered_from_backup
	var saved_pose:Dictionary=loaded.state.players.get(owner,{}).get(Seat,{})
	expect(valid_main and saved_pose.get("cell")==key and int(saved_pose.get("side",-1))==0,"The primary save reloads the occupied chair")
	var corrupt:=loaded.state.duplicate(true)
	corrupt.players[owner][Seat].side=1
	expect(not World.SAVE_SCHEMA.validate(corrupt,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The save rejects a second seat index on a one-seat chair")
	corrupt=loaded.state.duplicate(true)
	corrupt.players[VISITOR][Seat]=host[Seat].duplicate()
	expect(not World.SAVE_SCHEMA.validate(corrupt,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The save rejects two occupants of the same garden chair")
	await capture("garden-chair-seated")
	if DisplayServer.get_name()!="headless":
		app.set_process(false)
		app.view.set_process(false)
		app.view.hide_interaction_prompt=true
		var north:=await seat_pixels()
		var visible_player:String=app.session.own_id
		var previous_position:Vector2=app.view.display_positions.get(visible_player,Vector2(host.x,host.y))
		app.view.display_positions[visible_player]=Vector2(host.x,35.5)
		var south:=await seat_pixels()
		expect(north.get_data()==south.get_data(),"The seated sprite stays in front of the chair when approaching from either row")
		app.view.display_positions[visible_player]=previous_position
		app.view.hide_interaction_prompt=false
	app._interact()
	expect(not host.has(Seat),"Interacting again stands up")
	expect(world.act(VISITOR,"chair-available",Sit,PLOT).ok,"A friend may sit once the seat is available")
	world.move_player(VISITOR,Vector2.DOWN,0.03)
	expect(not guest.has(Seat),"Movement releases the visitor's seat")
	expect(world.act(VISITOR,"chair-before-disconnect",Sit,PLOT).ok,"The visitor may sit again")
	world.active_tokens.erase(VISITOR)
	app._interact()
	expect(host.has(Seat) and not guest.has(Seat),"An inactive player's previous pose does not block a returning player")
	app.session.perform("move_object",PLOT,World.key(MOVED))
	expect(not host.has(Seat) and not world.state.objects.has(key) and world.state.objects.get(World.key(MOVED),{}).get("type")==Kind,"Moving the chair releases its occupant and preserves the object")
	expect(host.inventory.copper_ingot==0 and host.inventory.wood==0,"Moving takes no extra materials")
	app.session.perform("remove",MOVED)
	expect(not world.state.objects.has(World.key(MOVED)) and host.inventory.copper_ingot==3 and host.inventory.wood==4,"Removing refunds exactly one recipe")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COPPER_GARDEN_CHAIR_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func seat_pixels()->Image:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var foot:Vector2=app.view.screen(Vector2(PLOT)+Vector2(0.5,0.76))*app.view.view_zoom()
	return root.get_texture().get_image().get_region(Rect2i(Vector2i(foot)+Vector2i(-25,-75),Vector2i(50,88)))
