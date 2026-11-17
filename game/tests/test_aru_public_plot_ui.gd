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
	var path:="user://aru-public-bench-test-%d.json"%OS.get_process_id()
	app.session.profile.token="aru-public-bench-test-%d"%OS.get_process_id()
	if app.session.host(0,"渡口島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var tile:=Goals.ARU_PARK_VIEW
	stand(tile)
	expect(not world.act(token,"locked",Goals.ARU_PARK_PLACE,Goals.ARU_PARK_SLOTS.lamp,"lamp").ok,"Friendship gates the shared plot")
	person.bonds={"aru":{"points":24,"talk_day":-1,"gift_day":-1}}
	person.stories.aru=2
	person.inventory.wood=100
	person.inventory.fiber=100
	person.inventory.stone=100
	stand(tile)
	expect(not world.act(token,"early-photo",Goals.ARU_PARK_PHOTO,tile).ok,"Cannot photograph unfinished plot")
	expect(not world.act(token,"ordinary-build", "build",Goals.ARU_PARK_SLOTS.lamp,"lamp").ok,"Ordinary building respects the reserved plot")
	app._interact()
	await process_frame
	expect(button("AruParkPhoto")==null,"Photo option waits for furniture")
	await press("AruParkPlace_long_bench")
	expect(Goals.aru_park_has(app.session.snapshot.objects,"long_bench"),"Public bench is placed from the marker")
	var friend:="aru-second-decorator"
	world.add_player(friend,"訪客")
	var guest:Dictionary=world.state.players[friend]
	guest.bonds={"aru":{"points":24,"talk_day":-1,"gift_day":-1}}
	guest.x=person.x
	guest.y=person.y
	expect(world.act(friend,"shared-lamp",Goals.ARU_PARK_PLACE,Goals.ARU_PARK_SLOTS.lamp,"lamp").ok,"Another islander can place the lamp")
	expect(not world.act(friend,"move-donation","move_object",Goals.ARU_PARK_SLOTS.lamp,"37,34").ok,"A donated lamp cannot be moved")
	expect(not world.act(token,"remove-donation","remove",Goals.ARU_PARK_SLOTS.long_bench).ok,"The donor cannot remove a public bench")
	stand(tile)
	app._interact()
	await process_frame
	await capture("01-public-plot.png")
	await press("AruParkPhoto")
	await process_frame
	var photo:=Tasks.aru_photo_path(app)
	expect(FileAccess.file_exists(photo),"A real PNG is saved on the player device")
	expect(person.get(Goals.ARU_PHOTO_KEY,false) and not guest.has(Goals.ARU_PHOTO_KEY),"Only the photographer earns progress")
	if FileAccess.file_exists(photo):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--capture-dir="):
				var out:=arg.trim_prefix("--capture-dir=").path_join("02-island-photo.png")
				expect(Image.load_from_file(photo).save_png(out)==OK,"Keep the player photo as test evidence")
	stand(tile)
	app._interact()
	await process_frame
	expect(app.modal.find_child("AruAlbumPhoto",true,false)!=null,"The album displays the actual saved image")
	await capture("03-album.png")
	stand(World.bond_place(app.session.snapshot,"aru")[1])
	Tasks.bond_goal(app,"aru",4)
	await process_frame
	await press("BondGoalDo")
	var bird:="keepsake_aru_bird"
	expect(int(person.inventory.get(Goals.keepsake_item(bird),0))==1,"Reporting awards one carved bird")
	stand(Vector2i(38,33))
	expect(world.act(token,"display-bird","build",Vector2i(38,33),bird).ok,"Build one bird from the earned decoration kit")
	stand(Vector2i(38,33))
	await capture("04-wood-bird.png")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the game after decorating")
	expect(Goals.aru_park_has(loaded.state.objects,"long_bench") and Goals.aru_park_has(loaded.state.objects,"lamp"),"Both donations survive reload")
	expect(loaded.state.objects.get(World.key(Vector2i(38,33)),{}).get("type")==bird,"Placed bird survives reload")
	for file:String in [path,path+".bak",path+".tmp",photo]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ARU_PUBLIC_PLOT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
