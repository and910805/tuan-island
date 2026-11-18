extends SceneTree
## Native renderer capture. Uses real Session actions; only crop maturity is preset.
const World=preload("res://scripts/world.gd")
const Feedback=preload("res://scripts/tool_action_feedback.gd")
var app
var directory:=""
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
	root.size=Vector2i(1280,800) if app.arg_value("qa-size","")=="1280" else Vector2i(1024,640)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="farm-body-motion-qa"
	assert(app.session.host(0,"農事動畫測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	var plot:=Vector2i(38,34)
	var person:Dictionary=world.state.players[token]
	var direction:String=app.arg_value("qa-facing","right")
	var facing:Vector2i={"right":Vector2i.RIGHT,"left":Vector2i.LEFT,"up":Vector2i.UP,"down":Vector2i.DOWN}.get(direction,Vector2i.RIGHT)
	var standing:=Vector2(plot)+Vector2(0.5,0.5)-Vector2(facing)
	person.x=standing.x
	person.y=standing.y
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	app.view.set_process(false)
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	var camera_before:Vector2=app.view.camera
	var ground_before:Dictionary=world.state.ground.duplicate(true)
	var position_before:=Vector2(person.x,person.y)
	var sequence:=0
	var records:Array=[]
	var seed_before:int=person.inventory.get("radish_seed",0)
	for step in [["hoe",""],["seed","radish"],["water",""],["harvest",""]]:
		var tool:String=step[0]
		if tool=="harvest":world.state.crops[World.key(plot)].growth=float(World.CROPS.radish.time)
		if tool=="water" and app.arg_value("qa-grown","")=="true":world.state.crops[World.key(plot)].growth=float(World.CROPS.radish.time)*0.7
		app.selected=tool
		app.view.selected=tool
		app.view.elapsed+=1.0
		app.session.rates[1]=[]
		sequence+=1
		app.session._action(1,sequence,tool,plot,step[1])
		app.session._send_snapshot(1)
		var started:float=app.view.elapsed
		var state_before:Dictionary=world.state.duplicate(true)
		var presses:={}
		var seed_contact_counts:={}
		expect(app.view.tool_action_plan(app.session.own_id).get("tool","")==tool,"Confirmed action starts: "+tool)
		expect(app.view.tool_action_plan(app.session.own_id).get("facing")==facing,"Action faces target: "+tool)
		for frame in 12:
			app.view.elapsed=started+Feedback.DURATION*float(frame)/12.0
			app.view.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var quiet:bool=app.view.reduced_motion or app.view.photograph_mode
			presses[app.view.tool_feedback.crop_press(plot,app.view.elapsed,quiet)]=true
			if tool=="seed":seed_contact_counts[Feedback.seed_contacts(float(frame)/12.0,quiet).size()]=true
			expect(world.state==state_before,"Drawing cannot change any saved world field: "+tool)
			var path:="%s_%02d.png"%[tool,frame]
			expect(root.get_texture().get_image().save_png(directory.path_join(path))==OK,"Capture "+path)
			records.append({"file":path,"pose":app.view.tool_action_plan(app.session.own_id)})
		expect(app.view.camera==camera_before,"Camera stays fixed: "+tool)
		expect(Vector2(person.x,person.y)==position_before and world.state.ground==ground_before,"World coordinates stay fixed: "+tool)
		if tool=="water":
			var quiet:bool=app.view.reduced_motion or app.view.photograph_mode
			expect(presses.size()==1 if quiet else presses.size()>=3,"Watered plant settles only with normal motion")
		if tool=="seed":
			var quiet:bool=app.view.reduced_motion or app.view.photograph_mode
			expect(int(person.inventory.get("radish_seed",0))==seed_before-1,"Three visual kernels consume exactly one seed item")
			expect(seed_contact_counts.size()==1 if quiet else seed_contact_counts.size()>=3,"Separate seed contacts appear only in normal motion")
	expect(world.state.crops.get(World.key(plot),{}).get("kind","")=="" and int(person.inventory.get("radish",0))>0,"Harvest reaches inventory and leaves reusable soil")
	expect(world.save(),"Farm result saves to the isolated QA world")
	var loaded=World.new()
	expect(loaded.load_world(directory.path_join("world.json")),"Farm result reloads through normal save validation")
	expect(loaded.state.players[token].inventory==person.inventory,"Inventory survives reload unchanged")
	expect(loaded.state.ground==world.state.ground,"Soil survives reload unchanged")
	# JSON represents all numeric fields as floats on reload; compare both sides
	# after the same serialization, including owner, care and harvest metadata.
	var persisted_crops=JSON.parse_string(JSON.stringify(world.state.crops))
	expect(loaded.state.crops==persisted_crops,"Every crop field survives the JSON save round trip")
	var record:=FileAccess.open(directory.path_join("frames.json"),FileAccess.WRITE)
	record.store_string(JSON.stringify(records,"\t"))
	print("FARM_BODY_CAPTURE checks=%d failures=%d frames=%d"%[checks,failures,records.size()])
	quit(int(failures>0))
