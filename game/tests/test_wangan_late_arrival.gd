extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const Chapter=World.CHAPTER_ONE
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(condition:bool,message:String)->void:
	checks+=1
	if condition:return
	failures+=1
	push_error(message)

func verify_shared_first_shipment()->void:
	var island:=World.new()
	var landing:=World.WANGAN_COAST.FERRY_LANDING
	var farmers:={"first-farmer":Vector2i(45,27),"second-farmer":Vector2i(46,27)}
	for token:String in farmers:
		island.add_player(token,token,landing)
		var actor:Dictionary=island.state.players[token]
		expect(actor.get(Chapter.PERSONAL_START,false) and Chapter.first_crop_step(island.state,token).id=="find",
			"Each player joining before the first shipment has a personal tracker")
		actor.x=45.5
		actor.y=28.5
		var cell:Vector2i=farmers[token]
		for step:Array in [["hoe",""],["seed","radish"],["water",""]]:
			expect(island.act(token,step[0],step[0],cell,step[1]).ok,"Each farmer works their own plot")
	island.step(110.0,true)
	var bin:=World.SHIPPING.cell_for(island.state)
	var cargo:=JSON.stringify([[["radish",1]],int(World.CROPS.radish.price)])
	for token:String in farmers:
		expect(island.act(token,"harvest","harvest",farmers[token]).ok,"Both players get their own harvest")
		var actor:Dictionary=island.state.players[token]
		actor.x=bin.x+0.5
		actor.y=bin.y+1.5
		expect(Chapter.first_crop_step(island.state,token).id=="ship","Both players have the shipment prompt before the chapter advances")
	expect(island.act("first-farmer","ship","ship",bin,cargo).ok and island.state.chapter_one.shipped,"The first shipment advances the island")
	expect(Chapter.first_crop_step(island.state,"first-farmer").is_empty(),"The first shipper's personal tutorial ends")
	expect(Chapter.first_crop_step(island.state,"second-farmer").get("id")=="ship","Clearing the shared harvest records does not clear the second player's guidance")
	expect(island.act("second-farmer","ship","ship",bin,cargo).ok and Chapter.first_crop_step(island.state,"second-farmer").is_empty(),
		"The second shipment completes that player's own lesson")

func run()->void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	app.session.profile.token=Crypto.new().generate_random_bytes(24).hex_encode()
	var path:="user://wangan-late-arrival-%d.json"%OS.get_process_id()
	var seeded:=World.new()
	seeded.add_player("on-island","老島民")
	seeded.state.board=true
	seeded.state.chapter_one.shipped=true
	seeded.state.chapter_one.watered=true
	var shared:Dictionary=seeded.state.chapter_one.duplicate(true)
	seeded.save_path=path
	expect(seeded.save(),"Start from an existing island past its first shipment")
	if app.session.host(0,"新島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	expect(app.WanganUI.card_open(app) and Vector2(person.x,person.y)==World.WANGAN_COAST.FERRY_LANDING,"Late newcomer gets the dock introduction")
	expect(Chapter.first_crop_step(app.session.snapshot,app.session.own_id).id=="find","The client gets the newcomer tracker despite the completed shared shipment")
	expect(Chapter.first_crop_step(world.state,"on-island").is_empty(),"The existing resident's tutorial does not restart")
	expect(not app.session.public_state().players[app.session.own_id].has(Chapter.PERSONAL_START),"The late tutorial flag is private")
	app.WanganUI.dismiss(app)
	await create_timer(0.25).timeout
	var hint:=app.hud.find_child("TrackerNext",true,false) as Button
	expect(hint!=null and "種田指引" in hint.text,"The HUD prioritizes the late newcomer's next step")
	if hint:hint.pressed.emit()
	expect(is_instance_valid(app.modal),"The tracker button opens the personal farming guide")
	app._close_modal()
	var bin:=World.SHIPPING.cell_for(world.state)
	var cargo:=JSON.stringify([[["radish",1]],int(World.CROPS.radish.price)])
	person.x=bin.x+0.5
	person.y=bin.y+1.5
	person.inventory.radish=1
	expect(world.act(token,"purchased-produce","ship",bin,cargo).ok and person.get(Chapter.PERSONAL_START,false),"Shipping produce with no earlier harvest leaves onboarding active")
	person.x=45.5
	person.y=28.5
	var cell:=Vector2i(45,27)
	var phases:=[["hoe","","sow"],["seed","radish","water"],["water","","wait"]]
	for stage:Array in phases:
		expect(world.act(token,str(stage[0]),stage[0],cell,stage[1]).ok,"Tutorial uses the normal "+str(stage[0])+" action")
		app.session._send_snapshot(1)
		expect(Chapter.first_crop_step(app.session.snapshot,app.session.own_id).id==str(stage[2]),"Tracker advances to "+str(stage[2]))
	world.step(110.0,true)
	expect(world.act(token,"harvest","harvest",cell).ok,"The new resident harvests their own crop")
	person.x=bin.x+0.5
	person.y=bin.y+1.5
	app.session._send_snapshot(1)
	expect(Chapter.first_crop_step(app.session.snapshot,app.session.own_id).id=="ship","The client points to the shipping bin")
	var loaded:=World.new()
	expect(loaded.load_world(path) and Chapter.first_crop_step(loaded.state,token).id=="ship","A mid-tutorial save retains the personal shipment step")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("late-arrival-shipping.png"))==OK,"Capture late arrival's shipping step")
	app.session.perform("ship",bin,cargo)
	expect(not person.has(Chapter.PERSONAL_START) and Chapter.first_crop_step(app.session.snapshot,app.session.own_id).is_empty(),
		"Shipping a personally harvested crop completes only that player's tutorial")
	expect(world.state.chapter_one==shared,"The established island's shared chapter flags and records stay intact")
	expect(loaded.load_world(path) and not loaded.state.players[token].has(Chapter.PERSONAL_START),"Completion survives reloading")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	verify_shared_first_shipment()
	print("WANGAN_LATE_ARRIVAL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
