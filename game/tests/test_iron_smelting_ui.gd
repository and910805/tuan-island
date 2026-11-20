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
	var path:="user://iron-smelting-%d.json"%OS.get_process_id()
	if app.session.host(0,"礦場島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":true}
	person.inventory.reinforced_pick=1
	person.region="mine_4"
	var node:Vector2i=World.MINES.NODES[0]
	stand(node+Vector2i.DOWN)
	app._perform_build_action("pick",node)
	await process_frame
	expect(int(person.inventory.get("iron_ore",0))==1 and int(person.inventory.get("copper_ore",0))==6,"B4 yields iron beside the existing copper")
	await capture("01-mine-iron.png")
	expect(not world.act(token,"repeat-strike","mine_extract",node).ok,"Iron uses the existing node cooldown")
	node=World.MINES.NODES[1]
	stand(node+Vector2i.DOWN)
	app._perform_build_action("pick",node)
	await process_frame
	expect(int(person.inventory.get("iron_ore",0))==2 and int(person.mine_energy)==80,"Two nodes cost normal energy and provide a batch")
	person.region="mine_6"
	node=World.MINES.NODES[0]
	stand(node+Vector2i.DOWN)
	expect(world.act(token,"deep-iron","mine_extract",node).ok and int(person.inventory.get("iron_ore",0))==3 and int(person.inventory.get("ochre_earth",0))==1,"B6 also yields iron, alongside ochre")
	person.region=World.REGIONS.HOME
	person.inventory.stone=25
	person.inventory.copper_ore=5
	person.inventory.charcoal=1
	var furnace:=Vector2i(40,34)
	stand(furnace+Vector2i(1,2))
	# C11: a new small smelter needs the Q03 board flag and a stone workbench (earned path: test_stone_workbench).
	preload("res://tests/stone_station_fixture.gd").install(world,token)
	expect(world.act(token,"build-furnace","build",furnace,"small_smelter").ok,"Build the small smelter")
	stand(furnace+Vector2i(1,2))
	app._interact()
	await process_frame
	await press("ProcessingRecipe_iron_ingot")
	await capture("02-iron-recipe.png")
	await press("ProcessingEnqueue")
	expect(int(person.inventory.get("iron_ore",0))==1 and int(person.inventory.get("charcoal",0))==0,"The recipe consumes two ore and one fuel")
	expect(world.step(60.1,true),"Smelt on the normal world clock")
	stand(furnace+Vector2i(1,2))
	await process_frame
	await press("ProcessingClaim")
	expect(int(person.inventory.get("iron_ingot",0))==2,"Claim two ingots")
	await capture("03-iron-claimed.png")
	var partial:=World.new()
	expect(partial.load_world(path) and int(partial.state.players[token].inventory.get("iron_ingot",0))==2,"Finished ingots survive a reload")
	app._close_modal()
	var ship:=World.SHIPPING.cell_for(world.state)
	stand(ship+Vector2i.DOWN)
	var coins:=int(person.coins)
	var sale:=world.act(token,"ship-iron","ship",ship,JSON.stringify([[["iron_ingot",1]],20]))
	expect(sale.ok and int(person.coins)==coins+20 and int(person.inventory.iron_ingot)==1,"Ship one ingot and receive twenty bells")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path) and int(loaded.state.players[token].inventory.get("iron_ingot",0))==1,"One sold and one retained after reload")
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("IRON_SMELTING_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
