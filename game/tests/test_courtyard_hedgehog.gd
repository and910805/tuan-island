extends SceneTree

const World=preload("res://scripts/world.gd")
const TOKEN:="hedgehog-observer"
const FIELD:=Vector2i(40,35)
var checks:=0
var failures:=0

func expect(result:bool,description:String)->void:
	checks+=1
	if not result:
		failures+=1
		push_error(description)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var world:=World.new()
	world.add_player(TOKEN,"庭院觀察員")
	world.add_player("neighbor","鄰居")
	var player:Dictionary=world.state.players[TOKEN]
	var site:=World.Hedgehog.site(world.state)
	player.x=FIELD.x+0.5
	player.y=FIELD.y+0.5
	expect(world.act(TOKEN,"too-far","hedgehog_leave_food",site).ok==false,"Leaving food requires being at the dish")
	expect(world.act(TOKEN,"hoe","hoe",FIELD).ok,"Prepare a field")
	expect(world.act(TOKEN,"seed","seed",FIELD,"radish").ok,"Plant an ordinary radish")
	expect(world.act(TOKEN,"water","water",FIELD).ok,"Water the crop")
	world.step(float(World.CROPS.radish.time),true)
	expect(world.act(TOKEN,"harvest","harvest",FIELD).ok and int(player.inventory.radish)==1,"Earn a radish with normal farming")
	player.x=site.x+0.5
	player.y=site.y+0.5
	expect(world.act(TOKEN,"leave","hedgehog_leave_food",site).ok and int(player.inventory.radish)==0,"Place one ordinary radish")
	expect(not world.act(TOKEN,"leave-twice","hedgehog_leave_food",site).ok,"Duplicate food is refused")
	expect(not world.act(TOKEN,"too-early","hedgehog_observe",site).ok,"Cannot observe immediately")
	expect(World.Hedgehog.phase(world.state.players.neighbor,float(world.state.time))=="empty","Another player has their own wildlife visit")
	var path:="user://hedgehog-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	expect(world.save() and world.load_world(path),"The invitation survives reload")
	player=world.state.players[TOKEN]
	var opening:=World.WEATHER.DAY_SECONDS+360.0
	world.step(opening-float(world.state.time)-1.0,true)
	expect(World.Hedgehog.phase(player,float(world.state.time))=="waiting","Still waiting before 06:00")
	world.step(1.0,true)
	expect(World.Hedgehog.phase(player,float(world.state.time))=="visiting","The hedgehog arrives at 06:00")
	if DisplayServer.get_name()!="headless":await verify_scene(world)
	expect(world.act(TOKEN,"observed","hedgehog_observe",site).ok,"Record one observation")
	expect(not world.act(TOKEN,"observe-again","hedgehog_observe",site).ok,"The same visit is only recorded once")
	expect(world.save() and world.load_world(path),"The observation survives reload")
	player=world.state.players[TOKEN]
	expect(World.Hedgehog.phase(player,float(world.state.time))=="visited","After reload the observed visitor remains until closing")
	world.step(300.0,true)
	expect(World.Hedgehog.phase(player,float(world.state.time))=="empty","At 11:00 the animal goes back to the woods")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COURTYARD_HEDGEHOG_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_scene(world:World)->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home")
	app.session.snapshot.players[TOKEN].y+=1.2
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._refresh_hud()
	await process_frame
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--hedgehog-preview="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--hedgehog-preview="))==OK,"Capture the courtyard visit")
	app._interact()
	await create_timer(0.27).timeout
	var buttons:Array=app.modal.find_children("*","Button",true,false) if is_instance_valid(app.modal) else []
	expect(buttons.any(func(node):return node.text=="靜靜觀察"),"The ordinary interaction shows the wildlife action")
	app.queue_free()
	await process_frame
