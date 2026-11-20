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
var wide:=false

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
		await create_timer(0.24).timeout
		await RenderingServer.frame_post_draw
		if wide:file_name=file_name.replace(".png","-wide.png")
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func project_modal() -> Node:
	return app.modal if is_instance_valid(app.modal) and app.modal.name=="SheepComfortProject" else null

func status_text() -> String:
	var modal:=project_modal()
	var label:=modal.find_child("SheepComfortStatus",true,false) as Label if modal!=null else null
	return label.text if label!=null else ""

func expect_unclipped(id:String) -> void:
	var node:=button(id)
	if node==null:return
	var parent:=node.get_parent()
	while parent!=null and not parent is ScrollContainer:parent=parent.get_parent()
	if parent==null:return
	var scroll:=parent as ScrollContainer
	scroll.ensure_control_visible(node)
	await process_frame
	await process_frame
	var view:=scroll.get_global_rect().grow(1.0)
	var rect:=node.get_global_rect()
	expect(view.encloses(rect),"Button not clipped in modal scroll at %s: %s"%[str(root.size),id])

func run() -> void:
	wide="--wide" in OS.get_cmdline_user_args()
	root.size=Vector2i(1280,800) if wide else Vector2i(1024,640)
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
	var modal:=project_modal()
	expect(modal!=null,"Root modal is SheepComfortProject")
	expect(modal!=null and modal.find_child("SheepComfortCard_shelter",true,false)!=null and modal.find_child("SheepComfortCard_mat",true,false)!=null,"Both material rows are shown")
	expect(button("SheepComfort_mat")!=null and button("SheepComfort_mat").disabled,"Mat needs fiber")
	await expect_unclipped("SheepComfort_shelter")
	await expect_unclipped("SheepComfort_mat")
	await capture("01-comfort-project.png")
	var before_status:=status_text()
	await press("SheepComfort_shelter")
	expect(int(person.inventory.wood)==0 and app.session.snapshot.own_sheep_corner==1,"Shelter charges exactly four wood")
	expect(project_modal()==modal and is_instance_valid(modal),"Building keeps the same modal instance")
	expect(modal!=null and modal.find_child("SheepComfortCard_shelter",true,false)!=null and modal.find_child("SheepComfortCard_mat",true,false)!=null,"Both material rows remain after the first part")
	expect(status_text()!="" and status_text()!=before_status,"Status updates inline after the shelter")
	expect(not world.act(token,"repeat",Goals.SHEEP_SHELTER_ACTION,sheep,"shelter").ok,"Cannot pay for the shelter twice")
	person.inventory.fiber=3
	stand(sheep)
	await process_frame
	await process_frame
	expect(project_modal()==modal,"Snapshot after fixture inventory injection keeps the modal")
	expect(button("SheepComfort_mat")!=null and not button("SheepComfort_mat").disabled,"Mat enables inline once fiber arrives")
	await expect_unclipped("SheepComfort_mat")
	before_status=status_text()
	await press("SheepComfort_mat")
	expect(project_modal()==modal,"The final part keeps the same project open")
	expect(status_text()!=before_status and "棉棉" in status_text(),"Finished project tells the player where to report")
	expect(button("SheepComfort_mat")!=null and button("SheepComfort_mat").disabled,"Completed mat cannot be built again")
	var locked_toy:=button("SheepToy_ball")
	expect(locked_toy==null or not locked_toy.is_visible_in_tree(),"Toys stay hidden until reporting")
	await capture("04-ready-to-report.png")
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
	expect(button("SheepToy_doll")!=null and button("SheepToy_doll").is_visible_in_tree(),"Reward offers a doll and a cloth ball")
	await expect_unclipped("SheepToy_ball")
	await expect_unclipped("SheepToy_doll")
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
	expect(root.size==(Vector2i(1280,800) if wide else Vector2i(1024,640)),"Final viewport size matches the requested layout")
	expect(app.session.snapshot.own_sheep_corner==3 and app.session.snapshot.sheep_comfort_fixtures==3,"Final state keeps both fixtures")
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
