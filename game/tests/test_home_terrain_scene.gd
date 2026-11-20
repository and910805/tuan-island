extends SceneTree

const World=preload("res://scripts/world.gd")
const OUTER:=Vector2i(24,31)
const INNER:=Vector2i(25,31)

var app
var world:World
var token:String
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	var resident:Dictionary=world.state.players[token]
	resident.x=cell.x+0.5
	resident.y=cell.y+0.5
	app.session._send_snapshot(1)

func capture(name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var directory:String=app.arg_value("capture-dir","")
	if not directory.is_empty():
		check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Captured "+name)

func run() -> void:
	root.size=Vector2i(1280,800)
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var save:="user://home-terrain-%d.json"%OS.get_process_id()
	if app.session.host(0,"渡口地形試玩",save)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	app.WanganUI.dismiss(app)
	world.state.time=World.Village.DAY*0.42
	stand(Vector2i(24,32))
	await create_timer(0.75).timeout
	await capture("west-before-farming")
	var player:Dictionary=world.state.players[token]
	var start:=Vector2(player.x,player.y)
	for step in 12:world.move_player(token,Vector2.RIGHT,1.0/30.0)
	check(Vector2(player.x,player.y).x>25.0,"Movement crosses the former artwork edge")
	check(start.y==float(player.y),"Crossing does not move the player vertically")
	app.session._send_snapshot(1)
	await create_timer(0.75).timeout
	var before_camera:Vector2=app.view.camera
	var nature:Dictionary=world.state.removed.duplicate(true)
	var terrain:Dictionary=world.state.ground.duplicate(true)
	var seeds:=int(player.inventory.radish_seed)
	for plot in [OUTER,INNER]:
		for tool in ["hoe","seed","water"]:
			app.session.rates[1].clear()
			app.session.perform(tool,plot,"radish" if tool=="seed" else "")
			await process_frame
			var crop:Dictionary=app.session.snapshot.crops.get(World.key(plot),{})
			check(not crop.is_empty(),"Farm action applies at %s"%plot)
			if tool!="hoe":check(crop.get("kind")=="radish","Plant stays on the selected tile")
			if tool=="water":check(crop.get("wet",false),"Watered crop stays on the selected tile")
			check(app.view.camera.is_equal_approx(before_camera),"Farm actions leave the camera fixed")
	check(int(player.inventory.radish_seed)==seeds-2,"The two plots use exactly two seeds")
	check(world.state.removed==nature and world.state.ground==terrain,"Farm overlays preserve the landscape")
	await create_timer(0.35).timeout
	await capture("west-farmed")
	for scene in [["north",Vector2i(40,16)],["east",Vector2i(65,30)],["south-coast",Vector2i(50,54)]]:
		stand(scene[1])
		await create_timer(0.75).timeout
		await capture(scene[0])
	check(app.session.shutdown(),"Save closes successfully")
	var loaded:=World.new()
	check(loaded.load_world(save),"The island reads back successfully")
	for plot in [OUTER,INNER]:
		check(loaded.state.crops.get(World.key(plot),{}).get("wet",false),"Both wet plots persist")
	app.sound.close()
	await create_timer(0.2).timeout
	print("HOME_TERRAIN_SCENE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
