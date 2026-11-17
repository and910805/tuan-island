extends SceneTree
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/processing_queue_ui.gd")
const CELL:=Vector2i(40,35)
var app
var world
var person:Dictionary
var sequence:=0
var directory:=""
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func act(action:String)->void:
	app.session.rates[1]=[]
	sequence+=1
	app.session._action(1,sequence,action,CELL,"")
	app.session._send_snapshot(1)
func shot(name:String,wanted:String)->void:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
	var title:=UI.world_status(app.session.snapshot.objects[World.key(CELL)],float(world.state.time))
	expect(title.contains(wanted),"World hint: "+wanted)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1024,640)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="processing-advice-qa"
	assert(app.session.host(0,"自動加工測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	world=app.session.world
	person=world.state.players[app.session.peers[1]]
	person.x=41.5
	person.y=36.5
	person.inventory.wood=80
	world.state.removed[World.key(CELL)]=true
	world.state.objects[World.key(CELL)]={"owner":app.session.peers[1],"type":"sawmill","items":{},"input_wood":0}
	act("toggle_auto_processing")
	await create_timer(0.3).timeout
	await shot("needs_wood","待補木材")
	for batch in 16:
		act("feed_processing")
		if batch==0:await shot("fed","待開始")
		expect(world.step(0.1,true),"Start automatic batch")
		app.session._send_snapshot(1)
		if batch==0:await shot("working","加工中")
		expect(world.step(12.2,true),"Finish automatic batch")
		app.session._send_snapshot(1)
		expect(int(world.state.objects[World.key(CELL)].items.get("plank",0))==(batch+1)*2,"Actual output accumulates")
	act("feed_processing")
	await shot("full","庫滿，先領取")
	var before:int=world.state.objects[World.key(CELL)].input_wood
	expect(world.step(1.0,true),"Attempt automatic tick while full")
	expect(world.state.objects[World.key(CELL)].input_wood==before and not world.state.objects[World.key(CELL)].has("job"),"Full buffer does not consume queued input")
	app.industry_ui.device(app,CELL)
	await create_timer(0.3).timeout
	var label:Label=app.modal.find_child("ProcessingAutoStatus",true,false)
	expect(is_instance_valid(label) and label.text.contains("先領取"),"Page and world prompt agree on next action")
	expect(str(app.modal.get_meta("processing_queue").refs.header_title.text).contains("產物庫已滿"),"Full buffer header never claims processing is running")
	await shot("full_panel","庫滿，先領取")
	app._close_modal()
	var planks:int=person.inventory.get("plank",0)
	act("collect_processing_output")
	expect(int(person.inventory.get("plank",0))==planks+32,"Collecting transfers exactly 16 real batches")
	await shot("collected","待開始")
	expect(world.step(0.1,true),"Automatic processing resumes")
	app.session._send_snapshot(1)
	await shot("resumed","加工中")
	# Edge fixture: an already-finished batch cannot enter a buffer filled meanwhile.
	var station:Dictionary=world.state.objects[World.key(CELL)]
	station.items.plank=32
	station.job.ready=float(world.state.time)
	app.session._send_snapshot(1)
	await shot("finished_but_full","庫滿，先領取")
	app.industry_ui.device(app,CELL)
	await create_timer(0.3).timeout
	label=app.modal.find_child("ProcessingAutoStatus",true,false)
	expect(is_instance_valid(label) and label.text.contains("先領取"),"Completed batch blocked by full output uses the same actionable warning")
	expect(str(app.modal.get_meta("processing_queue").refs.header_title.text).contains("產物庫已滿"),"Blocked completed batch header agrees with warning")
	await shot("finished_but_full_panel","庫滿，先領取")
	print("PROCESSING_ADVICE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
