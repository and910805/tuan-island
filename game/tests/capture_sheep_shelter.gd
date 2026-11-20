extends SceneTree
const World=preload("res://scripts/world.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const Goals=World.RESIDENT_GOALS
var app
var directory:=""
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func shot(name:String)->void:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800) if app.arg_value("qa-size","")=="1280" else Vector2i(1024,640)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="sheep-shelter-native-qa"
	expect(app.session.host(0,"小羊雨棚",directory.path_join("world.json"))==OK,"Host isolated native world")
	await create_timer(0.25).timeout
	app.session.set_physics_process(false)
	app.set_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	# Fixtures: picnic, six friendship points, legal standing position and day
	# boundary. Build costs come from normal starter inventory, not granted stock.
	world.state.picnic=true
	world.state.time=2880.0-0.25
	person.bonds={"mianmian":{"points":6,"talk_day":-1,"gift_day":-1}}
	person.x=50.5
	person.y=37.5
	expect(world.can_stand(Vector2(person.x,person.y)),"Fixture uses a truly passable standing cell")
	app.session._send_snapshot(1)
	preload("res://scripts/wangan_opening_ui.gd").dismiss(app)
	app.view.set_process(false)
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	var wood:int=person.inventory.wood
	var fiber:int=person.inventory.fiber
	for part in ["shelter","mat"]:
		Tasks.sheep_corner(app)
		var button:=app.modal.find_child("SheepComfort_"+part,true,false) as Button
		expect(button!=null and not button.disabled,"Existing construction button is available: "+part)
		if button!=null:button.pressed.emit()
		app.session._send_snapshot(1)
	app._close_modal()
	expect(int(person.inventory.wood)==wood-4 and int(person.inventory.fiber)==fiber-3,"Real shelter and mat buttons charge original costs")
	expect(app.session.snapshot.sheep_comfort_fixtures==3,"Built fixtures reach shared snapshot")
	if app.arg_value("qa-product","")=="true":
		# Explicit visual-only production fixture; not an earned wool reward.
		world.state.livestock.sheep=World.LIVESTOCK.fresh()
		world.state.livestock.sheep.ready=1
		app.session._send_snapshot(1)
	app.toast.hide()
	app.view.hide_interaction_prompt=true
	app.view.elapsed+=3.0
	app._process(0.0)
	app._refresh_hud()
	await shot("cloudy")
	var camera:Vector2=app.view.camera
	expect(world.step(0.5,true),"Advance actual world step across rainy midnight")
	app.session._send_snapshot(1)
	app._process(0.0)
	app._refresh_hud()
	var quiet:bool=app.view.reduced_motion or app.view.photograph_mode
	var started:float=app.view.elapsed
	var saved:Dictionary=world.state.duplicate(true)
	var offsets:={}
	for frame in 27:
		app.view.elapsed=started+float(frame)*0.1
		offsets[app.view.sheep_shelter.offset(app.view.elapsed,quiet)]=true
		await shot("rain_%02d"%frame)
		expect(world.state==saved and app.view.camera==camera,"Rain presentation keeps full world and camera fixed")
	expect(offsets.size()==1 if quiet else offsets.size()>10,"Rain walk is animated only with normal motion")
	expect(app.view.sheep_shelter.offset(app.view.elapsed,quiet)==Vector2(32,0),"Sheep reaches the existing canopy")
	expect(app.view.rain_sheltered(Vector2i(51,35)),"Rain effects respect the constructed canopy")
	# A live weather transition back to sunny; only test world time is preset.
	world.state.time=4320.25
	app.session._send_snapshot(1)
	app._process(0.0)
	app._refresh_hud()
	started=app.view.elapsed
	saved=world.state.duplicate(true)
	for frame in 27:
		app.view.elapsed=started+float(frame)*0.1
		await shot("sun_%02d"%frame)
		expect(world.state==saved and app.view.camera==camera,"Return presentation keeps full world and camera fixed")
	expect(app.view.sheep_shelter.offset(app.view.elapsed,quiet)==Vector2.ZERO,"Sheep returns after the rain")
	Tasks.sheep_corner(app)
	app._layout_preview()
	await create_timer(0.3).timeout
	await shot("corner_ui")
	app._close_modal()
	app.session.shutdown()
	print("SHEEP_SHELTER_NATIVE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
