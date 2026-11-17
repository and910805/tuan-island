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
	var path:="user://aru-bench-%d.json"%OS.get_process_id()
	if app.session.host(0,"渡口島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var aru:=World.Village.resident_cell(world.state,"aru")
	stand(aru)
	expect(not world.act(token,"locked",Goals.ARU_REST_ACTION,aru).ok,"Cannot start before trust")
	person.bonds={"aru":{"points":14,"talk_day":-1,"gift_day":-1}}
	stand(aru)
	app._interact()
	await press("AruRest")
	await capture("01-rest.png")
	expect(person.has(Goals.ARU_REST_KEY) and app.session.snapshot.aru_bench_open,"Sitting opens the invitation")
	var friend:="friend-at-aru"
	world.add_player(friend,"來訪的朋友")
	var guest:Dictionary=world.state.players[friend]
	guest.x=person.x
	guest.y=person.y
	expect(world.act(friend,"join",Goals.ARU_REST_ACTION,aru).ok and not guest.has(Goals.ARU_REST_KEY),"Friend opts in without gaining the quest prerequisite")
	await press("AruRise")
	Tasks.bond_goal(app,"aru",3)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.aru["3"].state=="done","Report unlocks engraving")
	expect(World.Village.unlocked(person,"sign"),"Report unlocks the sign pattern via relationship")
	var mark:=Vector2i(38,32)
	person.inventory.wood=100
	person.inventory.fiber=100
	stand(mark+Vector2i(0,1))
	expect(world.act(token,"build-sign","build",mark,"sign").ok,"Normal building accepts the unlocked sign")
	stand(mark)
	app._interact()
	await process_frame
	var field:=app.modal.find_child("AruInscription",true,false) as LineEdit
	expect(field!=null,"Owner can enter text after interacting in the world")
	if field!=null:field.text="風鈴小屋"
	await press("AruSaveInscription")
	expect(app.session.snapshot.objects.get(World.key(mark),{}).get("inscription")=="風鈴小屋","Carving is visible in world data")
	app._interact()
	await process_frame
	await capture("02-inscription.png")
	guest.x=person.x
	guest.y=person.y
	expect(not world.act(friend,"overwrite",Goals.INSCRIBE_ACTION,mark,"路過").ok,"Visitors cannot overwrite someone else's furniture")
	expect(not world.act(token,"bad",Goals.INSCRIBE_ACTION,mark,"錯誤\n換行").ok,"Invalid characters are rejected")
	var bench:=Vector2i(37,32)
	person.stories.aru=2
	stand(bench+Vector2i(0,1))
	expect(world.act(token,"build-bench","build",bench,"long_bench").ok,"Build the regular two-person bench")
	stand(bench)
	app._interact()
	await process_frame
	field=app.modal.find_child("AruInscription",true,false) as LineEdit
	expect(field!=null,"Two-person bench is interactable")
	if field!=null:field.text="留位給你"
	await press("AruSaveInscription")
	expect(world.state.objects.get(World.key(bench),{}).get("inscription")=="留位給你","Bench carving persists separately from the sign")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload old and new records together")
	expect(loaded.state.objects.get(World.key(mark),{}).get("inscription")=="風鈴小屋" and Goals.done(loaded.state.players[token],"aru").has(3),"Carving and reward persist")
	expect(loaded.state.objects.get(World.key(bench),{}).get("inscription")=="留位給你","Bench inscription also survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ARU_BENCH_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
