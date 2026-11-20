extends "res://tests/test_spring_garden_scene.gd"
## Windows renderer through the public sign and three actual stations. Only the
## picnic, arrival position and clock are seeded. Crew networking is separate.
const Relay=World.COOKING_RELAY

func own()->Dictionary:
	return app.session.snapshot.get(Relay.VIEW_KEY,{})

func shared()->Dictionary:
	return app.session.snapshot.get(Relay.KEY,{})

func fit_panel()->void:
	if not check(is_instance_valid(app.modal),"Relay panel is open"):return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Relay panel fits")
	var outer:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if outer:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Relay panel fits without outer scrolling")

func open_at(site:Vector2i)->bool:
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	if not await walk_to(site):return false
	await key(KEY_E)
	var expected:="sign"
	for station:String in Relay.STATIONS:
		if Relay.STATIONS[station]==site:expected=station
	var actual:String=app.modal.get_meta("cookrelay_station","-") if is_instance_valid(app.modal) else "-"
	if actual.is_empty():actual="sign"
	return check(actual==expected,"Interaction opens %s at %s; reached %s, focus %s, open %s"%[expected,str(site),str(point()),str(app.view.interaction_focus()),actual])

func exercise()->void:
	world.state.erase(Relay.KEY)
	world.state.players[player_id].erase(Relay.KEY)
	var bag:Dictionary=world.state.players[player_id].inventory.duplicate(true)
	var coins:int=world.state.players[player_id].coins
	app._select_tool("water")
	refresh()
	await settle()
	if not await open_at(Relay.SIGN):return
	fit_panel()
	await capture("01-relay-sign")
	if not await press("CookRelayPractice"):return
	if not check(shared().get("phase")=="run" and shared().get("mode")=="practice" and own().get("joined",false),"Solo practice starts directly"):return
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	app._refresh_hud()
	check(app._cooking_relay_active() and not app.preview_toolbar.visible,"Temporary kitchen actions replace the tool belt")
	var order:Dictionary=Relay.RECIPES.get(shared().get("dish"),{})
	var ingredients:Array=order.get("items",[])
	if not check(ingredients.size()==2,"The next order needs two ingredients"):return
	var different:=""
	for item:String in Relay.ITEMS:
		if item not in ingredients:
			different=item
			break
	if not await open_at(Relay.STATIONS.prep):return
	fit_panel()
	if not await press("CookRelayPrep_"+str(ingredients[0])):return
	if not await press("CookRelayPrep_"+different):return
	check(shared().get("tray",[]).size()==2,"Two practice ingredients are on the prep tray")
	await capture("02-prep-station")
	if not await open_at(Relay.STATIONS.assembly):return
	var plate:=button("CookRelayPlate")
	if plate!=null and not plate.disabled:await press("CookRelayPlate")
	check(not shared().get("plated",false),"Wrong ingredients won't make an incorrect plate")
	if not await press("CookRelayUndo"):return
	check(shared().get("tray",[]).is_empty(),"Undo returns loan ingredients so the shared tray can be reset")
	if not await open_at(Relay.STATIONS.prep):return
	var reversed:=ingredients.duplicate()
	reversed.reverse()
	for item:String in reversed:
		if not await press("CookRelayPrep_"+item):return
	if not await open_at(Relay.STATIONS.assembly):return
	if not await press("CookRelayPlate"):return
	check(shared().get("plated",false),"The correct dish is plated")
	fit_panel()
	await capture("03-assembled-plate")
	if not await open_at(Relay.STATIONS.serve):return
	if not await press("CookRelayServe"):return
	check(int(shared().get("plates",0))==1 and not shared().get("plated",true),"One plate is served and the tray clears")
	check(world.state.players[player_id].inventory==bag and int(world.state.players[player_id].coins)==coins,"Loan ingredients and completed plates never enter normal inventory")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	app._refresh_hud()
	app.toast.hide()
	app.view.camera=(Vector2(Relay.STATIONS.assembly)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()
	await capture("04-kitchen-field")
	check(world.step(241.0,true),"The world clock expires a round")
	refresh()
	await settle()
	check(shared().get("phase")=="results" and own().get("practice",false),"Timer closes practice and persists the keepsake")
	check(not app._cooking_relay_active() and app.preview_toolbar.visible and app.selected=="water","The original watering can returns after practice")
	if not await open_at(Relay.SIGN):return
	fit_panel()
	await capture("05-practice-results")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)

func run()->void:
	create_timer(100.0).timeout.connect(func():check(false,"Native suite watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/cooking-relay")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("cook-relay-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"接力旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=480.0
	var safe:=world.safe_arrival(Vector2(Relay.SIGN)+Vector2(0.5,-0.5),player_id)
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
	print("COOKING_RELAY_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
