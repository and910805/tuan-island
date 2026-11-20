extends "res://tests/test_spring_garden_scene.gd"

const Chase=World.LOST_CHICKS

func own()->Dictionary:
	return app.session.snapshot.get(Chase.VIEW_KEY,{})

func shared()->Dictionary:
	return app.session.snapshot.get(Chase.KEY,{})

func tick(seconds:float)->void:
	check(world.step(seconds,true),"World tick commits")
	refresh()
	await settle()

func walk_route(site:Vector2i)->bool:
	var route:=route_to(site)
	if not check(not route.is_empty(),"Walkable route to %s"%str(site)):return false
	for tile in route.slice(1):
		if not await walk_to(tile):return false
		await tick(0.5)
	return true

func center_camera()->void:
	app.view.camera=(Vector2(Chase.PEN)+Vector2(0,0.45))*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()

func fit_panel()->void:
	if not check(is_instance_valid(app.modal),"Activity panel is open"):return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Activity panel fits")
	var scroller:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroller:
		var bar:=scroller.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Map and buttons are visible without scrolling")

func exercise()->void:
	world.state.erase(Chase.KEY)
	var person:Dictionary=world.state.players[player_id]
	var bag:Dictionary=person.inventory.duplicate(true)
	var coins:int=person.coins
	var original_animal:Dictionary=world.state.animal.duplicate(true)
	app._select_tool("water")
	if not await walk_to(Chase.SIGN):return
	await key(KEY_E)
	if not check(is_instance_valid(app.modal) and app.modal.name=="LostChicksPanel","E opens the activity sign"):return
	fit_panel()
	await capture("01-route-card")
	if not await press("LostChicksStart"):return
	if not check(shared().get("mode")=="solo" and own().get("joined") and shared().get("total")==2,"One player starts the two chick route"):return
	await key(KEY_ESCAPE)
	refresh()
	check(app._lost_chicks_active() and not app.preview_toolbar.visible,"Bucket replaces the tool belt")
	if not await walk_route(Chase.SOLO_SPOTS[0]):return
	if not check(shared().chicks[0].status=="follow","Approaching the chick lures it automatically"):return
	center_camera()
	await capture("02-following")
	if not await walk_route(Chase.PEN):return
	for i in range(5):
		if int(shared().returned)>0:break
		await tick(0.55)
	check(shared().returned==1 and shared().score==2,"First return earns two points")
	if not await walk_route(Chase.SOLO_SPOTS[1]):return
	if not await walk_route(Chase.PEN):return
	for i in range(5):
		if shared().phase=="results":break
		await tick(0.55)
	check(shared().phase=="results" and shared().returned==2 and shared().score==4,"Both chicks safely return and conclude the round")
	check(not app._lost_chicks_active() and app.selected=="water" and app.preview_toolbar.visible,"The original watering can returns")
	check(person.inventory==bag and person.coins==coins and world.state.animal==original_animal,"Activity leaves farm inventory, coins and resident hen intact")
	center_camera()
	await capture("03-all-home")
	if not await walk_to(Chase.SIGN):return
	await key(KEY_E)
	fit_panel()
	await capture("04-results")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)

func run()->void:
	create_timer(80.0).timeout.connect(func():check(false,"Native suite watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/lost-chicks")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("lost-chicks-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"小雞旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=480.0
	var safe:=world.safe_arrival(Vector2(Chase.SIGN)+HALF,player_id)
	world.state.players[player_id].x=safe.x
	world.state.players[player_id].y=safe.y
	app.playing=true
	refresh()
	await settle()
	if app.WanganUI.card_open(app):await key(KEY_E)
	for window_size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=window_size
		size_tag="%dx%d"%[window_size.x,window_size.y]
		await exercise()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("LOST_CHICKS_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
