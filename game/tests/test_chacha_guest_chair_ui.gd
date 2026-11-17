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

func contains_text(value:String) -> bool:
	for node:Node in app.modal.find_children("*","Label",true,false):
		if node.text.contains(value) and node.is_visible_in_tree():return true
	return false

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://chacha-chair-%d.json"%OS.get_process_id()
	if app.session.host(0,"茶亭島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var host:=World.TEA_CERAMICS.TEA_NPC
	person.region=World.TEA_CERAMICS.MAOKONG
	stand(host)
	expect(not world.act(token,"locked",Goals.TEA_CHAIR_ACTION,Goals.TEA_CHAIRS.coast.cell,"coast").ok,"Not available before friendship")
	person.bonds={"chacha":{"points":24,"talk_day":-1,"gift_day":-1}}
	stand(host)
	expect(not world.act(token,"wrong-spot",Goals.TEA_CHAIR_ACTION,host,"coast").ok,"Requires an actual chair space")
	app._interact()
	await process_frame
	await press("BondOpen")
	await press("ChachaGuestSeat")
	expect(button("ChachaChair_wood")!=null and button("ChachaChair_coast")!=null,"Two non-teahouse finishes can be chosen")
	await capture("01-seat-options.png")
	await press("ChachaChair_coast")
	expect(app.session.snapshot.own_chacha_tea_chair=="coast","Choice is recorded for its contributor")
	expect(app.session.snapshot.chacha_tea_chairs=={"coast":true} and not app.session.snapshot.players[app.session.own_id].has(Goals.TEA_CHAIR_KEY),"Visitors see the seat without seeing personal records")
	expect(not world.act(token,"repeat",Goals.TEA_CHAIR_ACTION,Goals.TEA_CHAIRS.wood.cell,"wood").ok,"One seat per resident")

	var helper:="chacha-chair-guest"
	world.add_player(helper,"另一個島民")
	var friend_record:Dictionary=world.state.players[helper]
	friend_record.region=World.TEA_CERAMICS.MAOKONG
	friend_record.x=host.x+0.5
	friend_record.y=host.y+0.5
	friend_record.bonds={"chacha":{"points":24,"talk_day":-1,"gift_day":-1}}
	expect(world.act(helper,"wood-choice",Goals.TEA_CHAIR_ACTION,Goals.TEA_CHAIRS.wood.cell,"wood").ok,"A second participant can put down the other finish")
	stand(host)
	await capture("02-both-seats.png")
	expect(app.session.snapshot.chacha_tea_chairs.size()==2,"Both seats are shared")
	Tasks.bond_goal(app,"chacha",4)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.chacha["4"].state=="done","Report unlocks the handwritten menu")
	app._interact()
	await process_frame
	await press("BondOpen")
	await press("ChachaMenu")
	expect(contains_text("淺焙茶") and contains_text("深焙茶") and contains_text("茶香布丁"),"The handwritten tea menu has three items")
	await capture("03-handwritten-menu.png")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(loaded.state.players[token].get(Goals.TEA_CHAIR_KEY)=="coast" and loaded.state.players[helper].get(Goals.TEA_CHAIR_KEY)=="wood","Both placings persist")
	expect(Goals.done(loaded.state.players[token],"chacha").has(4),"Tea menu unlock persists")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CHACHA_GUEST_CHAIR_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
