extends SceneTree
const Idle=preload("res://scripts/resident_idle.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
var app
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func run()->void:
	for style in Idle.STYLES:
		var poses:={}
		for tick in 100:
			var time:=tick/10.0
			poses[Idle.facing(style,Vector2i.DOWN,Vector2.ZERO,Vector2(200,0),true,time,false)]=true
			check(Idle.facing(style,Vector2i.DOWN,Vector2.ZERO,Vector2(20,0),true,time,true)==Vector2i.DOWN,"Quiet mode preserves resident rest pose")
		check(poses.size()==3,"Resident sometimes looks both ways, then returns: "+style)
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			check(Idle.facing(style,Vector2i.DOWN,Vector2.ZERO,Vector2(direction)*50,true,6.3,false)==direction,"Nearby visitor takes priority over idle glance")
	check(Idle.facing("farmer",Vector2i.UP,Vector2.ZERO,Vector2(30,0),true,6.1,false)==Vector2i.UP,"Player facing is never changed")
	check(Idle.facing("aru",Vector2i.DOWN,Vector2.ZERO,Vector2.ZERO,true,6.1,false)==Vector2i.DOWN,"Overlapping visitor does not produce invalid facing")
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1280,800)
	var directory:String=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="resident-idle-isolated-qa"
	check(app.session.host(0,"居民動態測試",directory.path_join("world.json"))==OK,"Isolated host starts")
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var w=app.session.world
	var token:String=app.session.peers[1]
	var cell:Vector2i=World.Village.resident_cell(w.state,"aru")
	var person:Dictionary=w.state.players[token]
	person.x=cell.x+3.5
	person.y=cell.y+0.7
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	app.view.set_process(false)
	var saved:Dictionary=w.state.duplicate(true)
	var camera:Vector2=app.view.camera
	var hashes:={}
	for mode in ["normal","reduced","photo"]:
		app.view.reduced_motion=mode=="reduced"
		app.view.photograph_mode=mode=="photo"
		var samples:={}
		for index in 3:
			app.view.elapsed=[0.0,6.1,7.5][index]
			app.view.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var frame:=root.get_texture().get_image()
			check(frame.save_png(directory.path_join("%s_%d.png"%[mode,index]))==OK,"Native frame saved")
			var foot:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.7))*app.view.view_zoom()
			var crop:=Rect2i(Vector2i(foot-Vector2(24,44)*app.view.view_zoom()),Vector2i(48,48)*int(app.view.view_zoom()))
			frame.get_region(crop).save_png(directory.path_join("%s_%d_close.png"%[mode,index]))
			samples[hash(frame.get_region(crop).get_data())]=true
			check(w.state==saved and app.view.camera==camera,"Resident animation changes neither world nor camera")
		hashes[mode]=samples.size()
		check(samples.size()==3 if mode=="normal" else samples.size()==1,"Only normal mode changes resident PNG frames: "+mode)
	app.view.photograph_mode=false
	app.view.reduced_motion=false
	var near_samples:={}
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var position:=Vector2(cell)+Vector2(0.5,0.7)+Vector2(direction)*1.8
		person.x=position.x
		person.y=position.y
		app.session._send_snapshot(1)
		# Fixture relocation while interpolation is stopped for deterministic captures.
		app.view.display_positions[app.session.own_id]=position
		var camera_before:Vector2=app.view.camera
		var state_before:Dictionary=w.state.duplicate(true)
		app.view.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var frame:=root.get_texture().get_image()
		check(frame.save_png(directory.path_join("near_%s_%s.png"%[direction.x,direction.y]))==OK,"Nearby visitor native pose captured")
		var foot:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.7))*app.view.view_zoom()
		var crop:=Rect2i(Vector2i(foot-Vector2(24,44)*app.view.view_zoom()),Vector2i(48,48)*int(app.view.view_zoom()))
		frame.get_region(crop).save_png(directory.path_join("near_%s_%s_close.png"%[direction.x,direction.y]))
		near_samples[hash(frame.get_region(crop).get_data())]=true
		check(w.state==state_before,"Turning toward visitor cannot change saved world data")
		check(app.view.camera==camera_before,"Drawing a visitor-facing pose cannot move the camera")
	check(near_samples.size()==4,"Native resident has four different visitor-facing poses")
	person.x=cell.x+0.5
	person.y=cell.y+1.7
	app.session._send_snapshot(1)
	await process_frame
	app._interact()
	await process_frame
	check(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout","")=="resident_dialogue","Original interaction still opens resident dialogue")
	print("RESIDENT_IDLE_CAPTURE checks=%d failures=%d pixels=%s"%[checks,failures,str(hashes)])
	quit(int(failures>0))
