extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.AQUARIUM
const FISH:=Industry.AQUARIUM_FISH
const PLOT:=Vector2i(38,34)
const FAR:=PLOT+Vector2i.RIGHT
const ROTATED:=Vector2i(41,34)
const MOVED:=Vector2i(39,35)
const RIVER:=Vector2i(55,34)
const GUEST:="aquarium-guest"
var app
var world:World
var owner:String
var path:String
var directory:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func act(action:String,cell:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"aquarium-action-%d"%serial,action,cell,extra)

func count(at:Vector2i)->int:
	return int(world.state.objects.get(World.key(at),{}).get("items",{}).get(FISH,0))

func set_pos(person:Dictionary,at:Vector2)->void:
	person.x=at.x
	person.y=at.y

func capture(image_name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.28).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(image_name+".png"))==OK,"Saved "+image_name)

func tank_pixels(phase:float)->Image:
	app.view.elapsed=phase
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var anchor:Vector2=app.view.screen(Vector2(PLOT))*app.view.view_zoom()
	return root.get_texture().get_image().get_region(Rect2i(Vector2i(anchor)+Vector2i(-6,-34),Vector2i(140,104)))

func verify_swim()->void:
	if DisplayServer.get_name()=="headless":return
	app.set_process(false)
	app.view.set_process(false)
	app.view.hide_interaction_prompt=true
	app.view.reduced_motion=false
	var right:=await tank_pixels(0.0)
	var left:=await tank_pixels(1.0)
	expect(right.get_data()!=left.get_data(),"Normal mode renders visible swimming across the tank")
	app.view.reduced_motion=true
	var still:=await tank_pixels(0.0)
	var still_later:=await tank_pixels(1.0)
	expect(still.get_data()==still_later.get_data(),"Reduced motion displays a stable fish")
	app.view.reduced_motion=false
	app.view.photograph_mode=true
	var photo:=await tank_pixels(1.0)
	expect(photo.get_data()==still.get_data(),"Photo mode stills the fish in the same place")
	app.view.photograph_mode=false
	if not directory.is_empty():
		var saved:=true
		for step in 24:
			var frame:=await tank_pixels(float(step)*TAU/(24.0*1.6))
			saved=frame.save_png(directory.path_join("swim-%02d.png"%step))==OK and saved
		expect(saved,"Saved the actual game frames of one swimming cycle")
	app.view.hide_interaction_prompt=false
	app.view.set_process(true)
	app.set_process(true)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	directory=app.arg_value("aquarium-preview","")
	path="user://small-aquarium-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="aquarium-owner"
	if app.session.host(0,"魚缸測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	world.state.time=1020.0
	set_pos(person,Vector2(54.5,34.5))
	for index in 3:
		expect(act("fish_start",RIVER).ok,"A real cast by the river")
		world.step(3.15,true)
		expect(act("fish_catch",RIVER).ok,"The fish is reeled in")
	expect(person.inventory.get(FISH)==1 and person.collection.fish.has(FISH),"Real fishing puts one redtail carp in the bag and the almanac")
	set_pos(person,World.SPAWN)
	person.inventory.glass=16
	person.inventory.copper_ingot=4
	world.add_player(GUEST,"朋友",Vector2(40.5,33.5))
	app.session._send_snapshot(1)
	app._build_menu()
	var greenhouse:Button
	for button:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if button.text=="星砂溫室":greenhouse=button
	expect(greenhouse!=null,"The aquarium belongs to the greenhouse shelf")
	if greenhouse!=null:
		greenhouse.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(greenhouse.name).trim_prefix("BuildTab"),true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The aquarium has a visible icon and recipe")
		if slot!=null:slot.pressed.emit()
	app._layout_preview()
	await capture("aquarium-workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"Its real workshop recipe is available")
	if place!=null:place.pressed.emit()
	app.session.perform("build",PLOT,KIND)
	expect(world.blocked(PLOT) and world.blocked(FAR) and World.station_anchor(world.state.objects,FAR)==PLOT,"A two-tile aquarium has a single tank")
	expect(person.inventory.glass==8 and person.inventory.copper_ingot==2,"Only the listed materials are charged")
	expect(not act("fish_start",PLOT).ok,"The aquarium isn't a fishing spot")
	app.view.show_target=false
	app._interact()
	var stock:=app.modal.find_child("AquariumStock",true,false) as Button if app.modal!=null else null
	expect(stock!=null and not stock.disabled,"A catch can be stocked using the second tile's normal interaction")
	if stock!=null:stock.pressed.emit()
	expect(count(PLOT)==1 and int(person.inventory.get(FISH,0))==0,"Stocking transfers the single catch into the aquarium")
	expect(not act(Industry.AQUARIUM_STOCK,FAR).ok,"A full aquarium rejects another fish")
	expect(not act(Industry.AQUARIUM_TAKE,FAR,"",GUEST).ok and not act("withdraw",FAR,FISH,GUEST).ok,"A visitor and generic chest actions cannot take the fish")
	expect(not act("remove",FAR).ok,"A stocked tank cannot be dismantled")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(2,1)),"小型觀賞魚缸",World.BUILD,World.NAMES)
	expect(design.ok,"An occupied tank can supply a structural blueprint")
	if design.ok:
		var quote:=world.quote_blueprint(owner,design.blueprint,ROTATED,1)
		if quote.ok:
			var built:=world.apply_blueprint(owner,"f".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			expect(built.ok and Industry.is_vertical(world.state.objects.get(World.key(ROTATED),{})) and count(ROTATED)==0,"Rotating a blueprint creates an empty tank without duplicating a fish")
		else:expect(false,"The rotated blueprint fits in the other area")
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.camera=Vector2(39.5,34.5)*32-Vector2(root.size)/4.0
	app.view.queue_redraw()
	await capture("aquarium-placed")
	await verify_swim()
	for day in 3:world.step(World.WEATHER.DAY_SECONDS,true)
	expect(count(PLOT)==1 and int(person.inventory.get(FISH,0))==0,"Three world days neither remove nor multiply the fish")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and int(loaded.state.objects.get(World.key(PLOT),{}).get("items",{}).get(FISH,0))==1,"The original fish persists across save reload")
	for malformed in [{FISH:2},{"carp":1},{FISH:1,"carp":1}]:
		var bad:=loaded.state.duplicate(true)
		if bad.objects.has(World.key(PLOT)):
			bad.objects[World.key(PLOT)].items=malformed
			expect(not World.SAVE_SCHEMA.validate(bad,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The save rejects invalid aquarium contents")
	app.session.peers[1]=GUEST
	app.session._send_snapshot(1)
	app.LifeTasks.small_aquarium(app,FAR,app.session.snapshot.objects[World.key(PLOT)])
	expect(app.modal.find_child("AquariumTake",true,false)==null,"Visitors can watch without a take button")
	app._close_modal()
	app.session.peers[1]=owner
	app.session._send_snapshot(1)
	expect(act("move_object",FAR,World.key(MOVED)).ok and count(MOVED)==1 and not world.state.objects.has(World.key(PLOT)),"Moving a stocked aquarium keeps its fish")
	var move_id:String=world.state.construction.last.get(owner,{}).get("id","")
	expect(not move_id.is_empty(),"Moving the aquarium creates a construction receipt")
	set_pos(person,Vector2(39.5,34.5))
	app.session._send_snapshot(1)
	app._interact()
	var take:=app.modal.find_child("AquariumTake",true,false) as Button if app.modal!=null else null
	expect(take!=null,"The filled aquarium presents the owner's take control")
	await capture("aquarium-panel")
	if take!=null:take.pressed.emit()
	expect(count(MOVED)==0 and int(person.inventory.get(FISH,0))==1,"Taking returns the same one fish to the bag")
	expect(not act(World.UNDO_ACTION,MOVED,move_id).ok and count(MOVED)==0,"Undo after taking cannot recreate the fish")
	expect(act("remove",MOVED).ok and person.inventory.glass==8 and person.inventory.copper_ingot==2,"The empty aquarium can be dismantled and refunds its recipe")
	expect(act(Industry.AQUARIUM_STOCK,ROTATED).ok and count(ROTATED)==1,"The recovered fish can be stocked in a rotated aquarium")
	app.session._send_snapshot(1)
	await capture("aquarium-vertical")
	expect(act(Industry.AQUARIUM_TAKE,ROTATED+Vector2i.DOWN).ok and int(person.inventory.get(FISH,0))==1,"The far tile of the rotated tank returns the original fish")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SMALL_AQUARIUM_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
