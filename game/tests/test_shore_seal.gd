extends SceneTree

const World=preload("res://scripts/world.gd")
const Seal=World.Seal
const Almanac=preload("res://scripts/life_ui_almanac.gd")
const TOKEN:="seal-observer"
var checks:=0
var failures:=0

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var world:=World.new()
	world.add_player(TOKEN,"南岸訪客")
	world.add_player("neighbor","鄰居")
	var player:Dictionary=world.state.players[TOKEN]
	var nearby:=Vector2(Seal.SITE)+Vector2(-0.1,-0.65)
	player.x=nearby.x
	player.y=nearby.y
	expect(world.is_land(Seal.SITE) and not world.water(Vector2i(nearby.floor())),"The seal is visible from walkable shore")
	var low_tide:=World.WANGAN_COAST.TIDE_SECONDS*2.25
	world.step(low_tide-float(world.state.time)-1.0,true)
	expect(not world.act(TOKEN,"high-tide",Seal.ACTION,Seal.SITE).ok,"High tide hides the seal")
	world.step(1.0,true)
	expect(Seal.present(float(world.state.time)),"The seal arrives at the exact low-tide boundary")
	expect(world.act(TOKEN,"observe",Seal.ACTION,Seal.SITE).ok and player.seal_seen,"Low tide allows recording the observation")
	expect(not world.act(TOKEN,"duplicate",Seal.ACTION,Seal.SITE).ok,"The encounter is only recorded once")
	expect(not world.state.players.neighbor.has("seal_seen"),"Observations are personal")
	var path:="user://shore-seal-test-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	expect(world.save() and world.load_world(path) and world.state.players[TOKEN].seal_seen,"Seal observation survives save and reload")
	if DisplayServer.get_name()!="headless":await verify_photo(world)
	world.step(World.WANGAN_COAST.TIDE_SECONDS*0.5,true)
	expect(not Seal.present(float(world.state.time)),"The seal leaves at the next high tide")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SHORE_SEAL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func find_button(app,caption:String)->Button:
	if not is_instance_valid(app.modal):return null
	for button:Button in app.modal.find_children("*","Button",true,false):
		if button.text==caption:return button
	return null

func verify_photo(world:World)->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home")
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._refresh_hud()
	await process_frame
	app._interact()
	await create_timer(0.25).timeout
	var capture:=find_button(app,"和胖海豹合照")
	expect(capture!=null,"The coast interaction opens the photo control")
	var path:=Almanac.seal_photo_path(app)
	if capture!=null:
		capture.pressed.emit()
		await create_timer(0.3).timeout
		expect(FileAccess.file_exists(path),"Taking the photo saves a PNG")
		Almanac.seal_menu(app)
		var replay:=find_button(app,"翻看海豹合照")
		expect(replay!=null,"The saved photo appears in the observation card")
		if replay!=null:
			replay.pressed.emit()
			var photo_nodes:Array=app.modal.find_children("*","TextureRect",true,false)
			expect(photo_nodes.any(func(node):return node.texture is ImageTexture),"The album displays the saved image")
		for arg:String in OS.get_cmdline_user_args():
			if arg.begins_with("--seal-preview=") and FileAccess.file_exists(path):
				expect(Image.load_from_file(path).save_png(arg.trim_prefix("--seal-preview="))==OK,"Export the actual photo")
	if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	app.queue_free()
	await process_frame
