extends SceneTree
const World=preload("res://scripts/world.gd")
var app
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1024,640)
	var directory:String=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="rapid-farm-animation-qa"
	assert(app.session.host(0,"連續農事測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	person.x=38.5
	person.y=35.5
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	app.view.set_process(false)
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	var camera_before:Vector2=app.view.camera
	var ground_before:Dictionary=world.state.ground.duplicate(true)
	var started:float=app.view.elapsed
	var cells:=[Vector2i(38,34),Vector2i(39,34),Vector2i(40,34)]
	var frames:Array=[]
	var sequence:=0
	for frame in 25:
		app.view.elapsed=started+frame*0.04
		if frame in [0,4,8]:
			app.session.rates[1]=[]
			sequence+=1
			app.session._action(1,sequence,"hoe",cells[sequence-1],"")
			app.session._send_snapshot(1)
			expect(world.state.crops.has(World.key(cells[sequence-1])),"Confirmed hoe cell %d"%sequence)
		app.view.tool_draw_stats={"held":0,"particles":0,"lunge":0,"angles":{}}
		app.view.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var filename:="%02d.png"%frame
		expect(root.get_texture().get_image().save_png(directory.path_join(filename))==OK,"Capture "+filename)
		frames.append({"frame":frame,"particles":app.view.tool_draw_stats.particles})
		if frame==7 and app.arg_value("qa-expect-tail","")=="true":
			expect(app.view.tool_draw_stats.particles>0,"First confirmed impact survives the next rapid click")
		if app.view.reduced_motion or app.view.photograph_mode:
			expect(app.view.tool_draw_stats.particles==0,"Still mode suppresses current and interrupted particles")
		if frame==24:expect(app.view.tool_draw_stats.particles==0,"All impact particles finish without another snapshot")
	expect(app.view.camera==camera_before and world.state.ground==ground_before,"Rapid actions preserve camera and base terrain")
	var out:=FileAccess.open(directory.path_join("frames.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify(frames,"\t"))
	print("RAPID_FARM checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
