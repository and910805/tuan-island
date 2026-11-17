extends SceneTree
const World=preload("res://scripts/world.gd")
const Art=preload("res://scripts/industry_art.gd")
var app
var directory:=""
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func shot(name:String)->void:
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
	app.session.profile.token="processing-motion-qa"
	assert(app.session.host(0,"林業加工測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	person.inventory.wood=40
	person.x=41.5
	person.y=36.5
	var specs:=[[Vector2i(40,35),"sawmill","plank"],[Vector2i(42,35),"charcoal_kiln","charcoal"]]
	var sequence:=0
	for spec in specs:
		var cell:Vector2i=spec[0]
		var key:=World.key(cell)
		world.state.removed[key]=true
		world.state.objects[key]={"type":spec[1],"owner":token,"items":{},"input_wood":0}
		for batch in 2:
			app.session.rates[1]=[]
			sequence+=1
			app.session._action(1,sequence,"queue_processing",cell,spec[2])
		expect(Art.processing_active(world.state.objects[key],float(world.state.time)),"Real queued station is working")
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	app.view.set_process(false)
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	var camera:Vector2=app.view.camera
	var original:Dictionary=world.state.objects.duplicate(true)
	for frame in 20:
		app.view.elapsed+=0.06
		await shot("working_%02d"%frame)
	expect(original==world.state.objects,"Animation never advances or mutates processing jobs")
	expect(camera==app.view.camera,"Processing animation leaves camera fixed")
	expect(world.step(16.2,true),"Fast-forward to ready plus working")
	app.session._send_snapshot(1)
	await shot("ready_and_working")
	for spec in specs:
		var device:Dictionary=app.session.snapshot.objects[World.key(spec[0])]
		expect(Art.processing_active(device,float(world.state.time)) and Art.finished_output(device,spec[1],float(world.state.time))==spec[2],"Output stays visible alongside next working batch")
	expect(world.step(20.0,true),"Fast-forward remaining jobs")
	app.session._send_snapshot(1)
	await shot("all_ready")
	if app.arg_value("qa-finish","")=="true":
		# Real second-batch completion just above; do not inject presentation events.
		var stable:Dictionary=world.state.duplicate(true)
		var quiet:bool=app.view.reduced_motion or app.view.photograph_mode
		for spec in specs:
			var key:=World.key(spec[0])
			expect(app.view.processing_finish_feedback.age(key,app.view.data.objects[key],app.view.elapsed,quiet)>=0.0 if not quiet else app.view.processing_finish_feedback.age(key,app.view.data.objects[key],app.view.elapsed,quiet)<0.0,"Actual snapshot controls finish feedback")
		for frame in 18:
			await shot("finished_%02d"%frame)
			expect(stable==world.state,"Rendering never changes world state")
			expect(camera==app.view.camera,"Finish keeps camera anchored")
			app.view.elapsed+=0.05
		for spec in specs:
			var key:=World.key(spec[0])
			expect(app.view.processing_finish_feedback.age(key,app.view.data.objects[key],app.view.elapsed)<0.0,"Finish ends without another world tick")
	app.view.elapsed+=0.6
	await shot("all_ready_later")
	for spec in specs:
		var cell:Vector2i=spec[0]
		var obj:Dictionary=world.state.objects[World.key(cell)]
		expect(not Art.processing_active(obj,float(world.state.time)),"Finished station stops working")
		var before:int=person.inventory.get(spec[2],0)
		for batch in 2:
			app.session.rates[1]=[]
			sequence+=1
			app.session._action(1,sequence,"claim_processing",cell,"")
		expect(int(person.inventory.get(spec[2],0))==before+4,"Two real batches retain original yield")
	app.session._send_snapshot(1)
	await shot("collected")
	print("PROCESSING_MOTION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
