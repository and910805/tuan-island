extends "res://tests/test_spring_garden_scene.gd"

const Stroll=World.LANTERN_STROLL

func own()->Dictionary:
	return app.session.snapshot.get(Stroll.VIEW_KEY,{})

func shared()->Dictionary:
	return app.session.snapshot.get(Stroll.KEY,{})

func open_at(id:String)->bool:
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	var spot:Vector2i=Stroll.SIGN if id=="sign" else Stroll.SITES[id].cell
	if not await walk_to(spot):return false
	await key(KEY_E)
	return check(is_instance_valid(app.modal) and app.modal.name=="LanternStrollPanel" and app.modal.get_meta("stroll_site")==id,
		"Interaction opens %s (focus %s)"%[id,app.view.interaction_focus()])

func fit()->void:
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Panel fits window")
	var scroller:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroller:
		var bar:=scroller.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Route and choices fit without scrolling")

func exercise()->void:
	world.state.erase(Stroll.KEY)
	var player:Dictionary=world.state.players[player_id]
	player.erase(Stroll.KEY)
	var bag:Dictionary=player.inventory.duplicate(true)
	var coins:int=player.coins
	if not await open_at("sign"):return
	fit()
	await capture("01-route")
	if not await press("StrollStart"):return
	if not check(own().get("joined",false) and shared().get("phase")=="run","Board lends a lantern"):return
	if not await press("StrollCompanion"):return
	check(own().get("companion",false),"Choose a guide as a solo companion")
	await key(KEY_ESCAPE)
	for target:Vector2i in [Stroll.SIGN+Vector2i.UP,Stroll.SIGN+Vector2i(-1,-1),Stroll.SIGN+Vector2i(-2,-1)]:
		if not await walk_to(target):return
		await create_timer(0.13).timeout
	check(app.view.stroll_companion.is_finite(),"The guide appears behind the walking player")
	await capture("02-lantern-walk")
	var names:=["safe","growth","friends"]
	for i in Stroll.ORDER.size():
		var id:String=Stroll.ORDER[i]
		if not await open_at(id):return
		fit()
		if i==0:await capture("03-blessing")
		if not await press("StrollWish_"+names[i]):return
		check(own().stamps.size()==i+1 and shared().blessings[id]==names[i],"Personal stamp and visible preset blessing")
		check(button("StrollWish_"+names[i])==null,"Already stamped view hides repeated action")
	check(own().tickets==1 and player.inventory==bag and player.coins==coins,"Three authentic visits produce one ticket with no tool or coin changes")
	if not await open_at("sign"):return
	fit()
	if not await press("StrollDim"):return
	check(app.view.stroll_dim and app.sound.stroll_dim,"Dimmed lantern setting")
	var config:=ConfigFile.new()
	check(config.load(app.settings_path)==OK and config.get_value("comfort","stroll_dim",false),"Dimmed lighting persists locally")
	if not await press("StrollRedeem"):return
	check(own().tickets==0 and int(player.inventory.get(Stroll.PRIZE,0))==int(bag.get(Stroll.PRIZE,0))+1,"One ticket trades for existing buildable decoration")
	if not await press("StrollLeave"):return
	check(not own().joined and own().stamps.size()==3,"Returning lantern keeps all marks this round")
	if not await press("StrollJoin"):return
	check(own().joined and own().stamps.size()==3 and own().tickets==0,"Rejoin restores the personal route")
	check(world.step(Stroll.DURATION+0.1,true),"Activity timer commits final state")
	refresh()
	await settle()
	check(shared().phase=="results" and not own().joined,"Timeout returns the lantern")
	await capture("04-results")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	app._set_stroll_dim(false)

func run()->void:
	create_timer(125.0).timeout.connect(func():check(false,"Native suite watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/lantern-stroll")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native Windows rendering"):finish();return
	path=OS.get_environment("TEMP").path_join("lantern-stroll-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	app.settings_path=path+".cfg"
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"提燈旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	var spawn:=world.safe_arrival(Vector2(Stroll.SIGN)+HALF,player_id)
	world.state.players[player_id].x=spawn.x
	world.state.players[player_id].y=spawn.y
	app.playing=true
	refresh()
	await settle()
	if app.WanganUI.card_open(app):await key(KEY_E)
	for window_size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		world.state.time=1160.0 if window_size.x>1024 else 1120.0
		root.size=window_size
		size_tag="%dx%d"%[window_size.x,window_size.y]
		await exercise()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):app.session.shutdown()
	for suffix in ["",".bak",".writer-lock",".cfg"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("LANTERN_STROLL_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
