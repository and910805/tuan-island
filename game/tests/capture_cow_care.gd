extends SceneTree
const World=preload("res://scripts/world.gd")
const Almanac=preload("res://scripts/life_ui_almanac.gd")
var app
var directory:=""
var checks:=0
var failures:=0
var frames:Array=[]
func _initialize()->void:
	if DisplayServer.get_name()=="headless":
		print("COW_CARE_NATIVE requires native rendering")
		quit(1)
		return
	run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func shot(name:String)->void:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
	frames.append({"file":name+".png","offset":var_to_str(app.view.cow_follow.offset(false)),"target":var_to_str(app.view.cow_follow.destination),"legs":app.view.cow_follow.walking_frame(false)})
func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800) if app.arg_value("qa-size","")=="1280" else Vector2i(1024,640)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="cow-care-native"
	expect(app.session.host(0,"奶糖牛散步",directory.path_join("world-%d.json"%Time.get_ticks_usec()))==OK,"Host isolated cow care world")
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	app.set_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	world.state.picnic=true
	person.x=48.5
	person.y=37.5
	if app.arg_value("qa-product","")=="true":
		world.state.livestock.cow=World.LIVESTOCK.fresh()
		world.state.livestock.cow.ready=1 # Visual-only, explicitly unearned pending milk fixture.
	var milk_before:int=world.state.livestock.get("cow",{}).get("ready",0)
	expect(world.can_stand(Vector2(person.x,person.y)),"Real legal ranch standing position")
	app.session._send_snapshot(1)
	preload("res://scripts/wangan_opening_ui.gd").dismiss(app)
	app.view.set_process(false)
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	Almanac.livestock_menu(app,"cow")
	app._layout_preview()
	await process_frame
	await shot("cow-card")
	var button:=app.modal.find_child("LivestockPet",true,false) as Button
	expect(button!=null and not button.disabled and app.modal.find_child("CowFollowStatus",true,false)!=null,"Existing care card exposes pet and follow explanation")
	expect(app.modal.get_global_rect().encloses(button.get_global_rect()),"Pet button is inside visible card bounds")
	var bag:Dictionary=person.inventory.duplicate(true)
	button.pressed.emit()
	app.session._send_snapshot(1)
	expect(World.COW_CARE.active_actor(world.state)==token and world.state.livestock.cow.bond==1,"Actual UI care binds shared actor and one bond")
	app._refresh_hud()
	app._layout_preview()
	var camera:Vector2=app.view.camera
	var stable:Dictionary=world.state.duplicate(true)
	var poses:Dictionary={}
	var quiet:bool=app.view.reduced_motion or app.view.photograph_mode
	for frame in 24:
		app.view.elapsed+=0.06
		app.view.cow_follow.advance(0.06)
		poses[app.view.cow_follow.offset(quiet).round()]=true
		await shot("follow_%02d"%frame)
		expect(stable==world.state and camera==app.view.camera,"Following never changes world or camera")
	expect(poses.size()==1 if quiet else poses.size()>10,"Quiet/photo use same destination without travel, normal mode has many walking positions")
	expect(person.inventory==bag and world.state.livestock.cow.ready==milk_before,"No feed, milk or material change from pet")
	var old_y:float=person.y
	world.move_player(token,Vector2.DOWN,0.1)
	expect(person.y>old_y,"Original collision-checked movement still works")
	app.session._send_snapshot(1)
	app.view._process(0.15)
	camera=app.view.camera
	stable=world.state.duplicate(true)
	expect(app.view.cow_follow.destination.y>36.65,"Cow updates destination after real player movement")
	for frame in 24:
		app.view.elapsed+=0.06
		app.view.cow_follow.advance(0.06)
		await shot("walking_%02d"%frame)
		expect(stable==world.state and camera==app.view.camera,"Follower art leaves moved world and camera stable")
	expect(world.step(World.COW_CARE.SECONDS+0.1,true),"Advance authoritative care timeout")
	app.session._send_snapshot(1)
	stable=world.state.duplicate(true)
	for frame in 40:
		app.view.elapsed+=0.06
		app.view.cow_follow.advance(0.06)
		await shot("return_%02d"%frame)
		expect(stable==world.state and camera==app.view.camera,"Return leaves world and camera fixed")
	expect(app.view.cow_follow.offset(false).length()<0.1,"Cow returns to original station")
	var file:=FileAccess.open(directory.path_join("sequence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"quiet":quiet,"frames":frames}))
	app.session.shutdown()
	app.queue_free()
	await process_frame
	print("COW_CARE_NATIVE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
