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
	AudioServer.set_bus_mute(0,true)
	var path:="user://mianmian-comfort-%d.json"%OS.get_process_id()
	if app.session.host(0,"牧場島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.picnic=true
	var sheep:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	stand(sheep)
	expect(not world.act(token,"locked",Goals.SHEEP_SHELTER_ACTION,sheep,"shelter").ok,"Friendship gates this project")
	person.bonds={"mianmian":{"points":6,"talk_day":-1,"gift_day":-1}}
	person.inventory.wood=4
	person.inventory.fiber=0
	stand(sheep)
	app._interact()
	await process_frame
	await press("SheepCorner")
	expect(button("SheepComfort_mat")!=null and button("SheepComfort_mat").disabled,"Mat needs fiber")
	await capture("01-comfort-project.png")
	await press("SheepComfort_shelter")
	expect(int(person.inventory.wood)==0 and app.session.snapshot.own_sheep_corner==1,"Shelter charges exactly four wood")
	expect(not world.act(token,"repeat",Goals.SHEEP_SHELTER_ACTION,sheep,"shelter").ok,"Cannot pay for the shelter twice")
	person.inventory.fiber=3
	stand(sheep)
	app._interact()
	await press("SheepCorner")
	await press("SheepComfort_mat")
	expect(int(person.inventory.fiber)==0 and app.session.snapshot.own_sheep_corner==3,"Mat charges exactly three fiber")
	expect(app.session.snapshot.sheep_comfort_fixtures==3 and not app.session.snapshot.players[app.session.own_id].has(Goals.SHEEP_SHELTER_KEY),"Fixtures are shared and personal progress is private")
	expect(not world.act(token,"early-play",Goals.SHEEP_TOY_ACTION,sheep,"ball").ok,"Toys require reporting")
	stand(World.bond_place(app.session.snapshot,"mianmian")[1])
	Tasks.bond_goal(app,"mianmian",2)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.mianmian["2"].state=="done","Reporting completes the event")
	stand(sheep)
	app._interact()
	await press("SheepCorner")
	expect(button("SheepToy_doll")!=null,"Reward offers a doll and a cloth ball")
	await capture("02-toy-kit.png")
	var ranch:Dictionary=world.state.get("livestock",{}).duplicate(true)
	await press("SheepToy_ball")
	expect(world.state.get(Goals.SHEEP_PLAY_KEY,{}).get("toy")=="ball","The sheep plays with the selected toy even while muted")
	expect(world.state.get("livestock",{})==ranch,"Play does not alter care state")
	expect(not world.act(token,"cooldown",Goals.SHEEP_TOY_ACTION,sheep,"doll").ok,"Cannot restart the animation while playing")
	stand(sheep+Vector2i(-3,0))
	await capture("03-sheep-in-world.png")
	world.state.time+=Goals.SHEEP_PLAY_SECONDS+0.1
	stand(sheep)
	app._interact()
	await press("SheepCorner")
	await press("SheepToy_doll")
	expect(world.state.get(Goals.SHEEP_PLAY_KEY,{}).get("toy")=="doll","Doll also plays after the cooldown")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	if loaded.state.players.has(token):
		expect(loaded.state.players[token].get(Goals.SHEEP_SHELTER_KEY)==3 and Goals.done(loaded.state.players[token],"mianmian").has(2),"Both fixtures and the toy unlock persist")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MIANMIAN_COMFORT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
