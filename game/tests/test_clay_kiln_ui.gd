extends SceneTree

const World:=preload("res://scripts/world.gd")
const Tea:=World.TEA_CERAMICS

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://clay-kiln-%d.json"%OS.get_process_id()
	if app.session.host(0,"鶯歌陶工",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	world.state.board=true
	world.state.picnic=true
	person.inventory.merge({"stone":60,"charcoal":2},true)
	stand(Tea.RECEIVER+Vector2i.LEFT)
	expect(world.act(token,"tea-letter","tea_intro",Tea.RECEIVER).ok,"Receive the Yingge introduction")
	person.region=Tea.YINGGE
	person.travel_book.visited[Tea.YINGGE]=true
	stand(Tea.POTTER+Vector2i.RIGHT)
	expect(world.act(token,"tea-potter","tea_potter",Tea.POTTER).ok,"Yingge pottery workshop supplies the first clay")
	stand(Tea.CLAY+Vector2i.RIGHT)
	for count in range(15):
		expect(world.act(token,"clay-%d"%count,"tea_clay",Tea.CLAY).ok,"Acquire clay using the normal exchange")
		world.step(Tea.COOLDOWN+0.01,true)
	expect(person.inventory.clay==17 and person.inventory.stone==30,"Yingge supplies enough clay for the kiln and two batches")
	var kind:=World.INDUSTRY.CLAY_KILN
	var site:=Vector2i(40,34)
	var corner:=site+Vector2i.ONE
	var key:=World.key(site)
	person.region=World.REGIONS.HOME
	stand(corner+Vector2i.DOWN)
	world.state.objects[World.key(corner)]={"type":"lamp","owner":token,"items":{}}
	expect(not world.act(token,"busy-corner","build",site,kind).ok and person.inventory.clay==17,"Occupied corner refuses construction without consuming clay")
	world.state.objects.erase(World.key(corner))
	app._perform_build_action("build",site,kind)
	await process_frame
	expect(person.inventory.stone==0 and person.inventory.clay==7,"Kiln costs thirty stone and ten clay")
	if not world.state.objects.has(key):
		quit(1)
		return
	for offset:Vector2i in World.INDUSTRY.SQUARE_CELLS:
		expect(world.blocked(site+offset) and World.station_anchor(world.state.objects,site+offset)==site,"Four solid cells point to one kiln")
	stand(corner+Vector2i.DOWN)
	await create_timer(2.0).timeout
	await capture("clay-kiln-field.png")
	app._interact()
	await process_frame
	expect(button("ProcessingRecipe_flower_pot")!=null and button("ProcessingRecipe_fired_brick")!=null,"Both ceramic recipes are visible at the kiln")
	await press("ProcessingRecipe_fired_brick")
	await press("ProcessingEnqueue")
	await press("ProcessingRecipe_flower_pot")
	await press("ProcessingEnqueue")
	expect(person.inventory.clay==0 and person.inventory.charcoal==0,"Both batches spend the listed clay and fuel")
	var checkpoint:=World.new()
	expect(checkpoint.load_world(path) and checkpoint.state.objects[key].processing.waiting.size()==1,"Waiting pot order survives a reload")
	await capture("clay-kiln-queue.png")
	app._close_modal()
	expect(not world.act(token,"busy-kiln","remove",corner).ok,"A hot kiln is protected from dismantling")
	expect(world.step(135.1,true),"Advance the shared kiln clock")
	stand(corner+Vector2i.DOWN)
	app._interact()
	await process_frame
	await press("ProcessingClaim")
	await press("ProcessingClaim")
	expect(person.inventory.fired_brick==2 and person.inventory.flower_pot==1,"Ready batches return two bricks and one pot")
	app._close_modal()
	var pot:=site+Vector2i(2,0)
	stand(pot+Vector2i.RIGHT)
	expect(world.act(token,"place-pot","build",pot,"flower_pot").ok and person.inventory.flower_pot==0,
		"The fired pot is usable as a decoration")
	var design:=World.BLUEPRINT_DESIGN
	var snapshot:={"objects":world.state.objects}
	expect(not design.capture(snapshot,token,Rect2i(site,Vector2i.ONE),"半座陶窯",World.BUILD,World.NAMES).ok,
		"A partial kiln is rejected during blueprint capture")
	var captured:=design.capture(snapshot,token,Rect2i(site,Vector2i(2,2)),"陶窯",World.BUILD,World.NAMES)
	expect(captured.ok and captured.blueprint.pieces.size()==1,"A blueprint captures all four cells as one kiln")
	stand(corner+Vector2i.DOWN)
	expect(world.act(token,"remove-kiln","remove",corner).ok and person.inventory.stone==30 and person.inventory.clay==10,"Remove the whole kiln and refund exactly one build")
	var shipping:=World.SHIPPING.cell_for(world.state)
	stand(shipping+Vector2i.LEFT)
	var coins:=int(person.coins)
	expect(world.act(token,"ship-brick","ship",shipping,JSON.stringify([[["fired_brick",1]],16])).ok and person.inventory.fired_brick==1 and person.coins==coins+16,"Bricks can be shipped for sixteen bells apiece")
	expect(app.session.shutdown(),"Save and close the world")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.state.objects.has(key) and int(loaded.state.players[token].inventory.fired_brick)==1,"Final save retains the shipped count and removed kiln")
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CLAY_KILN_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
