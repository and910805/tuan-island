extends "res://tests/test_spring_garden_scene.gd"
## Native board and route through normal interaction keys. The winter-night
## clock, completed picnic and starting position are seeded for this fixture.
const Night=World.WARM_LANTERN_NIGHT
const WINTER_DAY:=42
const BLESSINGS:={"grove":"home","lane":"harvest","harbor":"friends"}

func own()->Dictionary:
	return app.session.snapshot.get(Night.VIEW_KEY,{})

func shared()->Dictionary:
	return app.session.snapshot.get(Night.KEY,{})

func fit_panel()->void:
	if not check(is_instance_valid(app.modal),"Festival panel is open"):return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Festival panel fits the window")
	var shell:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if shell:
		var scroll:=shell.get_v_scroll_bar()
		check(scroll.max_value<=scroll.page+1.0,"Festival panel fits without outer scrolling")

func board_open()->bool:
	if not await walk_to(Night.BOARD):return false
	await key(KEY_E)
	return await press("WarmNightBoardLink")

func warm_pixels(before:Image,after:Image,area:Rect2i)->int:
	var count:=0
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var a:=before.get_pixel(x,y)
			var b:=after.get_pixel(x,y)
			if b.r-a.r>0.06 and b.r-a.r>b.b-a.b+0.02:count+=1
	return count

func exercise()->void:
	world.state.erase(Night.KEY)
	world.state.players[player_id].erase(Night.KEY)
	var bag:Dictionary=world.state.players[player_id].inventory.duplicate(true)
	var coins:int=world.state.players[player_id].coins
	refresh()
	await settle()
	if not await board_open():return
	fit_panel()
	await capture("01-festival-board")
	if not await press("WarmNightStart"):return
	if not check(shared().get("phase")=="lighting" and own().get("joined",false),"The board begins a shared lantern round"):return
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	for station:String in Night.STATIONS:
		var site:Vector2i=Night.STATIONS[station].cell
		var photo_station:=station=="grove"
		var approach:=site+Vector2i.UP if photo_station else site
		if not await walk_to(approach):return
		var before:Image
		if photo_station:
			app.view.set_process(false)
			app.view.camera=(Vector2(site)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
			app.toast.hide()
			app.view.queue_redraw()
			await capture("02-lamp-unlit")
			before=Image.load_from_file(output.path_join(size_tag+"_02-lamp-unlit.png"))
		await key(KEY_E)
		fit_panel()
		if photo_station:await capture("03-choose-blessing")
		if not await press("WarmNightWish_"+str(BLESSINGS[station])):return
		if not check(shared().get("lamps",{}).get(station)==BLESSINGS[station],"Chosen blessing is visible in the shared round"):return
		var chosen:=app.modal.find_child("WarmNightChosen",true,false) as Label
		check(chosen!=null and chosen.visible and chosen.text.contains(Night.WISHES[BLESSINGS[station]]),"Read the committed blessing at the lamp")
		check(app.sound.pending_action=="warm_lantern" or app.sound.cue_kind=="warm_lantern","Lighting dispatches the dedicated sound cue")
		if is_instance_valid(app.modal):await key(KEY_ESCAPE)
		if photo_station:
			app.toast.hide()
			app.view.queue_redraw()
			await capture("04-lamp-lit")
			var after:=Image.load_from_file(output.path_join(size_tag+"_04-lamp-lit.png"))
			var point_at:=Vector2i(Vector2(root.size)*0.5)
			var sample:=Rect2i(point_at-Vector2i(85,8),Vector2i(170,68))
			check(warm_pixels(before,after,sample)>80,"Lighting visibly warms the terrain around the lantern")
			app.view.set_process(true)
	if not await board_open():return
	if not await press("WarmNightFinish"):return
	check(shared().get("phase")=="celebrated" and own().get("completed",false),"First completion saves a personal keepsake")
	check(shared().get("lamps",{})==BLESSINGS,"Completed festival preserves all three blessings")
	check(world.state.players[player_id].inventory==bag and int(world.state.players[player_id].coins)==coins,"The festival uses no backpack items or coins")
	fit_panel()
	await capture("05-lantern-keepsake")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)

func run()->void:
	create_timer(85.0).timeout.connect(func():check(false,"Native suite watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/warm-lantern-night")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("warm-lantern-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"暖燈旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=WINTER_DAY*World.WEATHER.DAY_SECONDS+1208.0
	var safe:=world.safe_arrival(Vector2(Night.BOARD)+Vector2(0.5,1.5),player_id)
	world.state.players[player_id].x=safe.x
	world.state.players[player_id].y=safe.y
	app.playing=true
	refresh()
	await settle()
	if app.WanganUI.card_open(app):await key(KEY_E)
	var cue:AudioStreamWAV=app.sound.sounds.get("warm_lantern")
	check(cue!=null and cue.get_length()>0.4 and cue.data!=app.sound.sounds.action.data,"Lantern uses a distinct audio cue")
	app.sound.master_volume=0.6
	app.sound.volume=0.4
	for size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		size_tag="%dx%d"%[size.x,size.y]
		await exercise()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WARM_LANTERN_NIGHT_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
