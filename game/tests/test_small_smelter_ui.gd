extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

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
	var path:="user://small-smelter-%d.json"%OS.get_process_id()
	if app.session.host(0,"熔爐島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var kind:=World.INDUSTRY.SMELTER
	var site:=Vector2i(40,34)
	var corner:=site+Vector2i.ONE
	person.inventory.merge({"stone":25,"copper_ore":25,"iron_ore":20,"charcoal":12},true)
	# C11: a new small smelter needs the Q03 board flag and a stone workbench (earned path: test_stone_workbench).
	preload("res://tests/stone_station_fixture.gd").install(world,token)
	stand(site+Vector2i(0,2))
	world.state.objects[World.key(corner)]={"type":"lamp","owner":token,"items":{}}
	expect(not world.act(token,"blocked","build",site,kind).ok and int(person.inventory.stone)==25,"One occupied corner prevents construction without debit")
	world.state.objects.erase(World.key(corner))
	app._perform_build_action("build",site,kind)
	await process_frame
	expect(int(person.inventory.stone)==0 and int(person.inventory.copper_ore)==20,"One furnace costs exactly 25 stone and five ore")
	for offset:Vector2i in World.INDUSTRY.SMELTER_CELLS:
		expect(world.blocked(site+offset) and World.station_anchor(world.state.objects,site+offset)==site,"Every tile blocks walking and points to the same furnace")
	stand(corner+Vector2i.DOWN)
	await create_timer(0.3).timeout
	await capture("01-furnace-footprint.png")
	app._interact()
	await process_frame
	expect(button("ProcessingRecipe_glass")==null,"The dedicated furnace exposes metal recipes")
	await press("ProcessingRecipe_copper_ingot")
	await press("ProcessingEnqueue")
	await press("ProcessingRecipe_iron_ingot")
	await press("ProcessingEnqueue")
	var obj:Dictionary=world.state.objects[World.key(site)]
	expect(obj.get("processing",{}).get("active",{}).get("kind")=="copper_ingot" and obj.processing.waiting[0].kind=="iron_ingot","Regular UI queues both metals through the far corner")
	for index in range(8):
		expect(world.act(token,"enqueue-%d"%index,"queue_processing",corner,"iron_ingot").ok,"Fill the shared ten-entry queue")
	expect(not world.act(token,"extra-queue","queue_processing",corner,"copper_ingot").ok,"An eleventh entry is rejected")
	expect(not world.act(token,"busy-remove","remove",corner).ok,"Queued work protects the whole footprint from removal")
	stand(corner+Vector2i.DOWN)
	await capture("02-metal-queue.png")
	var checkpoint:=World.new()
	expect(checkpoint.load_world(path) and checkpoint.state.objects[World.key(site)].processing.waiting.size()==9,"All ten queue entries survive reload")
	expect(world.step(600.0,true),"Advance the game clock through the full queue")
	for index in range(10):
		expect(world.act(token,"claim-%d"%index,"claim_processing",corner).ok,"Claim one complete batch")
	expect(int(person.inventory.copper_ingot)==2 and int(person.inventory.iron_ingot)==18,"Completed batches return the correct ingots")
	app._close_modal()
	var bp:=World.BLUEPRINT_DESIGN
	var snapshot:Dictionary=app.session.public_state()
	expect(not bp.capture(snapshot,app.session.own_id,Rect2i(corner,Vector2i.ONE),"半座爐",World.BUILD,World.NAMES).ok,"Partial footprint cannot be captured")
	var captured:=bp.capture(snapshot,app.session.own_id,Rect2i(site,Vector2i(2,2)),"小熔爐",World.BUILD,World.NAMES)
	expect(captured.ok and captured.blueprint.pieces.size()==1,"The whole furnace becomes one blueprint piece")
	var rotated:=bp.rotate(captured.blueprint,1,World.BUILD,World.NAMES)
	expect(rotated.ok and rotated.blueprint==captured.blueprint,"A rotated square footprint keeps its canonical anchor")
	stand(corner+Vector2i.DOWN)
	expect(world.act(token,"remove-furnace","remove",corner).ok,"Dismantle the furnace from the far corner")
	for offset:Vector2i in World.INDUSTRY.SMELTER_CELLS:
		expect(not world.state.objects.has(World.key(site+offset)),"Dismantle clears each footprint tile")
	expect(int(person.inventory.stone)==25 and int(person.inventory.copper_ore)==23,"Removal refunds the construction materials once")
	var quote:=world.quote_blueprint(token,captured.blueprint,site,1)
	expect(quote.ok and world.apply_blueprint(token,"d".repeat(32),captured.blueprint,site,1,quote.hash).ok,"Build the full furnace from a rotated blueprint")
	var moved:=Vector2i(42,35)
	expect(world.act(token,"move-furnace","move_object",corner,World.key(moved)).ok,"Moving from a corner moves all four tiles")
	for offset:Vector2i in World.INDUSTRY.SMELTER_CELLS:
		expect(world.blocked(moved+offset) and World.station_anchor(world.state.objects,moved+offset)==moved,"The moved footprint still resolves to one furnace")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects.get(World.key(moved+Vector2i.ONE),{}).get("smelter_part")==3,"The four-tile factory survives restart")
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("SMALL_SMELTER_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
