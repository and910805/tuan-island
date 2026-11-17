extends SceneTree
const World=preload("res://scripts/world.gd")
var app
var directory:=""
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func shot(name:String)->void:
	app.toast.hide()
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1024,640)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="water-motion-qa"
	assert(app.session.host(0,"供水動畫測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	person.x=52.5
	person.y=25.5
	# Isolated visual fixture; actions and water production use the real Session/World.
	for spec in [["53,24","water_pump",{"enabled":false}],["53,25","water_pipe",{}],["53,26","water_tank",{"water":0}],["52,26","sprinkler",{"water":0,"enabled":true,"next_water":0,"last_water":-1}]]:
		world.state.removed[spec[0]]=true
		var device:Dictionary={"type":spec[1],"owner":token,"items":{}}
		device.merge(spec[2],true)
		world.state.objects[spec[0]]=device
	world.state.crops["51,26"]={"owner":token,"kind":"radish","growth":0,"wet":false,"remaining":1}
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	app.view.set_process(false)
	app.set_process(false)
	app.toast.hide()
	app.view.hide_interaction_prompt=true
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	await shot("empty_stopped")
	app.view.elapsed+=0.63
	await shot("empty_stopped_later")
	app.session.rates[1]=[]
	app.session._action(1,1,"toggle_pump",Vector2i(53,24),"")
	expect(world.state.objects["53,24"].enabled,"Real action enables river pump")
	expect(world.step(8.1,true),"Advance real supply interval")
	expect(world.state.crops["51,26"].wet,"Network waters dry crop")
	expect(int(world.state.objects["52,26"].water)==7,"Eight units minus one watering")
	# A second interval fills the tank once the sprinkler reservoir is filled.
	expect(world.step(8.1,true),"Second real supply interval")
	expect(int(world.state.objects["53,26"].water)>0,"Tank contains authoritative stored water")
	app.session._send_snapshot(1)
	await process_frame
	var before:Dictionary=world.state.duplicate(true)
	var camera:Vector2=app.view.camera
	for frame in 20:
		app.view.elapsed=frame*0.09
		await shot("running_%02d"%frame)
	expect(before==world.state,"Rendering does not change water, crops, time or inventory")
	expect(camera==app.view.camera,"Water animation cannot move the map")
	app.session.rates[1]=[]
	app.session._action(1,2,"toggle_pump",Vector2i(53,24),"")
	expect(not world.state.objects["53,24"].enabled,"Real action stops pump")
	app.session._send_snapshot(1)
	app.view.elapsed=0.0
	await shot("stopped_00")
	app.view.elapsed=0.63
	await shot("stopped_01")
	print("WATER_MOTION checks=%d failures=%d"%[checks,failures])
	app.session.shutdown()
	quit(int(failures>0))
