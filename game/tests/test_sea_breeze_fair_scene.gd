extends "res://tests/test_spring_garden_scene.gd"
## Exercise the announcement board, live market and sample counter in the native
## Windows renderer. The picnic, summer clock and initial arrival are seeded.
const Fair=World.SEA_BREEZE_FAIR
const Market=preload("res://scripts/market_stall.gd")
const SUMMER_DAY:=14

func own()->Dictionary:
	return app.session.snapshot.get(Fair.VIEW_KEY,{})

func fit_fair()->void:
	if not check(is_instance_valid(app.modal),"Fair interface is open"):return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Fair interface fits")
	var outer:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if outer:
		var scroll:=outer.get_v_scroll_bar()
		check(scroll.max_value<=scroll.page+1.0,"Fair content fits without scrolling")

func board_open()->bool:
	if not await walk_to(Fair.BOARD):return false
	await key(KEY_E)
	return await press("SeaFairBoardLink")

func exercise()->void:
	world.state.players[player_id].erase(Fair.KEY)
	refresh()
	await settle()
	if not await board_open():return
	fit_fair()
	await capture("01-board-signup")
	if not await press("SeaFairStart"):return
	if not check(own().get("phase")=="visit","Signup opens the tasting shift"):return
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	var stall:=Market.active_cell(app.session.snapshot)
	if not check(stall!=Market.NO_CELL,"The event uses the real market location"):return
	if not await walk_to(stall):return
	app.toast.hide()
	app.view.camera=(Vector2(stall)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()
	await capture("02-sea-breeze-stall")
	await key(KEY_E)
	if not await press("SeaFairMarketLink"):return
	fit_fair()
	var portrait:=app.modal.find_child("SeaFairGuestPortrait",true,false) as TextureRect
	check(portrait!=null and portrait.visible and portrait.texture!=null,"Current guest has a readable portrait")
	var first_portrait:Texture2D=portrait.texture if portrait!=null else null
	var dishes:=Fair.DISHES.keys()
	var offset:=posmod(SUMMER_DAY,dishes.size())
	var first:=str(dishes[offset])
	var other:=str(dishes[(offset+1)%dishes.size()])
	if not await press("SeaFairServe_"+other):return
	check(int(own().get("served",-1))==0,"Wrong sample leaves the same guest and progress")
	if not await press("SeaFairServe_"+first):return
	check(int(own().get("served",-1))==1,"The matching sample serves the guest")
	check(portrait!=null and portrait.texture!=null and portrait.texture!=first_portrait,"Next guest has a different portrait")
	await capture("03-sample-counter")
	for index in range(1,dishes.size()):
		if not await press("SeaFairServe_"+str(dishes[(offset+index)%dishes.size()])):return
		check(int(own().get("served",-1))==index+1,"Served the next guest")
	check(own().get("phase")=="return","Full counter sends the player back to the board")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	if not await board_open():return
	if not await press("SeaFairFinish"):return
	check(own().get("completed",false) and not own().get("active",true),"Finished fair saves the keepsake")
	fit_fair()
	await capture("04-summer-keepsake")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)

func run()->void:
	create_timer(85.0).timeout.connect(func():check(false,"Native test watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/sea-breeze-fair")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("sea-fair-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"海風旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=SUMMER_DAY*World.WEATHER.DAY_SECONDS+480.0
	var safe:=world.safe_arrival(Vector2(Fair.BOARD)+Vector2(0.5,1.5),player_id)
	world.state.players[player_id].x=safe.x
	world.state.players[player_id].y=safe.y
	app.playing=true
	refresh()
	await settle()
	if app.WanganUI.card_open(app):await key(KEY_E)
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
	print("SEA_BREEZE_FAIR_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
